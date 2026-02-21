# modules\_shared\common.ps1
# Shared helpers for IT Swiss-Army Knife modules (optional import by the GUI runner)

function Write-ToolkitProgress {
    param(
        [Parameter(Mandatory = $true)][int]$Percent,
        [string]$Status = ""
    )

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    # Standard marker consumed by the GUI:
    #   PROGRESS:0..100
    Write-Information ("PROGRESS:{0}" -f $Percent)

    # Optional human-readable status line (also goes through Information stream)
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        Write-Information $Status
    }
}


function Write-ToolkitSection {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Information ""
    Write-Information ("=== {0} ===" -f $Title)
}

function Test-Admin {
    try {
        return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } catch { return $false }
}

# =========================================================
# IT Swiss-Army Knife - Shared HTML Report Engine (V8 - FINAL)
# =========================================================

# --- 1. CORE HELPERS ---

function ConvertTo-ToolkitHtmlEncoded {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return [System.Web.HttpUtility]::HtmlEncode($Text)
}

function Read-ToolkitJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) { return $null }
        # Ensure we return a PSCustomObject
        return ($content | ConvertFrom-Json)
    } catch { return $null }
}

# --- 2. HTML COMPONENT BUILDERS ---

function ConvertTo-ToolkitHtmlTable {
    param([AllowNull()]$Items, [AllowNull()]$Columns, [string]$BaseDir = "")

    # 1. Null check
    if ($null -eq $Items) { return "<p class='muted'>No data found.</p>" }

    # 2. Force into a standard array
    $arr = @($Items)
    if ($arr.Count -eq 0) { return "<p class='muted'>No records to display.</p>" }

    # 3. Resolve Columns Safely
    $actualColumns = @()
    if ($null -ne $Columns) {
        $actualColumns = $Columns
    } else {
        # Get properties from the first valid object in the array
        $firstItem = $arr | Where-Object { $null -ne $_ } | Select-Object -First 1
        if ($null -eq $firstItem) { return "<p class='muted'>No valid data objects.</p>" }
        $actualColumns = $firstItem.PSObject.Properties.Name | Where-Object { $_ -notmatch '^PS' }
    }

    # 4. Build HTML
    $th = ($actualColumns | ForEach-Object { "<th>$(ConvertTo-ToolkitHtmlEncoded $_)</th>" }) -join ""

    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($it in $arr) {
        if ($null -eq $it) { continue }
        $tds = ""
        foreach ($c in $actualColumns) {
            $val = ""
            try { $val = [string]$it.$c } catch { }

            # Directory link logic
            if (($c -eq "Name" -or $c -eq "File") -and -not [string]::IsNullOrEmpty($BaseDir)) {
                $uri = "file:///" + $BaseDir.Replace("\", "/")
                $val = "<a href='$uri' target='_blank' class='folder-link'>$val</a>"
            }

            $class = ""
            if ($val -match '^(Running|Enabled|OK|Healthy|True|Success)$') { $class = "status-green" }
            elseif ($val -match '^(Stopped|Disabled|Error|Unhealthy|False|Removed)$') { $class = "status-red" }
            elseif ($val -match '^(Warning|Changed)$') { $class = "status-yellow" }

            $tds += "<td class='$class'>$val</td>"
        }
        $rows.Add("<tr>$tds</tr>")
    }

    return "<div class='table-container'><table><thead><tr>$th</tr></thead><tbody>$($rows -join '')</tbody></table></div>"
}

function ConvertTo-ToolkitHtmlKeyValue {
    param([AllowNull()]$Object, [string[]]$Keys)
    if ($null -eq $Object) { return "<p class='muted'>No details available.</p>" }

    $actualKeys = if ($null -ne $Keys) { $Keys } else { $Object.PSObject.Properties.Name | Where-Object { $_ -notmatch '^PS' } }

    $rows = ""
    foreach ($k in $actualKeys) {
        $v = ""; try { $v = [string]$Object.$k } catch { }
        $rows += "<tr><td class='kv-key'>$k</td><td class='kv-val'>" + (ConvertTo-ToolkitHtmlEncoded $v) + "</td></tr>"
    }
    return "<div class='kv-container'><table><tbody>$rows</tbody></table></div>"
}

function ConvertTo-ToolkitHtmlTree {
    param([Parameter(Mandatory = $true)]$Node)

    function Render-Node($n) {
        if ($null -eq $n) { return "" }

        $name = "Unknown"; if ($n.PSObject.Properties['name']) { $name = [string]$n.name }
        $desc = ""; if ($n.PSObject.Properties['desc'] -and $n.desc) { $desc = " <span class='tree-desc'>$($n.desc)</span>" }

        # Force children to array for iteration
        $children = @()
        if ($n.PSObject.Properties['children'] -and $n.children) {
            $children = @($n.children)
        }

        if ($children.Count -gt 0) {
            $childHtml = ""
            foreach ($c in $children) { $childHtml += Render-Node $c }
            return "<li><details open><summary><b>$(ConvertTo-ToolkitHtmlEncoded $name)</b>$desc</summary><ul>$childHtml</ul></details></li>"
        }
        return "<li class='tree-leaf'>$(ConvertTo-ToolkitHtmlEncoded $name)$desc</li>"
    }

    return "<div class='tree-view'><ul>" + (Render-Node $Node) + "</ul></div>"
}

# --- 3. HARDWARE SCANNER ---

function New-ToolkitHardwareTree {
    param([string]$BundleFolder)
    $path = Join-Path $BundleFolder "system\hardware_tree.json"
    $categories = New-Object System.Collections.Generic.List[object]

    # Processors
    try {
        $cpus = @(Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores)
        $cpuItems = @(); foreach ($c in $cpus) { $cpuItems += [PSCustomObject]@{ name = [string]$c.Name.Trim(); desc = "Cores: $($c.NumberOfCores)"; children = @() } }
        $categories.Add([PSCustomObject]@{ name = "Processors"; desc = "$($cpus.Count) CPU(s)"; children = $cpuItems })
    } catch {}

    # Memory
    try {
        $mems = @(Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity, Speed, Manufacturer, DeviceLocator, PartNumber, BankLabel)
        $total = 0; foreach ($m in $mems) { $total += $m.Capacity }
        $memItems = @(); foreach ($m in $mems) {
            $memItems += [PSCustomObject]@{
                name     = "Slot $($m.DeviceLocator) [Channel: $($m.BankLabel)]"
                desc     = "$([math]::Round($m.Capacity/1GB,0)) GB $($m.Manufacturer) ($($m.PartNumber.Trim())) @ $($m.Speed)MHz"
                children = @()
            }
        }
        $categories.Add([PSCustomObject]@{ name = "Memory"; desc = "$([math]::Round($total/1GB,2)) GB Total"; children = $memItems })
    } catch {}

    # Disks
    try {
        $disks = @(Get-CimInstance Win32_DiskDrive | Select-Object Model, Size, MediaType, SerialNumber)
        $diskItems = @(); foreach ($d in $disks) {
            $diskItems += [PSCustomObject]@{
                name     = [string]$d.Model
                desc     = "$([math]::Round($d.Size/1GB,0)) GB ($($d.MediaType)) [S/N: $($d.SerialNumber)]"
                children = @()
            }
        }
        $categories.Add([PSCustomObject]@{ name = "Physical Disks"; desc = "$($disks.Count) Drive(s)"; children = $diskItems })
    } catch {}

    $tree = [PSCustomObject]@{ name = "Hardware Inventory"; desc = [string]$env:COMPUTERNAME; children = $categories.ToArray() }
    $tree | ConvertTo-Json -Depth 10 | Out-File $path -Encoding UTF8 -Force
    return $path

    # --- GRAPHICS (GPU) ---
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name, VideoProcessor, AdapterRAM)
        $gpuChildren = @()
        foreach ($g in $gpus) {
            $vram = if ($g.AdapterRAM) { "$([math]::Round($g.AdapterRAM / 1MB, 0)) MB" } else { "Shared" }
            $gpuChildren += [PSCustomObject]@{
                name     = [string]$g.Name
                desc     = "Processor: $($g.VideoProcessor) / VRAM: $vram"
                children = @()
            }
        }
        $categories.Add([PSCustomObject]@{ name = "Graphics"; desc = "$($gpus.Count) Adapter(s)"; children = $gpuChildren })
    } catch { }
}

# --- 4. MASTER REPORT ENGINE ---

function New-ToolkitGenericReport {
    param(
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][array]$ReportSections
    )

    $navLinks = @(); $cards = @()

    foreach ($sec in $ReportSections) {
        $id = [string]$sec.Id; $label = [string]$sec.Title; $type = [string]$sec.Type
        $isTree = ($type -eq "Tree"); if ($id -eq "sys") { $isTree = $false }

        $inner = ""
        switch ($type) {
            "GridKeyValue" {
                $inner = "<div class='dashboard-grid'>"
                foreach ($sub in $sec.Data) { $inner += "<div class='dash-column'><h3>$($sub.Title)</h3>" + (ConvertTo-ToolkitHtmlKeyValue -Object $sub.Obj) + "</div>" }
                $inner += "</div>"
            }
            "KeyValue" { $inner = ConvertTo-ToolkitHtmlKeyValue -Object $sec.Data }
            "Table" {
                $bDir = if ($sec.PSObject.Properties.Match('BaseDir').Count -gt 0) { [string]$sec.BaseDir } else { "" }
                $inner = ConvertTo-ToolkitHtmlTable -Items $sec.Data -BaseDir $bDir
            }
            "Tree" { $inner = ConvertTo-ToolkitHtmlTree -Node $sec.Data }
        }

        $navLinks += "<li><a href='#$id'>$label</a></li>"

        if ($isTree) {
            $isExp = if ($sec.PSObject.Properties.Match('Expanded').Count -gt 0) { [bool]$sec.Expanded } else { $false }
            $open = if ($isExp) { "open" } else { "" }
            $body = "<div class='tree-scoping'><ul class='dashed-tree'><li><details $open><summary><b>$label</b></summary><div class='tree-content'>$inner</div></details></li></ul></div>"
        } else {
            $body = "<div class='flat-view'>$inner</div>"
        }

        $cards += "<section id='$id' class='info-card'><div class='card-header'>$label</div><div class='card-body'>$body</div></section>"
    }

    $date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $html = @"
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>$Title</title>
<style>
    :root { --sidebar: #0f172a; --bg: #f1f5f9; --border: #cbd5e1; --primary: #2563eb; --text: #1e293b; }
    body { font-family: 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); margin: 0; display: flex; height: 100vh; overflow: hidden; }
    aside { width: 250px; background: var(--sidebar); color: #94a3b8; flex-shrink: 0; display: flex; flex-direction: column; }
    .nav-list { list-style: none; padding: 0; margin: 0; overflow-y: auto; flex: 1; }
    .nav-list a { display: block; padding: 12px 25px; color: inherit; text-decoration: none; font-size: 0.85rem; }
    .nav-list a:hover { background: #1e293b; color: white; }
    main { flex: 1; overflow-y: auto; padding: 30px; scroll-behavior: smooth; }
    .info-card { background: white; border-radius: 8px; border: 1px solid var(--border); margin-bottom: 30px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    .card-header { padding: 12px 20px; background: #f8fafc; border-bottom: 1px solid var(--border); font-weight: bold; font-size: 0.8rem; text-transform: uppercase; }
    .card-body { padding: 20px; }
    .dashboard-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
    .dash-column { border: 1px solid #e2e8f0; border-radius: 6px; padding: 15px; background: #fff; }
    .dash-column h3 { margin: 0 0 10px 0; color: var(--primary); border-bottom: 2px solid var(--primary); display: inline-block; font-size: 1rem; }
    table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
    th { text-align: left; padding: 10px; background: #f1f5f9; border-bottom: 2px solid var(--border); }
    td { padding: 8px 10px; border-bottom: 1px solid var(--border); }
    .status-green { color: #10b981; font-weight: bold; }
    .status-red { color: #ef4444; font-weight: bold; }
    .kv-key { width: 200px; font-weight: bold; background: #f8fafc; color: #64748b; border-right: 1px solid var(--border); }
    .kv-val { padding-left: 15px; font-family: 'Consolas', monospace; color: black; }
    .dashed-tree { list-style: none; padding-left: 20px; border-left: 1px dashed var(--border); margin: 0; }
    summary { cursor: pointer; padding: 10px; background: #f1f5f9; border-radius: 4px; font-weight: bold; }
    .tree-content { margin-top: 15px; }
    .tree-view ul { list-style: none; padding-left: 20px; border-left: 1px dashed var(--border); }
    .tree-leaf { padding: 5px 0; }
</style></head>
<body>
    <aside><div style='padding:25px; color:white; font-weight:bold;'>IT TOOLKIT</div><ul class='nav-list'>$($navLinks -join "")</ul></aside>
    <main>
        <div style='background:white; padding:25px; border-radius:8px; border:1px solid var(--border); margin-bottom:30px;'>
            <h2 style='margin:0;'>$ComputerName</h2><p style='color:#64748b; margin:5px 0 0 0;'>$Title | $date</p>
        </div>
        $($cards -join "")
    </main>
</body></html>
"@
    $html | Out-File $ReportPath -Encoding UTF8 -Force
}