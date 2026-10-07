# ====================== INITIALIZATION ======================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing, WindowsFormsIntegration

# Admin Check
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Paths
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($ScriptRoot)) { $ScriptRoot = Get-Location }
$ModulesRoot = Join-Path $ScriptRoot "modules"
$LogoPath = Join-Path $ScriptRoot "pics\techputno-1_white.png"

# Global Process Tracker
$script:ActivePowerShell = $null
$script:AsyncHandle = $null
$script:OutputTimer = $null

# Crash Catcher
$global:ToolkitCrashLog = Join-Path $env:TEMP ("IT-Toolkit-CRASH-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
trap {
    $msg = "FATAL ERROR:`n$($_.Exception.Message)`n`nTrace:`n$($_.ScriptStackTrace)"
    $msg | Out-File $global:ToolkitCrashLog -Encoding UTF8
    continue
}

# ====================== CONSOLE ENGINE (C#) ======================
$consoleClassDefinition = @"
using System;
using System.Windows.Forms;
using System.Drawing;
using System.Collections;

public class PowerShellConsole {
    private RichTextBox textBox;
    private Hashtable colors = new Hashtable();

    public PowerShellConsole(RichTextBox textBox) {
        this.textBox = textBox;
        colors["Default"] = Color.FromArgb(240, 240, 240);
        colors["Command"] = Color.FromArgb(86, 156, 214);
        colors["Error"]   = Color.FromArgb(255, 100, 100);
        colors["Warning"] = Color.FromArgb(255, 200, 100);
        colors["Success"] = Color.FromArgb(100, 255, 100);
        colors["Info"]    = Color.FromArgb(100, 200, 255);
        colors["Prompt"]  = Color.FromArgb(0, 255, 0);
    }

    public void Write(string text, string color) {
        if (textBox.InvokeRequired) {
            textBox.Invoke(new Action(() => Write(text, color)));
            return;
        }
        textBox.SelectionStart = textBox.TextLength;
        textBox.SelectionColor = (Color)(colors.ContainsKey(color) ? colors[color] : colors["Default"]);
        textBox.AppendText(text);
        textBox.ScrollToCaret();
    }
    public void WriteLine(string text, string color) { Write(text + "\r\n", color); }
    public void Clear() { textBox.Clear(); }
}
"@

if (-not ("PowerShellConsole" -as [type])) {
    Add-Type -TypeDefinition $consoleClassDefinition -ReferencedAssemblies @("System.Windows.Forms", "System.Drawing")
}

# ====================== HELPERS ======================
function Sanitize-FolderName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }

    $bad = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $bad) {
        $Name = $Name.Replace([string]$c, "_")
    }
    return $Name.Trim()
}

function Rename-CategoryFolderAndFixPaths {
    param(
        [Parameter(Mandatory = $true)][string]$OldName,
        [Parameter(Mandatory = $true)][string]$NewName
    )

    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        throw "ModulesPath is empty. Browse to the modules folder first."
    }

    $safeNew = Sanitize-FolderName $NewName

    $oldFolder = Join-Path $script:ModulesPath $OldName
    $newFolder = Join-Path $script:ModulesPath $safeNew

    if (-not (Test-Path -LiteralPath $oldFolder -PathType Container)) {
        # Not all toolkits use category folders. If it does not exist, just skip renaming.
        return @{ Renamed = $false; OldFolder = $oldFolder; NewFolder = $newFolder; NewName = $safeNew }
    }

    if (Test-Path -LiteralPath $newFolder) {
        throw "Target folder already exists: $newFolder"
    }

    # Rename the folder
    Rename-Item -LiteralPath $oldFolder -NewName $safeNew -ErrorAction Stop

    # Update all module FilePath values that were under that folder
    foreach ($mod in $script:Categories[$OldName].Modules) {
        if ($mod.FilePath -and $mod.FilePath.StartsWith($oldFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            $mod.FilePath = $newFolder + $mod.FilePath.Substring($oldFolder.Length)
        }
    }

    return @{ Renamed = $true; OldFolder = $oldFolder; NewFolder = $newFolder; NewName = $safeNew }
}
function Select-DriveLetterDialog {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Select Drive"; $f.Width = 300; $f.Height = 150; $f.StartPosition = "CenterParent"; $f.FormBorderStyle = "FixedDialog"
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.Left = 20; $cmb.Top = 20; $cmb.Width = 240; $cmb.DropDownStyle = "DropDownList"
    [System.IO.Directory]::GetLogicalDrives() | ForEach-Object { [void]$cmb.Items.Add($_.TrimEnd('\')) }
    $cIndex = $cmb.FindString("C:"); if ($cIndex -ge 0) { $cmb.SelectedIndex = $cIndex }
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "OK"; $btn.Left = 185; $btn.Top = 60; $btn.Width = 75; $btn.DialogResult = "OK"
    $f.Controls.AddRange(@($cmb, $btn))
    if ($f.ShowDialog() -eq "OK") { return $cmb.SelectedItem.ToString() }
    return $null
}

function Get-ToolkitModules {
    if (-not (Test-Path $ModulesRoot)) { return @() }

    # 1. Load hidden categories from JSON
    $catFile = Join-Path $ModulesRoot "categories.json"
    $hiddenCats = @()
    if (Test-Path $catFile) {
        $cData = Get-Content $catFile -Raw | ConvertFrom-Json
        $hiddenCats = $cData.Categories | Where-Object { $_.IsEmpty -eq $true } | Select-Object -ExpandProperty Name
    }

    $list = New-Object System.Collections.Generic.List[PSObject]
    # 2. Find modules excluding _deleted, _disabled, and shared
    $moduleFiles = Get-ChildItem $ModulesRoot -Filter "module.json" -Recurse | Where-Object {
        $_.FullName -notmatch '_deleted|_disabled|_shared'
    }

    foreach ($file in $moduleFiles) {
        try {
            $c = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if ($hiddenCats -contains $c.Category) { continue }

            $resolvedRunPath = if ($c.runPath) { $c.runPath } else { "run.ps1" }
            $list.Add([PSCustomObject]@{
                    Name = $c.Name; Category = $c.Category; Order = [int]$c.Order
                    Description = $c.Description; Params = $c.params; RunPath = Join-Path $file.DirectoryName $resolvedRunPath
                })
        } catch {}
    }
    return $list
}

function Show-MultiSelectDialog {
    param([string[]]$Options, [string]$Title = "Select Items")

    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title; $f.Width = 400; $f.Height = 500; $f.StartPosition = "CenterParent"; $f.BackColor = "White"; $f.TopMost = $true
    $f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false; $f.MinimizeBox = $false

    $pnl = New-Object System.Windows.Forms.FlowLayoutPanel -Property @{ Dock = "Fill"; AutoScroll = $true; Padding = New-Object System.Windows.Forms.Padding(20) }
    $f.Controls.Add($pnl)

    $checks = @()
    foreach ($opt in $Options) {
        $c = New-Object System.Windows.Forms.CheckBox -Property @{ Text = $opt; Width = 300; Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 5); Font = New-Object System.Drawing.Font("Segoe UI", 10) }
        $pnl.Controls.Add($c); $checks += $c
    }

    $btnOk = New-Object System.Windows.Forms.Button -Property @{ Text = "Confirm Selection"; Dock = "Bottom"; Height = 45; BackColor = "#10B981"; ForeColor = "White"; FlatStyle = "Flat"; Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold) }
    $btnOk.Add_Click({ $f.DialogResult = [System.Windows.Forms.DialogResult]::OK; $f.Close() })
    $f.Controls.Add($btnOk)

    if ($f.ShowDialog() -eq "OK") {
        return ($checks | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
    }
    return $null
}

# ====================== GUI XAML ======================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:wf="clr-namespace:System.Windows.Forms;assembly=System.Windows.Forms"
        xmlns:wfi="clr-namespace:System.Windows.Forms.Integration;assembly=WindowsFormsIntegration"
        Title="IT Swiss-Army Knife" Height="1000" Width="1100" WindowStartupLocation="CenterScreen" Background="#F1F5F9">
<Window.Resources>
        <Style x:Key="VisibleDisabledButton" TargetType="Button">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="5">
                            <ContentPresenter HorizontalAlignment="Center"
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#94A3B8"/>
                                <Setter Property="Foreground" Value="#1E293B"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="10">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="2*"/><RowDefinition Height="2.1*"/></Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#0F172A" Padding="15" CornerRadius="8" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="IT Swiss-Army Knife" Foreground="White" FontSize="20" FontWeight="Bold"/>
                    <TextBlock Name="txtStatus" Text="Ready" Foreground="#94A3B8"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button Name="btnRun" Content="RUN" Background="#EF4444" Foreground="White" FontWeight="Bold" Width="100" Height="35" Margin="5" Style="{StaticResource VisibleDisabledButton}"/>
                    <Button Name="btnStop" Content="STOP" Background="#F59E0B" Foreground="White" FontWeight="Bold" Width="80" Height="35" Margin="5" IsEnabled="False" Style="{StaticResource VisibleDisabledButton}"/>
                    <Button Name="btnReload" Content="Reload" Background="#3B82F6" Foreground="White" FontWeight="Bold" Width="80" Height="35" Margin="5" Style="{StaticResource VisibleDisabledButton}"/>
                    <Button Name="btnClear" Content="Clear" Background="#10B981" Foreground="White" FontWeight="Bold" Width="80" Height="35" Margin="5" Style="{StaticResource VisibleDisabledButton}"/>
                    <Image Name="imgLogo" Height="40" Margin="15,0,0,0" Stretch="Uniform" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions><ColumnDefinition Width="350"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="White" CornerRadius="8" BorderBrush="#CBD5E1" BorderThickness="1" Margin="0,0,10,0">
                <DockPanel>
                    <TextBlock Text="Search Modules:" DockPanel.Dock="Top" Margin="10,10,10,0" FontWeight="Bold"/>
                    <TextBox Name="txtSearch" DockPanel.Dock="Top" Margin="10,5,10,10" Padding="5"/>
                    <TreeView Name="tvModules" BorderThickness="0"/>
                </DockPanel>
            </Border>
            <Border Grid.Column="1" Background="White" CornerRadius="8" BorderBrush="#CBD5E1" BorderThickness="1">
                <ScrollViewer Padding="15"><StackPanel Name="pnlParams"><TextBlock Name="txtModuleName" FontSize="18" FontWeight="Bold"/><TextBlock Name="txtModuleDesc" Foreground="#64748B" Margin="0,5,0,15" TextWrapping="Wrap"/></StackPanel></ScrollViewer>
            </Border>
        </Grid>
        <Grid Grid.Row="2" Margin="0,10,0,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="White" CornerRadius="8,8,0,0" BorderBrush="#CBD5E1" BorderThickness="1,1,1,0" Padding="10">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <ProgressBar Name="progressBar" Grid.Column="0" Height="25" Minimum="0" Maximum="100" Value="0" Visibility="Collapsed"/>
                    <TextBlock Name="txtProgress" Grid.Column="1" Text="0%" VerticalAlignment="Center" Margin="10,0,0,0" FontWeight="Bold" Visibility="Collapsed"/>
                </Grid>
            </Border>

            <Border Grid.Row="1" Background="#0F172A" CornerRadius="0,0,8,8" BorderBrush="#CBD5E1" BorderThickness="1,0,1,1">
                <wfi:WindowsFormsHost Margin="5">
                    <wf:RichTextBox x:Name="rtbConsole" ReadOnly="True" BackColor="0,0,0" BorderStyle="None"/>
                </wfi:WindowsFormsHost>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Parse($xaml)

# Map Controls
$txtStatus = $window.FindName("txtStatus"); $btnReload = $window.FindName("btnReload"); $btnRun = $window.FindName("btnRun")
$btnStop = $window.FindName("btnStop"); $btnClear = $window.FindName("btnClear"); $tvModules = $window.FindName("tvModules")
$pnlParams = $window.FindName("pnlParams"); $txtModuleName = $window.FindName("txtModuleName"); $txtModuleDesc = $window.FindName("txtModuleDesc")
$txtSearch = $window.FindName("txtSearch"); $rtbConsole = $window.FindName("rtbConsole"); $imgLogo = $window.FindName("imgLogo")
$progressBar = $window.FindName("progressBar")
$txtProgress = $window.FindName("txtProgress")

if (Test-Path $LogoPath) {
    try { $imgLogo.Source = New-Object System.Windows.Media.Imaging.BitmapImage(New-Object System.Uri($LogoPath)) } catch { }
}
$rtbConsole.Font = New-Object System.Drawing.Font("Consolas", 11)
$script:Console = New-Object PowerShellConsole($rtbConsole)

# Progress Bar Functions
function Show-Progress {
    $progressBar.Visibility = "Visible"
    $txtProgress.Visibility = "Visible"
    $progressBar.Value = 0
    $txtProgress.Text = "0%"
}

function Update-Progress {
    param([int]$percent)
    if ($percent -lt 0) { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }

    $progressBar.Value = $percent
    $txtProgress.Text = "$percent%"
}

function Hide-Progress {
    $progressBar.Visibility = "Collapsed"
    $txtProgress.Visibility = "Collapsed"
    $progressBar.Value = 0
    $txtProgress.Text = "0%"
}

function Get-ConsoleColorKeyForLine {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return "Default" }

    $trim = $Line.TrimStart()

    if ($trim -match '^\[(ERROR|FAIL|FAILED)\]') { return "Error" }
    if ($trim -match '^\[(WARN|WARNING)\]') { return "Warning" }
    if ($trim -match '^\[(OK|SUCCESS|DONE)\]') { return "Success" }
    if ($trim -match '^\[(SKIP|SKIPPED|NOT\s+COPIED)\]') { return "Warning" }
    if ($trim -match '^\[(COPIED|REPLACED|DIR\s+CREATED)\]') { return "Success" }
    if ($trim -match '^\[(UNCHANGED|SAME)\]') { return "Info" }
    if ($trim -match '^\[(INFO|STATUS|SYSTEM)\]') { return "Info" }
    if ($trim -match '^(=+|-{3,})') { return "Command" }
    if ($trim -match '^(NETWORK SUMMARY|SYSTEM INFO|DISK INFO)') { return "Success" }
    if ($trim -match '^(Adapter|Interface|Drive|Computer|OS|User)\s*:') { return "Info" }
    if ($trim -match '^(IPv4|IPv6|Gateway|DNS|MAC|Status|Public IP|Subnet)\s*:') { return "Warning" }
    if ($trim -match '^(PS:|PowerShell|Version)\s*:') { return "Info" }

    return "Default"
}

function Get-ConsoleColorKeyFromHostColor {
    param(
        [string]$Line,
        [string]$ForegroundColor
    )

    switch ($ForegroundColor) {
        "Red" { return "Error" }
        "DarkRed" { return "Error" }
        "Yellow" { return "Warning" }
        "DarkYellow" { return "Warning" }
        "Green" { return "Success" }
        "DarkGreen" { return "Success" }
        "Cyan" { return "Info" }
        "DarkCyan" { return "Info" }
        "Magenta" { return "Info" }
        "DarkMagenta" { return "Info" }
        "Blue" { return "Command" }
        "DarkBlue" { return "Command" }
        "Gray" { return "Default" }
        "DarkGray" { return "Default" }
        "White" { return "Default" }
        default { return "Default" }
    }
}

# ====================== EXECUTION ENGINE ======================
function Process-AllStreams {
    if (-not $script:ActivePowerShell) { return }

    # Information/Output Stream (Write-Host goes here)
    $info = $script:ActivePowerShell.Streams.Information.ReadAll()
    foreach ($item in $info) {
        $msg = $null
        $fgColor = $null
        if ($null -ne $item.MessageData) {
            if ($item.MessageData.PSObject.Properties['Message']) {
                $msg = [string]$item.MessageData.Message
            } else {
                $msg = $item.MessageData.ToString()
            }
            if ($item.MessageData.PSObject.Properties['ForegroundColor']) {
                $fgColor = [string]$item.MessageData.ForegroundColor
            }
        } else {
            $msg = $item.ToString()
        }
        if ($null -ne $msg) {
            # Check for progress marker
            if ($msg -match '^PROGRESS:(\d+)$') {
                Update-Progress -percent ([int]$matches[1])
            } else {
                $colorKey = if ($fgColor) { Get-ConsoleColorKeyFromHostColor -Line $msg -ForegroundColor $fgColor } else { "Default" }
                if ($colorKey -eq "Default") {
                    $colorKey = Get-ConsoleColorKeyForLine -Line $msg
                }
                $script:Console.WriteLine($msg, $colorKey)
            }
        }
    }

    # Warning Stream
    $warnings = $script:ActivePowerShell.Streams.Warning.ReadAll()
    foreach ($w in $warnings) {
        $script:Console.WriteLine("[WARNING] $($w.Message)", "Warning")
    }

    # Error Stream
    $errors = $script:ActivePowerShell.Streams.Error.ReadAll()
    foreach ($e in $errors) {
        $script:Console.WriteLine("[ERROR] $($e.ToString())", "Error")
    }

    # Verbose Stream
    $verbose = $script:ActivePowerShell.Streams.Verbose.ReadAll()
    foreach ($v in $verbose) {
        $script:Console.WriteLine("[VERBOSE] $($v.Message)", "Info")
    }

    # Debug Stream
    $debug = $script:ActivePowerShell.Streams.Debug.ReadAll()
    foreach ($d in $debug) {
        $script:Console.WriteLine("[DEBUG] $($d.Message)", "Info")
    }
}

function Execute-CommandAsync {
    param([string]$fullCmd, [string]$displayName)

    $script:Console.WriteLine("-" * 50, "Default")
    $script:Console.WriteLine("STARTING: $displayName", "Command")

    $btnRun.IsEnabled = $false; $btnStop.IsEnabled = $true; $btnReload.IsEnabled = $false; $btnClear.IsEnabled = $false
    Show-Progress

    $m = $tvModules.SelectedItem.Tag

    # Build argument list
    $argList = @()
    foreach ($k in $script:InputControls.Keys) {
        $c = $script:InputControls[$k]
        if ($null -eq $c) { continue }

        # 1. Multi-Select Buttons (Use .Tag)
        if ($c -is [System.Windows.Controls.Button]) {
            if ($k -notmatch '__toggle') {
                $val = [string]$c.Tag
                $argList += "-${k} `"$($val -replace '"','""')`""
            }
        }
        # 2. Checkboxes (Use .IsChecked) - Handle nullable boolean properly
        elseif ($c -is [System.Windows.Controls.CheckBox]) {
            $boolVal = if ($c.IsChecked -eq $true) { '$true' } else { '$false' }
            $argList += "-${k} $boolVal"
        }
        # 3. ComboBoxes (Use .SelectedItem)
        elseif ($c -is [System.Windows.Controls.ComboBox]) {
            $v = if ($c.SelectedItem) { [string]$c.SelectedItem } else { "" }
            $argList += "-${k} `"$($v.Trim() -replace '"','""')`""
        }
        # 4. Passwords (Use .Password)
        elseif ($c -is [System.Windows.Controls.PasswordBox]) {
            $argList += "-${k} `"$($c.Password -replace '"','""')`""
        }
        # 5. TextBoxes (Final Default)
        else {
            if ($c.PSObject.Properties['Text']) {
                $v = [string]$c.Text
                $argList += "-${k} `"$($v.Trim() -replace '"','""')`""
            }
        }
    }

    # Create new PowerShell runspace
    $script:ActivePowerShell = [powershell]::Create()

    # Build the execution script
    $finalScript = @"
`$ErrorActionPreference = 'Continue'
`$VerbosePreference = 'SilentlyContinue'
`$DebugPreference = 'SilentlyContinue'
`$InformationPreference = 'Continue'

try {
    Write-Host "[System] Executing module..." -ForegroundColor Cyan
    Write-Host ""

    `$scriptPath = '$($m.RunPath -replace "'", "''")'

    if (Test-Path `$scriptPath) {
        & `$scriptPath $($argList -join ' ') 2>&1 | ForEach-Object {
            if (`$_ -is [System.Management.Automation.VerboseRecord]) {
                # Skip verbose
            } elseif (`$_ -is [System.Management.Automation.DebugRecord]) {
                # Skip debug
            } elseif (`$_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host "[ERROR] `$_" -ForegroundColor Red
            } elseif (`$_ -is [System.Management.Automation.WarningRecord]) {
                Write-Host "[WARNING] `$(`$_.Message)" -ForegroundColor Yellow
            } else {
                `$line = `$_.ToString()

                if (`$line -match '^(NETWORK SUMMARY|SYSTEM INFO|DISK INFO|=+|─+)') {
                    Write-Host `$line -ForegroundColor Green
                }
                elseif (`$line -match '^(Adapter|Interface|Drive|Computer|OS|User)\s*:') {
                    Write-Host `$line -ForegroundColor Cyan
                }
                elseif (`$line -match '^(IPv4|IPv6|Gateway|DNS|MAC|Status|Public IP|Subnet)\s*:') {
                    Write-Host `$line -ForegroundColor Yellow
                }
                elseif (`$line -match '^(PS:|PowerShell|Version)\s*:') {
                    Write-Host `$line -ForegroundColor Magenta
                }
                elseif (`$line -match '^\s*$' -or `$line -eq '') {
                    Write-Host ""
                }
                else {
                    Write-Host `$line -ForegroundColor White
                }
            }
        }
    } else {
        Write-Host "[ERROR] Script file not found: `$scriptPath" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "[System] Execution completed." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host `$_.ScriptStackTrace -ForegroundColor DarkRed
}
"@

    $script:ActivePowerShell.AddScript($finalScript)

    # Start async execution
    $script:AsyncHandle = $script:ActivePowerShell.BeginInvoke()

    # Create timer to poll for output
    $script:OutputTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:OutputTimer.Interval = [TimeSpan]::FromMilliseconds(100)

    $script:OutputTimer.Add_Tick({
            try {
                if ($script:AsyncHandle.IsCompleted) {
                    # Final output drain
                    Process-AllStreams

                    # Cleanup
                    try {
                        $script:ActivePowerShell.EndInvoke($script:AsyncHandle)
                    } catch {
                        $script:Console.WriteLine("[ERROR] $($_.Exception.Message)", "Error")
                    }

                    $script:ActivePowerShell.Dispose()
                    $script:ActivePowerShell = $null
                    $script:AsyncHandle = $null
                    $script:OutputTimer.Stop()

                    $btnRun.IsEnabled = $true
                    $btnStop.IsEnabled = $false
                    $btnReload.IsEnabled = $true
                    $btnClear.IsEnabled = $true
                    Hide-Progress
                    $script:Console.WriteLine("FINISHED.", "Success")
                } else {
                    # Process output while running
                    Process-AllStreams
                }
            } catch {
                $script:Console.WriteLine("[TIMER ERROR] $($_.Exception.Message)", "Error")
                $script:OutputTimer.Stop()
                $btnRun.IsEnabled = $true
                $btnStop.IsEnabled = $false
                $btnReload.IsEnabled = $true
                $btnClear.IsEnabled = $true
                Hide-Progress
            }
        })

    $script:OutputTimer.Start()
}

# ====================== UI LOGIC ======================

# Load category order from categories.json
function Get-CategoryOrder {
    $categoriesFile = Join-Path $ModulesRoot "categories.json"
    $categoryOrder = @{}

    if (Test-Path $categoriesFile) {
        try {
            $json = Get-Content $categoriesFile -Raw | ConvertFrom-Json
            $order = 1
            foreach ($cat in $json.Categories) {
                $categoryOrder[$cat.Name] = $cat.Order
                $order++
            }
        } catch {
            Write-Host "Error loading categories.json: $_" -ForegroundColor Yellow
        }
    }

    return $categoryOrder
}

function Update-TreeView {
    param($all)
    $tvModules.Items.Clear()

    # 1. Load the categories config
    $catConfigPath = Join-Path $ModulesRoot "categories.json"
    $catOrderData = if (Test-Path $catConfigPath) {
        Get-Content $catConfigPath -Raw | ConvertFrom-Json
    } else { $null }

    # 2. Group and Sort the Categories by CategoryOrder
    $groups = $all | Group-Object Category | Sort-Object {
        $name = $_.Name
        if ($null -ne $catOrderData) {
            $match = $catOrderData.Categories | Where-Object { $_.Name -eq $name }
            if ($match) { return [int]$match.CategoryOrder }
        }
        return 999
    }

    foreach ($g in $groups) {
        # --- 3. GET THE CATEGORY NUMBER ---
        $orderNum = 999
        if ($null -ne $catOrderData) {
            $match = $catOrderData.Categories | Where-Object { $_.Name -eq $g.Name }
            if ($match) { $orderNum = [int]$match.CategoryOrder }
        }

        $cat = New-Object System.Windows.Controls.TreeViewItem
        # --- 4. FORMAT HEADER: "Number. Name (Count)" ---
        $cat.Header = ("{0}. {1} ({2})" -f $orderNum, $g.Name, $g.Count)
        $cat.IsExpanded = $true

        # 5. Sort individual modules by their internal Order
        $sortedModules = @($g.Group) | Sort-Object Order, Name

        foreach ($m in $sortedModules) {
            # Get the module order number, default to 0 if not found
            $mOrder = if ($m.PSObject.Properties['Order']) { [int]$m.Order } else { 0 }

            # Create a display name like "1- Ping Test"
            $displayHeader = if ($mOrder -gt 9) { "{0}- {1}" -f $mOrder, $m.Name } else { "{0,3}- {1}" -f $mOrder, $m.Name }
            #$displayHeader = "{0,2}- {1}" -f $mOrder, $m.Name

            # Set the header to the new display name
            $item = New-Object System.Windows.Controls.TreeViewItem -Property @{
                Header = $displayHeader
                Tag    = $m
            }

            [void]$cat.Items.Add($item)
        }
        [void]$tvModules.Items.Add($cat)
    }
}
function Show-WelcomeMessage {
    $pnlParams.Children.Clear()
    $script:InputControls = @{}

    $txtModuleName.Text = "IT Swiss-Army Knife"
    $txtModuleDesc.Text = "Professional IT Administration Toolkit"

    # Welcome message
    $welcomeText = New-Object System.Windows.Controls.TextBlock -Property @{
        TextWrapping = "Wrap"
        Margin       = "0,10,0,10"
        FontSize     = 13
        LineHeight   = 22
        Text         = @"
Welcome to the IT Swiss-Army Knife!

This comprehensive toolkit provides powerful modules for system administration, maintenance, security, and network diagnostics. All modules are designed with safety features including dry-run modes, progress reporting, and detailed logging.

Getting Started:
1. Browse available modules in the left panel (organized by category)
2. Click on any module to view its configuration options
3. Configure the parameters as needed
4. Click RUN to execute the module
5. View real-time output in the console below

Features:
- Progress Tracking - Real-time progress bars for long-running operations
- Safety First - Dry-run modes and confirmations for destructive actions
- Comprehensive Logging - Detailed output for troubleshooting
- Export Options - Save results to CSV, JSON, HTML formats
- Admin Detection - Automatic elevation prompts when needed

Tips:
- Use the Search box above to quickly find modules
- Check module descriptions for detailed information
- Most modules include WhatIf/Dry-Run modes for safe testing
- Review the console output for detailed execution logs
- Press STOP to cancel any running operation

Select a module from the left panel to begin!
"@
    }

    $pnlParams.Children.Add($welcomeText) | Out-Null

    # Module count by category
    $all = Get-ToolkitModules
    if ($all.Count -gt 0) {
        $categorySummary = New-Object System.Windows.Controls.TextBlock -Property @{
            TextWrapping = "Wrap"
            Margin       = "0,20,0,10"
            FontWeight   = "Bold"
            FontSize     = 14
            Text         = "Available Modules:"
        }
        $pnlParams.Children.Add($categorySummary) | Out-Null

        $categoryOrder = Get-CategoryOrder
        $groups = $all | Group-Object Category
        $sortedGroups = $groups | Sort-Object {
            if ($categoryOrder.ContainsKey($_.Name)) {
                $categoryOrder[$_.Name]
            } else {
                999
            }
        }, Name

        foreach ($g in $sortedGroups) {
            $catText = New-Object System.Windows.Controls.TextBlock -Property @{
                Margin   = "10,5,0,0"
                FontSize = 12
                Text     = "  - $($g.Name): $($g.Count) module(s)"
            }
            $pnlParams.Children.Add($catText) | Out-Null
        }

        $totalText = New-Object System.Windows.Controls.TextBlock -Property @{
            Margin     = "0,15,0,0"
            FontWeight = "Bold"
            FontSize   = 13
            Foreground = "#10B981"
            Text       = "Total: $($all.Count) modules loaded"
        }
        $pnlParams.Children.Add($totalText) | Out-Null
    }
}

function Handle-CheckboxDependencies {
    param($checkboxControl, $param, $allParams)

    # When this checkbox changes, handle the disables property
    $checkboxControl.Add_Checked({
            if ($param.disables) {
                foreach ($disabledParamName in $param.disables) {
                    if ($script:InputControls.ContainsKey($disabledParamName)) {
                        $script:InputControls[$disabledParamName].IsEnabled = $false
                        $script:InputControls[$disabledParamName].IsChecked = $false
                    }
                }
            }
        }.GetNewClosure())

    $checkboxControl.Add_Unchecked({
            if ($param.disables) {
                foreach ($disabledParamName in $param.disables) {
                    if ($script:InputControls.ContainsKey($disabledParamName)) {
                        $script:InputControls[$disabledParamName].IsEnabled = $true
                    }
                }
            }
        }.GetNewClosure())
}

# ====================== Update-DisableRules (SCRIPT LEVEL) ======================
function Update-DisableRules {
    param($module)

    if ($script:__DisableRulesBusy) { return }
    $script:__DisableRulesBusy = $true

    try {
        # Build the set of disabled targets based on currently-checked sources
        $disabled = New-Object 'System.Collections.Generic.HashSet[string]'

        foreach ($srcParam in $module.Params) {
            $ptype = if ($srcParam.type) { $srcParam.type.ToLower() } else { "" }
            if ($ptype -ne "checkbox") { continue }
            if (-not $srcParam.disables) { continue }
            if (-not $script:InputControls.ContainsKey($srcParam.name)) { continue }

            $srcCtrl = $script:InputControls[$srcParam.name]
            if (-not ($srcCtrl -is [System.Windows.Controls.CheckBox])) { continue }

            # Check if this checkbox is checked
            if ($srcCtrl.IsChecked -eq $true) {
                # Add all its disabled targets
                foreach ($t in $srcParam.disables) {
                    [void]$disabled.Add([string]$t)
                }
            }
        }

        # Apply enabled/disabled state to all checkboxes
        foreach ($pp in $module.Params) {
            $ptype = if ($pp.type) { $pp.type.ToLower() } else { "" }
            if ($ptype -ne "checkbox") { continue }
            if (-not $script:InputControls.ContainsKey($pp.name)) { continue }

            $cb = $script:InputControls[$pp.name]
            if ($cb -isnot [System.Windows.Controls.CheckBox]) { continue }

            # Get the visual toggle button
            $toggleKey = "__toggle_" + $pp.name
            $toggleBtn = if ($script:InputControls.ContainsKey($toggleKey)) {
                $script:InputControls[$toggleKey]
            } else {
                $null
            }

            if ($disabled.Contains([string]$pp.name)) {
                # This checkbox should be DISABLED
                $cb.IsEnabled = $false

                # Force uncheck if it's checked
                if ($cb.IsChecked -eq $true) {
                    $cb.IsChecked = $false
                }

                # Update the toggle button visuals
                if ($toggleBtn) {
                    $toggleBtn.IsEnabled = $false
                    $toggleBtn.Tag = $false
                    $toggleBtn.Content = "OFF"
                    $toggleBtn.Background = "#9CA3AF"
                    $toggleBtn.Foreground = "#6B7280"
                    $toggleBtn.Cursor = "No"
                }
            } else {
                # This checkbox should be ENABLED
                $cb.IsEnabled = $true

                # Update the toggle button visuals
                if ($toggleBtn) {
                    $toggleBtn.IsEnabled = $true
                    $toggleBtn.Cursor = "Hand"

                    # Restore color based on current state
                    $currentState = $toggleBtn.Tag
                    if ($currentState -eq $true) {
                        $toggleBtn.Content = "ON"
                        $toggleBtn.Background = "#10B981"
                        $toggleBtn.Foreground = "White"
                    } else {
                        $toggleBtn.Content = "OFF"
                        $toggleBtn.Background = "#CBD5E1"
                        $toggleBtn.Foreground = "Black"
                    }
                }
            }
        }
    } finally {
        $script:__DisableRulesBusy = $false
    }
}
function Resolve-ParamDefault {
    param(
        $value,
        $module
    )

    if ($null -eq $value) { return "" }

    $s = [string]$value
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }

    # IMPORTANT: your module objects do NOT have .Path in Get-ToolkitModules
    # The module folder is Split-Path -Parent $module.RunPath
    $moduleDir = Split-Path -Parent $module.RunPath

    switch ($s) {
        "__MODULE_ROOT__" { return [string]$moduleDir }
        "__MODULE_OUTPUT__" { return (Join-Path ([string]$moduleDir) "output") }
        "__MODULE_LOGS__" { return (Join-Path ([string]$moduleDir) "logs") }
        default { return $s }
    }
}

function Initialize-ManifestChoiceControl {
    param($Combo, $Param, [switch]$HonorDefault)

    $Combo.Items.Clear()
    if ($Param.PSObject.Properties.Match("options").Count -gt 0 -and $Param.options) {
        foreach ($option in $Param.options) { [void]$Combo.Items.Add($option) }
    }

    if ($Combo.Items.Count -le 0) { return }

    $selectedIndex = 0
    if ($HonorDefault -and $Param.PSObject.Properties.Match("default").Count -gt 0 -and $null -ne $Param.default) {
        $defaultIndex = $Combo.Items.IndexOf($Param.default)
        if ($defaultIndex -ge 0) { $selectedIndex = $defaultIndex }
    }
    $Combo.SelectedIndex = $selectedIndex
}

function Get-ManifestMappedValue {
    param($Map, [string]$Key)

    if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($Key)) { return $null }
    foreach ($property in $Map.PSObject.Properties) {
        if ($property.Name -ieq $Key) { return $property.Value }
    }
    return $null
}

function Update-DependentSelects {
    param($Module)

    foreach ($param in $Module.Params) {
        if ($param.PSObject.Properties.Match("dependsOn").Count -le 0 -or
            $param.PSObject.Properties.Match("optionsMap").Count -le 0) { continue }

        $name = [string]$param.name
        $dependencyName = [string]$param.dependsOn
        if (-not $script:InputControls.ContainsKey($name) -or -not $script:InputControls.ContainsKey($dependencyName)) { continue }

        $target = $script:InputControls[$name]
        $dependency = $script:InputControls[$dependencyName]
        if ($target -isnot [System.Windows.Controls.ComboBox] -or $dependency -isnot [System.Windows.Controls.ComboBox]) { continue }

        $dependencyValue = [string]$dependency.SelectedItem
        $options = @(Get-ManifestMappedValue -Map $param.optionsMap -Key $dependencyValue)
        $previousValue = if ($target.SelectedItem) { [string]$target.SelectedItem } else { "" }

        $target.Items.Clear()
        foreach ($option in $options) { [void]$target.Items.Add($option) }
        if ($target.Items.Count -le 0) { continue }

        $selectedIndex = if (-not [string]::IsNullOrWhiteSpace($previousValue)) { $target.Items.IndexOf($previousValue) } else { -1 }
        if ($selectedIndex -lt 0) {
            $mappedDefault = if ($param.PSObject.Properties.Match("defaultMap").Count -gt 0) {
                Get-ManifestMappedValue -Map $param.defaultMap -Key $dependencyValue
            } else { $null }
            $selectedIndex = if ($null -ne $mappedDefault) { $target.Items.IndexOf($mappedDefault) } else { -1 }
        }
        $target.SelectedIndex = if ($selectedIndex -ge 0) { $selectedIndex } else { 0 }
    }
}

function ConvertTo-ManifestConditionValue {
    param($Value)

    if ($null -eq $Value) { return "" }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    return ([string]$Value).Trim()
}

function Get-ManifestControlValue {
    param($Control)

    if ($Control -is [System.Windows.Controls.CheckBox]) {
        return [bool]($Control.IsChecked -eq $true)
    }
    if ($Control -is [System.Windows.Controls.ComboBox]) {
        return $Control.SelectedItem
    }
    return $null
}

function Test-ManifestCondition {
    param($Condition, $Controls)

    if ($null -eq $Condition) { return $true }

    foreach ($property in $Condition.PSObject.Properties) {
        $controllerName = [string]$property.Name
        if (-not $Controls.ContainsKey($controllerName)) { return $false }

        $actual = ConvertTo-ManifestConditionValue (Get-ManifestControlValue $Controls[$controllerName])
        $allowed = @($property.Value) | ForEach-Object { ConvertTo-ManifestConditionValue $_ }
        if ($allowed -notcontains $actual) { return $false }
    }
    return $true
}

function Get-ParameterCondition {
    param($Param, [string]$ConditionName)

    if ($Param.PSObject.Properties.Match($ConditionName).Count -gt 0) {
        return $Param.$ConditionName
    }
    if ($Param.PSObject.Properties.Match("ui").Count -gt 0 -and $null -ne $Param.ui -and
        $Param.ui.PSObject.Properties.Match($ConditionName).Count -gt 0) {
        return $Param.ui.$ConditionName
    }
    return $null
}

function Update-ManifestConditions {
    param($Module)

    foreach ($param in $Module.Params) {
        $name = if ($param.PSObject.Properties.Match("name").Count -gt 0) { [string]$param.name } else { "" }
        if ([string]::IsNullOrWhiteSpace($name) -or -not $script:ParameterContainers.ContainsKey($name)) { continue }

        $container = $script:ParameterContainers[$name]
        $visibleWhen = Get-ParameterCondition -Param $param -ConditionName "visibleWhen"
        $enabledWhen = Get-ParameterCondition -Param $param -ConditionName "enabledWhen"

        $container.Visibility = if (Test-ManifestCondition -Condition $visibleWhen -Controls $script:InputControls) { "Visible" } else { "Collapsed" }
        $container.IsEnabled = Test-ManifestCondition -Condition $enabledWhen -Controls $script:InputControls
    }
}

function Update-ManifestUiRules {
    param($Module)

    if ($script:ManifestUiRulesBusy) { return }
    $script:ManifestUiRulesBusy = $true
    try {
        Update-DependentSelects -Module $Module
        Update-ManifestConditions -Module $Module
    } finally {
        $script:ManifestUiRulesBusy = $false
    }
}

function Test-DynamicDropdownStatusValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '^(ERROR:|LOG:|Loading\.\.\.$|No options available$|No disks found$|No partitions on this disk$|Select a disk first$|Invalid disk selection$)'
}

function Test-RequiredParameterSupported {
    param($Module, $Param)

    # These fields are action-dependent in the module script, but the manifest has no requiredWhen contract.
    if ($Module.Name -eq "Deploy Windows to Offline Disk" -and
        $Param.name -in @("ImageIndex", "TargetDiskNumber", "Confirmation")) { return $false }

    $type = if ($Param.PSObject.Properties.Match("type").Count -gt 0) { [string]$Param.type } else { "text" }
    return $type.ToLowerInvariant() -in @("text", "folder", "drive", "dropdown", "select")
}

function Test-RequiredComboBoxValue {
    param($Combo, $Param)

    if ($null -eq $Combo.SelectedItem) { return $false }
    $value = ([string]$Combo.SelectedItem).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }

    $isDynamic = $Param.PSObject.Properties.Match("dynamic").Count -gt 0 -and
        (($Param.dynamic -eq $true) -or ($Param.dynamic -is [string] -and $Param.dynamic.Trim().ToLowerInvariant() -eq "true"))
    if ($isDynamic -and (Test-DynamicDropdownStatusValue -Value $value)) { return $false }
    return $true
}

function Get-MissingRequiredParameter {
    param($Module)

    foreach ($param in $Module.Params) {
        if ($param.PSObject.Properties.Match("required").Count -le 0 -or $param.required -ne $true) { continue }
        if (-not (Test-RequiredParameterSupported -Module $Module -Param $param)) { continue }

        $visibleWhen = Get-ParameterCondition -Param $param -ConditionName "visibleWhen"
        if (-not (Test-ManifestCondition -Condition $visibleWhen -Controls $script:InputControls)) { continue }

        $name = [string]$param.name
        if (-not $script:InputControls.ContainsKey($name)) {
            return [PSCustomObject]@{ Param = $param; Control = $null }
        }

        $control = $script:InputControls[$name]
        $type = if ($param.PSObject.Properties.Match("type").Count -gt 0) { [string]$param.type } else { "text" }
        $hasValue = switch ($type.ToLowerInvariant()) {
            { $_ -in @("dropdown", "select") } { Test-RequiredComboBoxValue -Combo $control -Param $param; break }
            default {
                $control.PSObject.Properties.Match("Text").Count -gt 0 -and
                    -not [string]::IsNullOrWhiteSpace([string]$control.Text)
            }
        }

        if (-not $hasValue) { return [PSCustomObject]@{ Param = $param; Control = $control } }
    }
    return $null
}

#Render-ModuleUI FUNCTION
function Render-ModuleUI {
    param($m)

    $pnlParams.Children.Clear()
    $script:InputControls = @{}
    $script:ParameterContainers = @{}
    $txtModuleName.Text = $m.Name
    $txtModuleDesc.Text = $m.Description

    # Helper to track horizontal rows for inline elements
    $currentHorizontalRow = $null

    foreach ($p in $m.Params) {
        # Strict-Safe Property Extraction
        $pType = if ($p.PSObject.Properties.Match('type').Count -gt 0) { $p.type.ToLower() } else { "text" }
        $pLabel = if ($p.PSObject.Properties.Match('label').Count -gt 0) { $p.label } else { $p.name }
        $isInline = if ($p.PSObject.Properties.Match('inline').Count -gt 0) { [bool]$p.inline } else { $false }

        # --- 1. HANDLING SEPARATORS & INFO (Always break horizontal rows) ---
        if ($pType -eq "separator" -or $pType -eq "info") {
            $currentHorizontalRow = $null
        }

        # --- 2. CONTAINER LOGIC (Inline vs Normal) ---
        if ($isInline) {
            if ($null -eq $currentHorizontalRow) {
                $currentHorizontalRow = New-Object System.Windows.Controls.StackPanel -Property @{
                    Orientation = "Horizontal"; Margin = "0,0,0,5"
                }
                $pnlParams.Children.Add($currentHorizontalRow) | Out-Null
            }
            $targetContainer = $currentHorizontalRow
        } else {
            $currentHorizontalRow = $null
            $targetContainer = $pnlParams
        }

        # Vertical sub-stack for Label + Control (This ensures label stays ON TOP of the box)
        $elementStack = New-Object System.Windows.Controls.StackPanel -Property @{
            Margin = if ($isInline) { "0,0,10,0" } else { "0,0,0,12" }
            # Width set to 327 to allow 2 items side-by-side
            Width  = if ($isInline) { 327 } else { [double]::NaN }
        }
        $targetContainer.Children.Add($elementStack) | Out-Null
        if ($p.PSObject.Properties.Match("name").Count -gt 0) {
            $script:ParameterContainers[[string]$p.name] = $elementStack
        }
        if ($p.PSObject.Properties.Match("description").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$p.description)) {
            $elementStack.ToolTip = [string]$p.description
        }

        # ---------------- SEPARATOR ----------------
        if ($pType -eq "separator") {
            if ($pLabel -and $pLabel -ne $p.name) {
                $elementStack.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{
                            Text = $pLabel; FontWeight = "Bold"; Margin = "0,12,0,6"; FontSize = 12
                        })) | Out-Null
            }
            $elementStack.Children.Add((New-Object System.Windows.Controls.Border -Property @{
                        Height = 1; Background = "#CBD5E1"; Margin = "0,0,0,8"
                    })) | Out-Null
            continue
        }

        # ---------------- INFO ----------------
        if ($pType -eq "info") {
            $elementStack.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{
                        Text = [string]$p.default; TextWrapping = "Wrap"; Margin = "0,5,0,15";
                        FontSize = 12; Foreground = "#475569"; Background = "#F1F5F9"; Padding = 10
                    })) | Out-Null
            continue
        }

        # Add Label (except for checkboxes which handle their own)
        if ($pType -ne "checkbox") {
            $elementStack.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{
                        Text = $pLabel; FontWeight = "Bold"; Margin = "0,0,0,3"; FontSize = 11
                    })) | Out-Null
        }

        # ---------------- CHECKBOX ----------------
        if ($pType -eq "checkbox") {
            $isChecked = if ($p.PSObject.Properties.Match("default").Count -gt 0) { [bool]$p.default } else { $false }
            $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal"; Margin = "0,8,0,8" }
            $toggleButton = New-Object System.Windows.Controls.Button -Property @{
                Width = 40; Height = 20; Content = if ($isChecked) { "ON" } else { "OFF" }
                Background = if ($isChecked) { "#10B981" } else { "#CBD5E1" }; Foreground = "White"; FontWeight = "Bold"; FontSize = 11; BorderThickness = 0; Cursor = "Hand"
            }
            $toggleButton.Tag = $isChecked
            $cbLabel = New-Object System.Windows.Controls.TextBlock -Property @{
                Text = $pLabel; VerticalAlignment = "Center"; Margin = "15,0,0,0"; FontSize = 12; Width = if ($isInline) { 120 }else { 350 }; TextWrapping = "Wrap"
            }
            $ctrl = New-Object System.Windows.Controls.CheckBox -Property @{ IsChecked = $isChecked; Visibility = "Collapsed" }
            $checkboxRef = $ctrl
            $toggleButton.Add_Click({
                    if (-not $this.IsEnabled) { return }
                    $ns = -not [bool]$this.Tag; $this.Tag = $ns
                    $this.Content = if ($ns) { "ON" } else { "OFF" }; $this.Background = if ($ns) { "#10B981" } else { "#CBD5E1" }
                    $checkboxRef.IsChecked = $ns
                }.GetNewClosure())
            [void]$stack.Children.Add($toggleButton); [void]$stack.Children.Add($cbLabel)
            $elementStack.Children.Add($stack) | Out-Null
            $script:InputControls[$p.name] = $ctrl
            $script:InputControls["__toggle_" + $p.name] = $toggleButton
            continue
        }

        # ---------------- PASSWORD ----------------
        if ($pType -eq "password") {
            $ctrl = New-Object System.Windows.Controls.PasswordBox -Property @{ Height = 35; VerticalContentAlignment = "Center"; Padding = "8" }
            if ($p.default) { $ctrl.Password = [string]$p.default }
            $elementStack.Children.Add($ctrl) | Out-Null
            $script:InputControls[$p.name] = $ctrl
            continue
        }

        # ---------------- MULTI-SELECT ----------------
        if ($pType -eq "multi-select") {
            $btnSelect = New-Object System.Windows.Controls.Button -Property @{
                Content = "Click to Choose Data..."; Height = 35;
                Background = "#3B82F6"; Foreground = "White"; FontWeight = "Bold"
            }
            $btnSelect.Tag = ""

            # Store reference to InputControls hashtable for the closure
            $inputCtrlsRef = $script:InputControls

            $btnSelect.Add_Click({
                    try {
                        # Get SourceDir value at CLICK time
                        $sourceDir = ""
                        if ($null -ne $inputCtrlsRef -and $inputCtrlsRef.ContainsKey("SourceDir")) {
                            $ctrl = $inputCtrlsRef["SourceDir"]
                            if ($null -ne $ctrl -and $ctrl.Text) {
                                $sourceDir = [string]$ctrl.Text
                            }
                        }

                        if ([string]::IsNullOrWhiteSpace($sourceDir)) {
                            [System.Windows.MessageBox]::Show("Please select a Support Bundles Directory first.", "Missing Input")
                            return
                        }

                        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
                            [System.Windows.MessageBox]::Show("Directory not found: $sourceDir", "Error")
                            return
                        }

                        # Find SupportBundle folders directly
                        $bundleFolders = @(Get-ChildItem -LiteralPath $sourceDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*SupportBundle*" })

                        if ($bundleFolders.Count -eq 0) {
                            [System.Windows.MessageBox]::Show("No SupportBundle folders found in:`n$sourceDir", "No Data")
                            return
                        }

                        # Get JSON files from first bundle
                        $firstPath = $bundleFolders[0].FullName
                        $jsonFiles = @(Get-ChildItem -LiteralPath $firstPath -Filter "*.json" -Recurse -ErrorAction SilentlyContinue)

                        if ($jsonFiles.Count -eq 0) {
                            [System.Windows.MessageBox]::Show("No JSON data files found in bundles.", "No Data")
                            return
                        }

                        # Build list of common categories
                        $categories = @()
                        $pathLen = $firstPath.Length + 1

                        foreach ($file in $jsonFiles) {
                            $fp = $file.FullName
                            if ($fp.Length -le $pathLen) { continue }

                            $relPath = $fp.Substring($pathLen)

                            # Skip internal files
                            if ($relPath -like "*report_settings*" -or $relPath -like "*hardware_tree*") { continue }

                            # Check if exists in all bundles
                            $existsInAll = $true
                            foreach ($bundle in $bundleFolders) {
                                if (-not (Test-Path -LiteralPath (Join-Path $bundle.FullName $relPath))) {
                                    $existsInAll = $false
                                    break
                                }
                            }

                            if ($existsInAll) {
                                $nice = $relPath -replace '\.json$', ''
                                $nice = $nice -replace '\\', ' / '
                                $categories += $nice
                            }
                        }

                        if ($categories.Count -eq 0) {
                            [System.Windows.MessageBox]::Show("No common data found across bundles.", "No Data")
                            return
                        }

                        # Sort and show dialog
                        $sortedCategories = $categories | Sort-Object
                        $result = Show-MultiSelectDialog -Options $sortedCategories -Title "Select Data to Include ($($bundleFolders.Count) bundles found)"

                        if ($null -ne $result -and @($result).Count -gt 0) {
                            $resArr = @($result)
                            $this.Tag = $resArr -join ","
                            $this.Content = "$($resArr.Count) items selected"
                            $this.Background = "#10B981"
                        }

                    } catch {
                        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)`n`n$($_.ScriptStackTrace)", "Error")
                    }
                }.GetNewClosure())

            $elementStack.Children.Add($btnSelect) | Out-Null
            $script:InputControls[$p.name] = $btnSelect
            continue
        }

        # ---------------- DROPDOWN / SELECT ----------------
        $hasDirectOptions = ($p.PSObject.Properties.Match("options").Count -gt 0 -and $p.options)
        $hasDependentOptions = ($p.PSObject.Properties.Match("dependsOn").Count -gt 0 -and
            $p.PSObject.Properties.Match("optionsMap").Count -gt 0)
        if ($pType -eq "dropdown" -or ($pType -eq "select" -and ($hasDirectOptions -or $hasDependentOptions))) {
            $dyn = if ($p.PSObject.Properties.Match("dynamic").Count -gt 0) { $p.dynamic } else { $null }
            $isDynamic = $pType -eq "dropdown" -and (($dyn -eq $true) -or ($dyn -is [string] -and $dyn.Trim().ToLower() -eq "true"))

            if ($isDynamic) {
                $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
                $ctrl = New-Object System.Windows.Controls.ComboBox -Property @{ Height = 35; Width = if ($isInline) { 135 }else { 560 }; VerticalContentAlignment = "Center"; Padding = "8,0,8,0"; Margin = "0,0,5,0" }
                $btnRefresh = New-Object System.Windows.Controls.Button -Property @{
                    Content = "Refresh"; Width = 100; Height = 35; Background = "#475569"; Foreground = "White"; FontWeight = "Bold"
                }
                $btnRefresh.Style = $window.Resources["VisibleDisabledButton"]
                $moduleRef = $m; $paramRef = $p; $comboRef = $ctrl
                $btnRefresh.Add_Click({ Populate-DynamicDropdown -combo $comboRef -param $paramRef -module $moduleRef }.GetNewClosure())
                [void]$stack.Children.Add($ctrl); [void]$stack.Children.Add($btnRefresh)
                $elementStack.Children.Add($stack) | Out-Null
                Populate-DynamicDropdown -combo $ctrl -param $p -module $m
                $script:InputControls[$p.name] = $ctrl
                continue
            }
            $ctrl = New-Object System.Windows.Controls.ComboBox -Property @{ Height = 35; VerticalContentAlignment = "Center"; Padding = "8,0,8,0" }
            if ($hasDirectOptions) {
                Initialize-ManifestChoiceControl -Combo $ctrl -Param $p -HonorDefault:($pType -eq "select")
            }
            $elementStack.Children.Add($ctrl) | Out-Null
            $script:InputControls[$p.name] = $ctrl
            continue
        }

        # ---------------- BROWSE (DRIVE/FOLDER/FILE) ----------------
        if ($pType -in @("drive", "folder", "file")) {
            $stack = New-Object System.Windows.Controls.StackPanel -Property @{ Orientation = "Horizontal" }
            $ctrl = New-Object System.Windows.Controls.TextBox -Property @{
                Text = (Resolve-ParamDefault $p.default $m); Height = 35; Width = if ($isInline) { 135 }else { 560 }; VerticalContentAlignment = "Center"; Padding = "8"; Margin = "0,0,5,0"
            }
            $btn = New-Object System.Windows.Controls.Button -Property @{ Content = "Browse"; Width = 100; Height = 35; Background = "#475569"; Foreground = "White"; FontWeight = "Bold" }
            $btn.Style = $window.Resources["VisibleDisabledButton"]
            $t = $ctrl; $bt = $pType; $pFilter = if ($p.PSObject.Properties.Match("filter").Count -gt 0) { $p.filter } else { "All Files|*.*" }
            $btn.Add_Click({
                    if ($bt -eq "drive") { $r = Select-DriveLetterDialog; if ($r) { $t.Text = $r } }
                    elseif ($bt -eq "folder") { $d = New-Object System.Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq "OK") { $t.Text = $d.SelectedPath } }
                    elseif ($bt -eq "file") { $d = New-Object Microsoft.Win32.OpenFileDialog; $d.Filter = $pFilter; if ($d.ShowDialog()) { $t.Text = $d.FileName } }
                }.GetNewClosure())
            [void]$stack.Children.Add($ctrl); [void]$stack.Children.Add($btn)
            $elementStack.Children.Add($stack) | Out-Null
            $script:InputControls[$p.name] = $ctrl
            continue
        }

        # ---------------- DEFAULT TEXTBOX ----------------
        $ctrl = New-Object System.Windows.Controls.TextBox -Property @{
            Text = (Resolve-ParamDefault $p.default $m); Height = 35; VerticalContentAlignment = "Center"; Padding = "8"
        }
        $elementStack.Children.Add($ctrl) | Out-Null
        $script:InputControls[$p.name] = $ctrl
    }

    # Finalize Rules for Checkbox dependencies
    $script:__DisableRulesBusy = $false
    foreach ($pp in $m.Params) {
        $n = if ($pp.PSObject.Properties.Match('name').Count -gt 0) { $pp.name } else { "" }
        if ($pp.type -eq "checkbox" -and $script:InputControls.ContainsKey($n)) {
            $mRef = $m
            $script:InputControls[$n].Add_Checked({ Update-DisableRules -module $mRef }.GetNewClosure())
            $script:InputControls[$n].Add_Unchecked({ Update-DisableRules -module $mRef }.GetNewClosure())
        }

        if (-not $script:InputControls.ContainsKey($n)) { continue }
        $conditionControl = $script:InputControls[$n]
        $conditionModuleRef = $m
        if ($conditionControl -is [System.Windows.Controls.ComboBox]) {
            $conditionControl.Add_SelectionChanged({ Update-ManifestUiRules -Module $conditionModuleRef }.GetNewClosure())
        } elseif ($conditionControl -is [System.Windows.Controls.CheckBox]) {
            $conditionControl.Add_Checked({ Update-ManifestUiRules -Module $conditionModuleRef }.GetNewClosure())
            $conditionControl.Add_Unchecked({ Update-ManifestUiRules -Module $conditionModuleRef }.GetNewClosure())
        }
    }
    Update-DisableRules -module $m
    $script:ManifestUiRulesBusy = $false
    Update-ManifestUiRules -Module $m
}

# Populate-DynamicDropdown
function Populate-DynamicDropdown {
    param($combo, $param, $module)

    $combo.Items.Clear()

    if (-not $param.populateScript) {
        [void]$combo.Items.Add("ERROR: No populate script specified")
        return
    }

    $moduleDir = Split-Path -Parent $module.RunPath
    $populateScriptPath = Join-Path $moduleDir $param.populateScript

    if (-not (Test-Path -LiteralPath $populateScriptPath)) {
        [void]$combo.Items.Add("ERROR: Script not found - $($param.populateScript)")
        return
    }

    try {
        # Show loading indicator
        $combo.Items.Clear()
        [void]$combo.Items.Add("Loading...")
        $combo.SelectedIndex = 0

        # Force UI update
        [System.Windows.Forms.Application]::DoEvents()

        # Build a splat hashtable (MOST RELIABLE)
        $splat = @{}

        if ($param.populateArgs) {
            foreach ($argName in $param.populateArgs) {

                if (-not $script:InputControls.ContainsKey($argName)) { continue }
                $ctrl = $script:InputControls[$argName]

                if ($ctrl -is [System.Windows.Controls.CheckBox]) {
                    # Pass a REAL boolean. Works for [bool] and [switch] params.
                    $splat[$argName] = [bool]($ctrl.IsChecked -eq $true)
                } elseif ($ctrl -is [System.Windows.Controls.ComboBox]) {
                    if ($ctrl.SelectedItem) {
                        $splat[$argName] = $ctrl.SelectedItem.ToString()
                    }
                } else {
                    # TextBox / file path: only include if not empty
                    $textValue = (($ctrl.Text + "")).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($textValue)) {
                        $splat[$argName] = $textValue
                    }
                }
            }
        }

        # Execute and force array output
        $options = @(& $populateScriptPath @splat)

        $combo.Items.Clear()

        $added = 0
        foreach ($o in $options) {
            if ($null -eq $o) { continue }
            $s = $o.ToString().Trim()
            if ($s.Length -eq 0) { continue }
            [void]$combo.Items.Add($s)
            $added++
        }

        if ($added -le 0) {
            [void]$combo.Items.Add("No options available")
            $combo.SelectedIndex = 0
            return
        }

        # Select default/first
        if ($param.default) {
            $idx = $combo.Items.IndexOf($param.default)
            if ($idx -ge 0) { $combo.SelectedIndex = $idx }
            else { $combo.SelectedIndex = 0 }
        } else {
            $combo.SelectedIndex = 0
        }
    } catch {
        $errText = ($_ | Out-String).Trim()

        # Print full details to console so you can copy
        try {
            if ($script:Console) {
                $script:Console.WriteLine("=== Dynamic Dropdown Error ($($param.name)) ===", "Error")
                $script:Console.WriteLine("Script: $populateScriptPath", "Error")
                $script:Console.WriteLine("Splat : $($splat.Keys | ForEach-Object { "$_=$($splat[$_])" } -join '; ')", "Error")
                $script:Console.WriteLine($errText, "Error")
                $script:Console.WriteLine("=============================================", "Error")
            }
        } catch {}

        $combo.Items.Clear()
        [void]$combo.Items.Add("ERROR: Failed to load options (see output window)")
        $combo.SelectedIndex = 0
    }
}

# ====================== HANDLERS ======================
$btnReload.Add_Click({
        $script:Console.WriteLine("Reloading modules...", "Info")
        $all = Get-ToolkitModules
        Update-TreeView $all
        $txtStatus.Text = "Loaded $($all.Count) modules."
        $script:Console.WriteLine("Successfully loaded $($all.Count) modules.", "Success")
        Show-WelcomeMessage
    })

$tvModules.Add_SelectedItemChanged({
        if ($tvModules.SelectedItem -and $tvModules.SelectedItem.Tag) {
            Render-ModuleUI -m $tvModules.SelectedItem.Tag
        }
    })

$btnClear.Add_Click({
        $script:Console.Clear()
    })

$btnStop.Add_Click({
        if ($script:ActivePowerShell) {
            $script:Console.WriteLine("STOPPING...", "Warning")

            $script:ActivePowerShell.Stop()

            if ($script:OutputTimer) {
                $script:OutputTimer.Stop()
                $script:OutputTimer = $null
            }

            # Never terminate processes globally by executable name; unrelated system processes may be running.

            if ($script:ActivePowerShell) {
                $script:ActivePowerShell.Dispose()
                $script:ActivePowerShell = $null
            }
            $script:AsyncHandle = $null

            $btnRun.IsEnabled = $true
            $btnStop.IsEnabled = $false
            $btnReload.IsEnabled = $true
            $btnClear.IsEnabled = $true
            Hide-Progress
            $script:Console.WriteLine("STOPPED by user.", "Error")
        }
    })

$txtSearch.Add_TextChanged({
        $f = $txtSearch.Text.Trim()
        $all = Get-ToolkitModules | Where-Object { $_.Name -match $f -or $_.Category -match $f }
        Update-TreeView $all $f
    })

$btnRun.Add_Click({
        $m = $tvModules.SelectedItem.Tag
        if (!$m) {
            $script:Console.WriteLine("No module selected!", "Error")
            return
        }

        $missingRequired = Get-MissingRequiredParameter -Module $m
        if ($null -ne $missingRequired) {
            $param = $missingRequired.Param
            $label = if ($param.PSObject.Properties.Match("label").Count -gt 0 -and $param.label) { [string]$param.label } else { [string]$param.name }
            $message = "Please provide a value for the required field: $label"
            $script:Console.WriteLine($message, "Error")
            [System.Windows.MessageBox]::Show($message, "Required Input", "OK", "Warning") | Out-Null
            if ($missingRequired.Control) { [void]$missingRequired.Control.Focus() }
            return
        }

        Execute-CommandAsync -fullCmd "" -displayName $m.Name
    })

# ======================= START ======================
$all = Get-ToolkitModules
Update-TreeView $all
$txtStatus.Text = "Loaded $($all.Count) modules."
Show-WelcomeMessage
$window.ShowDialog() | Out-Null
