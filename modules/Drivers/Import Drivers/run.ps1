param(
    [bool]$WhatIfMode = $true,
    [string]$ImportPath = "C:\DriverBackup",
    [string]$OfflineWindowsPath = "",
    [bool]$Recurse = $true,
    [bool]$ForceUnsigned = $false
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
    Write-Header "DRIVER IMPORT"
    Write-Output ("WhatIf (Dry Run)          : {0}" -f $WhatIfMode)
    Write-Output ("Import Path               : {0}" -f $ImportPath)
    Write-Output ("Offline Windows Path      : {0}" -f $(if ($OfflineWindowsPath) { $OfflineWindowsPath } else { "(Online System)" }))
    Write-Output ("Recursive Scan            : {0}" -f $Recurse)
    Write-Output ("Allow Unsigned Drivers    : {0}" -f $ForceUnsigned)
    Write-Output ""

    Require-Admin
    Write-Progress-Status 10 "Validating paths..."

    # Validate import path
    if ([string]::IsNullOrWhiteSpace($ImportPath)) {
        throw "Import path is required."
    }

    if (-not (Test-Path $ImportPath)) {
        throw "Import path does not exist: $ImportPath"
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
        
        Write-Output "Offline mode: Installing to $OfflineWindowsPath"
    } else {
        Write-Output "Online mode: Installing to current system"
    }

    Write-Progress-Status 30 "Scanning for driver packages..."

    # Find all .inf files
    $searchParams = @{
        Path    = $ImportPath
        Filter  = "*.inf"
        File    = $true
    }
    
    if ($Recurse) {
        $searchParams.Recurse = $true
        Write-Output "Scanning for drivers recursively..."
    } else {
        Write-Output "Scanning for drivers (non-recursive)..."
    }

    $infFiles = @(Get-ChildItem @searchParams -ErrorAction SilentlyContinue)

    if ($infFiles.Count -eq 0) {
        throw "No driver packages (.inf files) found in: $ImportPath"
    }

    Write-Output "Found $($infFiles.Count) driver package(s)"
    Write-Output ""

    Write-Progress-Status 50 "Installing drivers..."

    if ($WhatIfMode) {
        Write-Output "[WhatIf] Would install $($infFiles.Count) driver packages"
        
        # Show sample of what would be installed
        $sample = $infFiles | Select-Object -First 10
        foreach ($inf in $sample) {
            Write-Output "[WhatIf]   - $($inf.Name) ($($inf.DirectoryName))"
        }
        
        if ($infFiles.Count -gt 10) {
            Write-Output "[WhatIf]   ... and $($infFiles.Count - 10) more"
        }
    } else {
        # Import drivers
        $importedCount = 0
        $failedCount = 0
        $skippedCount = 0
        $total = $infFiles.Count
        
        foreach ($i in 0..($infFiles.Count - 1)) {
            $inf = $infFiles[$i]
            $percent = 50 + (($i / $total) * 45)
            Write-Progress-Status ([int]$percent) "Installing driver $($i + 1) of $total..."
            
            try {
                if ($isOffline) {
                    # Import to offline Windows using DISM
                    $dismArgs = @(
                        "/Image:$OfflineWindowsPath"
                        "/Add-Driver"
                        "/Driver:$($inf.FullName)"
                    )
                    
                    if ($ForceUnsigned) {
                        $dismArgs += "/ForceUnsigned"
                    }
                    
                    $dismOutput = & dism.exe $dismArgs 2>&1 | Out-String
                    
                    if ($LASTEXITCODE -eq 0) {
                        $importedCount++
                        Write-Output "Imported: $($inf.Name)"
                    } elseif ($dismOutput -match "already exists" -or $dismOutput -match "already installed") {
                        $skippedCount++
                        Write-Output "[SKIP] Already exists: $($inf.Name)"
                    } else {
                        $failedCount++
                        Write-Output "[WARN] Failed: $($inf.Name) - $($dismOutput -split "`n" | Select-Object -First 1)"
                    }
                } else {
                    # Import to online system using pnputil
                    $pnputilArgs = @(
                        "/add-driver"
                        "`"$($inf.FullName)`""
                        "/install"
                    )
                    
                    if ($ForceUnsigned) {
                        Write-Output "[WARN] ForceUnsigned option not supported for online installation"
                    }
                    
                    $pnpOutput = & pnputil.exe $pnputilArgs 2>&1 | Out-String
                    
                    if ($LASTEXITCODE -eq 0) {
                        if ($pnpOutput -match "Driver package added successfully" -or $pnpOutput -match "successfully") {
                            $importedCount++
                            Write-Output "Imported: $($inf.Name)"
                        } elseif ($pnpOutput -match "already exists" -or $pnpOutput -match "already in") {
                            $skippedCount++
                            Write-Output "[SKIP] Already installed: $($inf.Name)"
                        } else {
                            $importedCount++
                            Write-Output "Imported: $($inf.Name)"
                        }
                    } else {
                        $failedCount++
                        Write-Output "[WARN] Failed: $($inf.Name)"
                    }
                }
            } catch {
                $failedCount++
                Write-Output "[WARN] Error importing $($inf.Name): $($_.Exception.Message)"
            }
        }
        
        Write-Output ""
        Write-Output "Import Summary:"
        Write-Output "  Successfully imported: $importedCount"
        Write-Output "  Already installed/Skipped: $skippedCount"
        Write-Output "  Failed: $failedCount"
        Write-Output "  Total: $total"
        
        if ($isOffline) {
            Write-Output ""
            Write-Output "NOTE: Changes to offline Windows will take effect on next boot."
        } else {
            Write-Output ""
            Write-Output "NOTE: Some drivers may require a system restart to take effect."
        }
    }

    Write-Progress-Status 100 "Done."
    Write-Output ""
    Write-Output "========================================="
    Write-Output "DRIVER IMPORT COMPLETED"
    Write-Output "========================================="
    Write-Output ("Import Location: {0}" -f $ImportPath)
    Write-Output ("Drivers Processed: {0}" -f $(if ($WhatIfMode) { "$($infFiles.Count) (WhatIf)" } else { $total }))
    if (-not $WhatIfMode) {
        Write-Output ("Successfully Imported: {0}" -f $importedCount)
    }
    Write-Output ""
    Write-Output "Operation completed."
    exit 0

} catch {
    Write-Output ""
    Write-Output "========================================="
    Write-Output "ERROR: Driver Import Failed"
    Write-Output "========================================="
    Write-Output ("Error: {0}" -f $_.Exception.Message)
    Write-Output ""
    Write-Output "Common causes:"
    Write-Output "  - Not running as Administrator"
    Write-Output "  - Invalid Windows installation path"
    Write-Output "  - No driver packages found in import path"
    Write-Output "  - Incompatible or corrupted driver packages"
    Write-Output "  - DISM/pnputil not available"
    Write-Output "  - Driver signature verification failed"
    Write-Output ""
    exit 1
}
