param(
    [bool]$WhatIfMode = $true,
    [bool]$ApplyForce = $false,

    # Explorer
    [bool]$ShowFileExtensions = $false,
    [bool]$ShowHiddenFiles = $false,
    [bool]$ShowFullPathInTitleBar = $false,
    [bool]$ExpandToOpenFolder = $false,
    [bool]$OpenThisPCByDefault = $false,

    # Start/Search
    [bool]$DisableSearchHighlights = $false,
    [bool]$DisableBingSearchInStart = $false,
    [bool]$DisableStartSuggestions = $false,

    # Windows 11 UI
    [bool]$Win11ClassicContextMenu = $false,
    [bool]$TaskbarAlignLeft = $false,
    [bool]$DisableWidgets = $false,
    [bool]$DisableChat = $false,

    # System
    [bool]$EnableLongPaths = $false,
    [bool]$DisableAutoPlay = $false,
    [bool]$DisableStickyKeysPrompt = $false,
    [bool]$EnableNumLockAtStartup = $false,

    # Policies/Privacy
    [bool]$DisableTelemetryBasic = $false,
    [bool]$DisableLockScreen = $false,
    [bool]$EnableVerboseLogon = $false,
    [bool]$DisableUACPromptSecureDesktop = $false,

    # Post actions
    [bool]$ExplorerRestartAfterApply = $false
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

function Ensure-Value {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("DWord", "String")][string]$Type,
        [Parameter(Mandatory = $true)]$Value
    )

    if ($WhatIfMode) {
        Out-Info ("[WHATIF MODE] Would set {0}\{1} = {2} ({3})" -f $Path, $Name, $Value, $Type)
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    if ($Type -eq "DWord") {
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value ([int]$Value) -Force | Out-Null
    } else {
        New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
    }

    Out-Info ("[OK] Set {0}\{1} = {2}" -f $Path, $Name, $Value)
}

function Ensure-DefaultValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet("DWord", "String")][string]$Type,
        [Parameter(Mandatory = $true)]$Value
    )

    if ($WhatIfMode) {
        Out-Info ("[WHATIF MODE] Would set (Default) in {0} = {1} ({2})" -f $Path, $Value, $Type)
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    if ($Type -eq "DWord") {
        Set-ItemProperty -Path $Path -Name "(Default)" -Value ([int]$Value) -Force | Out-Null
    } else {
        Set-ItemProperty -Path $Path -Name "(Default)" -Value ([string]$Value) -Force | Out-Null
    }

    Out-Info ("[OK] Set {0}\(Default) = {1}" -f $Path, $Value)
}

function Restart-Explorer {
    if ($WhatIfMode) {
        Out-Info "[WHATIF MODE] Would restart Explorer."
        return
    }

    Out-Info "Restarting Explorer..."
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    Start-Process explorer.exe | Out-Null
    Out-Info "[OK] Explorer restarted."
}

function Is-Win11 {
    try {
        $build = [int](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuild" -ErrorAction Stop).CurrentBuild
        return ($build -ge 22000)
    } catch {
        return $false
    }
}

try {
    Out-Info "=== Common Registry Tweaks ==="
    Out-Info "WhatIfMode: $WhatIfMode"
    Out-Info ""

    if (-not $WhatIfMode) {
        if (-not $ApplyForce) {
            throw "ApplyForce is not checked. Applying tweaks is blocked for safety."
        }
    }

    $isAdmin = Test-Admin
    $win11 = Is-Win11

    Out-Info ("Running as admin: {0}" -f $isAdmin)
    Out-Info ("Windows 11 detected: {0}" -f $win11)
    Out-Info ""

    # Explorer tweaks
    if ($ShowFileExtensions) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Type "DWord" -Value 0
    }
    if ($ShowHiddenFiles) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Type "DWord" -Value 1
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSuperHidden" -Type "DWord" -Value 1
    }
    if ($ShowFullPathInTitleBar) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Type "DWord" -Value 1
    }
    if ($ExpandToOpenFolder) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneExpandToCurrentFolder" -Type "DWord" -Value 1
    }
    if ($OpenThisPCByDefault) {
        # LaunchTo: 1 = This PC, 2 = Quick Access/Home (varies by version but 1 remains This PC)
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type "DWord" -Value 1
    }

    # Start/Search tweaks
    if ($DisableSearchHighlights) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsDynamicSearchBoxEnabled" -Type "DWord" -Value 0
    }
    if ($DisableBingSearchInStart) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type "DWord" -Value 0
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Type "DWord" -Value 0
    }
    if ($DisableStartSuggestions) {
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Type "DWord" -Value 0
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type "DWord" -Value 0
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353694Enabled" -Type "DWord" -Value 0
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type "DWord" -Value 0
    }

    # Windows 11 UI tweaks
    if ($Win11ClassicContextMenu) {
        if (-not $win11) {
            Out-Info "Skip: classic context menu tweak is intended for Windows 11."
        } else {
            # Create: HKCU\Software\Classes\CLSID\{...}\InprocServer32\(Default) = ""
            $p = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            Ensure-DefaultValue -Path $p -Type "String" -Value ""
            Out-Info "Note: You may need to restart Explorer or sign out/in for this to take effect."
        }
    }
    if ($TaskbarAlignLeft) {
        if (-not $win11) {
            Out-Info "Skip: taskbar alignment is Windows 11."
        } else {
            # TaskbarAl: 0=left, 1=center
            Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Type "DWord" -Value 0
        }
    }
    if ($DisableWidgets) {
        if (-not $win11) {
            Out-Info "Skip: widgets toggle is Windows 11."
        } else {
            # TaskbarDa: 0=off, 1=on
            Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Type "DWord" -Value 0
        }
    }
    if ($DisableChat) {
        if (-not $win11) {
            Out-Info "Skip: chat toggle is Windows 11."
        } else {
            # TaskbarMn: 0=off, 1=on
            Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Type "DWord" -Value 0
        }
    }

    # System tweaks
    if ($EnableLongPaths) {
        if (-not $isAdmin) {
            Out-Info "Warning: long paths requires admin. Skipping."
        } else {
            Ensure-Value -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type "DWord" -Value 1
        }
    }
    if ($DisableAutoPlay) {
        # 255 disables autoplay on all drives
        Ensure-Value -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Type "DWord" -Value 255
    }
    if ($DisableStickyKeysPrompt) {
        # Flags "506" commonly disables prompt and hotkey behavior
        Ensure-Value -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Type "String" -Value "506"
    }
    if ($EnableNumLockAtStartup) {
        Ensure-Value -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Type "String" -Value "2"
        Ensure-Value -Path "HKU:\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Type "String" -Value "2"
        Out-Info "Note: NumLock change may require logoff/reboot depending on device/firmware."
    }

    # Policies/Privacy tweaks
    if ($DisableTelemetryBasic) {
        if (-not $isAdmin) {
            Out-Info "Warning: telemetry policy requires admin. Skipping."
        } else {
            Ensure-Value -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type "DWord" -Value 0
        }
    }
    if ($DisableLockScreen) {
        if (-not $isAdmin) {
            Out-Info "Warning: lock screen policy requires admin. Skipping."
        } else {
            Ensure-Value -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -Type "DWord" -Value 1
        }
    }
    if ($EnableVerboseLogon) {
        if (-not $isAdmin) {
            Out-Info "Warning: verbose logon policy requires admin. Skipping."
        } else {
            Ensure-Value -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Type "DWord" -Value 1
        }
    }
    if ($DisableUACPromptSecureDesktop) {
        if (-not $isAdmin) {
            Out-Info "Warning: UAC settings require admin. Skipping."
        } else {
            Ensure-Value -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "PromptOnSecureDesktop" -Type "DWord" -Value 0
        }
    }

    Out-Info ""
    if ($ExplorerRestartAfterApply) {
        Restart-Explorer
    } else {
        Out-Info "Explorer restart: skipped."
    }

    Out-Info ""
    if ($WhatIfMode) { Out-Info "[WHATIF MODE] No registry changes were made." } else { Out-Info "[OK] Tweaks applied." }
    Out-Info "=== Done ==="
} catch {
    Out-Err $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Output $_.ScriptStackTrace }
    exit 1
}
