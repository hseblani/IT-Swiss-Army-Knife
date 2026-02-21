# Add Windows Firewall Rule

param(
    [string]$DisplayName = "SAK - Custom Rule",
    [ValidateSet("Inbound", "Outbound")]
    [string]$Direction = "Inbound",
    [ValidateSet("Allow", "Block")]
    [string]$FirewallAction = "Block",
    [string]$Enabled = "true",
    [ValidateSet("Any", "Domain", "Private", "Public")]
    [string]$Profile = "Any",
    [ValidateSet("TCP", "UDP", "Any")]
    [string]$Protocol = "TCP",
    [string]$LocalPort = "",
    [string]$RemotePort = "",
    [string]$Program = "",
    [string]$Service = "",
    [string]$LocalAddress = "",
    [string]$RemoteAddress = "",
    [string]$Description = "Created by IT Swiss-Army Knife",
    [string]$WhatIf = "true"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Output "ERROR: Administrator privileges required to add firewall rules."
    Write-Output "Please run the toolkit as Administrator."
    exit 1
}

try {
    Write-Output "========================================="
    Write-Output "ADD FIREWALL RULE"
    Write-Output "========================================="
    Write-Output ""
    
    $doWhatIf = ($WhatIf -eq "true")
    if ($doWhatIf) {
        Write-Output "MODE: DRY RUN (WhatIf) - No actual changes will be made"
        Write-Output ""
    }
    
    Write-Progress-Status -Percent 10 -Status "Validating inputs..."
    
    # Validate required fields
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        throw "Display Name is required."
    }
    
    # Check if rule already exists
    $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
    if ($existing) {
        throw "A firewall rule with the name '$DisplayName' already exists. Please use a unique name."
    }
    
    # Build parameters
    $args = @{
        DisplayName = $DisplayName
        Direction   = $Direction
        Action      = $FirewallAction
        Enabled     = $(if ($Enabled -eq "true") { "True" } else { "False" })
        Description = $Description
        Group       = "IT Swiss-Army Knife"
    }
    
    if ($Profile -ne "Any") { $args["Profile"] = $Profile }
    if ($Protocol -ne "Any") { $args["Protocol"] = $Protocol }
    
    if (-not [string]::IsNullOrWhiteSpace($LocalPort)) { $args["LocalPort"] = $LocalPort }
    if (-not [string]::IsNullOrWhiteSpace($RemotePort)) { $args["RemotePort"] = $RemotePort }
    
    if (-not [string]::IsNullOrWhiteSpace($Program)) { $args["Program"] = $Program }
    if (-not [string]::IsNullOrWhiteSpace($Service)) { $args["Service"] = $Service }
    
    if (-not [string]::IsNullOrWhiteSpace($LocalAddress)) { $args["LocalAddress"] = $LocalAddress }
    if (-not [string]::IsNullOrWhiteSpace($RemoteAddress)) { $args["RemoteAddress"] = $RemoteAddress }
    
    Write-Output "Rule Configuration:"
    Write-Output ""
    $args.GetEnumerator() | Sort-Object Name | ForEach-Object { 
        Write-Output ("  {0,-15}: {1}" -f $_.Key, $_.Value) 
    }
    Write-Output ""
    
    Write-Progress-Status -Percent 50 -Status "Creating firewall rule..."
    
    if ($doWhatIf) {
        New-NetFirewallRule @args -WhatIf
        Write-Output ""
        Write-Output "[DRY RUN] Rule would be created with the above configuration."
        Write-Output "Uncheck 'Dry Run' to actually create the rule."
    } else {
        New-NetFirewallRule @args | Out-Null
        Write-Output ""
        Write-Output "[OK] Firewall rule '$DisplayName' created successfully!"
    }
    
    Write-Progress-Status -Percent 100 -Status "Complete"
    Write-Output ""
    Write-Output "Operation completed."
    
} catch {
    Write-Output ""
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output ""
    Write-Output "Common causes:"
    Write-Output "  - Rule name already exists (must be unique)"
    Write-Output "  - Invalid port number or range"
    Write-Output "  - Invalid IP address or CIDR notation"
    Write-Output "  - Program file path doesn't exist"
    Write-Output "  - Invalid service name"
    exit 1
}
