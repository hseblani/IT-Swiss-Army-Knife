# Disk Space Information

param([string]$InfoNote = "")

# Shared helpers (includes Write-ToolkitProgress)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Output "========================================="
Write-Output "DISK SPACE INFORMATION"
Write-Output "========================================="
Write-Output ""

Write-ToolkitProgress -Percent 5 -Status "Initializing..."

# Get all local drives
Write-ToolkitProgress -Percent 15 -Status "Scanning local drives..."
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | Sort-Object Name

if (-not $drives -or $drives.Count -eq 0) {
    Write-Output "No local drives found."
    Write-ToolkitProgress -Percent 100 -Status "Complete"
    return
}

Write-Output "Found $($drives.Count) local drive(s)"
Write-Output ""

$totalCapacity = 0
$totalUsed = 0
$totalFree = 0

Write-ToolkitProgress -Percent 25 -Status "Calculating disk usage..."

$barLength = 40
$totalDrives = $drives.Count
$idx = 0

foreach ($drive in $drives) {
    $idx++

    $total = $drive.Used + $drive.Free
    $used = $drive.Used
    $free = $drive.Free

    # Avoid divide-by-zero edge case
    $percent = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }

    $totalCapacity += $total
    $totalUsed += $used
    $totalFree += $free

    # Progress from 25% -> 85% across drives
    $loopPct = 25 + [math]::Round(($idx / $totalDrives) * 60)
    if ($loopPct -gt 85) { $loopPct = 85 }
    Write-ToolkitProgress -Percent $loopPct -Status ("Processing drive {0}/{1}: {2}" -f $idx, $totalDrives, $drive.Name)

    # Determine status based on usage
    $status = if ($percent -ge 90) { "[CRITICAL]" }
    elseif ($percent -ge 80) { "[WARNING]" }
    else { "[OK]" }

    Write-Output "Drive $($drive.Name): $status"
    Write-Output "  Capacity : $([math]::Round($total / 1GB, 2)) GB"
    Write-Output "  Used     : $([math]::Round($used / 1GB, 2)) GB ($percent%)"
    Write-Output "  Free     : $([math]::Round($free / 1GB, 2)) GB"

    # Visual bar
    $filledLength = [int](($percent / 100) * $barLength)
    if ($filledLength -lt 0) { $filledLength = 0 }
    if ($filledLength -gt $barLength) { $filledLength = $barLength }

    $emptyLength = $barLength - $filledLength
    $bar = "[" + ("=" * $filledLength) + (" " * $emptyLength) + "]"
    Write-Output "  $bar"
    Write-Output ""
}

Write-ToolkitProgress -Percent 90 -Status "Calculating totals..."

Write-Output "========================================="
Write-Output "SUMMARY"
Write-Output "========================================="
Write-Output "Total Drives     : $($drives.Count)"
Write-Output "Total Capacity   : $([math]::Round($totalCapacity / 1GB, 2)) GB"
Write-Output "Total Used       : $([math]::Round($totalUsed / 1GB, 2)) GB"
Write-Output "Total Free       : $([math]::Round($totalFree / 1GB, 2)) GB"

$avgUsage = if ($totalCapacity -gt 0) { [math]::Round(($totalUsed / $totalCapacity) * 100, 1) } else { 0 }
Write-Output "Average Usage    : $avgUsage%"
Write-Output ""

Write-ToolkitProgress -Percent 95 -Status "Checking warnings..."

# Warnings (compute per drive; do not reuse loop $percent)
$criticalDrives = @(
    $drives | Where-Object {
        $t = $_.Used + $_.Free
        if ($t -le 0) { return $false }
        ((($_.Used / $t) * 100) -ge 90)
    }
)

$warningDrives = @(
    $drives | Where-Object {
        $t = $_.Used + $_.Free
        if ($t -le 0) { return $false }
        $p = (($_.Used / $t) * 100)
        ($p -ge 80 -and $p -lt 90)
    }
)

if ($criticalDrives.Count -gt 0) {
    Write-Output "[!] CRITICAL: $($criticalDrives.Count) drive(s) over 90% full!"
    $criticalDrives | ForEach-Object { Write-Output "    - Drive $($_.Name)" }
    Write-Output ""
}

if ($warningDrives.Count -gt 0) {
    Write-Output "[!] WARNING: $($warningDrives.Count) drive(s) over 80% full!"
    $warningDrives | ForEach-Object { Write-Output "    - Drive $($_.Name)" }
    Write-Output ""
}

Write-ToolkitProgress -Percent 100 -Status "Complete"
Write-Output "Disk space scan completed."
