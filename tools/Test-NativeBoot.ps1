param(
    [ValidateRange(1, 300)]
    [int] $Seconds = 15,
    [ValidateSet('Null', 'D3D', 'Vulkan', 'OGL')]
    [string] $Graphics = 'Null',
    [string] $GameRoot = 'C:\SMGRecomp\data\RMGE01',
    [string] $Modules = 'C:\SMGRecomp\modules',
    [string] $UserDirectory = 'C:\SMGRecomp\user\RMGE01',
    [switch] $TraceVideo,
    [Nullable[uint32]] $IdlePC = $null,
    [ValidateRange(0.0, 1.0)]
    [double] $MaximumFallbackRatio = 0.05,
    [uint64] $MinimumGuestTicks = 10000000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $root 'build\upstream\moderngekko\moderngekko-run.exe'
$moduleInfo = Join-Path $root 'build\upstream\moderngekko\moderngekko-module-info.exe'
$activeModule = Join-Path $Modules 'RMGE01\active-module.txt'
$logs = Join-Path $root 'logs'

& (Join-Path $PSScriptRoot 'Assert-GameRevision.ps1') -GameRoot $GameRoot

foreach ($required in @($runner, $moduleInfo, $activeModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required build artifact is missing: $required"
    }
}

$module = (Get-Content -LiteralPath $activeModule -Raw).Trim()
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw "Active module is missing: $module"
}

& $moduleInfo $module 'RMGE01'
if ($LASTEXITCODE -ne 0) {
    throw "Module validation failed with exit code $LASTEXITCODE"
}

New-Item -ItemType Directory -Force -Path $logs, $UserDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logs "native-boot-$stamp.stdout.log"
$stderr = Join-Path $logs "native-boot-$stamp.stderr.log"
$arguments = @(
    '--game', $GameRoot,
    '--module', $module,
    '--user-dir', $UserDirectory,
    '--graphics', $Graphics,
    '--headless',
    '--stop-after-ms', ($Seconds * 1000)
)
if ($null -ne $IdlePC) {
    $arguments += @('--idle-pc', ('0x{0:X8}' -f $IdlePC))
}
if ($TraceVideo) {
    $arguments += '--trace-video'
}

$process = Start-Process `
    -FilePath $runner `
    -ArgumentList $arguments `
    -WorkingDirectory $root `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$timeoutMilliseconds = ($Seconds + 30) * 1000
if (-not $process.WaitForExit($timeoutMilliseconds)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "Native boot did not stop within $($Seconds + 30) seconds"
}
$process.WaitForExit()
$process.Refresh()
$exitCode = $process.ExitCode
if ($null -ne $exitCode -and $exitCode -ne 0) {
    throw "Native boot failed with exit code $exitCode. See $stderr"
}

$runtimeOutput = Get-Content -LiteralPath $stderr -Raw
$stats = [regex]::Match(
    $runtimeOutput,
    'shutdown: native=(\d+) fallback=(\d+) native_exc=(\d+) hook_fb=(\d+) smc_failed=(\d+) verifications=(\d+) reverify_events=(\d+) charged_cycles=(\d+)'
)
if (-not $stats.Success) {
    throw "Static-recomp shutdown statistics were not emitted. See $stderr"
}

$native = [uint64]$stats.Groups[1].Value
$fallback = [uint64]$stats.Groups[2].Value
$smcFailed = [uint64]$stats.Groups[5].Value
$chargedCycles = [uint64]$stats.Groups[8].Value
if ($native -eq 0) {
    throw 'The module did not execute any native dispatches.'
}
$fallbackRatio = [double]$fallback / [double]$native
if ($fallbackRatio -gt $MaximumFallbackRatio) {
    throw ('Interpreter fallback ratio {0:P2} exceeded the {1:P2} limit.' -f $fallbackRatio, $MaximumFallbackRatio)
}
if ($smcFailed -ne 0) {
    throw "Self-modifying-code verification failures: $smcFailed"
}

$tickMatches = [regex]::Matches($runtimeOutput, 'ticks=(\d+)')
$guestTicks = $chargedCycles
if ($tickMatches.Count -ne 0) {
    $progressTicks = ($tickMatches | ForEach-Object { [uint64]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum
    if ($progressTicks -gt $guestTicks) {
        $guestTicks = $progressTicks
    }
}
if ($guestTicks -lt $MinimumGuestTicks) {
    throw "Guest timing only reached $guestTicks ticks; expected at least $MinimumGuestTicks."
}

$idleLoops = [regex]::Matches($runtimeOutput, 'detected idle loop: pc=0x[0-9A-Fa-f]+').Count
if ($null -eq $IdlePC -and $idleLoops -eq 0) {
    throw "Automatic idle-loop detection did not identify any polling loops. See $stderr"
}

Write-Host ('Native boot passed: {0} dispatches, {1:P2} fallback ratio, {2} guest ticks, {3} idle loops, {4} SMC failures.' -f $native, $fallbackRatio, $guestTicks, $idleLoops, $smcFailed)
Write-Host "Logs: $stdout"
Write-Host "      $stderr"
