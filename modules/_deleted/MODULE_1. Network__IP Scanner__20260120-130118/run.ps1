param(
    [Parameter()][string]$Target = "8.8.8.8",
    [Parameter()][bool]$Continuous = $false,
    [Parameter()][int]$Count = 4
)

$ErrorActionPreference = "Continue"

Write-Output "=== PING TEST ==="
Write-Output "Target     : $Target"
if ($Continuous -eq $true) {
    Write-Output "Mode       : Continuous (-t)"
} else {
    Write-Output "Count      : $Count"
}
Write-Output "------------------------------------------"
Write-Output ""

# We use the native ping.exe because our main script redirects it live.
# This allows the 'Stop' button in the GUI to kill the process immediately.

if ($Continuous -eq $true) {
    # Continuous ping (-t)
    # The main script's redirector will stream this line-by-line
    ping $Target -t
} else {
    # Standard count ping (-n in Windows ping)
    ping $Target -n $Count
}

Write-Output ""
Write-Output "Ping process reached end of execution."