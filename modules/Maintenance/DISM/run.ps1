param(
    [Parameter()][bool]$OfflineMode = $false,
    [Parameter()][string]$OfflineWindowsDir = "",
    [Parameter()][string]$SourceWimEsd = "",
    [Parameter()][string]$SourceIndex = "1",
    [Parameter()][bool]$LimitAccess = $false
)

$ErrorActionPreference = "Continue"

# Normalize strings - FIX: Check for null first
$OfflineWindowsDir = if ($OfflineWindowsDir) { $OfflineWindowsDir.Trim().TrimEnd('\') } else { "" }
$SourceWimEsd = if ($SourceWimEsd) { $SourceWimEsd.Trim().Trim('"') } else { "" }
$SourceIndex = if ($SourceIndex) { $SourceIndex.Trim() } else { "1" }

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "                     DISM" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Offline Mode: $(if ($OfflineMode) { 'Yes' } else { 'No' })"

# Build base DISM args
$argParts = New-Object System.Collections.Generic.List[string]

# Offline image
if ($OfflineMode) {
    if ([string]::IsNullOrWhiteSpace($OfflineWindowsDir)) {
        Write-Host "[ERROR] Offline Windows Directory is required (example: D:\Windows)" -ForegroundColor Red
        return
    }

    # DISM /Image expects the root of the offline Windows drive (e.g. D:\), not D:\Windows
    $imgRoot = (Split-Path -Path $OfflineWindowsDir -Qualifier)
    if ([string]::IsNullOrWhiteSpace($imgRoot)) {
        Write-Host "[ERROR] Could not infer image root from Offline Windows Directory" -ForegroundColor Red
        return
    }
    $imgRoot = $imgRoot.TrimEnd('\') + "\"

    [void]$argParts.Add("/Image:$imgRoot")
    Write-Host "  Offline Windows: $OfflineWindowsDir"
    Write-Host "  Image Root:      $imgRoot"
} else {
    # Online image
    [void]$argParts.Add("/Online")
    Write-Host "  Mode:            Online"
}

[void]$argParts.Add("/Cleanup-Image")
[void]$argParts.Add("/RestoreHealth")

# Optional Source
if (-not [string]::IsNullOrWhiteSpace($SourceWimEsd)) {
    if (-not (Test-Path -LiteralPath $SourceWimEsd)) {
        Write-Host "[ERROR] Source file not found: $SourceWimEsd" -ForegroundColor Red
        return
    }

    $ext = [System.IO.Path]::GetExtension($SourceWimEsd).ToLowerInvariant()
    $type = if ($ext -eq ".esd") { "esd" } else { "wim" }

    $idx = 1
    if (-not [int]::TryParse($SourceIndex, [ref]$idx)) { $idx = 1 }
    if ($idx -lt 1) { $idx = 1 }

    # /Source:wim:<path>:<index> or /Source:esd:<path>:<index>
    [void]$argParts.Add("/Source:${type}:${SourceWimEsd}:${idx}")

    if ($LimitAccess) {
        [void]$argParts.Add("/LimitAccess")
    }

    Write-Host "  Source:          $SourceWimEsd (index $idx)"
    Write-Host "  Limit Access:    $(if ($LimitAccess) { 'Yes' } else { 'No' })"
} else {
    Write-Host "  Source:          None (will use Windows Update or local store)"
}

Write-Host ""
Write-Host "Starting DISM repair..." -ForegroundColor Cyan
Write-Host "This may take several minutes. Please be patient." -ForegroundColor Yellow
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

# Initialize progress
Write-Host "PROGRESS:0" -ForegroundColor Magenta

try {
    # Run DISM with output redirection
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "dism.exe"
    $pinfo.Arguments = ($argParts -join ' ')
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    # Track progress
    $progressReported = 0

    $process.Start() | Out-Null

    # Read output in real-time
    while (!$process.HasExited) {
        if (!$process.StandardOutput.EndOfStream) {
            $line = $process.StandardOutput.ReadLine()

            # Parse progress percentage
            if ($line -match '(\d+\.\d+)%') {
                $percent = [math]::Round([double]$matches[1])
                if ($percent -ne $progressReported) {
                    $progressReported = $percent
                    Write-Host "PROGRESS:$percent" -ForegroundColor Magenta
                }
            }

            # Color-code important lines
            if ($line -match "Error|Failed|corrupt") {
                Write-Host $line -ForegroundColor Red
            } elseif ($line -match "Success|complete|restored") {
                Write-Host $line -ForegroundColor Green
            } elseif ($line -match "\d+\.\d+%") {
                Write-Host $line -ForegroundColor Cyan
            } else {
                Write-Host $line
            }
        } else {
            Start-Sleep -Milliseconds 200
        }
    }

    # Read any remaining output
    while (!$process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine()

        if ($line -match '(\d+\.\d+)%') {
            $percent = [math]::Round([double]$matches[1])
            Write-Host "PROGRESS:$percent" -ForegroundColor Magenta
        }

        if ($line -match "Error|Failed|corrupt") {
            Write-Host $line -ForegroundColor Red
        } elseif ($line -match "Success|complete|restored") {
            Write-Host $line -ForegroundColor Green
        } elseif ($line -match "\d+\.\d+%") {
            Write-Host $line -ForegroundColor Cyan
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
        Write-Host "DISM completed successfully!" -ForegroundColor Green
    } elseif ($process.ExitCode -eq 3010) {
        Write-Host "[INFO] DISM completed. A reboot is required." -ForegroundColor Yellow
    } else {
        Write-Host "[WARNING] DISM exited with code: $($process.ExitCode)" -ForegroundColor Yellow
        Write-Host "Check the output above for details." -ForegroundColor Yellow
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] Failed to run DISM: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan