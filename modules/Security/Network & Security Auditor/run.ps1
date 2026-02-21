param(
    [string]$Action = "Full Audit",
    [string]$ExportFolder = "__MODULE_OUTPUT__",
    [bool]$ScanPorts = $true,
    [bool]$ScanShares = $true
)

# Shared helpers
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }
function Set-Progress([int]$p, [string]$status = "") {
    Write-Information ("PROGRESS:{0}" -f $p)
    if ($status) { Out-Status $status }
}

try {
    Set-Progress -p 5 -status "Initializing Audit..."
    $computer = [string]$env:COMPUTERNAME
    $reportSections = @()

    # 1. SECURITY: Local Administrators
    Set-Progress -p 20 -status "Auditing Local Administrators..."
    # Rule: Wrap in @() to ensure .Count exists in Strict Mode
    $adminMembers = @(Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Select-Object Name, PrincipalSource, ObjectClass)
    $reportSections += @{ Id = "admins"; Title = "Local Administrators"; Type = "Table"; Data = $adminMembers; Expanded = $true }

    # 2. SECURITY: Firewall & Defender
    Set-Progress -p 40 -status "Checking Defensive Services..."
    $fw = @(Get-NetFirewallProfile | Select-Object Name, Enabled)
    $antivirus = "Unknown"
    try { $antivirus = [string](Get-MpComputerStatus).AntivirusEnabled } catch { $antivirus = "Not Found" }

    # FIXED LINE 38: Forced array check for .Count
    $isVulnerable = (@($fw | Where-Object { $_.Enabled -eq $false }).Count -gt 0)

    $secSummary = [PSCustomObject]@{
        AntivirusActive = [string]$antivirus
        FirewallStatus  = if ($isVulnerable) { "Vulnerable (Off)" } else { "Protected (On)" }
    }
    $reportSections += @{ Id = "sec"; Title = "Security Pulse"; Type = "GridKeyValue"; Collapsible = $false; Data = @(@{ Title = "Protection State"; Obj = $secSummary }) }

    # 3. NETWORK: Listening Ports
    if ($ScanPorts) {
        Set-Progress -p 60 -status "Scanning Listening Ports..."
        $connections = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)
        $portList = @()
        foreach ($c in $connections) {
            $procName = "Unknown"
            try { $procName = (Get-Process -Id $c.OwningProcess).ProcessName } catch {}
            $portList += [PSCustomObject]@{
                Port    = [int]$c.LocalPort
                Process = [string]$procName
                PID     = [int]$c.OwningProcess
                Address = [string]$c.LocalAddress
            }
        }
        $reportSections += @{ Id = "ports"; Title = "Active Listening Ports"; Type = "Table"; Data = @($portList | Sort-Object Port); Expanded = $false }
    }

    # 4. NETWORK: SMB Shares
    if ($ScanShares) {
        Set-Progress -p 80 -status "Scanning Network Shares..."
        $shares = @(Get-SmbShare | Where-Object { $_.Name -notmatch '\$' } | Select-Object Name, Path, Description)
        $reportSections += @{ Id = "shares"; Title = "Active Network Shares"; Type = "Table"; Data = $shares; Expanded = $true }
    }

    # 5. Generate Final Report
    Set-Progress -p 95 -status "Generating HTML Report..."
    if ($ExportFolder -eq "__MODULE_OUTPUT__" -or [string]::IsNullOrWhiteSpace($ExportFolder)) {
        $ExportFolder = Join-Path $env:TEMP "Toolkit-SecurityAudit"
    }
    if (-not (Test-Path $ExportFolder)) { New-Item $ExportFolder -ItemType Directory -Force | Out-Null }

    $htmlPath = Join-Path $ExportFolder "SecurityAudit_$($computer).html"
    New-ToolkitGenericReport -ReportPath $htmlPath `
        -Title "Network & Security Audit" `
        -ComputerName $computer `
        -ReportSections $reportSections

    Set-Progress -p 100 -status "Audit Complete!"
    Out-Status "[OK] Report created: $htmlPath"

} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}