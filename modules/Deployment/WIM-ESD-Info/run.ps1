param(
    [string]$StopFile = "",
    [string]$ImagePath = ""
)
# ========== GUI-COMPATIBLE EXTERNAL TOOL WRAPPER ==========
function Run-InGUI {
    param(
        [string]$Command,
        [string]$Arguments = "",
        [switch]$Elevated
    )
    
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $Command
    $processInfo.Arguments = $Arguments
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    
    if ($Elevated) {
        $processInfo.Verb = "runas"
    }
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    
    # Output to GUI
    if (-not [string]::IsNullOrEmpty($stdout)) {
        $stdout -split "`r?`n" | ForEach-Object { Write-Output $_ }
    }
    
    if (-not [string]::IsNullOrEmpty($stderr)) {
        $stderr -split "`r?`n" | ForEach-Object { Write-Output "[ERROR] $_" }
    }
    
    return $process.ExitCode
}
# ==========================================================


function Should-Stop {
    if ([string]::IsNullOrWhiteSpace($StopFile)) { return $false }
    return (Test-Path -LiteralPath $StopFile)
}

Write-Output "=== WIM / ESD IMAGE INFORMATION ==="

if ([string]::IsNullOrWhiteSpace($ImagePath)) {
    Write-Output "[ERROR] ImagePath is required."
    exit 1
}

$ImagePath = $ImagePath.Trim().Trim('"')

if (-not (Test-Path -LiteralPath $ImagePath)) {
    Write-Output ("[ERROR] File not found: {0}" -f $ImagePath)
    exit 1
}

$dism = "$env:WINDIR\System32\dism.exe"
if (-not (Test-Path -LiteralPath $dism)) {
    Write-Output ("[ERROR] DISM not found at: {0}" -f $dism)
    exit 1
}

Write-Output ("Image: {0}" -f $ImagePath)
Write-Output "Running: dism /Get-WimInfo"
Write-Output "--------------------------------------------"

# We'll parse these from DISM output
$entries = New-Object System.Collections.Generic.List[object]
$currentIndex = $null

function Parse-Line([string]$line) {
    # Example lines:
    #   Index : 1
    #   Name  : Windows 11 Pro
    if ($line -match '^\s*Index\s*:\s*(\d+)\s*$') {
        $script:currentIndex = [int]$Matches[1]
        return
    }
    if ($line -match '^\s*Name\s*:\s*(.+)\s*$') {
        if ($null -ne $script:currentIndex) {
            $name = $Matches[1].Trim()
            $entries.Add([pscustomobject]@{
                Index = $script:currentIndex
                Name  = $name
            }) | Out-Null

            # Reset for next block
            $script:currentIndex = $null
        }
        return
    }
}

# Build process
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $dism
$psi.Arguments = "/English /Get-WimInfo /WimFile:`"$ImagePath`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow = $true

# DISM commonly writes using console/OEM encoding
$psi.StandardOutputEncoding = [System.Text.Encoding]::OEM
$psi.StandardErrorEncoding  = [System.Text.Encoding]::OEM

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi

if (-not $p.Start()) {
    Write-Output "[ERROR] Failed to start DISM."
    exit 1
}

# Read output while running (PS5.1-safe, no events)
while (-not $p.HasExited) {

    if (Should-Stop) {
        Write-Output "[STOP] Cancelling DISM..."
        try { $p.Kill() } catch {}
        break
    }

    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        if ($line) {
            Write-Output $line
            Parse-Line $line
        }
    }

    while (-not $p.StandardError.EndOfStream) {
        $eline = $p.StandardError.ReadLine()
        if ($eline) { Write-Output ("[ERR] " + $eline) }
    }

    Start-Sleep -Milliseconds 150
}

# Flush remaining output
while (-not $p.StandardOutput.EndOfStream) {
    $line = $p.StandardOutput.ReadLine()
    if ($line) {
        Write-Output $line
        Parse-Line $line
    }
}
while (-not $p.StandardError.EndOfStream) {
    $eline = $p.StandardError.ReadLine()
    if ($eline) { Write-Output ("[ERR] " + $eline) }
}

try { $p.WaitForExit() } catch {}

Write-Output "--------------------------------------------"
Write-Output "WIM/ESD inspection completed."
Write-Output ("Exit code: {0}" -f $p.ExitCode)

# ===== Clean summary table =====
if ($p.ExitCode -eq 0 -and $entries.Count -gt 0) {

    # Sort by index and de-duplicate (just in case)
    $unique = @{}
    foreach ($e in ($entries | Sort-Object Index)) {
        if (-not $unique.ContainsKey($e.Index)) { $unique[$e.Index] = $e.Name }
    }

    # Compute column widths
    $idxWidth = 5
    foreach ($k in $unique.Keys) {
        $len = ([string]$k).Length
        if ($len -gt $idxWidth) { $idxWidth = $len }
    }

    $nameWidth = 10
    foreach ($v in $unique.Values) {
        $len = ([string]$v).Length
        if ($len -gt $nameWidth) { $nameWidth = $len }
    }
    if ($nameWidth -gt 80) { $nameWidth = 80 }  # keep readable

    Write-Output ""
    Write-Output "=== SUMMARY ==="
    Write-Output (("{0,-" + $idxWidth + "}  {1}") -f "Index", "Name")
    Write-Output (("{0,-" + $idxWidth + "}  {1}") -f ("-" * $idxWidth), ("-" * [Math]::Min($nameWidth, 40)))

    foreach ($k in ($unique.Keys | Sort-Object)) {
        $name = $unique[$k]
        if ($name.Length -gt 80) { $name = $name.Substring(0, 77) + "..." }
        Write-Output (("{0,-" + $idxWidth + "}  {1}") -f $k, $name)
    }

    Write-Output ""
    Write-Output "Tip: Use the Index number in your DISM /Source:WIM:...:<Index>"
}
else {
    Write-Output ""
    Write-Output "[WARN] Could not parse Index/Name blocks (or DISM failed)."
}

