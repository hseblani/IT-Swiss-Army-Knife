param(
    [Parameter()][string]$TargetHost = "127.0.0.1",
    [Parameter()][string]$ScanMode = "Quick Scan (Common Ports)",
    [Parameter()][string]$CustomPorts = "",
    [Parameter()][string]$Timeout = "1000",
    [Parameter()][bool]$ShowClosedPorts = $false,
    [Parameter()][bool]$ResolveServices = $true,
    [Parameter()][bool]$ExportResults = $false
)

$ErrorActionPreference = "Continue"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "              PORT SCANNER" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# Parse timeout
$timeoutMs = 1000
if (-not [int]::TryParse($Timeout, [ref]$timeoutMs)) {
    $timeoutMs = 1000
}
if ($timeoutMs -lt 100) { $timeoutMs = 100 }
if ($timeoutMs -gt 10000) { $timeoutMs = 10000 }

# Validate target
if ([string]::IsNullOrWhiteSpace($TargetHost)) {
    Write-Host "[ERROR] Target host is required!" -ForegroundColor Red
    return
}

# Resolve hostname to IP if needed
Write-Host "Target: $TargetHost" -ForegroundColor Yellow
$targetIP = $TargetHost

try {
    $resolvedIP = [System.Net.Dns]::GetHostAddresses($TargetHost) | 
        Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
        Select-Object -First 1
    
    if ($resolvedIP) {
        $targetIP = $resolvedIP.IPAddressToString
        if ($targetIP -ne $TargetHost) {
            Write-Host "Resolved to: $targetIP" -ForegroundColor Cyan
        }
    }
} catch {
    Write-Host "[WARNING] Could not resolve hostname, using as-is" -ForegroundColor Yellow
}

Write-Host ""

# Common port database with service names
$commonPorts = @{
    20    = "FTP Data"
    21    = "FTP Control"
    22    = "SSH"
    23    = "Telnet"
    25    = "SMTP"
    53    = "DNS"
    80    = "HTTP"
    110   = "POP3"
    143   = "IMAP"
    443   = "HTTPS"
    445   = "SMB"
    465   = "SMTPS"
    587   = "SMTP (TLS)"
    993   = "IMAPS"
    995   = "POP3S"
    1433  = "MS SQL Server"
    1521  = "Oracle DB"
    3306  = "MySQL"
    3389  = "RDP"
    5432  = "PostgreSQL"
    5900  = "VNC"
    6379  = "Redis"
    8080  = "HTTP Proxy"
    8443  = "HTTPS Alt"
    27017 = "MongoDB"
}

# Define port lists based on scan mode
$portsToScan = @()

switch -Wildcard ($ScanMode) {
    "Quick Scan*" {
        # Most common ports
        $portsToScan = @(21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 3389, 8080, 8443)
        Write-Host "Scan Mode: Quick Scan (13 common ports)" -ForegroundColor Yellow
    }
    "Full Scan*" {
        # Ports 1-1024
        $portsToScan = 1..1024
        Write-Host "Scan Mode: Full Scan (ports 1-1024)" -ForegroundColor Yellow
    }
    "Web Services*" {
        # Web-related ports
        $portsToScan = @(80, 443, 8000, 8008, 8080, 8088, 8443, 8888, 9000, 9090)
        Write-Host "Scan Mode: Web Services" -ForegroundColor Yellow
    }
    "Database Services*" {
        # Database ports
        $portsToScan = @(1433, 1521, 3306, 5432, 5984, 6379, 9042, 27017, 28015, 50000)
        Write-Host "Scan Mode: Database Services" -ForegroundColor Yellow
    }
    "Remote Access*" {
        # Remote access ports
        $portsToScan = @(22, 23, 3389, 5900, 5901, 5902, 5903, 5904, 5905)
        Write-Host "Scan Mode: Remote Access" -ForegroundColor Yellow
    }
    "Custom Range*" {
        Write-Host "Scan Mode: Custom Range" -ForegroundColor Yellow
        
        if ([string]::IsNullOrWhiteSpace($CustomPorts)) {
            Write-Host "[ERROR] Custom ports must be specified!" -ForegroundColor Red
            Write-Host "Examples: 80,443,8080 or 1000-2000 or 80,443,1000-2000" -ForegroundColor Yellow
            return
        }
        
        # Parse custom ports (support both comma-separated and ranges)
        $portParts = $CustomPorts -split ','
        foreach ($part in $portParts) {
            $part = $part.Trim()
            
            if ($part -match '^(\d+)-(\d+)$') {
                # Range (e.g., 1000-2000)
                $start = [int]$matches[1]
                $end = [int]$matches[2]
                
                if ($start -le $end -and $start -ge 1 -and $end -le 65535) {
                    $portsToScan += $start..$end
                } else {
                    Write-Host "[WARNING] Invalid port range: $part (must be 1-65535)" -ForegroundColor Yellow
                }
            }
            elseif ($part -match '^\d+$') {
                # Single port
                $port = [int]$part
                if ($port -ge 1 -and $port -le 65535) {
                    $portsToScan += $port
                } else {
                    Write-Host "[WARNING] Invalid port: $part (must be 1-65535)" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "[WARNING] Invalid port format: $part" -ForegroundColor Yellow
            }
        }
        
        if ($portsToScan.Count -eq 0) {
            Write-Host "[ERROR] No valid ports to scan!" -ForegroundColor Red
            return
        }
        
        # Remove duplicates and sort
        $portsToScan = $portsToScan | Select-Object -Unique | Sort-Object
    }
}

Write-Host ""
Write-Host "Scan Parameters:" -ForegroundColor Cyan
Write-Host "  Total Ports:       $($portsToScan.Count)"
Write-Host "  Timeout:           ${timeoutMs}ms"
Write-Host "  Resolve Services:  $(if ($ResolveServices) { 'Yes' } else { 'No' })"
Write-Host "  Show Closed:       $(if ($ShowClosedPorts) { 'Yes' } else { 'No' })"
Write-Host ""
Write-Host "Starting port scan..." -ForegroundColor Cyan
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

# Initialize progress
Write-Host "PROGRESS:0" -ForegroundColor Magenta

# Results storage
$results = @()
$openCount = 0
$closedCount = 0
$scanned = 0
$totalPorts = $portsToScan.Count

# Scan each port
foreach ($port in $portsToScan) {
    $scanned++
    
    # Update progress
    if ($scanned % 10 -eq 0 -or $scanned -eq $totalPorts) {
        $percent = [math]::Round(($scanned / $totalPorts) * 100)
        Write-Host "PROGRESS:$percent" -ForegroundColor Magenta
    }
    
    # Attempt TCP connection
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connect = $tcpClient.BeginConnect($targetIP, $port, $null, $null)
    $wait = $connect.AsyncWaitHandle.WaitOne($timeoutMs, $false)
    
    $isOpen = $false
    $status = "Closed"
    
    if ($wait) {
        try {
            $tcpClient.EndConnect($connect)
            $isOpen = $true
            $status = "Open"
            $openCount++
        } catch {
            $closedCount++
        }
    } else {
        $closedCount++
    }
    
    $tcpClient.Close()
    
    # Get service name
    $serviceName = "Unknown"
    if ($ResolveServices) {
        if ($commonPorts.ContainsKey($port)) {
            $serviceName = $commonPorts[$port]
        } else {
            try {
                $service = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
                    Where-Object { $_.Port -eq $port } | Select-Object -First 1
                
                if (-not $service) {
                    # Try to get from services file or well-known ports
                    $serviceName = "Unknown"
                }
            } catch {
                $serviceName = "Unknown"
            }
        }
    }
    
    # Display result
    if ($isOpen) {
        $line = "[OPEN]    Port {0,5}" -f $port
        if ($ResolveServices) {
            $line += "  -  $serviceName"
        }
        Write-Host $line -ForegroundColor Green
    } elseif ($ShowClosedPorts) {
        $line = "[CLOSED]  Port {0,5}" -f $port
        Write-Host $line -ForegroundColor DarkGray
    }
    
    # Store result
    $results += [PSCustomObject]@{
        Port        = $port
        Status      = $status
        ServiceName = $serviceName
    }
}

# Ensure 100% progress
Write-Host "PROGRESS:100" -ForegroundColor Magenta

Write-Host ""
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host ""
Write-Host "SCAN COMPLETE!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Target:        $TargetHost" -ForegroundColor White
if ($targetIP -ne $TargetHost) {
    Write-Host "  IP Address:    $targetIP" -ForegroundColor White
}
Write-Host "  Total Scanned: $totalPorts ports"
Write-Host "  Open:          $openCount" -ForegroundColor Green
Write-Host "  Closed:        $closedCount" -ForegroundColor Red
Write-Host ""

# Display open ports table
$openPorts = $results | Where-Object { $_.Status -eq "Open" } | Sort-Object Port

if ($openPorts.Count -gt 0) {
    Write-Host "Open Ports:" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------" -ForegroundColor Gray
    
    if ($ResolveServices) {
        Write-Host ("{0,-10} {1}" -f "Port", "Service") -ForegroundColor Yellow
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        
        foreach ($portInfo in $openPorts) {
            Write-Host ("{0,-10} {1}" -f $portInfo.Port, $portInfo.ServiceName) -ForegroundColor White
        }
    } else {
        Write-Host "Port" -ForegroundColor Yellow
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        
        foreach ($portInfo in $openPorts) {
            Write-Host $portInfo.Port -ForegroundColor White
        }
    }
    
    Write-Host ""
    
    # Security recommendations
    Write-Host "Security Notes:" -ForegroundColor Yellow
    
    $riskyPorts = @{
        21   = "FTP - Consider using SFTP (port 22) instead"
        23   = "Telnet - HIGHLY INSECURE! Use SSH (port 22) instead"
        445  = "SMB - Ensure proper authentication and latest patches"
        3389 = "RDP - Use strong passwords and consider VPN access"
        5900 = "VNC - Use strong passwords and consider SSH tunnel"
    }
    
    $foundRiskyPorts = $false
    foreach ($portInfo in $openPorts) {
        if ($riskyPorts.ContainsKey($portInfo.Port)) {
            if (-not $foundRiskyPorts) {
                Write-Host "  Security Recommendations:" -ForegroundColor Red
                $foundRiskyPorts = $true
            }
            Write-Host "  ⚠ Port $($portInfo.Port): $($riskyPorts[$portInfo.Port])" -ForegroundColor Yellow
        }
    }
    
    if (-not $foundRiskyPorts) {
        Write-Host "  No critical security issues detected" -ForegroundColor Green
    }
} else {
    Write-Host "No open ports found on $TargetHost" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible reasons:" -ForegroundColor DarkGray
    Write-Host "  - Host is offline or unreachable" -ForegroundColor DarkGray
    Write-Host "  - Firewall is blocking connections" -ForegroundColor DarkGray
    Write-Host "  - No services running on scanned ports" -ForegroundColor DarkGray
}

# Export to CSV if requested
if ($ExportResults -and $results.Count -gt 0) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeHostname = $TargetHost -replace '[\\/:*?"<>|]', '_'
    $exportPath = Join-Path $env:USERPROFILE "Desktop\PortScan-${safeHostname}-$timestamp.csv"
    
    try {
        # Only export open ports unless ShowClosedPorts is true
        $exportData = if ($ShowClosedPorts) { $results } else { $openPorts }
        $exportData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        
        Write-Host ""
        Write-Host "Results exported to:" -ForegroundColor Green
        Write-Host "  $exportPath" -ForegroundColor Cyan
        Write-Host "  $(($exportData).Count) port(s) exported" -ForegroundColor White
    } catch {
        Write-Host ""
        Write-Host "[ERROR] Failed to export CSV: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
