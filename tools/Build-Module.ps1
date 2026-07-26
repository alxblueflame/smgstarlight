param(
    [string] $GameRoot = 'C:\SMGRecomp\data\RMGE01',
    [string] $Output = 'C:\SMGRecomp\modules'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-BuildEnvironment.ps1')
$null = Enter-SmgBuildEnvironment

$root = Split-Path $PSScriptRoot -Parent
$port = Join-Path $root 'build\upstream\moderngekko\moderngekko-port.exe'
$moduleInfo = Join-Path $root 'build\upstream\moderngekko\moderngekko-module-info.exe'
if (-not (Test-Path -LiteralPath $port -PathType Leaf)) {
    throw 'ModernGekko is not built. Run Build-Upstream.ps1 -Target ModernGekko first.'
}

& (Join-Path $PSScriptRoot 'Assert-GameRevision.ps1') -GameRoot $GameRoot
New-Item -ItemType Directory -Force -Path $Output | Out-Null

Invoke-Checked $port @('inspect', $GameRoot, '--output', $Output)
Invoke-Checked $port @('build', $GameRoot, '--toolchain', 'msvc', '--output', $Output)

$activeModule = Join-Path $Output 'RMGE01\active-module.txt'
if (-not (Test-Path -LiteralPath $activeModule -PathType Leaf)) {
    throw "Module build completed without publishing $activeModule"
}
$module = (Get-Content -LiteralPath $activeModule -Raw).Trim()
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw "Module build published a missing DLL: $module"
}
Invoke-Checked $moduleInfo @($module, 'RMGE01')
Write-Host "Active module: $module"
