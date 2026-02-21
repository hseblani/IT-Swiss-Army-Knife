param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter()][string]$FileTypes = "*.txt;*.log",
    [Parameter()][bool]$AllFiles = $true,
    [Parameter()][bool]$DirectoriesOnly = $false,
    [Parameter()][bool]$ReplaceExisting = $false
)

$ErrorActionPreference = "Stop"

# Load shared helpers
$sharedPath = Join-Path $PSScriptRoot "..\..\_shared\common.ps1"
if (Test-Path $sharedPath) {
    . $sharedPath
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Write-ModuleLine {
    param([string]$Line, [ConsoleColor]$Color = "White")

    Write-Host $Line -ForegroundColor $Color
}

function Convert-SizeTokenToBytes {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }

    $t = $Token.Trim()

    if ($t -match '^\d[\d,]*$') {
        $numOnly = $t -replace ",", ""
        return [double]$numOnly
    }

    if ($t -match '^\s*([\d\.,]+)\s*([a-zA-Z]+)\s*$') {
        $numText = $Matches[1] -replace ",", ""
        $unit = $Matches[2].ToUpperInvariant()
        $factor = switch ($unit) {
            "B" { 1 }
            "K" { 1KB }
            "KB" { 1KB }
            "M" { 1MB }
            "MB" { 1MB }
            "G" { 1GB }
            "GB" { 1GB }
            "T" { 1TB }
            "TB" { 1TB }
            default { $null }
        }
        if ($null -eq $factor) { return $null }
        return ([double]$numText * [double]$factor)
    }

    return $null
}

function Format-BytesHuman {
    param([double]$Bytes)

    if ($Bytes -ge 1TB) { return ("{0:0.##} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:0.##} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:0.##} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:0.##} KB" -f ($Bytes / 1KB)) }
    return ("{0:0} B" -f [math]::Round($Bytes))
}

function Format-FileWithSize {
    param([string]$FilePath, [string]$SizeToken)

    if ([string]::IsNullOrWhiteSpace($SizeToken)) { return $FilePath }

    $bytes = Convert-SizeTokenToBytes -Token $SizeToken
    $sizeDisplay = if ($null -ne $bytes) { Format-BytesHuman -Bytes $bytes } else { $SizeToken }

    return ("{0} ({1})" -f $FilePath, $sizeDisplay)
}

function Write-ModuleOutput {
    param([string]$Message, [string]$Type = "Info")

    switch ($Type) {
        "Header" { Write-ModuleLine -Line "=== $Message ===" -Color "Cyan" }
        "Info" { Write-ModuleLine -Line "$Message" -Color "White" }
        "Success" { Write-ModuleLine -Line "[OK] $Message" -Color "Green" }
        "Warning" { Write-ModuleLine -Line "[WARNING] $Message" -Color "Yellow" }
        "Error" { Write-ModuleLine -Line "[ERROR] $Message" -Color "Red" }
        "Skip" { Write-ModuleLine -Line "[SKIPPED] $Message" -Color "DarkYellow" }
        default { Write-ModuleLine -Line "$Message" -Color "White" }
    }
}

function Get-SafePath {
    param([string]$Path)
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    
    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        throw "Invalid path: $Path"
    }
}

function Get-FilePatterns {
    param([string]$Patterns)
    
    if ([string]::IsNullOrWhiteSpace($Patterns)) {
        return @()
    }
    
    $result = @()
    $items = $Patterns -split '[,;]'
    
    foreach ($item in $items) {
        $trimmed = $item.Trim()
        if ($trimmed -ne "") {
            $result += $trimmed
        }
    }
    
    return $result
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

Write-ModuleOutput "COPY DATA MODULE" -Type Header
Write-ModuleOutput ""
Write-ModuleOutput "Configuration:" -Type Info
Write-ModuleOutput "  Source        : $Source"
Write-ModuleOutput "  Destination   : $Destination"
Write-ModuleOutput "  All Files     : $AllFiles"
Write-ModuleOutput "  Dirs Only     : $DirectoriesOnly"
Write-ModuleOutput "  Replace Files : $ReplaceExisting"
if (-not $AllFiles -and -not $DirectoriesOnly) {
    Write-ModuleOutput "  File Types    : $FileTypes"
}
Write-ModuleOutput ""

# Validate source
$sourcePath = Get-SafePath $Source
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Source path does not exist: $sourcePath"
}

$sourceIsFile = Test-Path -LiteralPath $sourcePath -PathType Leaf

if ($DirectoriesOnly -and $sourceIsFile) {
    throw "Cannot use 'Directories Only' with a file source"
}

# Prepare destination
$destPath = Get-SafePath $Destination

# Block same source and destination
$normalizedSource = [System.IO.Path]::GetFullPath($sourcePath).TrimEnd('\', '/')
$normalizedDest = [System.IO.Path]::GetFullPath($destPath).TrimEnd('\', '/')
if ($sourceIsFile) {
    if (Test-Path -LiteralPath $destPath -PathType Container) {
        $destFilePath = Join-Path $destPath (Split-Path -Path $sourcePath -Leaf)
        $normalizedDest = [System.IO.Path]::GetFullPath($destFilePath).TrimEnd('\', '/')
    }
    if ($normalizedSource -ieq $normalizedDest) {
        throw "Source and destination are the same file."
    }
}
else {
    if ($normalizedSource -ieq $normalizedDest) {
        throw "Source and destination are the same directory."
    }
}

# Build robocopy arguments
$robocopyArgs = @()

if ($sourceIsFile) {
    # Copying a single file
    $sourceDir = Split-Path -Path $sourcePath -Parent
    $sourceFileName = Split-Path -Path $sourcePath -Leaf
    
    # Determine destination directory
    if (Test-Path -LiteralPath $destPath -PathType Container) {
        $destDir = $destPath
    }
    else {
        $destDir = Split-Path -Path $destPath -Parent
        $destFileName = Split-Path -Path $destPath -Leaf
        
        if ($destFileName -ne $sourceFileName) {
            throw "When copying a file, destination filename must match source filename"
        }
    }
    
    # Create destination directory if needed
    if (-not (Test-Path -LiteralPath $destDir)) {
        Write-ModuleOutput "Creating destination directory: $destDir" -Type Info
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    
    # Handle existing file at destination
    $destFilePath = Join-Path $destDir $sourceFileName
    if ((Test-Path -LiteralPath $destFilePath) -and -not $ReplaceExisting) {
        $backupName = "$sourceFileName.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-ModuleOutput "Backing up existing file to: $backupName" -Type Warning
        Rename-Item -LiteralPath $destFilePath -NewName $backupName -Force
    }
    
    # Robocopy arguments for single file
    $robocopyArgs = @(
        "`"$sourceDir`""
        "`"$destDir`""
        "`"$sourceFileName`""
        "/256"          # Support long paths
        "/BYTES"        # Output sizes in bytes for reliable parsing
        "/R:1"          # 1 retry
        "/W:1"          # 1 second wait
        "/V"            # Verbose - show skipped files
        "/FP"           # Full path in output
        "/NJH"          # No job header
        "/NJS"          # No job summary
        "/NDL"          # No directory list
        "/NP"           # No progress percentage
    )
    
    # Skip newer files at destination if not replacing
    if (-not $ReplaceExisting) {
        $robocopyArgs += "/XO"
    }
    
}
else {
    # Copying a directory
    $sourceDir = $sourcePath
    $destDir = $destPath
    
    if (Test-Path -LiteralPath $destDir -PathType Leaf) {
        throw "Destination must be a directory when copying a directory"
    }
    
    if (-not (Test-Path -LiteralPath $destDir)) {
        Write-ModuleOutput "Creating destination directory: $destDir" -Type Info
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    
    # Base robocopy arguments
    $robocopyArgs = @(
        "`"$sourceDir`""
        "`"$destDir`""
    )
    
    # File patterns
    if (-not $AllFiles -and -not $DirectoriesOnly) {
        $patterns = Get-FilePatterns -Patterns $FileTypes
        if ($patterns.Count -eq 0) {
            throw "No file patterns specified. Enable 'All Files' or provide file patterns."
        }
        foreach ($pattern in $patterns) {
            $robocopyArgs += "`"$pattern`""
        }
    }
    
    # Directory copy options
    $robocopyArgs += @(
        "/E"            # Copy subdirectories including empty
        "/256"          # Support long paths
        "/BYTES"        # Output sizes in bytes for reliable parsing
        "/R:1"          # 1 retry
        "/W:1"          # 1 second wait
        "/V"            # Verbose - show skipped files
        "/FP"           # Full path in output
        "/NJH"          # No job header
        "/NJS"          # No job summary
        "/NDL"          # No directory list
        "/NP"           # No progress percentage
        "/XX"           # Report extra files
    )
    
    # Directories only
    if ($DirectoriesOnly) {
        $robocopyArgs += "/XF"
        $robocopyArgs += "*"
    }
    
    # Skip newer files
    if (-not $ReplaceExisting) {
        $robocopyArgs += "/XO"
    }
}

# Display command
$cmdDisplay = "robocopy " + ($robocopyArgs -join " ")
Write-ModuleOutput "Command: $cmdDisplay" -Type Info
Write-ModuleOutput ""
Write-ModuleOutput "Starting copy operation..." -Type Info
Write-ModuleOutput ""

# Execute robocopy
$robocopyCmd = "robocopy " + ($robocopyArgs -join " ")

# Start progress bar now that copy is beginning
if (Get-Command Write-ToolkitProgress -ErrorAction SilentlyContinue) {
    Write-ToolkitProgress -Percent 10 -Status "Copying files..."
}

# Process output
$filesCopied = 0
$filesSkipped = 0
$dirsCreated = 0
$errors = 0
$sameFiles = 0
$filesReplaced = 0
$skippedFiles = @()
$allOutput = New-Object System.Collections.Generic.List[string]

function Process-RobocopyLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    $lineStr = $Line.ToString()
    $allOutput.Add($lineStr)

    $status = $null
    $filePath = $null
    $sizeStr = $null

    if ($lineStr -match '^\s*(New File|Newer|Older|Same|Extra|Changed)\s+(\d[\d,\.]*\s*[a-zA-Z]{0,2})\s+(.+)$') {
        $status = $Matches[1].Trim()
        $sizeStr = $Matches[2].Trim()
        $filePath = $Matches[3].Trim()
    } elseif ($lineStr -match '^\s*New Dir\s+(.+)$') {
        $status = "New Dir"
        $filePath = $Matches[1].Trim()
    }

    if ($status -and $filePath) {
        $displayPath = Format-FileWithSize -FilePath $filePath -Size $sizeStr
        switch ($status) {
            "New File" {
                $filesCopied++
                Write-ModuleLine -Line "[COPIED]     $displayPath" -Color "Green"
            }
            "Newer" {
                if ($ReplaceExisting) {
                    $filesCopied++
                    $filesReplaced++
                    Write-ModuleLine -Line "[REPLACED]   $displayPath" -Color "Green"
                } else {
                    $filesSkipped++
                    $skippedFiles += @{File = $filePath; Reason = "Replace Existing Files is disabled" }
                    Write-ModuleLine -Line "[NOT COPIED] $displayPath" -Color "Yellow"
                    Write-ModuleLine -Line "    Reason: Replace Existing Files is disabled" -Color "DarkGray"
                }
            }
            "Older" {
                $filesSkipped++
                $skippedFiles += @{File = $filePath; Reason = "Destination has newer or same version" }
                Write-ModuleLine -Line "[NOT COPIED] $displayPath" -Color "Yellow"
                Write-ModuleLine -Line "    Reason: Destination has newer or same version" -Color "DarkGray"
            }
            "Same" {
                $sameFiles++
                Write-ModuleLine -Line "[UNCHANGED]  $displayPath" -Color "DarkGray"
            }
            "Changed" {
                $filesCopied++
                if ($ReplaceExisting) { $filesReplaced++ }
                Write-ModuleLine -Line "[COPIED]     $displayPath" -Color "Green"
            }
            "Extra" {
                # ignore extras
            }
            "New Dir" {
                $dirsCreated++
                Write-ModuleLine -Line "[DIR CREATED] $displayPath" -Color "Green"
            }
        }
    }

    if ($lineStr -match 'ERROR 32') {
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "File is in use by another program" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: File is in use by another program" -Color "DarkGray"
    }
    elseif ($lineStr -match 'ERROR 5') {
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "Access denied" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: Access denied" -Color "DarkGray"
    }
    elseif ($lineStr -match 'ERROR 206') {
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "Path too long" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: File path is too long" -Color "DarkGray"
    }
    elseif ($lineStr -match 'ERROR 3') {
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "Path not found" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: Path not found" -Color "DarkGray"
    }
    elseif ($lineStr -match 'ERROR 2') {
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "File not found" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: File not found" -Color "DarkGray"
    }
    elseif ($lineStr -match 'ERROR 123') {
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "Invalid file name" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: Invalid file name" -Color "DarkGray"
    }
    elseif ($lineStr -match 'ERROR (\d+)') {
        $errorCode = $Matches[1]
        $errors++
        $filesSkipped++
        $filepath = if ($filePath) { $filePath } else { "Unknown file" }
        $skippedFiles += @{File = $filepath; Reason = "Error code $errorCode" }
        Write-ModuleLine -Line "[NOT COPIED] $filepath" -Color "Red"
        Write-ModuleLine -Line "    Reason: Error code $errorCode" -Color "DarkGray"
    }
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "robocopy"
$psi.Arguments = ($robocopyArgs -join " ")
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
Write-ModuleLine -Line "" -Color "White"
Write-ModuleLine -Line "Processing Files:" -Color "Cyan"
Write-ModuleLine -Line "" -Color "White"

$progressPercent = 10
$lastProgressTick = Get-Date

while (-not $proc.HasExited -or -not $proc.StandardOutput.EndOfStream -or -not $proc.StandardError.EndOfStream) {
    $hadOutput = $false

    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -ne $line) {
            $hadOutput = $true
            Process-RobocopyLine -Line $line
        }
    }

    while (-not $proc.StandardError.EndOfStream) {
        $line = $proc.StandardError.ReadLine()
        if ($null -ne $line) {
            $hadOutput = $true
            Process-RobocopyLine -Line $line
        }
    }

    if (-not $proc.HasExited) {
        if ((Get-Date) - $lastProgressTick -ge [TimeSpan]::FromSeconds(1)) {
            $progressPercent = [Math]::Min(85, $progressPercent + 5)
            if (Get-Command Write-ToolkitProgress -ErrorAction SilentlyContinue) {
                Write-ToolkitProgress -Percent $progressPercent -Status ""
            }
            $lastProgressTick = Get-Date
        }
        if (-not $hadOutput) {
            Start-Sleep -Milliseconds 100
        }
    }
}

$proc.WaitForExit()
$exitCode = $proc.ExitCode

# Update progress after copy completes
if (Get-Command Write-ToolkitProgress -ErrorAction SilentlyContinue) {
    Write-ToolkitProgress -Percent 90 -Status "Processing results..."
}

Write-ModuleOutput ""
Write-ModuleOutput ""
Write-ModuleOutput "Operation Summary" -Type Header
Write-ModuleOutput "  Files copied   : $filesCopied"
Write-ModuleOutput "  Files replaced : $filesReplaced"
Write-ModuleOutput "  Files skipped  : $filesSkipped"
Write-ModuleOutput "  Files unchanged: $sameFiles"
Write-ModuleOutput "  Dirs created   : $dirsCreated"
Write-ModuleOutput "  Errors         : $errors"
Write-ModuleOutput "  Exit code      : $exitCode"

# Show skipped files summary
if ($skippedFiles.Count -gt 0) {
    Write-ModuleOutput ""
    Write-ModuleOutput "Skipped Files Summary ($($skippedFiles.Count) files):" -Type Warning
    foreach ($skip in $skippedFiles) {
        Write-ModuleOutput "  - $($skip.File)" -Type Warning
        Write-ModuleOutput "    $($skip.Reason)" -Type Info
    }
}

# Interpret exit code
$status = @()
if ($exitCode -eq 0) { $status += "No changes" }
if ($exitCode -band 1) { $status += "Files copied" }
if ($exitCode -band 2) { $status += "Extra files exist" }
if ($exitCode -band 4) { $status += "Mismatches exist" }
if ($exitCode -band 8) { $status += "Some files/dirs could not be copied" }
if ($exitCode -band 16) { $status += "Serious error - robocopy did not copy any files" }

if ($status.Count -gt 0) {
    Write-ModuleOutput "  Status         : $($status -join '; ')"
}

Write-ModuleOutput ""

# Show detailed output if there were serious errors
if ($exitCode -ge 8) {
    Write-ModuleOutput ""
    Write-ModuleOutput "Detailed Robocopy Output:" -Type Warning
    Write-ModuleOutput "-----------------------------------" -Type Warning
    foreach ($line in $allOutput) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-ModuleLine -Line "  $line" -Color "DarkGray"
        }
    }
    Write-ModuleOutput "-----------------------------------" -Type Warning
    Write-ModuleOutput ""
}

# Check for failure
if ($exitCode -ge 8) {
    if (Get-Command Write-ToolkitProgress -ErrorAction SilentlyContinue) {
        Write-ToolkitProgress -Percent 100 -Status "Failed"
    }
    Write-ModuleOutput "COPY FAILED" -Type Error
    throw "Robocopy failed with exit code $exitCode"
}

if (Get-Command Write-ToolkitProgress -ErrorAction SilentlyContinue) {
    Write-ToolkitProgress -Percent 100 -Status "Complete"
}

Write-ModuleOutput "COPY COMPLETED SUCCESSFULLY" -Type Success
