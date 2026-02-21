# List Windows Firewall Rules

param(
    [string]$RuleName = "*",
    [string]$IncludeDisabled = "true",
    [ValidateSet("Any", "Inbound", "Outbound")]
    [string]$DirectionFilter = "Any",
    [ValidateSet("Any", "Allow", "Block")]
    [string]$ActionFilter = "Any",
    [ValidateSet("Any", "Domain", "Private", "Public")]
    [string]$ProfileFilter = "Any",
    [ValidateSet("None", "CSV", "JSON")]
    [string]$ExportFormat = "None",
    [string]$ExportPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }

try {
    Write-Output "========================================="
    Write-Output "LIST FIREWALL RULES"
    Write-Output "========================================="
    Write-Output ""
    Write-Output "Rule Pattern     : $RuleName"
    Write-Output "Include Disabled : $IncludeDisabled"
    Write-Output "Direction Filter : $DirectionFilter"
    Write-Output "Action Filter    : $ActionFilter"
    Write-Output "Profile Filter   : $ProfileFilter"
    Write-Output ""

    Write-Progress-Status -Percent 10 -Status "Retrieving firewall rules..."
    
    # Get rules matching pattern
    $rules = @(Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)
    
    if ($rules.Count -eq 0) {
        Write-Output "No rules found matching pattern: $RuleName"
        Write-Progress-Status -Percent 100 -Status "No rules found"
        exit 0
    }
    
    # Apply filters
    if ($IncludeDisabled -ne "true") {
        $rules = @($rules | Where-Object { $_.Enabled -eq "True" })
    }
    
    if ($DirectionFilter -ne "Any") {
        $rules = @($rules | Where-Object { $_.Direction -eq $DirectionFilter })
    }
    
    if ($ActionFilter -ne "Any") {
        $rules = @($rules | Where-Object { $_.Action -eq $ActionFilter })
    }
    
    if ($ProfileFilter -ne "Any") {
        $rules = @($rules | Where-Object { ($_.Profile.ToString()) -match $ProfileFilter })
    }
    
    Write-Output "Found $($rules.Count) matching rule(s)"
    Write-Output ""
    
    Write-Progress-Status -Percent 50 -Status "Collecting rule details..."
    
    # Collect detailed information
    $rows = foreach ($r in $rules) {
        $port = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
        $app = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
        $addr = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue
        $svc = Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            DisplayName   = $r.DisplayName
            Enabled       = $r.Enabled
            Direction     = $r.Direction
            Action        = $r.Action
            Profile       = $r.Profile
            Protocol      = ($port | Select-Object -First 1).Protocol
            LocalPort     = ($port | Select-Object -First 1).LocalPort
            RemotePort    = ($port | Select-Object -First 1).RemotePort
            Program       = ($app  | Select-Object -First 1).Program
            Service       = ($svc  | Select-Object -First 1).Service
            LocalAddress  = ($addr | Select-Object -First 1).LocalAddress
            RemoteAddress = ($addr | Select-Object -First 1).RemoteAddress
            Group         = $r.Group
            Description   = $r.Description
        }
    }
    
    Write-Progress-Status -Percent 80 -Status "Formatting results..."
    
    # Display results
    Write-Output "Firewall Rules:"
    Write-Output ""
    $rows | Sort-Object DisplayName | Format-Table Enabled, Direction, Action, Profile, Protocol, LocalPort, DisplayName -AutoSize | Out-String | Write-Output
    
    # Summary
    $enabled = @($rows | Where-Object { $_.Enabled -eq "True" }).Count
    $disabled = $rows.Count - $enabled
    $inbound = @($rows | Where-Object { $_.Direction -eq "Inbound" }).Count
    $outbound = @($rows | Where-Object { $_.Direction -eq "Outbound" }).Count
    $allow = @($rows | Where-Object { $_.Action -eq "Allow" }).Count
    $block = @($rows | Where-Object { $_.Action -eq "Block" }).Count
    
    Write-Output ""
    Write-Output "Summary:"
    Write-Output "  Total Rules  : $($rows.Count)"
    Write-Output "  Enabled      : $enabled"
    Write-Output "  Disabled     : $disabled"
    Write-Output "  Inbound      : $inbound"
    Write-Output "  Outbound     : $outbound"
    Write-Output "  Allow        : $allow"
    Write-Output "  Block        : $block"
    
    # Export if requested
    if ($ExportFormat -ne "None") {
        Write-Progress-Status -Percent 90 -Status "Exporting results..."
        
        if ([string]::IsNullOrWhiteSpace($ExportPath)) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $extension = $ExportFormat.ToLower()
            $ExportPath = Join-Path $PSScriptRoot "firewall-rules-$timestamp.$extension"
        }
        
        if ($ExportFormat -eq "CSV") {
            $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ExportPath
        } elseif ($ExportFormat -eq "JSON") {
            $rows | ConvertTo-Json -Depth 6 | Out-File -Encoding UTF8 -FilePath $ExportPath
        }
        
        Write-Output ""
        Write-Output "Exported to: $ExportPath"
    }
    
    Write-Progress-Status -Percent 100 -Status "Complete"
    Write-Output ""
    Write-Output "Operation completed."
    
} catch {
    Write-Output ""
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output ""
    Write-Output "Common causes:"
    Write-Output "  - NetSecurity PowerShell module not available"
    Write-Output "  - Firewall service not running"
    Write-Output "  - Invalid rule name pattern"
    exit 1
}
