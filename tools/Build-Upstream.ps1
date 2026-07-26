param(
    [ValidateSet('DolRecomp', 'ModernGekko', 'All')]
    [string] $Target = 'All',
    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string] $Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-BuildEnvironment.ps1')
$null = Enter-SmgBuildEnvironment

$root = Split-Path $PSScriptRoot -Parent

if ($Target -in @('DolRecomp', 'All')) {
    $source = Join-Path $root 'third_party\DolRecomp'
    $build = Join-Path $root 'build\upstream\dolrecomp'
    Invoke-Checked cmake.exe @('-S', $source, '-B', $build, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$Configuration")
    Invoke-Checked cmake.exe @('--build', $build, '-j', '8')
    Invoke-Checked ctest.exe @('--test-dir', $build, '--output-on-failure')
}

if ($Target -in @('ModernGekko', 'All')) {
    & (Join-Path $PSScriptRoot 'Apply-UpstreamPatches.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to prepare the ModernGekko source tree.'
    }
    $source = Join-Path $root 'third_party\ModernGekko'
    $build = Join-Path $root 'build\upstream\moderngekko'
    Invoke-Checked cmake.exe @('-S', $source, '-B', $build, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$Configuration", '-DBUILD_TESTING=OFF', '-DMODERNGEKKO_ENABLE_DOLPHIN_TESTS=OFF')
    Invoke-Checked cmake.exe @('--build', $build, '-j', '8')
}
