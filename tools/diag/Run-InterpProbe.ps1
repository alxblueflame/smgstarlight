param(
    [Parameter(Mandatory)] [uint64] $Start,
    [Parameter(Mandatory)] [uint64] $End,
    [uint64] $CaptureAfter = 120,
    [int] $DeadlineSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$label = '{0:X8}-{1:X8}' -f $Start, $End
$capture = "C:\SMGRecomp\work\probe\interp-$label.png"
$captureParent = Split-Path $capture -Parent
New-Item -ItemType Directory -Force -Path $captureParent | Out-Null
if (Test-Path -LiteralPath $capture) { Remove-Item -LiteralPath $capture -Force }

$module = (Get-Content -LiteralPath C:\SMGRecomp\modules\RMGE01\active-module.txt -Raw).Trim()
$env:STATICRECOMP_INTERPRET_START = '0x{0:X8}' -f $Start
$env:STATICRECOMP_INTERPRET_END = '0x{0:X8}' -f $End
try {
    $p = Start-Process -FilePath C:\SMGRecomp\build\upstream\moderngekko\moderngekko-run.exe `
        -ArgumentList @('--game','C:\SMGRecomp\data\RMGE01','--module',$module,
            '--user-dir','C:\SMGRecomp\user\RMGE01','--graphics','D3D','--cpu-core','static',
            '--title',"probe-$label",'--capture-frame',$capture,'--capture-frame-after',$CaptureAfter,
            '--stop-after-ms', ($DeadlineSeconds * 1000)) `
        -WorkingDirectory C:\SMGRecomp `
        -RedirectStandardOutput "C:\SMGRecomp\logs\probe-$label.stdout.log" `
        -RedirectStandardError "C:\SMGRecomp\logs\probe-$label.stderr.log" -PassThru
}
finally {
    Remove-Item Env:STATICRECOMP_INTERPRET_START -ErrorAction SilentlyContinue
    Remove-Item Env:STATICRECOMP_INTERPRET_END -ErrorAction SilentlyContinue
}

$deadline = [DateTime]::UtcNow.AddSeconds($DeadlineSeconds + 30)
$result = 'timeout'
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $capture) { $result = 'captured'; break }
    if ($p.HasExited) { $result = 'exited'; break }
    Start-Sleep -Seconds 2
}
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit()
}

if ($result -ne 'captured') {
    Write-Output "probe=$label result=$result (no capture)"
    exit 2
}
Start-Sleep -Milliseconds 500
$info = & (Join-Path $PSScriptRoot 'Get-FrameBrightness.ps1') -Path $capture
Write-Output ("probe=$label result=captured max={0} mean={1} verdict={2}" -f $info.MaxChannel, $info.MeanBrightness, $(if ($info.MeanBrightness -gt 100) { 'RENDERS' } else { 'BLACK' }))
