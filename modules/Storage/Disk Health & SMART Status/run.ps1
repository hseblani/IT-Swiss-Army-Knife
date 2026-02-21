param(
    [string]$DiskNumber = "",
    [string]$DetailLevel = "Standard",
    [bool]$IncludeSMART = $true,
    [bool]$CheckBadSectors = $false,
    [bool]$ExportReport = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Output functions
function Out-Info([string]$msg) { Write-Output $msg }
function Out-Warn([string]$msg) { Write-Output "[WARNING] $msg" }
function Out-Err([string]$msg) { Write-Output "[ERROR] $msg" }
function Out-Success([string]$msg) { Write-Output "[OK] $msg" }

# Parse dropdown value
function Parse-DropdownValue([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    $value = $value.Trim()
    if ($value -like "*  |  *") {
        $parts = $value.Split(@("  |  "), 2, [StringSplitOptions]::None)
        return $parts[0].Trim()
    }
    return $value
}

# Health status determination
function Get-HealthStatus {
    param(
        [int]$ErrorCount,
        [int]$Temperature,
        [string]$PredictFailure,
        [double]$WearLevel
    )
    
    $issues = @()
    $score = 100
    
    # Check errors
    if ($ErrorCount -gt 100) { 
        $issues += "High error count ($ErrorCount)"
        $score -= 30
    } elseif ($ErrorCount -gt 10) {
        $issues += "Moderate errors ($ErrorCount)"
        $score -= 15
    }
    
    # Check temperature (for HDDs: warning >50°C, critical >60°C; SSDs: >70°C, >80°C)
    if ($Temperature -gt 80) {
        $issues += "Critical temperature (${Temperature}°C)"
        $score -= 25
    } elseif ($Temperature -gt 60) {
        $issues += "High temperature (${Temperature}°C)"
        $score -= 10
    }
    
    # Check prediction
    if ($PredictFailure -eq "True" -or $PredictFailure -eq $true) {
        $issues += "Failure predicted by SMART"
        $score -= 50
    }
    
    # Check wear level (SSDs)
    if ($WearLevel -gt 80) {
        $issues += "High wear level ($WearLevel%)"
        $score -= 20
    } elseif ($WearLevel -gt 50) {
        $issues += "Moderate wear ($WearLevel%)"
        $score -= 10
    }
    
    $score = [Math]::Max(0, $score)
    
    if ($score -ge 90) { $status = "EXCELLENT" }
    elseif ($score -ge 75) { $status = "GOOD" }
    elseif ($score -ge 50) { $status = "FAIR" }
    elseif ($score -ge 25) { $status = "POOR" }
    else { $status = "CRITICAL" }
    
    return @{
        Status = $status
        Score = $score
        Issues = $issues
    }
}

# Format size
function Format-Bytes {
    param([int64]$bytes)
    if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes Bytes"
}

# Format uptime
function Format-PowerOnHours {
    param([int]$hours)
    $days = [Math]::Floor($hours / 24)
    $years = [Math]::Floor($days / 365)
    $remainingDays = $days % 365
    
    if ($years -gt 0) {
        return "$years year(s), $remainingDays day(s) ($hours hours)"
    } else {
        return "$days day(s) ($hours hours)"
    }
}

# Get SMART data using WMI
function Get-SMARTData {
    param([int]$DiskIndex)
    
    try {
        # Try to get SMART data from WMI
        $wmi = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop |
               Where-Object { $_.InstanceName -like "*PhysicalDrive$DiskIndex*" }
        
        $data = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictData -ErrorAction Stop |
                Where-Object { $_.InstanceName -like "*PhysicalDrive$DiskIndex*" }
        
        if ($wmi -and $data) {
            return @{
                Available = $true
                PredictFailure = $wmi.PredictFailure
                Reason = $wmi.Reason
                VendorSpecific = $data.VendorSpecific
            }
        }
    } catch {
        # SMART not available
    }
    
    return @{ Available = $false }
}

# Parse SMART attributes from vendor data
function Parse-SMARTAttributes {
    param([byte[]]$VendorData)
    
    if (-not $VendorData -or $VendorData.Count -lt 362) {
        return @()
    }
    
    $attributes = @()
    
    # SMART attributes start at offset 2, each is 12 bytes
    for ($i = 2; $i -lt 362; $i += 12) {
        $id = $VendorData[$i]
        if ($id -eq 0) { continue }
        
        $flags = [BitConverter]::ToUInt16($VendorData, $i + 1)
        $value = $VendorData[$i + 3]
        $worst = $VendorData[$i + 4]
        $rawValue = [BitConverter]::ToUInt64(@($VendorData[($i + 5)..($i + 11)] + @(0)), 0)
        
        # Common SMART attribute names
        $name = switch ($id) {
            1 { "Read Error Rate" }
            5 { "Reallocated Sectors Count" }
            9 { "Power-On Hours" }
            10 { "Spin Retry Count" }
            12 { "Power Cycle Count" }
            184 { "End-to-End Error" }
            187 { "Reported Uncorrectable Errors" }
            188 { "Command Timeout" }
            190 { "Temperature" }
            194 { "Temperature" }
            195 { "Hardware ECC Recovered" }
            196 { "Reallocation Event Count" }
            197 { "Current Pending Sector Count" }
            198 { "Uncorrectable Sector Count" }
            199 { "UltraDMA CRC Error Count" }
            200 { "Write Error Rate" }
            201 { "Soft Read Error Rate" }
            202 { "Data Address Mark Errors" }
            233 { "Media Wearout Indicator" }
            241 { "Total LBAs Written" }
            242 { "Total LBAs Read" }
            default { "Attribute $id" }
        }
        
        $attributes += [PSCustomObject]@{
            ID = $id
            Name = $name
            Current = $value
            Worst = $worst
            Raw = $rawValue
            Threshold = 0  # Would need threshold data
        }
    }
    
    return $attributes
}

# Main execution
try {
    Out-Info "=========================================="
    Out-Info "DISK HEALTH CHECK & SMART STATUS"
    Out-Info "=========================================="
    Out-Info "Detail Level: $DetailLevel"
    Out-Info ""
    
    # Parse disk selection
    $DiskNumber = Parse-DropdownValue $DiskNumber
    
    # Get disks to check
    if ([string]::IsNullOrWhiteSpace($DiskNumber)) {
        Out-Info "Scanning ALL physical disks..."
        $disksToCheck = Get-PhysicalDisk | Sort-Object DeviceID
    } else {
        $dn = [int]$DiskNumber
        Out-Info "Scanning Disk $dn..."
        $disksToCheck = @(Get-PhysicalDisk | Where-Object DeviceID -eq $dn)
        if ($disksToCheck.Count -eq 0) {
            throw "Disk $dn not found"
        }
    }
    
    Out-Info "Found $($disksToCheck.Count) disk(s) to analyze"
    Out-Info ""
    
    $reportLines = @()
    $reportLines += "DISK HEALTH CHECK REPORT"
    $reportLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $reportLines += "=========================================="
    $reportLines += ""
    
    foreach ($disk in $disksToCheck) {
        $diskNum = $disk.DeviceID
        
        Out-Info "=========================================="
        Out-Info "DISK $diskNum - $($disk.FriendlyName)"
        Out-Info "=========================================="
        
        $reportLines += "=========================================="
        $reportLines += "DISK $diskNum - $($disk.FriendlyName)"
        $reportLines += "=========================================="
        
        # Basic information
        $sizeFormatted = Format-Bytes $disk.Size
        $mediaType = $disk.MediaType
        $busType = $disk.BusType
        $model = $disk.Model
        $serial = $disk.SerialNumber
        $firmwareVersion = $disk.FirmwareVersion
        
        Out-Info "Model         : $model"
        Out-Info "Serial Number : $serial"
        Out-Info "Firmware      : $firmwareVersion"
        Out-Info "Capacity      : $sizeFormatted"
        Out-Info "Media Type    : $mediaType"
        Out-Info "Bus Type      : $busType"
        Out-Info ""
        
        $reportLines += "Model: $model"
        $reportLines += "Serial: $serial"
        $reportLines += "Firmware: $firmwareVersion"
        $reportLines += "Capacity: $sizeFormatted"
        $reportLines += "Media Type: $mediaType"
        $reportLines += "Bus Type: $busType"
        $reportLines += ""
        
        # Get storage reliability counter
        try {
            $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
            
            if ($reliability) {
                $temp = $reliability.Temperature
                $readErrors = $reliability.ReadErrorsTotal
                $writeErrors = $reliability.WriteErrorsTotal
                $powerOnHours = $reliability.PowerOnHours
                $wear = $reliability.Wear
                
                Out-Info "Health Metrics:"
                Out-Info "  Temperature        : ${temp}°C"
                Out-Info "  Read Errors        : $readErrors"
                Out-Info "  Write Errors       : $writeErrors"
                Out-Info "  Power-On Hours     : $(if ($powerOnHours) { Format-PowerOnHours $powerOnHours } else { 'N/A' })"
                if ($null -ne $wear) {
                    Out-Info "  Wear Level         : $wear%"
                }
                Out-Info ""
                
                $reportLines += "Health Metrics:"
                $reportLines += "  Temperature: ${temp}°C"
                $reportLines += "  Read Errors: $readErrors"
                $reportLines += "  Write Errors: $writeErrors"
                $reportLines += "  Power-On Hours: $(if ($powerOnHours) { Format-PowerOnHours $powerOnHours } else { 'N/A' })"
                if ($null -ne $wear) {
                    $reportLines += "  Wear Level: $wear%"
                }
                $reportLines += ""
                
                # Calculate health status
                $totalErrors = $readErrors + $writeErrors
                $healthResult = Get-HealthStatus -ErrorCount $totalErrors -Temperature $temp -PredictFailure $false -WearLevel $(if ($wear) { $wear } else { 0 })
                
                Out-Info "Health Status: $($healthResult.Status) (Score: $($healthResult.Score)/100)"
                $reportLines += "Health Status: $($healthResult.Status) (Score: $($healthResult.Score)/100)"
                
                if ($healthResult.Issues.Count -gt 0) {
                    Out-Info "Issues Found:"
                    $reportLines += "Issues Found:"
                    foreach ($issue in $healthResult.Issues) {
                        Out-Warn "  - $issue"
                        $reportLines += "  WARNING: $issue"
                    }
                } else {
                    Out-Success "No issues detected"
                    $reportLines += "  No issues detected"
                }
                Out-Info ""
                $reportLines += ""
            }
        } catch {
            Out-Info "Reliability counters not available for this disk"
            $reportLines += "Reliability counters not available"
            Out-Info ""
            $reportLines += ""
        }
        
        # SMART Status
        if ($IncludeSMART -and $DetailLevel -ne "Quick Summary") {
            Out-Info "SMART Status:"
            $reportLines += "SMART Status:"
            
            $smartData = Get-SMARTData -DiskIndex $diskNum
            
            if ($smartData.Available) {
                $prediction = if ($smartData.PredictFailure) { "FAILURE PREDICTED!" } else { "OK" }
                Out-Info "  Predict Failure: $prediction"
                $reportLines += "  Predict Failure: $prediction"
                
                if ($smartData.PredictFailure) {
                    Out-Err "  SMART predicts imminent drive failure - BACKUP DATA IMMEDIATELY!"
                    $reportLines += "  ERROR: SMART predicts imminent drive failure!"
                }
                
                # Parse SMART attributes if detailed mode
                if ($DetailLevel -in @("Detailed", "Full Diagnostics") -and $smartData.VendorSpecific) {
                    $attributes = Parse-SMARTAttributes -VendorData $smartData.VendorSpecific
                    
                    if ($attributes.Count -gt 0) {
                        Out-Info ""
                        Out-Info "  Key SMART Attributes:"
                        $reportLines += ""
                        $reportLines += "  Key SMART Attributes:"
                        
                        # Show important attributes
                        $importantIDs = @(5, 9, 187, 188, 190, 194, 196, 197, 198, 199, 233, 241, 242)
                        $importantAttrs = $attributes | Where-Object { $_.ID -in $importantIDs } | Sort-Object ID
                        
                        foreach ($attr in $importantAttrs) {
                            $rawDisplay = switch ($attr.ID) {
                                9 { Format-PowerOnHours $attr.Raw }
                                {$_ -in @(190, 194)} { "$($attr.Raw)°C" }
                                {$_ -in @(241, 242)} { Format-Bytes ($attr.Raw * 512) }
                                default { $attr.Raw }
                            }
                            
                            $status = if ($attr.Current -lt 50) { "[WARN]" } elseif ($attr.Current -lt 100) { "[OK]" } else { "[GOOD]" }
                            Out-Info "    $status $($attr.Name): $rawDisplay (Value: $($attr.Current), Worst: $($attr.Worst))"
                            $reportLines += "    $status $($attr.Name): $rawDisplay (Value: $($attr.Current), Worst: $($attr.Worst))"
                        }
                    }
                }
            } else {
                Out-Info "  SMART data not available (may require admin rights or unsupported hardware)"
                $reportLines += "  SMART data not available"
            }
            Out-Info ""
            $reportLines += ""
        }
        
        # Partition information
        if ($DetailLevel -in @("Standard", "Detailed", "Full Diagnostics")) {
            $partitions = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue
            
            if ($partitions) {
                Out-Info "Partitions: $($partitions.Count)"
                $reportLines += "Partitions: $($partitions.Count)"
                
                foreach ($part in $partitions) {
                    $partSize = Format-Bytes $part.Size
                    $driveLetter = if ($part.DriveLetter) { "$($part.DriveLetter):" } else { "No letter" }
                    $partType = $part.Type
                    
                    Out-Info "  Partition $($part.PartitionNumber): $driveLetter - $partType - $partSize"
                    $reportLines += "  Partition $($part.PartitionNumber): $driveLetter - $partType - $partSize"
                    
                    # Get volume health if drive letter exists
                    if ($part.DriveLetter) {
                        try {
                            $volume = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                            $health = $volume.HealthStatus
                            $fs = $volume.FileSystem
                            $freeSpace = Format-Bytes $volume.SizeRemaining
                            $usedPercent = [Math]::Round((($volume.Size - $volume.SizeRemaining) / $volume.Size) * 100, 1)
                            
                            Out-Info "      Health: $health | FS: $fs | Free: $freeSpace | Used: $usedPercent%"
                            $reportLines += "      Health: $health | FS: $fs | Free: $freeSpace | Used: $usedPercent%"
                        } catch {}
                    }
                }
                Out-Info ""
                $reportLines += ""
            }
        }
        
        # Bad sectors check (if enabled)
        if ($CheckBadSectors) {
            Out-Warn "Bad sector scan requested - this may take several minutes..."
            $reportLines += "Bad Sector Scan: Requested"
            
            try {
                # Use chkdsk to scan for bad sectors (requires admin)
                Out-Info "Running surface scan..."
                
                # Get first volume with drive letter
                $partition = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue | Where-Object DriveLetter | Select-Object -First 1
                
                if ($partition) {
                    $chkdskResult = chkdsk $($partition.DriveLetter): /scan 2>&1
                    
                    # Parse results
                    $badSectors = $chkdskResult | Select-String "bad sectors"
                    
                    if ($badSectors) {
                        Out-Warn "Bad sectors detected: $badSectors"
                        $reportLines += "  WARNING: Bad sectors detected"
                    } else {
                        Out-Success "No bad sectors found"
                        $reportLines += "  No bad sectors found"
                    }
                } else {
                    Out-Info "No formatted volume found for bad sector scan"
                    $reportLines += "  No formatted volume for scan"
                }
            } catch {
                Out-Warn "Bad sector scan failed: $($_.Exception.Message)"
                $reportLines += "  Bad sector scan failed"
            }
            Out-Info ""
            $reportLines += ""
        }
        
        # Recommendations
        if ($DetailLevel -in @("Detailed", "Full Diagnostics")) {
            Out-Info "Recommendations:"
            $reportLines += "Recommendations:"
            
            try {
                $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
                
                if ($reliability) {
                    $temp = $reliability.Temperature
                    $readErrors = $reliability.ReadErrorsTotal
                    $writeErrors = $reliability.WriteErrorsTotal
                    $totalErrors = $readErrors + $writeErrors
                    
                    $recommendations = @()
                    
                    if ($temp -gt 60) {
                        $recommendations += "Improve cooling/ventilation - temperature is elevated"
                    }
                    
                    if ($totalErrors -gt 100) {
                        $recommendations += "Consider disk replacement - high error count"
                        $recommendations += "Ensure regular backups are current"
                    }
                    
                    if ($reliability.PowerOnHours -gt 43800) {  # 5 years
                        $recommendations += "Disk is 5+ years old - consider proactive replacement"
                    }
                    
                    if ($reliability.Wear -gt 80) {
                        $recommendations += "SSD wear level high - plan for replacement soon"
                    }
                    
                    if ($recommendations.Count -gt 0) {
                        foreach ($rec in $recommendations) {
                            Out-Info "  • $rec"
                            $reportLines += "  • $rec"
                        }
                    } else {
                        Out-Success "  Disk appears healthy - no immediate action needed"
                        Out-Info "  • Continue regular backups"
                        Out-Info "  • Monitor temperature periodically"
                        $reportLines += "  Disk appears healthy"
                        $reportLines += "  • Continue regular backups"
                        $reportLines += "  • Monitor temperature"
                    }
                }
            } catch {
                Out-Info "  Unable to generate recommendations"
                $reportLines += "  Unable to generate recommendations"
            }
        }
        
        Out-Info ""
        $reportLines += ""
        $reportLines += ""
    }
    
    # Export report if requested
    if ($ExportReport) {
        $reportPath = Join-Path $env:USERPROFILE "Desktop\disk-health-report.txt"
        try {
            $reportLines | Out-File -FilePath $reportPath -Encoding UTF8
            Out-Success "Report exported to: $reportPath"
        } catch {
            Out-Err "Failed to export report: $($_.Exception.Message)"
        }
    }
    
    Out-Info "=========================================="
    Out-Info "HEALTH CHECK COMPLETED"
    Out-Info "=========================================="
    Out-Info "Scanned $($disksToCheck.Count) disk(s)"
    if ($ExportReport) {
        Out-Info "Report saved to Desktop"
    }
}
catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Out-Info ""
        Out-Info "Stack Trace:"
        Write-Output $_.ScriptStackTrace
    }
    exit 1
}