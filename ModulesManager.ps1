<#
.SYNOPSIS
    IT Swiss-Army Knife - Modules Manager
.DESCRIPTION
    GUI tool to manage modules: arrange, rename, add/remove modules and categories.
    Changes are saved to module.json files.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Load Windows API Code Pack for modern folder dialog
$code = @"
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
internal class FileOpenDialogInternal { }

[ComImport]
[Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IFileOpenDialog
{
    [PreserveSig] int Show([In] IntPtr parent);
    void SetFileTypes();
    void SetFileTypeIndex([In] uint iFileType);
    void GetFileTypeIndex(out uint piFileType);
    void Advise();
    void Unadvise();
    void SetOptions([In] uint fos);
    void GetOptions(out uint pfos);
    void SetDefaultFolder(IShellItem psi);
    void SetFolder(IShellItem psi);
    void GetFolder(out IShellItem ppsi);
    void GetCurrentSelection(out IShellItem ppsi);
    void SetFileName([In, MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
    void SetTitle([In, MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
    void SetOkButtonLabel([In, MarshalAs(UnmanagedType.LPWStr)] string pszText);
    void SetFileNameLabel([In, MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
    void GetResult(out IShellItem ppsi);
    void AddPlace(IShellItem psi, int alignment);
    void SetDefaultExtension([In, MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
    void Close(int hr);
    void SetClientGuid();
    void ClearClientData();
    void SetFilter([MarshalAs(UnmanagedType.Interface)] IntPtr pFilter);
    void GetResults();
    void GetSelectedItems();
}

[ComImport]
[Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IShellItem
{
    void BindToHandler();
    void GetParent();
    void GetDisplayName([In] uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
    void GetAttributes();
    void Compare();
}

public class FolderPicker
{
    public static string SelectFolder(string title)
    {
        var dialog = (IFileOpenDialog)new FileOpenDialogInternal();
        dialog.SetOptions(0x20); // FOS_PICKFOLDERS
        dialog.SetTitle(title);

        if (dialog.Show(IntPtr.Zero) == 0)
        {
            IShellItem item;
            dialog.GetResult(out item);
            string path;
            item.GetDisplayName(0x80058000, out path);
            return path;
        }
        return null;
    }
}
"@

try {
    Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop
    $script:UseModernDialog = $true
}
catch {
    $script:UseModernDialog = $false
}

function Select-FolderDialog {
    param([string]$Title = "Select Folder")

    if ($script:UseModernDialog) {
        try {
            return [FolderPicker]::SelectFolder($Title)
        }
        catch { }
    }

    # Fallback to Shell.Application
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.BrowseForFolder(0, $Title, 0x50, 0)
    if ($folder) {
        return $folder.Self.Path
    }
    return $null
}

# ====================== XAML GUI ======================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="IT Swiss-Army Knife - Modules Manager" Height="700" Width="1000" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Background="#1e1e1e">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#3B82F6" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="FontWeight" Value="Bold" />
            <Setter Property="Padding" Value="12,6" />
            <Setter Property="Margin" Value="3" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Cursor" Value="Hand" />
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2d2d2d" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderBrush" Value="#444" />
            <Setter Property="Padding" Value="8,5" />
            <Setter Property="Margin" Value="3" />
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="#252526" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderBrush" Value="#444" />
        </Style>
        <Style TargetType="TreeView">
            <Setter Property="Background" Value="#252526" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderBrush" Value="#444" />
        </Style>
    </Window.Resources>
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>
        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,8">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,10,0">
                <TextBlock Text="Modules Manager" FontSize="24" FontWeight="Bold" Foreground="#3B82F6" />
                <TextBlock Text="Organize, rename, and manage your toolkit modules" Foreground="#888" Margin="0,2,0,6" />
            </StackPanel>
            <Image x:Name="imgLogo" Grid.Row="0" Grid.Column="1" Width="140" Height="50" Margin="10,0,0,0" Stretch="Uniform" VerticalAlignment="Top" />
            <Grid Grid.Row="1" Grid.ColumnSpan="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="100" />
                    <ColumnDefinition Width="100" />
                </Grid.ColumnDefinitions>
                <TextBox x:Name="txtModulesPath" Grid.Column="0" IsReadOnly="True" Text="Select modules folder..." Margin="0,15,5,5" />
                <Button x:Name="btnBrowse" Grid.Column="1" Content="Browse" Width="100" Height="28" Margin="0,15,5,5" />
                <Button x:Name="btnRefresh" Grid.Column="2" Content="Refresh" Width="100" Height="28" Margin="0,15,0,5" />
            </Grid>
        </Grid>
        <!-- Main Content -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="350" />
                <ColumnDefinition Width="Auto" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>
            <!-- Left Panel: Tree View -->
            <Grid Grid.Column="0" Margin="0,0,10,0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="Categories and Modules" FontWeight="Bold" Foreground="White" Margin="0,0,0,8" />
                <Border Grid.Row="1" Background="#252526" CornerRadius="8" Padding="15">
                    <TreeView x:Name="treeModules" Background="Transparent" BorderThickness="0">
                        <TreeView.ItemContainerStyle>
                            <Style TargetType="TreeViewItem">
                                <Setter Property="Foreground" Value="White" />
                                <Setter Property="FontSize" Value="13" />
                                <Setter Property="Padding" Value="3" />
                                <Setter Property="IsExpanded" Value="True" />
                            </Style>
                        </TreeView.ItemContainerStyle>
                    </TreeView>
                </Border>
            </Grid>
            <!-- Middle: Move Buttons -->
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                <Button x:Name="btnMoveUp" Width="40" Height="35" ToolTip="Move Up">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Grid>
                                <!-- Up Arrow -->
                                <Path x:Name="Arrow" Fill="#007ACC" Data="M 20 0 L 40 35 L 0 35 Z" />
                            </Grid>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="Arrow" Property="Fill" Value="#3399FF" />
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="Arrow" Property="Fill" Value="#005A9E" />
                                </Trigger>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter TargetName="Arrow" Property="Fill" Value="#555" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                <Button x:Name="btnMoveDown" Width="40" Height="35" ToolTip="Move Down">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Grid>
                                <!-- Down Arrow -->
                                <Path x:Name="Arrow" Fill="#007ACC" Data="M 0 0 L 40 0 L 20 35 Z" />
                            </Grid>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="Arrow" Property="Fill" Value="#3399FF" />
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="Arrow" Property="Fill" Value="#005A9E" />
                                </Trigger>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter TargetName="Arrow" Property="Fill" Value="#555" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                <Button x:Name="btnMoveToCategory" Width="60" Height="35" ToolTip="Move to Category">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="Border" Background="#2D2D30" BorderBrush="#555" BorderThickness="1" CornerRadius="6">
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                                    <!-- Text -->
                                    <TextBlock Text="Move" Foreground="White" VerticalAlignment="Center" />
                                </StackPanel>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="Border" Property="Background" Value="#3A3A3D" />
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="Border" Property="Background" Value="#007ACC" />
                                </Trigger>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter TargetName="Border" Property="Opacity" Value="0.5" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </StackPanel>
            <!-- Right Panel: Edit Details -->
            <Grid Grid.Column="2" Margin="10,0,0,0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="*" />
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="Edit Selected Item" FontWeight="Bold" Foreground="White" Margin="0,0,0,8" />
                <Border Grid.Row="1" Background="#252526" CornerRadius="8" Padding="15">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="pnlDetails">
                            <TextBlock Text="Nothing selected" Foreground="#666" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,50,0,0" />
                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </Grid>
        </Grid>
        <!-- Footer -->
        <Grid Grid.Row="2" Margin="0,15,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>
            <!-- Left: Tree action buttons -->
            <StackPanel Grid.Column="0" Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Left">
                <Button x:Name="btnAddCategory" Content="+ Category" Width="90" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#10B981" />
                <Button x:Name="btnAddModule" Content="+ Module" Width="90" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#10B981" />
                <Button x:Name="btnDelete" Content="Delete" Width="67" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#EF4444" />
                <Button x:Name="btnRestore" Content="Restore" Width="67" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#1d3ecf" />
            </StackPanel>
            <!-- Right: Save action buttons -->
            <StackPanel Grid.Column="1" Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="btnApply" Content="Apply Changes" Width="117" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#10B981" />
                <Button x:Name="btnSaveCategories" Content="Save Categories Only" Width="150" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#3B82F6" />
                <Button x:Name="btnSave" Content="Save All" Width="117" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#F59E0B" />
                <Button x:Name="btnCancel" Content="Cancel" Width="117" Height="30" Padding="0" VerticalContentAlignment="Center" Background="#6B7280" />
            </StackPanel>
            <!-- Status text under right buttons -->
            <TextBlock x:Name="txtStatus" Grid.Column="1" Grid.Row="1" Foreground="#888" HorizontalAlignment="Right" Margin="0,5,0,0" />
        </Grid>
    </Grid>
</Window>
"@

# Parse XAML
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$txtModulesPath = $window.FindName("txtModulesPath")
$btnBrowse = $window.FindName("btnBrowse")
$btnRefresh = $window.FindName("btnRefresh")
$treeModules = $window.FindName("treeModules")
$btnAddCategory = $window.FindName("btnAddCategory")
$btnAddModule = $window.FindName("btnAddModule")
$btnDelete = $window.FindName("btnDelete")
$btnRestore = $window.FindName("btnRestore")
$btnMoveUp = $window.FindName("btnMoveUp")
$btnMoveDown = $window.FindName("btnMoveDown")
$btnMoveToCategory = $window.FindName("btnMoveToCategory")
$pnlDetails = $window.FindName("pnlDetails")
$txtStatus = $window.FindName("txtStatus")
$btnApply = $window.FindName("btnApply")
$btnSave = $window.FindName("btnSave")
$btnCancel = $window.FindName("btnCancel")
$btnSaveCategories = $window.FindName("btnSaveCategories")
$imgLogo = $window.FindName("imgLogo")

if ($null -ne $imgLogo) {
    $logoPath = Join-Path $PSScriptRoot "pics\\techputno-1_white.png"
    if (Test-Path -LiteralPath $logoPath) {
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.UriSource = [Uri]$logoPath
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.EndInit()
            $bmp.Freeze()
            $imgLogo.Source = $bmp
        }
        catch {
            Write-Host "Warning: failed to load logo image: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Warning: logo image not found at $logoPath" -ForegroundColor Yellow
    }
}

# ====================== DATA STRUCTURES ======================
$script:ModulesPath = ""
$script:Categories = @{}  # CategoryName -> @{ Order, Modules = @() }
$script:OriginalData = @{}  # For tracking changes
$script:HasChanges = $false
$script:HasCategoryChanges = $false
$script:HasModuleChanges = $false
$script:ModuleJsonCache = @{}  # FilePath -> @{ LastWriteTime; Json }
$script:CategoriesDirty = $true
$script:SortedCategoriesCache = @()
$script:ModulesDirty = @{}  # CategoryName -> $true
$script:SortedModulesCache = @{}  # CategoryName -> @()
$script:PendingRefresh = $false
$script:ModuleDirtyMap = @{}  # FilePath -> $true
$script:SelectedItem = $null

# ====================== HELPER FUNCTIONS ======================
function Normalize-ModuleOrders {
    param([string]$CategoryName)

    if ([string]::IsNullOrWhiteSpace($CategoryName)) { return }
    if ($null -eq $script:Categories) { return }
    if (-not $script:Categories.ContainsKey($CategoryName)) { return }
    if ($null -eq $script:Categories[$CategoryName].Modules) { $script:Categories[$CategoryName].Modules = @() }

    $mods = @(
        $script:Categories[$CategoryName].Modules |
        Sort-Object { [int]$_.Order }, { $_.Name }
    )

    for ($i = 0; $i -lt $mods.Count; $i++) {
        $mods[$i].Order = $i + 1
    }

    $script:Categories[$CategoryName].Modules = $mods
    Mark-CategoryModulesDirty -CategoryName $CategoryName
}

function Mark-CategoriesDirty {
    $script:CategoriesDirty = $true
}

function Mark-ModulesDirty {
    param([string]$CategoryName)
    if ([string]::IsNullOrWhiteSpace($CategoryName)) { return }
    $script:ModulesDirty[$CategoryName] = $true
}

function Mark-CategoryModulesDirty {
    param([string]$CategoryName)
    if ([string]::IsNullOrWhiteSpace($CategoryName)) { return }
    if (-not $script:Categories.ContainsKey($CategoryName)) { return }
    foreach ($m in @($script:Categories[$CategoryName].Modules)) {
        if ($m.FilePath) { Mark-ModuleDirty -FilePath $m.FilePath }
    }
}

function Mark-ModuleDirty {
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return }
    $script:ModuleDirtyMap[$FilePath] = $true
}

function Clear-ModuleDirty {
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return }
    if ($script:ModuleDirtyMap.ContainsKey($FilePath)) {
        $script:ModuleDirtyMap.Remove($FilePath)
    }
}

function Is-ModuleDirty {
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return $false }
    return $script:ModuleDirtyMap.ContainsKey($FilePath)
}

function Get-SortedCategories {
    if ($script:CategoriesDirty -or $null -eq $script:SortedCategoriesCache -or $script:SortedCategoriesCache.Count -eq 0) {
        $script:SortedCategoriesCache = @(
            $script:Categories.GetEnumerator() | Sort-Object { $_.Value.Order }, { $_.Key }
        )
        $script:CategoriesDirty = $false
    }
    return $script:SortedCategoriesCache
}

function Get-SortedModules {
    param([string]$CategoryName)

    if ([string]::IsNullOrWhiteSpace($CategoryName)) { return @() }
    if (-not $script:Categories.ContainsKey($CategoryName)) { return @() }

    $needsSort = $true
    if ($script:SortedModulesCache.ContainsKey($CategoryName)) {
        $needsSort = $script:ModulesDirty.ContainsKey($CategoryName) -and $script:ModulesDirty[$CategoryName]
        if (-not $needsSort) { return $script:SortedModulesCache[$CategoryName] }
    }

    $mods = @($script:Categories[$CategoryName].Modules | Sort-Object { [int]$_.Order }, { $_.Name })
    $script:SortedModulesCache[$CategoryName] = $mods
    $script:ModulesDirty[$CategoryName] = $false
    return $mods
}

function Request-TreeRefresh {
    if ($script:PendingRefresh -or $null -eq $window) { return }
    $script:PendingRefresh = $true
    $window.Dispatcher.BeginInvoke([System.Action] {
            $script:PendingRefresh = $false
            Refresh-TreeView
        }) | Out-Null
}

function Get-ModuleJsonCached {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $info = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $info) { return $null }

    if ($script:ModuleJsonCache.ContainsKey($Path)) {
        $cached = $script:ModuleJsonCache[$Path]
        if ($cached -and $cached.LastWriteTime -ge $info.LastWriteTimeUtc) {
            return $cached.Json
        }
    }

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $script:ModuleJsonCache[$Path] = @{
        LastWriteTime = $info.LastWriteTimeUtc
        Json          = $json
    }
    return $json
}

function Set-ModuleJsonCache {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$JsonObj
    )

    $ts = [datetime]::UtcNow
    if (Test-Path -LiteralPath $Path) {
        $ts = (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    }

    $script:ModuleJsonCache[$Path] = @{
        LastWriteTime = $ts
        Json          = $JsonObj
    }
}

function Move-ModuleJsonCacheEntry {
    param(
        [Parameter(Mandatory = $true)][string]$OldPath,
        [Parameter(Mandatory = $true)][string]$NewPath
    )

    if ($script:ModuleJsonCache.ContainsKey($OldPath)) {
        $script:ModuleJsonCache[$NewPath] = $script:ModuleJsonCache[$OldPath]
        $script:ModuleJsonCache.Remove($OldPath)
    }
}
function ConvertTo-Brush {
    param([string]$Color)

    try {
        return ([System.Windows.Media.BrushConverter]::new()).ConvertFromString($Color)
    }
    catch {
        return [System.Windows.Media.Brushes]::Gray
    }
}

function Set-Status {
    param([string]$Message, [string]$Color = "#888")
    $txtStatus.Text = $Message
    $txtStatus.Foreground = ConvertTo-Brush $Color
}

function Write-CategoriesJson {
    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        throw "ModulesPath is empty."
    }

    $path = Join-Path $script:ModulesPath "categories.json"

    if ($null -eq $script:Categories -or -not ($script:Categories -is [hashtable])) {
        throw "Categories collection is missing or invalid."
    }

    $categoriesList = @()
    foreach ($cat in $script:Categories.GetEnumerator()) {
        $categoriesList += [PSCustomObject]@{
            Name          = [string]$cat.Key
            CategoryOrder = [int]$cat.Value.Order
        }
    }

    $categoriesList = $categoriesList | Sort-Object CategoryOrder, Name

    $obj = [PSCustomObject]@{ Categories = $categoriesList }

    $jsonText = $obj | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $jsonText -Encoding UTF8 -Force -ErrorAction Stop
}

function Set-HasChanges {
    param(
        [bool]$Value,
        [ValidateSet("All", "Category", "Module")][string]$ChangeType = "All"
    )

    if ($Value) {
        switch ($ChangeType) {
            "Category" { $script:HasCategoryChanges = $true; Mark-CategoriesDirty }
            "Module" { $script:HasModuleChanges = $true }
            "All" {
                $script:HasCategoryChanges = $true; Mark-CategoriesDirty
                $script:HasModuleChanges = $true
            }
        }
    }
    else {
        switch ($ChangeType) {
            "Category" { $script:HasCategoryChanges = $false }
            "Module" { $script:HasModuleChanges = $false }
            "All" {
                $script:HasCategoryChanges = $false
                $script:HasModuleChanges = $false
            }
        }
    }

    $script:HasChanges = ($script:HasCategoryChanges -or $script:HasModuleChanges)
    if ($script:HasChanges) {
        $window.Title = "IT Swiss-Army Knife - Modules Manager *"
        Set-Status "Unsaved changes" "#F59E0B"
    }
    else {
        $window.Title = "IT Swiss-Army Knife - Modules Manager"
        Set-Status "All changes saved" "#10B981"
    }
}

function Get-ModuleOrder {
    param($Module)
    if ($Module.Order) { return [int]$Module.Order }
    if ($Module.Name -match '^(\d+)-?\s*') { return [int]$Matches[1] }
    return 999
}

function Load-CategoriesJson {
    $script:CategoriesJsonPath = Join-Path $script:ModulesPath "categories.json"
    $script:CategoryOrderMap = @{}

    if (Test-Path -LiteralPath $script:CategoriesJsonPath) {
        try {
            $json = Get-Content -LiteralPath $script:CategoriesJsonPath -Raw | ConvertFrom-Json
            if ($json -and $json.Categories) {
                foreach ($cat in $json.Categories) {
                    $name = [string]$cat.Name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }

                    $order = 999
                    if ($cat.PSObject.Properties["CategoryOrder"]) {
                        $order = [int]$cat.CategoryOrder
                    }
                    elseif ($cat.PSObject.Properties["Order"]) {
                        # Backward compatibility if you ever saved Order
                        $order = [int]$cat.Order
                    }

                    $script:CategoryOrderMap[$name] = $order
                }
            }
        }
        catch {
            Write-Host "Error loading categories.json: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Load-Modules {
    $script:Categories = @{}
    $script:ModuleJsonCache = @{}
    $script:SortedCategoriesCache = @()
    $script:SortedModulesCache = @{}
    $script:ModulesDirty = @{}
    $script:ModuleDirtyMap = @{}

    if (-not $script:ModulesPath -or -not (Test-Path -LiteralPath $script:ModulesPath)) {
        Set-Status "Invalid modules path" "#EF4444"
        return
    }

    # 1) Load categories.json first
    Load-CategoriesJson

    # 2) Create ALL categories from categories.json even if empty / no folder
    foreach ($catName in ($script:CategoryOrderMap.Keys | Sort-Object)) {
        $script:Categories[$catName] = @{
            Order        = [int]$script:CategoryOrderMap[$catName]
            OriginalName = $catName
            Modules      = @()
            IsNew        = $false
        }
    }

    # 3) Scan all module.json files
    $moduleFiles = Get-ChildItem -Path $script:ModulesPath -Recurse -Filter "module.json" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '\\_deleted\\' -and
        $_.FullName -notmatch '/_deleted/'   # safe for any slash style
    }


    foreach ($file in $moduleFiles) {
        try {
            $json = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            Set-ModuleJsonCache -Path $file.FullName -JsonObj $json
            $categoryName = if ($json.Category) { [string]$json.Category } else { "Uncategorized" }

            $infoDesc = $null
            if ($json.Params) {
                foreach ($p in $json.Params) {
                    if ($p -and $p.Name -eq "InfoNote" -and $p.Type -eq "info") {
                        $infoDesc = [string]$p.Default
                        break
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($infoDesc)) {
                $infoDesc = $json.Description
            }

            if (-not $script:Categories.ContainsKey($categoryName)) {
                $catOrder = 999
                if ($script:CategoryOrderMap -and $script:CategoryOrderMap.ContainsKey($categoryName)) {
                    $catOrder = [int]$script:CategoryOrderMap[$categoryName]
                }

                $script:Categories[$categoryName] = @{
                    Order        = $catOrder
                    OriginalName = $categoryName
                    Modules      = @()
                    IsNew        = $false
                }
            }

            $modObj = @{
                Id               = $json.Id
                Name             = $json.Name
                OriginalName     = $json.Name
                Description      = $infoDesc
                Category         = $categoryName
                OriginalCategory = $categoryName
                Order            = if ($json.Order) { [int]$json.Order } else { Get-ModuleOrder -Module $json }
                FilePath         = $file.FullName
                Json             = $json
            }
            $script:Categories[$categoryName].Modules += $modObj
            Clear-ModuleDirty -FilePath $file.FullName
        }
        catch {
            Write-Host "Error loading $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Sort modules within each category
    foreach ($cat in $script:Categories.Keys) {
        $script:Categories[$cat].Modules = @($script:Categories[$cat].Modules | Sort-Object { [int]$_.Order })
        Mark-ModulesDirty -CategoryName $cat
    }

    Set-Status "Loaded $($moduleFiles.Count) modules" "#10B981"
    Mark-CategoriesDirty
    Request-TreeRefresh
}

function Refresh-TreeView {
    Write-Host "=== Refresh-TreeView called ===" -ForegroundColor Gray
    Write-Host "Categories count: $($script:Categories.Count)" -ForegroundColor Gray

    $treeModules.Items.Clear()

    if ($null -eq $script:Categories) { return }

    # Sort categories by display order
    $sortedCategories = Get-SortedCategories

    foreach ($cat in $sortedCategories) {

        $catName = [string]$cat.Key
        $catData = $cat.Value
        $modules = @(Get-SortedModules -CategoryName $catName)
        $isEmpty = ($modules.Count -eq 0)
        $isNew = $catData.IsNew -eq $true

        # Check directory existence
        $catDir = Join-Path $script:ModulesPath $catName
        $hasDir = (Test-Path -LiteralPath $catDir -PathType Container)

        # Build suffix label
        $suffix = @()
        if ($isNew) { $suffix += "New - Unsaved" }
        elseif ($isEmpty) { $suffix += "Empty" }
        if (-not $hasDir -and -not $isNew) { $suffix += "No Directory" }

        $suffixText = if ($suffix.Count -gt 0) {
            " (" + ($suffix -join " - ") + ")"
        }
        else {
            ""
        }

        # Category Tree Item
        $catItem = New-Object System.Windows.Controls.TreeViewItem
        $catItem.Header = "{0}- {1}{2}" -f $catData.Order, $catName, $suffixText
        $catItem.Tag = @{
            Type = "Category"
            Name = $catName
            Data = $catData
        }
        $catItem.FontWeight = "Bold"

        # Visual cue for new/missing folder
        if ($isNew) {
            $catItem.Foreground = [System.Windows.Media.Brushes]::LimeGreen
        }
        elseif (-not $hasDir) {
            $catItem.Foreground = [System.Windows.Media.Brushes]::Orange
        }
        else {
            $catItem.Foreground = [System.Windows.Media.Brushes]::LightBlue
        }

        # Lazy-load module children on expand
        $catItem.Tag.Loaded = $false
        if ($modules.Count -gt 0) {
            $placeholder = New-Object System.Windows.Controls.TreeViewItem
            $placeholder.Header = "Loading..."
            $placeholder.Foreground = [System.Windows.Media.Brushes]::Gray
            $catItem.Items.Add($placeholder) | Out-Null
        }

        $catItem.Add_Expanded({
                $item = $_.Source
                if ($null -eq $item.Tag -or $item.Tag.Type -ne "Category") { return }
                if ($item.Tag.Loaded -eq $true) { return }

                $item.Items.Clear()
                $catNameLocal = [string]$item.Tag.Name
                foreach ($module in (Get-SortedModules -CategoryName $catNameLocal)) {
                    $modItem = New-Object System.Windows.Controls.TreeViewItem

                    # Show "(New)" suffix for unsaved modules
                    $suffix = if ($module.IsNew -eq $true) { " (New)" } else { "" }
                    $modItem.Header = "{0}- {1}{2}" -f $module.Order, $module.Name, $suffix

                    $modItem.Tag = @{
                        Type     = "Module"
                        Data     = $module
                        Category = $catNameLocal
                    }

                    # Green for new, white for existing
                    if ($module.IsNew -eq $true) {
                        $modItem.Foreground = [System.Windows.Media.Brushes]::LimeGreen
                    }
                    else {
                        $modItem.Foreground = [System.Windows.Media.Brushes]::White
                    }

                    $item.Items.Add($modItem) | Out-Null
                }
                $item.Tag.Loaded = $true
            })

        $treeModules.Items.Add($catItem) | Out-Null
    }

    # -------------------- Deleted section --------------------
    $deleted = Get-DeletedItems
    if ($deleted.Count -gt 0) {
        $delRoot = New-Object System.Windows.Controls.TreeViewItem
        $delRoot.Header = "Deleted"
        $delRoot.Tag = @{ Type = "DeletedRoot" }
        $delRoot.FontWeight = "Bold"
        $delRoot.Foreground = [System.Windows.Media.Brushes]::Gray
        $delRoot.IsExpanded = $true

        foreach ($d in $deleted) {
            $item = New-Object System.Windows.Controls.TreeViewItem
            $item.Header = $d.Name
            $item.Tag = @{ Type = "DeletedItem"; Path = $d.FullName }
            $item.Foreground = [System.Windows.Media.Brushes]::DarkGray
            $delRoot.Items.Add($item) | Out-Null
        }

        $treeModules.Items.Add($delRoot) | Out-Null
    }
}
function Show-CategoryDetails {
    param(
        $CategoryData,
        [string]$CategoryName
    )

    $pnlDetails.Children.Clear()

    # Capture stable references for the click handler
    $categoriesRef = $script:Categories
    $categoryKey = [string]$CategoryName

    # UI: Category Name
    $pnlDetails.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{
                Text = "Category Name:"; Foreground = "Gray"; Margin = "0,0,0,5"
            })) | Out-Null

    $txtName = New-Object System.Windows.Controls.TextBox -Property @{
        Text = $CategoryName
        Name = "txtCategoryName"
        Tag  = $CategoryName   # stores OLD name
    }
    $pnlDetails.Children.Add($txtName) | Out-Null

    # UI: Order
    $pnlDetails.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{
                Text = "Display Order:"; Foreground = "Gray"; Margin = "0,15,0,5"
            })) | Out-Null

    $txtOrder = New-Object System.Windows.Controls.TextBox -Property @{
        Text = $CategoryData.Order
        Name = "txtCategoryOrder"
    }
    $pnlDetails.Children.Add($txtOrder) | Out-Null

    # Apply button
    $btnApplyItem = New-Object System.Windows.Controls.Button -Property @{
        Content    = "Apply to Category"
        Margin     = "0,20,0,0"
        Background = "#10B981"
    }

    $btnApplyItem.Add_Click({

            # Validate captured reference
            if ($null -eq $categoriesRef -or -not ($categoriesRef -is [hashtable])) {
                [System.Windows.MessageBox]::Show("Categories collection is not available. Please click Refresh.", "Error")
                return
            }

            $txtNameBox = ($pnlDetails.Children | Where-Object { $_.Name -eq "txtCategoryName" }  | Select-Object -First 1)
            $txtOrderBox = ($pnlDetails.Children | Where-Object { $_.Name -eq "txtCategoryOrder" } | Select-Object -First 1)

            if ($null -eq $txtNameBox -or $null -eq $txtOrderBox) {
                [System.Windows.MessageBox]::Show("Internal UI error: category fields not found.", "Error")
                return
            }

            $newName = [string]$txtNameBox.Text
            if ([string]::IsNullOrWhiteSpace($newName)) {
                [System.Windows.MessageBox]::Show("Category name cannot be empty.", "Invalid Name")
                return
            }
            $newName = $newName.Trim()

            [int]$parsed = 0
            if (-not [int]::TryParse(([string]$txtOrderBox.Text).Trim(), [ref]$parsed)) {
                [System.Windows.MessageBox]::Show("Order must be a number.", "Invalid Order")
                return
            }
            $newOrder = $parsed

            # Determine old name reliably
            $oldName = [string]$txtNameBox.Tag
            if ([string]::IsNullOrWhiteSpace($oldName)) { $oldName = $categoryKey }
            $oldName = $oldName.Trim()

            if ([string]::IsNullOrWhiteSpace($oldName)) {
                [System.Windows.MessageBox]::Show("Cannot determine old category name. Re-select the category and try again.", "Error")
                return
            }

            if (-not $categoriesRef.ContainsKey($oldName)) {
                [System.Windows.MessageBox]::Show("Old category '$oldName' not found. Please Refresh.", "Error")
                return
            }

            # Prevent collisions on rename
            if ($newName -ne $oldName -and $categoriesRef.ContainsKey($newName)) {
                [System.Windows.MessageBox]::Show("A category named '$newName' already exists.", "Rename Error")
                return
            }

            # Always update order (in-memory)
            $data = $categoriesRef[$oldName]
            if ($null -eq $data) {
                [System.Windows.MessageBox]::Show("Internal error: category data is missing. Please Refresh.", "Error")
                return
            }
            if ($null -eq $data.Modules) { $data.Modules = @() }
            $data.Order = $newOrder

            # If rename: rename folder + re-key + update module objects + save to disk
            if ($newName -ne $oldName) {

                # IMPORTANT: Call rename helper ONCE and handle its result
                $r = Rename-CategoryFolderAndFixPaths -OldName $oldName -NewName $newName

                # Support either return style:
                # - new safe style: @{ Ok=...; Message=... }
                # - old style: @{ NewName=... }
                if ($r -is [hashtable] -and $r.ContainsKey("Ok") -and (-not $r.Ok)) {
                    [System.Windows.MessageBox]::Show([string]$r.Message, "Rename Error")
                    return
                }

                if ($r -is [hashtable] -and $r.ContainsKey("NewName") -and -not [string]::IsNullOrWhiteSpace([string]$r.NewName)) {
                    $newName = [string]$r.NewName
                }

                # Re-key the category in the hashtable (use captured reference, not $script:Categories)
                $categoriesRef.Remove($oldName)
                $categoriesRef[$newName] = $data

                # Update module objects (Category + Json.Category)
                foreach ($mod in @($data.Modules)) {
                    $mod.Category = $newName
                    if ($mod.Json) { $mod.Json.Category = $newName }
                }

                # Push back to script scope so other functions see it
                $script:Categories = $categoriesRef
                $script:SortedModulesCache.Remove($oldName)
                $script:ModulesDirty.Remove($oldName)
                Mark-ModulesDirty -CategoryName $newName

                # Persist to disk immediately
                try {
                    Write-CategoriesJson
                    Save-CategoryModulesJson -CategoryName $newName
                }
                catch {
                    [System.Windows.MessageBox]::Show("Saved in memory, but disk save failed:`n$($_.Exception.Message)", "Save Error")
                    Set-HasChanges -Value $true -ChangeType Category
                    Request-TreeRefresh
                    return
                }

                Set-HasChanges -Value $false -ChangeType Category
                Set-Status "Category renamed and saved to disk" "#10B981"
                $txtNameBox.Tag = $newName
                $categoryKey = $newName

                Request-TreeRefresh
                return
            }

            # No rename: order-only update -> persist categories.json now
            $script:Categories = $categoriesRef

            try {
                Write-CategoriesJson
                Set-Status ("categories.json updated: " + (Join-Path $script:ModulesPath "categories.json")) "#10B981"
            }
            catch {
                [System.Windows.MessageBox]::Show(
                    "Failed to update categories.json.`n`nPath:`n$((Join-Path $script:ModulesPath 'categories.json'))`n`nError:`n$($_.Exception.Message)",
                    "Save Error"
                )
                return
            }

            Set-HasChanges -Value $false -ChangeType Category
            Set-Status "Category order updated and saved to disk" "#10B981"
            Request-TreeRefresh


        }.GetNewClosure())

    $pnlDetails.Children.Add($btnApplyItem) | Out-Null
}
function Save-CategoryModulesJson {
    param([Parameter(Mandatory = $true)][string]$CategoryName)

    if ([string]::IsNullOrWhiteSpace($CategoryName)) { return }
    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) { return }
    if ($null -eq $script:Categories -or -not ($script:Categories -is [hashtable])) { return }
    if (-not $script:Categories.ContainsKey($CategoryName)) { return }

    $mods = @($script:Categories[$CategoryName].Modules)
    if ($mods.Count -eq 0) { return }

    foreach ($m in $mods) {
        try {
            if (-not $m.FilePath) { continue }
            if (-not (Test-Path -LiteralPath $m.FilePath)) { continue }

            $json = Get-ModuleJsonCached -Path $m.FilePath
            if ($null -eq $json) { continue }

            # Update category (this covers "category" / "Category" cases)
            if ($json.PSObject.Properties["Category"]) {
                $json.Category = [string]$CategoryName
            }
            elseif ($json.PSObject.Properties["category"]) {
                $json.category = [string]$CategoryName
            }
            else {
                # Add standard property name
                $json | Add-Member -NotePropertyName "Category" -NotePropertyValue ([string]$CategoryName) -Force
            }

            # Optional sync of other fields (safe)
            if ($m.Name) { $json.Name = [string]$m.Name }

            $descText = [string]$m.Description
            if (-not [string]::IsNullOrWhiteSpace($descText)) {
                if ($json.Params) {
                    foreach ($p in $json.Params) {
                        if ($p -and $p.Name -eq "InfoNote" -and $p.Type -eq "info") {
                            $p.Default = $descText
                            $descText = $null
                            break
                        }
                    }
                }

                if ($null -ne $descText) {
                    $json.Description = [string]$descText
                }
            }

            [int]$ord = 0
            if ([int]::TryParse([string]$m.Order, [ref]$ord)) {
                if ($json.PSObject.Properties["Order"]) {
                    $json.Order = $ord
                }
                else {
                    $json | Add-Member -NotePropertyName "Order" -NotePropertyValue $ord -Force
                }
            }

            # Write back
            $json | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $m.FilePath -Encoding UTF8 -Force
            Set-ModuleJsonCache -Path $m.FilePath -JsonObj $json
            Clear-ModuleDirty -FilePath $m.FilePath

            # Keep in-memory copy aligned too
            $m.Json = $json
        }
        catch {
            Write-Host "Failed to update module.json: $($m.FilePath) :: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
function Show-ModuleDetails {
    param($ModuleData)

    $pnlDetails.Children.Clear()

    # Module Name
    $lblName = New-Object System.Windows.Controls.TextBlock
    $lblName.Text = "Module Name:"
    $lblName.Foreground = [System.Windows.Media.Brushes]::Gray
    $lblName.Margin = "0,0,0,5"
    $pnlDetails.Children.Add($lblName)

    $txtName = New-Object System.Windows.Controls.TextBox
    $txtName.Text = $ModuleData.Name
    $txtName.Name = "txtModuleName"
    $pnlDetails.Children.Add($txtName)

    # Module Order
    $lblOrder = New-Object System.Windows.Controls.TextBlock
    $lblOrder.Text = "Display Order:"
    $lblOrder.Foreground = [System.Windows.Media.Brushes]::Gray
    $lblOrder.Margin = "0,15,0,5"
    $pnlDetails.Children.Add($lblOrder)

    $txtOrder = New-Object System.Windows.Controls.TextBox
    $txtOrder.Text = $ModuleData.Order
    $txtOrder.Name = "txtModuleOrder"
    $pnlDetails.Children.Add($txtOrder)

    # Category
    $lblCat = New-Object System.Windows.Controls.TextBlock
    $lblCat.Text = "Category:"
    $lblCat.Foreground = [System.Windows.Media.Brushes]::Gray
    $lblCat.Margin = "0,15,0,5"
    $pnlDetails.Children.Add($lblCat)

    $cmbCategory = New-Object System.Windows.Controls.ComboBox
    $cmbCategory.Name = "cmbModuleCategory"
    $cmbCategory.Background = "#2d2d2d"
    $cmbCategory.Foreground = "Black"
    foreach ($cat in (Get-SortedCategories)) {
        $cmbCategory.Items.Add($cat.Key) | Out-Null
    }
    $cmbCategory.SelectedItem = $ModuleData.Category
    $pnlDetails.Children.Add($cmbCategory)

    # Description
    $lblDesc = New-Object System.Windows.Controls.TextBlock
    $lblDesc.Text = "Description:"
    $lblDesc.Foreground = [System.Windows.Media.Brushes]::Gray
    $lblDesc.Margin = "0,15,0,5"
    $pnlDetails.Children.Add($lblDesc)

    $txtDesc = New-Object System.Windows.Controls.TextBox
    $txtDesc.Text = $ModuleData.Description
    $txtDesc.Name = "txtModuleDesc"
    $txtDesc.TextWrapping = "Wrap"
    $txtDesc.AcceptsReturn = $true
    $txtDesc.Height = 80
    $pnlDetails.Children.Add($txtDesc)

    # File path (readonly)
    $lblPath = New-Object System.Windows.Controls.TextBlock
    $lblPath.Text = "File: $($ModuleData.FilePath)"
    $lblPath.Foreground = [System.Windows.Media.Brushes]::DarkGray
    $lblPath.FontSize = 10
    $lblPath.TextWrapping = "Wrap"
    $lblPath.Margin = "0,15,0,5"
    $pnlDetails.Children.Add($lblPath)

    # Store reference for apply
    $modRef = $ModuleData

    # Apply button for this item
    $btnApplyItem = New-Object System.Windows.Controls.Button
    $btnApplyItem.Content = "Apply to Module"
    $btnApplyItem.Margin = "0,20,0,0"
    $btnApplyItem.Background = "#10B981"
    $btnApplyItem.Add_Click({
            $txtNameBox = ($pnlDetails.Children | Where-Object { $_.Name -eq "txtModuleName" }  | Select-Object -First 1)
            $txtOrderBox = ($pnlDetails.Children | Where-Object { $_.Name -eq "txtModuleOrder" } | Select-Object -First 1)
            $cmbCatBox = ($pnlDetails.Children | Where-Object { $_.Name -eq "cmbModuleCategory" } | Select-Object -First 1)
            $txtDescBox = ($pnlDetails.Children | Where-Object { $_.Name -eq "txtModuleDesc" }  | Select-Object -First 1)

            if ($null -eq $txtNameBox -or $null -eq $txtOrderBox -or $null -eq $cmbCatBox -or $null -eq $txtDescBox) {
                [System.Windows.MessageBox]::Show("Internal UI error: module fields not found.", "Error")
                return
            }

            $newName = [string]$txtNameBox.Text
            if ([string]::IsNullOrWhiteSpace($newName)) {
                [System.Windows.MessageBox]::Show("Module name cannot be empty.", "Invalid Name")
                return
            }
            $newName = $newName.Trim()

            [int]$parsed = 0
            if (-not [int]::TryParse($txtOrderBox.Text.Trim(), [ref]$parsed)) {
                [System.Windows.MessageBox]::Show("Order must be a number.", "Invalid Order")
                return
            }
            $newOrder = $parsed

            $newCategory = [string]$cmbCatBox.SelectedItem
            $newDesc = [string]$txtDescBox.Text

            $oldCategory = [string]$modRef.Category

            # Update module data safely
            $modRef.Name = $newName
            $modRef.Order = $newOrder
            $modRef.Description = $newDesc

            if ($modRef.Json) {
                $modRef.Json.Name = $newName

                $infoNoteUpdated = $false
                if ($modRef.Json.Params) {
                    foreach ($p in $modRef.Json.Params) {
                        if ($p -and $p.Name -eq "InfoNote" -and $p.Type -eq "info") {
                            $p.Default = $newDesc
                            $infoNoteUpdated = $true
                            break
                        }
                    }
                }

                if (-not $infoNoteUpdated) {
                    $modRef.Json.Description = $newDesc
                }
            }

            # Move if category changed
            if ($newCategory -and $newCategory -ne $oldCategory) {
                try {
                    Move-ModuleFolderToCategory -ModuleObj $modRef -SourceCategory $oldCategory -TargetCategory $newCategory
                }
                catch {
                    [System.Windows.MessageBox]::Show("Move failed:`n$($_.Exception.Message)", "Move Error")
                    return
                }

                $script:Categories[$oldCategory].Modules = @(
                    $script:Categories[$oldCategory].Modules | Where-Object { $_.FilePath -ne $modRef.FilePath }
                )

                $modRef.Category = $newCategory
                if ($modRef.Json) { $modRef.Json.Category = $newCategory }

                $script:Categories[$newCategory].Modules += $modRef

                Normalize-ModuleOrders $oldCategory
                Normalize-ModuleOrders $newCategory
                Mark-ModulesDirty -CategoryName $oldCategory
                Mark-ModulesDirty -CategoryName $newCategory

                try {
                    if ($null -eq $modRef.Json) {
                        if ($modRef.FilePath -and (Test-Path -LiteralPath $modRef.FilePath)) {
                            $modRef.Json = Get-ModuleJsonCached -Path $modRef.FilePath
                        }
                        if ($null -eq $modRef.Json) {
                            $modRef.Json = [PSCustomObject]@{
                                Id          = $modRef.Id
                                Name        = $modRef.Name
                                Category    = $newCategory
                                Order       = [int]$modRef.Order
                                Shell       = "Pwsh"
                                Description = $modRef.Description
                                RunPath     = "run.ps1"
                                Params      = @()
                            }
                        }
                    }

                    Save-ModuleJsonOrdered -Path $modRef.FilePath -JsonObj $modRef.Json -Category $newCategory -Order ([int]$modRef.Order)
                    Clear-ModuleDirty -FilePath $modRef.FilePath
                }
                catch {
                    [System.Windows.MessageBox]::Show("Moved, but failed to update module.json:`n$($_.Exception.Message)", "Save Error")
                }
            }
            else {
                Normalize-ModuleOrders $oldCategory
                Mark-ModulesDirty -CategoryName $oldCategory
            }

            Mark-ModuleDirty -FilePath $modRef.FilePath
            Set-HasChanges -Value $true -ChangeType Module
            Request-TreeRefresh
        }.GetNewClosure())

    $pnlDetails.Children.Add($btnApplyItem)
}
function Sanitize-FolderName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }

    $bad = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $bad) { $Name = $Name.Replace([string]$c, "_") }

    return $Name.Trim().TrimEnd(".")
}

function Rename-CategoryFolderAndFixPaths {
    param(
        [Parameter(Mandatory = $true)][string]$OldName,
        [Parameter(Mandatory = $true)][string]$NewName
    )

    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        return @{ Ok = $false; Message = "ModulesPath is empty. Browse to the modules folder first." }
    }

    $safeNew = Sanitize-FolderName $NewName
    if ([string]::IsNullOrWhiteSpace($safeNew)) {
        return @{ Ok = $false; Message = "New category name is empty or invalid." }
    }

    $oldFolder = Join-Path $script:ModulesPath $OldName
    $newFolder = Join-Path $script:ModulesPath $safeNew

    # OLD folder must exist (this is what we rename)
    if (-not (Test-Path -LiteralPath $oldFolder -PathType Container)) {
        return @{ Ok = $false; Message = "Category folder not found: $oldFolder" }
    }

    # NEW folder must NOT exist
    if (Test-Path -LiteralPath $newFolder) {
        return @{ Ok = $false; Message = "Target category folder already exists: $newFolder" }
    }

    if (-not (Test-FolderRenameAccess -FolderPath $oldFolder)) {
        return @{ Ok = $false; Message = "Cannot write inside '$oldFolder'. Something is locking it or permissions are blocked. Close apps using it (Toolkit GUI, VS Code, Explorer), or run as Admin." }
    }

    try {
        Rename-Item -LiteralPath $oldFolder -NewName $safeNew -ErrorAction Stop
    }
    catch {
        $msg = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg += "`n" + $_.Exception.InnerException.Message }
        return @{ Ok = $false; Message = "Rename-Item failed.`nOld: $oldFolder`nNew: $newFolder`n$msg" }
    }

    # Update FilePath for all modules under that old category
    if ($script:Categories -and $script:Categories.ContainsKey($OldName)) {
        foreach ($mod in $script:Categories[$OldName].Modules) {
            if ($mod.FilePath -and $mod.FilePath.StartsWith($oldFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
                $mod.FilePath = $newFolder + $mod.FilePath.Substring($oldFolder.Length)
            }
        }
    }

    return @{ Ok = $true; OldFolder = $oldFolder; NewFolder = $newFolder; NewName = $safeNew }
}
function Test-FolderRenameAccess {
    param([Parameter(Mandatory = $true)][string]$FolderPath)

    try {
        # Create and delete a temp file inside the folder as a quick permission/lock test
        $tmp = Join-Path $FolderPath ("__rename_test_{0}.tmp" -f ([guid]::NewGuid().ToString("N")))
        Set-Content -LiteralPath $tmp -Value "test" -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $tmp -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Ensure-CategoryFolders {
    <#
    .SYNOPSIS
        Creates category folders for any categories marked as IsNew.
        Called during Save operations.
    #>
    $createdCount = 0
    $errors = @()

    # Get category names first to avoid modifying collection during iteration
    $categoryNames = @($script:Categories.Keys)

    foreach ($catName in $categoryNames) {
        $catData = $script:Categories[$catName]

        Write-Host "Checking category '$catName': IsNew = $($catData.IsNew)" -ForegroundColor Yellow

        # Skip if not a new category
        if ($catData.IsNew -ne $true) { continue }

        $catDir = Join-Path $script:ModulesPath $catName
        Write-Host "Creating folder: $catDir" -ForegroundColor Cyan

        # Create folder if it doesn't exist
        if (-not (Test-Path -LiteralPath $catDir -PathType Container)) {
            try {
                New-Item -ItemType Directory -Path $catDir -Force -ErrorAction Stop | Out-Null
                $createdCount++
                Write-Host "Created folder successfully" -ForegroundColor Green
            }
            catch {
                $errors += "Failed to create folder '$catName': $($_.Exception.Message)"
                Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
                continue
            }
        }
        else {
            Write-Host "Folder already exists" -ForegroundColor Yellow
            $createdCount++  # Count it as success since folder exists
        }

        # Clear the IsNew flag after successful folder creation
        $script:Categories[$catName].IsNew = $false
    }

    return @{
        CreatedCount = $createdCount
        Errors       = $errors
    }
}

function Ensure-CategoryFolderExists {
    param([Parameter(Mandatory = $true)][string]$CategoryName)

    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        throw "ModulesPath is empty. Browse to the modules folder first."
    }
    if ([string]::IsNullOrWhiteSpace($CategoryName)) {
        throw "Category name is empty."
    }

    $catDir = Join-Path $script:ModulesPath $CategoryName
    if (-not (Test-Path -LiteralPath $catDir -PathType Container)) {
        New-Item -ItemType Directory -Path $catDir -Force -ErrorAction Stop | Out-Null
    }
    return $catDir
}

function Save-AllModules {
    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        [System.Windows.MessageBox]::Show("Error: Modules path is empty.", "Save Error")
        return
    }

    # First, create any missing category folders for new categories
    $folderResult = Ensure-CategoryFolders
    if ($folderResult.Errors.Count -gt 0) {
        $errMsg = "Some category folders could not be created:`n`n" + ($folderResult.Errors -join "`n")
        [System.Windows.MessageBox]::Show($errMsg, "Folder Creation Errors", "OK", "Warning")
    }

    $savedCount = 0
    $copiedCount = 0

    foreach ($cat in $script:Categories.GetEnumerator()) {
        $categoryName = [string]$cat.Key
        $categoryFolder = Join-Path $script:ModulesPath $categoryName

        foreach ($module in $cat.Value.Modules) {
            try {
                if ($module.FilePath -and -not (Is-ModuleDirty -FilePath $module.FilePath) -and -not $module.IsNew) {
                    continue
                }

                # Handle NEW modules (need to copy folder first)
                if ($module.IsNew -eq $true -and $module.SourcePath) {
                    $moduleFolderName = Split-Path $module.SourcePath -Leaf
                    $destModuleFolder = Join-Path $categoryFolder $moduleFolderName

                    # Ensure category folder exists
                    if (-not (Test-Path -LiteralPath $categoryFolder -PathType Container)) {
                        New-Item -ItemType Directory -Path $categoryFolder -Force -ErrorAction Stop | Out-Null
                    }

                    # Check if already exists
                    if (Test-Path -LiteralPath $destModuleFolder) {
                        Write-Host "Module folder already exists, skipping copy: $destModuleFolder" -ForegroundColor Yellow
                    }
                    else {
                        # Copy module folder
                        Copy-Item -Path $module.SourcePath -Destination $categoryFolder -Recurse -Force -ErrorAction Stop
                        Write-Host "Copied module to: $destModuleFolder" -ForegroundColor Green
                        $copiedCount++
                    }

                    # Update FilePath to new location
                    $module.FilePath = Join-Path $destModuleFolder "module.json"
                    $module.IsNew = $false
                    $module.Remove('SourcePath')
                    Mark-ModuleDirty -FilePath $module.FilePath
                }

                $json = $module.Json

                $json.Name = [string]$module.Name
                $json.Category = [string]$categoryName

                if ($json.PSObject.Properties['Order']) {
                    $json.Order = [int]$module.Order
                }
                else {
                    $json | Add-Member -NotePropertyName "Order" -NotePropertyValue ([int]$module.Order) -Force
                }

                if ($module.Description) {
                    $json.Description = [string]$module.Description
                }

                $json | ConvertTo-Json -Depth 10 | Out-File -FilePath $module.FilePath -Encoding UTF8 -Force
                Set-ModuleJsonCache -Path $module.FilePath -JsonObj $json
                $savedCount++
                Clear-ModuleDirty -FilePath $module.FilePath
            }
            catch {
                Write-Host "Failed to save module: $($module.Name) - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    # Write categories.json once
    Write-CategoriesJson

    Set-HasChanges -Value $false -ChangeType All
    Set-Status "Saved $savedCount modules, copied $copiedCount new (created $($folderResult.CreatedCount) folders)" "#10B981"
    [System.Windows.MessageBox]::Show("Successfully saved $savedCount module(s)`nCopied $copiedCount new module(s)`nCreated $($folderResult.CreatedCount) new category folder(s)", "Success")

    Request-TreeRefresh
}

function Save-OnlyCategories {
    # Debug: List all categories at start
    Write-Host "=== Save-OnlyCategories called ===" -ForegroundColor Magenta
    Write-Host "All categories in memory:" -ForegroundColor Magenta
    foreach ($k in $script:Categories.Keys) {
        Write-Host "  - $k (IsNew = $($script:Categories[$k].IsNew))" -ForegroundColor Magenta
    }

    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        [System.Windows.MessageBox]::Show("Error: Modules path is not set.", "Save Error")
        return
    }

    # Debug: Show what we're about to process
    $newCats = @($script:Categories.GetEnumerator() | Where-Object { $_.Value.IsNew -eq $true })

    # First, create any missing category folders for new categories
    $folderResult = Ensure-CategoryFolders

    if ($folderResult.Errors.Count -gt 0) {
        $errMsg = "Some category folders could not be created:`n`n" + ($folderResult.Errors -join "`n")
        [System.Windows.MessageBox]::Show($errMsg, "Folder Creation Errors", "OK", "Warning")
    }

    try {
        Write-Host "Calling Write-CategoriesJson..." -ForegroundColor Cyan
        Write-Host "ModulesPath = $($script:ModulesPath)" -ForegroundColor Cyan
        Write-Host "Categories count = $($script:Categories.Count)" -ForegroundColor Cyan

        Write-CategoriesJson

        Write-Host "Write-CategoriesJson completed" -ForegroundColor Green

        Set-HasChanges -Value $false -ChangeType Category
        $catMsg = "Categories saved (created $($folderResult.CreatedCount) folders)"
        if ($script:HasModuleChanges) {
            Set-Status ($catMsg + "; module changes pending") "#F59E0B"
        }
        else {
            Set-Status $catMsg "#10B981"
        }
        Request-TreeRefresh
        [System.Windows.MessageBox]::Show("Successfully saved categories.json`nFound $($newCats.Count) new categories`nCreated $($folderResult.CreatedCount) new category folder(s)", "Categories Saved")
    }
    catch {
        Write-Host "ERROR in Save-OnlyCategories: $($_.Exception.Message)" -ForegroundColor Red
        [System.Windows.MessageBox]::Show("Failed to save categories.json: $($_.Exception.Message)", "Error")
    }
}
function Get-NextModuleOrder {
    param([string]$CategoryName)

    $max = 0
    foreach ($m in @($script:Categories[$CategoryName].Modules)) {
        [int]$o = 0
        if ([int]::TryParse([string]$m.Order, [ref]$o)) {
            if ($o -gt $max) { $max = $o }
        }
    }
    return ($max + 1)
}

function Get-NextCategoryOrder {
    $max = 0
    foreach ($cat in $script:Categories.Values) {
        if ($cat.Order -gt $max -and $cat.Order -lt 999) {
            $max = $cat.Order
        }
    }
    return ($max + 1)
}

function Ensure-CategoryEntry {
    param([Parameter(Mandatory = $true)][string]$CategoryName)

    if (-not $script:Categories.ContainsKey($CategoryName)) {
        $script:Categories[$CategoryName] = @{
            Order        = (Get-NextCategoryOrder)
            OriginalName = $CategoryName
            Modules      = @()
            IsNew        = $false
        }
        Mark-CategoriesDirty
    }

    if ($null -eq $script:Categories[$CategoryName].Modules) {
        $script:Categories[$CategoryName].Modules = @()
    }
}

function Add-ModuleFromJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$CategoryName,
        [Parameter(Mandatory = $true)][string]$ModuleJsonPath
    )

    if (-not (Test-Path -LiteralPath $ModuleJsonPath)) { return }

    try {
        $json = Get-Content -LiteralPath $ModuleJsonPath -Raw | ConvertFrom-Json
    }
    catch {
        return
    }
    Set-ModuleJsonCache -Path $ModuleJsonPath -JsonObj $json

    Ensure-CategoryEntry -CategoryName $CategoryName

    $already = $false
    foreach ($c in $script:Categories.Keys) {
        if ($script:Categories[$c].Modules | Where-Object { $_.FilePath -eq $ModuleJsonPath }) {
            $already = $true
            break
        }
    }
    if ($already) { return }

            $script:Categories[$CategoryName].Modules += @{
                Id               = $json.Id
                Name             = $json.Name
                OriginalName     = $json.Name
                Description      = $json.Description
                Category         = $CategoryName
                OriginalCategory = $CategoryName
                Order            = if ($json.Order) { [int]$json.Order } else { Get-ModuleOrder -Module $json }
                FilePath         = $ModuleJsonPath
                Json             = $json
            }

    $script:Categories[$CategoryName].Modules = @(
        $script:Categories[$CategoryName].Modules | Sort-Object { [int]$_.Order }
    )
    Mark-ModulesDirty -CategoryName $CategoryName
    Clear-ModuleDirty -FilePath $ModuleJsonPath
}

function Save-ModuleJsonOrdered {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$JsonObj,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][int]$Order
    )

    # Convert existing object to a hashtable so we can re-order keys
    $ht = @{}
    foreach ($p in $JsonObj.PSObject.Properties) {
        $ht[$p.Name] = $p.Value
    }

    # Force these values
    $ht["Category"] = $Category
    $ht["Order"] = $Order

    # Create ordered output: ... Category, Order ... (Order right after Category)
    $out = [ordered]@{}

    foreach ($k in @("Id", "Name", "Category", "Order", "Shell", "Description", "RunPath", "Params")) {
        if ($ht.ContainsKey($k)) { $out[$k] = $ht[$k] }
    }

    # Add any remaining properties (kept, but placed after the known ones)
    foreach ($k in ($ht.Keys | Sort-Object)) {
        if (-not $out.Contains($k)) {
            $out[$k] = $ht[$k]
        }
    }

    $obj = [PSCustomObject]$out
    $obj | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $Path -Encoding UTF8 -Force
    Set-ModuleJsonCache -Path $Path -JsonObj $obj
}
function Move-ModuleFolderToCategory {
    param(
        [Parameter(Mandatory = $true)]$ModuleObj,
        [Parameter(Mandatory = $true)][string]$SourceCategory,
        [Parameter(Mandatory = $true)][string]$TargetCategory
    )

    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        throw "ModulesPath is empty. Browse to the modules folder first."
    }

    $dstCategoryFolder = Ensure-CategoryFolderExists -CategoryName $TargetCategory
    $oldJsonPath = $ModuleObj.FilePath

    # If module is new and not yet saved, copy/move from SourcePath
    if ($ModuleObj.IsNew -eq $true -and $ModuleObj.SourcePath) {
        $sourceFolder = [string]$ModuleObj.SourcePath
        if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) {
            throw "Source module folder not found: $sourceFolder"
        }

        $moduleFolderName = Split-Path -Path $sourceFolder -Leaf
        $destModuleFolder = Join-Path $dstCategoryFolder $moduleFolderName
        if (Test-Path -LiteralPath $destModuleFolder) {
            throw "A module folder with the same name already exists in target category: $destModuleFolder"
        }

        $insideModules = $sourceFolder.StartsWith($script:ModulesPath, [System.StringComparison]::OrdinalIgnoreCase)
        if ($insideModules) {
            Microsoft.PowerShell.Management\Move-Item -Path $sourceFolder -Destination $dstCategoryFolder -Force -ErrorAction Stop
        }
        else {
            Copy-Item -Path $sourceFolder -Destination $dstCategoryFolder -Recurse -Force -ErrorAction Stop
        }

        $ModuleObj.FilePath = Join-Path $destModuleFolder "module.json"
        $ModuleObj.IsNew = $false
        if ($ModuleObj.ContainsKey("SourcePath")) { $ModuleObj.Remove("SourcePath") }
        if ($oldJsonPath -and $ModuleObj.FilePath -ne $oldJsonPath) {
            Move-ModuleJsonCacheEntry -OldPath $oldJsonPath -NewPath $ModuleObj.FilePath
        }
        return
    }

    $moduleJsonPath = $ModuleObj.FilePath
    if (-not $moduleJsonPath -or -not (Test-Path -Path $moduleJsonPath)) {
        throw "module.json path not found: $moduleJsonPath"
    }

    $moduleFolder = Split-Path -Path $moduleJsonPath -Parent
    $moduleFolderName = Split-Path -Path $moduleFolder -Leaf

    $destModuleFolder = Join-Path $dstCategoryFolder $moduleFolderName
    if (Test-Path -Path $destModuleFolder) {
        throw "A module folder with the same name already exists in target category: $destModuleFolder"
    }

    # Use the real cmdlet explicitly to avoid any shadowing/alias issues
    Microsoft.PowerShell.Management\Move-Item -Path $moduleFolder -Destination $dstCategoryFolder -Force -ErrorAction Stop

    # Update FilePath to the new module.json location
    $ModuleObj.FilePath = Join-Path $destModuleFolder "module.json"
    if ($oldJsonPath -and $ModuleObj.FilePath -ne $oldJsonPath) {
        Move-ModuleJsonCacheEntry -OldPath $oldJsonPath -NewPath $ModuleObj.FilePath
    }
}
function Ensure-DeletedFolder {
    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) { return $null }
    $p = Join-Path $script:ModulesPath "_deleted"
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
    return $p
}
function Get-UniqueDeletedPath {
    param(
        [Parameter(Mandatory = $true)][string]$DeletedRoot,
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $name = "{0}__{1}" -f $BaseName, $ts
    $dest = Join-Path $DeletedRoot $name

    $i = 1
    while (Test-Path -LiteralPath $dest) {
        $dest = Join-Path $DeletedRoot ("{0}__{1}__{2}" -f $BaseName, $ts, $i)
        $i++
    }
    return $dest
}
function Move-FolderToDeleted {
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $true)][string]$LabelForName
    )

    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        return $null
    }

    $deletedRoot = Ensure-DeletedFolder
    if ([string]::IsNullOrWhiteSpace($deletedRoot)) {
        throw "Cannot create/find _deleted folder (ModulesPath is empty)."
    }

    $dest = Get-UniqueDeletedPath -DeletedRoot $deletedRoot -BaseName $LabelForName

    # Use real cmdlet explicitly (avoid shadowing/parameter-set issues)
    Microsoft.PowerShell.Management\Move-Item -Path $FolderPath -Destination $dest -Force -ErrorAction Stop

    return $dest
}
function Get-DeletedItems {
    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) { return @() }

    $deletedRoot = Join-Path $script:ModulesPath "_deleted"
    if (-not (Test-Path -LiteralPath $deletedRoot -PathType Container)) { return @() }

    # Show folders only (each folder represents a deleted category or module folder)
    return @(Get-ChildItem -LiteralPath $deletedRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Get-UniqueFolderName {
    param(
        [Parameter(Mandatory = $true)][string]$ParentPath,
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $candidate = $BaseName
    $i = 1
    while (Test-Path -LiteralPath (Join-Path $ParentPath $candidate)) {
        $candidate = "{0}_restored_{1}" -f $BaseName, $i
        $i++
    }
    return $candidate
}

function Prompt-RestoreConflictAction {
    param([Parameter(Mandatory = $true)][string]$Message)

    $w = New-Object System.Windows.Window
    $w.Title = "Restore Conflict"
    $w.Width = 420
    $w.Height = 200
    $w.WindowStartupLocation = "CenterOwner"
    $w.Owner = $window
    $w.Background = "#1e1e1e"

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Text = $Message
    $txt.Foreground = "White"
    $txt.TextWrapping = "Wrap"
    $stack.Children.Add($txt) | Out-Null

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,20,0,0"

    $choice = $null

    $btnRename = New-Object System.Windows.Controls.Button
    $btnRename.Content = "Auto-Rename"
    $btnRename.Width = 110
    $btnRename.Margin = "5,0,5,0"
    $btnRename.Add_Click({ $choice = "rename"; $w.Close() })

    $btnChoose = New-Object System.Windows.Controls.Button
    $btnChoose.Content = "Choose Category"
    $btnChoose.Width = 120
    $btnChoose.Margin = "5,0,5,0"
    $btnChoose.Add_Click({ $choice = "choose"; $w.Close() })

    $btnOverwrite = New-Object System.Windows.Controls.Button
    $btnOverwrite.Content = "Overwrite"
    $btnOverwrite.Width = 100
    $btnOverwrite.Margin = "5,0,5,0"
    $btnOverwrite.Add_Click({ $choice = "overwrite"; $w.Close() })

    $btnPanel.Children.Add($btnRename) | Out-Null
    $btnPanel.Children.Add($btnChoose) | Out-Null
    $btnPanel.Children.Add($btnOverwrite) | Out-Null

    $stack.Children.Add($btnPanel) | Out-Null
    $w.Content = $stack
    $w.ShowDialog() | Out-Null

    return $choice
}

function Prompt-CategoryNameInput {
    param([Parameter(Mandatory = $true)][string]$Title)

    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 360
    $w.Height = 200
    $w.WindowStartupLocation = "CenterOwner"
    $w.Owner = $window
    $w.Background = "#1e1e1e"

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = "Enter a new category name:"
    $lbl.Foreground = "White"
    $lbl.Margin = "0,0,0,10"
    $stack.Children.Add($lbl) | Out-Null

    $txt = New-Object System.Windows.Controls.TextBox
    $txt.Background = "#2d2d2d"
    $txt.Foreground = "White"
    $stack.Children.Add($txt) | Out-Null

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"
    $btnPanel.Margin = "0,20,0,0"

    $result = $null

    $btnOk = New-Object System.Windows.Controls.Button
    $btnOk.Content = "OK"
    $btnOk.Width = 80
    $btnOk.Margin = "0,0,5,0"
    $btnOk.Add_Click({ $result = $txt.Text; $w.Close() })

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = "Cancel"
    $btnCancel.Width = 80
    $btnCancel.Add_Click({ $result = $null; $w.Close() })

    $btnPanel.Children.Add($btnOk) | Out-Null
    $btnPanel.Children.Add($btnCancel) | Out-Null

    $stack.Children.Add($btnPanel) | Out-Null
    $w.Content = $stack
    $w.ShowDialog() | Out-Null

    if ([string]::IsNullOrWhiteSpace($result)) { return $null }
    return $result.Trim()
}

function Prompt-CategorySelection {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$ExcludeCategory = ""
    )

    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 360
    $w.Height = 220
    $w.WindowStartupLocation = "CenterOwner"
    $w.Owner = $window
    $w.Background = "#1e1e1e"

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = "Select a category:"
    $lbl.Foreground = "White"
    $lbl.Margin = "0,0,0,10"
    $stack.Children.Add($lbl) | Out-Null

    $cmb = New-Object System.Windows.Controls.ComboBox
    $cmb.Background = "#2d2d2d"
    $cmb.Foreground = "Black"
    foreach ($cat in (Get-SortedCategories)) {
        if ($cat.Key -ne $ExcludeCategory) {
            $cmb.Items.Add($cat.Key) | Out-Null
        }
    }
    if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
    $stack.Children.Add($cmb) | Out-Null

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"
    $btnPanel.Margin = "0,20,0,0"

    $result = $null

    $btnOk = New-Object System.Windows.Controls.Button
    $btnOk.Content = "OK"
    $btnOk.Width = 80
    $btnOk.Margin = "0,0,5,0"
    $btnOk.Add_Click({ $result = [string]$cmb.SelectedItem; $w.Close() })

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = "Cancel"
    $btnCancel.Width = 80
    $btnCancel.Add_Click({ $result = $null; $w.Close() })

    $btnPanel.Children.Add($btnOk) | Out-Null
    $btnPanel.Children.Add($btnCancel) | Out-Null

    $stack.Children.Add($btnPanel) | Out-Null
    $w.Content = $stack
    $w.ShowDialog() | Out-Null

    if ([string]::IsNullOrWhiteSpace($result)) { return $null }
    return $result.Trim()
}

function Restore-DeletedItem {
    param([Parameter(Mandatory = $true)][string]$DeletedPath)

    if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
        throw "ModulesPath is empty. Browse to the modules folder first."
    }
    if (-not (Test-Path -LiteralPath $DeletedPath -PathType Container)) {
        throw "Deleted item not found: $DeletedPath"
    }

    $deletedName = Split-Path -Path $DeletedPath -Leaf
    $catMatch = [regex]::Match($deletedName, '^CATEGORY_(.+?)__\d{8}-\d{6}(?:__\d+)?$')
    $modMatch = [regex]::Match($deletedName, '^MODULE_(.+?)__(.+?)__\d{8}-\d{6}(?:__\d+)?$')

    if ($catMatch.Success) {
        $catName = $catMatch.Groups[1].Value
        $destCatFolder = Join-Path $script:ModulesPath $catName
        if (Test-Path -LiteralPath $destCatFolder) {
            $action = Prompt-RestoreConflictAction -Message "Category '$catName' already exists. Choose how to restore it."
            if ($action -eq "rename") {
                $catName = Get-UniqueFolderName -ParentPath $script:ModulesPath -BaseName $catName
                $destCatFolder = Join-Path $script:ModulesPath $catName
            }
            elseif ($action -eq "choose") {
                $newName = Prompt-CategoryNameInput -Title "New Category Name"
                if ([string]::IsNullOrWhiteSpace($newName)) { return }
                $catName = $newName
                $destCatFolder = Join-Path $script:ModulesPath $catName
                if (Test-Path -LiteralPath $destCatFolder) {
                    throw "Category folder already exists: $destCatFolder"
                }
            }
            elseif ($action -eq "overwrite") {
                Move-FolderToDeleted -FolderPath $destCatFolder -LabelForName ("CATEGORY_" + $catName) | Out-Null
            }
            else {
                return
            }
        }

        Microsoft.PowerShell.Management\Move-Item -Path $DeletedPath -Destination $destCatFolder -Force -ErrorAction Stop

        Ensure-CategoryEntry -CategoryName $catName
        $moduleFiles = Get-ChildItem -Path $destCatFolder -Recurse -Filter "module.json" -ErrorAction SilentlyContinue
        foreach ($file in $moduleFiles) {
            Add-ModuleFromJsonFile -CategoryName $catName -ModuleJsonPath $file.FullName
        }

        Mark-ModulesDirty -CategoryName $catName
        Set-HasChanges -Value $true -ChangeType Category
        if ($moduleFiles.Count -gt 0) {
            Set-HasChanges -Value $true -ChangeType Module
        }
        return
    }

    if ($modMatch.Success) {
        $catName = $modMatch.Groups[1].Value
        $moduleFolderName = $modMatch.Groups[2].Value

        $destCatFolder = Ensure-CategoryFolderExists -CategoryName $catName
        $destModuleFolder = Join-Path $destCatFolder $moduleFolderName
        if (Test-Path -LiteralPath $destModuleFolder) {
            $action = Prompt-RestoreConflictAction -Message "Module '$moduleFolderName' already exists in category '$catName'. Choose how to restore it."
            if ($action -eq "rename") {
                $moduleFolderName = Get-UniqueFolderName -ParentPath $destCatFolder -BaseName $moduleFolderName
                $destModuleFolder = Join-Path $destCatFolder $moduleFolderName
            }
            elseif ($action -eq "choose") {
                $targetCat = Prompt-CategorySelection -Title "Select Target Category" -ExcludeCategory $catName
                if ([string]::IsNullOrWhiteSpace($targetCat)) { return }
                $destCatFolder = Ensure-CategoryFolderExists -CategoryName $targetCat
                $destModuleFolder = Join-Path $destCatFolder $moduleFolderName
                if (Test-Path -LiteralPath $destModuleFolder) {
                    throw "Module folder already exists: $destModuleFolder"
                }
                $catName = $targetCat
            }
            elseif ($action -eq "overwrite") {
                Move-FolderToDeleted -FolderPath $destModuleFolder -LabelForName ("MODULE_{0}__{1}" -f $catName, $moduleFolderName) | Out-Null
            }
            else {
                return
            }
        }

        Microsoft.PowerShell.Management\Move-Item -Path $DeletedPath -Destination $destModuleFolder -Force -ErrorAction Stop

        Ensure-CategoryEntry -CategoryName $catName
        $moduleJsonPath = Join-Path $destModuleFolder "module.json"
        if (Test-Path -LiteralPath $moduleJsonPath) {
            Add-ModuleFromJsonFile -CategoryName $catName -ModuleJsonPath $moduleJsonPath
        }

        Mark-ModulesDirty -CategoryName $catName
        Set-HasChanges -Value $true -ChangeType Module
        return
    }

    throw "Unrecognized deleted item name: $deletedName"
}

# ====================== EVENT HANDLERS ======================

$btnBrowse.Add_Click({
        $selectedPath = Select-FolderDialog -Title "Select Modules Folder"

        if ($selectedPath -and (Test-Path $selectedPath -PathType Container)) {
            $script:ModulesPath = $selectedPath
            $txtModulesPath.Text = $script:ModulesPath
            Load-Modules
        }
    })

$btnRefresh.Add_Click({
        if ($script:HasChanges) {
            $result = [System.Windows.MessageBox]::Show("You have unsaved changes. Refresh anyway?", "Confirm Refresh", "YesNo", "Warning")
            if ($result -ne "Yes") { return }
        }
        Load-Modules
    })

$treeModules.Add_SelectedItemChanged({
        $selected = $treeModules.SelectedItem
        if ($null -eq $selected) { return }

        $tag = $selected.Tag
        $script:SelectedItem = $tag

        if ($tag.Type -eq "Category") {
            Show-CategoryDetails -CategoryData $tag.Data -CategoryName $tag.Name
        }
        elseif ($tag.Type -eq "Module") {
            Show-ModuleDetails -ModuleData $tag.Data
        }
    })

$btnAddCategory.Add_Click({
        # Check BEFORE opening dialog
        if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
            [System.Windows.MessageBox]::Show("Please browse to a modules folder first.", "No Folder Selected")
            return
        }

        $inputWindow = New-Object System.Windows.Window
        $inputWindow.Title = "Add Category"
        $inputWindow.Width = 350
        $inputWindow.Height = 250
        $inputWindow.WindowStartupLocation = "CenterOwner"
        $inputWindow.Owner = $window
        $inputWindow.Background = "#1e1e1e"

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = "20"

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "Category Name:"
        $lbl.Foreground = "White"
        $lbl.Margin = "0,0,0,5"
        $stack.Children.Add($lbl) | Out-Null

        $txt = New-Object System.Windows.Controls.TextBox
        $txt.Background = "#2d2d2d"
        $txt.Foreground = "White"
        $txt.Padding = "8,5"
        $stack.Children.Add($txt) | Out-Null

        # Calculate next order number
        $maxOrder = 0
        foreach ($cat in $script:Categories.Values) {
            if ($cat.Order -gt $maxOrder -and $cat.Order -lt 999) {
                $maxOrder = $cat.Order
            }
        }
        $nextOrder = $maxOrder + 1

        $lblOrder = New-Object System.Windows.Controls.TextBlock
        $lblOrder.Text = "Display Order:"
        $lblOrder.Foreground = "White"
        $lblOrder.Margin = "0,10,0,5"
        $stack.Children.Add($lblOrder) | Out-Null

        $txtOrder = New-Object System.Windows.Controls.TextBox
        $txtOrder.Background = "#2d2d2d"
        $txtOrder.Foreground = "White"
        $txtOrder.Padding = "8,5"
        $txtOrder.Text = $nextOrder
        $stack.Children.Add($txtOrder) | Out-Null

        $btnOk = New-Object System.Windows.Controls.Button
        $btnOk.Content = "Add Category"
        $btnOk.Margin = "0,20,0,0"
        $btnOk.Background = "#10B981"
        $btnOk.Foreground = "White"

        # Capture references for the closure
        $txtRef = $txt
        $txtOrderRef = $txtOrder
        $inputWindowRef = $inputWindow
        $categoriesRef = $script:Categories

        $btnOk.Add_Click({
                $catName = [string]$txtRef.Text
                if (-not $catName) { $catName = "" }
                $catName = $catName.Trim()

                if ([string]::IsNullOrWhiteSpace($catName)) {
                    [System.Windows.MessageBox]::Show("Category name cannot be empty.", "Invalid Input", "OK", "Warning")
                    return
                }

                if ($categoriesRef.ContainsKey($catName)) {
                    [System.Windows.MessageBox]::Show("Please enter a unique category name.", "Invalid Input", "OK", "Warning")
                    return
                }

                [int]$catOrder = 0
                if (-not [int]::TryParse(([string]$txtOrderRef.Text).Trim(), [ref]$catOrder)) {
                    [System.Windows.MessageBox]::Show("Display Order must be a number.", "Invalid Input", "OK", "Warning")
                    return
                }

                # Add to the captured hashtable reference (this IS $script:Categories)
                $categoriesRef[$catName] = @{
                    Order        = $catOrder
                    OriginalName = $catName
                    Modules      = @()
                    IsNew        = $true
                }

                Write-Host "Added category '$catName' with IsNew = $($categoriesRef[$catName].IsNew)" -ForegroundColor Cyan
                Write-Host "Total categories now: $($categoriesRef.Count)" -ForegroundColor Cyan

                Set-HasChanges -Value $true -ChangeType Category
                Request-TreeRefresh

                Write-Host "After Refresh-TreeView: $($categoriesRef.Count)" -ForegroundColor Cyan

                $inputWindowRef.Close()
            }.GetNewClosure())

        $stack.Children.Add($btnOk) | Out-Null

        $inputWindow.Content = $stack
        $inputWindow.ShowDialog() | Out-Null
    })

$btnAddModule.Add_Click({
        if ($script:Categories.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Please add a category first.", "No Categories", "OK", "Warning")
            return
        }

        if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
            [System.Windows.MessageBox]::Show("Please browse to a modules folder first.", "No Folder Selected")
            return
        }

        $modulePath = Select-FolderDialog -Title "Select Module Folder (containing run.ps1)"

        if (-not $modulePath -or -not (Test-Path $modulePath -PathType Container)) {
            return
        }

        $runScript = Join-Path $modulePath "run.ps1"

        if (-not (Test-Path $runScript)) {
            [System.Windows.MessageBox]::Show("No run.ps1 found in selected folder.", "Invalid Module", "OK", "Error")
            return
        }

        $moduleName = Split-Path $modulePath -Leaf
        $moduleJsonPath = Join-Path $modulePath "module.json"

        # Select category
        $catWindow = New-Object System.Windows.Window
        $catWindow.Title = "Select Category"
        $catWindow.Width = 350
        $catWindow.Height = 200
        $catWindow.WindowStartupLocation = "CenterOwner"
        $catWindow.Owner = $window
        $catWindow.Background = "#1e1e1e"

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = "20"

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "Select category for '$moduleName':"
        $lbl.Foreground = "White"
        $lbl.Margin = "0,0,0,10"
        $stack.Children.Add($lbl)

        $cmb = New-Object System.Windows.Controls.ComboBox
        $cmb.Background = "#2d2d2d"
        $cmb.Foreground = "Black"

        # Build sorted list of categories with order numbers
        # Store actual category name in Tag, display "Order- Name" format
        $sortedCats = Get-SortedCategories
        foreach ($cat in $sortedCats) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = "{0}- {1}" -f $cat.Value.Order, $cat.Key
            $item.Tag = $cat.Key  # Store actual category name
            $cmb.Items.Add($item) | Out-Null
        }
        if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
        $stack.Children.Add($cmb)

        $btnOk = New-Object System.Windows.Controls.Button
        $btnOk.Content = "Add Module"
        $btnOk.Margin = "0,20,0,0"
        $btnOk.Background = "#10B981"
        $btnOk.Foreground = "White"

        # Capture references
        $cmbRef = $cmb
        $catWindowRef = $catWindow
        $categoriesRef = $script:Categories
        $moduleNameRef = $moduleName
        $moduleJsonPathRef = $moduleJsonPath
        $modulePathRef = $modulePath
        $modulesPathRef = $script:ModulesPath

        $btnOk.Add_Click({
                $selectedItem = $cmbRef.SelectedItem
                if ($null -eq $selectedItem) {
                    [System.Windows.MessageBox]::Show("Please select a category.", "No Selection", "OK", "Warning")
                    return
                }

                # Get actual category name from Tag
                $selectedCat = $selectedItem.Tag

                if ([string]::IsNullOrWhiteSpace($selectedCat)) {
                    [System.Windows.MessageBox]::Show("Category name cannot be empty.", "Invalid Selection", "OK", "Warning")
                    return
                }

                $newOrder = ($categoriesRef[$selectedCat].Modules.Count + 1)

                # Create in-memory module entry (not saved to disk yet)
                $newModule = @{
                    Id               = $moduleNameRef.ToLower() -replace '\s+', '-'
                    Name             = $moduleNameRef
                    OriginalName     = $moduleNameRef
                    Category         = $selectedCat
                    OriginalCategory = $selectedCat
                    Description      = "New module"
                    Order            = $newOrder
                    FilePath         = $moduleJsonPathRef
                    SourcePath       = $modulePathRef  # Original location - will be copied on Save
                    IsNew            = $true           # Flag for deferred save
                    Json             = [PSCustomObject]@{
                        Id          = $moduleNameRef.ToLower() -replace '\s+', '-'
                        Name        = $moduleNameRef
                        Category    = $selectedCat
                        Order       = $newOrder
                        Shell       = "Pwsh"
                        Description = "New module"
                        RunPath     = "run.ps1"
                        Params      = @()
                    }
                }

                $categoriesRef[$selectedCat].Modules += $newModule

                Write-Host "Added module '$moduleNameRef' to '$selectedCat' (unsaved)" -ForegroundColor Cyan

                Mark-ModuleDirty -FilePath $moduleJsonPathRef
                Mark-ModulesDirty -CategoryName $selectedCat
                Set-HasChanges -Value $true -ChangeType Module
                Request-TreeRefresh
                $catWindowRef.Close()
            }.GetNewClosure())

        $stack.Children.Add($btnOk)

        $catWindow.Content = $stack
        $catWindow.ShowDialog()
    })

$btnDelete.Add_Click({
        if ($null -eq $script:SelectedItem) {
            [System.Windows.MessageBox]::Show("Please select an item to delete.", "No Selection", "OK", "Warning")
            return
        }

        if ([string]::IsNullOrWhiteSpace($script:ModulesPath)) {
            [System.Windows.MessageBox]::Show("Modules path is not set. Click Browse first.", "Error")
            return
        }

        # -------------------- DELETE CATEGORY --------------------
        if ($script:SelectedItem.Type -eq "Category") {

            $catName = [string]$script:SelectedItem.Name
            if ([string]::IsNullOrWhiteSpace($catName)) { return }

            if (-not $script:Categories.ContainsKey($catName)) {
                [System.Windows.MessageBox]::Show("Category not found. Please Refresh.", "Error")
                return
            }

            if (@($script:Categories[$catName].Modules).Count -gt 0) {
                [System.Windows.MessageBox]::Show(
                    "Cannot delete a category that contains modules.`nMove or delete the modules first.",
                    "Cannot Delete", "OK", "Error"
                )
                return
            }

            $catData = $script:Categories[$catName]
            $isNewCategory = $catData.IsNew -eq $true
            $catFolder = Join-Path $script:ModulesPath $catName

            # If it's a new (unsaved) category, just remove from memory
            if ($isNewCategory) {
                $result = [System.Windows.MessageBox]::Show(
                    "Delete unsaved category '$catName'?`n`nThis category has not been saved yet, so it will simply be removed.",
                    "Confirm Delete Category", "YesNo", "Warning"
                )
                if ($result -ne "Yes") { return }

                $script:Categories.Remove($catName)
                $script:SortedModulesCache.Remove($catName)
                $script:ModulesDirty.Remove($catName)
                Mark-CategoriesDirty
                $script:SelectedItem = $null
                $pnlDetails.Children.Clear()
                Set-HasChanges -Value $true -ChangeType Category
                Request-TreeRefresh
                return
            }

            $msg = "Delete category '$catName'?"
            $msg += "`n`nThis will MOVE the category folder to:"
            $msg += "`n  " + (Join-Path $script:ModulesPath "_deleted")
            $msg += "`n`n(No files will be permanently deleted.)"

            $result = [System.Windows.MessageBox]::Show($msg, "Confirm Delete Category", "YesNo", "Warning")
            if ($result -ne "Yes") { return }

            # Move folder if exists
            try {
                if (Test-Path -LiteralPath $catFolder -PathType Container) {
                    $movedTo = Move-FolderToDeleted -FolderPath $catFolder -LabelForName ("CATEGORY_" + $catName)
                }
            }
            catch {
                [System.Windows.MessageBox]::Show("Failed to move category folder:`n$($_.Exception.Message)", "Delete Error")
                return
            }

            # Remove from memory
            $script:Categories.Remove($catName)
            $script:SortedModulesCache.Remove($catName)
            $script:ModulesDirty.Remove($catName)
            Mark-CategoriesDirty

            # Persist categories.json immediately
            try {
                Write-CategoriesJson
            }
            catch {
                [System.Windows.MessageBox]::Show("Category removed, but failed to update categories.json:`n$($_.Exception.Message)", "Save Error")
            }

            $script:SelectedItem = $null
            $pnlDetails.Children.Clear()

            Set-HasChanges -Value $true -ChangeType Category
            Request-TreeRefresh
            return
        }

        # -------------------- DELETE MODULE --------------------
        if ($script:SelectedItem.Type -eq "Module") {

            $mod = $script:SelectedItem.Data
            $cat = [string]$script:SelectedItem.Category

            if ($null -eq $mod -or [string]::IsNullOrWhiteSpace($cat)) { return }
            if (-not $script:Categories.ContainsKey($cat)) { return }

            # module folder = parent of module.json
            $moduleJsonPath = [string]$mod.FilePath
            if ([string]::IsNullOrWhiteSpace($moduleJsonPath)) {
                [System.Windows.MessageBox]::Show("Module has no FilePath. Please Refresh.", "Error")
                return
            }

            $moduleFolder = Split-Path -Path $moduleJsonPath -Parent
            $moduleFolderName = Split-Path -Path $moduleFolder -Leaf

            $msg = "Delete module '$($mod.Name)'?"
            $msg += "`nCategory: $cat"
            $msg += "`n`nThis will MOVE the module folder to:"
            $msg += "`n  " + (Join-Path $script:ModulesPath "_deleted")
            $msg += "`nFolder:"
            $msg += "`n  $moduleFolder"
            $msg += "`n`n(No files will be permanently deleted.)"

            $result = [System.Windows.MessageBox]::Show($msg, "Confirm Delete Module", "YesNo", "Warning")
            if ($result -ne "Yes") { return }

            # Move folder on disk so Refresh cannot rediscover it
            try {
                if (Test-Path -LiteralPath $moduleFolder -PathType Container) {
                    $label = "MODULE_{0}__{1}" -f $cat, $moduleFolderName
                    $movedTo = Move-FolderToDeleted -FolderPath $moduleFolder -LabelForName $label
                }
            }
            catch {
                [System.Windows.MessageBox]::Show("Failed to move module folder:`n$($_.Exception.Message)", "Delete Error")
                return
            }

            # Remove from memory
            $script:Categories[$cat].Modules = @(
                $script:Categories[$cat].Modules | Where-Object { $_.FilePath -ne $mod.FilePath }
            )

            Normalize-ModuleOrders $cat
            Mark-ModulesDirty -CategoryName $cat

            $script:SelectedItem = $null
            $pnlDetails.Children.Clear()

            Set-HasChanges -Value $true -ChangeType Module
            Request-TreeRefresh
            return
        }
    })

if ($null -ne $btnRestore) {
    $btnRestore.Add_Click({
            if ($null -eq $script:SelectedItem -or $script:SelectedItem.Type -ne "DeletedItem") {
                [System.Windows.MessageBox]::Show("Please select a deleted item to restore.", "No Selection", "OK", "Warning")
                return
            }

            try {
                Restore-DeletedItem -DeletedPath $script:SelectedItem.Path
                Request-TreeRefresh
            }
            catch {
                [System.Windows.MessageBox]::Show("Restore failed:`n$($_.Exception.Message)", "Restore Error")
            }
        })
}
else {
    Write-Host "Warning: btnRestore not found in XAML." -ForegroundColor Yellow
}

$btnMoveUp.Add_Click({
        if ($null -eq $script:SelectedItem -or $script:SelectedItem.Type -ne "Module") { return }

        $mod = $script:SelectedItem.Data
        $cat = $script:SelectedItem.Category
        $modules = @($script:Categories[$cat].Modules)
        $idx = -1

        for ($i = 0; $i -lt $modules.Count; $i++) {
            if ($modules[$i].FilePath -eq $mod.FilePath) { $idx = $i; break }
        }

        if ($idx -gt 0) {
            # Swap orders
            $prevOrder = $modules[$idx - 1].Order
            $modules[$idx - 1].Order = $modules[$idx].Order
            $modules[$idx].Order = $prevOrder

            # Re-sort
            $script:Categories[$cat].Modules = @($modules | Sort-Object { $_.Order })
            Mark-ModulesDirty -CategoryName $cat
            Set-HasChanges -Value $true -ChangeType Module
        }
        Normalize-ModuleOrders $cat
        Mark-ModulesDirty -CategoryName $cat
        Request-TreeRefresh
    })

$btnMoveDown.Add_Click({
        if ($null -eq $script:SelectedItem -or $script:SelectedItem.Type -ne "Module") { return }

        $mod = $script:SelectedItem.Data
        $cat = $script:SelectedItem.Category
        $modules = @($script:Categories[$cat].Modules)
        $idx = -1

        for ($i = 0; $i -lt $modules.Count; $i++) {
            if ($modules[$i].FilePath -eq $mod.FilePath) { $idx = $i; break }
        }

        if ($idx -ge 0 -and $idx -lt ($modules.Count - 1)) {
            # Swap orders
            $nextOrder = $modules[$idx + 1].Order
            $modules[$idx + 1].Order = $modules[$idx].Order
            $modules[$idx].Order = $nextOrder

            # Re-sort
            $script:Categories[$cat].Modules = @($modules | Sort-Object { $_.Order })
            Mark-ModulesDirty -CategoryName $cat
            Set-HasChanges -Value $true -ChangeType Module
        }
        Normalize-ModuleOrders $cat
        Mark-ModulesDirty -CategoryName $cat
        Request-TreeRefresh
    })

$btnMoveToCategory.Add_Click({
        if ($null -eq $script:SelectedItem -or $script:SelectedItem.Type -ne "Module") {
            [System.Windows.MessageBox]::Show("Please select a module to move.", "No Selection", "OK", "Warning")
            return
        }

        $mod = $script:SelectedItem.Data
        $currentCat = $script:SelectedItem.Category

        # Show category selector
        $catWindow = New-Object System.Windows.Window
        $catWindow.Title = "Move to Category"
        $catWindow.Width = 350
        $catWindow.Height = 180
        $catWindow.WindowStartupLocation = "CenterOwner"
        $catWindow.Owner = $window
        $catWindow.Background = "#1e1e1e"

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = "20"

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "Move '$($mod.Name)' to:"
        $lbl.Foreground = "White"
        $lbl.Margin = "0,0,0,10"
        $stack.Children.Add($lbl)

        $cmb = New-Object System.Windows.Controls.ComboBox
        $cmb.Background = "#2d2d2d"
        $cmb.Foreground = "Black"

        # Build sorted list of categories with order numbers
        $sortedCats = Get-SortedCategories
        foreach ($cat in $sortedCats) {
            if ($cat.Key -ne $currentCat) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Content = "{0}- {1}" -f $cat.Value.Order, $cat.Key
                $item.Tag = $cat.Key  # Store actual category name
                $cmb.Items.Add($item) | Out-Null
            }
        }
        if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
        $stack.Children.Add($cmb)

        $btnOk = New-Object System.Windows.Controls.Button
        $btnOk.Content = "Move"
        $btnOk.Margin = "0,20,0,0"
        $btnOk.Background = "#10B981"
        $btnOk.Foreground = "White"
        $btnOk.Add_Click({
                $selectedItem = $cmb.SelectedItem
                if ($null -eq $selectedItem) {
                    [System.Windows.MessageBox]::Show("Please select a category.", "No Selection", "OK", "Warning")
                    return
                }
                $targetCat = [string]$selectedItem.Tag
                if ([string]::IsNullOrWhiteSpace($targetCat)) { return }

                # Move module folder on disk: modules\OldCat\ModuleName -> modules\NewCat\ModuleName
                try {
                    Move-ModuleFolderToCategory -ModuleObj $mod -SourceCategory $currentCat -TargetCategory $targetCat
                }
                catch {
                    [System.Windows.MessageBox]::Show("Move failed:`n$($_.Exception.Message)", "Move Error")
                    return
                }

                # Remove from source list (in memory) after successful move
                $script:Categories[$currentCat].Modules = @(
                    $script:Categories[$currentCat].Modules | Where-Object { $_.FilePath -ne $mod.FilePath }
                )

                if ($null -eq $script:Categories[$targetCat].Modules) {
                    $script:Categories[$targetCat].Modules = @()
                }

                # Assign next order in target (always set to end)
                $nextOrder = Get-NextModuleOrder -CategoryName $targetCat
                $mod.Order = $nextOrder
                $mod.Category = $targetCat

                # Load or create Json
                if ($null -eq $mod.Json) {
                    if ($mod.FilePath -and (Test-Path -LiteralPath $mod.FilePath)) {
                        $mod.Json = Get-ModuleJsonCached -Path $mod.FilePath
                    }
                    if ($null -eq $mod.Json) {
                        $mod.Json = [PSCustomObject]@{
                            Id          = $mod.Id
                            Name        = $mod.Name
                            Category    = $targetCat
                            Order       = [int]$mod.Order
                            Shell       = "Pwsh"
                            Description = $mod.Description
                            RunPath     = "run.ps1"
                            Params      = @()
                        }
                    }
                }

                # Update json values (Category + Order)
                $mod.Json.Category = $targetCat
                $mod.Json.Order = [int]$mod.Order

                # Add into target list
                $script:Categories[$targetCat].Modules += $mod

                # Normalize both categories (optional, but keeps list tidy)
                Normalize-ModuleOrders $currentCat
                Normalize-ModuleOrders $targetCat
                Mark-ModulesDirty -CategoryName $currentCat
                Mark-ModulesDirty -CategoryName $targetCat
                Mark-ModuleDirty -FilePath $mod.FilePath

                # Write module.json with stable property order (Order right after Category)
                try {
                    Save-ModuleJsonOrdered -Path $mod.FilePath -JsonObj $mod.Json -Category $targetCat -Order ([int]$mod.Order)
                    Clear-ModuleDirty -FilePath $mod.FilePath
                }
                catch {
                    [System.Windows.MessageBox]::Show("Moved, but failed to update module.json:`n$($_.Exception.Message)", "Save Error")
                    Set-HasChanges -Value $true -ChangeType Module
                    Request-TreeRefresh
                    $catWindow.Close()
                    return
                }

                Set-HasChanges -Value $true -ChangeType Module
                Request-TreeRefresh
                $catWindow.Close()
            })


        $stack.Children.Add($btnOk)

        $catWindow.Content = $stack
        $catWindow.ShowDialog()
    })

$btnApply.Add_Click({
        Set-Status "Changes applied (not yet saved to disk)" "#F59E0B"
    })

$btnSaveCategories.Add_Click({
        Save-OnlyCategories
    })

$btnSave.Add_Click({
        if (-not $script:HasChanges) {
            [System.Windows.MessageBox]::Show("No changes to save.", "Nothing to Save", "OK", "Information")
            return
        }

        $result = [System.Windows.MessageBox]::Show("Save all changes to module.json files?", "Confirm Save", "YesNo", "Question")
        if ($result -eq "Yes") {
            Save-AllModules
        }
    })

$btnCancel.Add_Click({
        if ($script:HasChanges) {
            $result = [System.Windows.MessageBox]::Show("You have unsaved changes. Exit anyway?", "Confirm Exit", "YesNo", "Warning")
            if ($result -ne "Yes") { return }
        }
        $window.Close()
    })

$window.Add_Closing({
        if ($script:HasChanges) {
            $result = [System.Windows.MessageBox]::Show("You have unsaved changes. Exit anyway?", "Confirm Exit", "YesNo", "Warning")
            if ($result -ne "Yes") {
                $_.Cancel = $true
            }
        }
    })

# ====================== STARTUP ======================
Set-Status "Select a modules folder to begin" "#888"
$window.ShowDialog() | Out-Null
