param(
    [bool]$WhatIfMode = $true,

    [string]$OfflineWindowsPath = "",
    [bool]$AllowProtectedAccounts = $false,

    [string]$TargetUser = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference = 'None'
$ProgressPreference = 'SilentlyContinue'

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }
function Write-Header([string]$title) {
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
    if (-not (Is-Admin)) { throw "Administrator privileges are required. Please run the toolkit as Administrator." }
}

$ProtectedAccounts = @("Administrator", "Guest", "DefaultAccount", "WDAGUtilityAccount", "krbtgt")
function Is-ProtectedUser([string]$name) { return $ProtectedAccounts -contains $name }

try {
    Write-Header "DELETE USER"
    Write-Output ("WhatIf (Dry Run)       : {0}" -f $WhatIfMode)
    Write-Output ("TargetUser             : {0}" -f $TargetUser)
    Write-Output ("AllowProtectedAccounts : {0}" -f $AllowProtectedAccounts)
    Write-Output ""

    Require-Admin

    Write-Progress-Status 10 "Validating..."
    if ([string]::IsNullOrWhiteSpace($TargetUser)) { throw "TargetUser is required." }

    if (Is-ProtectedUser $TargetUser -and -not $AllowProtectedAccounts) {
        throw "Refusing to delete protected account '$TargetUser' (enable AllowProtectedAccounts to override)."
    }

    $existing = Get-LocalUser -Name $TargetUser -ErrorAction SilentlyContinue
    if ($null -eq $existing) { throw "User '$TargetUser' was not found on the ONLINE system." }

    Write-Progress-Status 60 "Deleting user..."
    Remove-LocalUser -Name $TargetUser -WhatIf:$WhatIfMode -Confirm:$false

    Write-Progress-Status 100 "Done."
    Write-Output ""
    Write-Output "Operation completed."
    exit 0
} catch {
    Write-Output ""
    Write-Output ("ERROR: {0}" -f $_.Exception.Message)
    Write-Output "Common causes:"
    Write-Output "  - Not running as Administrator"
    Write-Output "  - Protected account blocked (enable AllowProtectedAccounts to override)"
    Write-Output "  - TargetUser not found on ONLINE Windows"
    exit 1
}
