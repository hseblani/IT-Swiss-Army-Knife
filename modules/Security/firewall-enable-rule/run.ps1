# Enable Windows Firewall Rules

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
    Write-Output "ERROR: Administrator privileges required to enable firewall rules."
    Write-Output "Please run the toolkit as Administrator."
    exit 1
}

try {
    Write-Output "========================================="
    Write-Output "ENABLE FIREWALL RULES"
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
    
    # Filter to only disabled rules
    $disabledRules = @($rules | Where-Object { $_.Enabled -eq "False" })
    
    if ($disabledRules.Count -eq 0) {
        Write-Output "All matching rules are already enabled."
        Write-Progress-Status -Percent 100 -Status "Nothing to enable"
        exit 0
    }
    
    Write-Output "Found $($disabledRules.Count) disabled rule(s) to enable:"
    Write-Output ""
    $disabledRules | Select-Object -ExpandProperty DisplayName | Sort-Object | ForEach-Object { 
        Write-Output "  - $_" 
    }
    Write-Output ""
    
    Write-Progress-Status -Percent 60 -Status "Enabling rules..."
    
    if ($doWhatIf) {
        Set-NetFirewallRule -InputObject $disabledRules -Enabled True -WhatIf
        Write-Output ""
        Write-Output "[DRY RUN] The above rules would be enabled."
        Write-Output "Uncheck 'Dry Run' to actually enable them."
    } else {
        Set-NetFirewallRule -InputObject $disabledRules -Enabled True -Confirm:$false
        Write-Output "[OK] Successfully enabled $($disabledRules.Count) firewall rule(s)."
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
