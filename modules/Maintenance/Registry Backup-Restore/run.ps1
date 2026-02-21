param(
    [bool]$WhatIfMode = $true,

    [ValidateSet("Backup", "Restore")]
    [string]$Mode = "Backup",

    [string]$BackupFolder = "",
    [string]$BackupName = "RegistryBackup",
    [bool]$AddTimestamp = $true,

    [bool]$IncludeHKLM_SOFTWARE = $true,
    [bool]$IncludeHKLM_SYSTEM = $true,
    [bool]$IncludeHKCU = $true,
    [bool]$IncludeHKU_DEFAULT = $false,

    [string]$RestoreRegFile = "",
    [bool]$RestoreForce = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference = "None"
$ProgressPreference = "SilentlyContinue"

function Out-Info([string]$msg) { Write-Output $msg }
function Out-Err([string]$msg) { Write-Output "[ERROR] $msg" }

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Ensure-Folder {
    param([string]$path)

    if ([string]::IsNullOrWhiteSpace($path)) { return }

    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would ensure folder exists: $path"
        return
    }

    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Run-RegExport {
    param(
        [string]$HivePath,
        [string]$OutFile
    )

    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would export: $HivePath"
        Out-Info "[WHATIF MODE] To file     : $OutFile"
        return
    }

    Out-Info "Exporting $HivePath -> $OutFile"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "reg.exe"
    $psi.Arguments = ('export "{0}" "{1}" /y' -f $HivePath, $OutFile)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($stdout) { Out-Info $stdout.TrimEnd() }
    if ($stderr) { Out-Info $stderr.TrimEnd() }

    if ($p.ExitCode -ne 0) {
        throw ("reg.exe export failed for {0}. ExitCode={1}" -f $HivePath, $p.ExitCode)
    }
}

function Run-RegImport {
    param([string]$InFile)

    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would import registry file:"
        Out-Info "[WHATIF MODE] $InFile"
        return
    }

    Out-Info "Importing registry file: $InFile"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "reg.exe"
    $psi.Arguments = ('import "{0}"' -f $InFile)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($stdout) { Out-Info $stdout.TrimEnd() }
    if ($stderr) { Out-Info $stderr.TrimEnd() }

    if ($p.ExitCode -ne 0) {
        throw ("reg.exe import failed. ExitCode={0}" -f $p.ExitCode)
    }
}

try {
    Out-Info "=== Registry Backup/Restore ==="
    Out-Info "WhatIfMode  : $WhatIfMode"
    Out-Info "Mode        : $Mode"
    Out-Info ""

    $isAdmin = Test-Admin
    Out-Info ("Running as admin: {0}" -f $isAdmin)
    Out-Info ""

    if ($Mode -eq "Backup") {

        if ([string]::IsNullOrWhiteSpace($BackupFolder)) {
            $BackupFolder = Join-Path $PSScriptRoot "backups"
        }

        $suffix = ""
        if ($AddTimestamp) {
            $suffix = "_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
        }

        $baseName = ($BackupName.Trim())
        if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = "RegistryBackup" }

        $outDir = Join-Path $BackupFolder ($baseName + $suffix)

        Out-Info "Backup folder: $outDir"
        Out-Info ""

        # Ensure target folders (no-op in WhatIfMode)
        Ensure-Folder -path $BackupFolder
        Ensure-Folder -path $outDir

        $any = $false

        if ($IncludeHKLM_SOFTWARE) {
            $any = $true
            Run-RegExport -HivePath "HKLM\SOFTWARE" -OutFile (Join-Path $outDir "HKLM_SOFTWARE.reg")
        }

        if ($IncludeHKLM_SYSTEM) {
            $any = $true
            Run-RegExport -HivePath "HKLM\SYSTEM" -OutFile (Join-Path $outDir "HKLM_SYSTEM.reg")
        }

        if ($IncludeHKCU) {
            $any = $true
            Run-RegExport -HivePath "HKCU" -OutFile (Join-Path $outDir "HKCU.reg")
        }

        if ($IncludeHKU_DEFAULT) {
            $any = $true
            Run-RegExport -HivePath "HKU\.DEFAULT" -OutFile (Join-Path $outDir "HKU_DEFAULT.reg")
        }

        if (-not $any) {
            Out-Info ""
            Out-Info "No hives selected. Nothing to export."
            Out-Info "=== Done ==="
            exit 0
        }

        Out-Info ""
        if ($WhatIfMode) {
            Out-Info "[WHATIF MODE] No actual changes made."
        } else {
            Out-Info "[OK] Backup completed."
        }
        Out-Info "=== Done ==="
        exit 0
    }

    # Restore mode
    if (-not $WhatIfMode) {
        if (-not $RestoreForce) {
            throw "You must check: 'I understand restore can break the system' to proceed."
        }
    }

    if ([string]::IsNullOrWhiteSpace($RestoreRegFile)) {
        throw "RestoreRegFile is empty. Provide a .reg file to import."
    }

    if (-not (Test-Path -LiteralPath $RestoreRegFile)) {
        throw ("RestoreRegFile not found: {0}" -f $RestoreRegFile)
    }

    $ext = [IO.Path]::GetExtension($RestoreRegFile)
    if ($ext -ne ".reg") {
        throw "Only .reg files are supported for restore in this module."
    }

    if (-not $isAdmin) {
        Out-Info "Warning: not running as admin. Some imports may fail."
        Out-Info ""
    }

    Run-RegImport -InFile $RestoreRegFile

    Out-Info ""
    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] No actual changes made."
    } else {
        Out-Info "[OK] Restore completed."
    }
    Out-Info "=== Done ==="
} catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}
