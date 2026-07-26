param(
    [string] $Iso = 'C:\WIIGALAXY\Super Mario Galaxy (USA) (En,Fr,Es).iso',
    [string] $Wit = 'C:\WIIGALAXY\wit-v3.05a-r8638-cygwin64\bin\wit.exe',
    [string] $Destination = 'C:\SMGRecomp\data\RMGE01'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-BuildEnvironment.ps1')

$root = Split-Path $PSScriptRoot -Parent
$dolrecomp = Join-Path $root 'build\upstream\dolrecomp\dolrecomp.exe'
foreach ($path in @($Iso, $Wit, $dolrecomp)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file was not found: $path"
    }
}
if (Test-Path -LiteralPath $Destination) {
    throw "Destination already exists: $Destination"
}

$discInfo = & $Wit dump $Iso 2>&1 | Out-String
if ($discInfo -notmatch 'disc=RMGE01' -or $discInfo -notmatch 'NTSC/USA') {
    throw 'The input image is not the expected RMGE01 USA release.'
}

$isoHash = (Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash.ToLowerInvariant()
Invoke-Checked $dolrecomp @('extract', '--wit', $Wit, $Iso, $Destination)

$dataPartition = Join-Path $Destination 'DATA'
if (-not (Test-Path -LiteralPath (Join-Path $Destination 'sys\main.dol')) -and (Test-Path -LiteralPath (Join-Path $dataPartition 'sys\main.dol'))) {
    Get-ChildItem -LiteralPath $dataPartition -Force | Move-Item -Destination $Destination
    Remove-Item -LiteralPath $dataPartition -Force
}

$dol = Join-Path $Destination 'sys\main.dol'
$boot = Join-Path $Destination 'sys\boot.bin'
$files = Join-Path $Destination 'files'
if (-not (Test-Path -LiteralPath $dol -PathType Leaf) -or -not (Test-Path -LiteralPath $boot -PathType Leaf) -or -not (Test-Path -LiteralPath $files -PathType Container)) {
    throw 'Extraction did not produce the expected sys/main.dol, sys/boot.bin, and files tree.'
}

$manifest = [ordered]@{
    gameId = 'RMGE01'
    region = 'NTSC-U'
    isoPath = $Iso
    isoSha256 = $isoHash
    dolSha256 = (Get-FileHash -LiteralPath $dol -Algorithm SHA256).Hash.ToLowerInvariant()
    extractedAtUtc = [DateTime]::UtcNow.ToString('O')
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'local-manifest.json') -Encoding utf8
$manifest

