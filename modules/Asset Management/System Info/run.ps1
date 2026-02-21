# System Information Display
param(
    [string]$InfoNote = ""
)

# Shared helpers (includes Write-ToolkitProgress)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Output "========================================="
Write-Output "SYSTEM INFORMATION"
Write-Output "========================================="
Write-Output ""

if (-not [string]::IsNullOrWhiteSpace($InfoNote)) {
    Write-Output "NOTE: $InfoNote"
    Write-Output ""
}

function Safe-GetCim {
    param(
        [Parameter(Mandatory)]
        [string]$ClassName
    )
    try { Get-CimInstance -ClassName $ClassName -ErrorAction Stop } catch { $null }
}

function Safe-GetCommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -lt 1KB) { return "{0:N0} B" -f $Bytes }
    if ($Bytes -lt 1MB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -lt 1TB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    return "{0:N2} TB" -f ($Bytes / 1TB)
}

try {
    Write-ToolkitProgress -Percent 10 -Status "Gathering OS information..."

    $os = Safe-GetCim -ClassName "Win32_OperatingSystem"
    $cs = Safe-GetCim -ClassName "Win32_ComputerSystem"
    $cpu = Safe-GetCim -ClassName "Win32_Processor" | Select-Object -First 1

    Write-Output "COMPUTER / OS"
    Write-Output "============="
    if ($cs) {
        Write-Output ("Computer Name    : {0}" -f $env:COMPUTERNAME)
        Write-Output ("Manufacturer     : {0}" -f $cs.Manufacturer)
        Write-Output ("Model            : {0}" -f $cs.Model)
        Write-Output ("Domain/Workgroup : {0}" -f ($cs.Domain))
    }
    else {
        Write-Output ("Computer Name    : {0}" -f $env:COMPUTERNAME)
    }

    if ($os) {
        Write-Output ("OS               : {0}" -f $os.Caption)
        Write-Output ("Version          : {0}" -f $os.Version)
        Write-Output ("Build            : {0}" -f $os.BuildNumber)
        Write-Output ("Install Date     : {0}" -f $os.InstallDate)
        Write-Output ("Last Boot        : {0}" -f $os.LastBootUpTime)
    }
    Write-Output ""

    Write-ToolkitProgress -Percent 30 -Status "Gathering OS details..."

    Write-Output "OS DETAILS"
    Write-Output "=========="
    Write-Output ("User             : {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    Write-Output ("PowerShell       : {0}" -f $PSVersionTable.PSVersion)
    if ($os) {
        $freeMem = [double]$os.FreePhysicalMemory * 1KB
        $totalMem = [double]$os.TotalVisibleMemorySize * 1KB
        Write-Output ("RAM (OS view)     : {0} total / {1} free" -f (Format-Bytes $totalMem), (Format-Bytes $freeMem))
    }
    Write-Output ""

    Write-ToolkitProgress -Percent 50 -Status "Gathering hardware information..."

    $ramModules = Safe-GetCim -ClassName "Win32_PhysicalMemory"
    $ramTotal = 0
    if ($ramModules) {
        $ramTotal = ($ramModules | Measure-Object -Property Capacity -Sum).Sum
    }
    elseif ($cs) {
        $ramTotal = $cs.TotalPhysicalMemory
    }

    Write-Output "HARDWARE"
    Write-Output "========"
    if ($cpu) {
        Write-Output ("CPU              : {0}" -f $cpu.Name)
        Write-Output ("Cores / Threads  : {0} / {1}" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    }
    if ($ramTotal -gt 0) {
        Write-Output ("RAM              : {0}" -f (Format-Bytes $ramTotal))
    }
    Write-Output ""

    Write-ToolkitProgress -Percent 70 -Status "Gathering disk information..."

    Write-Output "STORAGE"
    Write-Output "======="

    $printedSomething = $false

    if (Safe-GetCommandExists -Name "Get-Disk") {
        $disks = Get-Disk | Sort-Object Number
        foreach ($d in $disks) {
            $printedSomething = $true
            $size = if ($d.Size) { Format-Bytes $d.Size } else { "N/A" }
            Write-Output ("Disk {0}          : {1} ({2})" -f $d.Number, $d.FriendlyName, $size)
            Write-Output ("  BusType         : {0}" -f $d.BusType)
            Write-Output ("  PartitionStyle  : {0}" -f $d.PartitionStyle)
            Write-Output ("  HealthStatus    : {0}" -f $d.HealthStatus)
        }
        if ($printedSomething) { Write-Output "" }
    }

    if (Safe-GetCommandExists -Name "Get-Volume") {
        $vols = Get-Volume | Sort-Object DriveLetter
        foreach ($v in $vols) {
            if ([string]::IsNullOrWhiteSpace($v.DriveLetter)) { continue }
            $printedSomething = $true
            $total = if ($v.Size) { Format-Bytes $v.Size } else { "N/A" }
            $free = if ($v.SizeRemaining) { Format-Bytes $v.SizeRemaining } else { "N/A" }
            Write-Output ("{0}:  {1}  {2} total / {3} free  ({4})" -f $v.DriveLetter, $v.FileSystemLabel, $total, $free, $v.FileSystem)
        }
        if ($printedSomething) { Write-Output "" }
    }

    if (-not $printedSomething) {
        Write-Output "Storage cmdlets not available on this system."
        Write-Output ""
    }

    Write-ToolkitProgress -Percent 90 -Status "Gathering BIOS information..."

    $bios = Safe-GetCim -ClassName "Win32_BIOS"

    Write-Output "BIOS/FIRMWARE"
    Write-Output "============="
    if ($bios) {
        Write-Output ("Manufacturer     : {0}" -f $bios.Manufacturer)
        Write-Output ("Version          : {0}" -f $bios.SMBIOSBIOSVersion)
        Write-Output ("Release Date     : {0}" -f $bios.ReleaseDate)
        if ($bios.SerialNumber) {
            Write-Output ("Serial Number    : {0}" -f $bios.SerialNumber)
        }
    }
    else {
        Write-Output "BIOS information unavailable."
    }
    Write-Output ""

    Write-ToolkitProgress -Percent 100 -Status "Complete"

    Write-Output "========================================="
    Write-Output "System information gathered successfully."
    Write-Output "========================================="
}
catch {
    # Keep module behavior consistent: show error and rethrow so runner can handle state
    Write-Output ""
    Write-Output "========================================="
    Write-Output "ERROR: Failed to gather system information."
    Write-Output "========================================="
    Write-Output $_.Exception.Message
    throw
}
