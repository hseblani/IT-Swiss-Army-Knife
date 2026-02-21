# User-Friendly Event Log Viewer

param(
    [ValidateSet("System", "Application", "Security", "Setup", "All")]
    [string]$LogName = "System",

    [ValidateSet("All", "Critical", "Error", "Warning", "Information")]
    [string]$EventLevel = "All",

    [int]$MaxEvents = 100,

    [ValidateSet("Last1Hour", "Last6Hours", "Last24Hours", "Last7Days", "Last30Days", "All")]
    [string]$TimeRange = "Last24Hours",

    [string]$EventID = "",
    [string]$SearchText = "",

    [ValidateSet("None", "CSV", "HTML", "JSON")]
    [string]$ExportFormat = "None",

    [string]$ExportPath = "",

    # Keep as string to stay compatible with toolkits that pass checkbox values as "true"/"false"
    [string]$GroupBySource = "false",
    [string]$ShowTopErrors = "true"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Write-Progress-Status {
    param([int]$Percent, [string]$Status)
    Write-Output "[PROGRESS:$Percent] $Status"
}

function Get-TimeRangeFilter {
    param([string]$Range)
    switch ($Range) {
        "Last1Hour" { (Get-Date).AddHours(-1) }
        "Last6Hours" { (Get-Date).AddHours(-6) }
        "Last24Hours" { (Get-Date).AddDays(-1) }
        "Last7Days" { (Get-Date).AddDays(-7) }
        "Last30Days" { (Get-Date).AddDays(-30) }
        "All" { $null }
        default { (Get-Date).AddDays(-1) }
    }
}

function Get-LevelPrefix {
    param([string]$Level)
    switch -Regex ($Level) {
        '^Critical$' { '[!!]' }
        '^Error$' { '[X ]' }
        '^Warning$' { '[! ]' }
        '^Information$' { '[ i]' }
        default { '[  ]' }
    }
}

function Format-EventMessage {
    param(
        [string]$Message,
        [int]$MaxLength = 120
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { return "" }

    $m = $Message -replace '\s+', ' '
    if ($m.Length -gt $MaxLength) {
        return $m.Substring(0, $MaxLength - 3) + "..."
    }
    return $m
}

function To-BoolString {
    param([object]$Value, [string]$Default = "false")
    if ($null -eq $Value) { return $Default }

    if ($Value -is [bool]) { return $Value.ToString().ToLower() }

    $s = ($Value.ToString()).Trim().ToLower()
    if ($s -in @("true", "false")) { return $s }
    if ($s -in @("1", "yes", "y", "on")) { return "true" }
    if ($s -in @("0", "no", "n", "off")) { return "false" }
    return $Default
}

function Export-Events {
    param(
        [array]$Events,
        [string]$Format,
        [string]$Path
    )

    if ($Format -eq "None") { return }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $Path = Join-Path $PWD ("EventLogExport-$stamp.$($Format.ToLower())")
    }

    switch ($Format) {
        "CSV" { $Events | Export-Csv -NoTypeInformation -Path $Path -Encoding UTF8 }
        "HTML" { $Events | ConvertTo-Html -Title "Event Log Export" | Out-File -FilePath $Path -Encoding UTF8 }
        "JSON" { $Events | ConvertTo-Json -Depth 6 | Out-File -FilePath $Path -Encoding UTF8 }
    }

    Write-Output ""
    Write-Output "Exported to: $Path"
}

try {
    # Normalize checkbox inputs
    $GroupBySource = To-BoolString $GroupBySource "false"
    $ShowTopErrors = To-BoolString $ShowTopErrors "true"

    Write-Output "========================================="
    Write-Output "EVENT LOG VIEWER"
    Write-Output "========================================="
    Write-Output ("Log: {0}" -f $LogName)
    Write-Output ("Level Filter: {0}" -f $EventLevel)
    Write-Output ("Time Range: {0}" -f $TimeRange)
    Write-Output ("Max Events: {0}" -f $MaxEvents)
    if (-not [string]::IsNullOrWhiteSpace($EventID)) { Write-Output ("EventID Filter: {0}" -f $EventID) }
    if (-not [string]::IsNullOrWhiteSpace($SearchText)) { Write-Output ("Search Text: {0}" -f $SearchText) }

    Write-Progress-Status 10 "Retrieving events from log..."
    Write-Output "Retrieving events..."

    $startTime = Get-TimeRangeFilter -Range $TimeRange

    if ($LogName -eq "All") {

        # Query common logs and merge, then take most recent $MaxEvents
        $logs = @("System", "Application", "Security", "Setup")

        $allEvents = @()
        foreach ($ln in $logs) {
            $fh = @{ LogName = $ln }
            if ($null -ne $startTime) { $fh.StartTime = $startTime }

            try {
                $allEvents += Get-WinEvent -FilterHashtable $fh -ErrorAction Stop
            } catch {
                # Security can fail without admin; ignore and continue
                Write-Output "[WARN] Could not read '$ln' log: $($_.Exception.Message)"
            }
        }

        # Sort newest first and clamp
        $raw = $allEvents | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents

    } else {

        $filter = @{ LogName = $LogName }
        if ($null -ne $startTime) { $filter.StartTime = $startTime }

        $raw = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop
    }


    # Apply level filter
    if ($EventLevel -ne "All") {
        $raw = $raw | Where-Object { $_.LevelDisplayName -eq $EventLevel }
    }

    # Apply EventID filter
    if (-not [string]::IsNullOrWhiteSpace($EventID)) {
        $idList = $EventID -split '[,; ]+' |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ }

        if ($idList.Count -gt 0) {
            $raw = $raw | Where-Object { $idList -contains $_.Id }
        }
    }

    # Apply search text (case-insensitive contains)
    if (-not [string]::IsNullOrWhiteSpace($SearchText)) {
        $st = $SearchText.Trim()
        $raw = $raw | Where-Object {
            $msg = ($_.Message -as [string])
            if ([string]::IsNullOrEmpty($msg)) { return $false }
            $msg.IndexOf($st, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    }

    $events = @($raw)

    Write-Progress-Status 50 ("Processing {0} events..." -f $events.Count)
    Write-Output ("Found {0} events" -f $events.Count)

    # TOP ISSUES
    if ($ShowTopErrors -eq "true") {
        Write-Output ""
        Write-Output "========================================="
        Write-Output "TOP ISSUES (Most Frequent)"
        Write-Output "========================================="

        # Use safe composite key so commas in ProviderName don't break parsing
        $top = $events |
        ForEach-Object {
            [PSCustomObject]@{
                Key     = "{0}||{1}||{2}" -f $_.LevelDisplayName, $_.Id, $_.ProviderName
                Level   = $_.LevelDisplayName
                EventID = $_.Id
                Source  = $_.ProviderName
                Message = $_.Message
            }
        } |
        Group-Object -Property Key |
        Sort-Object Count -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            $k = $_.Name -split '\|\|', 3
            $level = $k[0]
            $id = [int]$k[1]
            $src = $k[2]
            $sample = ($events | Where-Object { $_.LevelDisplayName -eq $level -and $_.Id -eq $id -and $_.ProviderName -eq $src } | Select-Object -First 1).Message

            $props = [ordered]@{
                Count            = $_.Count
                Level            = $level
                EventID          = $id
                Source           = $src
                'Sample Message' = Format-EventMessage -Message $sample -MaxLength 70
            }
            New-Object PSObject -Property $props
        }

        if ($top.Count -gt 0) {
            $top | Format-Table -AutoSize | Out-String | Write-Output
        } else {
            Write-Output "(No issues to summarize.)"
        }
    }

    Write-Progress-Status 70 "Formatting events..."
    Write-Output "========================================="
    Write-Output "EVENT DETAILS"
    Write-Output "========================================="

    if ($events.Count -eq 0) {
        Write-Output "(No events match the selected filters.)"
        Export-Events -Events @() -Format $ExportFormat -Path $ExportPath
        Write-Output ""
        Write-Output "Operation completed."
        exit 0
    }

    # Convert to display objects (ROBUST: avoids invalid property-name conversion edge cases)
    $displayEvents = @()
    foreach ($event in $events) {
        $prefix = Get-LevelPrefix -Level $event.LevelDisplayName

        $props = [ordered]@{
            Tag     = $prefix
            Time    = $event.TimeCreated.ToString("MM/dd HH:mm:ss")
            Level   = $event.LevelDisplayName
            EventID = $event.Id
            Source  = $event.ProviderName
            Message = Format-EventMessage -Message $event.Message -MaxLength 100
        }

        $displayEvents += New-Object PSObject -Property $props
    }

    $displayEvents |
    Format-Table Tag, Time, Level, EventID, Source, Message -AutoSize |
    Out-String | Write-Output

    # Statistics
    Write-Output ""
    Write-Output "========================================="
    Write-Output "STATISTICS"
    Write-Output "========================================="

    $byLevel = $events | Group-Object LevelDisplayName | Sort-Object Count -Descending
    foreach ($g in $byLevel) {
        Write-Output ("{0,-12} : {1}" -f $g.Name, $g.Count)
    }

    if ($GroupBySource -eq "true") {
        Write-Output ""
        Write-Output "-----------------------------------------"
        Write-Output "By Source"
        Write-Output "-----------------------------------------"
        $bySource = $events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 15
        foreach ($g in $bySource) {
            Write-Output ("{0,-35} : {1}" -f $g.Name, $g.Count)
        }
    }

    # Export (raw events simplified)
    $exportObjects = $events | ForEach-Object {
        $props = [ordered]@{
            TimeCreated = $_.TimeCreated
            Level       = $_.LevelDisplayName
            EventID     = $_.Id
            Source      = $_.ProviderName
            Message     = $_.Message
        }
        New-Object PSObject -Property $props
    }

    Export-Events -Events $exportObjects -Format $ExportFormat -Path $ExportPath

} catch {
    Write-Output ""
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "Common causes:"
    Write-Output "  - Log does not exist or is empty"
    Write-Output "  - Insufficient permissions (run as Administrator)"
    Write-Output "  - Time range has no events"
    exit 1
}

Write-Output ""
Write-Output "Operation completed."
