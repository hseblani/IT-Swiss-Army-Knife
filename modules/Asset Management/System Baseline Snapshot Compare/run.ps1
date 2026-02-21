param(
    [bool]$WhatIfMode = $true,
    [string]$Mode = "CreateSnapshot",
    [string]$SnapshotFolder = "__MODULE_OUTPUT__",
    [string]$SnapshotName = "Baseline",
    [bool]$AddTimestamp = $true,
    [string]$OldSnapshotFile = "",
    [string]$NewSnapshotFile = ""
)

# Shared helpers
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- COLLECTION HELPERS --------------------
function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }
function Set-Progress([int]$p) { Write-Information ("PROGRESS:{0}" -f $p) }

function Get-SystemBaseline {
    Set-Progress 5
    Out-Status "Collecting OS and Environment..."
    $os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
    $envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

    Set-Progress 15
    Out-Status "Hashing Hosts file..."
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsHash = if (Test-Path $hostsPath) { (Get-FileHash $hostsPath -Algorithm SHA256).Hash } else { "Missing" }

    Set-Progress 25
    Out-Status "Collecting Local Administrators..."
    $admins = try { Get-LocalGroupMember -Group "Administrators" | Select-Object Name, PrincipalSource, ObjectClass } catch { @() }

    Set-Progress 35
    Out-Status "Collecting Scheduled Tasks (Logon/Boot)..."
    $tasksList = New-Object System.Collections.Generic.List[object]
    try {
        $allTasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' }
        foreach ($t in $allTasks) {
            $isMatch = $false
            if ($t.PSObject.Properties['Triggers'] -and $t.Triggers) {
                foreach ($tr in $t.Triggers) {
                    if ($tr.PSObject.Properties['TriggerType']) {
                        if ([string]$tr.TriggerType -match 'Logon|Boot|Startup') { $isMatch = $true; break }
                    }
                }
            }
            if ($isMatch) { $tasksList.Add([pscustomobject]@{ TaskName = [string]$t.TaskName; TaskPath = [string]$t.TaskPath }) }
        }
    } catch { }

    Set-Progress 45
    Out-Status "Collecting Services..."
    $svc = Get-Service | Select-Object Name, Status, StartType

    Set-Progress 55
    Out-Status "Collecting Registry Run keys..."
    $runKeys = New-Object System.Collections.Generic.List[object]
    $regPaths = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Run", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            $p = Get-ItemProperty $path
            $p.PSObject.Properties | Where-Object { $_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider') } | ForEach-Object {
                $runKeys.Add([pscustomobject]@{ Name = [string]$_.Name; Command = [string]$_.Value })
            }
        }
    }

    Set-Progress 65
    Out-Status "Collecting Firewall profiles..."
    $fw = Get-NetFirewallProfile | Select-Object Name, Enabled

    Set-Progress 75
    Out-Status "Collecting Drivers inventory..."
    $drivers = Get-CimInstance Win32_PnPSignedDriver | Select-Object InfName, DeviceName, DriverVersion, DriverProviderName

    Set-Progress 85
    Out-Status "Collecting Installed Apps..."
    $apps = New-Object System.Collections.Generic.List[object]
    $uninstPaths = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
    foreach ($path in $uninstPaths) {
        if (Test-Path $path) {
            Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $prop = Get-ItemProperty $_.PSPath -ErrorAction Stop
                    if ($prop.PSObject.Properties['DisplayName'] -and $prop.DisplayName) {
                        $apps.Add([pscustomobject]@{ Name = [string]$prop.DisplayName; Version = [string]$prop.DisplayVersion })
                    }
                } catch {}
            }
        }
    }

    return [pscustomobject]@{
        Metadata = @{ Computer = [string]$env:COMPUTERNAME; Date = (Get-Date).ToString(); User = [string]$env:USERNAME }
        OS       = $os
        Hosts    = @{ SHA256 = [string]$hostsHash }
        Admins   = $admins
        Tasks    = $tasksList
        Services = $svc
        RunKeys  = $runKeys
        Firewall = $fw
        Drivers  = $drivers
        Apps     = $apps | Sort-Object Name -Unique
        PathVar  = @{ Value = [string]$envPath }
    }
}

function Compare-Collections($old, $new, [string]$key) {
    $results = New-Object System.Collections.Generic.List[object]

    # Initialize maps (Safe check for nulls to satisfy StrictMode)
    $oldMap = @{}
    if ($null -ne $old) {
        foreach ($i in $old) { if ($i.$key) { $oldMap[[string]$i.$key] = $i } }
    }

    $newMap = @{}
    if ($null -ne $new) {
        foreach ($i in $new) { if ($i.$key) { $newMap[[string]$i.$key] = $i } }
    }

    # Find Added & Changed
    foreach ($k in $newMap.Keys) {
        if (-not $oldMap.ContainsKey($k)) {
            $results.Add([pscustomobject]@{ Item = $k; Action = "ADDED"; Status = "Success" })
        } else {
            # Deep compare using compressed JSON
            $oldJson = $oldMap[$k] | ConvertTo-Json -Compress
            $newJson = $newMap[$k] | ConvertTo-Json -Compress
            if ($oldJson -ne $newJson) {
                $results.Add([pscustomobject]@{ Item = $k; Action = "CHANGED"; Status = "Warning" })
            }
        }
    }

    # Find Removed
    foreach ($k in $oldMap.Keys) {
        if (-not $newMap.ContainsKey($k)) {
            $results.Add([pscustomobject]@{ Item = $k; Action = "REMOVED"; Status = "Error" })
        }
    }

    return $results | Sort-Object Action, Item
}

# -------------------- MAIN --------------------
try {
    if ($Mode -eq "CreateSnapshot") {
        if ($SnapshotFolder -eq "__MODULE_OUTPUT__") { $SnapshotFolder = Join-Path $env:TEMP "Toolkit-Snapshots" }
        if ($WhatIfMode) { Out-Status "[WHATIF] Would save to $SnapshotFolder"; Set-Progress 100; return }

        if (-not (Test-Path $SnapshotFolder)) { New-Item $SnapshotFolder -ItemType Directory -Force | Out-Null }
        $ts = if ($AddTimestamp) { "_" + (Get-Date -Format "yyyyMMdd_HHmmss") } else { "" }
        $outPath = Join-Path $SnapshotFolder "$SnapshotName$ts.json"

        (Get-SystemBaseline) | ConvertTo-Json -Depth 10 | Out-File $outPath -Encoding UTF8
        Set-Progress 100
        Out-Status "[OK] Snapshot saved: $outPath"
    } else {
        # --- COMPARE MODE ---
        if (-not (Test-Path $OldSnapshotFile) -or -not (Test-Path $NewSnapshotFile)) { throw "Select both files." }
        Out-Status "Loading snapshots..."
        $o = Read-ToolkitJson $OldSnapshotFile; $n = Read-ToolkitJson $NewSnapshotFile
        $mySections = @()

        # 1. System Overview (Dashboard)
        $meta = [PSCustomObject]@{ Old = (Split-Path $OldSnapshotFile -Leaf); New = (Split-Path $NewSnapshotFile -Leaf); PC = $n.Metadata.Computer }
        $mySections += @{ Id = "sys"; Title = "System Comparison Overview"; Type = "GridKeyValue"; Collapsible = $false; Data = @(@{ Title = "Session Info"; Obj = $meta }) }

        # 2. Integrity Alerts (Dashboard style)
        $integrity = @()
        if ($o.Hosts.SHA256 -ne $n.Hosts.SHA256) { $integrity += [pscustomobject]@{ Check = "Hosts File"; Note = "Integrity Mismatch (File Modified)"; Status = "Warning" } }
        if ($o.PathVar.Value -ne $n.PathVar.Value) { $integrity += [pscustomobject]@{ Check = "System PATH"; Note = "Environment Variables Changed"; Status = "Warning" } }
        if ($integrity) { $mySections += @{ Id = "int"; Title = "Integrity Alerts"; Type = "Table"; Data = $integrity; Collapsible = $false } }

        # 3. Security & Core Changes (Expanded)
        Out-Status "Comparing Core Settings..."
        $mySections += @{ Id = "adm"; Title = "Local Admin Changes"; Type = "Table"; Data = (Compare-Collections $o.Admins $n.Admins "Name"); Expanded = $true }
        $mySections += @{ Id = "fw"; Title = "Firewall Profile Changes"; Type = "Table"; Data = (Compare-Collections $o.Firewall $n.Firewall "Name"); Expanded = $true }
        $mySections += @{ Id = "app"; Title = "Installed App Changes"; Type = "Table"; Data = (Compare-Collections $o.Apps $n.Apps "Name"); Expanded = $true }

        # 4. Persistence & Drivers (Collapsed)
        Out-Status "Comparing Persistence & Drivers..."
        $mySections += @{ Id = "run"; Title = "Registry Run Key Changes"; Type = "Table"; Data = (Compare-Collections $o.RunKeys $n.RunKeys "Name"); Expanded = $false }
        $mySections += @{ Id = "tsk"; Title = "Scheduled Task Changes"; Type = "Table"; Data = (Compare-Collections $o.Tasks $n.Tasks "TaskName"); Expanded = $false }
        $mySections += @{ Id = "svc"; Title = "Service Changes"; Type = "Table"; Data = (Compare-Collections $o.Services $n.Services "Name"); Expanded = $false }
        $mySections += @{ Id = "drv"; Title = "Driver Inventory Changes"; Type = "Table"; Data = (Compare-Collections $o.Drivers $n.Drivers "InfName"); Expanded = $false }

        Out-Status "Generating Comparison Report..."
        $rep = Join-Path (Split-Path $NewSnapshotFile) "Comparison_Report.html"
        New-ToolkitGenericReport -ReportPath $rep -Title "System Baseline Comparison" -ComputerName $n.Metadata.Computer -ReportSections $mySections

        Set-Progress 100
        Out-Status "[OK] Comparison Complete. Report: $rep"
    }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}