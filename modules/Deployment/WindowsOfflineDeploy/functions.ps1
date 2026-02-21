Set-StrictMode -Version Latest

<# 
    WindowsOfflineDeploy - functions.ps1 (ENHANCED)
    - Live streaming for ALL external tools (DISM / DiskPart / BCDBOOT / REG / EXPAND)
    - Optional capture (while streaming) for commands where we need to parse output
    - Progress reporting support
    - Better error handling and validation
#>

function Invoke-LiveProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string]$Arguments = "",
        [Parameter()][string]$WorkingDirectory = "",
        [Parameter()][hashtable]$Environment = $null,
        [Parameter()][switch]$IgnoreExitCode,
        [Parameter()][int]$TimeoutSeconds = 0,
        [Parameter()][switch]$Capture
    )

    # Pretty command line for logs
    $cmdLine = if ($Arguments) { "$FilePath $Arguments" } else { $FilePath }
    Write-Output ">> $cmdLine"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    if ($Environment) {
        foreach ($k in $Environment.Keys) {
            $psi.Environment[$k] = [string]$Environment[$k]
        }
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    # Capture collections (thread-safe) if requested
    $outQ = $null
    $errQ = $null
    if ($Capture) {
        $outQ = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $errQ = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    }

    # Use async events to get live output reliably
    $outEvent = Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) {
            Write-Output $EventArgs.Data
            if ($Event.MessageData -and $Event.MessageData.outQ) { $Event.MessageData.outQ.Enqueue([string]$EventArgs.Data) }
        }
    } -MessageData @{ outQ = $outQ }

    $errEvent = Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) {
            Write-Output ("[stderr] " + $EventArgs.Data)
            if ($Event.MessageData -and $Event.MessageData.errQ) { $Event.MessageData.errQ.Enqueue([string]$EventArgs.Data) }
        }
    } -MessageData @{ errQ = $errQ }

    try {
        if (-not $p.Start()) { throw "Failed to start: $FilePath" }
        $p.BeginOutputReadLine()
        $p.BeginErrorReadLine()

        if ($TimeoutSeconds -gt 0) {
            if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
                try { $p.Kill() } catch {}
                throw "Timeout after $TimeoutSeconds seconds: $cmdLine"
            }
        } else {
            $p.WaitForExit()
        }

        $code = $p.ExitCode
        Write-Output "<< ExitCode: $code"

        if (-not $IgnoreExitCode -and $code -ne 0) {
            throw "Command failed (ExitCode=$code): $cmdLine"
        }

        if ($Capture) {
            # Drain queues to arrays
            $out = New-Object System.Collections.Generic.List[string]
            $err = New-Object System.Collections.Generic.List[string]
            $tmp = $null
            while ($outQ.TryDequeue([ref]$tmp)) { $out.Add($tmp) | Out-Null }
            while ($errQ.TryDequeue([ref]$tmp)) { $err.Add($tmp) | Out-Null }

            return [pscustomobject]@{
                ExitCode    = $code
                StdOutLines = $out.ToArray()
                StdErrLines = $err.ToArray()
                StdOutText  = ($out -join "`r`n")
                StdErrText  = ($err -join "`r`n")
                Command     = $cmdLine
            }
        }

        return $code
    }
    finally {
        try { Unregister-Event -SourceIdentifier $outEvent.Name -ErrorAction SilentlyContinue } catch {}
        try { Unregister-Event -SourceIdentifier $errEvent.Name -ErrorAction SilentlyContinue } catch {}
        try { $outEvent | Remove-Job -Force -ErrorAction SilentlyContinue } catch {}
        try { $errEvent | Remove-Job -Force -ErrorAction SilentlyContinue } catch {}
        try { $p.Dispose() } catch {}
    }
}

function Invoke-DiskPartLive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter()][string]$LogName = "diskpart",
        [Parameter()][switch]$Capture
    )

    $temp = Join-Path $env:TEMP ("diskpart_{0}_{1}.txt" -f $LogName, (Get-Date -Format "yyyyMMdd_HHmmss"))
    Set-Content -LiteralPath $temp -Value $ScriptText -Encoding ASCII

    try {
        if ($Capture) {
            return Invoke-LiveProcess -FilePath "diskpart.exe" -Arguments "/s `"$temp`"" -Capture
        } else {
            return Invoke-LiveProcess -FilePath "diskpart.exe" -Arguments "/s `"$temp`""
        }
    }
    finally {
        try { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Write-Output $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Write-Progress-Status {
    param(
        [Parameter(Mandatory)][int]$Percent,
        [Parameter(Mandatory)][string]$Status
    )
    # Output in a format the GUI can parse
    Write-Output "[PROGRESS:$Percent] $Status"
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This module must run as Administrator."
    }
}

function Get-SafeDisk {
    param([Parameter(Mandatory)][int]$DiskNumber)

    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop

    if ($disk.IsSystem -or $disk.IsBoot) {
        throw "Refusing to operate on Disk $DiskNumber because it is marked IsSystem/IsBoot."
    }
    
    # Additional safety check for disk 0
    if ($DiskNumber -eq 0) {
        throw "Refusing to operate on Disk 0 as an additional safety measure."
    }
    
    return $disk
}

function Test-DiskSpace {
    param(
        [Parameter(Mandatory)][object]$Disk,
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$ImageIndex
    )
    
    Write-Log "Checking disk space requirements..."
    
    # Get image size using DISM
    $res = Invoke-LiveProcess -FilePath "dism.exe" -Arguments ("/English /Get-WimInfo /WimFile:`"$ImagePath`" /Index:$ImageIndex") -Capture
    
    $imageSizeGB = 0
    foreach ($line in $res.StdOutLines) {
        if ($line -match "Size\s*:\s*([\d,]+)\s*bytes") {
            $bytes = $matches[1] -replace ",", ""
            $imageSizeGB = [Math]::Round([long]$bytes / 1GB, 2)
            break
        }
    }
    
    $diskSizeGB = [Math]::Round($Disk.Size / 1GB, 2)
    $requiredGB = $imageSizeGB + 5  # Add 5GB buffer for boot partitions and overhead
    
    Write-Log "Disk Size: $diskSizeGB GB, Image Size: $imageSizeGB GB, Required: $requiredGB GB"
    
    if ($diskSizeGB -lt $requiredGB) {
        throw "Insufficient disk space. Disk: $diskSizeGB GB, Required: $requiredGB GB (Image: $imageSizeGB GB + 5GB buffer)"
    }
    
    Write-Log "Disk space check passed."
}

function Mount-IsoAndGetInstallImage {
    param([Parameter(Mandatory)][string]$IsoPath)

    if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }

    Write-Log "Mounting ISO: $IsoPath"
    $di = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    Start-Sleep -Milliseconds 800  # Increased wait time for slower systems

    $vol = $null
    $retries = 5
    while ($retries -gt 0 -and -not $vol) {
        try { 
            $vol = $di | Get-Volume -ErrorAction Stop | Select-Object -First 1 
            if ($vol.DriveLetter) { break }
        } catch {}
        Start-Sleep -Milliseconds 500
        $retries--
    }
    
    if (-not $vol -or -not $vol.DriveLetter) { throw "Failed to determine mounted ISO drive letter." }

    $root = "{0}:\" -f $vol.DriveLetter
    $wim = Join-Path $root "sources\install.wim"
    $esd = Join-Path $root "sources\install.esd"

    if (Test-Path -LiteralPath $wim) { return [pscustomobject]@{ DiskImage=$di; Root=$root; ImagePath=$wim; Sxs=(Join-Path $root "sources\sxs") } }
    if (Test-Path -LiteralPath $esd) { return [pscustomobject]@{ DiskImage=$di; Root=$root; ImagePath=$esd; Sxs=(Join-Path $root "sources\sxs") } }

    throw "Could not find sources\install.wim or sources\install.esd inside ISO."
}

function Dism-GetWimInfo {
    param([Parameter(Mandatory)][string]$ImagePath)

    if (-not (Test-Path -LiteralPath $ImagePath)) { throw "Image file not found: $ImagePath" }

    Write-Log "Reading image info: $ImagePath"
    $res = Invoke-LiveProcess -FilePath "dism.exe" -Arguments ("/English /Get-WimInfo /WimFile:`"$ImagePath`"") -Capture

    $outLines = @($res.StdOutLines + $res.StdErrLines)
    $raw = (($outLines | Out-String).TrimEnd())

    $images = @()
    $current = $null

    foreach ($ln in $outLines) {
        if ($ln -match "^Index\s*:\s*(\d+)") {
            if ($current) { $images += $current }
            $current = [pscustomobject]@{
                Index = [int]$matches[1]
                Name = ""
                Architecture = ""
                Version = ""
                Size = ""
            }
        }
        elseif ($current) {
            if ($ln -match "^Name\s*:\s*(.+)") { $current.Name = $matches[1].Trim() }
            elseif ($ln -match "^Architecture\s*:\s*(.+)") { $current.Architecture = $matches[1].Trim() }
            elseif ($ln -match "^Version\s*:\s*(.+)") { $current.Version = $matches[1].Trim() }
            elseif ($ln -match "^Size\s*:\s*(.+)") { $current.Size = $matches[1].Trim() }
        }
    }
    if ($current) { $images += $current }

    return [pscustomobject]@{ Images = $images; Raw = $raw }
}

function New-DiskPartScript_UEFI {
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [int]$EfiSizeMB = 260,
        [switch]$RecoveryPartition,
        [int]$RecoverySizeMB = 1024,
        [switch]$AssignDriveLetters
    )

    $lines = @()
    $lines += "select disk $DiskNumber"
    $lines += "clean"
    $lines += "convert gpt"
    $lines += "create partition efi size=$EfiSizeMB"
    $lines += "format quick fs=fat32 label=System"
    if ($AssignDriveLetters) { $lines += "assign letter=S" }
    $lines += "create partition msr size=16"
    $lines += "create partition primary"
    $lines += "format quick fs=ntfs label=Windows"
    if ($AssignDriveLetters) { $lines += "assign letter=W" }

    if ($RecoveryPartition) {
        $lines += "select partition 3"
        $lines += "shrink desired=$RecoverySizeMB minimum=$RecoverySizeMB"
        $lines += "create partition primary"
        $lines += "format quick fs=ntfs label=Recovery"
        $lines += "set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac"
        $lines += "gpt attributes=0x8000000000000001"
    }

    return ($lines -join "`r`n")
}

function New-DiskPartScript_BIOS {
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [int]$SystemReservedMB = 500,
        [switch]$RecoveryPartition,
        [int]$RecoverySizeMB = 1024,
        [switch]$AssignDriveLetters
    )

    $lines = @()
    $lines += "select disk $DiskNumber"
    $lines += "clean"
    $lines += "convert mbr"
    $lines += "create partition primary size=$SystemReservedMB"
    $lines += "format quick fs=ntfs label=System"
    if ($AssignDriveLetters) { $lines += "assign letter=S" }
    $lines += "active"
    $lines += "create partition primary"
    $lines += "format quick fs=ntfs label=Windows"
    if ($AssignDriveLetters) { $lines += "assign letter=W" }

    if ($RecoveryPartition) {
        $lines += "select partition 2"
        $lines += "shrink desired=$RecoverySizeMB minimum=$RecoverySizeMB"
        $lines += "create partition primary"
        $lines += "format quick fs=ntfs label=Recovery"
        $lines += "set id=27"
    }

    return ($lines -join "`r`n")
}

function Invoke-DiskPartScript {
    param([Parameter(Mandatory)][string]$ScriptText)
    Write-Log "Running diskpart (live)"
    Write-Progress-Status -Percent 10 -Status "Partitioning disk..."
    Invoke-DiskPartLive -ScriptText $ScriptText -LogName "partition" | Out-Null
    Write-Progress-Status -Percent 20 -Status "Disk partitioned successfully"
}

function Ensure-DriveLetters {
    param([switch]$UEFI)

    $retries = 10
    $success = $false
    
    while ($retries -gt 0 -and -not $success) {
        $wExists = Test-Path -LiteralPath "W:\"
        $sExists = Test-Path -LiteralPath "S:\"
        
        if ($wExists -and $sExists) {
            $success = $true
            break
        }
        
        Start-Sleep -Milliseconds 500
        $retries--
    }
    
    if (-not (Test-Path -LiteralPath "W:\")) { 
        throw "Windows target drive letter W: not found after partitioning. Enable 'AssignDriveLetters' or check for drive letter conflicts." 
    }
    if (-not (Test-Path -LiteralPath "S:\")) { 
        throw "System/EFI drive letter S: not found after partitioning. Enable 'AssignDriveLetters' or check for drive letter conflicts." 
    }
    
    Write-Log "Drive letters W: and S: validated successfully."
}

function Apply-WindowsImage {
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$ApplyDir,
        [switch]$Compact
    )

    Write-Log ("Applying image Index={0} from {1} to {2}{3}" -f $Index, $ImagePath, $ApplyDir, $(if ($Compact) { " (Compact)" } else { "" }))
    Write-Progress-Status -Percent 25 -Status "Applying Windows image..."

    $args = @("/English","/Apply-Image","/ImageFile:`"$ImagePath`"","/Index:$Index","/ApplyDir:`"$ApplyDir`"")
    if ($Compact) { $args += "/Compact" }

    Invoke-LiveProcess -FilePath "dism.exe" -Arguments ($args -join " ") | Out-Null
    Write-Progress-Status -Percent 50 -Status "Windows image applied successfully"
}

function Inject-Drivers {
    param([string]$DriverFolder, [string]$WindowsDir = "W:\")

    if ([string]::IsNullOrWhiteSpace($DriverFolder)) { return }
    if (-not (Test-Path -LiteralPath $DriverFolder)) { throw "Driver folder not found: $DriverFolder" }

    Write-Log "Injecting drivers from: $DriverFolder"
    Write-Progress-Status -Percent 55 -Status "Injecting drivers..."
    Invoke-LiveProcess -FilePath "dism.exe" -Arguments ("/English /Image:`"$WindowsDir`" /Add-Driver /Driver:`"$DriverFolder`" /Recurse") | Out-Null
    Write-Progress-Status -Percent 65 -Status "Drivers injected successfully"
}

function Inject-Updates {
    param([string]$UpdatesFolder, [string]$WindowsDir = "W:\")

    if ([string]::IsNullOrWhiteSpace($UpdatesFolder)) { return }
    if (-not (Test-Path -LiteralPath $UpdatesFolder)) { throw "Updates folder not found: $UpdatesFolder" }

    Write-Progress-Status -Percent 70 -Status "Injecting updates..."
    
    $all = Get-ChildItem -LiteralPath $UpdatesFolder -Recurse -File -ErrorAction SilentlyContinue
    $cabs = @($all | Where-Object { $_.Extension -ieq ".cab" })
    $msus = @($all | Where-Object { $_.Extension -ieq ".msu" })

    $totalUpdates = $cabs.Count + $msus.Count
    $currentUpdate = 0

    foreach ($cab in $cabs) {
        $currentUpdate++
        Write-Log "Adding CAB package ($currentUpdate/$totalUpdates): $($cab.Name)"
        Write-Progress-Status -Percent (70 + ($currentUpdate / $totalUpdates * 10)) -Status "Installing update $currentUpdate of $totalUpdates"
        Invoke-LiveProcess -FilePath "dism.exe" -Arguments ("/English /Image:`"$WindowsDir`" /Add-Package /PackagePath:`"$($cab.FullName)`"") | Out-Null
    }

    foreach ($msu in $msus) {
        $currentUpdate++
        Write-Log "Expanding MSU ($currentUpdate/$totalUpdates): $($msu.Name)"
        Write-Progress-Status -Percent (70 + ($currentUpdate / $totalUpdates * 10)) -Status "Installing update $currentUpdate of $totalUpdates"
        
        $tmp = Join-Path $env:TEMP ("msu-{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        try {
            Invoke-LiveProcess -FilePath "expand.exe" -Arguments ("-F:* `"$($msu.FullName)`" `"$tmp`"") | Out-Null

            $innerCabs = Get-ChildItem -LiteralPath $tmp -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ieq ".cab" }
            foreach ($cab in $innerCabs) {
                Write-Log "Adding CAB from MSU: $($cab.Name)"
                Invoke-LiveProcess -FilePath "dism.exe" -Arguments ("/English /Image:`"$WindowsDir`" /Add-Package /PackagePath:`"$($cab.FullName)`"") | Out-Null
            }
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Progress-Status -Percent 80 -Status "Updates installed successfully"
}

function Enable-NetFx3Offline {
    param([string]$WindowsDir="W:\", [string]$SxsSource)

    if ([string]::IsNullOrWhiteSpace($SxsSource)) { throw "SxS source not provided. Provide SxsSourcePath or use ISO source." }
    if (-not (Test-Path -LiteralPath $SxsSource)) { throw "SxS source not found: $SxsSource" }

    Write-Log "Enabling NetFx3 using source: $SxsSource"
    Write-Progress-Status -Percent 82 -Status "Enabling .NET Framework 3.5..."
    Invoke-LiveProcess -FilePath "dism.exe" -Arguments ("/English /Image:`"$WindowsDir`" /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:`"$SxsSource`"") | Out-Null
    Write-Progress-Status -Percent 85 -Status ".NET Framework 3.5 enabled"
}

function Write-UnattendXml {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ComputerName,
        [string]$LocalAdminUser,
        [string]$LocalAdminPassword,
        [string]$TimeZone = "UTC"
    )

    # FIXED: Corrected XML tag from <n> to <Name>
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$ComputerName</ComputerName>
      <TimeZone>$TimeZone</TimeZone>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <Name>$LocalAdminUser</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>$LocalAdminPassword</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
    </component>
  </settings>
</unattend>
"@
    Set-Content -LiteralPath $Path -Value $xml -Encoding UTF8
}

function Apply-OfflineTweaks {
    param([string]$WindowsDir="W:\")

    Write-Log "Applying offline tweaks"
    Write-Progress-Status -Percent 87 -Status "Applying offline registry tweaks..."
    
    $soft = Join-Path $WindowsDir "Windows\System32\config\SOFTWARE"
    if (-not (Test-Path -LiteralPath $soft)) { 
        Write-Log "SOFTWARE hive not found, skipping offline registry tweaks" "WARN"
        return 
    }

    $mount = "HKLM\OFFSOFT"
    Invoke-LiveProcess -FilePath "reg.exe" -Arguments ("load $mount `"$soft`"") | Out-Null
    
    try {
        # Disable Windows Consumer Features
        Invoke-LiveProcess -FilePath "reg.exe" -Arguments ("add `"$mount\Policies\Microsoft\Windows\CloudContent`" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f") | Out-Null
        Invoke-LiveProcess -FilePath "reg.exe" -Arguments ("add `"$mount\Policies\Microsoft\Windows\CloudContent`" /v DisableConsumerAccountStateContent /t REG_DWORD /d 1 /f") | Out-Null
        
        # Disable Windows Spotlight
        Invoke-LiveProcess -FilePath "reg.exe" -Arguments ("add `"$mount\Policies\Microsoft\Windows\CloudContent`" /v DisableWindowsSpotlightFeatures /t REG_DWORD /d 1 /f") | Out-Null
        
        Write-Log "Offline tweaks applied successfully"
    } 
    catch {
        Write-Log "Error applying offline tweaks: $($_.Exception.Message)" "WARN"
    }
    finally {
        Invoke-LiveProcess -FilePath "reg.exe" -Arguments ("unload $mount") -IgnoreExitCode | Out-Null
    }
    
    Write-Progress-Status -Percent 90 -Status "Offline tweaks applied"
}

function Create-BootFiles {
    param([Parameter(Mandatory)][ValidateSet("UEFI","BIOS","ALL")][string]$FirmwareType)

    Write-Log "Creating boot files (bcdboot) FirmwareType=$FirmwareType"
    Write-Progress-Status -Percent 92 -Status "Creating boot files..."
    
    Invoke-LiveProcess -FilePath "bcdboot.exe" -Arguments ("`"W:\Windows`" /s S: /f $FirmwareType") | Out-Null
    
    Write-Progress-Status -Percent 95 -Status "Boot files created successfully"
}

function Verify-Deployment {
    param([switch]$UEFI)

    Write-Log "Verifying deployment"
    Write-Progress-Status -Percent 97 -Status "Verifying deployment..."
    
    if (-not (Test-Path -LiteralPath "W:\Windows\System32")) { 
        throw "Windows folder missing under W:\Windows\System32. Apply may have failed." 
    }

    if ($UEFI) {
        if (-not (Test-Path -LiteralPath "S:\EFI")) { 
            Write-Log "EFI folder not found on S: (check bcdboot output)" "WARN" 
        } else {
            Write-Log "EFI boot files verified"
        }
    } else {
        if (-not (Test-Path -LiteralPath "S:\Boot")) { 
            Write-Log "Boot folder not found on S: (check bcdboot output)" "WARN" 
        } else {
            Write-Log "BIOS boot files verified"
        }
    }
    
    # Additional verification checks
    if (Test-Path -LiteralPath "W:\Windows\System32\config\SOFTWARE") {
        Write-Log "Windows registry hives verified"
    }
    
    if (Test-Path -LiteralPath "W:\Windows\System32\winload.exe") {
        Write-Log "Windows boot loader verified"
    }
    
    Write-Progress-Status -Percent 100 -Status "Verification complete"
}

function Cleanup-OnFailure {
    param([string]$MountedIso)
    
    Write-Log "Cleaning up after failure..." "WARN"
    
    # Attempt to unload any mounted registry hives
    try {
        Invoke-LiveProcess -FilePath "reg.exe" -Arguments ("unload HKLM\OFFSOFT") -IgnoreExitCode | Out-Null
    } catch {}
    
    # Unmount ISO if provided
    if ($MountedIso -and (Test-Path -LiteralPath $MountedIso)) {
        try {
            Write-Log "Unmounting ISO: $MountedIso"
            Dismount-DiskImage -ImagePath $MountedIso -ErrorAction SilentlyContinue
        } catch {}
    }
}
