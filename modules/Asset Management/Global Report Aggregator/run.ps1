param(
    [string]$CompanyName = "My Organization",
    [string]$TechnicianName = "Admin",
    [string]$SourceDir = "",
    [string]$SelectedCategories = "",
    [bool]$SelectAllData = $false,
    [string]$ExportFolder = "__MODULE_OUTPUT__"
)

. (Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Out-Info([string]$m) { Write-Host $m -ForegroundColor White }
function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }
function Out-Success([string]$m) { Write-Host "[OK] $m" -ForegroundColor Green }
function Out-Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Out-Err([string]$m) { Write-Host "[ERROR] $m" -ForegroundColor Red }

function Set-Progress([int]$p, [string]$status = "") {
    if ($p -lt 0) { $p = 0 }; if ($p -gt 100) { $p = 100 }
    Write-Information ("PROGRESS:{0}" -f $p)
    if ($status) { Out-Status $status }
}

function Get-SafeValue($Obj, [string]$Prop) {
    if ($null -eq $Obj) { return $null }
    if ($Obj.PSObject.Properties[$Prop]) { return $Obj.$Prop }
    return $null
}

function Get-CommonDataFiles {
    param([array]$BundleFolders)
    if ($BundleFolders.Count -eq 0) { return @() }
    $firstPath = $BundleFolders[0].FullName
    $candidates = @(Get-ChildItem -Path $firstPath -Filter "*.json" -Recurse -EA SilentlyContinue | ForEach-Object {
            $_.FullName.Substring($firstPath.Length + 1)
        })
    $common = @()
    foreach ($relPath in $candidates) {
        if ($relPath -match "report_settings|hardware_tree") { continue }
        $isCommon = $true
        foreach ($bundle in $BundleFolders) {
            if (-not (Test-Path -LiteralPath (Join-Path $bundle.FullName $relPath))) { $isCommon = $false; break }
        }
        if ($isCommon) { $common += ($relPath -replace '\.json$', '' -replace '\\', ' / ') }
    }
    return $common
}

try {
    Out-Info "=========================================="; Out-Info "GLOBAL REPORT AGGREGATOR"; Out-Info "=========================================="
    Out-Info "Company:    $CompanyName"
    Out-Info "Technician: $TechnicianName"
    Out-Info "Mode:       $(if ($SelectAllData) { 'Include All Common Data' } else { 'Manual Selection' })"
    Out-Info ""

    if ([string]::IsNullOrWhiteSpace($SourceDir)) {
        Out-Warn "Please select a Support Bundles Directory before running."
        return
    }

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        Out-Warn "The selected directory was not found:"
        Out-Warn "  $SourceDir"
        Out-Warn "Please check the path and try again."
        return
    }

    Set-Progress -p 5 -status "Scanning for Support Bundles..."
    $bundleFolders = @(Get-ChildItem -LiteralPath $SourceDir -Directory | Where-Object { $_.Name -match "SupportBundle" })
    if ($bundleFolders.Count -eq 0) {
        Out-Warn "No Support Bundle folders found in the selected directory."
        Out-Warn "Make sure the folder contains subfolders named 'SupportBundle-*'."
        return
    }
    Out-Success "Found $($bundleFolders.Count) Support Bundle(s)"

    [array]$selection = @()
    if ($SelectAllData) {
        Out-Status "Discovering common data categories..."
        $selection = Get-CommonDataFiles -BundleFolders $bundleFolders
        Out-Info "  Found $($selection.Count) common data categories"
    } else {
        if ([string]::IsNullOrWhiteSpace($SelectedCategories)) {
            Out-Warn "No data categories selected."
            Out-Warn "Please click 'Choose Data to Include' and select at least one item,"
            Out-Warn "or check 'Include All Common Data' to include everything."
            return
        }
        $selection = @($SelectedCategories -split ",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    }
    if ($selection.Count -eq 0) {
        Out-Warn "No common data categories were found across all bundles."
        return
    }

    Set-Progress -p 10 -status "Processing bundles..."
    $pcDataList = New-Object System.Collections.Generic.List[PSObject]
    $counter = 0

    foreach ($folder in $bundleFolders) {
        $counter++
        Set-Progress -p ([int](10 + ($counter / $bundleFolders.Count * 70))) -status "Processing: $($folder.Name)"

        $pcName = [string]$folder.Name
        if ($folder.Name -match "SupportBundle-(.*)-\d{8}-\d{6}") { $pcName = $matches[1] }
        elseif ($folder.Name -match "SupportBundle-(.*)") { $pcName = $matches[1] }

        $pcObj = [PSCustomObject]@{
            ID = "tab_$counter"; PCName = $pcName; FolderName = $folder.Name
            Summary = @{ OS = "N/A"; Build = "N/A"; Model = "N/A"; RAM = "N/A"; IP = "N/A"; CPU = "N/A"; GPU = "N/A" }
            Details = New-Object System.Collections.Generic.List[PSObject]
        }

        foreach ($item in $selection) {
            $relPath = ($item -replace ' / ', '\') + ".json"
            $fullPath = Join-Path $folder.FullName $relPath
            if (-not (Test-Path -LiteralPath $fullPath)) { continue }
            $data = Read-ToolkitJson $fullPath
            if ($null -eq $data) { continue }

            if ($relPath -match "system[/\\]os\.json$") {
                $pcObj.Summary.OS = [string](Get-SafeValue $data "Caption")
                $pcObj.Summary.Build = [string](Get-SafeValue $data "BuildNumber")
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Operating System"; Type = "KeyValue"; Data = $data; Order = 1; Expanded = $true })
            } elseif ($relPath -match "system[/\\]computer\.json$") {
                $pcObj.Summary.Model = [string](Get-SafeValue $data "Model")
                $ramBytes = Get-SafeValue $data "TotalPhysicalMemory"
                $pcObj.Summary.RAM = if ($ramBytes) { "$([math]::Round($ramBytes / 1GB, 0)) GB" } else { "N/A" }
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Hardware Environment"; Type = "KeyValue"; Data = $data; Order = 2; Expanded = $true })
            } elseif ($relPath -match "network[/\\]ipconfig\.json$") {
                $ips = @()
                $ipWithSubnet = @()
                $networkDetails = @()

                foreach ($adapter in @($data)) {
                    $alias = Get-SafeValue $adapter "InterfaceAlias"
                    if (-not $alias) { $alias = Get-SafeValue $adapter "Alias" }
                    if (-not $alias) { $alias = "Unknown" }

                    $adapterIPs = @()
                    $adapterSubnets = @()

                    # Get IPv4 addresses
                    if ($adapter.PSObject.Properties['IPv4Address']) {
                        foreach ($addr in @($adapter.IPv4Address)) {
                            $ipVal = $null
                            $subnetVal = $null

                            if ($addr -is [string]) {
                                $ipVal = $addr
                            } else {
                                $ipVal = Get-SafeValue $addr "IPAddress"
                                $subnetVal = Get-SafeValue $addr "PrefixLength"
                            }

                            if ($ipVal -and $ipVal -notmatch '^169\.254\.') {
                                $adapterIPs += $ipVal
                                if ($subnetVal) {
                                    $ipWithSubnet += "$ipVal/$subnetVal"
                                } else {
                                    $ipWithSubnet += $ipVal
                                }
                            }
                        }
                    }

                    # Also check for IPAddress property directly
                    if ($adapterIPs.Count -eq 0 -and $adapter.PSObject.Properties['IPAddress']) {
                        $ipVal = Get-SafeValue $adapter "IPAddress"
                        if ($ipVal -and $ipVal -notmatch '^169\.254\.') {
                            $adapterIPs += $ipVal
                            $subnet = Get-SafeValue $adapter "PrefixLength"
                            if (-not $subnet) { $subnet = Get-SafeValue $adapter "SubnetMask" }
                            if ($subnet) {
                                $ipWithSubnet += "$ipVal/$subnet"
                            } else {
                                $ipWithSubnet += $ipVal
                            }
                        }
                    }

                    $ips += $adapterIPs

                    # Build a flattened detail object for display
                    if ($adapterIPs.Count -gt 0) {
                        $networkDetails += [PSCustomObject]@{
                            Adapter      = $alias
                            "IP Address" = $adapterIPs -join ", "
                            "Subnet"     = if ($adapter.PSObject.Properties['PrefixLength']) { Get-SafeValue $adapter "PrefixLength" } elseif ($adapter.PSObject.Properties['SubnetMask']) { Get-SafeValue $adapter "SubnetMask" } else { "N/A" }
                            Gateway      = if ($adapter.PSObject.Properties['IPv4DefaultGateway']) {
                                $gw = @($adapter.IPv4DefaultGateway) | ForEach-Object { if ($_ -is [string]) { $_ } else { Get-SafeValue $_ "NextHop" } } | Where-Object { $_ }
                                $gw -join ", "
                            } else { "N/A" }
                            DNS          = if ($adapter.PSObject.Properties['DNSServer']) {
                                $dns = @($adapter.DNSServer) | ForEach-Object { if ($_ -is [string]) { $_ } else { Get-SafeValue $_ "ServerAddresses" } } | Where-Object { $_ }
                                ($dns | Select-Object -First 2) -join ", "
                            } else { "N/A" }
                        }
                    }
                }

                # Summary IP for top table (with subnet)
                $pcObj.Summary.IP = if ($ipWithSubnet.Count -gt 0) { $ipWithSubnet -join ", " } else { "N/A" }

                # Use the flattened details for the Network Configuration section
                $displayData = if ($networkDetails.Count -gt 0) { $networkDetails } else { $data }
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Network Configuration"; Type = "Table"; Data = $displayData; Order = 3; Expanded = $false })
            } elseif ($relPath -match "network[/\\]netadapter\.json$") {
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Network Adapters"; Type = "Table"; Data = $data; Order = 4; Expanded = $false })
            } elseif ($relPath -match "services[/\\]services\.json$") {
                $pcObj.Details.Add([PSCustomObject]@{ Title = "System Services"; Type = "Table"; Data = $data; Order = 10; Expanded = $false })
            } elseif ($relPath -match "apps[/\\]installed_apps\.json$") {
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Installed Applications"; Type = "Table"; Data = $data; Order = 11; Expanded = $false })
            } elseif ($relPath -match "disk[/\\]volumes\.json$") {
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Storage Volumes"; Type = "Table"; Data = $data; Order = 6; Expanded = $false })
            } elseif ($relPath -match "drivers[/\\]") {
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Drivers: $($item -replace 'drivers / ', '')"; Type = "Table"; Data = $data; Order = 20; Expanded = $false })
            } elseif ($relPath -match "security[/\\]") {
                $pcObj.Details.Add([PSCustomObject]@{ Title = "Security: $($item -replace 'security / ', '')"; Type = "KeyValue"; Data = $data; Order = 15; Expanded = $false })
            } else {
                $pcObj.Details.Add([PSCustomObject]@{ Title = $item; Type = "Table"; Data = $data; Order = 50; Expanded = $false })
            }
        }

        # Always try to load hardware tree for CPU/GPU summary info
        $hwPath = Join-Path $folder.FullName "system\hardware_tree.json"
        if (-not (Test-Path -LiteralPath $hwPath)) { try { New-ToolkitHardwareTree -BundleFolder $folder.FullName | Out-Null } catch { } }
        $hwTree = Read-ToolkitJson $hwPath
        if ($null -ne $hwTree) {
            if ($hwTree.PSObject.Properties['children']) {
                foreach ($cat in @($hwTree.children)) {
                    if ($cat.name -match "Processor" -and $cat.children) { $pcObj.Summary.CPU = [string](@($cat.children)[0].name) }
                    if ($cat.name -match "Graphics" -and $cat.children) { $pcObj.Summary.GPU = [string](@($cat.children)[0].name) }
                }
            }
            $pcObj.Details.Add([PSCustomObject]@{ Title = "Hardware Inventory"; Type = "Tree"; Data = $hwTree; Order = 5; Expanded = $false })
        }
        $pcDataList.Add($pcObj)
    }

    Set-Progress -p 85 -status "Generating HTML report..."
    $sortedPCs = @($pcDataList) | Sort-Object PCName
    $reportTime = Get-Date -Format "yyyy-MM-dd hh:mm tt"

    # Build HTML content - always include CPU column
    $headerHtml = "<th onclick='sortTable(this)'>#</th><th onclick='sortTable(this)'>PC Name</th><th onclick='sortTable(this)'>OS</th><th onclick='sortTable(this)'>Build</th><th onclick='sortTable(this)'>IP / Subnet</th><th onclick='sortTable(this)'>Model</th><th onclick='sortTable(this)'>RAM</th><th onclick='sortTable(this)'>CPU</th>"

    $tableRows = New-Object System.Collections.Generic.List[string]
    $rowCounter = 0
    foreach ($pc in $sortedPCs) {
        $rowCounter++; $s = $pc.Summary
        $cpuShort = if ($s.CPU.Length -gt 35) { $s.CPU.Substring(0, 32) + "..." } else { $s.CPU }
        $row = "<tr onclick='showTab(`"$($pc.ID)`")' style='cursor:pointer;'><td>$rowCounter</td><td><b style='color:#2563eb'>$($pc.PCName)</b></td><td>$($s.OS)</td><td>$($s.Build)</td><td style='font-size:0.72rem;max-width:180px;white-space:normal;'>$($s.IP)</td><td>$($s.Model)</td><td>$($s.RAM)</td><td style='font-size:0.72rem;' title='$($s.CPU)'>$cpuShort</td></tr>"
        $tableRows.Add($row)
    }

    $tabBtns = New-Object System.Collections.Generic.List[string]
    $tabContents = New-Object System.Collections.Generic.List[string]

    foreach ($pc in $sortedPCs) {
        $tabBtns.Add("<button class='tab-btn' id='btn_$($pc.ID)' onclick='showTab(`"$($pc.ID)`")'>$($pc.PCName)</button>")
        $innerHtml = ""
        $summaryDetails = @(@($pc.Details) | Where-Object { $_.Title -match "Operating System|Hardware Environment" } | Sort-Object Order)
        if ($summaryDetails -and $summaryDetails.Count -gt 0) {
            $innerHtml += "<div class='dashboard-grid'>"
            foreach ($sec in $summaryDetails) { $innerHtml += "<div class='dash-col'><h4>$($sec.Title)</h4>$(ConvertTo-ToolkitHtmlKeyValue -Object $sec.Data)</div>" }
            $innerHtml += "</div>"
        }
        $otherDetails = @(@($pc.Details) | Where-Object { $_.Title -notmatch "Operating System|Hardware Environment" } | Sort-Object Order)
        foreach ($sec in $otherDetails) {
            $isOpen = if ($sec.Expanded) { "open" } else { "" }
            $dataBody = switch ($sec.Type) { "Table" { ConvertTo-ToolkitHtmlTable -Items $sec.Data } "Tree" { ConvertTo-ToolkitHtmlTree -Node $sec.Data } "KeyValue" { ConvertTo-ToolkitHtmlKeyValue -Object $sec.Data } default { "<p>Unknown</p>" } }
            $innerHtml += "<div class='detail-card'><details $isOpen><summary><b>$($sec.Title)</b></summary><div class='detail-body'>$dataBody</div></details></div>"
        }
        $tabContents.Add("<div id='$($pc.ID)' class='pc-tab-content'><div class='tab-header-row'><h2>$($pc.PCName)</h2><span class='folder-label'>$($pc.FolderName)</span><a href='#top' class='top-btn'>Back to Overview</a></div>$innerHtml</div>")
    }

    $htmlTemplate = Get-Content -Path (Join-Path $PSScriptRoot "report_template.html") -Raw -ErrorAction SilentlyContinue
    if (-not $htmlTemplate) {
        # Inline template fallback
        $htmlTemplate = @'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>{{COMPANY}} - Fleet Report</title>
<style>
:root{--primary:#2563eb;--bg:#f1f5f9;--border:#cbd5e1;--text:#1e293b;--green:#10b981;}
*{box-sizing:border-box}body{font-family:'Segoe UI',sans-serif;background:var(--bg);color:var(--text);margin:0;padding:20px;scroll-behavior:smooth}
.header{background:linear-gradient(135deg,#0f172a,#1e293b);color:#fff;padding:25px;border-radius:10px;display:flex;justify-content:space-between;align-items:center;margin-bottom:20px}
.header h1{margin:0}.header p{margin:5px 0 0;color:#94a3b8}.header-meta{text-align:right;font-size:.85rem}.header-meta b{color:var(--green)}
.stat-bar{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin-bottom:20px}
.stat-card{background:#fff;padding:12px 16px;border-radius:8px;border:1px solid var(--border)}.stat-label{font-size:.65rem;text-transform:uppercase;color:#64748b;font-weight:600}.stat-val{font-size:1.3rem;font-weight:700;color:var(--primary);margin-top:3px}
.card{background:#fff;border:1px solid var(--border);border-radius:10px;padding:20px;margin-bottom:20px}.card h3{margin:0 0 12px}
.table-wrapper{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:.78rem}th{position:sticky;top:0;background:#f8fafc;padding:10px;text-align:left;border-bottom:2px solid var(--border);cursor:pointer;white-space:nowrap}th:hover{color:var(--primary)}td{padding:8px 10px;border-bottom:1px solid var(--border)}tr:hover{background:#f8fafc}
.tab-bar{display:flex;gap:4px;overflow-x:auto;margin-bottom:-1px}.tab-btn{padding:9px 14px;border:1px solid var(--border);border-bottom:none;background:#e2e8f0;cursor:pointer;border-radius:6px 6px 0 0;font-weight:600;font-size:.75rem;white-space:nowrap}.tab-btn:hover{background:#f1f5f9}.tab-btn.active{background:#fff;border-bottom:3px solid var(--primary);color:var(--primary)}
.pc-tab-content{display:none;background:#fff;border:1px solid var(--border);padding:20px;border-radius:0 8px 8px 8px}.pc-tab-content.active{display:block}
.tab-header-row{display:flex;align-items:center;gap:12px;margin-bottom:15px;padding-bottom:12px;border-bottom:2px solid var(--border)}.tab-header-row h2{margin:0;color:var(--primary)}.folder-label{font-size:.7rem;color:#64748b;background:#f1f5f9;padding:3px 8px;border-radius:4px}.top-btn{margin-left:auto;font-size:.72rem;text-decoration:none;color:#64748b;background:#f1f5f9;padding:5px 10px;border-radius:4px;border:1px solid var(--border)}.top-btn:hover{background:var(--primary);color:#fff}
.dashboard-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:15px;margin-bottom:15px}.dash-col{border:1px solid #e2e8f0;border-radius:8px;padding:12px;background:#fafbfc}.dash-col h4{margin:0 0 10px;color:var(--primary);border-bottom:2px solid var(--primary);display:inline-block;padding-bottom:2px;font-size:.85rem}
.detail-card{border:1px solid #e2e8f0;border-radius:6px;margin-bottom:12px;overflow:hidden}.detail-card summary{cursor:pointer;padding:10px 12px;background:#f8fafc}.detail-card summary:hover{background:#f1f5f9}.detail-body{padding:12px}
.kv-container table{font-size:.78rem}.kv-key{width:160px;font-weight:600;background:#f8fafc;color:#64748b;font-size:.72rem;border-right:1px solid var(--border);padding:6px 10px}.kv-val{padding:6px 10px;font-family:Consolas,monospace}
.tree-view ul{list-style:none;padding-left:18px;border-left:1px dashed var(--border);margin:4px 0}.tree-view>ul{border-left:none;padding-left:0}.tree-view li{padding:3px 0}.tree-view summary{cursor:pointer;padding:2px 5px;border-radius:3px}.tree-view summary:hover{background:#f1f5f9}.tree-desc{color:#64748b;font-size:.78rem;margin-left:6px}
.status-green{color:var(--green);font-weight:600}.status-red{color:#ef4444;font-weight:600}
.table-container{overflow-x:auto;max-height:400px;overflow-y:auto}
</style>
<script>
function showTab(id){document.querySelectorAll('.pc-tab-content,.tab-btn').forEach(e=>e.classList.remove('active'));const t=document.getElementById(id),b=document.getElementById('btn_'+id);if(t){t.classList.add('active');if(b)b.classList.add('active');window.location.hash=id;t.scrollIntoView({behavior:'smooth'})}}
function sortTable(h){const t=document.getElementById('overviewTable'),b=t.querySelector('tbody'),r=Array.from(b.querySelectorAll('tr')),i=Array.from(h.parentNode.children).indexOf(h),a=h.dataset.sort!=='asc';r.sort((x,y)=>{let xv=x.children[i]?.innerText||'',yv=y.children[i]?.innerText||'';const xn=parseFloat(xv),yn=parseFloat(yv);if(!isNaN(xn)&&!isNaN(yn))return a?xn-yn:yn-xn;return a?xv.localeCompare(yv):yv.localeCompare(xv)});r.forEach(row=>b.appendChild(row));document.querySelectorAll('th').forEach(th=>th.dataset.sort='');h.dataset.sort=a?'asc':'desc'}
window.onload=()=>{const h=window.location.hash.replace('#',''),f=document.querySelector('.pc-tab-content');if(h&&document.getElementById(h))showTab(h);else if(f)showTab(f.id)}
</script>
</head>
<body>
<div id="top" class="header"><div><h1>{{COMPANY}}</h1><p>Global Fleet Audit Report</p></div><div class="header-meta"><small>GENERATED BY</small><br><b>{{TECHNICIAN}}</b><br><small>{{DATETIME}}</small></div></div>
<div class="stat-bar"><div class="stat-card"><div class="stat-label">Total PCs</div><div class="stat-val">{{PC_COUNT}}</div></div><div class="stat-card"><div class="stat-label">Data Categories</div><div class="stat-val">{{CAT_COUNT}}</div></div><div class="stat-card"><div class="stat-label">Mode</div><div class="stat-val" style="font-size:.95rem">{{MODE}}</div></div></div>
<div class="card"><h3>Fleet Overview <small style="font-weight:normal;color:#64748b">(Click headers to sort, rows to view)</small></h3><div class="table-wrapper"><table id="overviewTable"><thead><tr>{{TABLE_HEADERS}}</tr></thead><tbody>{{TABLE_ROWS}}</tbody></table></div></div>
<div class="tab-bar">{{TAB_BUTTONS}}</div>{{TAB_CONTENTS}}
</body></html>
'@
    }

    $html = $htmlTemplate -replace '{{COMPANY}}', [System.Web.HttpUtility]::HtmlEncode($CompanyName) `
        -replace '{{TECHNICIAN}}', [System.Web.HttpUtility]::HtmlEncode($TechnicianName) `
        -replace '{{DATETIME}}', $reportTime `
        -replace '{{PC_COUNT}}', $sortedPCs.Count `
        -replace '{{CAT_COUNT}}', $selection.Count `
        -replace '{{MODE}}', $(if ($SelectAllData) { 'Complete' } else { 'Custom' }) `
        -replace '{{TABLE_HEADERS}}', $headerHtml `
        -replace '{{TABLE_ROWS}}', ($tableRows -join "") `
        -replace '{{TAB_BUTTONS}}', ($tabBtns -join "") `
        -replace '{{TAB_CONTENTS}}', ($tabContents -join "")

    if ($ExportFolder -eq "__MODULE_OUTPUT__") { $ExportFolder = Join-Path $SourceDir "AggregatedReport" }
    if (-not (Test-Path -LiteralPath $ExportFolder)) { New-Item $ExportFolder -ItemType Directory -Force | Out-Null }

    $reportPath = Join-Path $ExportFolder "Global_Fleet_Report.html"
    $html | Out-File -FilePath $reportPath -Encoding UTF8 -Force

    Set-Progress -p 100 -status "Report generated successfully!"
    Out-Success "Report saved: $reportPath"
    Out-Info ""
    Out-Info "Summary:"
    Out-Info "  - PCs processed: $($sortedPCs.Count)"
    Out-Info "  - Data categories: $($selection.Count)"
    Out-Info "  - Output: $reportPath"

} catch {
    Out-Err $_.Exception.Message
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}