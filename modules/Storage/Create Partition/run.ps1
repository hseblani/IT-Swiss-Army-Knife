param(
    [bool]$WhatIfMode = $true,
    [string]$DiskNumber = "",
    [string]$AvailableSpaceInfo = "",
    [string]$Size = "MAX",
    [string]$FileSystem = "NTFS",
    [string]$VolumeLabel = "",
    [string]$DriveLetter = ""
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

function Parse-SizeBytes([string]$s, [UInt64]$maxBytes) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $maxBytes }
    $s = $s.Trim().ToUpperInvariant()
    if ($s -eq "MAX") { return $maxBytes }

    $m = [regex]::Match($s, '^(?<n>\d+(?:\.\d+)?)\s*(?<u>MB|GB)$')
    if (-not $m.Success) { throw "Invalid Size '$s'. Use like 50GB, 10240MB, or MAX." }
    $n = [double]$m.Groups["n"].Value
    $u = $m.Groups["u"].Value
    $bytes = if ($u -eq "GB") { [UInt64]($n * 1GB) } else { [UInt64]($n * 1MB) }
    return $bytes
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
    
    Out-Info "=== Create Partition ==="
    Out-Info "WhatIfMode: $WhatIfMode"
    Out-Info "DiskNumber: $dn"
    Out-Info "Size      : $Size"
    Out-Info "FileSystem: $FileSystem"
    if (-not [string]::IsNullOrWhiteSpace($VolumeLabel)) {
        Out-Info "Label     : $VolumeLabel"
    }
    if (-not [string]::IsNullOrWhiteSpace($DriveLetter)) {
        Out-Info "DriveLetter: $DriveLetter"
    }
    Out-Info ""
    
    # Get disk and check free space
    $disk = Get-Disk -Number $dn -ErrorAction Stop
    
    if ($disk.PartitionStyle -eq 'RAW') {
        throw "Disk $dn is not initialized. Please initialize the disk first."
    }
    
    $freeBytes = $disk.LargestFreeExtent
    if (-not $freeBytes -or $freeBytes -eq 0) {
        throw "Disk $dn has no free space available for a new partition."
    }
    
    $freeMB = [math]::Round($freeBytes / 1MB, 2)
    $freeGB = [math]::Round($freeBytes / 1GB, 2)
    
    Out-Info "Disk Information:"
    Out-Info "  Friendly Name   : $($disk.FriendlyName)"
    Out-Info "  Total Size      : $([math]::Round($disk.Size / 1GB, 2)) GB"
    Out-Info "  Available Space : $freeGB GB ($freeMB MB)"
    Out-Info ""
    
    $sizeBytes = Parse-SizeBytes $Size $freeBytes
    
    if ($sizeBytes -gt $freeBytes) {
        $requestedGB = [math]::Round($sizeBytes / 1GB, 2)
        throw "Requested size ($requestedGB GB) exceeds available free space ($freeGB GB)."
    }
    
    $requestedSizeGB = [math]::Round($sizeBytes / 1GB, 2)
    Out-Info "Partition will be created with size: $requestedSizeGB GB"
    Out-Info ""
    
    # Create partition
    $npArgs = @{ 
        DiskNumber = $dn
        Size       = $sizeBytes 
    }
    
    if (-not [string]::IsNullOrWhiteSpace($DriveLetter)) {
        $letter = $DriveLetter.Trim().TrimEnd(":").ToUpper()
        if ($letter.Length -ne 1 -or $letter -notmatch '^[A-Z]$') {
            throw "Drive letter must be a single letter (A-Z)."
        }
        $npArgs["DriveLetter"] = $letter
    }
    
    if ($WhatIfMode) { 
        Out-Info "[WHATIF MODE] Would create partition with parameters:"
        Out-Info "  DiskNumber: $dn"
        Out-Info "  Size: $([math]::Round($sizeBytes / 1GB, 2)) GB"
        Out-Info "  FileSystem: $FileSystem"
        if ($npArgs.ContainsKey("DriveLetter")) {
            Out-Info "  DriveLetter: $($npArgs['DriveLetter'])"
        }
        if (-not [string]::IsNullOrWhiteSpace($VolumeLabel)) {
            Out-Info "  VolumeLabel: $VolumeLabel"
        }
        Out-Info ""
        Out-Info "[WHATIF MODE] Partition creation simulated. No actual changes made."
    }
    else {
        Out-Info "Creating partition on Disk $dn..."
        $part = New-Partition @npArgs
        
        if ($part) {
            Out-Info "[OK] Partition created: Number $($part.PartitionNumber), Size $([math]::Round($part.Size / 1GB, 2)) GB"
            
            # Format the partition
            $fmtArgs = @{ 
                Partition  = $part
                FileSystem = $FileSystem
                Confirm    = $false 
            }
            
            if (-not [string]::IsNullOrWhiteSpace($VolumeLabel)) { 
                $fmtArgs["NewFileSystemLabel"] = $VolumeLabel 
            }
            
            Out-Info "Formatting partition as $FileSystem..."
            $vol = Format-Volume @fmtArgs
            
            if ($vol) {
                Out-Info "[OK] Partition formatted successfully."
                
                # Wait a moment for Windows to assign drive letter
                Start-Sleep -Milliseconds 500
                
                # Refresh partition info to get auto-assigned drive letter
                $part = Get-Partition -DiskNumber $dn -PartitionNumber $part.PartitionNumber
                
                if ($part.DriveLetter) {
                    Out-Info "[OK] Drive Letter: $($part.DriveLetter):"
                }
                elseif ($vol.DriveLetter) {
                    Out-Info "[OK] Drive Letter: $($vol.DriveLetter):"
                }
                else {
                    # One more attempt - check volume by unique ID
                    Start-Sleep -Milliseconds 500
                    $allVolumes = Get-Volume
                    $matchedVol = $allVolumes | Where-Object { 
                        $_.Size -eq $part.Size -and 
                        $_.FileSystem -eq $FileSystem 
                    } | Select-Object -First 1
                    
                    if ($matchedVol -and $matchedVol.DriveLetter) {
                        Out-Info "[OK] Drive Letter: $($matchedVol.DriveLetter): (auto-assigned)"
                    }
                    else {
                        Out-Info "[INFO] No drive letter assigned (may be a system/recovery partition)"
                    }
                }
                
                if ($vol.FileSystemLabel) {
                    Out-Info "[OK] Volume Label: $($vol.FileSystemLabel)"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($VolumeLabel)) {
                    Out-Info "[OK] Volume Label: $VolumeLabel"
                }
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