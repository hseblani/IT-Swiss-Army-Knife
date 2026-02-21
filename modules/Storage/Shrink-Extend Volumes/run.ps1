param(
    [bool]$WhatIfMode = $true,
    [string]$Operation = "List Volumes",
    [string]$DriveLetter = "",
    [string]$SizeChange = "MAX"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference = "None"
$ProgressPreference = "SilentlyContinue"

function Out-Info([string]$msg) { Write-Output $msg }
function Out-Err([string]$msg) { Write-Output "[ERROR] $msg" }

function Parse-DropdownValue([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    $value = $value.Trim()
    
    # Handle format: "> C < 0-1  |  ..."
    if ($value -match '^\s*>\s*([A-Z])\s*<') {
        return $matches[1]
    }
    
    # Handle format: "C  |  C: Windows..."
    if ($value -like "*  |  *") {
        $parts = $value.Split(@("  |  "), 2, [StringSplitOptions]::None)
        return $parts[0].Trim()
    }
    
    return $value
}

function Normalize-DriveLetter([string]$letter) {
    if ([string]::IsNullOrWhiteSpace($letter)) { return "" }
    
    # First parse dropdown format if present
    $letter = Parse-DropdownValue $letter
    
    $letter = $letter.Trim().ToUpper()
    # Remove colon if present
    $letter = $letter.TrimEnd(":")
    # Should be single letter A-Z
    if ($letter.Length -eq 1 -and $letter -match '^[A-Z]$') {
        return $letter
    }
    return ""
}

function Parse-SizeBytes([string]$s, [UInt64]$maxBytes) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $maxBytes }
    $s = $s.Trim().ToUpperInvariant()
    if ($s -eq "MAX") { return $maxBytes }

    $m = [regex]::Match($s, '^(?<n>\d+(?:\.\d+)?)\s*(?<u>MB|GB)$')
    if (-not $m.Success) { 
        throw "Invalid size format '$s'. Use: 10GB, 5120MB, or MAX" 
    }
    $n = [double]$m.Groups["n"].Value
    $u = $m.Groups["u"].Value
    $bytes = if ($u -eq "GB") { [UInt64]($n * 1GB) } else { [UInt64]($n * 1MB) }
    return $bytes
}

try {
    Out-Info "=========================================="
    Out-Info "SHRINK/EXTEND VOLUMES"
    Out-Info "=========================================="
    Out-Info "Operation : $Operation"
    Out-Info "WhatIf    : $WhatIfMode"
    Out-Info ""
    
    switch ($Operation) {
        
        "List Volumes" {
            Out-Info "Available Volumes:"
            Out-Info "------------------------------------------"
            
            $volumes = Get-Volume | Where-Object { $_.DriveType -ne 'Unknown' -and $_.DriveLetter } | Sort-Object DriveLetter
            
            if ($volumes.Count -eq 0) {
                Out-Info "[INFO] No volumes found with drive letters."
                Out-Info ""
            }
            else {
                foreach ($vol in $volumes) {
                    $letter = "$($vol.DriveLetter):"
                    $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "(no label)" }
                    $totalGB = [math]::Round($vol.Size / 1GB, 2)
                    $usedGB = [math]::Round(($vol.Size - $vol.SizeRemaining) / 1GB, 2)
                    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
                    $usedPercent = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
                    
                    Out-Info "$letter $label"
                    Out-Info "    Total: $totalGB GB  |  Used: $usedGB GB ($usedPercent%)  |  Free: $freeGB GB"
                    Out-Info "    File System: $($vol.FileSystem)  |  Health: $($vol.HealthStatus)"
                    Out-Info ""
                }
            }
            
            Out-Info "[TIP] Use 'Get Maximum Shrink Size' to check resize limits"
        }
        
        "Get Maximum Shrink Size" {
            $driveLetter = Normalize-DriveLetter $DriveLetter
            if ([string]::IsNullOrWhiteSpace($driveLetter)) {
                throw "Please select a volume from the dropdown."
            }
            
            # Get partition for this drive letter
            $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $driveLetter }
            if (-not $partition) {
                throw "No partition found with drive letter ${driveLetter}:"
            }
            
            # Get volume info
            $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
            
            Out-Info "Volume: ${driveLetter}:"
            Out-Info "------------------------------------------"
            Out-Info "Label         : $(if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { '(no label)' })"
            Out-Info "File System   : $($volume.FileSystem)"
            Out-Info "Total Size    : $([math]::Round($volume.Size / 1GB, 2)) GB"
            Out-Info "Used Space    : $([math]::Round(($volume.Size - $volume.SizeRemaining) / 1GB, 2)) GB"
            Out-Info "Free Space    : $([math]::Round($volume.SizeRemaining / 1GB, 2)) GB"
            Out-Info ""
            
            # Get supported sizes
            try {
                $supportedSizes = Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
                
                $currentSizeGB = [math]::Round($partition.Size / 1GB, 2)
                $minSizeGB = [math]::Round($supportedSizes.SizeMin / 1GB, 2)
                $maxSizeGB = [math]::Round($supportedSizes.SizeMax / 1GB, 2)
                
                $maxShrinkGB = [math]::Round($currentSizeGB - $minSizeGB, 2)
                $maxExtendGB = [math]::Round($maxSizeGB - $currentSizeGB, 2)
                
                Out-Info "Resize Limits:"
                Out-Info "------------------------------------------"
                Out-Info "Current Size      : $currentSizeGB GB"
                Out-Info "Minimum Size      : $minSizeGB GB"
                Out-Info "Maximum Size      : $maxSizeGB GB"
                Out-Info ""
                Out-Info "Max Shrink Amount : $maxShrinkGB GB"
                Out-Info "Max Extend Amount : $maxExtendGB GB"
                Out-Info ""
                
                if ($maxShrinkGB -gt 0) {
                    Out-Info "[OK] Can shrink by up to $maxShrinkGB GB"
                    Out-Info "[TIP] Use 'MAX' or specify amount (e.g., ${maxShrinkGB}GB, 10GB)"
                }
                else {
                    Out-Info "[WARNING] Cannot shrink further - at minimum size"
                    Out-Info "[TIP] Try defragmenting the volume first"
                }
                
                if ($maxExtendGB -gt 0) {
                    Out-Info ""
                    Out-Info "[OK] Can extend by up to $maxExtendGB GB"
                }
                else {
                    Out-Info ""
                    Out-Info "[INFO] No adjacent free space to extend"
                }
                
            }
            catch {
                throw "Failed to get resize limits: $($_.Exception.Message)"
            }
        }
        
        "Shrink Volume" {
            $driveLetter = Normalize-DriveLetter $DriveLetter
            if ([string]::IsNullOrWhiteSpace($driveLetter)) {
                throw "Please select a volume from the dropdown."
            }
            
            # Get partition
            $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $driveLetter }
            if (-not $partition) {
                throw "No partition found with drive letter ${driveLetter}:"
            }
            
            # Get volume
            $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
            $label = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "(no label)" }
            
            # Get supported sizes
            $supportedSizes = Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
            
            $currentSize = $partition.Size
            $minSize = $supportedSizes.SizeMin
            $maxShrinkBytes = $currentSize - $minSize
            
            if ($maxShrinkBytes -le 0) {
                throw "Cannot shrink ${driveLetter}: - already at minimum size. Try defragmenting first."
            }
            
            # Parse size change
            $shrinkBytes = Parse-SizeBytes $SizeChange $maxShrinkBytes
            
            if ($shrinkBytes -gt $maxShrinkBytes) {
                $maxShrinkGB = [math]::Round($maxShrinkBytes / 1GB, 2)
                $requestedGB = [math]::Round($shrinkBytes / 1GB, 2)
                throw "Requested $requestedGB GB exceeds maximum shrinkable space of $maxShrinkGB GB"
            }
            
            $newSize = $currentSize - $shrinkBytes
            
            $currentGB = [math]::Round($currentSize / 1GB, 2)
            $shrinkGB = [math]::Round($shrinkBytes / 1GB, 2)
            $newGB = [math]::Round($newSize / 1GB, 2)
            
            Out-Info "Shrink Volume: ${driveLetter}: $label"
            Out-Info "------------------------------------------"
            Out-Info "Current Size  : $currentGB GB"
            Out-Info "Shrink By     : $shrinkGB GB"
            Out-Info "New Size      : $newGB GB"
            Out-Info "Free Space    : $shrinkGB GB will be released"
            Out-Info ""
            
            if ($WhatIfMode) {
                Out-Info "[WHATIF MODE] No changes made"
                Out-Info "[WHATIF MODE] Would shrink ${driveLetter}: from $currentGB GB to $newGB GB"
            }
            else {
                Out-Info "Shrinking volume... (this may take several minutes)"
                
                Resize-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Size $newSize
                
                Out-Info ""
                Out-Info "=========================================="
                Out-Info "[SUCCESS] Volume shrunk successfully!"
                Out-Info "=========================================="
                Out-Info "Volume ${driveLetter}: $label"
                Out-Info "New Size: $newGB GB"
                Out-Info "Released: $shrinkGB GB of free disk space"
            }
        }
        
        "Extend Volume" {
            $driveLetter = Normalize-DriveLetter $DriveLetter
            if ([string]::IsNullOrWhiteSpace($driveLetter)) {
                throw "Please select a volume from the dropdown."
            }
            
            # Get partition
            $partition = Get-Partition | Where-Object { $_.DriveLetter -eq $driveLetter }
            if (-not $partition) {
                throw "No partition found with drive letter ${driveLetter}:"
            }
            
            # Get volume
            $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
            $label = if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { "(no label)" }
            
            # Get supported sizes
            $supportedSizes = Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
            
            $currentSize = $partition.Size
            $maxSize = $supportedSizes.SizeMax
            $maxExtendBytes = $maxSize - $currentSize
            
            if ($maxExtendBytes -le 0) {
                throw "Cannot extend ${driveLetter}: - no adjacent free space available"
            }
            
            # Parse size change
            $extendBytes = Parse-SizeBytes $SizeChange $maxExtendBytes
            
            if ($extendBytes -gt $maxExtendBytes) {
                $maxExtendGB = [math]::Round($maxExtendBytes / 1GB, 2)
                $requestedGB = [math]::Round($extendBytes / 1GB, 2)
                throw "Requested $requestedGB GB exceeds available space of $maxExtendGB GB"
            }
            
            $newSize = $currentSize + $extendBytes
            
            $currentGB = [math]::Round($currentSize / 1GB, 2)
            $extendGB = [math]::Round($extendBytes / 1GB, 2)
            $newGB = [math]::Round($newSize / 1GB, 2)
            
            Out-Info "Extend Volume: ${driveLetter}: $label"
            Out-Info "------------------------------------------"
            Out-Info "Current Size  : $currentGB GB"
            Out-Info "Extend By     : $extendGB GB"
            Out-Info "New Size      : $newGB GB"
            Out-Info ""
            
            if ($WhatIfMode) {
                Out-Info "[WHATIF MODE] No changes made"
                Out-Info "[WHATIF MODE] Would extend ${driveLetter}: from $currentGB GB to $newGB GB"
            }
            else {
                Out-Info "Extending volume..."
                
                Resize-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Size $newSize
                
                Out-Info ""
                Out-Info "=========================================="
                Out-Info "[SUCCESS] Volume extended successfully!"
                Out-Info "=========================================="
                Out-Info "Volume ${driveLetter}: $label"
                Out-Info "New Size: $newGB GB"
                Out-Info "Added: $extendGB GB"
            }
        }
        
        default {
            throw "Unknown operation: $Operation"
        }
    }
    
    Out-Info ""
    Out-Info "=========================================="
    Out-Info "OPERATION COMPLETED"
    Out-Info "=========================================="
}
catch {
    Out-Info ""
    Out-Info "=========================================="
    Out-Info "ERROR"
    Out-Info "=========================================="
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { 
        Out-Info ""
        Out-Info "Stack Trace:"
        Write-Output $_.ScriptStackTrace 
    }
    Out-Info "=========================================="
    exit 1
}