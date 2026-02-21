param(
    [Parameter(Mandatory=$true)]
    [string]$Name,

    # Optional: GUI Stop button support
    [string]$StopFile = ""
)

$ErrorActionPreference = "Stop"

function Should-Stop {
    if ([string]::IsNullOrWhiteSpace($StopFile)) { return $false }
    Test-Path -LiteralPath $StopFile
}

Write-Output "DNS RESOLVE"
Write-Output "Name: $Name"
Write-Output "PS  : $($PSVersionTable.PSVersion)"
Write-Output ""

if (Should-Stop) { Write-Output "[STOP] Stop requested."; exit 0 }

try {
    $r = Resolve-DnsName -Name $Name -ErrorAction Stop |
         Where-Object { $_.Type -in @("A","AAAA") } |
         Select-Object -ExpandProperty IPAddress -Unique

    if (-not $r) { Write-Output "No A/AAAA records found." }
    else { $r | ForEach-Object { " - $_" } }
}
catch {
    $ips = [System.Net.Dns]::GetHostAddresses($Name)
    if (-not $ips -or $ips.Count -eq 0) { throw }
    $ips | ForEach-Object { " - $($_.IPAddressToString)" }
}

