param(
    [string]$Path,
    [switch]$Force
)

# =====================
# Configuration constants
# =====================
# Default path if -Path is not provided
# Relative to the directory from which the script is launched (i.e., current $PWD)
$DefaultFilePath = ".\lib.dll"

# What to SEARCH (hex without spaces)
$PatternHex = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Which byte inside the found sequence to modify (hex)
$TargetByteHex = "YY" # the last 0xXX within the sequence

# What value to set (hex)
$NewByteHex    = "ZZ"

# Backup extension
$BackupExtension = ".bak"

# =====================
# Implementation
# =====================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function HexToBytes([string]$hex) {
    $clean = ($hex -replace "\s", "").ToUpper()
    if (($clean.Length % 2) -ne 0) { throw "Hex string length must be even: '$hex'" }
    $bytes = New-Object byte[] ($clean.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($clean.Substring($i*2, 2), 16)
    }
    return $bytes
}

function FindPattern([byte[]]$data, [byte[]]$pattern) {
    if ($pattern.Length -eq 0) { throw "Empty pattern" }
    $indices = New-Object System.Collections.Generic.List[int]
    $limit = $data.Length - $pattern.Length
    for ($i = 0; $i -le $limit; $i++) {
        $match = $true
        for ($j = 0; $j -lt $pattern.Length; $j++) {
            if ($data[$i + $j] -ne $pattern[$j]) { $match = $false; break }
        }
        if ($match) { $indices.Add($i) }
    }
    return $indices
}

# Defaults
if (-not $Path -or [string]::IsNullOrWhiteSpace($Path)) {
    $Path = $DefaultFilePath
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

# Read data
[byte[]]$data = [System.IO.File]::ReadAllBytes($Path)

# Prepare byte representations
[byte[]]$pattern = HexToBytes $PatternHex
$targetByte = [Convert]::ToByte($TargetByteHex, 16)
$newByte    = [Convert]::ToByte($NewByteHex, 16)

# Find occurrences
$occurs = @((FindPattern -data $data -pattern $pattern))
if ($occurs.Count -eq 0) { throw "No occurrences found" }
if ($occurs.Count -gt 1) { throw "Multiple occurrences found (${($occurs.Count)}). Expected exactly one." }
$startIndex = $occurs[0]

# Find the last position of the target byte within the pattern
$lastInPattern = -1
for ($k = $pattern.Length - 1; $k -ge 0; $k--) {
    if ($pattern[$k] -eq $targetByte) { $lastInPattern = $k; break }
}
if ($lastInPattern -lt 0) { throw "Target byte 0x$TargetByteHex is not present in the pattern" }

$absIndex = $startIndex + $lastInPattern
if ($data[$absIndex] -ne $targetByte) {
    throw "Expected byte 0x$TargetByteHex at index $absIndex, but found: 0x{0}" -f $data[$absIndex].ToString('X2')
}

# Create backup
$backupPath = "$Path$BackupExtension"
if ((Test-Path -LiteralPath $backupPath) -and -not $Force) {
    throw "Backup already exists: $backupPath. Run with -Force to overwrite."
}
Copy-Item -LiteralPath $Path -Destination $backupPath -Force

# Patch and save
$data[$absIndex] = $newByte
[System.IO.File]::WriteAllBytes($Path, $data)

Write-Host ("OK: Patch applied. Offset: {0}, old: 0x{1}, new: 0x{2}. Backup: {3}" -f $absIndex, $targetByte.ToString('X2'), $newByte.ToString('X2'), $backupPath)