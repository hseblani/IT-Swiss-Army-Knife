param(
  [ValidateSet("Enable","Disable")]
  [string]$Operation = "Enable",

  [bool]$WhatIfMode = $true,

  [string]$OfflineWindowsPath = "",
  [string]$TargetUser = "",

  [bool]$AllowProtectedAccounts = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ConfirmPreference  = 'None'
$ProgressPreference = 'SilentlyContinue'

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }
function Write-Header($title) { Write-Output "========================================="; Write-Output $title; Write-Output "=========================================" }

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Require-Admin {
    if (-not (Is-Admin)) { throw "Administrator privileges are required. Please run the toolkit as Administrator." }
}

$ProtectedAccounts = @("Administrator","Guest","DefaultAccount","WDAGUtilityAccount","krbtgt")
function Is-ProtectedUser([string]$name) { return $ProtectedAccounts -contains $name }
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

try {
  Write-Header "USER ACCOUNT - ENABLE / DISABLE"
  Write-Output ("Operation              : {0}" -f $Operation)
  Write-Output ("TargetUser              : {0}" -f $TargetUser)
  Write-Output ("WhatIf (Dry Run)        : {0}" -f $WhatIfMode)
  Write-Output ("OfflineWindowsPath      : {0}" -f $(if ($OfflineWindowsPath) { $OfflineWindowsPath } else { "(none)" }))
  Write-Output ("AllowProtectedAccounts  : {0}" -f $AllowProtectedAccounts)
  Write-Output ""

  Require-Admin
  Assert-OfflineNotForChanges -OfflineWindowsPath $OfflineWindowsPath

  if ([string]::IsNullOrWhiteSpace($TargetUser)) { throw "TargetUser is required." }
  $targets = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -eq $TargetUser })
  if (@($targets).Count -eq 0) { throw "User '$TargetUser' not found." }

  Ensure-NotProtected -targets $targets -AllowProtectedAccounts $AllowProtectedAccounts

  if ($Operation -eq "Enable") {
      Write-Progress-Status 60 "Enabling user..."
      Enable-LocalUser -Name $TargetUser -WhatIf:$WhatIfMode -Confirm:$false
  } else {
      Write-Progress-Status 60 "Disabling user..."
      Disable-LocalUser -Name $TargetUser -WhatIf:$WhatIfMode -Confirm:$false
  }

  Write-Progress-Status 100 "Done."
  Write-Output ""; Write-Output "Operation completed."
  exit 0
} catch {
  Write-Output ""
  Write-Output ("ERROR: {0}" -f $_.Exception.Message)
  Write-Output "Common causes:"
  Write-Output "  - Not running as Administrator"
  Write-Output "  - Protected account blocked (enable AllowProtectedAccounts to override)"
  exit 1
}
