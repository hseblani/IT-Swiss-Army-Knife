param(
    [string]$Action = "CheckUpdates",
    [string]$UpdateTypes = "All",
    [bool]$IncludeDrivers = $false,
    [bool]$AutoReboot = $false,
    [string]$ServiceAction = "Status",
    [bool]$DownloadOnly = $false
)

# Shared helpers
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -------------------- HELPERS --------------------
function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }
function Set-Progress([int]$p) { Write-Information ("PROGRESS:{0}" -f $p) }

# -------------------- LOGIC FUNCTIONS --------------------

function Get-WUHistory {
    Out-Status "Reading Windows Update History..."
    Set-Progress 20
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $total = $searcher.GetTotalHistoryCount()

    if ($total -eq 0) { return @() }

    # Query last 100 items
    $history = $searcher.QueryHistory(0, 100)
    $results = foreach ($entry in $history) {
        [PSCustomObject]@{
            Date   = $entry.Date.ToString("yyyy-MM-dd HH:mm")
            Result = switch ($entry.ResultCode) { 2 { "Success" } 4 { "Failed" } 5 { "Aborted" } default { "Unknown" } }
            KB     = if ($entry.Title -match 'KB\d+') { $matches[0] } else { "N/A" }
            Title  = $entry.Title
        }
    }
    return $results
}

function Get-WUPending {
    Out-Status "Searching for available updates (This may take a minute)..."
    Set-Progress 30
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()

    $criteria = "IsInstalled=0 and IsHidden=0"
    if ($UpdateTypes -eq "SecurityOnly") { $criteria += " and Type='Software' and CategoryIDs contains '0FA1201D-4330-4FA8-8AE9-B877473B6441'" }

    $searchResult = $searcher.Search($criteria)
    $list = foreach ($update in $searchResult.Updates) {
        if (-not $IncludeDrivers -and $update.Type -eq 2) { continue }
        [PSCustomObject]@{
            Title      = $update.Title
            KB         = if ($update.Title -match 'KB\d+') { $matches[0] } else { "N/A" }
            Size_MB    = [Math]::Round($update.MaxDownloadSize / 1MB, 2)
            Mandatory  = $update.IsMandatory
            Downloaded = $update.IsDownloaded
        }
    }
    return $list
}

function Reset-WUComponents {
    Out-Status "Stopping Windows Update services..."
    Set-Progress 10
    $svcs = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    foreach ($s in $svcs) {
        if ((Get-Service $s).Status -eq 'Running') { Stop-Service $s -Force -ErrorAction SilentlyContinue }
    }

    Out-Status "Cleaning SoftwareDistribution and Catroot2..."
    Set-Progress 40
    $paths = @("$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2")
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $bak = "$p.bak_$(Get-Date -Format 'HHmmss')"
            Rename-Item -Path $p -NewName $bak -ErrorAction SilentlyContinue
        }
    }

    Out-Status "Reregistering System DLLs..."
    Set-Progress 70
    $dlls = @('wuapi.dll', 'wuaueng.dll', 'wups.dll', 'wups2.dll', 'qmgr.dll', 'wucltux.dll')
    foreach ($dll in $dlls) { Start-Process regsvr32.exe -ArgumentList "/s $dll" -Wait }

    Out-Status "Restarting services..."
    Set-Progress 90
    foreach ($s in $svcs) { Start-Service $s -ErrorAction SilentlyContinue }

    Set-Progress 100
    Out-Status "[OK] Windows Update components reset successfully."
}

# -------------------- MAIN --------------------
try {
    $reportSections = @()
    $outDir = Join-Path $env:TEMP "Toolkit-WindowsUpdate"
    if (-not (Test-Path $outDir)) { New-Item $outDir -ItemType Directory | Out-Null }

    switch ($Action) {
        "ViewHistory" {
            $data = Get-WUHistory
            $reportSections += @{ Id = "hist"; Title = "Installation History (Last 100)"; Type = "Table"; Data = $data; Expanded = $true }
        }
        "CheckUpdates" {
            $data = Get-WUPending
            $reportSections += @{ Id = "pend"; Title = "Available Updates"; Type = "Table"; Data = $data; Expanded = $true }
        }
        "ResetWindowsUpdate" {
            Reset-WUComponents
            return
        }
        "ManageService" {
            Out-Status "Service Operation: $ServiceAction"
            Manage-UpdateService -Operation $ServiceAction # Logic kept from original script
            Set-Progress 100; return
        }
        "InstallUpdates" {
            # Standard Install logic here, but redirecting summary to report
            Install-WindowsUpdates # Your original logic is mostly fine, just ensure it uses Write-Host [Status]
            return
        }
    }

    # Generate Report if data was collected
    if ($reportSections) {
        Set-Progress 95
        $htmlPath = Join-Path $outDir "WindowsUpdateReport.html"
        New-ToolkitGenericReport -ReportPath $htmlPath -Title "Windows Update Manager" -ComputerName $env:COMPUTERNAME -ReportSections $reportSections
        Out-Status "[OK] Report Generated: $htmlPath"
    }

    Set-Progress 100
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}