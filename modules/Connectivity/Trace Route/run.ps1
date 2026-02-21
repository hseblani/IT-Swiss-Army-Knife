param(
    [string]$Target = "8.8.8.8",
    [int]$MaxHops = 30,
    [bool]$ResolveHostnames = $true,
    [bool]$ShowHopStatus = $false
)

# Shared helpers (Write-ToolkitProgress)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Output "========================================="
Write-Output "TRACE ROUTE"
Write-Output "========================================="
Write-Output ("Target            : {0}" -f $Target)
Write-Output ("Max Hops          : {0}" -f $MaxHops)
Write-Output ("Resolve Hostnames : {0}" -f $ResolveHostnames)
Write-Output ""

Write-ToolkitProgress -Percent 0 -Status "Starting trace..."

# Build tracert arguments
$args = @("-h", $MaxHops)
if (-not $ResolveHostnames) {
    $args += "-d"
}
$args += $Target

# Start tracert as a process we can read from
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "tracert.exe"
$psi.Arguments = ($args -join " ")
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()

$hop = 0

# Read output line-by-line
# Read output line-by-line
while (-not $proc.StandardOutput.EndOfStream) {
    $line = $proc.StandardOutput.ReadLine()
    if (-not $line) { continue }

    # Only show hop output if enabled
    Write-Output $line

    # Detect hop lines for progress
    if ($line -match '^\s*(\d+)\s+') {
        $hop = [int]$Matches[1]
        if ($hop -gt $MaxHops) { $hop = $MaxHops }

        $pct = [math]::Round(($hop / $MaxHops) * 100)
        if ($pct -gt 100) { $pct = 100 }

        if ($ShowHopStatus) {
            Write-ToolkitProgress -Percent $pct -Status ("Hop {0}/{1}" -f $hop, $MaxHops)
        } else {
            # Keep bar moving, but don't show hop text
            Write-ToolkitProgress -Percent $pct -Status ""
        }
    }

}

$proc.WaitForExit()

Write-ToolkitProgress -Percent 100 -Status "Complete"

Write-Output ""
Write-Output "Trace complete."
