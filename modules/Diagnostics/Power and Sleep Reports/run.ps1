param(
    [bool]$WhatIfMode = $true,
    [string]$OutputFolder = "__MODULE_OUTPUT__",
    [bool]$RunEnergyReport = $false,
    [bool]$RunBatteryReport = $false
)

# Shared helpers
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }

function Set-Progress([int]$p) {
    Write-Information ("PROGRESS:{0}" -f $p)
}

function Get-PowerCfgText([string]$args) {
    # Helper to capture raw text from powercfg
    try {
        $result = powercfg.exe $args 2>&1 | Out-String
        return "<pre style='font-family:Consolas; font-size:12px; background:#f1f5f9; padding:10px; border-radius:4px;'>$($result.Trim())</pre>"
    } catch {
        return "Error collecting $args"
    }
}

# -------------------- main --------------------
try {
    Set-Progress 5
    $computer = $env:COMPUTERNAME

    # 1. Resolve Output Folder
    if ($OutputFolder -eq "__MODULE_OUTPUT__" -or [string]::IsNullOrWhiteSpace($OutputFolder)) {
        $OutputFolder = Join-Path $env:TEMP "Toolkit-PowerReports"
    }

    # 2. Define the target path (but don't create it yet!)
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $bundleRoot = Join-Path $OutputFolder "PowerReport_$stamp"

    # 3. DRY RUN CHECK (Moved up)
    if ($WhatIfMode) {
        Out-Status "[WHATIF] Dry run enabled. No folders or reports will be created."
        Out-Status "[WHATIF] Target Location: $bundleRoot"
        Set-Progress 100
        return
    }

    # 4. REAL RUN: Now we create the folder
    if (-not (Test-Path $bundleRoot)) {
        New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
    }
    Out-Status "Creating bundle folder: $bundleRoot"

    $mySections = @()

    # 1. Dashboard Summary (Flat)
    $summary = [PSCustomObject]@{
        ReportDate = (Get-Date).ToString()
        User       = $env:USERNAME
        PCName     = $computer
    }
    $mySections += @{ Id = "sys"; Title = "Diagnostic Info"; Type = "GridKeyValue"; Collapsible = $false; Data = @(@{ Title = "Session"; Obj = $summary }) }

    if ($WhatIfMode) {
        Out-Status "[WHATIF] Dry run enabled. No reports will be generated."
        Set-Progress 100
        return
    }

    # 2. Collect Quick Stats
    Set-Progress 20
    Out-Status "Collecting available sleep states..."
    $states = Get-PowerCfgText "/a"

    Out-Status "Checking wake requests..."
    $requests = Get-PowerCfgText "/requests"

    $mySections += @{
        Id = "quick"; Title = "Sleep & Requests"; Type = "GridKeyValue"; Collapsible = $false;
        Data = @(
            @{ Title = "Available Sleep States"; Obj = $states; Type = "Html" },
            @{ Title = "Active Power Requests"; Obj = $requests; Type = "Html" }
        )
    }

    # 3. Last Wake & Timers
    Set-Progress 40
    Out-Status "Checking wake history and timers..."
    $lastWake = Get-PowerCfgText "/lastwake"
    $timers = Get-PowerCfgText "/waketimers"

    $mySections += @{
        Id = "wake"; Title = "Wake Diagnostics"; Type = "GridKeyValue"; Collapsible = $false;
        Data = @(
            @{ Title = "Last Wake Event"; Obj = $lastWake; Type = "Html" },
            @{ Title = "Scheduled Wake Timers"; Obj = $timers; Type = "Html" }
        )
    }

    # 4. Energy Report (Takes 60 Seconds)
    if ($RunEnergyReport) {
        Set-Progress 60
        Out-Status "Running Energy Report (Waiting 60s)..."
        $energyPath = Join-Path $bundleRoot "energy-report.html"
        # Run directly to catch the 60s wait
        powercfg.exe /energy /output $energyPath | Out-Null
        Out-Status "[OK] Energy report generated."
    }

    # 5. Battery Report
    if ($RunBatteryReport) {
        Set-Progress 90
        Out-Status "Generating Battery Report..."
        $batteryPath = Join-Path $bundleRoot "battery-report.html"
        powercfg.exe /batteryreport /output $batteryPath | Out-Null
        Out-Status "[OK] Battery report generated."
    }

    # 6. File Links Section
    $files = Get-ChildItem $bundleRoot -File | Select-Object Name, @{n = "Size(KB)"; e = { [math]::Round($_.Length / 1KB, 1) } }
    if ($files) {
        $mySections += @{ Id = "files"; Title = "Generated HTML Reports"; Type = "Table"; Data = $files; BaseDir = $bundleRoot; Expanded = $true }
    }

    # ---- GENERATE FINAL HTML ----
    Set-Progress 95
    Out-Status "Assembling Toolkit Report..."
    $reportPath = Join-Path $bundleRoot "POWER_DIAGNOSTICS.html"

    New-ToolkitGenericReport -ReportPath $reportPath `
        -Title "Power & Sleep Analysis" `
        -ComputerName $computer `
        -ReportSections $mySections

    Set-Progress 100
    Out-Status "[OK] Done. Report created at $reportPath"

} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}