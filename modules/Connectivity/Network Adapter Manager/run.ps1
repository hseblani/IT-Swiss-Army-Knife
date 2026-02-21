param(
    [Parameter()][string]$Action = "List All Adapters",
    [Parameter()][string]$SelectedAdapter = "",
    [Parameter()][bool]$AutoReboot = $false
)

$ErrorActionPreference = "Continue"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "        NETWORK ADAPTER MANAGER" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This module requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please run the IT Swiss-Army Knife as Administrator." -ForegroundColor Yellow
    return
}

# Parse adapter selection (format: "AdapterName - Status")
$AdapterName = ""
if ($SelectedAdapter -and $SelectedAdapter -ne "N/A (not required for this action)") {
    if ($SelectedAdapter -match '^(.+?)\s+-\s+(.+)$') {
        $AdapterName = $matches[1].Trim()
    } else {
        $AdapterName = $SelectedAdapter
    }
}

Write-Host "Action: $Action" -ForegroundColor Yellow
if ($AdapterName) {
    Write-Host "Selected Adapter: $AdapterName" -ForegroundColor Cyan
}
Write-Host ""

# Initialize progress
Write-Host "PROGRESS:0" -ForegroundColor Magenta

switch -Wildcard ($Action) {

    "List All Adapters*" {
        Write-Host "Detecting network adapters on your system..." -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""

        $adapters = Get-NetAdapter | Sort-Object -Property Name

        if ($adapters.Count -eq 0) {
            Write-Host "No network adapters found!" -ForegroundColor Yellow
            return
        }

        Write-Host "AVAILABLE ADAPTERS:" -ForegroundColor Yellow
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""

        foreach ($adapter in $adapters) {
            $statusColor = if ($adapter.Status -eq 'Up') { 'Green' }
            elseif ($adapter.Status -eq 'Disabled') { 'Red' }
            else { 'Yellow' }

            Write-Host "Adapter Name:  $($adapter.Name)" -ForegroundColor Cyan
            Write-Host "  Status:      $($adapter.Status)" -ForegroundColor $statusColor
            Write-Host "  MAC:         $($adapter.MacAddress)" -ForegroundColor DarkGray
            Write-Host "  Description: $($adapter.InterfaceDescription)" -ForegroundColor DarkGray

            # Get IP info if active
            if ($adapter.Status -eq 'Up') {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                if ($ipConfig) {
                    Write-Host "  IP Address:  $($ipConfig.IPAddress)/$($ipConfig.PrefixLength)" -ForegroundColor Cyan

                    # Get gateway
                    $gateway = Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty NextHop -First 1
                    if ($gateway) {
                        Write-Host "  Gateway:     $gateway" -ForegroundColor Cyan
                    }
                }
            }

            Write-Host ""
        }

        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host "Total Adapters: $($adapters.Count)" -ForegroundColor Yellow

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Enable Selected Adapter*" {
        if ([string]::IsNullOrWhiteSpace($AdapterName)) {
            Write-Host "[ERROR] No adapter selected!" -ForegroundColor Red
            Write-Host "Please select an adapter from the dropdown menu." -ForegroundColor Yellow
            return
        }

        Write-Host "Enabling adapter: $AdapterName" -ForegroundColor Cyan
        Write-Host "PROGRESS:30" -ForegroundColor Magenta

        try {
            $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop

            if ($adapter.Status -eq 'Up') {
                Write-Host "[INFO] Adapter is already enabled" -ForegroundColor Yellow
            } else {
                Enable-NetAdapter -Name $AdapterName -Confirm:$false
                Start-Sleep -Seconds 3

                Write-Host "PROGRESS:70" -ForegroundColor Magenta

                $adapter = Get-NetAdapter -Name $AdapterName
                if ($adapter.Status -eq 'Up') {
                    Write-Host ""
                    Write-Host "Success! Adapter enabled" -ForegroundColor Green
                    Write-Host "  Name:   $($adapter.Name)" -ForegroundColor Cyan
                    Write-Host "  Status: $($adapter.Status)" -ForegroundColor Green

                    # Wait for DHCP
                    Write-Host ""
                    Write-Host "Waiting for network configuration..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 3

                    # Show new IP
                    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notmatch '^169\.254\.' }

                    if ($ipConfig) {
                        Write-Host "  IP:     $($ipConfig.IPAddress)/$($ipConfig.PrefixLength)" -ForegroundColor Cyan
                    } else {
                        Write-Host "  IP:     Obtaining address..." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host ""
                    Write-Host "[WARNING] Adapter enabled but status: $($adapter.Status)" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host ""
            Write-Host "[ERROR] Adapter not found or cannot be enabled" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        }

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Disable Selected Adapter*" {
        if ([string]::IsNullOrWhiteSpace($AdapterName)) {
            Write-Host "[ERROR] No adapter selected!" -ForegroundColor Red
            Write-Host "Please select an adapter from the dropdown menu." -ForegroundColor Yellow
            return
        }

        Write-Host "Disabling adapter: $AdapterName" -ForegroundColor Cyan
        Write-Host "PROGRESS:30" -ForegroundColor Magenta

        try {
            $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop

            if ($adapter.Status -eq 'Disabled') {
                Write-Host "[INFO] Adapter is already disabled" -ForegroundColor Yellow
            } else {
                Disable-NetAdapter -Name $AdapterName -Confirm:$false
                Start-Sleep -Seconds 2

                Write-Host "PROGRESS:70" -ForegroundColor Magenta

                $adapter = Get-NetAdapter -Name $AdapterName
                if ($adapter.Status -eq 'Disabled') {
                    Write-Host ""
                    Write-Host "Success! Adapter disabled" -ForegroundColor Green
                    Write-Host "  Name:   $($adapter.Name)" -ForegroundColor Cyan
                    Write-Host "  Status: $($adapter.Status)" -ForegroundColor Red
                } else {
                    Write-Host ""
                    Write-Host "[WARNING] Adapter disabled but status: $($adapter.Status)" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host ""
            Write-Host "[ERROR] Adapter not found or cannot be disabled" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        }

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Release/Renew IP*" {
        Write-Host "Releasing and renewing IP addresses (DHCP)..." -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""

        Write-Host "Step 1: Releasing IP addresses..." -ForegroundColor Yellow
        Write-Host "PROGRESS:20" -ForegroundColor Magenta

        $releaseOutput = ipconfig /release 2>&1
        $releaseOutput | ForEach-Object { Write-Host $_ -ForegroundColor White }

        Start-Sleep -Seconds 2
        Write-Host "PROGRESS:50" -ForegroundColor Magenta

        Write-Host ""
        Write-Host "Step 2: Renewing IP addresses..." -ForegroundColor Yellow

        $renewOutput = ipconfig /renew 2>&1
        $renewOutput | ForEach-Object { Write-Host $_ -ForegroundColor White }

        Write-Host "PROGRESS:80" -ForegroundColor Magenta

        Start-Sleep -Seconds 1

        Write-Host ""
        Write-Host "Success! IP Release/Renew completed" -ForegroundColor Green

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Flush DNS Cache*" {
        Write-Host "Flushing DNS resolver cache..." -ForegroundColor Cyan
        Write-Host "PROGRESS:30" -ForegroundColor Magenta

        try {
            Clear-DnsClientCache

            Write-Host "PROGRESS:70" -ForegroundColor Magenta

            Write-Host ""
            Write-Host "Success! DNS cache flushed" -ForegroundColor Green
            Write-Host ""
            Write-Host "DNS resolver cache has been cleared." -ForegroundColor White
            Write-Host "This can resolve DNS-related connectivity issues." -ForegroundColor DarkGray
        } catch {
            Write-Host ""
            Write-Host "[ERROR] Failed to flush DNS: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Reset TCP/IP Stack*" {
        Write-Host "Resetting TCP/IP Stack..." -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[WARNING] This will reset all TCP/IP settings to defaults!" -ForegroundColor Yellow
        Write-Host "A system reboot may be required for changes to take effect." -ForegroundColor Yellow
        Write-Host ""

        Write-Host "PROGRESS:20" -ForegroundColor Magenta

        Write-Host "Resetting IPv4..." -ForegroundColor Cyan
        $resetIPv4 = netsh int ipv4 reset 2>&1
        $resetIPv4 | ForEach-Object { Write-Host $_ -ForegroundColor White }

        Write-Host "PROGRESS:50" -ForegroundColor Magenta

        Write-Host ""
        Write-Host "Resetting IPv6..." -ForegroundColor Cyan
        $resetIPv6 = netsh int ipv6 reset 2>&1
        $resetIPv6 | ForEach-Object { Write-Host $_ -ForegroundColor White }

        Write-Host "PROGRESS:80" -ForegroundColor Magenta

        Write-Host ""
        Write-Host "Success! TCP/IP Stack reset completed" -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT: A system reboot is recommended for changes to take effect." -ForegroundColor Yellow

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Reset Winsock Catalog*" {
        Write-Host "Resetting Winsock Catalog..." -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[WARNING] This will reset Windows Sockets API settings!" -ForegroundColor Yellow
        Write-Host "Useful for fixing network application connectivity issues." -ForegroundColor Yellow
        Write-Host ""

        Write-Host "PROGRESS:30" -ForegroundColor Magenta

        Write-Host "Executing: netsh winsock reset" -ForegroundColor Cyan
        $winsockReset = netsh winsock reset 2>&1
        $winsockReset | ForEach-Object { Write-Host $_ -ForegroundColor White }

        Write-Host "PROGRESS:80" -ForegroundColor Magenta

        Write-Host ""
        Write-Host "Success! Winsock Catalog reset completed" -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT: A system reboot is recommended for changes to take effect." -ForegroundColor Yellow

        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }

    "Full Network Reset*" {
        Write-Host "FULL NETWORK RESET" -ForegroundColor Red
        Write-Host "=======================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "[WARNING] This will perform ALL network reset operations:" -ForegroundColor Yellow
        Write-Host "  1. Flush DNS cache" -ForegroundColor White
        Write-Host "  2. Release/Renew IP addresses" -ForegroundColor White
        Write-Host "  3. Reset TCP/IP stack (IPv4 & IPv6)" -ForegroundColor White
        Write-Host "  4. Reset Winsock catalog" -ForegroundColor White
        Write-Host ""
        Write-Host "This is useful for resolving persistent network issues." -ForegroundColor Yellow
        Write-Host ""

        Start-Sleep -Seconds 2

        # Step 1: Flush DNS
        Write-Host "Step 1/4: Flushing DNS cache..." -ForegroundColor Cyan
        Write-Host "PROGRESS:10" -ForegroundColor Magenta
        Clear-DnsClientCache
        Write-Host "Success - DNS cache flushed" -ForegroundColor Green
        Write-Host ""

        # Step 2: Release/Renew
        Write-Host "Step 2/4: Releasing and renewing IP..." -ForegroundColor Cyan
        Write-Host "PROGRESS:25" -ForegroundColor Magenta
        ipconfig /release | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "PROGRESS:35" -ForegroundColor Magenta
        ipconfig /renew | Out-Null
        Write-Host "Success - IP released and renewed" -ForegroundColor Green
        Write-Host ""

        # Step 3: Reset TCP/IP
        Write-Host "Step 3/4: Resetting TCP/IP stack..." -ForegroundColor Cyan
        Write-Host "PROGRESS:50" -ForegroundColor Magenta
        netsh int ipv4 reset | Out-Null
        netsh int ipv6 reset | Out-Null
        Write-Host "Success - TCP/IP stack reset" -ForegroundColor Green
        Write-Host ""

        # Step 4: Reset Winsock
        Write-Host "Step 4/4: Resetting Winsock catalog..." -ForegroundColor Cyan
        Write-Host "PROGRESS:75" -ForegroundColor Magenta
        netsh winsock reset | Out-Null
        Write-Host "Success - Winsock catalog reset" -ForegroundColor Green
        Write-Host ""

        Write-Host "PROGRESS:100" -ForegroundColor Magenta

        Write-Host "=======================================================" -ForegroundColor Cyan
        Write-Host "Success! FULL NETWORK RESET COMPLETED" -ForegroundColor Green
        Write-Host "=======================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "CRITICAL: A system reboot is REQUIRED for all changes to take effect!" -ForegroundColor Red
        Write-Host ""

        if ($AutoReboot) {
            Write-Host "Auto-reboot is enabled. System will restart in 30 seconds..." -ForegroundColor Yellow
            Write-Host "Press Ctrl+C in the main window to cancel." -ForegroundColor Yellow
            Write-Host ""

            for ($i = 30; $i -gt 0; $i--) {
                Write-Host "Rebooting in $i seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }

            Write-Host ""
            Write-Host "Initiating system reboot..." -ForegroundColor Red
            shutdown /r /t 5 /c "Network reset complete - System reboot required"
        } else {
            Write-Host "Please reboot your system manually to complete the network reset." -ForegroundColor Yellow
            Write-Host "You can use: shutdown /r /t 0" -ForegroundColor DarkGray
        }
    }

    default {
        Write-Host "[ERROR] Unknown action: $Action" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan