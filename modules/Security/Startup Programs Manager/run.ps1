# Startup Programs Manager

param(
    [ValidateSet("ViewAll", "ViewEnabled", "ViewDisabled", "DisableByName", "EnableByName", "ExportList")]
    [string]$Action = "ViewAll",

    [string]$ItemName = "",

    [string]$IncludeServices = "false",
    [string]$IncludeTaskScheduler = "true",
    [string]$ShowDetails = "false",

    # IMPORTANT: this is a FOLDER path (picked via Browse). The script will generate the CSV filename.
    # The UI may pass "__MODULE_OUTPUT__" literally. We handle that.
    [string]$ExportPath = "",

    [ValidateSet("Name", "Status", "Location", "Impact")]
    [string]$SortBy = "Name"
)

# Shared helpers (includes Write-ToolkitProgress)
.(Join-Path $PSScriptRoot "..\..\_shared\common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# -------------------- Admin check --------------------
function Assert-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This module must be run as Administrator to manage startup programs (registry, services, scheduled tasks)."
        return $false
    }
    return $true
}

if (-not (Assert-Administrator)) { return }

function Get-StartupImpact {
    param([string]$Name, [string]$Path)

    $highImpact = @('Adobe', 'iTunes', 'Skype', 'Steam', 'Origin', 'Discord', 'Zoom')
    $mediumImpact = @('OneDrive', 'Dropbox', 'Google', 'Microsoft', 'Update')

    foreach ($high in $highImpact) {
        if ($Name -like "*$high*" -or $Path -like "*$high*") { return "High" }
    }
    foreach ($medium in $mediumImpact) {
        if ($Name -like "*$medium*" -or $Path -like "*$medium*") { return "Medium" }
    }
    return "Low"
}

function Get-RegistryStartupItems {
    $items = @()

    $regPaths = @(
        @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "All Users"; Hive = "HKLM" }
        @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"; Scope = "All Users"; Hive = "HKLM" }
        @{Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Scope = "All Users (32-bit)"; Hive = "HKLM" }
        @{Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Scope = "Current User"; Hive = "HKCU" }
        @{Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"; Scope = "Current User"; Hive = "HKCU" }
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath.Path) {
            $props = Get-ItemProperty -Path $regPath.Path -ErrorAction SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                    $items += [PSCustomObject]@{
                        Name     = $_.Name
                        Command  = $_.Value
                        Location = "Registry"
                        Path     = $regPath.Path
                        Scope    = $regPath.Scope
                        Enabled  = $true
                        Type     = "Registry"
                        Impact   = Get-StartupImpact -Name $_.Name -Path $_.Value
                    }
                }
            }
        }
    }

    return $items
}

function Get-StartupFolderItems {
    $items = @()

    $folders = @(
        @{Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; Scope = "All Users" }
        @{Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Scope = "Current User" }
    )

    foreach ($folder in $folders) {
        if (Test-Path $folder.Path) {
            $shortcuts = Get-ChildItem -Path $folder.Path -Filter *.lnk -ErrorAction SilentlyContinue
            foreach ($shortcut in $shortcuts) {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $link = $shell.CreateShortcut($shortcut.FullName)

                    $items += [PSCustomObject]@{
                        Name     = $shortcut.BaseName
                        Command  = $link.TargetPath
                        Location = "Startup Folder"
                        Path     = $shortcut.FullName
                        Scope    = $folder.Scope
                        Enabled  = $true
                        Type     = "Shortcut"
                        Impact   = Get-StartupImpact -Name $shortcut.BaseName -Path $link.TargetPath
                    }
                }
                catch {
                    # Ignore errors reading shortcuts
                }
            }
        }
    }

    return $items
}

function Get-ScheduledTaskStartupItems {
    $items = @()

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq 'Ready' -and
                $_.Triggers.Count -gt 0 -and
                ($_.Triggers.CimClass.CimClassName -contains 'MSFT_TaskLogonTrigger' -or
                $_.Triggers.CimClass.CimClassName -contains 'MSFT_TaskBootTrigger')
            })

        foreach ($task in $tasks) {
            try {
                $action = $task.Actions | Select-Object -First 1

                $items += [PSCustomObject]@{
                    Name     = $task.TaskName
                    Command  = if ($action.Execute) { $action.Execute } else { "N/A" }
                    Location = "Task Scheduler"
                    Path     = $task.TaskPath
                    Scope    = "System"
                    Enabled  = ($task.State -eq 'Ready')
                    Type     = "Scheduled Task"
                    Impact   = Get-StartupImpact -Name $task.TaskName -Path $action.Execute
                }
            }
            catch {
                continue
            }
        }
    }
    catch {
        # Ignore if Task Scheduler not accessible
    }

    return $items
}

function Get-ServiceStartupItems {
    $items = @()

    try {
        $services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.StartType -eq 'Automatic' }

        foreach ($service in $services) {
            $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue

            $items += [PSCustomObject]@{
                Name     = $service.DisplayName
                Command  = if ($wmiService) { $wmiService.PathName } else { "N/A" }
                Location = "Service"
                Path     = "Services.msc"
                Scope    = "System"
                Enabled  = ($service.StartType -eq 'Automatic')
                Type     = "Service"
                Impact   = Get-StartupImpact -Name $service.DisplayName -Path $wmiService.PathName
            }
        }
    }
    catch {
        # Ignore if services not accessible
    }

    return $items
}

function Get-AllStartupItems {
    $includeServices = ($IncludeServices -eq "true")
    $includeTaskScheduler = ($IncludeTaskScheduler -eq "true")

    Write-ToolkitProgress -Percent 10 -Status "Scanning registry..."
    $allItems = @(Get-RegistryStartupItems)

    Write-ToolkitProgress -Percent 30 -Status "Scanning startup folders..."
    $allItems += @(Get-StartupFolderItems)

    if ($includeTaskScheduler) {
        Write-ToolkitProgress -Percent 50 -Status "Scanning scheduled tasks..."
        $allItems += @(Get-ScheduledTaskStartupItems)
    }

    if ($includeServices) {
        Write-ToolkitProgress -Percent 70 -Status "Scanning services..."
        $allItems += @(Get-ServiceStartupItems)
    }

    Write-ToolkitProgress -Percent 90 -Status "Processing results..."

    # Filter out malformed items
    $allItems = @($allItems | Where-Object { $null -ne $_.PSObject.Properties['Enabled'] })

    return $allItems
}

function Disable-StartupItem {
    param([PSCustomObject]$Item)

    try {
        switch ($Item.Type) {
            "Registry" {
                $regPath = $Item.Path
                $valueName = $Item.Name

                if (Test-Path $regPath) {
                    $props = Get-ItemProperty -Path $regPath
                    if ($props.PSObject.Properties.Name -contains $valueName) {
                        $backupName = "$valueName.disabled"
                        Remove-ItemProperty -Path $regPath -Name $backupName -ErrorAction SilentlyContinue
                        Rename-ItemProperty -Path $regPath -Name $valueName -NewName $backupName -ErrorAction Stop
                        return $true
                    }
                }
            }
            "Shortcut" {
                if (Test-Path $Item.Path) {
                    $newPath = $Item.Path -replace '\.lnk$', '.lnk.disabled'
                    Rename-Item -Path $Item.Path -NewName ([System.IO.Path]::GetFileName($newPath)) -ErrorAction Stop
                    return $true
                }
            }
            "Scheduled Task" {
                Disable-ScheduledTask -TaskName $Item.Name -ErrorAction Stop | Out-Null
                return $true
            }
            "Service" {
                # Note: current code uses display name as Item.Name; Set-Service expects service name.
                # Keeping your original behavior as-is.
                Set-Service -Name $Item.Name -StartupType Manual -ErrorAction Stop
                return $true
            }
        }
    }
    catch {
        Write-Output "  Error disabling $($Item.Name): $($_.Exception.Message)"
        return $false
    }

    return $false
}

function Enable-StartupItem {
    param([PSCustomObject]$Item)

    try {
        switch ($Item.Type) {
            "Registry" {
                $regPath = $Item.Path
                $valueName = $Item.Name
                $disabledName = "$valueName.disabled"

                if (Test-Path $regPath) {
                    $props = Get-ItemProperty -Path $regPath
                    if ($props.PSObject.Properties.Name -contains $disabledName) {
                        Rename-ItemProperty -Path $regPath -Name $disabledName -NewName $valueName -ErrorAction Stop
                        return $true
                    }
                }
            }
            "Shortcut" {
                $disabledPath = $Item.Path + ".disabled"
                if (Test-Path $disabledPath) {
                    $newName = [System.IO.Path]::GetFileName($Item.Path)
                    Rename-Item -Path $disabledPath -NewName $newName -ErrorAction Stop
                    return $true
                }
            }
            "Scheduled Task" {
                Enable-ScheduledTask -TaskName $Item.Name -ErrorAction Stop | Out-Null
                return $true
            }
            "Service" {
                # Note: current code uses display name as Item.Name; Set-Service expects service name.
                # Keeping your original behavior as-is.
                Set-Service -Name $Item.Name -StartupType Automatic -ErrorAction Stop
                return $true
            }
        }
    }
    catch {
        Write-Output "  Error enabling $($Item.Name): $($_.Exception.Message)"
        return $false
    }

    return $false
}

function Test-FolderWritable {
    param([Parameter(Mandatory)][string]$Folder)

    try {
        if (-not (Test-Path -LiteralPath $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }

        $testFile = Join-Path $Folder ("write-test-{0}.tmp" -f ([guid]::NewGuid().ToString("N")))
        "test" | Set-Content -Path $testFile -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}
function Get-ModuleOutputFolder {
    # Under StrictMode, touching an unset variable throws.
    # So check if the variable exists first.
    $var = Get-Variable -Name "ModuleOutputPath" -Scope Script -ErrorAction SilentlyContinue

    if ($var -and $var.Value -and -not [string]::IsNullOrWhiteSpace([string]$var.Value)) {
        return [string]$var.Value
    }

    # Fallback: module folder (usually writable in your toolkit layout)
    $fallback = Join-Path $PSScriptRoot "output"
    if (-not (Test-Path -LiteralPath $fallback)) {
        New-Item -ItemType Directory -Path $fallback -Force | Out-Null
    }

    # If even that is not writable, fallback to TEMP
    if (-not (Test-FolderWritable -Folder $fallback)) {
        $fallback = Join-Path $env:TEMP "IT-Toolkit-Exports"
        if (-not (Test-Path -LiteralPath $fallback)) {
            New-Item -ItemType Directory -Path $fallback -Force | Out-Null
        }
    }

    return $fallback
}

function Resolve-ExportFolder {
    param([string]$Folder)

    $moduleOut = Get-ModuleOutputFolder

    # Handle placeholder and empty value
    if ([string]::IsNullOrWhiteSpace($Folder) -or $Folder -eq "__MODULE_OUTPUT__") {
        return $moduleOut
    }

    # If chosen folder isn't writable, fallback
    if (-not (Test-FolderWritable -Folder $Folder)) {
        Write-Output ("[WARN] Selected export folder is not writable: {0}" -f $Folder)
        Write-Output ("[WARN] Falling back to: {0}" -f $moduleOut)
        return $moduleOut
    }

    return $Folder
}


# -------------------- Main execution --------------------
Write-Output "========================================="
Write-Output "STARTUP PROGRAMS MANAGER"
Write-Output "========================================="
Write-Output ""

$showDetails = ($ShowDetails -eq "true")

switch ($Action) {

    "ViewAll" {
        Write-ToolkitProgress -Percent 5 -Status "Starting..."
        $items = Get-AllStartupItems

        Write-Output "Total startup items: $($items.Count)"
        Write-Output ""

        switch ($SortBy) {
            "Name" { $items = $items | Sort-Object Name }
            "Status" { $items = $items | Sort-Object @{Expression = "Enabled"; Descending = $true }, Name }
            "Location" { $items = $items | Sort-Object Location, Name }
            "Impact" { $items = $items | Sort-Object @{Expression = "Impact"; Descending = $true }, Name }
        }

        if ($showDetails) {
            $items | Format-Table Name, Enabled, Location, Impact, Command, Scope -AutoSize | Out-String | Write-Output
        }
        else {
            $items | Format-Table Name, Enabled, Location, Impact, Scope -AutoSize | Out-String | Write-Output
        }

        $enabledItems = @($items | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $true })
        $enabled = $enabledItems.Count
        $disabled = $items.Count - $enabled

        Write-Output ""
        Write-Output "Summary:"
        Write-Output "  Enabled: $enabled"
        Write-Output "  Disabled: $disabled"
        Write-Output "  High Impact: $(@($items | Where-Object { $_.PSObject.Properties['Impact'] -and $_.Impact -eq 'High' }).Count)"
        Write-Output "  Medium Impact: $(@($items | Where-Object { $_.PSObject.Properties['Impact'] -and $_.Impact -eq 'Medium' }).Count)"
        Write-Output "  Low Impact: $(@($items | Where-Object { $_.PSObject.Properties['Impact'] -and $_.Impact -eq 'Low' }).Count)"

        Write-ToolkitProgress -Percent 100 -Status "Complete"
    }

    "ViewEnabled" {
        Write-ToolkitProgress -Percent 5 -Status "Starting..."
        $items = @(Get-AllStartupItems | Where-Object { $_.Enabled -eq $true })

        Write-Output "Enabled startup items: $($items.Count)"
        Write-Output ""

        if ($showDetails) {
            $items | Sort-Object Name | Format-Table Name, Location, Impact, Command -AutoSize | Out-String | Write-Output
        }
        else {
            $items | Sort-Object Name | Format-Table Name, Location, Impact, Scope -AutoSize | Out-String | Write-Output
        }

        Write-ToolkitProgress -Percent 100 -Status "Complete"
    }

    "ViewDisabled" {
        Write-ToolkitProgress -Percent 5 -Status "Starting..."
        $items = @(Get-AllStartupItems | Where-Object { $_.Enabled -ne $true })

        Write-Output "Disabled startup items: $($items.Count)"
        Write-Output ""

        if ($showDetails) {
            $items | Sort-Object Name | Format-Table Name, Location, Impact, Command -AutoSize | Out-String | Write-Output
        }
        else {
            $items | Sort-Object Name | Format-Table Name, Location, Impact, Scope -AutoSize | Out-String | Write-Output
        }

        Write-ToolkitProgress -Percent 100 -Status "Complete"
    }

    "DisableByName" {
        Write-ToolkitProgress -Percent 5 -Status "Starting..."

        if ([string]::IsNullOrWhiteSpace($ItemName)) {
            Write-Output "ERROR: ItemName parameter is required for DisableByName action."
            Write-ToolkitProgress -Percent 100 -Status "Failed"
            exit 1
        }

        $items = @(Get-AllStartupItems | Where-Object { $_.Name -like "*$ItemName*" -and $_.Enabled -eq $true })

        if ($items.Count -eq 0) {
            Write-Output "No enabled startup items found matching '$ItemName'"
            Write-ToolkitProgress -Percent 100 -Status "Complete"
            exit 0
        }

        Write-Output "Found $($items.Count) matching items:"
        Write-Output ""

        $disabled = 0
        foreach ($item in $items) {
            Write-Output "Disabling: $($item.Name) ($($item.Location))"
            if (Disable-StartupItem -Item $item) {
                Write-Output "  [OK] Successfully disabled"
                $disabled++
            }
            else {
                Write-Output "  [ERROR] Failed to disable"
            }
        }

        Write-Output ""
        Write-Output "Disabled $disabled out of $($items.Count) items."

        Write-ToolkitProgress -Percent 100 -Status "Complete"
    }

    "EnableByName" {
        Write-ToolkitProgress -Percent 5 -Status "Starting..."

        if ([string]::IsNullOrWhiteSpace($ItemName)) {
            Write-Output "ERROR: ItemName parameter is required for EnableByName action."
            Write-ToolkitProgress -Percent 100 -Status "Failed"
            exit 1
        }

        $items = @(Get-AllStartupItems | Where-Object { $_.Name -like "*$ItemName*" -and $_.Enabled -ne $true })

        if ($items.Count -eq 0) {
            Write-Output "No disabled startup items found matching '$ItemName'"
            Write-ToolkitProgress -Percent 100 -Status "Complete"
            exit 0
        }

        Write-Output "Found $($items.Count) matching items:"
        Write-Output ""

        $enabled = 0
        foreach ($item in $items) {
            Write-Output "Enabling: $($item.Name) ($($item.Location))"
            if (Enable-StartupItem -Item $item) {
                Write-Output "  [OK] Successfully enabled"
                $enabled++
            }
            else {
                Write-Output "  [ERROR] Failed to enable"
            }
        }

        Write-Output ""
        Write-Output "Enabled $enabled out of $($items.Count) items."

        Write-ToolkitProgress -Percent 100 -Status "Complete"
    }

    "ExportList" {
        Write-ToolkitProgress -Percent 5 -Status "Starting..."

        $items = Get-AllStartupItems

        Write-ToolkitProgress -Percent 92 -Status "Preparing export..."

        # Resolve folder safely (folder picker)
        $exportFolder = Resolve-ExportFolder -Folder $ExportPath

        # Generate file name automatically
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $exportFile = Join-Path $exportFolder ("startup-list-{0}.csv" -f $timestamp)

        Write-ToolkitProgress -Percent 95 -Status "Exporting to CSV..."

        Write-Output "Exporting $($items.Count) startup items to:"
        Write-Output "  $exportFile"
        Write-Output ""

        $items | Export-Csv -Path $exportFile -NoTypeInformation -Encoding UTF8

        Write-Output "Export complete!"
        Write-Output ""
        Write-Output "You can open this file in Excel or any text editor."

        Write-ToolkitProgress -Percent 100 -Status "Complete"
    }
}

Write-Output ""
Write-Output "Operation completed."
