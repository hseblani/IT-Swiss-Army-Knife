# Remove Windows Firewall Rules

param(
    [string]$RuleName = "SAK - *",
    [string]$WhatIf = "true",
    [string]$Confirm = "true"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Output "ERROR: Administrator privileges required to remove firewall rules."
    Write-Output "Please run the toolkit as Administrator."
    exit 1
}

try {
    Write-Output "========================================="
    Write-Output "REMOVE FIREWALL RULES"
    Write-Output "========================================="
    Write-Output ""
    Write-Output "Rule Pattern: $RuleName"
    
    $doWhatIf = ($WhatIf -eq "true")
    $doConfirm = ($Confirm -eq "true")
    
    if ($doWhatIf) {
        Write-Output "Mode: DRY RUN (WhatIf) - No actual changes"
    }
    Write-Output ""
    
    Write-Progress-Status -Percent 20 -Status "Finding matching rules..."
    
    $rules = @(Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)
    
    if ($rules.Count -eq 0) {
        Write-Output "No rules matched pattern: $RuleName"
        Write-Progress-Status -Percent 100 -Status "No rules found"
        exit 0
    }
    
    Write-Output "Found $($rules.Count) matching rule(s):"
    Write-Output ""
    $rules | Select-Object -ExpandProperty DisplayName | Sort-Object | ForEach-Object { 
        Write-Output "  - $_" 
    }
    Write-Output ""
    
    if ($doConfirm -and -not $doWhatIf) {
        $response = Read-Host "Remove these $($rules.Count) rule(s)? (Y/N)"
        if ($response.Trim().ToUpper() -ne "Y") {
            Write-Output "Cancelled by user."
            exit 0
        }
    }
    
    Write-Progress-Status -Percent 60 -Status "Removing rules..."
    
    if ($doWhatIf) {
        Remove-NetFirewallRule -InputObject $rules -WhatIf
        Write-Output ""
        Write-Output "[DRY RUN] The above rules would be removed."
        Write-Output "Uncheck 'Dry Run' to actually remove them."
    } else {
        Remove-NetFirewallRule -InputObject $rules -Confirm:$false
        Write-Output "[OK] Successfully removed $($rules.Count) firewall rule(s)."
    }
    
    Write-Progress-Status -Percent 100 -Status "Complete"
    Write-Output ""
    Write-Output "Operation completed."
    
} catch {
    Write-Output ""
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output ""
    Write-Output "Common causes:"
    Write-Output "  - No rules matched the pattern"
    Write-Output "  - Insufficient permissions"
    Write-Output "  - Firewall service not running"
    exit 1
}
