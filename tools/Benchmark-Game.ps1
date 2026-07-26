param(
    [ValidateRange(5, 300)]
    [int] $Seconds = 20,
    [ValidateSet('D3D', 'Vulkan', 'OGL', 'Null')]
    [string[]] $Graphics = @('D3D'),
    [ValidateSet('static', 'jit', 'cached-interpreter', 'interpreter')]
    [string[]] $CpuCore = @('static', 'jit'),
    [string] $GameRoot = 'C:\SMGRecomp\data\RMGE01',
    [string] $Modules = 'C:\SMGRecomp\modules',
    [string] $UserDirectory = 'C:\SMGRecomp\user\RMGE01',
    [string] $LoadState = '',
    [switch] $PureStatic,
    [switch] $Headless
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $root 'build\upstream\moderngekko\moderngekko-run.exe'
$activeModule = Join-Path $Modules 'RMGE01\active-module.txt'
$logs = Join-Path $root 'logs'

& (Join-Path $PSScriptRoot 'Assert-GameRevision.ps1') -GameRoot $GameRoot
foreach ($required in @($runner, $activeModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required artifact is missing: $required"
    }
}
if ($LoadState -and -not (Test-Path -LiteralPath $LoadState -PathType Leaf)) {
    throw "Savestate is missing: $LoadState"
}

$module = (Get-Content -LiteralPath $activeModule -Raw).Trim()
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw "Active module is missing: $module"
}

New-Item -ItemType Directory -Force -Path $logs, $UserDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = foreach ($backend in $Graphics) {
    foreach ($core in $CpuCore) {
        $name = "benchmark-$stamp-$($core)-$($backend.ToLowerInvariant())"
        $stdout = Join-Path $logs "$name.stdout.log"
        $stderr = Join-Path $logs "$name.stderr.log"
        $arguments = @(
            '--game', $GameRoot,
            '--module', $module,
            '--user-dir', $UserDirectory,
            '--graphics', $backend,
            '--cpu-core', $core,
            '--no-save-settings',
            '--trace-video',
            '--stop-after-ms', ($Seconds * 1000)
        )
        if ($Headless) {
            $arguments += '--headless'
        }
        if ($LoadState) {
            $arguments += @('--load-state', $LoadState)
        }
        if ($PureStatic -and $core -eq 'static') {
            $arguments += '--pure-static'
        }

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $runner -ArgumentList $arguments -WorkingDirectory $root `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $timeout = ($Seconds + 60) * 1000
        if (-not $process.WaitForExit($timeout)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "$core/$backend did not stop within $($Seconds + 60) seconds"
        }
        $process.WaitForExit()
        $watch.Stop()
        $process.Refresh()
        $exitCode = $process.ExitCode
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            throw "$core/$backend failed with exit code $exitCode. See $stderr"
        }

        $output = Get-Content -LiteralPath $stderr -Raw
        $video = [regex]::Match($output, 'fps=([0-9.]+) vps=([0-9.]+) speed=([0-9.]+)')
        $videoCounts = [regex]::Match(
            $output,
            'summary: before_frames=(\d+) xfb_copies=(\d+) vi_fields=(\d+).*present_completions=(\d+)'
        )
        $native = [regex]::Match(
            $output,
            'shutdown: native=(\d+) fallback=(\d+) native_exc=(\d+) hook_fb=(\d+).*jit_slices=(\d+)'
        )
        $charged = [regex]::Match($output, 'charged_cycles=(\d+)')
        $wallSeconds = $watch.Elapsed.TotalSeconds
        # The timed-stop clock starts after Runtime::Create. Process wall time also includes
        # module validation, Dolphin initialization, and shutdown, so video cadence must use
        # the requested runtime interval rather than total process lifetime.
        $measurementSeconds = [double]$Seconds
        $nativeDispatches = if ($native.Success) { [uint64]$native.Groups[1].Value } else { 0 }
        $hookFallbacks = if ($native.Success) { [uint64]$native.Groups[4].Value } else { 0 }
        $chargedCycles = if ($charged.Success) { [uint64]$charged.Groups[1].Value } else { 0 }
        $frameCount = if ($videoCounts.Success) { [uint64]$videoCounts.Groups[2].Value } else { 0 }
        $fieldCount = if ($videoCounts.Success) { [uint64]$videoCounts.Groups[3].Value } else { 0 }
        $measuredFps = if ($video.Success) {
            [double]$video.Groups[1].Value
        } elseif ($frameCount -gt 0) {
            $frameCount / $measurementSeconds
        } else { 0 }
        $measuredVps = if ($video.Success) {
            [double]$video.Groups[2].Value
        } elseif ($fieldCount -gt 0) {
            $fieldCount / $measurementSeconds
        } else { 0 }
        $hostCpuSeconds = 0.0
        try {
            $hostCpuSeconds = ([TimeSpan]$process.TotalProcessorTime).TotalSeconds
        } catch {
            $hostCpuSeconds = 0.0
        }

        [pscustomobject]@{
            Core = $core
            Graphics = $backend
            FPS = [math]::Round($measuredFps, 2)
            VPS = [math]::Round($measuredVps, 2)
            SpeedPercent = [math]::Round(($measuredVps / 60.0) * 100, 1)
            HostCPUSeconds = [math]::Round($hostCpuSeconds, 2)
            WallSeconds = [math]::Round($wallSeconds, 2)
            NativeDispatchesPerSecond = [math]::Round($nativeDispatches / $measurementSeconds)
            GuestCyclesPerSecond = [math]::Round($chargedCycles / $measurementSeconds)
            HookFallbacksPerSecond = [math]::Round($hookFallbacks / $measurementSeconds)
            Log = $stderr
        }
    }
}

$csv = Join-Path $logs "benchmark-$stamp.csv"
$results | Export-Csv -LiteralPath $csv -NoTypeInformation
$results | Format-Table Core, Graphics, FPS, VPS, SpeedPercent, HostCPUSeconds, `
    NativeDispatchesPerSecond, GuestCyclesPerSecond, HookFallbacksPerSecond -AutoSize
Write-Host "Results: $csv"
