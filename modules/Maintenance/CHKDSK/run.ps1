param(
    [Parameter()][bool]$OfflineMode = $false,
    [Parameter()][string]$OfflineBootDrive = "",
    [Parameter()][string]$DriveLetter = "C:",
    [Parameter()][bool]$OnlineUseFixF = $false,
    [Parameter()][bool]$OnlineUseR = $false
)

$ErrorActionPreference = "Continue"

# Normalize drives
if ($DriveLetter -and $DriveLetter.Length -eq 1) { $DriveLetter = "${DriveLetter}:" }
$DriveLetter = ($DriveLetter.Trim()).TrimEnd('\')

if ($null -eq $OfflineBootDrive) { $OfflineBootDrive = "" }
$OfflineBootDrive = ($OfflineBootDrive.Trim()).TrimEnd('\')
if ($OfflineBootDrive -and $OfflineBootDrive.Length -eq 1) { $OfflineBootDrive = "${OfflineBootDrive}:" }

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "                    CHKDSK" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Offline Mode: $(if ($OfflineMode) { 'Yes' } else { 'No' })"
Write-Host "  Use /r:       $(if ($OnlineUseR) { 'Yes' } else { 'No' })"
Write-Host "  Use /f:       $(if ($OnlineUseFixF) { 'Yes' } else { 'No' })"
Write-Host ""

# Build command
if ($OfflineMode) {
    if ([string]::IsNullOrWhiteSpace($OfflineBootDrive)) {
        Write-Host "[ERROR] Offline Boot Drive is required (example: D:)" -ForegroundColor Red
        return
    }

    if ($OnlineUseR) {
        Write-Host "[NOTE] /r is very slow and implies /f" -ForegroundColor Yellow
        $cmdArgs = "$OfflineBootDrive /r"
    } else {
        $cmdArgs = "$OfflineBootDrive /f"
    }
} else {
    if ($OnlineUseR) {
        Write-Host "[NOTE] /r is very slow and implies /f. May require reboot on system drives." -ForegroundColor Yellow
        $cmdArgs = "$DriveLetter /r"
    } elseif ($OnlineUseFixF) {
        Write-Host "[NOTE] /f may require reboot to complete repairs." -ForegroundColor Yellow
        $cmdArgs = "$DriveLetter /f"
    } else {
        $cmdArgs = "$DriveLetter /scan"
    }
}

Write-Host "Running: chkdsk $cmdArgs" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

try {
    # Run CHKDSK with output redirection
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "chkdsk.exe"
    $pinfo.Arguments = $cmdArgs
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo
    $process.Start() | Out-Null

    # Read output in real-time
    while (!$process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine()
        Write-Host $line
    }

    # Read any error output
    while (!$process.StandardError.EndOfStream) {
        $line = $process.StandardError.ReadLine()
        Write-Host $line -ForegroundColor Yellow
    }

    $process.WaitForExit()

    Write-Host ""
    if ($process.ExitCode -eq 0) {
        Write-Host "CHKDSK completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] CHKDSK exited with code: $($process.ExitCode)" -ForegroundColor Yellow
        Write-Host "This may mean a reboot is required or the drive is in use." -ForegroundColor Yellow
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] Failed to run CHKDSK: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan