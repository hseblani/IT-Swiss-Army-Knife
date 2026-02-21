param(
    [bool]$WhatIfMode = $true,
    [string]$Operation = "List Drive Letters",
    [string]$DiskNumber = "",
    [string]$PartitionNumber = "",
    [string]$CurrentDriveLetter = "",
    [string]$NewDriveLetter = ""
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

function Normalize-DriveLetter([string]$letter) {
    if ([string]::IsNullOrWhiteSpace($letter)) { return "" }
    $letter = $letter.Trim().ToUpper()
    # Remove colon if present
    $letter = $letter.TrimEnd(":")
    # Should be single letter A-Z
    if ($letter.Length -eq 1 -and $letter -match '^[A-Z]$') {
        return $letter
    }
    return ""
}

try {
    # Parse dropdown values
    $DiskNumber = Parse-DropdownValue $DiskNumber
    $PartitionNumber = Parse-DropdownValue $PartitionNumber
    
    Out-Info "=== Drive Letters Manager ==="
    Out-Info "WhatIfMode: $WhatIfMode"
    Out-Info "Operation : $Operation"
    Out-Info ""
    
    switch ($Operation) {
        
        "List Drive Letters" {
            Out-Info "All Volumes and Their Drive Letters:"
            Out-Info "=========================================="
            
            $volumes = Get-Volume | Where-Object { $_.DriveType -ne 'Unknown' } | Sort-Object DriveLetter
            
            if ($volumes.Count -eq 0) {
                Out-Info "[INFO] No volumes found."
            }
            else {
                foreach ($vol in $volumes) {
                    $letter = if ($vol.DriveLetter) { "$($vol.DriveLetter):" } else { "No Letter" }
                    $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(no label)" }
                    $sizeGB = [math]::Round($vol.Size / 1GB, 2)
                    $fs = $vol.FileSystem
                    $health = $vol.HealthStatus
                    
                    Out-Info "$letter - $label - $sizeGB GB - $fs - $health"
                }
            }
            
            Out-Info ""
            Out-Info "Partitions Without Drive Letters:"
            Out-Info "=========================================="
            
            $allPartitions = Get-Partition | Where-Object { $_.Type -ne 'Unknown' } | Sort-Object DiskNumber, PartitionNumber
            $noLetter = $allPartitions | Where-Object { -not $_.DriveLetter }
            
            if ($noLetter.Count -eq 0) {
                Out-Info "[INFO] All partitions have drive letters assigned."
            }
            else {
                foreach ($part in $noLetter) {
                    $sizeGB = [math]::Round($part.Size / 1GB, 2)
                    Out-Info "Disk $($part.DiskNumber) Partition $($part.PartitionNumber) - $($part.Type) - $sizeGB GB"
                }
            }
        }
        
        "Assign Drive Letter" {
            if ([string]::IsNullOrWhiteSpace($DiskNumber)) {
                throw "Please select a disk from the dropdown."
            }
            
            if ([string]::IsNullOrWhiteSpace($PartitionNumber)) {
                throw "Please select a partition from the dropdown."
            }
            
            if ([string]::IsNullOrWhiteSpace($NewDriveLetter)) {
                throw "Please enter a drive letter (A-Z) in the 'New Drive Letter' field."
            }
            
            $dn = 0
            if (-not [int]::TryParse($DiskNumber.Trim(), [ref]$dn)) {
                throw "DiskNumber must be an integer (got '$DiskNumber')."
            }
            
            $pn = 0
            if (-not [int]::TryParse($PartitionNumber.Trim(), [ref]$pn)) {
                throw "PartitionNumber must be an integer (got '$PartitionNumber')."
            }
            
            $newLetter = Normalize-DriveLetter $NewDriveLetter
            if ([string]::IsNullOrWhiteSpace($newLetter)) {
                throw "Drive letter must be a single letter A-Z. You entered: '$NewDriveLetter'"
            }
            
            Out-Info "DiskNumber     : $dn"
            Out-Info "PartitionNumber: $pn"
            Out-Info "NewDriveLetter : $newLetter"
            Out-Info ""
            
            # Get the partition
            $partition = Get-Partition -DiskNumber $dn -PartitionNumber $pn -ErrorAction Stop
            
            # Check if partition already has a drive letter
            if ($partition.DriveLetter) {
                Out-Info "[WARNING] Partition already has drive letter: $($partition.DriveLetter):"
                Out-Info "[INFO] Use 'Change Drive Letter' operation to modify it."
                throw "Partition already has a drive letter. Cannot assign."
            }
            
            # Check if the drive letter is already in use
            $existing = Get-Volume | Where-Object { $_.DriveLetter -eq $newLetter }
            if ($existing) {
                throw "Drive letter ${newLetter}: is already in use by another volume."
            }
            
            if ($WhatIfMode) {
                Out-Info "[WHATIF MODE] Would assign drive letter ${newLetter}: to Disk $dn Partition $pn"
            }
            else {
                Out-Info "Assigning drive letter ${newLetter}: to partition..."
                Set-Partition -DiskNumber $dn -PartitionNumber $pn -NewDriveLetter $newLetter
                Out-Info "[OK] Drive letter ${newLetter}: assigned successfully."
            }
        }
        
        "Change Drive Letter" {
            $currentLetter = Normalize-DriveLetter $CurrentDriveLetter
            if ([string]::IsNullOrWhiteSpace($currentLetter)) {
                throw "Please enter the current drive letter (A-Z) to change."
            }
            
            $newLetter = Normalize-DriveLetter $NewDriveLetter
            if ([string]::IsNullOrWhiteSpace($newLetter)) {
                throw "Please enter the new drive letter (A-Z)."
            }
            
            Out-Info "CurrentDriveLetter: $currentLetter"
            Out-Info "NewDriveLetter    : $newLetter"
            Out-Info ""
            
            # Get the volume with current drive letter
            $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $currentLetter }
            if (-not $volume) {
                throw "No volume found with drive letter ${currentLetter}:"
            }
            
            # Check if new drive letter is already in use
            $existingNew = Get-Volume | Where-Object { $_.DriveLetter -eq $newLetter }
            if ($existingNew) {
                throw "Drive letter ${newLetter}: is already in use by another volume."
            }
            
            # Get partition for the volume
            $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $currentLetter }
            if (-not $partition) {
                throw "Could not find partition for drive letter ${currentLetter}:"
            }
            
            $sizeGB = [math]::Round($volume.Size / 1GB, 2)
            $label = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "(no label)" }
            
            Out-Info "Volume Information:"
            Out-Info "  Current Letter: ${currentLetter}:"
            Out-Info "  Label         : $label"
            Out-Info "  Size          : $sizeGB GB"
            Out-Info "  File System   : $($volume.FileSystem)"
            Out-Info ""
            
            if ($WhatIfMode) {
                Out-Info "[WHATIF MODE] Would change drive letter from ${currentLetter}: to ${newLetter}:"
            }
            else {
                Out-Info "Changing drive letter from ${currentLetter}: to ${newLetter}:..."
                Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter $newLetter
                Out-Info "[OK] Drive letter changed successfully from ${currentLetter}: to ${newLetter}:"
            }
        }
        
        "Remove Drive Letter" {
            $currentLetter = Normalize-DriveLetter $CurrentDriveLetter
            if ([string]::IsNullOrWhiteSpace($currentLetter)) {
                throw "Please enter the drive letter (A-Z) to remove."
            }
            
            Out-Info "CurrentDriveLetter: $currentLetter"
            Out-Info ""
            
            # Get the volume with this drive letter
            $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $currentLetter }
            if (-not $volume) {
                throw "No volume found with drive letter ${currentLetter}:"
            }
            
            # Get partition
            $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $currentLetter }
            if (-not $partition) {
                throw "Could not find partition for drive letter ${currentLetter}:"
            }
            
            $sizeGB = [math]::Round($volume.Size / 1GB, 2)
            $label = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "(no label)" }
            
            Out-Info "Volume Information:"
            Out-Info "  Drive Letter: ${currentLetter}:"
            Out-Info "  Label       : $label"
            Out-Info "  Size        : $sizeGB GB"
            Out-Info "  File System : $($volume.FileSystem)"
            Out-Info "  Disk        : $($partition.DiskNumber)"
            Out-Info "  Partition   : $($partition.PartitionNumber)"
            Out-Info ""
            
            Out-Info "[WARNING] Removing drive letter will make this volume inaccessible!"
            Out-Info "[WARNING] Programs and services may fail if they use this drive letter."
            Out-Info ""
            
            if ($WhatIfMode) {
                Out-Info "[WHATIF MODE] Would remove drive letter ${currentLetter}:"
                Out-Info "[WHATIF MODE] AccessPath to remove: ${currentLetter}:\"
            }
            else {
                Out-Info "Removing drive letter ${currentLetter}:..."
                
                try {
                    # Get all access paths for this partition
                    $accessPaths = (Get-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber).AccessPaths
                    Out-Info "[DEBUG] Current access paths: $($accessPaths -join ', ')"
                    
                    # The drive letter access path format is "D:\"
                    $pathToRemove = "${currentLetter}:\"
                    
                    if ($accessPaths -notcontains $pathToRemove) {
                        throw "Access path ${pathToRemove} not found in partition's access paths."
                    }
                    
                    # Remove the drive letter access path
                    Remove-PartitionAccessPath -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $pathToRemove -Confirm:$false -ErrorAction Stop
                    
                    Out-Info "[OK] Drive letter ${currentLetter}: removed successfully."
                    Out-Info "[INFO] Partition is still accessible via Disk Management or by assigning a new letter."
                    
                    # Verify removal
                    Start-Sleep -Milliseconds 500
                    $checkPartition = Get-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
                    if ($checkPartition.DriveLetter) {
                        Out-Info "[WARNING] Drive letter still shows as: $($checkPartition.DriveLetter):"
                        Out-Info "[INFO] This may take a moment to update. Refresh in Disk Management to verify."
                    }
                    else {
                        Out-Info "[VERIFIED] Drive letter has been removed."
                    }
                    
                }
                catch {
                    $errMsg = $_.Exception.Message
                    Out-Info "[ERROR] Primary method failed: $errMsg"
                    Out-Info "[INFO] Trying diskpart method..."
                    
                    try {
                        # Alternative method using diskpart
                        $diskpartScript = @"
select volume $currentLetter
remove letter=$currentLetter
"@
                        $tempFile = Join-Path $env:TEMP "diskpart_remove_letter.txt"
                        $diskpartScript | Out-File -FilePath $tempFile -Encoding ASCII -Force
                        
                        $result = diskpart /s $tempFile 2>&1 | Out-String
                        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                        
                        Out-Info "[DEBUG] Diskpart output:"
                        Out-Info $result
                        
                        if ($result -like "*successfully*" -or $result -notlike "*error*") {
                            Out-Info "[OK] Drive letter ${currentLetter}: removed successfully (using diskpart)."
                            Out-Info "[INFO] Partition is still accessible via Disk Management."
                        }
                        else {
                            throw "Diskpart failed to remove drive letter."
                        }
                        
                    }
                    catch {
                        throw "Failed to remove drive letter using both methods: $($_.Exception.Message)"
                    }
                }
            }
        }
        
        default {
            throw "Unknown operation: $Operation"
        }
    }
    
    Out-Info ""
    Out-Info "=== Done ==="
}
catch {
    Out-Info ""
    Out-Info "=========================================="
    Out-Info "ERROR"
    Out-Info "=========================================="
    Out-Err $_.Exception.Message
    Out-Info ""
    Out-Info "[TIP] Make sure all required fields are filled:"
    Out-Info "  - For Assign: Select Disk, Partition, and enter New Drive Letter"
    Out-Info "  - For Change: Enter Current and New Drive Letters"
    Out-Info "  - For Remove: Enter Current Drive Letter"
    Out-Info "=========================================="
    exit 1
}