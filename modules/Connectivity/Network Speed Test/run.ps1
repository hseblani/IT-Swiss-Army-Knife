param(
    [Parameter()][string]$TestServer = "Auto (Closest Server)",
    [Parameter()][string]$TestSize = "Standard Test (50 MB)",
    [Parameter()][bool]$SkipUploadTest = $false
)

$ErrorActionPreference = "Continue"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "           NETWORK SPEED TEST" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$testTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "  Test Time: $testTime" -ForegroundColor DarkGray
Write-Host ""

# Function to create visual bar graph
function Show-SpeedBar {
    param(
        [string]$Label,
        [double]$SpeedMbps,
        [double]$MaxScale = 500
    )

    $barLength = 50
    $fillLength = [math]::Min([math]::Round(($SpeedMbps / $MaxScale) * $barLength), $barLength)

    $color = if ($SpeedMbps -gt 100) { 'Green' }
    elseif ($SpeedMbps -gt 25) { 'Yellow' }
    else { 'Red' }

    $filledBar = "=" * $fillLength
    $emptyBar = "." * ($barLength - $fillLength)
    $bar = $filledBar + $emptyBar

    Write-Host "  $Label " -NoNewline
    Write-Host "[$bar]" -ForegroundColor $color -NoNewline
    Write-Host " $SpeedMbps Mbps" -ForegroundColor White
}

# Function to show speed gauge
function Show-SpeedGauge {
    param(
        [double]$DownloadMbps,
        [double]$UploadMbps = 0,
        [double]$LatencyMs = 0
    )

    Write-Host ""
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host "  |            SPEED TEST RESULTS                        |" -ForegroundColor Cyan
    Write-Host "  +======================================================+" -ForegroundColor Cyan

    # Download
    $dlRating = if ($DownloadMbps -gt 200) { "EXCELLENT" }
    elseif ($DownloadMbps -gt 100) { "VERY GOOD" }
    elseif ($DownloadMbps -gt 50) { "GOOD" }
    elseif ($DownloadMbps -gt 25) { "FAIR" }
    else { "POOR" }

    $dlColor = if ($DownloadMbps -gt 100) { 'Green' }
    elseif ($DownloadMbps -gt 25) { 'Yellow' }
    else { 'Red' }

    Write-Host "  |                                                      |" -ForegroundColor Cyan
    Write-Host "  |  >> DOWNLOAD SPEED                                   |" -ForegroundColor White
    Write-Host "  |  ---------------------------------------------------- |" -ForegroundColor DarkGray

    $dlSpeedLine = "      Speed:  " + ("{0,10:F2}" -f $DownloadMbps) + " Mbps"
    Write-Host "  | $($dlSpeedLine.PadRight(53))|" -ForegroundColor $dlColor

    $dlRatingLine = "      Rating: " + $dlRating
    Write-Host "  | $($dlRatingLine.PadRight(53))|" -ForegroundColor $dlColor

    # Upload
    if ($UploadMbps -gt 0) {
        $ulRating = if ($UploadMbps -gt 100) { "EXCELLENT" }
        elseif ($UploadMbps -gt 50) { "VERY GOOD" }
        elseif ($UploadMbps -gt 25) { "GOOD" }
        elseif ($UploadMbps -gt 10) { "FAIR" }
        else { "POOR" }

        $ulColor = if ($UploadMbps -gt 50) { 'Green' }
        elseif ($UploadMbps -gt 10) { 'Yellow' }
        else { 'Red' }

        Write-Host "  |                                                      |" -ForegroundColor Cyan
        Write-Host "  |  >> UPLOAD SPEED                                     |" -ForegroundColor White
        Write-Host "  |  ---------------------------------------------------- |" -ForegroundColor DarkGray

        $ulSpeedLine = "      Speed:  " + ("{0,10:F2}" -f $UploadMbps) + " Mbps"
        Write-Host "  | $($ulSpeedLine.PadRight(53))|" -ForegroundColor $ulColor

        $ulRatingLine = "      Rating: " + $ulRating
        Write-Host "  | $($ulRatingLine.PadRight(53))|" -ForegroundColor $ulColor
    }

    # Latency
    if ($LatencyMs -gt 0) {
        $latRating = if ($LatencyMs -lt 20) { "EXCELLENT" }
        elseif ($LatencyMs -lt 50) { "VERY GOOD" }
        elseif ($LatencyMs -lt 100) { "GOOD" }
        elseif ($LatencyMs -lt 150) { "FAIR" }
        else { "POOR" }

        $latColor = if ($LatencyMs -lt 50) { 'Green' }
        elseif ($LatencyMs -lt 100) { 'Yellow' }
        else { 'Red' }

        Write-Host "  |                                                      |" -ForegroundColor Cyan
        Write-Host "  |  >> LATENCY (PING)                                   |" -ForegroundColor White
        Write-Host "  |  ---------------------------------------------------- |" -ForegroundColor DarkGray

        $latPingLine = "      Ping:   " + ("{0,10:F1}" -f $LatencyMs) + " ms"
        Write-Host "  | $($latPingLine.PadRight(53))|" -ForegroundColor $latColor

        $latRatingLine = "      Rating: " + $latRating
        Write-Host "  | $($latRatingLine.PadRight(53))|" -ForegroundColor $latColor
    }

    Write-Host "  |                                                      |" -ForegroundColor Cyan
    Write-Host "  +======================================================+" -ForegroundColor Cyan
}

# Function to show visual comparison graph
function Show-ComparisonGraph {
    param(
        [double]$DownloadMbps,
        [double]$UploadMbps
    )

    Write-Host ""
    Write-Host "  +======================================================+" -ForegroundColor Yellow
    Write-Host "  |         VISUAL BANDWIDTH COMPARISON                  |" -ForegroundColor Yellow
    Write-Host "  +======================================================+" -ForegroundColor Yellow
    Write-Host ""

    Show-SpeedBar -Label "Download >>" -SpeedMbps $DownloadMbps -MaxScale 500
    if ($UploadMbps -gt 0) {
        Show-SpeedBar -Label "Upload   >>" -SpeedMbps $UploadMbps -MaxScale 200
    }

    Write-Host ""
    Write-Host "  Scale: 0       100       250       500+ Mbps" -ForegroundColor DarkGray
}

# Test configuration
$downloadSizeMB = switch -Wildcard ($TestSize) {
    "Quick*" { 10 }
    "Standard*" { 50 }
    "Large*" { 100 }
    default { 50 }
}

$pingTarget = switch -Wildcard ($TestServer) {
    "Cloudflare*" { "1.1.1.1" }
    "Google*" { "8.8.8.8" }
    "Quad9*" { "9.9.9.9" }
    default { "1.1.1.1" }
}

$uploadTestText = if ($SkipUploadTest) { 'Disabled' } else { 'Enabled' }
Write-Host "  +------------------------------------------------+" -ForegroundColor DarkGray
Write-Host "  | Server:      $($TestServer.PadRight(33))|" -ForegroundColor DarkGray
Write-Host "  | Test Size:   $("${downloadSizeMB} MB".PadRight(33))|" -ForegroundColor DarkGray
Write-Host "  | Upload Test: $($uploadTestText.PadRight(33))|" -ForegroundColor DarkGray
Write-Host "  +------------------------------------------------+" -ForegroundColor DarkGray
Write-Host ""

Write-Host "PROGRESS:0" -ForegroundColor Magenta

$downloadSpeedMbps = 0
$uploadSpeedMbps = 0
$avgLatency = 0

# Network detection
Write-Host "  [*] Detecting network connection..." -ForegroundColor Cyan
try {
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1

    if ($adapter) {
        Write-Host "      Adapter:    $($adapter.Name)" -ForegroundColor DarkGray
        Write-Host "      Link Speed: $($adapter.LinkSpeed)" -ForegroundColor DarkGray
        if ($ipConfig) {
            Write-Host "      Local IP:   $($ipConfig.IPAddress)" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Host "      Unable to detect network details" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "PROGRESS:10" -ForegroundColor Magenta

# Latency test
Write-Host "  [*] Testing latency to $pingTarget..." -ForegroundColor Cyan

try {
    $pingResult = Test-Connection -ComputerName $pingTarget -Count 4 -ErrorAction SilentlyContinue

    if ($pingResult) {
        $avgLatency = ($pingResult | Measure-Object -Property ResponseTime -Average).Average
        $minLatency = ($pingResult | Measure-Object -Property ResponseTime -Minimum).Minimum
        $maxLatency = ($pingResult | Measure-Object -Property ResponseTime -Maximum).Maximum

        $latColor = if ($avgLatency -lt 50) { 'Green' } elseif ($avgLatency -lt 100) { 'Yellow' } else { 'Red' }

        Write-Host "      Average: " -NoNewline
        Write-Host ("{0:F1}ms" -f $avgLatency) -ForegroundColor $latColor
        Write-Host "      Range:   ${minLatency}ms - ${maxLatency}ms" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "      Latency test failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "PROGRESS:20" -ForegroundColor Magenta

# Download test
Write-Host "  [*] Testing download speed..." -ForegroundColor Cyan
Write-Host "      Downloading ${downloadSizeMB} MB..." -ForegroundColor DarkGray

$downloadBytes = $downloadSizeMB * 1024 * 1024
$downloadUrl = switch ($downloadSizeMB) {
    10 { "https://speed.cloudflare.com/__down?bytes=10485760" }
    50 { "https://speed.cloudflare.com/__down?bytes=52428800" }
    100 { "https://speed.cloudflare.com/__down?bytes=104857600" }
    default { "https://speed.cloudflare.com/__down?bytes=52428800" }
}

try {
    $tempFile = Join-Path $env:TEMP "speedtest_download.tmp"

    $startTime = Get-Date

    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "IT-Swiss-Army-Knife-SpeedTest/1.0")

    $progressScript = {
        param($sender, $e)
        $percent = [math]::Round(($e.BytesReceived / $e.TotalBytesToReceive) * 100)
        if ($percent % 10 -eq 0) {
            $adjustedPercent = 20 + [math]::Round(($percent / 100) * 30)
            Write-Host "PROGRESS:$adjustedPercent" -ForegroundColor Magenta
        }
    }

    Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action $progressScript -SourceIdentifier WebClientProgress | Out-Null

    $webClient.DownloadFile($downloadUrl, $tempFile)

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    Unregister-Event -SourceIdentifier WebClientProgress -ErrorAction SilentlyContinue
    $webClient.Dispose()

    if (Test-Path $tempFile) {
        $actualBytes = (Get-Item $tempFile).Length
        Remove-Item $tempFile -Force

        $downloadSpeedMbps = [math]::Round(($actualBytes * 8 / $duration / 1000000), 2)

        $dlColor = if ($downloadSpeedMbps -gt 100) { 'Green' } elseif ($downloadSpeedMbps -gt 25) { 'Yellow' } else { 'Red' }

        Write-Host ""
        Write-Host "      Download: " -NoNewline
        Write-Host "$downloadSpeedMbps Mbps" -ForegroundColor $dlColor
        Write-Host "      Time: $([math]::Round($duration, 2))s" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
    Unregister-Event -SourceIdentifier WebClientProgress -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "PROGRESS:50" -ForegroundColor Magenta

# Upload test
if (-not $SkipUploadTest) {
    Write-Host "  [*] Testing upload speed..." -ForegroundColor Cyan
    Write-Host "      Uploading 10 MB..." -ForegroundColor DarkGray

    try {
        $uploadSizeMB = 10
        $uploadBytes = $uploadSizeMB * 1024 * 1024
        $uploadData = New-Object byte[] $uploadBytes
        (New-Object Random).NextBytes($uploadData)

        Write-Host "PROGRESS:60" -ForegroundColor Magenta

        $uploadUrl = "https://speed.cloudflare.com/__up"

        $startTime = Get-Date

        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "IT-Swiss-Army-Knife-SpeedTest/1.0")
        $webClient.Headers.Add("Content-Type", "application/octet-stream")

        $response = $webClient.UploadData($uploadUrl, "POST", $uploadData)

        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        $webClient.Dispose()

        $uploadSpeedMbps = [math]::Round(($uploadBytes * 8 / $duration / 1000000), 2)

        $ulColor = if ($uploadSpeedMbps -gt 50) { 'Green' } elseif ($uploadSpeedMbps -gt 10) { 'Yellow' } else { 'Red' }

        Write-Host ""
        Write-Host "      Upload: " -NoNewline
        Write-Host "$uploadSpeedMbps Mbps" -ForegroundColor $ulColor
        Write-Host "      Time: $([math]::Round($duration, 2))s" -ForegroundColor DarkGray

    } catch {
        Write-Host "      Upload test failed" -ForegroundColor Red
    }

    Write-Host "PROGRESS:80" -ForegroundColor Magenta
} else {
    Write-Host "  [*] Upload test skipped" -ForegroundColor Yellow
    Write-Host "PROGRESS:80" -ForegroundColor Magenta
}

Write-Host ""
Write-Host "PROGRESS:90" -ForegroundColor Magenta

# Display results
Write-Host "=======================================================" -ForegroundColor Cyan

Show-SpeedGauge -DownloadMbps $downloadSpeedMbps -UploadMbps $uploadSpeedMbps -LatencyMs $avgLatency

if ($downloadSpeedMbps -gt 0) {
    Show-ComparisonGraph -DownloadMbps $downloadSpeedMbps -UploadMbps $uploadSpeedMbps
}

# Quick Summary
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor White
Write-Host "  |                 QUICK SUMMARY                        |" -ForegroundColor White
Write-Host "  +======================================================+" -ForegroundColor White

$summaryColor = if ($downloadSpeedMbps -gt 100) { 'Green' } elseif ($downloadSpeedMbps -gt 25) { 'Yellow' } else { 'Red' }
$overallRating = if ($downloadSpeedMbps -gt 200) { "EXCELLENT" }
elseif ($downloadSpeedMbps -gt 100) { "VERY GOOD" }
elseif ($downloadSpeedMbps -gt 50) { "GOOD" }
elseif ($downloadSpeedMbps -gt 25) { "FAIR" }
else { "POOR" }

$dlSummaryLine = "  Download:   " + ("{0:F2}" -f $downloadSpeedMbps) + " Mbps"
Write-Host "  | $($dlSummaryLine.PadRight(53))|" -ForegroundColor $summaryColor

if ($uploadSpeedMbps -gt 0) {
    $ulSummaryColor = if ($uploadSpeedMbps -gt 50) { 'Green' } elseif ($uploadSpeedMbps -gt 10) { 'Yellow' } else { 'Red' }
    $ulSummaryLine = "  Upload:     " + ("{0:F2}" -f $uploadSpeedMbps) + " Mbps"
    Write-Host "  | $($ulSummaryLine.PadRight(53))|" -ForegroundColor $ulSummaryColor
}

if ($avgLatency -gt 0) {
    $latSummaryColor = if ($avgLatency -lt 50) { 'Green' } elseif ($avgLatency -lt 100) { 'Yellow' } else { 'Red' }
    $latSummaryLine = "  Latency:    " + ("{0:F1}" -f $avgLatency) + " ms"
    Write-Host "  | $($latSummaryLine.PadRight(53))|" -ForegroundColor $latSummaryColor
}

$overallLine = "  Overall:    " + $overallRating
Write-Host "  | $($overallLine.PadRight(53))|" -ForegroundColor $summaryColor
Write-Host "  +======================================================+" -ForegroundColor White

Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Yellow
Write-Host "  |             RECOMMENDATIONS                          |" -ForegroundColor Yellow
Write-Host "  +======================================================+" -ForegroundColor Yellow
Write-Host ""

if ($downloadSpeedMbps -gt 200) {
    Write-Host "  >> Your connection is EXCELLENT!" -ForegroundColor Green
    Write-Host "     + Perfect for 4K/8K streaming" -ForegroundColor Green
    Write-Host "     + Smooth online gaming" -ForegroundColor Green
    Write-Host "     + Fast large file transfers" -ForegroundColor Green
} elseif ($downloadSpeedMbps -gt 100) {
    Write-Host "  >> Very good connection!" -ForegroundColor Cyan
    Write-Host "     + Great for HD streaming" -ForegroundColor Cyan
    Write-Host "     + Suitable for video calls" -ForegroundColor Cyan
    Write-Host "     + Good for most online activities" -ForegroundColor Cyan
} elseif ($downloadSpeedMbps -gt 25) {
    Write-Host "  >> Good connection" -ForegroundColor Yellow
    Write-Host "     + Adequate for SD streaming" -ForegroundColor Yellow
    Write-Host "     + Basic browsing and email" -ForegroundColor Yellow
} else {
    Write-Host "  >> Slow connection detected" -ForegroundColor Red
    Write-Host "     - May struggle with video streaming" -ForegroundColor Red
    Write-Host "     - Large downloads will be slow" -ForegroundColor Red
    Write-Host "     - Consider upgrading your plan" -ForegroundColor Red
}

Write-Host ""
Write-Host "PROGRESS:100" -ForegroundColor Magenta

Write-Host "=======================================================" -ForegroundColor Cyan