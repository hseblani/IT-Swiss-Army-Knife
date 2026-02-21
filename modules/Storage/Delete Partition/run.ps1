param(
    [bool]$WhatIfMode = $true,
    [string]$DiskNumber = "",
    [string]$PartitionNumber = ""
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
    # Parse dropdown values
    $DiskNumber = Parse-DropdownValue $DiskNumber
    $PartitionNumber = Parse-DropdownValue $PartitionNumber
    
    if ([string]::IsNullOrWhiteSpace($DiskNumber)) {
        throw "DiskNumber is required."
    }
    
    if ([string]::IsNullOrWhiteSpace($PartitionNumber)) {
        throw "PartitionNumber is required."
    }
    
    $dn = 0
    if (-not [int]::TryParse($DiskNumber.Trim(), [ref]$dn)) {
        throw "DiskNumber must be an integer (got '$DiskNumber')."
    }
    
    $pn = 0
    if (-not [int]::TryParse($PartitionNumber.Trim(), [ref]$pn)) {
        throw "PartitionNumber must be an integer (got '$PartitionNumber')."
    }
    
    Out-Info "=== Delete Partition ==="
    Out-Info "WhatIfMode     : $WhatIfMode"
    Out-Info "DiskNumber     : $dn"
    Out-Info "PartitionNumber: $pn"
    Out-Info ""
    
    # Get partition info before deletion
    $part = Get-Partition -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop
    
    $sizeGB = [math]::Round($part.Size / 1GB, 2)
    $driveInfo = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "No drive letter" }
    
    Out-Info "Partition Information:"
    Out-Info "  Type       : $($part.Type)"
    Out-Info "  Drive      : $driveInfo"
    Out-Info "  Size       : $sizeGB GB"
    Out-Info ""
    
    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would delete partition $pn from disk $dn"
    } else {
        Out-Info "[WARNING] Deleting partition $pn from disk $dn..."
        Out-Info "[WARNING] All data on this partition will be permanently lost!"
    }
    
    $rmArgs = @{ 
        InputObject = $part
        Confirm = $false 
    }
    
    if ($WhatIfMode) { 
        $rmArgs["WhatIf"] = $true 
    }
    
    Remove-Partition @rmArgs | Out-Null
    
    if ($WhatIfMode) {
        Out-Info ""
        Out-Info "[WHATIF MODE] No actual changes made."
    } else {
        Out-Info ""
        Out-Info "[OK] Partition deleted successfully."
    }
    
    Out-Info ""
    Out-Info "=== Done ==="
}
catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}
