param(
    [string]$StopFile = "",

    [string]$SourceImage = "",
    [string]$TargetFormat = "esd",

    [string]$DestinationFolder = "",
    [string]$DestinationFileName = "",

    [string]$SourceIndex = "",

    [string]$Compression = "",
    [string]$CheckIntegrity = "true"
)

function To-Bool {
    param([object]$v, [bool]$default = $false)
    if ($null -eq $v) { return $default }
    $s = ($v.ToString()).Trim().ToLowerInvariant()
    if ($s -in @("true","1","yes","y","on","checked")) { return $true }
    if ($s -in @("false","0","no","n","off","unchecked","")) { return $false }
    return $default
}

function Should-Stop {
    if ([string]::IsNullOrWhiteSpace($StopFile)) { return $false }
    return (Test-Path -LiteralPath $StopFile)
}

Write-Output "=== CONVERT WIM <-> ESD ==="

# Normalize nulls safely (PS 5.1)
if ($null -eq $SourceImage) { $SourceImage = "" }
if ($null -eq $TargetFormat) { $TargetFormat = "esd" }
if ($null -eq $DestinationFolder) { $DestinationFolder = "" }
if ($null -eq $DestinationFileName) { $DestinationFileName = "" }
if ($null -eq $SourceIndex) { $SourceIndex = "" }
if ($null -eq $Compression) { $Compression = "" }

# Trim whitespace + quotes (use char 34 to avoid quote parsing issues)
$SourceImage = $SourceImage.Trim().Trim([char]34)
$TargetFormat = $TargetFormat.Trim().ToLowerInvariant()
$DestinationFolder = $DestinationFolder.Trim().Trim([char]34)
$DestinationFileName = $DestinationFileName.Trim().Trim([char]34)
$SourceIndex = $SourceIndex.Trim()
$Compression = $Compression.Trim().ToLowerInvariant()

$DoCheck = To-Bool $CheckIntegrity $true

# Validate target format
if ($TargetFormat -ne "wim" -and $TargetFormat -ne "esd") {
    Write-Output "[ERROR] TargetFormat must be 'wim' or 'esd'."
    exit 1
}

# Validate source
if ([string]::IsNullOrWhiteSpace($SourceImage)) {
    Write-Output "[ERROR] SourceImage is required."
    exit 1
}
if (-not (Test-Path -LiteralPath $SourceImage)) {
    Write-Output ("[ERROR] Source file not found: {0}" -f $SourceImage)
    exit 1
}

# Default destination folder
if ([string]::IsNullOrWhiteSpace($DestinationFolder)) {
    $DestinationFolder = [System.IO.Path]::GetDirectoryName($SourceImage)
    Write-Output ("[INFO] DestinationFolder not set. Using source folder: {0}" -f $DestinationFolder)
}

if (-not (Test-Path -LiteralPath $DestinationFolder)) {
    Write-Output ("[ERROR] DestinationFolder not found: {0}" -f $DestinationFolder)
    exit 1
}

# Default destination filename
if ([string]::IsNullOrWhiteSpace($DestinationFileName)) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($SourceImage)
    $DestinationFileName = ($base + "." + $TargetFormat)
    Write-Output ("[INFO] DestinationFileName not set. Using: {0}" -f $DestinationFileName)
}

$destPath = [System.IO.Path]::Combine($DestinationFolder, $DestinationFileName)

# Default compression if blank
if ([string]::IsNullOrWhiteSpace($Compression)) {
    if ($TargetFormat -eq "esd") { $Compression = "recovery" } else { $Compression = "max" }
}

# DISM path
$dism = "$env:WINDIR\System32\dism.exe"
if (-not (Test-Path -LiteralPath $dism)) {
    Write-Output ("[ERROR] DISM not found at: {0}" -f $dism)
    exit 1
}

Write-Output ("Source:      {0}" -f $SourceImage)
Write-Output ("Target:      {0}" -f $destPath)
Write-Output ("Format:      {0}" -f $TargetFormat.ToUpperInvariant())
Write-Output ("Compression: {0}" -f $Compression)
Write-Output ("Integrity:   {0}" -f $(if ($DoCheck) { "Yes" } else { "No" }))
Write-Output ("Index:       {0}" -f $(if ($SourceIndex) { $SourceIndex } else { "(blank)" }))

if (Should-Stop) {
    Write-Output "[STOP] Cancelled before start."
    exit 0
}

# Build DISM args safely
$args = New-Object System.Collections.Generic.List[string]
[void]$args.Add("/English")
[void]$args.Add("/Export-Image")
[void]$args.Add(('/SourceImageFile:"{0}"' -f $SourceImage))

$idxAdded = $false
if (-not [string]::IsNullOrWhiteSpace($SourceIndex)) {
    [int]$idx = 0
    if ([int]::TryParse($SourceIndex, [ref]$idx) -and $idx -ge 1) {
        [void]$args.Add(("/SourceIndex:{0}" -f $idx))
        $idxAdded = $true
    } else {
        Write-Output ("[WARN] SourceIndex '{0}' is invalid. Ignoring it." -f $SourceIndex)
    }
}

if (-not $idxAdded) {
    Write-Output "[INFO] If the image has multiple indexes, DISM may require SourceIndex."
}

[void]$args.Add(('/DestinationImageFile:"{0}"' -f $destPath))
[void]$args.Add(("/Compress:{0}" -f $Compression))
if ($DoCheck) { [void]$args.Add("/CheckIntegrity") }

Write-Output "--------------------------------------------"
Write-Output ("Running: dism.exe {0}" -f ($args -join " "))
Write-Output "--------------------------------------------"

# Start DISM and stream output
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $dism
$psi.Arguments = ($args -join " ")
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::OEM
$psi.StandardErrorEncoding  = [System.Text.Encoding]::OEM

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi

if (-not $p.Start()) {
    Write-Output "[ERROR] Failed to start DISM."
    exit 1
}

while (-not $p.HasExited) {

    if (Should-Stop) {
        Write-Output "[STOP] Cancelling DISM..."
        try { $p.Kill() } catch {}
        break
    }

    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        if ($line) { Write-Output $line }
    }

    while (-not $p.StandardError.EndOfStream) {
        $eline = $p.StandardError.ReadLine()
        if ($eline) { Write-Output ("[ERR] " + $eline) }
    }

    Start-Sleep -Milliseconds 150
}

# Flush remaining
while (-not $p.StandardOutput.EndOfStream) {
    $line = $p.StandardOutput.ReadLine()
    if ($line) { Write-Output $line }
}
while (-not $p.StandardError.EndOfStream) {
    $eline = $p.StandardError.ReadLine()
    if ($eline) { Write-Output ("[ERR] " + $eline) }
}

try { $p.WaitForExit() } catch {}

Write-Output "--------------------------------------------"
Write-Output ("Finished. Exit code: {0}" -f $p.ExitCode)

if ($p.ExitCode -eq 0) {
    if (Test-Path -LiteralPath $destPath) {
        $size = (Get-Item -LiteralPath $destPath).Length
        Write-Output ("Output created: {0} ({1:N0} bytes)" -f $destPath, $size)
    } else {
        Write-Output ("[WARN] ExitCode=0 but destination file not found: {0}" -f $destPath)
    }
} else {
    Write-Output "[WARN] Conversion failed. Check DISM output above."
}
