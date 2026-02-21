# Deploy Windows to an offline disk (ISO/WIM/ESD) with partitioning, DISM apply, BCDBOOT, logs
# ENHANCED VERSION with better error handling, progress reporting, and validation

param(
    [ValidateSet("Deploy", "ListImages", "DryRunPlan")][string]$Action = "Deploy",

    [ValidateSet("ISO", "WIM", "ESD")][string]$SourceType = "ISO",
    [string]$IsoPath = "",
    [string]$ImagePath = "",
    [int]$ImageIndex = 1,

    [int]$TargetDiskNumber = 1,
    [ValidateSet("UEFI", "BIOS", "ALL")][string]$FirmwareType = "UEFI",

    [int]$EfiSizeMB = 260,
    [int]$SystemReservedMB = 500,
    [string]$RecoveryPartition = "false",
    [int]$RecoverySizeMB = 1024,

    [string]$AssignDriveLetters = "true",

    [string]$DriverFolderPath = "",
    [string]$UpdatesFolderPath = "",
    [string]$EnableNetFx3 = "false",
    [string]$SxsSourcePath = "",

    [string]$UnattendXmlPath = "",
    [string]$AutoGenerateUnattend = "false",
    [string]$ComputerName = "",
    [string]$LocalAdminUser = "Admin",
    [string]$LocalAdminPassword = "",
    [string]$LocalAdminPasswordConfirm = "",
    [string]$TimeZone = "Middle East Standard Time",

    [string]$OfflineTweaks = "false",
    [string]$VerifyAfterApply = "true",
    [string]$ApplyCompact = "false",

    [string]$Confirmation = "",
    [string]$LogPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\functions.ps1"

# Log file
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $script:LogFile = Join-Path $PSScriptRoot ("deploy-windows-{0}.log" -f $stamp)
} else {
    $script:LogFile = $LogPath
}
New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

Write-Log "=== Windows Offline Deploy (Enhanced) ==="
Write-Log "Action=$Action SourceType=$SourceType FirmwareType=$FirmwareType TargetDisk=$TargetDiskNumber Index=$ImageIndex"
Write-Log "LogFile=$script:LogFile"

Assert-Admin

$isoHandle = $null
$resolvedImage = $null
$sxs = $null

try {
    # ---- Password Validation ----
    if ($AutoGenerateUnattend -eq "true" -and -not [string]::IsNullOrWhiteSpace($LocalAdminPassword)) {
        if ($LocalAdminPassword -ne $LocalAdminPasswordConfirm) {
            throw "Admin passwords do not match. Please re-enter the password in both fields."
        }
    }

    Write-Progress-Status -Percent 0 -Status "Initializing deployment..."

    # Resolve image path (ISO mount OR direct WIM/ESD)
    if ($SourceType -eq "ISO") {
        if ([string]::IsNullOrWhiteSpace($IsoPath)) { throw "IsoPath is required when SourceType=ISO." }
        if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO file not found: $IsoPath" }

        Write-Progress-Status -Percent 2 -Status "Mounting ISO..."
        $isoHandle = Mount-IsoAndGetInstallImage -IsoPath $IsoPath
        $resolvedImage = $isoHandle.ImagePath
        if ($isoHandle.Sxs -and (Test-Path -LiteralPath $isoHandle.Sxs)) { $sxs = $isoHandle.Sxs }
        Write-Log "ISO mounted. Image=$resolvedImage"
        Write-Progress-Status -Percent 5 -Status "ISO mounted successfully"
    } else {
        if ([string]::IsNullOrWhiteSpace($ImagePath)) { throw "ImagePath is required when SourceType=WIM/ESD." }
        if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Image file not found: $ImagePath" }
        $resolvedImage = $ImagePath
        Write-Progress-Status -Percent 5 -Status "Image file located"
    }

    if (-not (Test-Path -LiteralPath $resolvedImage)) { throw "Resolved image path not found: $resolvedImage" }

    # ListImages action (live DISM + JSON marker for UI)
    if ($Action -eq "ListImages") {
        Write-Log "Listing available Windows editions..."
        $info = Dism-GetWimInfo -ImagePath $resolvedImage

        if ($info.Images -and $info.Images.Count -gt 0) {
            Write-Output ""
            Write-Output "Available Windows Editions:"
            Write-Output ("=" * 80)
            $info.Images | Select-Object Index, Name, Architecture, Version, Size | Format-Table -AutoSize | Out-String | Write-Output
            Write-Output ""
            Write-Output "Tip: Set ImageIndex to the Index you want, then run Action=Deploy."
            Write-Output ""

            # Machine-friendly line for UI auto-fill/parsing
            $json = ($info.Images | ConvertTo-Json -Depth 6 -Compress)
            Write-Output ("__IMAGE_LIST_JSON__=" + $json)
        } else {
            Write-Output $info.Raw
        }
        return
    }

    $wantDryRun = ($Action -eq "DryRunPlan")

    # Safety gate
    if (-not $wantDryRun) {
        if ($Confirmation -ne "WIPE") {
            throw "SAFETY CONFIRMATION FAILED: You must type 'WIPE' (exactly) in the Confirmation field to proceed with disk erasure."
        }
        Write-Log "Safety confirmation passed (user typed: $Confirmation)"
    }

    # Disk safety checks
    Write-Progress-Status -Percent 7 -Status "Validating target disk..."
    $disk = Get-SafeDisk -DiskNumber $TargetDiskNumber
    Write-Log ("Target disk: #{0} {1} {2}GB {3}" -f $disk.Number, $disk.FriendlyName, [Math]::Round($disk.Size / 1GB, 2), $disk.PartitionStyle)

    # Disk space validation
    if (-not $wantDryRun) {
        Test-DiskSpace -Disk $disk -ImagePath $resolvedImage -ImageIndex $ImageIndex
    }

    # Coerce flags
    $doRecovery = ($RecoveryPartition -eq "true")
    $doAssignLetters = ($AssignDriveLetters -eq "true")
    $doCompact = $false
    try { $doCompact = [bool]::Parse($ApplyCompact) } catch { $doCompact = ($ApplyCompact -eq "true") }

    # Build diskpart plan
    Write-Progress-Status -Percent 8 -Status "Building partition plan..."
    if ($FirmwareType -eq "BIOS") {
        $dp = New-DiskPartScript_BIOS -DiskNumber $TargetDiskNumber -SystemReservedMB $SystemReservedMB -RecoveryPartition:($doRecovery) -RecoverySizeMB $RecoverySizeMB -AssignDriveLetters:($doAssignLetters)
        $isUEFI = $false
    } else {
        # For UEFI and ALL, we use GPT/UEFI layout (ALL is intended for BCDBOOT only)
        $dp = New-DiskPartScript_UEFI -DiskNumber $TargetDiskNumber -EfiSizeMB $EfiSizeMB -RecoveryPartition:($doRecovery) -RecoverySizeMB $RecoverySizeMB -AssignDriveLetters:($doAssignLetters)
        $isUEFI = $true
    }

    Write-Log "DiskPart plan:"
    Write-Log "---BEGIN DISKPART SCRIPT---"
    $dp -split "`r`n" | ForEach-Object { Write-Log $_ }
    Write-Log "---END DISKPART SCRIPT---"

    Write-Log ("DISM plan: dism /Apply-Image /ImageFile:`"{0}`" /Index:{1} /ApplyDir:W:\{2}" -f $resolvedImage, $ImageIndex, $(if ($doCompact) { " /Compact" } else { "" }))
    Write-Log ("BCDBOOT plan: bcdboot W:\Windows /s S: /f {0}" -f $FirmwareType)

    if ($wantDryRun) {
        Write-Log "DryRunPlan requested. No changes were made."
        Write-Output ""
        Write-Output "=== DRY RUN PLAN SUMMARY ==="
        Write-Output "Target Disk: $TargetDiskNumber ($($disk.FriendlyName) - $([Math]::Round($disk.Size/1GB,2)) GB)"
        Write-Output "Partition Style: $(if ($isUEFI) { 'GPT (UEFI)' } else { 'MBR (BIOS)' })"
        Write-Output "Image: $resolvedImage (Index $ImageIndex)"
        Write-Output "Recovery Partition: $(if ($doRecovery) { 'Yes (' + $RecoverySizeMB + ' MB)' } else { 'No' })"
        Write-Output "Compact Mode: $(if ($doCompact) { 'Yes' } else { 'No' })"
        Write-Output ""
        Write-Output "No actual changes were made to the disk."
        return
    }

    # === LIVE DEPLOYMENT STARTS HERE ===

    # Partition/format (LIVE)
    Invoke-DiskPartScript -ScriptText $dp

    # Validate expected drive letters exist
    Ensure-DriveLetters -UEFI:($isUEFI)

    # Apply image (LIVE DISM)
    Apply-WindowsImage -ImagePath $resolvedImage -Index $ImageIndex -ApplyDir "W:\" -Compact:($doCompact)

    # Optional drivers / updates (LIVE DISM)
    if (-not [string]::IsNullOrWhiteSpace($DriverFolderPath)) {
        if (Test-Path -LiteralPath $DriverFolderPath) {
            Inject-Drivers -DriverFolder $DriverFolderPath -WindowsDir "W:\"
        } else {
            Write-Log "Driver folder not found, skipping: $DriverFolderPath" "WARN"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($UpdatesFolderPath)) {
        if (Test-Path -LiteralPath $UpdatesFolderPath) {
            Inject-Updates -UpdatesFolder $UpdatesFolderPath -WindowsDir "W:\"
        } else {
            Write-Log "Updates folder not found, skipping: $UpdatesFolderPath" "WARN"
        }
    }

    # Optional NetFx3 (LIVE DISM)
    if ($EnableNetFx3 -eq "true") {
        $src = $null
        if ($sxs) { $src = $sxs }
        elseif (-not [string]::IsNullOrWhiteSpace($SxsSourcePath)) { $src = $SxsSourcePath }

        if ($src) {
            Enable-NetFx3Offline -WindowsDir "W:\" -SxsSource $src
        } else {
            Write-Log "NetFx3 requested but no SxS source available. Skipping." "WARN"
        }
    }

    # Unattend
    if (-not [string]::IsNullOrWhiteSpace($UnattendXmlPath)) {
        if (Test-Path -LiteralPath $UnattendXmlPath) {
            $destDir = "W:\Windows\Panther"
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Copy-Item -LiteralPath $UnattendXmlPath -Destination (Join-Path $destDir "Unattend.xml") -Force
            Write-Log "Copied Unattend.xml to $destDir"
        } else {
            Write-Log "Unattend.xml file not found: $UnattendXmlPath" "WARN"
        }
    } elseif ($AutoGenerateUnattend -eq "true") {
        $destDir = "W:\Windows\Panther"
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $dest = Join-Path $destDir "Unattend.xml"

        if ([string]::IsNullOrWhiteSpace($ComputerName)) { $ComputerName = "WIN-PC" }
        if ([string]::IsNullOrWhiteSpace($LocalAdminUser)) { $LocalAdminUser = "Admin" }

        Write-UnattendXml -Path $dest -ComputerName $ComputerName -LocalAdminUser $LocalAdminUser -LocalAdminPassword $LocalAdminPassword -TimeZone $TimeZone
        Write-Log "Generated Unattend.xml at $dest"
        Write-Log "  Computer Name: $ComputerName"
        Write-Log "  Admin User: $LocalAdminUser"
        Write-Log "  Time Zone: $TimeZone"
    }

    # Offline tweaks (LIVE reg.exe)
    if ($OfflineTweaks -eq "true") {
        Apply-OfflineTweaks -WindowsDir "W:\"
    }

    # Boot files (LIVE bcdboot.exe)
    Create-BootFiles -FirmwareType $FirmwareType

    # Verification
    if ($VerifyAfterApply -eq "true") {
        Verify-Deployment -UEFI:($isUEFI)
    }

    Write-Progress-Status -Percent 100 -Status "Deployment completed successfully"
    Write-Log ""
    Write-Log "========================================="
    Write-Log "DEPLOYMENT COMPLETED SUCCESSFULLY"
    Write-Log "========================================="
    Write-Log ""

    Write-Output ""
    Write-Output "========================================="
    Write-Output "DEPLOYMENT COMPLETED SUCCESSFULLY"
    Write-Output "========================================="
    Write-Output ""
    Write-Output "Target Disk: Disk $TargetDiskNumber"
    Write-Output "Image Applied: Index $ImageIndex from $resolvedImage"
    Write-Output "Firmware Type: $FirmwareType"
    Write-Output ""
    Write-Output "Next Steps:"
    Write-Output "1. Remove installation media (USB/DVD)"
    Write-Output "2. Reboot the computer"
    Write-Output "3. Boot from the newly installed disk"
    Write-Output ""
    Write-Output "Log File: $script:LogFile"
    Write-Output ""
} catch {
    Write-Log "DEPLOYMENT FAILED: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"

    Write-Output ""
    Write-Output "========================================="
    Write-Output "DEPLOYMENT FAILED"
    Write-Output "========================================="
    Write-Output ""
    Write-Output "Error: $($_.Exception.Message)"
    Write-Output ""
    Write-Output "Log File: $script:LogFile"
    Write-Output ""

    # Attempt cleanup
    try {
        if ($isoHandle -and $isoHandle.DiskImage) {
            Cleanup-OnFailure -MountedIso $isoHandle.DiskImage.ImagePath
        }
    } catch {}

    throw
} finally {
    # Unmount ISO if mounted
    if ($isoHandle -and $isoHandle.DiskImage) {
        try {
            Write-Log "Unmounting ISO..."
            Dismount-DiskImage -ImagePath $isoHandle.DiskImage.ImagePath -ErrorAction SilentlyContinue
            Write-Log "ISO unmounted successfully"
        } catch {
            Write-Log "Failed to unmount ISO: $($_.Exception.Message)" "WARN"
        }
    }
}
