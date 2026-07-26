Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent

function Apply-RepositoryPatch {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $Patch
    )

    if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
        throw "Repository not found: $Repository"
    }
    if (-not (Test-Path -LiteralPath $Patch -PathType Leaf)) {
        throw "Patch not found: $Patch"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & git.exe -C $Repository apply --reverse --check $Patch 2>&1
        $reverseApplies = $LASTEXITCODE -eq 0
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($reverseApplies) {
        Write-Host "Already applied: $Patch"
        return
    }

    $ErrorActionPreference = 'Continue'
    try {
        $checkOutput = & git.exe -C $Repository apply --check $Patch 2>&1
        $checkExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($checkExitCode -ne 0) {
        throw "Patch does not apply cleanly: $Patch`n$($checkOutput -join [Environment]::NewLine)"
    }

    & git.exe -C $Repository apply --whitespace=nowarn $Patch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply patch: $Patch"
    }
    Write-Host "Applied: $Patch"
}

function Apply-RepositoryPatchSeries {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string[]] $Patches
    )

    if ($Patches.Count -eq 0) {
        return
    }
    foreach ($patch in $Patches) {
        if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) {
            throw "Patch not found: $patch"
        }
    }

    $lastPatch = $Patches[-1]
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & git.exe -C $Repository apply --reverse --check $lastPatch 2>&1
        $seriesApplied = $LASTEXITCODE -eq 0
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($seriesApplied) {
        Write-Host "Already applied patch series ending in: $lastPatch"
        return
    }

    foreach ($patch in $Patches) {
        Apply-RepositoryPatch -Repository $Repository -Patch $patch
    }
}

function Set-RepositoryRevision {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $Revision
    )

    $current = (& git.exe -C $Repository rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read repository revision: $Repository"
    }
    if ($current -eq $Revision) {
        return
    }

    $changes = & git.exe -C $Repository status --porcelain
    if ($LASTEXITCODE -ne 0 -or $changes) {
        throw "Cannot change revision of a modified repository: $Repository"
    }

    & git.exe -C $Repository switch --detach $Revision
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to select revision $Revision in $Repository"
    }
    Write-Host "Selected revision: $Repository @ $Revision"
}

$modernGekko = Join-Path $root 'third_party\ModernGekko'
Apply-RepositoryPatchSeries -Repository $modernGekko -Patches @(
    (Join-Path $root 'patches\moderngekko\0006-starlight-complete.patch')
)
$provenance = Join-Path $modernGekko 'PROVENANCE.md'
if (Test-Path -LiteralPath $provenance -PathType Leaf) {
    $cleanProvenance = Get-Content -LiteralPath $provenance |
        Where-Object { $_ -notmatch '^Note:\s' }
    [System.IO.File]::WriteAllLines(
        $provenance,
        $cleanProvenance,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$dolphin = Join-Path $modernGekko 'vendor\dolphin'
Apply-RepositoryPatchSeries -Repository $dolphin -Patches @(
    (Join-Path $root 'patches\recompcore\0008-starlight-complete.patch')
)

$dolRecomp = Join-Path $dolphin 'DolRecomp'
Set-RepositoryRevision `
    -Repository $dolRecomp `
    -Revision 'efaa0a7dd0fdbedc3445d155b5ba5b228d801def'

Apply-RepositoryPatchSeries -Repository $dolRecomp -Patches @(
    (Join-Path $root 'patches\dolrecomp\0005-starlight-complete.patch')
)
