param(
    [Parameter()][string]$Action = "List All WiFi Profiles",
    [Parameter()][string]$ProfileName = "",
    [Parameter()][bool]$ExportToFile = $false
)

$ErrorActionPreference = "Continue"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "           WiFi PASSWORD VIEWER" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This module requires Administrator privileges!" -ForegroundColor Red
    Write-Host "WiFi passwords can only be viewed by administrators." -ForegroundColor Yellow
    return
}

Write-Host "Action: $Action" -ForegroundColor Yellow
Write-Host ""

# Initialize progress
Write-Host "PROGRESS:0" -ForegroundColor Magenta

# Function to get WiFi password
function Get-WiFiPassword {
    param([string]$ProfileName)
    
    try {
        $profileInfo = netsh wlan show profile name="$ProfileName" key=clear
        
        $password = $profileInfo | Select-String "Key Content\s+:\s+(.+)" | ForEach-Object {
            $_.Matches.Groups[1].Value.Trim()
        }
        
        if ($password) {
            return $password
        } else {
            return "No password (Open network)"
        }
    } catch {
        return "Unable to retrieve"
    }
}

switch -Wildcard ($Action) {
    
    "List All WiFi Profiles*" {
        Write-Host "Scanning for saved WiFi profiles..." -ForegroundColor Cyan
        Write-Host "PROGRESS:20" -ForegroundColor Magenta
        Write-Host ""
        
        # Get all WiFi profiles
        $profilesOutput = netsh wlan show profiles
        
        # Parse profile names
        $profiles = $profilesOutput | Select-String "All User Profile\s+:\s+(.+)" | ForEach-Object {
            $_.Matches.Groups[1].Value.Trim()
        }
        
        if (-not $profiles -or $profiles.Count -eq 0) {
            Write-Host "No WiFi profiles found on this system." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "This could mean:" -ForegroundColor DarkGray
            Write-Host "  - No WiFi adapter is present" -ForegroundColor DarkGray
            Write-Host "  - No WiFi networks have been saved" -ForegroundColor DarkGray
            return
        }
        
        Write-Host "Found $($profiles.Count) saved WiFi profile(s)" -ForegroundColor Green
        Write-Host ""
        Write-Host "PROGRESS:50" -ForegroundColor Magenta
        
        # Collect results
        $results = @()
        $current = 0
        
        Write-Host "Retrieving passwords..." -ForegroundColor Cyan
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host ""
        
        foreach ($profile in $profiles) {
            $current++
            $percent = [math]::Round((($current / $profiles.Count) * 50) + 50)
            Write-Host "PROGRESS:$percent" -ForegroundColor Magenta
            
            $password = Get-WiFiPassword -ProfileName $profile
            
            $results += [PSCustomObject]@{
                ProfileName = $profile
                Password    = $password
            }
            
            # Display inline
            $passwordDisplay = if ($password -eq "No password (Open network)") {
                $password
            } elseif ($password -eq "Unable to retrieve") {
                $password
            } else {
                $password
            }
            
            Write-Host "Network: " -NoNewline -ForegroundColor Cyan
            Write-Host $profile -ForegroundColor White
            Write-Host "  Password: " -NoNewline -ForegroundColor Yellow
            
            if ($password -eq "No password (Open network)") {
                Write-Host $password -ForegroundColor DarkGray
            } elseif ($password -eq "Unable to retrieve") {
                Write-Host $password -ForegroundColor Red
            } else {
                Write-Host $password -ForegroundColor Green
            }
            Write-Host ""
        }
        
        Write-Host "PROGRESS:100" -ForegroundColor Magenta
        
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host "Total WiFi Networks: $($results.Count)" -ForegroundColor Cyan
        
        # Export if requested
        if ($ExportToFile) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $exportPath = Join-Path $env:USERPROFILE "Desktop\WiFi-Passwords-$timestamp.csv"
            
            try {
                $results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
                Write-Host ""
                Write-Host "Passwords exported to:" -ForegroundColor Green
                Write-Host "  $exportPath" -ForegroundColor Cyan
            } catch {
                Write-Host ""
                Write-Host "[ERROR] Failed to export: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        Write-Host "TIP: Use these passwords to reconnect devices or share with others" -ForegroundColor DarkGray
    }
    
    "Show Password for Specific Profile*" {
        if ([string]::IsNullOrWhiteSpace($ProfileName)) {
            Write-Host "[ERROR] Profile Name is required!" -ForegroundColor Red
            Write-Host ""
            Write-Host "Please enter the exact WiFi network name." -ForegroundColor Yellow
            Write-Host "You can get the list by running 'List All WiFi Profiles' first." -ForegroundColor Yellow
            return
        }
        
        Write-Host "Looking up WiFi profile: $ProfileName" -ForegroundColor Cyan
        Write-Host "PROGRESS:30" -ForegroundColor Magenta
        Write-Host ""
        
        $password = Get-WiFiPassword -ProfileName $ProfileName
        
        Write-Host "PROGRESS:80" -ForegroundColor Magenta
        
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        Write-Host "WiFi Network: " -NoNewline -ForegroundColor Cyan
        Write-Host $ProfileName -ForegroundColor White
        Write-Host ""
        Write-Host "Password:     " -NoNewline -ForegroundColor Yellow
        
        if ($password -eq "No password (Open network)") {
            Write-Host $password -ForegroundColor DarkGray
        } elseif ($password -eq "Unable to retrieve") {
            Write-Host $password -ForegroundColor Red
            Write-Host ""
            Write-Host "This could mean:" -ForegroundColor DarkGray
            Write-Host "  - Profile name is incorrect (case-sensitive)" -ForegroundColor DarkGray
            Write-Host "  - Profile does not exist" -ForegroundColor DarkGray
        } else {
            Write-Host $password -ForegroundColor Green
        }
        
        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
        
        Write-Host "PROGRESS:100" -ForegroundColor Magenta
    }
    
    default {
        Write-Host "[ERROR] Unknown action: $Action" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
