param(
    [int] $ProcessId = 0,
    [int] $ThreadId = 0,
    [ValidateRange(1, 16)]
    [int] $ThreadRank = 1,
    [ValidateRange(2, 120)]
    [int] $Seconds = 8,
    [ValidateRange(1, 100)]
    [int] $IntervalMilliseconds = 2,
    [ValidateSet(16, 64, 256, 1024, 4096, 16384, 65536)]
    [int] $BucketBytes = 4096
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ProcessId -eq 0) {
    $game = Get-Process moderngekko-run -ErrorAction SilentlyContinue |
        Sort-Object StartTime -Descending |
        Select-Object -First 1
    if (-not $game) {
        throw 'No running moderngekko-run process was found.'
    }
    $ProcessId = $game.Id
}

if (-not ('LiveThreadSampler' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public sealed class LiveThreadSampler : IDisposable
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenThread(uint access, bool inheritHandle, uint threadId);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SuspendThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetThreadContext(IntPtr thread, IntPtr context);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    private const uint ThreadAccess = 0x0002 | 0x0008 | 0x0040;
    private const uint ContextFull = 0x0010000B;
    private readonly IntPtr _thread;
    private readonly IntPtr _allocation;
    private readonly IntPtr _context;

    public LiveThreadSampler(int threadId)
    {
        _thread = OpenThread(ThreadAccess, false, unchecked((uint)threadId));
        if (_thread == IntPtr.Zero)
            throw new InvalidOperationException("OpenThread failed: " + Marshal.GetLastWin32Error());
        _allocation = Marshal.AllocHGlobal(1232 + 15);
        _context = new IntPtr((_allocation.ToInt64() + 15) & ~15L);
    }

    public ulong ReadInstructionPointer()
    {
        if (SuspendThread(_thread) == uint.MaxValue)
            throw new InvalidOperationException("SuspendThread failed: " + Marshal.GetLastWin32Error());
        try
        {
            Marshal.WriteInt32(_context, 48, unchecked((int)ContextFull));
            if (!GetThreadContext(_thread, _context))
                throw new InvalidOperationException("GetThreadContext failed: " + Marshal.GetLastWin32Error());
            return unchecked((ulong)Marshal.ReadInt64(_context, 248));
        }
        finally
        {
            ResumeThread(_thread);
        }
    }

    public void Dispose()
    {
        if (_thread != IntPtr.Zero)
            CloseHandle(_thread);
        if (_allocation != IntPtr.Zero)
            Marshal.FreeHGlobal(_allocation);
    }
}
'@
}

function Get-ThreadCpuSnapshot {
    param([System.Diagnostics.Process] $Process)

    $result = @{}
    $Process.Refresh()
    foreach ($thread in $Process.Threads) {
        try {
            $result[$thread.Id] = $thread.TotalProcessorTime.TotalSeconds
        } catch {
        }
    }
    return $result
}

$process = Get-Process -Id $ProcessId
$before = Get-ThreadCpuSnapshot $process
$processCpuBefore = $process.TotalProcessorTime.TotalSeconds
$cpuWatch = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds 1
$cpuWatch.Stop()
$process.Refresh()
$after = Get-ThreadCpuSnapshot $process
$processCpuAfter = $process.TotalProcessorTime.TotalSeconds

$threadUsage = foreach ($entry in $after.GetEnumerator()) {
    if ($before.ContainsKey($entry.Key)) {
        [pscustomobject]@{
            ThreadId = [int]$entry.Key
            CPU = [double]$entry.Value - [double]$before[$entry.Key]
        }
    }
}
$hottest = if ($ThreadId -ne 0) {
    $threadUsage | Where-Object ThreadId -eq $ThreadId | Select-Object -First 1
} else {
    $threadUsage | Sort-Object CPU -Descending |
        Select-Object -Skip ($ThreadRank - 1) -First 1
}
if (-not $hottest) {
    throw "Thread $ThreadId was not found in process $ProcessId."
}

$modules = foreach ($module in $process.Modules) {
    [pscustomobject]@{
        Name = $module.ModuleName
        Path = $module.FileName
        Start = [uint64]$module.BaseAddress.ToInt64()
        End = [uint64]($module.BaseAddress.ToInt64() + $module.ModuleMemorySize)
    }
}

$sampleCount = 0
$samples = @{}
$sampler = [LiveThreadSampler]::new($hottest.ThreadId)
$profileWatch = [Diagnostics.Stopwatch]::StartNew()
try {
    while ($profileWatch.Elapsed.TotalSeconds -lt $Seconds) {
        $rip = $sampler.ReadInstructionPointer()
        $module = $null
        foreach ($candidate in $modules) {
            if ($rip -ge $candidate.Start -and $rip -lt $candidate.End) {
                $module = $candidate
                break
            }
        }
        if ($module) {
            $rva = $rip - $module.Start
            $bucket = [uint64]([math]::Floor($rva / $BucketBytes) * $BucketBytes)
            $key = '{0}|{1:X}' -f $module.Name, $bucket
        } else {
            $bucket = [uint64]([math]::Floor($rip / $BucketBytes) * $BucketBytes)
            $key = '<dynamic>|{0:X}' -f $bucket
        }
        if ($samples.ContainsKey($key)) {
            $samples[$key]++
        } else {
            $samples[$key] = 1
        }
        $sampleCount++
        [Threading.Thread]::Sleep($IntervalMilliseconds)
    }
} finally {
    $profileWatch.Stop()
    $sampler.Dispose()
}

$rows = foreach ($entry in $samples.GetEnumerator()) {
    $parts = $entry.Key.Split('|')
    [pscustomobject]@{
        Module = $parts[0]
        RVABucket = '0x' + $parts[1]
        Samples = $entry.Value
        Percent = [math]::Round(100.0 * $entry.Value / $sampleCount, 2)
    }
}
$rows = $rows | Sort-Object Samples -Descending

$logDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$output = Join-Path $logDirectory ("live-profile-{0}-pid{1}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $ProcessId)
$rows | Export-Csv -LiteralPath $output -NoTypeInformation

[pscustomobject]@{
    ProcessId = $ProcessId
    ProcessCPUCoreEquivalent = [math]::Round(($processCpuAfter - $processCpuBefore) / $cpuWatch.Elapsed.TotalSeconds, 2)
    HottestThread = $hottest.ThreadId
    HottestThreadCoreEquivalent = [math]::Round($hottest.CPU / $cpuWatch.Elapsed.TotalSeconds, 2)
    Samples = $sampleCount
    Profile = $output
} | Format-List
$rows | Select-Object -First 30 | Format-Table -AutoSize
