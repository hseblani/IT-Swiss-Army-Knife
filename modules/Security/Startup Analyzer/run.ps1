param(
    [Parameter()][bool]$WhatIfMode = $false,
    [Parameter()][bool]$IncludeRunKeys = $true,
    [Parameter()][bool]$IncludeStartupFolders = $true,
    [Parameter()][bool]$IncludeScheduledTasks = $true,
    [Parameter()][bool]$IncludeAutoServices = $true,

    [Parameter()][string]$ExportFolder = "__MODULE_OUTPUT__",
    [Parameter()][bool]$ExportJson = $true,
    [Parameter()][bool]$ExportCsv = $false,
    [Parameter()][bool]$ExportHtml = $true
)

# Shared helpers (New-ToolkitGenericReport is here)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Out-Info([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }

function Set-Progress([int]$p) {
    Write-Information ("PROGRESS:{0}" -f $p)
}

function Ensure-Folder([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# -------------------- DATA COLLECTION --------------------
function Get-RunKeyData {
    $list = @()
    $paths = @(
        @{ p = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; s = 'HKLM' },
        @{ p = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; s = 'HKLM' },
        @{ p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; s = 'HKCU' },
        @{ p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; s = 'HKCU' }
    )
    foreach ($item in $paths) {
        if (Test-Path $item.p) {
            $props = (Get-ItemProperty $item.p).PSObject.Properties | Where-Object { $_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider') }
            foreach ($pr in $props) {
                $list += [pscustomobject]@{ Name = $pr.Name; Command = [string]$pr.Value; Scope = $item.s; Location = $item.p }
            }
        }
    }
    return $list
}

function Get-StartupFolderData {
    $list = @()
    $folders = @(
        @{ p = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; s = 'Current User' },
        @{ p = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; s = 'All Users' }
    )
    foreach ($f in $folders) {
        if (Test-Path $f.p) {
            Get-ChildItem $f.p -File | ForEach-Object {
                $list += [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Scope = $f.s }
            }
        }
    }
    return $list
}

function Get-TaskData {
    # Get only active tasks to reduce noise and potential errors
    $tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' }
    $list = @()

    foreach ($t in $tasks) {
        $triggerMatch = $false

        # Ensure Triggers property exists and is not null
        if ($t.PSObject.Properties['Triggers'] -and $t.Triggers) {
            foreach ($tr in $t.Triggers) {
                # Strict-safe check for TriggerType property
                if ($tr.PSObject.Properties['TriggerType']) {
                    $tt = [string]$tr.TriggerType
                    if ($tt -match 'Logon|Boot|Startup') {
                        $triggerMatch = $true
                        break
                    }
                }
            }
        }

        if ($triggerMatch) {
            $actionStr = "Unknown Action"
            # Ensure Actions property exists and is not null
            if ($t.PSObject.Properties['Actions'] -and $t.Actions) {
                try {
                    $actionStr = ($t.Actions | ForEach-Object {
                            $exec = if ($_.PSObject.Properties['Execute']) { [string]$_.Execute } else { "" }
                            $args = if ($_.PSObject.Properties['Arguments']) { [string]$_.Arguments } else { "" }
                            ($exec + " " + $args).Trim()
                        }) -join " | "
                } catch { $actionStr = "Complex Action" }
            }

            $list += [pscustomobject]@{
                TaskName = [string]$t.TaskName
                Action   = $actionStr
                Path     = [string]$t.TaskPath
            }
        }
    }
    return $list
}

# -------------------- MAIN --------------------
try {
    Set-Progress 5
    $computer = $env:COMPUTERNAME
    if ($ExportFolder -eq "__MODULE_OUTPUT__") { $ExportFolder = Join-Path $env:TEMP "Toolkit-StartupAnalyzer" }
    Ensure-Folder $ExportFolder

    $reportSections = @()

    # 1. Dashboard (Flat Summary)
    $summary = [PSCustomObject]@{
        ScanDate = (Get-Date).ToString()
        User     = $env:USERNAME
        OS       = (Get-CimInstance Win32_OperatingSystem).Caption
    }
    $reportSections += @{ Id = "sys"; Title = "Scan Summary"; Type = "GridKeyValue"; Collapsible = $false; Data = @(@{ Title = "Environment"; Obj = $summary }) }

    # 2. Registry Keys
    if ($IncludeRunKeys) {
        Set-Progress 25
        Out-Info "Scanning Registry Run keys..."
        $regData = Get-RunKeyData
        $reportSections += @{ Id = "reg"; Title = "Registry Startup Keys"; Type = "Table"; Data = $regData; Expanded = $true }
    }

    # 3. Startup Folders
    if ($IncludeStartupFolders) {
        Set-Progress 50
        Out-Info "Scanning Startup folders..."
        $foldData = Get-StartupFolderData
        $reportSections += @{ Id = "folders"; Title = "Startup Folder Items"; Type = "Table"; Data = $foldData; Expanded = $true }
    }

    # 4. Scheduled Tasks
    if ($IncludeScheduledTasks) {
        Set-Progress 75
        Out-Info "Scanning Scheduled Tasks..."
        $taskData = Get-TaskData
        $reportSections += @{ Id = "tasks"; Title = "Logon/Boot Tasks"; Type = "Table"; Data = $taskData; Expanded = $false }
    }

    # 5. Auto-Services
    if ($IncludeAutoServices) {
        Set-Progress 90
        Out-Info "Scanning Auto-Start Services..."
        $svcData = Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' } | Select-Object Name, DisplayName, State
        $reportSections += @{ Id = "svcs"; Title = "Auto-Start Services"; Type = "Table"; Data = $svcData; Expanded = $false }
    }

    # ---- GENERATE HTML REPORT ----
    if ($ExportHtml) {
        Set-Progress 95
        Out-Info "Generating HTML Report..."
        $htmlPath = Join-Path $ExportFolder "StartupReport.html"

        # Call the generic engine
        New-ToolkitGenericReport -ReportPath $htmlPath `
            -Title "Startup Analyzer Report" `
            -ComputerName $computer `
            -ReportSections $reportSections

        Out-Info "[OK] Report: $htmlPath"
    }

    Set-Progress 100
    Write-Host ""
    Write-Host "[OK] Startup Analysis Complete." -ForegroundColor Green

} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}