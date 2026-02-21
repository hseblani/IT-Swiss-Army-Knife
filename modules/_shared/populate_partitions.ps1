#Requires -RunAsAdministrator

param(
    [string]$DiskNumber = ""
)

# Ensure output encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$ProgressPreference = 'SilentlyContinue'

try {
    # Check if DiskNumber is provided
    if ([string]::IsNullOrWhiteSpace($DiskNumber)) {
        Write-Output "Select a disk first"
        return
    }
    
    # Extract disk number from the dropdown format: "0 - Samsung SSD..." or "0  |  Samsung..."
    $diskNum = $null
    if ($DiskNumber -match '^(\d+)\s*[-|]') {
        $diskNum = [int]$matches[1]
    }
    elseif ($DiskNumber -like "*  |  *") {
        $parts = $DiskNumber.Split("  |  ", 2)
        $diskNum = [int]$parts[0].Trim()
    }
    elseif ($DiskNumber -match '^\d+$') {
        $diskNum = [int]$DiskNumber
    }
    else {
        Write-Output "Invalid disk selection"
        return
    }
    
    # Force refresh storage cache
    Update-HostStorageCache -ErrorAction SilentlyContinue
    
    # Get partitions for the selected disk
    $partitions = @(Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)
    
    if ($partitions.Count -eq 0) {
        Write-Output "No partitions on this disk"
        return
    }
    
    foreach ($part in $partitions) {
        try {
            # Try multiple methods to get drive letter
            $driveLetter = $part.DriveLetter
            
            if (-not $driveLetter) {
                # Method 2: Try via volume
                $volume = Get-Volume -Partition $part -ErrorAction SilentlyContinue
                if ($volume -and $volume.DriveLetter) {
                    $driveLetter = $volume.DriveLetter
                }
            }
            
            if (-not $driveLetter) {
                # Method 3: Query all volumes and match by partition
                $allVolumes = Get-Volume -ErrorAction SilentlyContinue
                foreach ($vol in $allVolumes) {
                    try {
                        $volPart = Get-Partition -Volume $vol -ErrorAction SilentlyContinue
                        if ($volPart -and 
                            $volPart.DiskNumber -eq $diskNum -and 
                            $volPart.PartitionNumber -eq $part.PartitionNumber -and
                            $vol.DriveLetter) {
                            $driveLetter = $vol.DriveLetter
                            break
                        }
                    }
                    catch {
                        continue
                    }
                }
            }
            
            # Format drive letter display
            $driveLetterDisplay = if ($driveLetter) { "${driveLetter}:" } else { "(No letter)" }
            
            # Get volume for label (if not already retrieved)
            if (-not $volume) {
                $volume = Get-Volume -Partition $part -ErrorAction SilentlyContinue
            }
            
            # Format label
            $label = if ($volume -and $volume.FileSystemLabel) { $volume.FileSystemLabel } else { "(No label)" }
            
            # Format size
            $sizeGB = [math]::Round($part.Size / 1GB, 2)
            
            # Format type
            $partType = if ($part.Type) { $part.Type } else { "Unknown" }
            
            # Output format: "1  |  C: Windows (237.00 GB) - Basic"
            # Use partition number as the key, full info as display
            $displayText = "{0} {1} ({2} GB) - {3}" -f $driveLetterDisplay, $label, $sizeGB, $partType
            Write-Output "$($part.PartitionNumber)  |  $displayText"
        }
        catch {
            # Skip partitions that cause errors
            continue
        }
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}