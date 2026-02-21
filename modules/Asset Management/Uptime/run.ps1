# System Uptime

param([string]$InfoNote = "")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }

Write-Output "========================================="
Write-Output "SYSTEM UPTIME"
Write-Output "========================================="
Write-Output ""

Write-Progress-Status -Percent 30 -Status "Retrieving boot time..."

$os = Get-CimInstance Win32_OperatingSystem
$bootTime = $os.LastBootUpTime
$currentTime = Get-Date
$uptime = $currentTime - $bootTime

Write-Output "Computer Name    : $env:COMPUTERNAME"
Write-Output "Current Time     : $($currentTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output "Last Boot Time   : $($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output ""

Write-Progress-Status -Percent 70 -Status "Calculating uptime..."

Write-Output "========================================="
Write-Output "UPTIME BREAKDOWN"
Write-Output "========================================="
Write-Output "Days             : $($uptime.Days)"
Write-Output "Hours            : $($uptime.Hours)"
Write-Output "Minutes          : $($uptime.Minutes)"
Write-Output "Seconds          : $($uptime.Seconds)"
Write-Output ""
Write-Output "Total Hours      : $([math]::Round($uptime.TotalHours, 2))"
Write-Output "Total Minutes    : $([math]::Round($uptime.TotalMinutes, 2))"
Write-Output ""

# Uptime summary
$summary = ""
if ($uptime.Days -gt 0) {
    $summary = "$($uptime.Days) day$(if($uptime.Days -ne 1){'s'}), $($uptime.Hours) hour$(if($uptime.Hours -ne 1){'s'}), $($uptime.Minutes) minute$(if($uptime.Minutes -ne 1){'s'})"
} elseif ($uptime.Hours -gt 0) {
    $summary = "$($uptime.Hours) hour$(if($uptime.Hours -ne 1){'s'}), $($uptime.Minutes) minute$(if($uptime.Minutes -ne 1){'s'})"
} else {
    $summary = "$($uptime.Minutes) minute$(if($uptime.Minutes -ne 1){'s'})"
}

Write-Output "Uptime Summary   : $summary"
Write-Output ""

# Recommendations
if ($uptime.Days -gt 30) {
    Write-Output "[!] NOTICE: System has been running for over 30 days."
    Write-Output "    Consider rebooting to apply pending updates and clear memory."
} elseif ($uptime.Days -gt 7) {
    Write-Output "[i] INFO: System has been running for over a week."
    Write-Output "    A reboot may help maintain optimal performance."
}

Write-Progress-Status -Percent 100 -Status "Complete"

Write-Output ""
Write-Output "Uptime check completed."
