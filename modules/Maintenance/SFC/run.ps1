param(
    [Parameter()][bool]$OfflineMode = $false,
    [Parameter()][string]$OfflineBootDrive = "",
    [Parameter()][string]$OfflineWinDir = "",
    [Parameter()][bool]$ScanOnly = $false
)

$ErrorActionPreference = "Continue"

# Normalize paths - Check for null first
$OfflineBootDrive = if ($OfflineBootDrive) { $OfflineBootDrive.Trim().TrimEnd('\') } else { "" }
$OfflineWinDir = if ($OfflineWinDir) { $OfflineWinDir.Trim().TrimEnd('\') } else { "" }

# Add colon if single letter
if ($OfflineBootDrive -and $OfflineBootDrive.Length -eq 1) {
    $OfflineBootDrive = "${OfflineBootDrive}:"
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "          SYSTEM FILE CHECKER (SFC)" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Mode:       $(if ($OfflineMode) { 'Offline' } else { 'Online' })"
Write-Host "  Scan Type:  $(if ($ScanOnly) { 'Verify Only' } else { 'Scan and Repair' })"

# Build SFC arguments
$sfcArgs = @()

if ($OfflineMode) {
    # Offline mode requires both boot drive and Windows directory
    if ([string]::IsNullOrWhiteSpace($OfflineBootDrive)) {
        Write-Host ""
        Write-Host "[ERROR] Offline Boot Drive is required for offline mode!" -ForegroundColor Red
        Write-Host "Example: D:" -ForegroundColor Yellow
        return
    }

    if ([string]::IsNullOrWhiteSpace($OfflineWinDir)) {
        Write-Host ""
        Write-Host "[ERROR] Offline Windows Directory is required for offline mode!" -ForegroundColor Red
        Write-Host "Example: D:\Windows" -ForegroundColor Yellow
        return
    }

    # Verify paths exist
    if (-not (Test-Path $OfflineBootDrive)) {
        Write-Host ""
        Write-Host "[ERROR] Offline Boot Drive not found: $OfflineBootDrive" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $OfflineWinDir)) {
        Write-Host ""
        Write-Host "[ERROR] Offline Windows Directory not found: $OfflineWinDir" -ForegroundColor Red
        return
    }

    Write-Host "  Boot Drive: $OfflineBootDrive"
    Write-Host "  Win Dir:    $OfflineWinDir"

    # SFC offline syntax: sfc /scannow /offbootdir=<boot> /offwindir=<windows>
    if ($ScanOnly) {
        $sfcArgs += "/verifyonly"
    } else {
        $sfcArgs += "/scannow"
    }
    $sfcArgs += "/offbootdir=$OfflineBootDrive"
    $sfcArgs += "/offwindir=$OfflineWinDir"

} else {
    # Online mode
    if ($ScanOnly) {
        $sfcArgs += "/verifyonly"
    } else {
        $sfcArgs += "/scannow"
    }
}

Write-Host ""

if ($OfflineMode) {
    Write-Host "Starting SFC on offline Windows installation..." -ForegroundColor Cyan
    Write-Host "Target: $OfflineWinDir" -ForegroundColor Cyan
} else {
    Write-Host "Starting SFC on current system..." -ForegroundColor Cyan
}

if ($ScanOnly) {
    Write-Host "Mode: Verify only (no repairs will be attempted)" -ForegroundColor Yellow
} else {
    Write-Host "Mode: Scan and repair corrupted files" -ForegroundColor Yellow
}

Write-Host "This may take 15-30 minutes. Please be patient." -ForegroundColor Yellow
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

# Initialize progress tracking
Write-Host "PROGRESS:0" -ForegroundColor Magenta

try {
    # Run SFC with output redirection
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "sfc.exe"
    $pinfo.Arguments = ($sfcArgs -join ' ')
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    # Track progress
    $progressReported = 0
    $lastProgressUpdate = Get-Date
    $estimatedProgress = 0

    $process.Start() | Out-Null

    # Read output in real-time
    while (!$process.HasExited) {
        # Try to read a line (non-blocking)
        if (!$process.StandardOutput.EndOfStream) {
            $line = $process.StandardOutput.ReadLine()

            # Parse actual progress percentage from SFC
            if ($line -match '(\d+)%') {
                $percent = [int]$matches[1]
                if ($percent -ne $progressReported) {
                    $progressReported = $percent
                    $estimatedProgress = $percent
                    $lastProgressUpdate = Get-Date
                    Write-Host "PROGRESS:$percent" -ForegroundColor Magenta
                }
            }

            # Color-code important lines
            if ($line -match "corrupt|error|failed") {
                Write-Host $line -ForegroundColor Red
            } elseif ($line -match "successfully|repaired|complete") {
                Write-Host $line -ForegroundColor Green
            } elseif ($line -match "verification|scanning|beginning") {
                Write-Host $line -ForegroundColor Cyan
            } elseif ($line -match "\d+%") {
                Write-Host $line -ForegroundColor Yellow
            } else {
                Write-Host $line
            }
        } else {
            # If no output for a while, estimate progress (very rough)
            $timeSinceLastUpdate = (Get-Date) - $lastProgressUpdate

            # Update estimated progress every 30 seconds if we haven't seen actual progress
            if ($timeSinceLastUpdate.TotalSeconds -gt 30 -and $estimatedProgress -lt 95) {
                $estimatedProgress += 1
                if ($estimatedProgress -ne $progressReported) {
                    $progressReported = $estimatedProgress
                    Write-Host "PROGRESS:$estimatedProgress" -ForegroundColor Magenta
                    $lastProgressUpdate = Get-Date
                }
            }

            Start-Sleep -Milliseconds 500
        }
    }

    # Read any remaining output
    while (!$process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine()

        if ($line -match '(\d+)%') {
            $percent = [int]$matches[1]
            Write-Host "PROGRESS:$percent" -ForegroundColor Magenta
        }

        if ($line -match "corrupt|error|failed") {
            Write-Host $line -ForegroundColor Red
        } elseif ($line -match "successfully|repaired|complete") {
            Write-Host $line -ForegroundColor Green
        } elseif ($line -match "verification|scanning|beginning") {
            Write-Host $line -ForegroundColor Cyan
        } elseif ($line -match "\d+%") {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }

    # Read any error output
    while (!$process.StandardError.EndOfStream) {
        $line = $process.StandardError.ReadLine()
        Write-Host $line -ForegroundColor Yellow
    }

    $process.WaitForExit()

    # Ensure we reach 100%
    Write-Host "PROGRESS:100" -ForegroundColor Magenta

    Write-Host ""
    Write-Host "-------------------------------------------------------" -ForegroundColor Gray

    if ($process.ExitCode -eq 0) {
        Write-Host "SFC completed successfully!" -ForegroundColor Green
        Write-Host "No integrity violations found or all violations were repaired." -ForegroundColor Green
    } else {
        Write-Host "[INFO] SFC exited with code: $($process.ExitCode)" -ForegroundColor Yellow

        if ($OfflineMode) {
            Write-Host "Check the offline Windows logs for detailed information." -ForegroundColor Cyan
            Write-Host "Log location: $OfflineWinDir\Logs\CBS\CBS.log" -ForegroundColor Cyan
        } else {
            Write-Host "Check C:\Windows\Logs\CBS\CBS.log for detailed information." -ForegroundColor Cyan
        }
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] Failed to run SFC: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan