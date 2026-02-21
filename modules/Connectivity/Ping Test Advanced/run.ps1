param(
    [Parameter(Mandatory=$true)]
    [string]$Target,

    [int]$Count = 4,                 # 0 = continuous
    [int]$TimeoutMs = 2000,
    [int]$IntervalMs = 500,
    [int]$GraphWidth = 30,

    # Hidden/internal (GUI can pass this)
    [string]$StopFile = ""
)

$ErrorActionPreference = "Stop"

function Should-Stop {
    if ([string]::IsNullOrWhiteSpace($StopFile)) { return $false }
    return (Test-Path -LiteralPath $StopFile)
}

function Try-TestConnectionOnce {
    param([string]$TargetHost, [int]$TimeoutMs)

    # Prefer Test-Connection (PS5/PS7), but Timeout differs by version.
    $cmd = Get-Command Test-Connection -ErrorAction SilentlyContinue
    if ($cmd) {
        $p = $cmd.Parameters.Keys

        try {
            if ($p -contains "TimeoutSeconds") {
                $sec = [math]::Ceiling($TimeoutMs / 1000.0)
                $r = Test-Connection -ComputerName $TargetHost -Count 1 -TimeoutSeconds $sec -ErrorAction Stop
                return [pscustomobject]@{ Ok=$true; TimeMs=[int]$r.ResponseTime; Address=[string]$r.Address }
            } else {
                # Windows PowerShell 5.1 doesn't have TimeoutSeconds; fall back to ping.exe for timeout accuracy
                throw "No TimeoutSeconds support"
            }
        } catch {
            # fall through to ping.exe
        }
    }

    # Fallback: ping.exe (honors ms timeout with -w)
    $out = & ping.exe -n 1 -w $TimeoutMs $TargetHost 2>&1
    $text = ($out | Out-String)

    if ($text -match "Reply from\s+([^\s:]+):.*time[=<]\s*(\d+)\s*ms") {
        return [pscustomobject]@{ Ok=$true; TimeMs=[int]$matches[2]; Address=[string]$matches[1] }
    }

    return [pscustomobject]@{ Ok=$false; TimeMs=$null; Address="" }
}

$res = Try-TestConnectionOnce -TargetHost $Target -TimeoutMs $TimeoutMs

function Write-Line {
    param([string]$Text, [string]$Tag = "")
    if ($Tag) { Write-Output ("[{0}] {1}" -f $Tag, $Text) }
    else { Write-Output $Text }
}

function Render-AsciiGraph {
    param([int[]]$Times, [int]$Width)

    if (-not $Times -or $Times.Count -eq 0) { return }

    $max = ($Times | Measure-Object -Maximum).Maximum
    if ($max -le 0) { $max = 1 }

    Write-Output ""
    Write-Output "Latency graph (ms):"
    foreach ($t in $Times) {
        $len = [int]([math]::Round(($t / $max) * $Width))
        if ($len -lt 0) { $len = 0 }
        if ($len -gt $Width) { $len = $Width }
        $bar = ("#" * $len).PadRight($Width, ".")
        Write-Output ("{0,4} ms |{1}|" -f $t, $bar)
    }
}

Write-Output "PING TEST"
Write-Output ("Target     : {0}" -f $Target)
Write-Output ("Count      : {0}  (0 = continuous)" -f $Count)
Write-Output ("TimeoutMs  : {0}" -f $TimeoutMs)
Write-Output ("IntervalMs : {0}" -f $IntervalMs)
Write-Output ("PS         : {0}" -f $PSVersionTable.PSVersion)
Write-Output ""

$times = New-Object System.Collections.Generic.List[int]
$sent = 0
$replies = 0

$continuous = ($Count -le 0)

while ($true) {
    if (Should-Stop) {
        Write-Line "Stop requested." "STOP"
        break
    }

    $sent++
    if (-not $continuous -and $sent -gt $Count) { break }

    $label = if ($continuous) { "Ping $sent (continuous)" } else { "Ping $sent/$Count" }
    Write-Output $label

    $res = Try-TestConnectionOnce -TargetHost $Target -TimeoutMs $TimeoutMs

    if ($res.Ok) {
        $replies++
        $times.Add($res.TimeMs) | Out-Null
        Write-Line ("Reply from {0}: time={1} ms" -f $res.Address, $res.TimeMs) "OK"
    } else {
        Write-Line "Request timed out." "TIMEOUT"
    }

    Start-Sleep -Milliseconds $IntervalMs
}

Write-Output ""
Write-Output "---- Summary ----"
Write-Output ("Sent    : {0}" -f $sent)
Write-Output ("Replies : {0}" -f $replies)

if ($times.Count -gt 0) {
    $min = ($times | Measure-Object -Minimum).Minimum
    $avg = ($times | Measure-Object -Average).Average
    $max = ($times | Measure-Object -Maximum).Maximum
    Write-Output ("RTT ms  : min={0} avg={1:N1} max={2}" -f $min, $avg, $max)

    Render-AsciiGraph -Times $times.ToArray() -Width $GraphWidth
} else {
    Write-Output "No replies received."
}

