param(
    [int] $RunSeconds = 110,
    [string] $UserDirectory = 'C:\SMGRecomp\user\RMGE01',
    [int[]] $ClickAtSeconds = @(20, 30),
    [int[]] $ClickBothAtSeconds = @(45, 60, 75),
    [int[]] $DownAtSeconds = @(),
    [int[]] $RightAtSeconds = @(),
    [int[]] $ShotAtSeconds = @(),
    [int] $KeyHoldMilliseconds = 450,
    [string] $ShotPrefix = 'C:\SMGRecomp\work\strap-drive'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StrapDriveNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004, RIGHTDOWN = 0x0008, RIGHTUP = 0x0010;
    public const uint EXTENDEDKEY = 0x0001, KEYUP = 0x0002;
}
'@

function Save-WindowShot {
    param([IntPtr] $Handle, [string] $Path)
    $rect = New-Object StrapDriveNative+RECT
    if (-not [StrapDriveNative]::GetWindowRect($Handle, [ref]$rect)) { return $false }
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose()
    $bmp.Dispose()
    return $true
}

$module = (Get-Content -LiteralPath C:\SMGRecomp\modules\RMGE01\active-module.txt -Raw).Trim()
$stderr = 'C:\SMGRecomp\logs\strap-drive.stderr.log'
$arguments = @(
    '--game', 'C:\SMGRecomp\data\RMGE01',
    '--module', $module,
    '--user-dir', $UserDirectory,
    '--graphics', 'D3D',
    '--cpu-core', 'static',
    '--title', 'SMG-strap-drive',
    '--stop-after-ms', ($RunSeconds * 1000)
)
$process = Start-Process -FilePath C:\SMGRecomp\build\upstream\moderngekko\moderngekko-run.exe `
    -ArgumentList $arguments -WorkingDirectory C:\SMGRecomp `
    -RedirectStandardOutput 'C:\SMGRecomp\logs\strap-drive.stdout.log' `
    -RedirectStandardError $stderr -PassThru

function Invoke-DriveClick {
    param([System.Diagnostics.Process] $Process, [int] $At, [bool] $Both, [string] $ShotPrefix)
    $Process.Refresh()
    $handle = $Process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) { Write-Output "no window handle at t=${At}s"; return }
    $rect = New-Object StrapDriveNative+RECT
    if (-not [StrapDriveNative]::GetWindowRect($handle, [ref]$rect)) { return }
    $cx = [int](($rect.Left + $rect.Right) / 2)
    $cy = [int](($rect.Top + $rect.Bottom) / 2)
    [void][StrapDriveNative]::SetForegroundWindow($handle)
    Start-Sleep -Milliseconds 300
    [void][StrapDriveNative]::SetCursorPos($cx, $cy)
    Start-Sleep -Milliseconds 200
    [StrapDriveNative]::mouse_event([StrapDriveNative]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    if ($Both) { [StrapDriveNative]::mouse_event([StrapDriveNative]::RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero) }
    Start-Sleep -Milliseconds 400
    [StrapDriveNative]::mouse_event([StrapDriveNative]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    if ($Both) { [StrapDriveNative]::mouse_event([StrapDriveNative]::RIGHTUP, 0, 0, 0, [UIntPtr]::Zero) }
    $kind = if ($Both) { 'A+B' } else { 'A' }
    Write-Output "clicked $kind at t=${At}s center=$cx,$cy"
    Start-Sleep -Seconds 3
    $shot = "$ShotPrefix-t$At.png"
    if (Save-WindowShot -Handle $handle -Path $shot) { Write-Output "shot=$shot" }
}

function Invoke-DriveKey {
    param([System.Diagnostics.Process] $Process, [int] $At, [byte] $Key, [int] $HoldMilliseconds)
    $Process.Refresh()
    if ($Process.MainWindowHandle -eq [IntPtr]::Zero) { return }
    [void][StrapDriveNative]::SetForegroundWindow($Process.MainWindowHandle)
    $scan = if ($Key -eq 0x28) { 0x50 } else { 0x4D }
    [StrapDriveNative]::keybd_event($Key, $scan, [StrapDriveNative]::EXTENDEDKEY, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $HoldMilliseconds
    [StrapDriveNative]::keybd_event(
        $Key, $scan, [StrapDriveNative]::EXTENDEDKEY -bor [StrapDriveNative]::KEYUP,
        [UIntPtr]::Zero)
    Write-Output ('pressed {0} at t={1}s' -f $(if ($Key -eq 0x28) { 'DOWN' } else { 'RIGHT' }), $At)
}

$started = Get-Date
$plan = @()
$ClickAtSeconds | ForEach-Object { $plan += [pscustomobject]@{ At = $_; Action = 'A' } }
$ClickBothAtSeconds | ForEach-Object { $plan += [pscustomobject]@{ At = $_; Action = 'AB' } }
$DownAtSeconds | ForEach-Object { $plan += [pscustomobject]@{ At = $_; Action = 'Down' } }
$RightAtSeconds | ForEach-Object { $plan += [pscustomobject]@{ At = $_; Action = 'Right' } }
$ShotAtSeconds | ForEach-Object { $plan += [pscustomobject]@{ At = $_; Action = 'Shot' } }
$plan = $plan | Sort-Object At
$next = 0

while (-not $process.HasExited) {
    $elapsed = ((Get-Date) - $started).TotalSeconds
    if ($next -lt $plan.Count -and $elapsed -ge $plan[$next].At) {
        $event = $plan[$next]
        if ($event.Action -eq 'A' -or $event.Action -eq 'AB') {
            Invoke-DriveClick -Process $process -At $event.At -Both ($event.Action -eq 'AB') -ShotPrefix $ShotPrefix
        } elseif ($event.Action -eq 'Down') {
            Invoke-DriveKey -Process $process -At $event.At -Key 0x28 -HoldMilliseconds $KeyHoldMilliseconds
        } elseif ($event.Action -eq 'Right') {
            Invoke-DriveKey -Process $process -At $event.At -Key 0x27 -HoldMilliseconds $KeyHoldMilliseconds
        } else {
            $shot = "$ShotPrefix-t$($event.At).png"
            if (Save-WindowShot -Handle $process.MainWindowHandle -Path $shot) { Write-Output "shot=$shot" }
        }
        $next++
    }
    Start-Sleep -Milliseconds 500
}
$process.WaitForExit()
Write-Output "exit_code=$($process.ExitCode)"
Select-String -LiteralPath $stderr -Pattern 'shutdown:' | ForEach-Object { $_.Line }
