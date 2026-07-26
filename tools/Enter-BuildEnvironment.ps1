Set-StrictMode -Version Latest

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter()] [string[]] $Arguments = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath"
    }
}

function Enter-SmgBuildEnvironment {
    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer was not found.'
    }

    $vsInstall = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsInstall) {
        throw 'A Visual Studio installation with the x64 C++ toolchain was not found.'
    }

    $devShell = Join-Path $vsInstall 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    Import-Module $devShell
    Enter-VsDevShell -VsInstallPath $vsInstall -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
    $env:VSLANG = '1033'

    $cmakeRoot = Join-Path $vsInstall 'Common7\IDE\CommonExtensions\Microsoft\CMake'
    $env:PATH = "$(Join-Path $cmakeRoot 'CMake\bin');$(Join-Path $cmakeRoot 'Ninja');$env:PATH"

    [pscustomobject]@{
        VisualStudio = $vsInstall
        CMake = (Get-Command cmake.exe -ErrorAction Stop).Source
        Ninja = (Get-Command ninja.exe -ErrorAction Stop).Source
    }
}
