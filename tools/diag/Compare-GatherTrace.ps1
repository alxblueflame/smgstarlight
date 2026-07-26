param(
    [Parameter(Mandatory)] [string] $JitPath,
    [Parameter(Mandatory)] [string] $StaticPath,
    [int] $Context = 3,
    [int] $SearchWindow = 64
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-GatherTrace {
    param([string] $Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $magic = [Text.Encoding]::ASCII.GetString($bytes, 0, 8)
    if ($magic -ne 'MGFIFOH6') {
        throw "Unexpected trace magic '$magic' in $Path"
    }
    $count = [BitConverter]::ToUInt64($bytes, 8)
    $p = 16L
    $prefixes = $p; $p += 8 * $count
    $chunks = $p; $p += 8 * $count
    $contexts = $p; $p += 4 * $count
    $entries = $p; $p += 4 * $count
    $dispatches = $p; $p += 8 * $count
    $ticks = $p; $p += 8 * $count
    $data = $p; $p += 32 * $count

    [pscustomobject]@{
        Bytes = $bytes
        Count = [long]$count
        Chunks = $chunks
        Contexts = $contexts
        Entries = $entries
        Dispatches = $dispatches
        Ticks = $ticks
        Data = $data
    }
}

function Get-Chunk { param($t, [long]$i) [BitConverter]::ToUInt64($t.Bytes, $t.Chunks + 8 * $i) }
function Get-Tick { param($t, [long]$i) [BitConverter]::ToUInt64($t.Bytes, $t.Ticks + 8 * $i) }
function Get-Ctx { param($t, [long]$i) [BitConverter]::ToUInt32($t.Bytes, $t.Contexts + 4 * $i) }
function Get-Entry { param($t, [long]$i) [BitConverter]::ToUInt32($t.Bytes, $t.Entries + 4 * $i) }
function Get-Data { param($t, [long]$i) [BitConverter]::ToString($t.Bytes, [int]($t.Data + 32 * $i), 32).Replace('-','') }

$j = Read-GatherTrace $JitPath
$s = Read-GatherTrace $StaticPath
$n = [Math]::Min($j.Count, $s.Count)
Write-Output "jit_bursts=$($j.Count) static_bursts=$($s.Count) compared=$n"

$first = -1L
for ($i = 0L; $i -lt $n; $i++) {
    if ((Get-Chunk $j $i) -ne (Get-Chunk $s $i)) { $first = $i; break }
}
if ($first -lt 0) {
    Write-Output 'traces identical over compared range'
    exit 0
}

Write-Output "first_content_difference=burst $($first + 1)"
$lo = [Math]::Max(0, $first - $Context)
$hi = [Math]::Min($n - 1, $first + $Context)
for ($i = $lo; $i -le $hi; $i++) {
    $same = (Get-Chunk $j $i) -eq (Get-Chunk $s $i)
    Write-Output ("burst={0} same={1}" -f ($i + 1), $same)
    Write-Output ("  J tick={0} ctx=0x{1:X8} entry=0x{2:X8}" -f (Get-Tick $j $i), (Get-Ctx $j $i), (Get-Entry $j $i))
    Write-Output ("  S tick={0} ctx=0x{1:X8} entry=0x{2:X8}" -f (Get-Tick $s $i), (Get-Ctx $s $i), (Get-Entry $s $i))
    if (-not $same) {
        Write-Output ("  J data={0}" -f (Get-Data $j $i))
        Write-Output ("  S data={0}" -f (Get-Data $s $i))
    }
}

# Is the divergence a reordering? Look for J[first] later in S and vice versa.
$jTarget = Get-Chunk $j $first
$sTarget = Get-Chunk $s $first
$jFoundAt = -1L; $sFoundAt = -1L
$lo = [Math]::Max(0, $first - $SearchWindow)
$hi = [Math]::Min($n - 1, $first + $SearchWindow)
for ($k = $lo; $k -le $hi; $k++) {
    if ($jFoundAt -lt 0 -and (Get-Chunk $s $k) -eq $jTarget) { $jFoundAt = $k }
    if ($sFoundAt -lt 0 -and (Get-Chunk $j $k) -eq $sTarget) { $sFoundAt = $k }
}
if ($jFoundAt -ge 0) {
    Write-Output ("J[{0}] found at S[{1}] delta={2}" -f ($first + 1), ($jFoundAt + 1), ($jFoundAt - $first))
} else {
    Write-Output ("J[{0}] not found in S within +/-{1}" -f ($first + 1), $SearchWindow)
}
if ($sFoundAt -ge 0) {
    Write-Output ("S[{0}] found at J[{1}] delta={2}" -f ($first + 1), ($sFoundAt + 1), ($sFoundAt - $first))
} else {
    Write-Output ("S[{0}] not found in J within +/-{1}" -f ($first + 1), $SearchWindow)
}

# Tick alignment before the divergence: how far apart are guest times for identical bursts?
Write-Output '--- tick drift on matching prefix ---'
$samplePoints = @(0L, [long]($first / 4), [long]($first / 2), [long](3 * $first / 4), [Math]::Max(0L, $first - 1))
foreach ($i in ($samplePoints | Sort-Object -Unique)) {
    $jt = Get-Tick $j $i
    $st = Get-Tick $s $i
    Write-Output ("burst={0} jit_tick={1} static_tick={2} drift={3}" -f ($i + 1), $jt, $st, ([long]$st - [long]$jt))
}
