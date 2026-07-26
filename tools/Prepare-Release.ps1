param(
    [string] $Version = 'Beta-5',
    [string] $OutputRoot = 'C:\SMGRecomp\dist'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Split-Path $PSScriptRoot -Parent)).Path
$dist = [System.IO.Path]::GetFullPath($OutputRoot)
$allowedDist = [System.IO.Path]::GetFullPath((Join-Path $root 'dist'))
if (-not $dist.Equals($allowedDist, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Release output must be $allowedDist"
}

$releaseName = "Super-Mario-Galaxy-Starlight-$Version"
$package = Join-Path $dist $releaseName
$zip = "$package.zip"
$modernBuild = Join-Path $root 'build\upstream\moderngekko'
$modernSource = Join-Path $root 'third_party\ModernGekko'
$module = (Get-Content (Join-Path $root 'modules\RMGE01\active-module.txt') -Raw).Trim()

$required = @(
    (Join-Path $modernBuild 'Super Mario Galaxy Starlight.exe'),
    (Join-Path $modernBuild 'moderngekko-run.exe'),
    (Join-Path $modernBuild 'Sys'),
    (Join-Path $modernSource 'assets\RMGE01'),
    (Join-Path $modernSource 'assets\ShaderCache\RMGE01.uidcache'),
    $module
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required release input not found: $path"
    }
}

if (Test-Path -LiteralPath $package) {
    Remove-Item -LiteralPath $package -Recurse -Force
}
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}

foreach ($directory in @('Assets', 'Licenses', 'Module', 'ShaderCache')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $package $directory) | Out-Null
}

Copy-Item (Join-Path $modernBuild 'Super Mario Galaxy Starlight.exe') $package
Copy-Item (Join-Path $modernBuild 'moderngekko-run.exe') $package
Copy-Item (Join-Path $modernBuild 'Sys') (Join-Path $package 'Sys') -Recurse
Copy-Item (Join-Path $modernSource 'assets\RMGE01') (Join-Path $package 'Assets\RMGE01') -Recurse
Copy-Item $module (Join-Path $package 'Module\gRMGE01_recomp.dll')
Copy-Item (Join-Path $modernSource 'assets\ShaderCache\RMGE01.uidcache') `
    (Join-Path $package 'ShaderCache\RMGE01.uidcache')
Copy-Item (Join-Path $modernSource 'assets\ShaderCache\README.txt') `
    (Join-Path $package 'ShaderCache\README.txt')

$licenses = @{
    'ModernGekko-LICENSE.txt' = (Join-Path $modernSource 'LICENSE')
    'Dolphin-COPYING.txt' = (Join-Path $modernSource 'vendor\dolphin\COPYING')
    'DolRecomp-LICENSE.txt' = (Join-Path $modernSource 'vendor\dolphin\DolRecomp\LICENSE')
    'Cubeb-LICENSE.txt' = (Join-Path $modernSource 'vendor\dolphin\Externals\cubeb\cubeb\LICENSE')
    'SDL-LICENSE.txt' = (Join-Path $modernSource 'vendor\dolphin\Externals\SDL\SDL\LICENSE.txt')
}
foreach ($entry in $licenses.GetEnumerator()) {
    Copy-Item $entry.Value (Join-Path $package "Licenses\$($entry.Key)")
}

$readme = @"
SUPER MARIO GALAXY: STARLIGHT - $Version

QUICK START
1. Extract the entire ZIP to a writable folder.
2. Open "Super Mario Galaxy Starlight.exe".
3. Choose your USA RMGE01 ISO or WBFS and select "Extract and play".
4. Keep the launcher open until extraction and verification finish.
5. Press A+B on the original title screen and choose PLAY.

FIRST-LAUNCH SHADERS
- The first launch compiles the included portable RMGE01 pipeline set for your graphics driver.
- Let the compilation progress screen finish. Later launches reuse the generated local cache.
- Driver-specific shader binaries are not included in this ZIP.

DISPLAY
- Aspect modes: Auto, Stretch, 4:3, 16:9, 21:9 and 32:9.
- Stretch fills the active display, including 16:10 and other monitor shapes.
- Normal widescreen modes keep the interface centered and proportion-correct.
- 21:9 and 32:9 expand the 3D view and apply the RMGE01 edge-culling correction.
- F11 or Alt+Enter toggles borderless fullscreen. F2 opens in-game settings.

INPUT AND AUDIO
- Xbox, DualShock, DualSense, SDL controllers, keyboard and mouse are supported.
- DualShock and DualSense motion input, rumble, dead zones and pointer speed are configurable.
- Cubeb shared-mode audio is the default for OBS, Game Bar and Snipping Tool capture.

DATA
- Settings, saves, extracted game data, logs and generated shader caches are stored in:
  %LOCALAPPDATA%\SMGRecomp\RMGE01
- This package contains no Wii disc image or extracted game files.
"@

$buildInfo = @"
Super Mario Galaxy: Starlight - $Version
Game revision: RMGE01 (USA)
CPU path: DolRecomp native module with runtime fallback for dynamically loaded Wii code
Graphics: D3D default, portable first-launch shader preparation
Aspect modes: Auto, Stretch, 4:3, 16:9, 21:9 and 32:9
Audio: Cubeb shared mode by default
Built: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC
"@

$notices = @"
Super Mario Galaxy: Starlight uses ModernGekko and Dolphin-derived runtime components.
License information for redistributed open-source components is included in the Licenses directory.
This package contains no Wii disc image or extracted game files.
"@

[System.IO.File]::WriteAllText(
    (Join-Path $package 'README-FIRST.txt'),
    $readme,
    [System.Text.UTF8Encoding]::new($false)
)
[System.IO.File]::WriteAllText(
    (Join-Path $package 'BUILD-INFO.txt'),
    $buildInfo,
    [System.Text.UTF8Encoding]::new($false)
)
[System.IO.File]::WriteAllText(
    (Join-Path $package 'THIRD-PARTY-NOTICES.txt'),
    $notices,
    [System.Text.UTF8Encoding]::new($false)
)

$checksumLines = Get-ChildItem -LiteralPath $package -Recurse -File |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($package.Length + 1).Replace('\', '/')
        "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
    }
[System.IO.File]::WriteAllLines(
    (Join-Path $package 'SHA256SUMS.txt'),
    $checksumLines,
    [System.Text.UTF8Encoding]::new($false)
)

Compress-Archive -LiteralPath $package -DestinationPath $zip -CompressionLevel Optimal
$zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "Release folder: $package"
Write-Host "Release ZIP: $zip"
Write-Host "SHA-256: $zipHash"
