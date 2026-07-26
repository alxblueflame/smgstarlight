param(
    [Parameter(Mandatory)] [string] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$bmp = [System.Drawing.Bitmap]::FromFile($Path)
try {
    $maxChannel = 0; $sum = 0.0; $samples = 0
    $stepX = [Math]::Max(1, [int]($bmp.Width / 64))
    $stepY = [Math]::Max(1, [int]($bmp.Height / 64))
    for ($y = 0; $y -lt $bmp.Height; $y += $stepY) {
        for ($x = 0; $x -lt $bmp.Width; $x += $stepX) {
            $c = $bmp.GetPixel($x, $y)
            $peak = [Math]::Max([int]$c.R, [Math]::Max([int]$c.G, [int]$c.B))
            if ($peak -gt $maxChannel) { $maxChannel = $peak }
            $sum += ($c.R + $c.G + $c.B) / 3.0
            $samples++
        }
    }
    $mean = if ($samples) { $sum / $samples } else { 0 }
    [pscustomobject]@{
        Path = $Path
        Width = $bmp.Width
        Height = $bmp.Height
        MaxChannel = $maxChannel
        MeanBrightness = [Math]::Round($mean, 2)
        HasContent = ($maxChannel -gt 24)
    }
}
finally {
    $bmp.Dispose()
}
