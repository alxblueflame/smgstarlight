param(
    [string] $GameRoot = 'C:\SMGRecomp\data\RMGE01',
    [string] $Modules = 'C:\SMGRecomp\modules',
    [string] $UserDirectory = 'C:\SMGRecomp\user\RMGE01',
    [ValidateSet('D3D', 'Vulkan', 'OGL')]
    [string] $Graphics = 'D3D',
    [ValidateSet('static', 'jit', 'cached-interpreter', 'interpreter')]
    [string] $CpuCore = 'static',
    [string] $Controller = '',
    [ValidateSet('', 'Auto', '640x528', '1280x720', '1920x1080', '2560x1440', '3840x2160', '5120x2880', '7680x4320')]
    [string] $Resolution = '',
    [Nullable[bool]] $ShowPerformanceOverlay = $null,
    [Nullable[bool]] $EnableGraphicsMods = $null,
    [Nullable[bool]] $LoadCustomTextures = $null,
    [ValidateSet('', 'Cubeb', 'WASAPI (Exclusive Mode)')]
    [string] $AudioBackend = '',
    [string] $ImportSave = '',
    [string] $ExportSave = '',
    [switch] $Launcher
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Super Mario Galaxy: Starlight - $CpuCore CPU core"
Write-Host ''
Write-Host 'Default controls (keyboard + mouse, upright Wii Remote with Nunchuk):'
Write-Host '  A button        left mouse click'
Write-Host '  B button        right mouse click'
Write-Host '  Pointer (IR)    move the mouse'
Write-Host '  Shake / spin    middle mouse click'
Write-Host '  D-Pad           arrow keys'
Write-Host '  1 / 2 buttons   keyboard 1 / 2'
Write-Host '  - / +           Q / E'
Write-Host '  Home            Enter'
Write-Host '  Nunchuk stick   W A S D'
Write-Host '  Nunchuk C / Z   Left Ctrl / Left Shift'
Write-Host ''
Write-Host 'Title screen: press A and B together. The PC menu opens after the native fade.'
Write-Host 'Choose Play to continue to the original save-file selection.'
Write-Host ''
Write-Host 'Gamepad (pass -Controller "SDL/0/<pad name>" or set controller= in user config.ini):'
Write-Host '  A = south button, B = right trigger, spin = west button'
Write-Host '  Nunchuk stick = left stick, pointer = right stick'
Write-Host '  C = left shoulder, Z = left trigger, +/- = Start/Back, Home = Guide'
Write-Host ''

$runArgs = @{
    GameRoot      = $GameRoot
    Modules       = $Modules
    UserDirectory = $UserDirectory
    Graphics      = $Graphics
    CpuCore       = $CpuCore
}
$configPath = Join-Path $UserDirectory 'config.ini'
$existing = @{}
if (Test-Path -LiteralPath $configPath) {
    foreach ($line in Get-Content -LiteralPath $configPath) {
        if ($line -match '^\s*([^#;\[=][^=]*)=(.*)$') {
            $existing[$matches[1].Trim().ToLowerInvariant()] = $matches[2].Trim()
        }
    }
}
$configuredResolution = $existing['resolution']
$configuredController = $existing['controller']
$configuredOverlay = $existing['show_performance_overlay']
$configuredGraphicsMods = $existing['enable_graphics_mods']
$configuredCustomTextures = $existing['load_custom_textures']
$configuredAudioBackend = $existing['audio_backend']
New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null

$configUpdates = [ordered]@{}
if ($PSBoundParameters.ContainsKey('Resolution') -and $Resolution) {
    $configUpdates['resolution'] = $Resolution
}
if ($PSBoundParameters.ContainsKey('Controller')) {
    $configUpdates['controller'] = $Controller
}
if ($null -ne $ShowPerformanceOverlay) {
    $configUpdates['show_performance_overlay'] = $ShowPerformanceOverlay.Value.ToString().ToLowerInvariant()
}
if ($null -ne $EnableGraphicsMods) {
    $configUpdates['enable_graphics_mods'] = $EnableGraphicsMods.Value.ToString().ToLowerInvariant()
}
if ($null -ne $LoadCustomTextures) {
    $configUpdates['load_custom_textures'] = $LoadCustomTextures.Value.ToString().ToLowerInvariant()
}
if ($PSBoundParameters.ContainsKey('AudioBackend') -and $AudioBackend) {
    $configUpdates['audio_backend'] = $AudioBackend
}

if ($configUpdates.Count -gt 0) {
    $configLines = if (Test-Path -LiteralPath $configPath) {
        [System.Collections.Generic.List[string]](Get-Content -LiteralPath $configPath)
    } else {
        [System.Collections.Generic.List[string]]@(
            '# Super Mario Galaxy: Starlight settings'
            '[Video]'
            'resolution=1280x720'
        )
    }
    foreach ($entry in $configUpdates.GetEnumerator()) {
        $replaced = $false
        for ($i = 0; $i -lt $configLines.Count; $i++) {
            if ($configLines[$i] -match ('^\s*' + [regex]::Escape($entry.Key) + '\s*=')) {
                $configLines[$i] = "$($entry.Key)=$($entry.Value)"
                $replaced = $true
                break
            }
        }
        if (-not $replaced) {
            $configLines.Add("$($entry.Key)=$($entry.Value)")
        }
    }
    Set-Content -LiteralPath $configPath -Value $configLines -Encoding ascii
}

$saveData = Join-Path $UserDirectory 'Wii\title\00010000\524d4745\data'
if ($ImportSave) {
    if (Test-Path -LiteralPath $saveData -PathType Container) {
        $backup = Join-Path $UserDirectory ('Backup\RMGE01-before-import-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -LiteralPath $saveData -Destination $backup -Recurse -Force
    }
    if (Test-Path -LiteralPath $ImportSave -PathType Leaf) {
        if ([System.IO.Path]::GetExtension($ImportSave) -ine '.bin') {
            throw "Save import file must be a Wii data.bin: $ImportSave"
        }
        $runArgs.ImportWiiSave = $ImportSave
    } elseif (Test-Path -LiteralPath $ImportSave -PathType Container) {
        $source = if (Test-Path -LiteralPath (Join-Path $ImportSave 'data') -PathType Container) {
            Join-Path $ImportSave 'data'
        } else { $ImportSave }
        $staging = "$saveData.importing"
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        Copy-Item -Path (Join-Path $source '*') -Destination $staging -Recurse -Force
        Remove-Item -LiteralPath $saveData -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $staging -Destination $saveData
    } else {
        throw "Save import path does not exist: $ImportSave"
    }
}
if ($ExportSave) {
    if (-not (Test-Path -LiteralPath $saveData -PathType Container)) {
        throw "No RMGE01 save data exists at $saveData"
    }
    $destination = Join-Path $ExportSave 'RMGE01-save\data'
    $staging = "$destination.exporting"
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Copy-Item -Path (Join-Path $saveData '*') -Destination $staging -Recurse -Force
    Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $staging -Destination $destination
    Write-Host "Save exported to $destination"
    if (-not $ImportSave) { return }
}

# The direct runner is the stable, tested path; the ImGui launcher is opt-in.
if (-not $Launcher) {
    & (Join-Path $PSScriptRoot 'Run-Game.ps1') @runArgs
    return
}

$root = Split-Path $PSScriptRoot -Parent
$launcherExe = Join-Path $root 'build\upstream\moderngekko\Super Mario Galaxy Starlight.exe'
$activeModule = Join-Path $Modules 'RMGE01\active-module.txt'
foreach ($required in @($launcherExe, $activeModule)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required launcher artifact is missing: $required"
    }
}
$module = (Get-Content -LiteralPath $activeModule -Raw).Trim()
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw "Active module is missing: $module"
}

& $launcherExe --game $GameRoot --module $module --user-dir $UserDirectory --graphics $Graphics
if ($LASTEXITCODE -ne 0) {
    throw "ModernGekko launcher failed with exit code $LASTEXITCODE"
}
