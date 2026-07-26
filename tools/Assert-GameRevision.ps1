param(
    [string] $GameRoot = 'C:\SMGRecomp\data\RMGE01'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedGameId = 'RMGE01'
$expectedIsoSha256 = 'b47683440931bcf1a604c20fbad22b918977e20db4965df108050342f4857b8e'
$expectedDolSha256 = '2c680585a8f58e1cc9c5521b579057f12b124ff0ef409e470a57606c50a93c09'

$boot = Join-Path $GameRoot 'sys\boot.bin'
$dol = Join-Path $GameRoot 'sys\main.dol'
$manifestPath = Join-Path $GameRoot 'local-manifest.json'

foreach ($required in @($boot, $dol, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required game file is missing: $required"
    }
}

$bootBytes = [System.IO.File]::ReadAllBytes($boot)
if ($bootBytes.Length -lt 6) {
    throw "Invalid boot.bin: $boot"
}

$gameId = [System.Text.Encoding]::ASCII.GetString($bootBytes, 0, 6)
if ($gameId -cne $expectedGameId) {
    throw "Unsupported game ID '$gameId'. Expected $expectedGameId."
}

$dolSha256 = (Get-FileHash -LiteralPath $dol -Algorithm SHA256).Hash.ToLowerInvariant()
if ($dolSha256 -cne $expectedDolSha256) {
    throw "Unsupported main.dol revision '$dolSha256'. Expected $expectedDolSha256."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.gameId -cne $expectedGameId -or
    $manifest.isoSha256 -cne $expectedIsoSha256 -or
    $manifest.dolSha256 -cne $expectedDolSha256) {
    throw "Extraction manifest does not match the pinned RMGE01 release: $manifestPath"
}

Write-Host "Verified $expectedGameId (main.dol SHA-256 $expectedDolSha256)"
