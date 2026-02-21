param(
    [bool]$WhatIfMode = $true,
    [bool]$OfflineMode = $false,
    [string]$OfflineWinDir = "",

    [string]$NewUserName = "newuser",
    [string]$NewFullName = "",
    [string]$NewDescription = "Created by IT Toolkit",
    [string]$NewPassword = "",
    [string]$NewPasswordConfirm = "",

    [bool]$AddToAdministrators = $false,
    [bool]$MustChangeAtNextLogon = $false
)

# Shared helpers (Apply Golden Rules)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------- HELPERS --------------------
function Out-Status([string]$m) { Write-Host "[Status] $m" -ForegroundColor Gray }
function Set-Progress([int]$p, [string]$status = "") {
    Write-Information ("PROGRESS:{0}" -f $p)
    if ($status) { Out-Status $status }
}

# -------------------- MAIN --------------------
try {
    Set-Progress 5 "Validating inputs..."

    # 1. Validation
    if ([string]::IsNullOrWhiteSpace($NewUserName)) { throw "Username is required." }
    if ($NewPassword -ne $NewPasswordConfirm) { throw "Passwords do not match." }

    # 2. ONLINE MODE
    if (-not $OfflineMode) {
        if (-not (Test-Admin)) { throw "Administrator privileges required for online creation." }

        if ($WhatIfMode) {
            Out-Status "[WHATIF] Would create user '$NewUserName' on the live system."
        } else {
            Set-Progress 30 "Creating local user..."
            $secPass = ConvertTo-SecureString $NewPassword -AsPlainText -Force
            $userParams = @{ Name = $NewUserName; Password = $secPass; Description = $NewDescription }
            if ($NewFullName) { $userParams.FullName = $NewFullName }

            New-LocalUser @userParams | Out-Null

            if ($AddToAdministrators) {
                Set-Progress 60 "Adding to Administrators..."
                Add-LocalGroupMember -Group "Administrators" -Member $NewUserName
            }

            if ($MustChangeAtNextLogon) {
                & net.exe user $NewUserName /logonpasswordchg:yes | Out-Null
            }
            Out-Status "[OK] User '$NewUserName' created successfully on live system."
        }
    }
    # 3. OFFLINE MODE
    else {
        if (-not (Test-Path -LiteralPath $OfflineWinDir)) { throw "Windows directory not found: $OfflineWinDir" }
        $systemHive = Join-Path $OfflineWinDir "System32\config\SYSTEM"
        if (-not (Test-Path -LiteralPath $systemHive)) { throw "SYSTEM hive not found at: $systemHive" }

        # Build the 'net user' command strings
        $cmdCreate = "net user $NewUserName `"$NewPassword`" /add /comment:`"$NewDescription`""
        if ($AddToAdministrators) { $cmdCreate += " & net localgroup Administrators $NewUserName /add" }
        if ($MustChangeAtNextLogon) { $cmdCreate += " & net user $NewUserName /logonpasswordchg:yes" }

        if ($WhatIfMode) {
            Out-Status "[WHATIF] Would mount $systemHive"
            Out-Status "[WHATIF] Would inject command: $cmdCreate"
        } else {
            Set-Progress 20 "Mounting offline SYSTEM hive..."
            & reg.exe load HKLM\OFF_SYS "$systemHive" | Out-Null

            try {
                Set-Progress 50 "Injecting creation command..."
                # We inject into the 'Setup' phase which runs before the login screen
                & reg.exe add "HKLM\OFF_SYS\Setup" /v "CmdLine" /t REG_SZ /d "cmd.exe /c $cmdCreate" /f | Out-Null
                # Ensure SetupPhase is set to triggered
                & reg.exe add "HKLM\OFF_SYS\Setup" /v "SetupType" /t REG_DWORD /d 2 /f | Out-Null

                Out-Status "[OK] Command injected. User will be created on next boot of that disk."
            } finally {
                Set-Progress 80 "Unmounting hive..."
                [gc]::Collect()
                Start-Sleep -Seconds 1
                & reg.exe unload HKLM\OFF_SYS | Out-Null
            }
        }
    }

    Set-Progress 100 "Done."

} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}