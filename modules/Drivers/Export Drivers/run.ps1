param(
    [bool]$WhatIfMode = $true,
    [string]$ExportPath = "C:\DriverBackup",
    [string]$OfflineWindowsPath = "",
    [bool]$ThirdPartyOnly = $true,
    [bool]$CreateReport = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'

function Write-Progress-Status { 
    param([int]$Percent, [string]$Status) 
    Write-Output "[PROGRESS:$Percent] $Status" 
}

function Write-Header([string]$title) {
    Write-Output "========================================="
    Write-Output $title
    Write-Output "========================================="
}

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Is-Admin)) { 
        throw "Administrator privileges are required. Please run the toolkit as Administrator." 
    }
}

try {
    Write-Header "DRIVER EXPORT"
    Write-Output ("WhatIf (Dry Run)          : {0}" -f $WhatIfMode)
    Write-Output ("Export Path               : {0}" -f $ExportPath)
    Write-Output ("Offline Windows Path      : {0}" -f $(if ($OfflineWindowsPath) { $OfflineWindowsPath } else { "(Online System)" }))
    Write-Output ("3rd-Party Drivers Only    : {0}" -f $ThirdPartyOnly)
    Write-Output ("Create CSV Report         : {0}" -f $CreateReport)
    Write-Output ""

    Require-Admin
    Write-Progress-Status 10 "Validating paths..."

    # Validate export path
    if ([string]::IsNullOrWhiteSpace($ExportPath)) {
        throw "Export path is required."
    }

    $isOffline = -not [string]::IsNullOrWhiteSpace($OfflineWindowsPath)

    # Validate offline Windows path if provided
    if ($isOffline) {
        if (-not (Test-Path $OfflineWindowsPath)) {
            throw "Offline Windows path does not exist: $OfflineWindowsPath"
        }
        
        # Check if it's a valid Windows installation
        $systemRoot = Join-Path $OfflineWindowsPath "System32"
        if (-not (Test-Path $systemRoot)) {
            throw "Invalid Windows installation path. System32 folder not found in: $OfflineWindowsPath"
        }
        
        Write-Output "Offline mode: Exporting from $OfflineWindowsPath"
    } else {
        Write-Output "Online mode: Exporting from current system"
    }

    # Create export directory
    if ($WhatIfMode) {
        Write-Output "[WhatIf] Would create export directory: $ExportPath"
    } else {
        if (-not (Test-Path $ExportPath)) {
            New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
            Write-Output "Created export directory: $ExportPath"
        } else {
            Write-Output "Using existing export directory: $ExportPath"
        }
    }

    Write-Progress-Status 30 "Enumerating drivers..."

    # Get drivers
    if ($isOffline) {
        # Offline driver enumeration using DISM
        $dismArgs = @(
            "/Image:$OfflineWindowsPath"
            "/Get-Drivers"
            "/Format:Table"
        )
        
        Write-Output "Running DISM to enumerate offline drivers..."
        $dismOutput = & dism.exe $dismArgs 2>&1 | Out-String
        
        if ($LASTEXITCODE -ne 0) {
            throw "DISM failed to enumerate drivers. Exit code: $LASTEXITCODE`n$dismOutput"
        }
        
        # Parse DISM output to get driver list
        $driverLines = $dismOutput -split "`n" | Where-Object { $_ -match "oem\d+\.inf" }
        
        if ($driverLines.Count -eq 0) {
            throw "No drivers found in offline Windows installation"
        }
        
        Write-Output "Found $($driverLines.Count) driver packages in offline system"
        
        $drivers = @()
        foreach ($line in $driverLines) {
            if ($line -match "^(oem\d+\.inf)\s+:\s+(.+)") {
                $infName = $matches[1]
                $providerName = $matches[2].Trim()
                
                $drivers += [PSCustomObject]@{
                    OriginalFileName = $infName
                    ProviderName     = $providerName
                    ClassName        = "Unknown"
                    DriverVersion    = "Unknown"
                    Date             = "Unknown"
                    IsThirdParty     = ($providerName -notmatch "Microsoft")
                }
            }
        }
    } else {
        # Online driver enumeration using Get-WindowsDriver or pnputil
        Write-Output "Enumerating installed drivers..."
        
        # Try using pnputil (more reliable)
        $pnpOutput = & pnputil.exe /enum-drivers 2>&1 | Out-String
        
        if ($LASTEXITCODE -eq 0) {
            # Parse pnputil output
            $driverBlocks = $pnpOutput -split "Published Name" | Where-Object { $_ -match "oem\d+\.inf" }
            
            $drivers = @()
            foreach ($block in $driverBlocks) {
                $infMatch = $block -match ":\s+(oem\d+\.inf)"
                $providerMatch = $block -match "Provider Name\s+:\s+(.+)"
                $classMatch = $block -match "Class Name\s+:\s+(.+)"
                $versionMatch = $block -match "Driver Version\s+:\s+(.+)"
                $dateMatch = $block -match "Date\s+:\s+(.+)"
                
                if ($infMatch) {
                    $providerName = if ($providerMatch) { $matches[1].Trim() } else { "Unknown" }
                    
                    $drivers += [PSCustomObject]@{
                        OriginalFileName = $matches[1]
                        ProviderName     = $providerName
                        ClassName        = if ($classMatch) { $matches[1].Trim() } else { "Unknown" }
                        DriverVersion    = if ($versionMatch) { $matches[1].Trim() } else { "Unknown" }
                        Date             = if ($dateMatch) { $matches[1].Trim() } else { "Unknown" }
                        IsThirdParty     = ($providerName -notmatch "Microsoft")
                    }
                }
            }
        } else {
            throw "Failed to enumerate drivers using pnputil"
        }
        
        Write-Output "Found $($drivers.Count) driver packages on system"
    }

    # Filter 3rd-party drivers if requested
    if ($ThirdPartyOnly) {
        $driversToExport = $drivers | Where-Object { $_.IsThirdParty }
        Write-Output "Filtered to $($driversToExport.Count) third-party drivers"
    } else {
        $driversToExport = $drivers
    }

    if ($driversToExport.Count -eq 0) {
        Write-Output ""
        Write-Output "No drivers to export based on current filters."
        Write-Progress-Status 100 "Done."
        exit 0
    }

    Write-Progress-Status 50 "Exporting drivers..."

    if ($WhatIfMode) {
        Write-Output "[WhatIf] Would export $($driversToExport.Count) drivers to: $ExportPath"
        
        # Show sample of what would be exported
        $sample = $driversToExport | Select-Object -First 5
        foreach ($driver in $sample) {
            Write-Output "[WhatIf]   - $($driver.OriginalFileName) ($($driver.ProviderName))"
        }
        
        if ($driversToExport.Count -gt 5) {
            Write-Output "[WhatIf]   ... and $($driversToExport.Count - 5) more"
        }
    } else {
        # Export drivers
        $exportedCount = 0
        $failedCount = 0
        $total = $driversToExport.Count
        
        foreach ($i in 0..($driversToExport.Count - 1)) {
            $driver = $driversToExport[$i]
            $percent = 50 + (($i / $total) * 40)
            Write-Progress-Status ([int]$percent) "Exporting driver $($i + 1) of $total..."
            
            try {
                if ($isOffline) {
                    # Export from offline Windows using DISM
                    $driverExportPath = Join-Path $ExportPath $driver.OriginalFileName.Replace('.inf', '')
                    
                    $dismExportArgs = @(
                        "/Image:$OfflineWindowsPath"
                        "/Export-Driver"
                        "/Destination:$driverExportPath"
                    )
                    
                    $null = & dism.exe $dismExportArgs 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        $exportedCount++
                        Write-Output "Exported: $($driver.OriginalFileName) ($($driver.ProviderName))"
                    } else {
                        $failedCount++
                        Write-Output "[WARN] Failed to export: $($driver.OriginalFileName)"
                    }
                } else {
                    # Export from online system using pnputil
                    $driverExportPath = Join-Path $ExportPath $driver.OriginalFileName.Replace('.inf', '')
                    
                    if (-not (Test-Path $driverExportPath)) {
                        New-Item -Path $driverExportPath -ItemType Directory -Force | Out-Null
                    }
                    
                    $null = & pnputil.exe /export-driver $driver.OriginalFileName $driverExportPath 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        $exportedCount++
                        Write-Output "Exported: $($driver.OriginalFileName) ($($driver.ProviderName))"
                    } else {
                        $failedCount++
                        Write-Output "[WARN] Failed to export: $($driver.OriginalFileName)"
                    }
                }
            } catch {
                $failedCount++
                Write-Output "[WARN] Error exporting $($driver.OriginalFileName): $($_.Exception.Message)"
            }
        }
        
        Write-Output ""
        Write-Output "Export Summary:"
        Write-Output "  Successfully exported: $exportedCount"
        Write-Output "  Failed: $failedCount"
        Write-Output "  Total: $total"
    }

    # Create CSV report if requested
    if ($CreateReport) {
        Write-Progress-Status 95 "Creating driver inventory report..."
        
        $reportPath = Join-Path $ExportPath "DriverInventory.csv"
        
        if ($WhatIfMode) {
            Write-Output "[WhatIf] Would create driver report: $reportPath"
        } else {
            try {
                $driversToExport | Select-Object OriginalFileName, ProviderName, ClassName, DriverVersion, Date, IsThirdParty |
                    Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
                
                Write-Output ""
                Write-Output "Driver inventory report created: $reportPath"
            } catch {
                Write-Output "[WARN] Failed to create CSV report: $($_.Exception.Message)"
            }
        }
    }

    Write-Progress-Status 100 "Done."
    Write-Output ""
    Write-Output "========================================="
    Write-Output "DRIVER EXPORT COMPLETED"
    Write-Output "========================================="
    Write-Output ("Export Location: {0}" -f $ExportPath)
    Write-Output ("Drivers Exported: {0}" -f $(if ($WhatIfMode) { "$($driversToExport.Count) (WhatIf)" } else { $exportedCount }))
    Write-Output ""
    Write-Output "Operation completed."
    exit 0

} catch {
    Write-Output ""
    Write-Output "========================================="
    Write-Output "ERROR: Driver Export Failed"
    Write-Output "========================================="
    Write-Output ("Error: {0}" -f $_.Exception.Message)
    Write-Output ""
    Write-Output "Common causes:"
    Write-Output "  - Not running as Administrator"
    Write-Output "  - Invalid Windows installation path"
    Write-Output "  - Insufficient disk space"
    Write-Output "  - Export path not accessible"
    Write-Output "  - DISM/pnputil not available"
    Write-Output ""
    exit 1
}
