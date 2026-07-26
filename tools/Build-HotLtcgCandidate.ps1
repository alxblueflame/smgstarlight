param(
    [Parameter(Mandatory)]
    [string] $Profile,
    [Parameter(Mandatory)]
    [string] $Map,
    [string] $ProfileModule = 'gRMGE01_recomp.dll',
    [ValidateRange(1, 128)]
    [int] $HotChunks = 24,
    [string] $Output = 'C:\SMGRecomp\work\gRMGE01_hot-ltcg.dll'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-BuildEnvironment.ps1')
$null = Enter-SmgBuildEnvironment

$root = Split-Path $PSScriptRoot -Parent
$build = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Map))
$artifact = [IO.Path]::GetDirectoryName($build)
$generated = Join-Path $artifact 'dolrecomp-output\RMGE01_generated'
$chunks = Join-Path $generated 'chunks'
$gx = Join-Path $root 'third_party\ModernGekko\vendor\dolphin\GXRuntime'
$moduleTemplate = Join-Path $root 'third_party\ModernGekko\vendor\dolphin\module-template'
$abi = Join-Path $root 'third_party\ModernGekko\vendor\dolphin\Source\Core\Core\PowerPC\StaticRecomp'
$baseResponse = Join-Path $build 'CMakeFiles\gRMGE01_recomp.rsp'
$work = Join-Path $root 'work\ltcg-hot'
New-Item -ItemType Directory -Force -Path $work | Out-Null

$resolved = & (Join-Path $PSScriptRoot 'Resolve-ProfileMap.ps1') `
    -Profile $Profile -Map $Map -Module $ProfileModule `
    -BucketBytes 16 -Top 200
$hotSources = $resolved | Where-Object Symbol -Like 'func_*' | Select-Object -First $HotChunks |
    ForEach-Object {
        $address = $_.Symbol.Substring(5)
        $source = Get-ChildItem -LiteralPath $chunks -Filter "*_$address.c" | Select-Object -First 1
        if (-not $source) {
            throw "No generated chunk contains $($_.Symbol)."
        }
        $source
    }

$runtimeSources = @(
    (Join-Path $moduleTemplate 'module_export.c'),
    (Join-Path $gx 'src\core\cpu.c'),
    (Join-Path $gx 'src\core\cpu_interpreter.c'),
    (Join-Path $gx 'src\core\cpu_interpreter_table.c'),
    (Join-Path $gx 'src\core\cpu_interpreter_float.c'),
    (Join-Path $gx 'src\core\cpu_interpreter_integer.c')
)
$sources = @($runtimeSources) + @($hotSources.FullName)
$cl = (Get-Command cl.exe -ErrorAction Stop).Source
$common = @(
    '/nologo', '/c', '/TC', '/O2', '/Ob3', '/GL', '/Gy', '/Gw', '/GS-',
    '/fp:precise', '/std:c11', '/MD', '/DNDEBUG', '/DWIN32', '/D_WINDOWS',
    '/DgRMGE01_recomp_EXPORTS', '/DMODULE_GAME_ID=\"RMGE01\"',
    "/I$generated", "/I$(Join-Path $gx 'include')", "/I$abi", "/I$build"
)

$compiled = @{}
foreach ($source in $sources) {
    $sourcePath = [string]$source
    $stem = [IO.Path]::GetFileNameWithoutExtension($sourcePath)
    if ($sourcePath -like '*GXRuntime*') {
        $stem = 'runtime_' + $stem
    } elseif ($sourcePath -like '*module_export.c') {
        $stem = 'module_export'
    }
    $object = Join-Path $work ($stem + '.obj')
    Invoke-Checked $cl (@($common) + @("/Fo$object", $sourcePath))
    $compiled[$sourcePath] = $object
}

$responseLines = Get-Content -LiteralPath $baseResponse
$replacements = @{}
foreach ($sourcePath in $compiled.Keys) {
    $sourceName = [IO.Path]::GetFileName($sourcePath)
    $match = if ($sourcePath -like '*chunks*') {
        $responseLines | Where-Object { $_.EndsWith($sourceName + '.obj', [StringComparison]::OrdinalIgnoreCase) }
    } elseif ($sourceName -eq 'module_export.c') {
        $responseLines | Where-Object { $_.EndsWith('module_export.c.obj', [StringComparison]::OrdinalIgnoreCase) }
    } else {
        $responseLines | Where-Object {
            $_.Replace('\', '/').EndsWith(('/' + $sourceName + '.obj'), [StringComparison]::OrdinalIgnoreCase)
        }
    }
    if (@($match).Count -ne 1) {
        throw "Expected one response-file object for $sourceName, found $(@($match).Count)."
    }
    $replacements[[string]$match] = $compiled[$sourcePath]
}

$candidateResponse = Join-Path $work 'gRMGE01_hot-ltcg.rsp'
$responseLines | ForEach-Object {
    if ($replacements.ContainsKey($_)) { $replacements[$_] } else { $_ }
} | Set-Content -LiteralPath $candidateResponse -Encoding ASCII

$outputBase = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Output),
                                [IO.Path]::GetFileNameWithoutExtension($Output))
$link = (Get-Command link.exe -ErrorAction Stop).Source
Push-Location $build
try {
    Invoke-Checked $link @(
        '/nologo', '/dll', '/machine:x64', '/incremental:no', '/LTCG', '/OPT:REF', '/OPT:ICF',
        "/out:$Output", "/implib:$outputBase.lib", "/pdb:$outputBase.pdb",
        "/MAP:$outputBase.map", "@$candidateResponse"
    )
} finally {
    Pop-Location
}

Write-Output $Output
