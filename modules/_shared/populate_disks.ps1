param(
    [string]$Operation = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

$log = Join-Path $env:TEMP "populate_disks_DEBUG.log"
function dlog([string]$m) {
    try { Add-Content -LiteralPath $log -Value ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"), $m) } catch {}
}

dlog "=== populate_disks.ps1 DEBUG START ==="
dlog "PSVersion=$($PSVersionTable.PSVersion) PSEdition=$($PSVersionTable.PSEdition) Host=$($Host.Name)"
try { dlog "PWD=$(Get-Location)" } catch {}
dlog "Operation=$Operation"

try {
    # Ensure Storage module is available (helps on pwsh scenarios)
    try {
        if (-not (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
            dlog "Get-Disk not found. Attempting Import-Module Storage..."
            Import-Module Storage -ErrorAction SilentlyContinue
        }
        dlog "Get-Disk command: $((Get-Command Get-Disk -ErrorAction SilentlyContinue | Select-Object -First 1 | Format-List * | Out-String).Trim())"
    } catch {
        dlog "ERROR while checking/importing Storage: $($_.Exception.ToString())"
    }

    $disks = @(Get-Disk -ErrorAction Stop | Sort-Object Number)
    dlog "DiskCount=$($disks.Count)"

    if ($disks.Count -eq 0) {
        Write-Output "No disks found"
        return
    }

    foreach ($disk in $disks) {
        $sizeGB = [math]::Round($disk.Size / 1GB, 2)
        $friendlyName = if ($disk.FriendlyName) { $disk.FriendlyName } else { "Unknown" }
        $busType = if ($disk.BusType) { $disk.BusType.ToString() } else { "Unknown" }

        # IMPORTANT: return disk number first so GUI can parse the number if needed
        # Format: "0  |  CT500MX500SSD1 (465.76 GB) - SATA"
        $label = "{0} ({1} GB) - {2}" -f $friendlyName, $sizeGB, $busType
        Write-Output ("{0}  |  {1}" -f $disk.Number, $label)

    }
} catch {
    dlog "EXCEPTION: $($_.Exception.ToString())"
    Write-Output ("ERROR: " + $_.Exception.Message)
    Write-Output ("LOG: " + $log)
} finally {
    dlog "=== populate_disks.ps1 DEBUG END ==="
}
