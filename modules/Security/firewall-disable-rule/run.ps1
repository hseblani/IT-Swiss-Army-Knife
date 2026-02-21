# Disable Windows Firewall Rules

param(
    [string]$RuleName = "*",
    [string]$WhatIf = "true"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Output "ERROR: Administrator privileges required to disable firewall rules."
    Write-Output "Please run the toolkit as Administrator."
    exit 1
}

try {
    Write-Output "========================================="
    Write-Output "DISABLE FIREWALL RULES"
    Write-Output "========================================="
    Write-Output ""
    Write-Output "Rule Pattern: $RuleName"
    
    $doWhatIf = ($WhatIf -eq "true")
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
    
    # Filter to only enabled rules
    $enabledRules = @($rules | Where-Object { $_.Enabled -eq "True" })
    
    if ($enabledRules.Count -eq 0) {
        Write-Output "All matching rules are already disabled."
        Write-Progress-Status -Percent 100 -Status "Nothing to disable"
        exit 0
    }
    
    Write-Output "Found $($enabledRules.Count) enabled rule(s) to disable:"
    Write-Output ""
    $enabledRules | Select-Object -ExpandProperty DisplayName | Sort-Object | ForEach-Object { 
        Write-Output "  - $_" 
    }
    Write-Output ""
    
    Write-Progress-Status -Percent 60 -Status "Disabling rules..."
    
    if ($doWhatIf) {
        Set-NetFirewallRule -InputObject $enabledRules -Enabled False -WhatIf
        Write-Output ""
        Write-Output "[DRY RUN] The above rules would be disabled."
        Write-Output "Uncheck 'Dry Run' to actually disable them."
    } else {
        Set-NetFirewallRule -InputObject $enabledRules -Enabled False -Confirm:$false
        Write-Output "[OK] Successfully disabled $($enabledRules.Count) firewall rule(s)."
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
