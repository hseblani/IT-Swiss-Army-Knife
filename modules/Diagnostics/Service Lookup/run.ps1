# Service Lookup

param(
    [string]$UsageInfo = "",
    [string]$Query = "windows update"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-Progress-Status { param([int]$Percent, [string]$Status) Write-Output "[PROGRESS:$Percent] $Status" }

Write-Output "========================================="
Write-Output "SERVICE LOOKUP"
Write-Output "========================================="
Write-Output ""
Write-Output "Search Query: $Query"
Write-Output ""

if ([string]::IsNullOrWhiteSpace($Query)) {
    Write-Output "ERROR: Please enter a search query."
    exit 1
}

Write-Progress-Status -Percent 20 -Status "Searching for services..."

# Search services by name and display name
try {
    $services = Get-Service | Where-Object { 
        $_.Name -like "*$Query*" -or 
        $_.DisplayName -like "*$Query*" 
    } | Sort-Object DisplayName
    
    if ($services.Count -eq 0) {
        Write-Output "No services found matching '$Query'"
        Write-Output ""
        Write-Output "Try:"
        Write-Output "  - Using partial names (e.g., 'update' instead of 'windows update')"
        Write-Output "  - Checking spelling"
        Write-Output "  - Using wildcards (e.g., 'win*')"
        exit 0
    }
    
    Write-Output "Found $($services.Count) matching service(s):"
    Write-Output ""
    
    Write-Progress-Status -Percent 60 -Status "Retrieving service details..."
    
    foreach ($service in $services) {
        # Get additional details from WMI
        $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue
        
        Write-Output "========================================="
        Write-Output "Service: $($service.DisplayName)"
        Write-Output "========================================="
        Write-Output "Name             : $($service.Name)"
        Write-Output "Status           : $($service.Status)"
        Write-Output "Startup Type     : $($service.StartType)"
        
        if ($wmiService) {
            Write-Output "Path             : $($wmiService.PathName)"
            Write-Output "Start Name       : $($wmiService.StartName)"
            Write-Output "Description      : $($wmiService.Description)"
            
            if ($wmiService.State -eq "Running") {
                Write-Output "Process ID       : $($wmiService.ProcessId)"
            }
        }
        
        # Status indicator
        $statusIndicator = switch ($service.Status) {
            "Running" { "[RUNNING]" }
            "Stopped" { "[STOPPED]" }
            "Paused" { "[PAUSED]" }
            default { "[$($service.Status.ToUpper())]" }
        }
        Write-Output "Current State    : $statusIndicator"
        Write-Output ""
    }
    
    Write-Progress-Status -Percent 90 -Status "Generating summary..."
    
    # Summary
    Write-Output "========================================="
    Write-Output "SUMMARY"
    Write-Output "========================================="
    Write-Output "Total Services   : $($services.Count)"
    Write-Output "Running          : $(($services | Where-Object { $_.Status -eq 'Running' }).Count)"
    Write-Output "Stopped          : $(($services | Where-Object { $_.Status -eq 'Stopped' }).Count)"
    Write-Output ""
    
    # Startup type breakdown
    $auto = @($services | Where-Object { $_.StartType -eq 'Automatic' }).Count
    $manual = @($services | Where-Object { $_.StartType -eq 'Manual' }).Count
    $disabled = @($services | Where-Object { $_.StartType -eq 'Disabled' }).Count
    
    Write-Output "Startup Types:"
    Write-Output "  Automatic      : $auto"
    Write-Output "  Manual         : $manual"
    Write-Output "  Disabled       : $disabled"
    Write-Output ""
    
    Write-Progress-Status -Percent 100 -Status "Complete"
    Write-Output "Service lookup completed."
    
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
