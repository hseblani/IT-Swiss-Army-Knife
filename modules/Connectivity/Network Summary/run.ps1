$ErrorActionPreference = "Stop"

Write-Output "NETWORK SUMMARY"
Write-Output "PS: $($PSVersionTable.PSVersion)"
Write-Output ""

# Local adapters
try {
  $adapters = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq "Up" }
  foreach ($a in $adapters) {
    Write-Output "Adapter : $($a.InterfaceAlias)"
    Write-Output "IPv4    : $($a.IPv4Address.IPAddress -join ', ')"
    Write-Output "Gateway : $($a.IPv4DefaultGateway.NextHop)"
    Write-Output "DNS     : $($a.DnsServer.ServerAddresses -join ', ')"
    Write-Output "---------------------------------------------------------------"
  }
}
catch {
  ipconfig /all
  Write-Output ""
}

# Public IP
try {
  $pub = Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 8
  Write-Output "---------------------------------------------------------------"
  Write-Output "Public IP: $($pub.ip)"
  Write-Output "---------------------------------------------------------------"
}
catch {
  Write-Output "---------------------------------------------------------------"
  Write-Output "Public IP: (failed to fetch)"
  Write-Output "---------------------------------------------------------------"
}

