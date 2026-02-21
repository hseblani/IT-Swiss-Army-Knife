param(
    [bool]$WhatIfMode = $true,
    [string]$DiskNumber = "",
    [string]$PartitionNumber = "",
    [string]$FileSystem = "NTFS",
    [string]$VolumeLabel = ""
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
    
    Out-Info "=== Format Partition ==="
    Out-Info "WhatIfMode     : $WhatIfMode"
    Out-Info "DiskNumber     : $dn"
    Out-Info "PartitionNumber: $pn"
    Out-Info "FileSystem     : $FileSystem"
    if (-not [string]::IsNullOrWhiteSpace($VolumeLabel)) {
        Out-Info "VolumeLabel    : $VolumeLabel"
    }
    Out-Info ""
    
    # Get partition and volume info
    $part = Get-Partition -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop
    $vol = $part | Get-Volume -ErrorAction Stop
    
    if (-not $vol.DriveLetter) {
        throw "Partition does not have a drive letter assigned. Cannot format without drive letter."
    }
    
    $sizeGB = [math]::Round($vol.Size / 1GB, 2)
    
    Out-Info "Current Partition Information:"
    Out-Info "  Drive Letter: $($vol.DriveLetter):"
    Out-Info "  File System : $($vol.FileSystem)"
    Out-Info "  Size        : $sizeGB GB"
    if ($vol.FileSystemLabel) {
        Out-Info "  Label       : $($vol.FileSystemLabel)"
    }
    Out-Info ""
    
    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would format partition as $FileSystem"
    } else {
        Out-Info "[WARNING] Formatting partition $pn (Drive $($vol.DriveLetter):) as $FileSystem..."
        Out-Info "[WARNING] All data on this partition will be permanently lost!"
    }
    
    $fmtArgs = @{ 
        DriveLetter = $vol.DriveLetter
        FileSystem = $FileSystem
        Confirm = $false 
    }
    
    if (-not [string]::IsNullOrWhiteSpace($VolumeLabel)) { 
        $fmtArgs["NewFileSystemLabel"] = $VolumeLabel 
    }
    
    if ($WhatIfMode) { 
        $fmtArgs["WhatIf"] = $true 
    }
    
    $result = Format-Volume @fmtArgs
    
    if ($WhatIfMode) {
        Out-Info ""
        Out-Info "[WHATIF MODE] No actual changes made."
    } else {
        Out-Info ""
        Out-Info "[OK] Partition formatted successfully."
        if ($result) {
            Out-Info "[OK] Drive Letter: $($result.DriveLetter):"
            Out-Info "[OK] File System: $($result.FileSystem)"
            if ($result.FileSystemLabel) {
                Out-Info "[OK] Volume Label: $($result.FileSystemLabel)"
            }
        }
    }
    
    Out-Info ""
    Out-Info "=== Done ==="
}
catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}
