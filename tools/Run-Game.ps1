param(
    [string] $GameRoot = 'C:\SMGRecomp\data\RMGE01',
    [string] $Modules = 'C:\SMGRecomp\modules',
    [string] $UserDirectory = 'C:\SMGRecomp\user\RMGE01',
    [ValidateSet('Vulkan', 'D3D', 'OGL', 'Null')]
    [string] $Graphics = 'Vulkan',
    [ValidateSet('static', 'jit', 'cached-interpreter', 'interpreter')]
    [string] $CpuCore = 'static',
    [switch] $Headless,
    [switch] $TraceVideo,
    [string] $CaptureFrame = '',
    [ValidateRange(1, 1000000)]
    [uint64] $CaptureFrameAfter = 120,
    [string] $TraceGather = '',
    [ValidateRange(1, 1000000)]
    [uint64] $TraceGatherBursts = 200000,
    [Nullable[uint32]] $IdlePC = $null,
    [ValidateRange(0, 300000)]
    [int] $StopAfterMilliseconds = 0,
    [string] $LoadState = '',
    [string] $ImportWiiSave = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-BuildEnvironment.ps1')

$root = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $root 'build\upstream\moderngekko\moderngekko-run.exe'
$moduleInfo = Join-Path $root 'build\upstream\moderngekko\moderngekko-module-info.exe'
$activeModule = Join-Path $Modules 'RMGE01\active-module.txt'

& (Join-Path $PSScriptRoot 'Assert-GameRevision.ps1') -GameRoot $GameRoot

foreach ($required in @($runner, $moduleInfo, $activeModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required build artifact is missing: $required"
    }
}

$module = (Get-Content -LiteralPath $activeModule -Raw).Trim()
if (-not [System.IO.Path]::IsPathRooted($module)) {
    $module = Join-Path (Split-Path $activeModule -Parent) $module
}
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw "Active module is missing: $module"
}

New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
Invoke-Checked $moduleInfo @($module, 'RMGE01')

$arguments = @(
    '--game', $GameRoot,
    '--module', $module,
    '--user-dir', $UserDirectory,
    '--graphics', $Graphics,
    '--cpu-core', $CpuCore,
    '--title', 'Super Mario Galaxy PC'
)
if ($null -ne $IdlePC) {
    $arguments += @('--idle-pc', ('0x{0:X8}' -f $IdlePC))
}
if ($Headless) {
    $arguments += '--headless'
}
if ($TraceVideo) {
    $arguments += '--trace-video'
}
if ($CaptureFrame) {
    $captureParent = Split-Path $CaptureFrame -Parent
    if ($captureParent) {
        New-Item -ItemType Directory -Force -Path $captureParent | Out-Null
    }
    $arguments += @('--capture-frame', $CaptureFrame, '--capture-frame-after', $CaptureFrameAfter)
}
if ($TraceGather) {
    $traceGatherParent = Split-Path $TraceGather -Parent
    if ($traceGatherParent) {
        New-Item -ItemType Directory -Force -Path $traceGatherParent | Out-Null
    }
    $arguments += @('--trace-gather', $TraceGather, '--trace-gather-bursts', $TraceGatherBursts)
}
if ($StopAfterMilliseconds -gt 0) {
    $arguments += @('--stop-after-ms', $StopAfterMilliseconds)
}
if ($LoadState) {
    if (-not (Test-Path -LiteralPath $LoadState -PathType Leaf)) {
        throw "Savestate is missing: $LoadState"
    }
    $arguments += @('--load-state', $LoadState)
}
if ($ImportWiiSave) {
    $arguments += @('--import-wii-save', $ImportWiiSave)
}

$runnerArguments = $arguments | ForEach-Object {
    if ($_ -match '[\s"]') {
        '"' + $_.Replace('"', '\"') + '"'
    } else {
        $_
    }
}
$process = Start-Process -FilePath $runner -ArgumentList $runnerArguments `
    -WorkingDirectory $root -NoNewWindow -PassThru -Wait
if ($process.ExitCode -ne 0) {
    throw "ModernGekko runner failed with exit code $($process.ExitCode)"
}
