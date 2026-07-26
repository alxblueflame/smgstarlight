param(
    [Parameter(Mandatory)]
    [string] $Profile,
    [Parameter(Mandatory)]
    [string] $Map,
    [Parameter(Mandatory)]
    [string] $Module,
    [ValidateRange(1, 65536)]
    [int] $BucketBytes = 16,
    [ValidateRange(1, 200)]
    [int] $Top = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$imageBase = [uint64]0x180000000
$symbols = foreach ($line in Get-Content -LiteralPath $Map) {
    if ($line -match '^\s+[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}\s+(\S+)\s+([0-9A-Fa-f]{16})\s+f(?:\s|$)') {
        $address = [Convert]::ToUInt64($matches[2], 16)
        if ($address -ge $imageBase) {
            [pscustomobject]@{
                Name = $matches[1]
                RVA = $address - $imageBase
            }
        }
    }
}
$symbols = $symbols | Sort-Object RVA, Name -Unique
if (-not $symbols) {
    throw "No function symbols were parsed from $Map."
}

$counts = @{}
foreach ($row in Import-Csv -LiteralPath $Profile) {
    if ($row.Module -ne $Module) {
        continue
    }

    $rva = [Convert]::ToUInt64($row.RVABucket.Substring(2), 16) +
        [uint64]([math]::Floor($BucketBytes / 2))
    $low = 0
    $high = $symbols.Count - 1
    $best = -1
    while ($low -le $high) {
        $middle = [int](($low + $high) / 2)
        if ($symbols[$middle].RVA -le $rva) {
            $best = $middle
            $low = $middle + 1
        } else {
            $high = $middle - 1
        }
    }
    if ($best -lt 0) {
        continue
    }

    $key = '{0:X}|{1}' -f $symbols[$best].RVA, $symbols[$best].Name
    if (-not $counts.ContainsKey($key)) {
        $counts[$key] = 0
    }
    $counts[$key] += [int]$row.Samples
}

$resolvedTotal = ($counts.Values | Measure-Object -Sum).Sum
$result = foreach ($entry in $counts.GetEnumerator()) {
    $parts = $entry.Key.Split('|', 2)
    [pscustomobject]@{
        RVA = '0x' + $parts[0]
        Symbol = $parts[1]
        Samples = $entry.Value
        ResolvedPercent = [math]::Round(100.0 * $entry.Value / $resolvedTotal, 2)
    }
}
$result | Sort-Object Samples -Descending | Select-Object -First $Top
