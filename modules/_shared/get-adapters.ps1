# modules\_shared\get-adapters.ps1
$ErrorActionPreference = "SilentlyContinue"

try {
    $adapters = Get-NetAdapter | Sort-Object Name
    foreach ($a in $adapters) {
        Write-Output ("{0} ({1})" -f $a.Name, $a.Status)
    }
} catch {
    # Fallback – still return something usable
    Get-NetAdapter -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object {
        Write-Output $_.Name
    }
}
