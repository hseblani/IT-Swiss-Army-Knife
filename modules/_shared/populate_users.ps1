param(
    [string]$OfflineWindowsPath = "",
    [string]$AllowProtectedAccounts = "false"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Built-in/protected accounts to filter out when AllowProtectedAccounts is false
$protectedAccounts = @(
    "Administrator",
    "Guest",
    "DefaultAccount",
    "WDAGUtilityAccount",
    "krbtgt"
)

function Require-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator privileges are required to load an offline SAM hive. Run the toolkit as Administrator."
    }
}

function Get-OfflineSamUserNames([string]$pathInput) {
    Require-Admin

    # Trim the input
    $pathInput = $pathInput.Trim()

    # Check if it's a direct SAM file or a folder path
    if (Test-Path -LiteralPath $pathInput -PathType Leaf) {
        # It's a file - use it directly as SAM hive
        $samPath = $pathInput
    } else {
        # It's a folder - try to find SAM hive inside
        $testPath = $pathInput

        # If path has Windows subfolder, use it
        if (Test-Path -LiteralPath (Join-Path $testPath "Windows")) {
            $testPath = Join-Path $testPath "Windows"
        }

        # Build SAM path
        $samPath = Join-Path $testPath "System32\Config\SAM"
    }

    if (-not (Test-Path -LiteralPath $samPath)) {
        throw "Offline SAM hive not found: $samPath"
    }

    $mount = "HKLM\OFFSAM_ITSAK"
    $loaded = $false
    try {
        & reg.exe unload $mount 2>$null | Out-Null
        $out = & reg.exe load $mount $samPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to load offline SAM hive. Error: $out"
        }
        $loaded = $true

        $namesKey = "$mount\SAM\Domains\Account\Users\Names"
        $items = Get-ChildItem -Path "Registry::$namesKey" -ErrorAction Stop
        return @($items | Select-Object -ExpandProperty PSChildName | Sort-Object)
    } finally {
        if ($loaded) { & reg.exe unload $mount 2>$null | Out-Null }
    }
}

function Get-OnlineUserNames {
    try {
        return @(Get-LocalUser -ErrorAction Stop | Select-Object -ExpandProperty Name | Sort-Object)
    } catch {
        $out = & net.exe user 2>$null
        $lines = $out -split "`r?`n"
        $names = @()
        $capture = $false
        foreach ($ln in $lines) {
            if ($ln -match '---') { $capture = $true; continue }
            if ($ln -match 'The command completed successfully') { break }
            if ($capture) {
                $parts = $ln.Trim() -split '\s+'
                foreach ($p in $parts) { if ($p) { $names += $p } }
            }
        }
        return @($names | Sort-Object -Unique)
    }
}

function Filter-ProtectedAccounts([array]$userList, [bool]$allowProtected) {
    if ($allowProtected) {
        return $userList
    }

    # Filter out protected accounts
    return @($userList | Where-Object { $_ -notin $protectedAccounts })
}

# Main execution
try {
    $allowProtected = ($AllowProtectedAccounts -eq "true")

    # Check if offline path is provided
    if ([string]::IsNullOrWhiteSpace($OfflineWindowsPath)) {
        # Use online SAM (current Windows)
        $users = Get-OnlineUserNames
    } else {
        # Use offline SAM
        $users = Get-OfflineSamUserNames -pathInput $OfflineWindowsPath
    }

    # Filter and return
    Filter-ProtectedAccounts -userList $users -allowProtected $allowProtected

} catch {
    # Return error as output (will show in dropdown)
    Write-Output "ERROR: $($_.Exception.Message)"
}