param(
    [string]$Action = "GenerateReport",
    [string]$TargetFolder = "",
    [string]$MaxDepth = "3",
    [bool]$IncludeFiles = $true,
    [bool]$ShowHidden = $false,
    [string]$ExportFolder = "__MODULE_OUTPUT__"
)

# Shared helpers
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -------------------- HELPERS --------------------
function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }
function Set-Progress([int]$p, [string]$status = "") {
    Write-Information ("PROGRESS:{0}" -f $p)
    if ($status) { Write-Host "[Status] $status" -ForegroundColor Gray }
}

function Get-FriendlySize {
    param($bytes)
    $b = if ($null -eq $bytes) { 0.0 } else { [double]$bytes }
    if ($b -gt 1GB) { return "$([math]::Round($b / 1GB, 2)) GB" }
    if ($b -gt 1MB) { return "$([math]::Round($b / 1MB, 2)) MB" }
    if ($b -gt 1KB) { return "$([math]::Round($b / 1KB, 2)) KB" }
    return "$b Bytes"
}

# --- RECURSIVE TREE BUILDER (Strict-Safe) ---
function Get-FolderTreeObject {
    param(
        [string]$Path,
        [int]$CurrentDepth,
        [int]$MaxDepthLimit
    )

    $item = Get-Item -LiteralPath $Path
    $displayName = if ([string]::IsNullOrWhiteSpace($item.Name)) { [string]$item.FullName } else { [string]$item.Name }

    # Use standard array @() for children to avoid "Argument types do not match"
    $nodeChildren = @()

    if ($MaxDepthLimit -eq 0 -or $CurrentDepth -lt $MaxDepthLimit) {
        try {
            $items = Get-ChildItem -LiteralPath $Path -Force:$ShowHidden -ErrorAction SilentlyContinue
            if ($null -ne $items) {
                foreach ($child in $items) {
                    if ($child.PSIsContainer) {
                        $nodeChildren += Get-FolderTreeObject -Path $child.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepthLimit $MaxDepthLimit
                    } elseif ($IncludeFiles) {
                        $nodeChildren += [PSCustomObject]@{
                            name     = [string]$child.Name
                            desc     = [string]"Size: $(Get-FriendlySize $child.Length)"
                            children = @() # Leaf nodes MUST have an empty array
                        }
                    }
                }
            }
        } catch { }
    }

    return [PSCustomObject]@{
        name     = $displayName
        desc     = [string]"Modified: $($item.LastWriteTime.ToString('yyyy-MM-dd'))"
        children = $nodeChildren
    }
}

# -------------------- MAIN --------------------
try {
    Set-Progress 5 "Initializing..."
    $computer = [string]$env:COMPUTERNAME
    if (-not (Test-Path -LiteralPath $TargetFolder)) { throw "Target folder not found: $TargetFolder" }

    $depthLimit = if ($MaxDepth -eq "Unlimited") { 0 } else { [int]$MaxDepth }

    # 1. Build the Tree
    Out-Status "Scanning hierarchy: $TargetFolder"
    $treeData = Get-FolderTreeObject -Path $TargetFolder -CurrentDepth 0 -MaxDepthLimit $depthLimit
    Set-Progress 50 "Scan complete."

    # 2. Stats Calculation
    Out-Status "Calculating stats..."
    $allFiles = Get-ChildItem -LiteralPath $TargetFolder -Recurse -File -Force:$ShowHidden -ErrorAction SilentlyContinue
    $totalCount = 0; $totalSizeBytes = 0
    if ($null -ne $allFiles) {
        $measure = $allFiles | Measure-Object -Property Length -Sum
        if ($measure.PSObject.Properties['Count']) { $totalCount = [int]$measure.Count }
        if ($measure.PSObject.Properties['Sum'] -and $measure.Sum) { $totalSizeBytes = $measure.Sum }
    }

    $statsObj = [PSCustomObject]@{
        RootFolder = [string]$TargetFolder
        TotalFiles = [int]$totalCount
        TotalSize  = Get-FriendlySize $totalSizeBytes
        ScanDepth  = [string]$MaxDepth
    }

    # 3. Generate Report
    if ($Action -eq "GenerateReport") {
        Out-Status "Generating HTML..."

        if ($ExportFolder -eq "__MODULE_OUTPUT__" -or [string]::IsNullOrWhiteSpace($ExportFolder)) {
            $ExportFolder = Join-Path $env:TEMP "Toolkit-FolderScan"
        }
        if (-not (Test-Path $ExportFolder)) { New-Item $ExportFolder -ItemType Directory -Force | Out-Null }

        $reportSections = @()
        $reportSections += @{ Id = "sys"; Title = "Scan Summary"; Type = "GridKeyValue"; Collapsible = [bool]$false; Data = @(@{ Title = "Folder Metrics"; Obj = $statsObj }) }
        $reportSections += @{ Id = "tree"; Title = "Hierarchical View"; Type = "Tree"; Collapsible = [bool]$true; Expanded = [bool]$true; Data = $treeData }

        $htmlPath = Join-Path $ExportFolder "FolderTree_Report.html"
        New-ToolkitGenericReport -ReportPath $htmlPath -Title "Folder Tree Analysis" -ComputerName $computer -ReportSections $reportSections
        Out-Status "[OK] Report: $htmlPath"
    }

    Set-Progress 100 "Done."

} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}