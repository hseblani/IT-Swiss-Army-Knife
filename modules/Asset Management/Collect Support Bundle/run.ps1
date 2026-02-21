param(
    [bool]$WhatIfMode = $true,

    [string]$OutputFolder = "__MODULE_OUTPUT__",
    [string]$BundleName = "SupportBundle",
    [bool]$AddTimestamp = $true,

    [string]$CmdTimeoutSec = "60",

    [bool]$IncludeSystemInfo = $true,
    [bool]$IncludeNetwork = $true,
    [bool]$IncludeServices = $true,
    [bool]$IncludeInstalledApps = $true,
    [bool]$IncludeDrivers = $true,
    [bool]$IncludeDisk = $true,
    [bool]$IncludeDefender = $true,
    [bool]$IncludeEventLogs = $true,
    [bool]$CreateZip = $true,

    [bool]$EventsOnly = $false,

    [string]$EventLogsMode = "EvtxFast",   # EvtxFast | JsonSummary
    [string]$EventLogDays = "7",
    [string]$MaxEventsPerLog = "500",

    [bool]$IncludeMinidumps = $true,
    [bool]$IncludeCBSLogs = $false
)

. (Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- helpers --------------------
function Out-Info([string]$m) {
    Write-Information $m
}

<#function Set-ToolkitProgress([int]$p, [string]$status = "") {
    if ($p -lt 0) { $p = 0 }
    if ($p -gt 100) { $p = 100 }
    Write-Information ("PROGRESS:{0}" -f $p)
    if ($status) { Out-Info $status }
}#>
function Set-ToolkitProgress([int]$p, [string]$status = "") {
    if ($p -lt 0) { $p = 0 }
    if ($p -gt 100) { $p = 100 }

    # Send numeric progress to the progress bar
    Write-Information ("PROGRESS:{0}" -f $p)

    # Send text status to the console
    if ($status) {
        # Using a specific prefix the engine can recognize for "System" messages
        Write-Host "[Status] $status" -ForegroundColor Gray
    }
}

function Ensure-Folder([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

function Try-WriteJson($obj, [string]$path) {
    try {
        $obj | ConvertTo-Json -Depth 6 | Out-File -FilePath $path -Encoding UTF8 -Force
        return $true
    } catch {
        Out-Info "[WARN] Failed to write JSON: $path : $($_.Exception.Message)"
        return $false
    }
}

function Invoke-ExternalWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][string]$Arguments = "",
        [Parameter(Mandatory = $false)][int]$TimeoutSec = 60
    )

    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        throw "Timeout running: $FilePath $Arguments"
    }
    if ($p.ExitCode -ne 0) {
        throw "Command failed (exit $($p.ExitCode)): $FilePath $Arguments"
    }
}

# -------------------- main --------------------
try {
    $timeout = 60
    [void][int]::TryParse($CmdTimeoutSec, [ref]$timeout)
    if ($timeout -lt 5) { $timeout = 5 }

    $days = 7
    [void][int]::TryParse($EventLogDays, [ref]$days)
    if ($days -lt 1) { $days = 1 }

    $maxEv = 500
    [void][int]::TryParse($MaxEventsPerLog, [ref]$maxEv)
    if ($maxEv -lt 50) { $maxEv = 50 }

    $computer = $env:COMPUTERNAME

    if ($OutputFolder -eq "__MODULE_OUTPUT__") {
        $OutputFolder = Join-Path $env:TEMP "IT-SwissArmyKnife-Output"
    }
    Ensure-Folder $OutputFolder

    $suffix = ""
    if ($AddTimestamp) {
        # Adds -ComputerName-Timestamp
        $suffix = "-$computer-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    } else {
        # Adds only -ComputerName
        $suffix = "-$computer"
    }

    $bundleFolderName = "$BundleName$suffix"
    $bundleRoot = Join-Path $OutputFolder $bundleFolderName

    # Events-only mode: force-disable everything else
    if ($EventsOnly) {
        $IncludeSystemInfo = $false
        $IncludeNetwork = $false
        $IncludeServices = $false
        $IncludeInstalledApps = $false
        $IncludeDrivers = $false
        $IncludeDisk = $false
        $IncludeDefender = $false
        $IncludeMinidumps = $false
        $IncludeCBSLogs = $false

        $IncludeEventLogs = $true

        Out-Info "[Mode] EventsOnly enabled: other sections disabled."
    }

    # Dry run: do not create bundle folder, do not collect
    if ($WhatIfMode) {
        Out-Info "[WHATIF] Dry-run enabled. No files will be collected."
        Out-Info "[WHATIF] Would create bundle folder: $bundleRoot"
        Out-Info "[WHATIF] Sections enabled: System=$IncludeSystemInfo Network=$IncludeNetwork Services=$IncludeServices Apps=$IncludeInstalledApps Drivers=$IncludeDrivers Disk=$IncludeDisk Defender=$IncludeDefender EventLogs=$IncludeEventLogs"
        Out-Info "[WHATIF] EventLogsMode=$EventLogsMode Days=$days MaxEventsPerLog=$maxEv"
        Out-Info "[WHATIF] Optional: Minidumps=$IncludeMinidumps CBSLogs=$IncludeCBSLogs"
        Set-ToolkitProgress 100 "Dry run complete."
        return
    }

    # Real run starts here
    Ensure-Folder $bundleRoot
    Set-ToolkitProgress 5 "Creating bundle folder: $bundleRoot"
    # ---- Save report settings (so HTML can hide disabled sections) ----
    $settings = [PSCustomObject]@{
        IncludeSystemInfo    = $IncludeSystemInfo
        IncludeNetwork       = $IncludeNetwork
        IncludeServices      = $IncludeServices
        IncludeInstalledApps = $IncludeInstalledApps
        IncludeDrivers       = $IncludeDrivers
        IncludeDisk          = $IncludeDisk
        IncludeDefender      = $IncludeDefender
        IncludeEventLogs     = $IncludeEventLogs
        IncludeMinidumps     = $IncludeMinidumps
        IncludeCBSLogs       = $IncludeCBSLogs
        EventsOnly           = $EventsOnly
        CreateZip            = $CreateZip
        EventLogsMode        = $EventLogsMode
        EventLogDays         = $EventLogDays
        MaxEventsPerLog      = $MaxEventsPerLog
    }
    Try-WriteJson $settings (Join-Path $bundleRoot "report_settings.json") | Out-Null

    # ---- System info ----
    if ($IncludeSystemInfo) {
        Set-ToolkitProgress 10 "Collecting system info..."
        $p = Join-Path $bundleRoot "system"
        Ensure-Folder $p

        Try-WriteJson (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime) (Join-Path $p "os.json") | Out-Null
        Try-WriteJson (Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemType, TotalPhysicalMemory, Domain, UserName) (Join-Path $p "computer.json") | Out-Null
        Try-WriteJson (Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate) (Join-Path $p "bios.json") | Out-Null
        Try-WriteJson (Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber, Version) (Join-Path $p "baseboard.json") | Out-Null
    } else {
        Out-Info "[Skip] System info disabled."
    }

    # ---- Network ----
    if ($IncludeNetwork) {
        Set-ToolkitProgress 25 "Collecting network info..."
        $p = Join-Path $bundleRoot "network"
        Ensure-Folder $p

        Try-WriteJson (Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress) (Join-Path $p "netadapter.json") | Out-Null
        Try-WriteJson (Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv6Address, DNSServer, IPv4DefaultGateway) (Join-Path $p "ipconfig.json") | Out-Null
    } else {
        Out-Info "[Skip] Network disabled."
    }

    # ---- Services and processes ----
    if ($IncludeServices) {
        Set-ToolkitProgress 40 "Collecting services and processes..."
        $p = Join-Path $bundleRoot "services"
        Ensure-Folder $p

        Try-WriteJson (Get-Service | Select-Object Name, DisplayName, Status, StartType | Sort-Object Name) (Join-Path $p "services.json") | Out-Null
        Try-WriteJson (Get-Process | Select-Object ProcessName, Id, CPU, WS | Sort-Object ProcessName) (Join-Path $p "processes.json") | Out-Null
    } else {
        Out-Info "[Skip] Services/processes disabled."
    }

    # ---- Installed apps ----
    if ($IncludeInstalledApps) {
        Set-ToolkitProgress 55 "Collecting installed applications..."
        $p = Join-Path $bundleRoot "apps"
        Ensure-Folder $p

        $apps = New-Object System.Collections.Generic.List[object]

        function Get-RegProp($obj, [string]$name) {
            try {
                $pp = $obj.PSObject.Properties[$name]
                if ($null -ne $pp) { return $pp.Value }
            } catch {}
            return $null
        }

        function Add-UninstallAppsFrom([string]$regPath, [string]$scope) {
            try {
                # Get the subkeys first instead of the properties directly
                # We remove the '*' from the end to get the parent container
                $parentPath = $regPath.Replace("\*", "")
                $keys = Get-ChildItem -Path $parentPath -ErrorAction SilentlyContinue

                if (-not $keys) { return }

                $countAdded = 0
                foreach ($key in $keys) {
                    try {
                        # Try to get properties for this specific app only
                        $r = Get-ItemProperty -Path $key.PSPath -ErrorAction Stop

                        $dn = [string](Get-RegProp $r "DisplayName")
                        if ([string]::IsNullOrWhiteSpace($dn)) { continue }

                        $apps.Add([PSCustomObject]@{
                                Scope           = $scope
                                DisplayName     = $dn
                                Version         = [string](Get-RegProp $r "DisplayVersion")
                                Publisher       = [string](Get-RegProp $r "Publisher")
                                InstallDate     = [string](Get-RegProp $r "InstallDate")
                                InstallLocation = [string](Get-RegProp $r "InstallLocation")
                                UninstallString = [string](Get-RegProp $r "UninstallString")
                            })
                        $countAdded++
                    } catch {
                        # If one specific app key is corrupt, skip it and move to the next
                        continue
                    }
                }
                Out-Info ("[Apps] {0} entries from {1}" -f $countAdded, $scope)
            } catch {
                Out-Info ("[WARN] Failed reading {0}: {1}" -f $regPath, $_.Exception.Message)
            }
        }

        Add-UninstallAppsFrom "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" "HKLM-64"
        Add-UninstallAppsFrom "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" "HKLM-32"
        Add-UninstallAppsFrom "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" "HKCU"

        try {
            $appx = Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    Scope           = "AppX"
                    DisplayName     = $_.Name
                    Version         = $_.Version.ToString()
                    Publisher       = $_.Publisher
                    InstallDate     = ""
                    InstallLocation = $_.InstallLocation
                    UninstallString = ""
                }
            }
            foreach ($it in @($appx)) { $apps.Add($it) }
            Out-Info ("[Apps] {0} AppX packages" -f (@($appx).Count))
        } catch {
            Out-Info ("[WARN] AppX query failed: {0}" -f $_.Exception.Message)
        }

        $appsFinal = $apps |
        Where-Object { $_.DisplayName } |
        Sort-Object Scope, DisplayName -Unique

        Out-Info ("[Apps] Total written: {0}" -f (@($appsFinal).Count))
        Try-WriteJson $appsFinal (Join-Path $p "installed_apps.json") | Out-Null
    } else {
        Out-Info "[Skip] Installed apps disabled."
    }

    # ---- Drivers inventory ----
    if ($IncludeDrivers) {
        Set-ToolkitProgress 65 "Collecting drivers inventory..."
        $p = Join-Path $bundleRoot "drivers"
        Ensure-Folder $p

        Try-WriteJson (Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion, DriverProviderName, InfName, DriverDate) (Join-Path $p "pnp_signed_drivers.json") | Out-Null
    } else {
        Out-Info "[Skip] Drivers disabled."
    }

    # ---- Disk / volumes ----
    if ($IncludeDisk) {
        Set-ToolkitProgress 75 "Collecting disk and volume info..."
        $p = Join-Path $bundleRoot "disk"
        Ensure-Folder $p

        Try-WriteJson (Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, HealthStatus, SizeRemaining, Size) (Join-Path $p "volumes.json") | Out-Null
        Try-WriteJson (Get-Disk | Select-Object Number, FriendlyName, SerialNumber, BusType, PartitionStyle, OperationalStatus, Size) (Join-Path $p "disks.json") | Out-Null
    } else {
        Out-Info "[Skip] Disk disabled."
    }

    # ---- Defender status ----
    if ($IncludeDefender) {
        Set-ToolkitProgress 82 "Collecting Defender status (if available)..."
        $p = Join-Path $bundleRoot "security"
        Ensure-Folder $p

        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            Try-WriteJson ($mp | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, AntispywareEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, NISEnabled, AMServiceEnabled, AntivirusSignatureLastUpdated) (Join-Path $p "defender_status.json") | Out-Null
        } catch {
            Out-Info "[WARN] Defender status not available: $($_.Exception.Message)"
        }
    } else {
        Out-Info "[Skip] Defender disabled."
    }

    # ---- Event logs (toggle) ----
    if ($IncludeEventLogs) {
        Set-ToolkitProgress 88 "Collecting event logs ($EventLogsMode)..."
        $p = Join-Path $bundleRoot "eventlogs"
        Ensure-Folder $p

        $startTime = (Get-Date).AddDays(-1 * $days)
        $logs = @("System", "Application", "Security")

        foreach ($ln in $logs) {
            if ($EventLogsMode -eq "EvtxFast") {
                $dst = Join-Path $p ("{0}.evtx" -f $ln)
                Invoke-ExternalWithTimeout -FilePath "wevtutil.exe" -Arguments ("epl {0} `"{1}`"" -f $ln, $dst) -TimeoutSec $timeout
            } else {
                try {
                    $events = Get-WinEvent -FilterHashtable @{ LogName = $ln; StartTime = $startTime } -ErrorAction Stop |
                    Select-Object -First $maxEv TimeCreated, Id, LevelDisplayName, ProviderName, Message
                    Try-WriteJson $events (Join-Path $p ("{0}.json" -f $ln)) | Out-Null
                } catch {
                    Out-Info "[WARN] Failed to read $ln events: $($_.Exception.Message)"
                }
            }
        }
    } else {
        Out-Info "[Skip] Event logs disabled."
    }

    # ---- Optional files: Minidumps ----
    if ($IncludeMinidumps) {
        Set-ToolkitProgress 92 "Collecting optional files..."
        $src = Join-Path $env:SystemRoot "Minidump"

        if (Test-Path -LiteralPath $src) {
            $dst = Join-Path $bundleRoot "Minidump"
            Ensure-Folder $dst

            # Copy
            Copy-Item -Path (Join-Path $src "*") -Destination $dst -Force -ErrorAction SilentlyContinue

            # Safe count
            $dumpCount = @(Get-ChildItem -LiteralPath $dst -File -ErrorAction SilentlyContinue).Count
            Out-Info ("[Minidump] Copied files: {0}" -f $dumpCount)
        } else {
            Out-Info "[Minidump] Source folder not found. Skipping."
        }
    } else {
        Out-Info "[Skip] Minidumps disabled."
    }

    # ---- Optional files: CBS ----
    if ($IncludeCBSLogs) {
        $src = Join-Path $env:windir "Logs\CBS"
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination (Join-Path $bundleRoot "CBS") -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Out-Info "[Skip] CBS logs disabled."
    }

    # Build portable hardware tree JSON inside the bundle (only useful if system is enabled)
    function ConvertTo-ToolkitHtmlTree {
        param([Parameter(Mandatory = $true)]$Node)

        function Render-Node($n) {
            # Strict-safe property access
            $name = "Unknown"
            if ($n.PSObject.Properties['name']) { $name = [string]$n.name }

            $desc = ""
            if ($n.PSObject.Properties['desc'] -and $n.desc) {
                $desc = " <span class='tree-desc'>$($n.desc)</span>"
            }

            # Force children to be an array
            $children = @()
            if ($n.PSObject.Properties['children'] -and $n.children) {
                $children = [object[]]@($n.children)
            }

            if ($children.Count -gt 0) {
                $childHtml = ""
                foreach ($child in $children) {
                    $childHtml += Render-Node $child
                }
                # Category nodes are always expanded per your request
                return "<li><details open><summary><b>$name</b>$desc</summary><ul>$childHtml</ul></details></li>"
            } else {
                # Leaf node
                return "<li class='tree-leaf'>$name$desc</li>"
            }
        }

        return "<div class='tree-view'><ul>" + (Render-Node $Node) + "</ul></div>"
    }

    # ---- Generate report ----
    Set-ToolkitProgress 95 "Generating report..."
    $reportPath = Join-Path $bundleRoot "REPORT.html"

    # BUILD THE REPORT MANIFEST
    $mySections = @()

    # --- SYSTEM OVERVIEW: PLAIN DISPLAY ---
    $mySections += @{
        Id          = "sys"  # <--- CRITICAL: The engine looks for this exact string
        Title       = "System Overview"
        Type        = "GridKeyValue"
        Collapsible = $false
        Data        = @(
            @{ Title = "Operating System"; Obj = Read-ToolkitJson (Join-Path $bundleRoot "system\os.json") },
            @{ Title = "Hardware Environment"; Obj = Read-ToolkitJson (Join-Path $bundleRoot "system\computer.json") }
        )
    }

    # Hardware (Expanded Tree)
    $hwPath = Join-Path $bundleRoot "system\hardware_tree.json"
    if (Test-Path $hwPath) {
        $mySections += @{
            Id          = "hw"
            Title       = "Hardware Inventory"
            Type        = "Tree"
            Collapsible = $true
            Expanded    = $true
            Data        = Read-ToolkitJson $hwPath
        }
    }

    # 3. APPLICATIONS & SERVICES (Collapsed)
    if ($IncludeInstalledApps) {
        $appsData = Read-ToolkitJson (Join-Path $bundleRoot "apps\installed_apps.json")
        if ($appsData) {
            $mySections += @{ Id = "apps"; Title = "Installed Applications"; Type = "Table"; Data = $appsData; Expanded = $false }
        }
    }

    if ($IncludeServices) {
        $svcData = Read-ToolkitJson (Join-Path $bundleRoot "services\services.json")
        if ($svcData) {
            $mySections += @{ Id = "svc"; Title = "System Services"; Type = "Table"; Data = $svcData; Expanded = $false }
        }
    }

    # 4. NETWORK & DISK (Expanded)
    if ($IncludeNetwork) {
        $netData = Read-ToolkitJson (Join-Path $bundleRoot "network\netadapter.json")
        if ($netData) {
            $mySections += @{ Id = "net"; Title = "Network Adapters"; Type = "Table"; Data = $netData; Expanded = $true }
        }
    }

    if ($IncludeDisk) {
        $diskData = Read-ToolkitJson (Join-Path $bundleRoot "disk\volumes.json")
        if ($diskData) {
            $mySections += @{ Id = "disk"; Title = "Storage Volumes"; Type = "Table"; Data = $diskData; Expanded = $true }
        }
    }

    # 5. FILE FOLDERS (Clickable links to Directory)
    $folders = @(
        @{ Id = "evtx"; Title = "Event Logs"; Path = "eventlogs" },
        @{ Id = "dump"; Title = "Minidumps"; Path = "Minidump" },
        @{ Id = "cbs"; Title = "CBS Logs"; Path = "CBS" }
    )
    foreach ($f in $folders) {
        $absPath = Join-Path $bundleRoot $f.Path
        if (Test-Path $absPath) {
            $files = Get-ChildItem $absPath -File | Select-Object Name, @{n = "Size(KB)"; e = { [math]::Round($_.Length / 1KB, 1) } }, LastWriteTime
            $mySections += @{ Id = $f.Id; Title = $f.Title; Type = "Table"; Data = $files; BaseDir = $absPath; Expanded = $true }
        }
    }

    # CALL THE GLOBAL GENERIC ENGINE
    New-ToolkitGenericReport -ReportPath $reportPath `
        -Title "System Support Bundle" `
        -ComputerName $computer `
        -ReportSections $mySections

    # ---- ZIP ----
    if ($CreateZip) {
        Set-ToolkitProgress 98 "Creating ZIP..."
        $zipPath = Join-Path $OutputFolder ("{0}.zip" -f $bundleFolderName)
        if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path (Join-Path $bundleRoot "*") -DestinationPath $zipPath -Force
        Out-Info "[OK] Bundle ZIP   : $zipPath"
    } else {
        Out-Info "[Skip] ZIP creation disabled."
    }

    Set-ToolkitProgress 100 "Done."
    Out-Info "[OK] Bundle folder: $bundleRoot"
    if ($CreateZip) { Out-Info "[OK] Bundle ZIP   : $zipPath" }
    Out-Info "[OK] Report       : $reportPath"
} catch {
    Out-Info "[ERROR] $($_.Exception.Message)"
    throw
}
