param(
    [string]$Operation = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$log = Join-Path $env:TEMP "populate_volumes_DEBUG.log"
function dlog([string]$m) {
    try { Add-Content -LiteralPath $log -Value ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"), $m) } catch {}
}

dlog "=== populate_volumes.ps1 START ==="
dlog "Operation=$Operation"

try {
    # Force refresh of partition cache
    Update-HostStorageCache -ErrorAction SilentlyContinue

    # Get all partitions (fresh data)
    $partitions = Get-Partition | Where-Object { $_.Type -ne 'Unknown' } | Sort-Object DiskNumber, PartitionNumber

    dlog "Total partitions found: $($partitions.Count)"

    if ($partitions.Count -eq 0) {
        Write-Output "No partitions found"
        exit 0
    }

    foreach ($part in $partitions) {
        $driveLetter = $part.DriveLetter
        $label = ""
        $sizeGB = [math]::Round($part.Size / 1GB, 2)
        $typeInfo = $part.Type

        dlog "Processing partition: Disk $($part.DiskNumber) Part $($part.PartitionNumber), DriveLetter=$driveLetter"

        if ($driveLetter) {
            # Partition has a drive letter
            # Try to get volume info for label
            try {
                $volume = Get-Volume | Where-Object { $_.DriveLetter -eq $driveLetter }
                if ($volume -and $volume.FileSystemLabel) {
                    $label = $volume.FileSystemLabel
                } else {
                    $label = "(no label)"
                }
                $fs = $volume.FileSystem
            } catch {
                $label = "(no label)"
                $fs = "Unknown"
            }

            $displayText = "$label ($sizeGB GB) - $fs"
            Write-Output "-> $driveLetter <-   $($part.DiskNumber)-$($part.PartitionNumber)  |  $displayText"
            dlog "Added with letter: $driveLetter - $displayText"

        } else {
            # Partition without drive letter - double-check with volume query
            try {
                # Try to find volume by matching partition
                $volumes = Get-Volume -ErrorAction SilentlyContinue
                $matchedVolume = $volumes | Where-Object {
                    $volumePartition = Get-Partition -Volume $_ -ErrorAction SilentlyContinue
                    $volumePartition -and
                    $volumePartition.DiskNumber -eq $part.DiskNumber -and
                    $volumePartition.PartitionNumber -eq $part.PartitionNumber
                } | Select-Object -First 1

                if ($matchedVolume -and $matchedVolume.DriveLetter) {
                    # Found drive letter via volume query!
                    $driveLetter = $matchedVolume.DriveLetter
                    $label = if ($matchedVolume.FileSystemLabel) { $matchedVolume.FileSystemLabel } else { "(no label)" }
                    $fs = $matchedVolume.FileSystem

                    $displayText = "${driveLetter}: $label ($sizeGB GB) - $fs"
                    Write-Output "$driveLetter  |  $displayText"
                    dlog "Added with letter (via volume): $driveLetter - $displayText"
                } else {
                    # Truly no drive letter
                    $identifier = "-> NA <- $($part.DiskNumber)-$($part.PartitionNumber)"
                    $displayText = "Disk $($part.DiskNumber) Partition $($part.PartitionNumber) ($sizeGB GB) - $typeInfo"
                    Write-Output "$identifier  |  [No Letter] $displayText"
                    dlog "Added without letter: $identifier - $displayText"
                }
            } catch {
                # Fallback to no letter
                $identifier = "NONE-$($part.DiskNumber)-$($part.PartitionNumber)"
                $displayText = "Disk $($part.DiskNumber) Partition $($part.PartitionNumber) ($sizeGB GB) - $typeInfo"
                Write-Output "$identifier  |  [No Letter] $displayText"
                dlog "Added without letter (catch): $identifier - $displayText"
            }
        }
    }

    dlog "Successfully populated volume list"

} catch {
    dlog "EXCEPTION: $($_.Exception.ToString())"
    Write-Output "ERROR: $($_.Exception.Message)"
} finally {
    dlog "=== populate_volumes.ps1 END ==="
}