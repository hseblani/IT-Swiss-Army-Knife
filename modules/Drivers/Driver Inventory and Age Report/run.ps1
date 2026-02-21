param(
    [bool]$WhatIfMode = $true,

    [string]$AgeYears = "3",
    [bool]$IncludeOnlyPresentDevices = $false,

    [string]$ExportFolder = "",
    [bool]$ExportJson = $true,
    [bool]$ExportCsv = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference = "None"

function Out-Info([string]$m) { Write-Output $m }
function Out-Err([string]$m) { Write-Output "[ERROR] $m" }

function Ensure-Folder([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return }
    if ($WhatIfMode) { Out-Info "[WHATIF MODE] Would ensure folder exists: $p"; return }
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Export-Json([string]$path, $obj) {
    if ($WhatIfMode) { Out-Info "[WHATIF MODE] Would write JSON: $path"; return }
    ($obj | ConvertTo-Json -Depth 8) | Out-File -FilePath $path -Encoding UTF8
}

function Export-Csv([string]$path, $obj) {
    if ($WhatIfMode) { Out-Info "[WHATIF MODE] Would write CSV: $path"; return }
    $obj | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
}

try {
    Out-Info "=== Driver Inventory and Age Report ==="
    Out-Info "WhatIfMode: $WhatIfMode"
    Out-Info ""

    $yrs = 3
    [int]::TryParse($AgeYears, [ref]$yrs) | Out-Null
    if ($yrs -lt 1) { $yrs = 1 }
    if ($yrs -gt 30) { $yrs = 30 }

    if ([string]::IsNullOrWhiteSpace($ExportFolder)) {
        $ExportFolder = Join-Path $PSScriptRoot "output"
    }
    Ensure-Folder $ExportFolder

    $cutoff = (Get-Date).AddYears(-1 * $yrs)

    $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
    Select-Object DeviceName, DriverVersion, DriverProviderName, DriverDate, IsSigned, InfName, Manufacturer, Present

    if ($IncludeOnlyPresentDevices) {
        $drivers = $drivers | Where-Object { $_.Present -eq $true }
    }

    $report = $drivers | ForEach-Object {
        $dt = $null
        try { $dt = [datetime]$_.DriverDate } catch { $dt = $null }
        [pscustomobject]@{
            DeviceName    = [string]$_.DeviceName
            Provider      = [string]$_.DriverProviderName
            Manufacturer  = [string]$_.Manufacturer
            DriverVersion = [string]$_.DriverVersion
            DriverDate    = if ($dt) { $dt.ToString("yyyy-MM-dd") } else { "" }
            IsSigned      = [bool]$_.IsSigned
            InfName       = [string]$_.InfName
            Present       = [bool]$_.Present
            IsOld         = if ($dt) { ($dt -lt $cutoff) } else { $false }
        }
    } | Sort-Object IsOld -Descending, Provider, DeviceName

    $oldCount = ($report | Where-Object { $_.IsOld }).Count
    Out-Info ("Age threshold: {0} years (cutoff: {1})" -f $yrs, $cutoff.ToString("yyyy-MM-dd"))
    Out-Info ("Total drivers: {0}" -f $report.Count)
    Out-Info ("Flagged old  : {0}" -f $oldCount)
    Out-Info ""

    $report | Select-Object IsOld, DriverDate, Provider, DeviceName, DriverVersion, IsSigned, InfName |
    Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Output

    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    if ($ExportJson) { Export-Json (Join-Path $ExportFolder "drivers_report_$stamp.json") $report }
    if ($ExportCsv) { Export-Csv (Join-Path $ExportFolder "drivers_report_$stamp.csv") $report }

    Out-Info ""
    if ($WhatIfMode) { Out-Info "[WHATIF MODE] No files were created." } else { Out-Info "[OK] Done." }
    Out-Info "=== Done ==="
} catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}
