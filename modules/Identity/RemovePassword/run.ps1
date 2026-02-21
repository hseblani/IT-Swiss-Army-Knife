param(
    [bool]$WhatIfMode = $true,
    [string]$OfflineWindowsPath = "",
    [string]$TargetUser = "",
    [bool]$AllowProtectedAccounts = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'

function Write-Progress-Status { 
    param([int]$Percent, [string]$Status) 
    Write-Output "[PROGRESS:$Percent] $Status" 
}

function Write-Header($title) { 
    Write-Output "========================================="
    Write-Output $title
    Write-Output "=========================================" 
}

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Is-Admin)) { 
        throw "Administrator privileges are required. Please run the toolkit as Administrator." 
    }
}

$ProtectedAccounts = @("Administrator", "Guest", "DefaultAccount", "WDAGUtilityAccount", "krbtgt")

function Is-ProtectedUser([string]$name) { 
    return $ProtectedAccounts -contains $name 
}

function Ensure-NotProtected([array]$targets, [bool]$AllowProtectedAccounts) {
    $hit = @($targets | Where-Object { Is-ProtectedUser $_.Name })
    if (@($hit).Count -gt 0 -and -not $AllowProtectedAccounts) {
        $names = ($hit | Select-Object -ExpandProperty Name) -join ", "
        throw "Refusing to modify protected account(s): $names (set AllowProtectedAccounts=true to override)"
    }
}

function Assert-OfflineNotForChanges([string]$OfflineWindowsPath) {
    if (-not [string]::IsNullOrWhiteSpace($OfflineWindowsPath)) {
        throw "OfflineWindowsPath is supported only for loading usernames into the dropdown. This module performs ONLINE changes only."
    }
}

function Remove-UserPassword([string]$userName) {
    Write-Output "Attempting to set blank password..."
    
    # Method 1: Set-LocalUser (most reliable)
    try {
        $secureBlankPassword = New-Object System.Security.SecureString
        Set-LocalUser -Name $userName -Password $secureBlankPassword -ErrorAction Stop
        Write-Output "SUCCESS: Password removed using Set-LocalUser"
        return $true
    }
    catch {
        Write-Output "WARNING: Set-LocalUser failed: $($_.Exception.Message)"
    }
    
    # Method 2: net.exe user
    try {
        $out = & net.exe user $userName "" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "SUCCESS: Password removed using net.exe"
            return $true
        }
        else {
            Write-Output "WARNING: net.exe failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Output "WARNING: net.exe failed: $($_.Exception.Message)"
    }
    
    # Method 3: ADSI
    try {
        $user = [ADSI]"WinNT://./$userName,user"
        $user.SetPassword("")
        $user.SetInfo()
        Write-Output "SUCCESS: Password removed using ADSI"
        return $true
    }
    catch {
        Write-Output "WARNING: ADSI failed: $($_.Exception.Message)"
    }
    
    return $false
}

try {
    Write-Header "USER ACCOUNT - REMOVE PASSWORD"
    Write-Output ("TargetUser              : {0}" -f $TargetUser)
    Write-Output ("WhatIf (Dry Run)        : {0}" -f $WhatIfMode)
    Write-Output ("OfflineWindowsPath      : {0}" -f $(if ($OfflineWindowsPath) { $OfflineWindowsPath } else { "(none)" }))
    Write-Output ("AllowProtectedAccounts  : {0}" -f $AllowProtectedAccounts)
    Write-Output ""

    Require-Admin
    Assert-OfflineNotForChanges -OfflineWindowsPath $OfflineWindowsPath

    if ([string]::IsNullOrWhiteSpace($TargetUser)) { 
        throw "TargetUser is required." 
    }
    
    $targets = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -eq $TargetUser })
    if (@($targets).Count -eq 0) { 
        throw "User '$TargetUser' not found." 
    }

    Ensure-NotProtected -targets $targets -AllowProtectedAccounts $AllowProtectedAccounts

    if ($WhatIfMode) {
        Write-Output ""
        Write-Output "[WhatIf] Would set a blank password for '$TargetUser'."
        Write-Progress-Status 100 "Done."
        Write-Output ""
        Write-Output "Operation completed (DRY RUN)."
        exit 0
    }

    Write-Output ""
    Write-Progress-Status 60 "Removing password (setting blank)..."
    $success = Remove-UserPassword -userName $TargetUser
    
    if (-not $success) {
        throw "All password removal methods failed. See output above for details."
    }

    Write-Output ""
    Write-Progress-Status 100 "Done."
    Write-Output ""
    Write-Output "PASSWORD SUCCESSFULLY REMOVED"
    Write-Output ""
    Write-Output "User '$TargetUser' now has NO password (blank password)"
    Write-Output ""
    Write-Output "IMPORTANT NOTES:"
    Write-Output "  - Network logon may be restricted by local security policy"
    Write-Output "  - To enable blank passwords for network access:"
    Write-Output "    1. Run: secpol.msc"
    Write-Output "    2. Navigate to: Local Policies -> Security Options"
    Write-Output "    3. Find: Accounts: Limit local account use of blank passwords..."
    Write-Output "    4. Set to: DISABLED"
    Write-Output ""
    Write-Output "Operation completed successfully."
    exit 0
    
}
catch {
    Write-Output ""
    Write-Output "========================================"
    Write-Output "ERROR: Password Removal Failed"
    Write-Output "========================================"
    Write-Output ("Error: {0}" -f $_.Exception.Message)
    Write-Output ""
    Write-Output "Common causes:"
    Write-Output "  1. Not running as Administrator"
    Write-Output "  2. Local Security Policy blocks blank passwords"
    Write-Output "  3. Protected account - enable AllowProtectedAccounts"
    Write-Output "  4. User account does not exist"
    Write-Output "  5. Domain account (only local accounts supported)"
    Write-Output ""
    exit 1
}