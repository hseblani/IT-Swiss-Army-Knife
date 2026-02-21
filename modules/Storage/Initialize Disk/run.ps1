param(
    [bool]$WhatIfMode = $true,
    [string]$DiskNumber = "",
    [string]$PartitionStyle = "GPT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference = "None"
$ProgressPreference = "SilentlyContinue"

function Out-Info([string]$msg) { Write-Output $msg }
function Out-Err([string]$msg) { Write-Output "[ERROR] $msg" }

# Parse dropdown value format: "0  |  Samsung SSD (500 GB) - SATA" -> "0"
function Parse-DropdownValue([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    $value = $value.Trim()
    
    if ($value -like "*  |  *") {
        $parts = $value.Split(@("  |  "), 2, [StringSplitOptions]::None)
        return $parts[0].Trim()
    }
    
    return $value
}

try {
    # Parse dropdown value
    $DiskNumber = Parse-DropdownValue $DiskNumber
    
    if ([string]::IsNullOrWhiteSpace($DiskNumber)) {
        throw "DiskNumber is required."
    }
    
    $dn = 0
    if (-not [int]::TryParse($DiskNumber.Trim(), [ref]$dn)) {
        throw "DiskNumber must be an integer (got '$DiskNumber')."
    }
    
    if ($PartitionStyle -notin @("GPT", "MBR")) {
        throw "PartitionStyle must be either 'GPT' or 'MBR'."
    }
    
    Out-Info "=== Initialize Disk ==="
    Out-Info "WhatIfMode    : $WhatIfMode"
    Out-Info "DiskNumber    : $dn"
    Out-Info "PartitionStyle: $PartitionStyle"
    Out-Info ""
    
    # Get disk info
    $disk = Get-Disk -Number $dn -ErrorAction Stop
    
    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
    
    Out-Info "Disk Information:"
    Out-Info "  Friendly Name: $($disk.FriendlyName)"
    Out-Info "  Size         : $sizeGB GB"
    Out-Info "  Bus Type     : $($disk.BusType)"
    Out-Info "  Current Style: $($disk.PartitionStyle)"
    Out-Info ""
    
    # Check if already initialized
    if ($disk.PartitionStyle -ne 'RAW') {
        Out-Info "[WARNING] Disk $dn is already initialized as $($disk.PartitionStyle)."
        Out-Info "[INFO] If you want to reinitialize, you must first clean the disk."
        Out-Info ""
        Out-Info "=== Done (No action taken) ==="
        exit 0
    }
    
    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would initialize Disk $dn as $PartitionStyle"
        Out-Info ""
        Out-Info "[WHATIF MODE] No actual changes made."
    }
    else {
        Out-Info "Initializing Disk $dn as $PartitionStyle..."
        
        $initArgs = @{
            Number         = $dn
            PartitionStyle = $PartitionStyle
        }
        
        Initialize-Disk @initArgs | Out-Null
        
        Out-Info ""
        Out-Info "[OK] Disk initialized successfully as $PartitionStyle."
        Out-Info "[OK] You can now create partitions on this disk."
    }
    
    Out-Info ""
    Out-Info "=== Done ==="
}
catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}