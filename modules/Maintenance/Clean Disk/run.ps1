param(
    [bool]$WhatIfMode = $true,
    [string]$DiskNumber = "",
    [bool]$ConfirmClean = $false
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
    
    Out-Info "=== Clean Disk ==="
    Out-Info "WhatIfMode  : $WhatIfMode"
    Out-Info "DiskNumber  : $dn"
    Out-Info "ConfirmClean: $ConfirmClean"
    Out-Info ""
    
    # Get disk info
    $disk = Get-Disk -Number $dn -ErrorAction Stop
    
    # Safety check: Don't allow cleaning boot/system disk
    if ($disk.IsBoot -or $disk.IsSystem) {
        throw "SAFETY BLOCK: Cannot clean boot or system disk! Disk $dn is a critical system disk."
    }
    
    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
    
    Out-Info "*** DISK TO BE CLEANED ***"
    Out-Info "  Friendly Name : $($disk.FriendlyName)"
    Out-Info "  Size          : $sizeGB GB"
    Out-Info "  Bus Type      : $($disk.BusType)"
    Out-Info "  Partition Style: $($disk.PartitionStyle)"
    Out-Info ""
    
    # Show current partitions
    $partitions = @(Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue)
    if ($partitions.Count -gt 0) {
        Out-Info "Partitions that will be removed:"
        foreach ($p in $partitions) {
            $pSizeGB = [math]::Round($p.Size / 1GB, 2)
            $driveInfo = if ($p.DriveLetter) { "$($p.DriveLetter):" } else { "No drive letter" }
            Out-Info "  Partition $($p.PartitionNumber): $driveInfo, $($p.Type), $pSizeGB GB"
        }
        Out-Info ""
    }
    else {
        Out-Info "Disk has no partitions (already clean/RAW)."
        Out-Info ""
    }
    
    # Check confirmation checkbox
    if (-not $ConfirmClean -and -not $WhatIfMode) {
        throw "You must check the 'I understand all data will be lost' checkbox to proceed."
    }
    
    Out-Info "=========================================================="
    Out-Info "         *** EXTREME DANGER WARNING ***"
    Out-Info ""
    Out-Info "  This will REMOVE ALL PARTITIONS from Disk $dn"
    Out-Info "  ALL DATA on this disk will be PERMANENTLY LOST!"
    Out-Info ""
    Out-Info "  Disk: $($disk.FriendlyName)"
    Out-Info "  Size: $sizeGB GB"
    Out-Info "=========================================================="
    Out-Info ""
    
    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would clean Disk $dn (remove all partitions)"
    }
    else {
        Out-Info "Cleaning Disk $dn - Removing all partitions..."
    }
    
    if ($WhatIfMode) {
        Out-Info ""
        Out-Info "[WHATIF MODE] No actual changes made."
        Out-Info "[WHATIF MODE] When executed, disk will be returned to RAW state."
    }
    else {
        $cleanArgs = @{
            Number     = $dn
            RemoveData = $true
            RemoveOEM  = $true
            Confirm    = $false
        }
        
        Clear-Disk @cleanArgs | Out-Null
        
        Out-Info ""
        Out-Info "[OK] Disk cleaned successfully."
        Out-Info "[OK] All partitions have been removed."
        Out-Info "[OK] Disk is now in RAW/uninitialized state."
        Out-Info "[INFO] Use 'Initialize Disk' to prepare disk for new partitions."
    }
    
    Out-Info ""
    Out-Info "=== Done ==="
}
catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}