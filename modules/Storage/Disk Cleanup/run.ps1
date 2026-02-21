# Advanced Disk Cleanup Tool

param(
    [string]$TargetDrive = "C:",
    [string]$CleanTempFiles = "true",
    [string]$CleanWindowsUpdate = "true",
    [string]$CleanRecycleBin = "true",
    [string]$CleanBrowserCache = "false",
    [string]$CleanThumbnails = "true",
    [string]$CleanErrorReports = "true",
    [string]$CleanOldWindows = "false",
    [string]$CleanDeliveryOptimization = "true",
    [string]$CleanDownloads = "false",
    [string]$DryRun = "false",
    [int]$MinFileAge = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Shared helpers (includes Write-ToolkitProgress)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

# Ensure drive has colon
if ($TargetDrive -notmatch ':$') { $TargetDrive += ':' }

$script:TotalFreed = 0
$script:IsDryRun = ($DryRun -eq "true")
$script:MinAgeDays = $MinFileAge

function Update-ToolkitProgress {
    param(
        [Parameter(Mandatory = $true)][int]$Percent,
        [Parameter()][string]$Status = ""
    )

    # Prefer the shared helper (toolkit runner progress bar)
    if (Get-Command -Name Write-ToolkitProgress -ErrorAction SilentlyContinue) {
        # Do not spam console output: leave Status empty unless you explicitly want it shown.
        if ([string]::IsNullOrWhiteSpace($Status)) {
            Write-ToolkitProgress -Percent $Percent
        } else {
            Write-ToolkitProgress -Percent $Percent -Status $Status
        }
        return
    }

    # Fallback (should rarely happen): emit runner-compatible progress markers
    if ([string]::IsNullOrWhiteSpace($Status)) {
        Write-Output "[PROGRESS:$Percent]"
    } else {
        Write-Output "[PROGRESS:$Percent] $Status"
    }
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $size) { return 0 }
        return $size
    } catch {
        return 0
    }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else { return "$Bytes bytes" }
}

function Remove-PathSafely {
    param(
        [string]$Path,
        [string]$Description,
        [switch]$IsFolder
    )

    if (-not (Test-Path $Path)) {
        Write-Host "  [SKIP] $Description - Not found, skipping"
        return 0
    }

    $sizeBefore = Get-FolderSize -Path $Path

    if ($script:IsDryRun) {
        Write-Host ("  [DRY] $Description - Would free: " + (Format-Bytes $sizeBefore))
        return $sizeBefore
    }

    try {
        if ($IsFolder) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        } else {
            Remove-Item -Path $Path -Force -ErrorAction Stop
        }
        Write-Host ("  [OK] $Description - Freed: " + (Format-Bytes $sizeBefore))
        return $sizeBefore
    } catch {
        Write-Host ("  [ERROR] $Description - Error: " + $_.Exception.Message)
        return 0
    }
}

function Clean-OldFiles {
    param(
        [string]$Path,
        [string]$Description,
        [string]$Filter = "*"
    )

    if (-not (Test-Path $Path)) {
        Write-Host "  [SKIP] $Description - Not found, skipping"
        return 0
    }

    $cutoffDate = (Get-Date).AddDays(-$script:MinAgeDays)

    try {
        $files = @(Get-ChildItem -Path $Path -Filter $Filter -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoffDate })

        if ($files.Count -eq 0) {
            Write-Host "  [SKIP] $Description - No files to clean"
            return 0
        }

        $sizeBefore = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sizeBefore) { $sizeBefore = 0 }

        if ($script:IsDryRun) {
            Write-Host ("  [DRY] $Description - Would free: " + (Format-Bytes $sizeBefore) + " ($($files.Count) files)")
            return $sizeBefore
        }

        $files | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host ("  [OK] $Description - Freed: " + (Format-Bytes $sizeBefore) + " ($($files.Count) files)")
        return $sizeBefore
    } catch {
        Write-Host ("  [ERROR] $Description - Error: " + $_.Exception.Message)
        return 0
    }
}

Write-Output "========================================="
Write-Output "ADVANCED DISK CLEANUP"
Write-Output "========================================="
Write-Output ""
Write-Output "Target Drive: $TargetDrive"
if ($script:IsDryRun) {
    Write-Output "Mode: DRY RUN (no files will be deleted)"
} else {
    Write-Output "Mode: LIVE CLEANUP"
}
Write-Output "Minimum File Age: $script:MinAgeDays days"
Write-Output ""

# Check if drive exists
if (-not (Test-Path $TargetDrive)) {
    Write-Output "ERROR: Drive $TargetDrive not found!"
    exit 1
}

# Get initial disk space
Update-ToolkitProgress -Percent 5 -Status "Analyzing disk space..."
$driveLetter = $TargetDrive.TrimEnd(':')
$driveInfo = Get-PSDrive -Name $driveLetter
$spaceBeforeGB = [Math]::Round($driveInfo.Free / 1GB, 2)
Write-Output ("Disk space before: " + (Format-Bytes $driveInfo.Free))
Write-Output ""

# Clean Temporary Files
if ($CleanTempFiles -eq "true") {
    Update-ToolkitProgress -Percent 10 -Status "Cleaning temporary files..."
    Write-Output "Cleaning Temporary Files..."

    $freed = Clean-OldFiles -Path "$TargetDrive\Windows\Temp" -Description "Windows Temp"
    $script:TotalFreed += $freed

    $freed = Clean-OldFiles -Path "$env:TEMP" -Description "User Temp"
    $script:TotalFreed += $freed

    # All user temp folders
    $userProfiles = Get-ChildItem "$TargetDrive\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($user in $userProfiles) {
        if ($user.Name -notin @('Public', 'Default', 'Default User')) {
            $tempPath = Join-Path $user.FullName "AppData\Local\Temp"
            $freed = Clean-OldFiles -Path $tempPath -Description "Temp ($($user.Name))"
            $script:TotalFreed += $freed
        }
    }
    Write-Output ""
}

# Clean Windows Update
if ($CleanWindowsUpdate -eq "true") {
    Update-ToolkitProgress -Percent 25 -Status "Cleaning Windows Update cache..."
    Write-Output "Cleaning Windows Update Cache..."

    # Stop Windows Update service
    if (-not $script:IsDryRun) {
        Write-Output "  Stopping Windows Update service..."
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    }

    $freed = Clean-OldFiles -Path "$TargetDrive\Windows\SoftwareDistribution\Download" -Description "Update Downloads"
    $script:TotalFreed += $freed

    if (-not $script:IsDryRun) {
        Write-Output "  Starting Windows Update service..."
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    }
    Write-Output ""
}

# Clean Recycle Bin
if ($CleanRecycleBin -eq "true") {
    Update-ToolkitProgress -Percent 35 -Status "Emptying Recycle Bin..."
    Write-Output "Emptying Recycle Bin..."

    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(0xA)
        $items = $recycleBin.Items()

        if ($items.Count -eq 0) {
            Write-Host "  [SKIP] Recycle Bin is already empty"
        } else {
            $sizeBefore = 0
            foreach ($item in $items) {
                $sizeBefore += $item.Size
            }

            if ($script:IsDryRun) {
                Write-Output ("  [DRY] Recycle Bin - Would free: " + (Format-Bytes $sizeBefore) + " ($($items.Count) items)")
                $script:TotalFreed += $sizeBefore
            } else {
                Clear-RecycleBin -DriveLetter $driveLetter -Force -ErrorAction Stop
                Write-Output ("  [OK] Recycle Bin - Freed: " + (Format-Bytes $sizeBefore) + " ($($items.Count) items)")
                $script:TotalFreed += $sizeBefore
            }
        }
    } catch {
        Write-Output ("  [ERROR] Recycle Bin - Error: " + $_.Exception.Message)
    }
    Write-Output ""
}

# Clean Browser Caches
if ($CleanBrowserCache -eq "true") {
    Update-ToolkitProgress -Percent 45 -Status "Cleaning browser caches..."
    Write-Output "Cleaning Browser Caches..."
    Write-Output "  WARNING: Close all browsers before running this!"

    $userProfiles = Get-ChildItem "$TargetDrive\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($user in $userProfiles) {
        if ($user.Name -notin @('Public', 'Default', 'Default User')) {
            # Chrome
            $chromePath = Join-Path $user.FullName "AppData\Local\Google\Chrome\User Data\Default\Cache"
            $freed = Remove-PathSafely -Path $chromePath -Description "Chrome Cache ($($user.Name))" -IsFolder
            $script:TotalFreed += $freed

            # Edge
            $edgePath = Join-Path $user.FullName "AppData\Local\Microsoft\Edge\User Data\Default\Cache"
            $freed = Remove-PathSafely -Path $edgePath -Description "Edge Cache ($($user.Name))" -IsFolder
            $script:TotalFreed += $freed

            # Firefox
            $firefoxPath = Join-Path $user.FullName "AppData\Local\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxPath) {
                $profiles = Get-ChildItem $firefoxPath -Directory -ErrorAction SilentlyContinue
                foreach ($profile in $profiles) {
                    $cachePath = Join-Path $profile.FullName "cache2"
                    $freed = Remove-PathSafely -Path $cachePath -Description "Firefox Cache ($($user.Name))" -IsFolder
                    $script:TotalFreed += $freed
                }
            }
        }
    }
    Write-Output ""
}

# Clean Thumbnails
if ($CleanThumbnails -eq "true") {
    Update-ToolkitProgress -Percent 55 -Status "Cleaning thumbnail cache..."
    Write-Output "Cleaning Thumbnail Cache..."

    $userProfiles = Get-ChildItem "$TargetDrive\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($user in $userProfiles) {
        if ($user.Name -notin @('Public', 'Default', 'Default User')) {
            $thumbPath = Join-Path $user.FullName "AppData\Local\Microsoft\Windows\Explorer"
            $freed = Clean-OldFiles -Path $thumbPath -Description "Thumbnails ($($user.Name))" -Filter "thumbcache_*.db"
            $script:TotalFreed += $freed
        }
    }
    Write-Output ""
}

# Clean Error Reports
if ($CleanErrorReports -eq "true") {
    Update-ToolkitProgress -Percent 65 -Status "Cleaning error reports..."
    Write-Output "Cleaning Error Reports..."

    $freed = Clean-OldFiles -Path "$TargetDrive\ProgramData\Microsoft\Windows\WER\ReportQueue" -Description "Windows Error Reports"
    $script:TotalFreed += $freed

    $freed = Clean-OldFiles -Path "$TargetDrive\ProgramData\Microsoft\Windows\WER\ReportArchive" -Description "WER Archive"
    $script:TotalFreed += $freed
    Write-Output ""
}

# Clean Windows.old
if ($CleanOldWindows -eq "true") {
    Update-ToolkitProgress -Percent 75 -Status "Cleaning Windows.old..."
    Write-Output "Cleaning Windows.old Folder..."
    Write-Output "  WARNING: This cannot be undone!"

    $windowsOldPath = "$TargetDrive\Windows.old"
    if (Test-Path $windowsOldPath) {
        $sizeBefore = Get-FolderSize -Path $windowsOldPath

        if ($script:IsDryRun) {
            Write-Output ("  [DRY] Windows.old - Would free: " + (Format-Bytes $sizeBefore))
            $script:TotalFreed += $sizeBefore
        } else {
            try {
                # Take ownership and delete
                & takeown /F $windowsOldPath /R /D Y 2>&1 | Out-Null
                & icacls $windowsOldPath /grant administrators:F /T 2>&1 | Out-Null
                Remove-Item -Path $windowsOldPath -Recurse -Force -ErrorAction Stop
                Write-Output ("  [OK] Windows.old - Freed: " + (Format-Bytes $sizeBefore))
                $script:TotalFreed += $sizeBefore
            } catch {
                Write-Output ("  [ERROR] Windows.old - Error: " + $_.Exception.Message)
            }
        }
    } else {
        Write-Host "  [SKIP] Windows.old not found"
    }
    Write-Output ""
}

# Clean Delivery Optimization
if ($CleanDeliveryOptimization -eq "true") {
    Update-ToolkitProgress -Percent 85 -Status "Cleaning delivery optimization..."
    Write-Output "Cleaning Delivery Optimization Cache..."

    $freed = Clean-OldFiles -Path "$TargetDrive\Windows\SoftwareDistribution\DeliveryOptimization" -Description "Delivery Optimization"
    $script:TotalFreed += $freed
    Write-Output ""
}

# Clean Downloads (old files)
if ($CleanDownloads -eq "true") {
    Update-ToolkitProgress -Percent 90 -Status "Cleaning old downloads..."
    Write-Output "Cleaning Old Downloads (30+ days)..."

    $userProfiles = Get-ChildItem "$TargetDrive\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($user in $userProfiles) {
        if ($user.Name -notin @('Public', 'Default', 'Default User')) {
            $downloadsPath = Join-Path $user.FullName "Downloads"
            if (Test-Path $downloadsPath) {
                $cutoffDate = (Get-Date).AddDays(-30)
                try {
                    $files = Get-ChildItem -Path $downloadsPath -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt $cutoffDate }

                    if ($files.Count -gt 0) {
                        $sizeBefore = ($files | Measure-Object -Property Length -Sum).Sum

                        if ($script:IsDryRun) {
                            Write-Output ("  [DRY] Downloads ($($user.Name)) - Would free: " + (Format-Bytes $sizeBefore) + " ($($files.Count) files)")
                            $script:TotalFreed += $sizeBefore
                        } else {
                            $files | Remove-Item -Force -ErrorAction SilentlyContinue
                            Write-Output ("  [OK] Downloads ($($user.Name)) - Freed: " + (Format-Bytes $sizeBefore) + " ($($files.Count) files)")
                            $script:TotalFreed += $sizeBefore
                        }
                    } else {
                        Write-Host "  [SKIP] Downloads ($($user.Name)) - No old files"
                    }
                } catch {
                    Write-Output ("  [ERROR] Downloads ($($user.Name)) - Error: " + $_.Exception.Message)
                }
            }
        }
    }
    Write-Output ""
}

# Get final disk space
Update-ToolkitProgress -Percent 95 -Status "Calculating final disk space..."
$driveInfo = Get-PSDrive -Name $driveLetter
$spaceAfterGB = [Math]::Round($driveInfo.Free / 1GB, 2)

Write-Output "========================================="
Write-Output "CLEANUP SUMMARY"
Write-Output "========================================="
Write-Output ""
Write-Output ("Disk space before: " + (Format-Bytes ($spaceBeforeGB * 1GB)))
Write-Output ("Disk space after:  " + (Format-Bytes ($spaceAfterGB * 1GB)))
Write-Output ("Total freed:       " + (Format-Bytes $script:TotalFreed))
Write-Output ""

if ($script:IsDryRun) {
    Write-Output "This was a DRY RUN - no files were actually deleted."
    Write-Output "Uncheck 'Dry Run' and run again to perform actual cleanup."
} else {
    Write-Output "Cleanup completed successfully!"
}

Update-ToolkitProgress -Percent 100 -Status "Cleanup complete"