param(
    [string]$DiskNumber = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# Debug log
$log = Join-Path $env:TEMP "populate_max_size_DEBUG.log"
function dlog([string]$m) {
    try { Add-Content -LiteralPath $log -Value ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"), $m) } catch {}
}

dlog "=== populate_max_size.ps1 START ==="
dlog "DiskNumber parameter: '$DiskNumber'"

try {
    if ([string]::IsNullOrWhiteSpace($DiskNumber)) {
        dlog "DiskNumber is empty/null"
        Write-Output "Select a disk first"
        exit 0
    }

    # Support "0  |  Samsung SSD..." format coming from the Disk dropdown
    $dnText = $DiskNumber.Trim()
    dlog "DiskNumber trimmed: '$dnText'"
    
    if ($dnText -like "*  |  *") {
        $dnText = $dnText.Split("  |  ", 2)[0].Trim()
        dlog "DiskNumber after split: '$dnText'"
    }

    $dn = 0
    if (-not [int]::TryParse($dnText, [ref]$dn)) {
        dlog "Failed to parse as integer"
        Write-Output "Invalid disk number"
        exit 0
    }
    
    dlog "Parsed disk number: $dn"

    # Get disk information
    $disk = Get-Disk -Number $dn -ErrorAction Stop
    dlog "Got disk: $($disk.FriendlyName)"
    
    # Check if disk is initialized
    if ($disk.PartitionStyle -eq 'RAW') {
        dlog "Disk is RAW"
        Write-Output "Disk not initialized"
        Write-Output "Please use 'Initialize Disk' module first"
        exit 0
    }
    
    # Get largest free extent
    $freeBytes = $disk.LargestFreeExtent
    dlog "Free bytes: $freeBytes"
    
    if (-not $freeBytes -or $freeBytes -eq 0) {
        dlog "No free space"
        Write-Output "NO FREE SPACE AVAILABLE"
        Write-Output "All space is allocated to partitions"
        exit 0
    }
    
    # Convert to GB and MB
    $freeGB = [math]::Round($freeBytes / 1GB, 2)
    $freeMB = [math]::Round($freeBytes / 1MB, 2)
    dlog "Free GB: $freeGB, Free MB: $freeMB"
    
    # Return space information as dropdown options
    Write-Output "Available: $freeGB GB ($freeMB MB)"
    Write-Output "---"
    Write-Output "You can use: MAX, ${freeGB}GB, or ${freeMB}MB"
    
    # Add helpful size suggestions
    $halfGB = [math]::Round($freeGB / 2, 2)
    Write-Output "Half: ${halfGB}GB"
    
    if ($freeGB -gt 20) {
        $quarterGB = [math]::Round($freeGB / 4, 2)
        Write-Output "Quarter: ${quarterGB}GB"
    }
    
    # Add common sizes that fit
    Write-Output "---"
    Write-Output "Common sizes that fit:"
    foreach ($sizeGB in @(100, 50, 20, 10, 5)) {
        if ($sizeGB -lt $freeGB) {
            Write-Output "${sizeGB}GB"
        }
    }
    
    dlog "Successfully returned size options"
    
}
catch {
    dlog "EXCEPTION: $($_.Exception.ToString())"
    Write-Output "Error: $($_.Exception.Message)"
    exit 0
}
finally {
    dlog "=== populate_max_size.ps1 END ==="
}