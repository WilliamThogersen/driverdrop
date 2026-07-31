<#  =====================================================================
    DriverDrop v1.5.0  -  free, open-source Windows driver & update picker
    ---------------------------------------------------------------------
    * Scans Microsoft Update for driver updates (or all updates)
    * Lets you tick exactly what you want installed - nothing more
    * Optional system restore point before installing
    * Devices view: every installed driver, problem devices, hardware IDs
      and safe links (Microsoft Update Catalog, your PC maker, GPU vendor)
    * No ads, no paywall, no telemetry, one readable .ps1 file

    Click the version badge in the title bar to see the full changelog,
    or read CHANGELOG.md in the repo.

    Run straight from GitHub (any PowerShell window, it self-elevates):

        irm "https://raw.githubusercontent.com/WilliamThogersen/driverdrop/prod/DriverDrop.ps1" | iex

    Branches: prod = stable releases, staging = ongoing development.

    Or run the file locally:

        powershell -ExecutionPolicy Bypass -File .\DriverDrop.ps1

    Note: if you re-run a NEWER version inside the SAME PowerShell window
    you used for an older one, open a fresh window instead (the .NET row
    classes cannot be redefined in a running session).
    ===================================================================== #>

# ---------------------------------------------------------------- config
# This URL is used to self-elevate when the script is run via  irm | iex.
# It points at the stable prod branch ON PURPOSE - even in the staging copy -
# so end users always land on stable and staging-to-prod merges need no edits.
# When testing the staging branch yourself, start from an already-elevated
# PowerShell window so this fallback is never used.
$ScriptUrl = 'https://raw.githubusercontent.com/WilliamThogersen/driverdrop/prod/DriverDrop.ps1'
$AppName   = 'DriverDrop'
$AppVer    = '1.5.0'

# ------------------------------------------------------------- changelog
# Newest first. Shown in-app when the version badge is clicked.
$ChangeLog = @(
    @{ Version = '1.5.0'; Date = '2026-07-31'; Changes = @(
        'New Devices view: every installed device with its driver version and date',
        'Devices with problems (no driver, errors) are flagged and grouped at the top',
        'Click a device for its hardware ID, with one-click copy',
        'Search the Microsoft Update Catalog by hardware ID for drivers WU does not offer',
        'Quick links to your PC maker and GPU vendor driver pages, auto-detected',
        'DriverDrop still never downloads drivers from third-party driver packs'
    )}
    @{ Version = '1.4.1'; Date = '2026-07-31'; Changes = @(
        'Two-branch setup: prod is the stable branch, staging is ongoing development',
        'The public one-liner and self-elevation now always use the stable prod branch',
        'Testing staging? Run its one-liner from an already-admin PowerShell window'
    )}
    @{ Version = '1.4.0'; Date = '2026-07-31'; Changes = @(
        'Added this changelog - click the version badge in the title bar any time',
        'Added CHANGELOG.md to the repo so changes are tracked on GitHub too',
        'Esc or clicking outside the panel closes the changelog'
    )}
    @{ Version = '1.3.0'; Date = '2026-07-31'; Changes = @(
        'History is now human readable: raw driver titles are parsed into clean names',
        'History entries are grouped by day (Today / Yesterday / date) with counts',
        'Duplicates on the same day are collapsed into one row with an (x2), (x3) suffix',
        'Store app IDs like 9NRZT3Q9R3DL-... are cleaned up and get a purple Store pill',
        'Category pills show the driver class (System, LAN, Bluetooth...), Defender and Store',
        'Uninstalls show as an amber Removed pill instead of a green Succeeded',
        'Fake pre-1990 driver dates (the Intel 1968 trick) are hidden from titles',
        'The filter box also matches history categories'
    )}
    @{ Version = '1.2.0'; Date = '2026-07-31'; Changes = @(
        'New Released column: the manufacturer driver date for drivers, publish date otherwise',
        'New Device column: the friendly hardware name the driver targets',
        'Details pane: click a row to see device, manufacturer, driver date and description',
        'New History view (Available / History switcher) of everything installed, newest first',
        'History loads automatically, has a refresh button, and reloads after installs',
        'The filter box also matches device names'
    )}
    @{ Version = '1.1.0'; Date = '2026-07-31'; Changes = @(
        'Modern UI overhaul: custom dark title bar with min / max / close buttons',
        'Segmented controls for scan scope and a toggle switch for the restore point',
        'Type badges (Driver / Software), live filter box, and friendly empty states',
        'Install button shows a live selected count and disables when nothing is ticked',
        'Double-click a row or press Space to toggle; Select all respects the filter',
        'Slim dark scrollbars, row hover, thin busy indicator, and a Clear log button'
    )}
    @{ Version = '1.0.0'; Date = '2026-07-31'; Changes = @(
        'First release: dark WPF GUI over Windows Update, one self-contained .ps1',
        'Scan Microsoft Update for drivers only or all updates, then pick what to install',
        'Optional system restore point before installing (24h limit lifted automatically)',
        'Reboot prompt when needed - never reboots on its own',
        'Self-elevates via UAC and installs the PSWindowsUpdate module on first run',
        'Runs straight from GitHub with the irm | iex one-liner'
    )}
)

# ------------------------------------------------------------- elevation
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ''
    Write-Host "  $AppName needs administrator rights - asking Windows for elevation..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            # started from a local .ps1 file -> relaunch the file elevated
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        }
        elseif ($ScriptUrl -notmatch 'YOURUSER') {
            # started via irm | iex -> relaunch the one-liner elevated
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$ScriptUrl' | iex`""
        }
        else {
            Write-Host '  Cannot self-elevate: the script was run from memory and $ScriptUrl is' -ForegroundColor Red
            Write-Host '  still the placeholder. Open PowerShell AS ADMINISTRATOR and run it again.' -ForegroundColor Red
            $null = Read-Host '  Press Enter to close'
            return
        }
        Write-Host '  A new elevated window should have opened - you can close this one.' -ForegroundColor Green
    }
    catch {
        Write-Host "  Elevation was cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
        $null = Read-Host '  Press Enter to close'
    }
    return
}

# ---------------------------------------------------------- console intro
Write-Host ''
Write-Host "  $AppName v$AppVer  -  select the updates you want, skip the rest" -ForegroundColor Green
Write-Host '  ----------------------------------------------------------------'

try { Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue } catch {}

# TLS 1.2 so PowerShell 5.1 can talk to the PowerShell Gallery
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

# ------------------------------------------------- PSWindowsUpdate module
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host '  [*] Installing the PSWindowsUpdate module (first run only)...' -ForegroundColor Cyan
    try {
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
    }
    catch {
        Write-Host "  Could not install PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
        $null = Read-Host '  Press Enter to close'
        return
    }
}

try { Import-Module PSWindowsUpdate -ErrorAction Stop }
catch {
    Write-Host "  Could not load PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
    $null = Read-Host '  Press Enter to close'
    return
}

# Register the "Microsoft Update" service - that is where driver updates live
try {
    $muId = '7971f918-a847-4430-9279-4a52d1efe18d'
    if (-not (Get-WUServiceManager -ErrorAction SilentlyContinue | Where-Object { $_.ServiceID -eq $muId })) {
        Write-Host '  [*] Registering the Microsoft Update service (needed for drivers)...' -ForegroundColor Cyan
        Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null
    }
}
catch {
    Write-Host "  Warning: could not register Microsoft Update service: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host '  [*] Starting the interface...' -ForegroundColor Cyan

# ------------------------------------------------------------ row classes
# Tiny .NET classes so WPF checkbox binding is 100% reliable
if (-not ([System.Management.Automation.PSTypeName]'DriverDrop.UpdateItem').Type) {
    Add-Type -TypeDefinition @"
namespace DriverDrop {
    public class UpdateItem {
        public bool   IsSelected   { get; set; }
        public string Title        { get; set; }
        public string Device       { get; set; }
        public string Type         { get; set; }
        public string Released     { get; set; }
        public string KB           { get; set; }
        public string Size         { get; set; }
        public string UpdateID     { get; set; }
        public string Manufacturer { get; set; }
        public string Description  { get; set; }
    }
}
"@
}
if (-not ([System.Management.Automation.PSTypeName]'DriverDrop.HistoryItem').Type) {
    Add-Type -TypeDefinition @"
namespace DriverDrop {
    public class HistoryItem {
        public string Day      { get; set; }
        public string Time     { get; set; }
        public string Title    { get; set; }
        public string Category { get; set; }
        public string Kind     { get; set; }
        public string Result   { get; set; }
        public string KB       { get; set; }
    }
}
"@
}
if (-not ([System.Management.Automation.PSTypeName]'DriverDrop.DeviceItem').Type) {
    Add-Type -TypeDefinition @"
namespace DriverDrop {
    public class DeviceItem {
        public string Name       { get; set; }
        public string Group      { get; set; }
        public string Class      { get; set; }
        public string Version    { get; set; }
        public string DriverDate { get; set; }
        public string Status     { get; set; }
        public string StatusKind { get; set; }
        public string HardwareID { get; set; }
        public string Provider   { get; set; }
        public string Inf        { get; set; }
    }
}
"@
}

Add-Type -AssemblyName PresentationFramework

# --------------------------------------------------------- shared state
$sync                 = [hashtable]::Synchronized(@{})
$sync.LogQueue        = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$sync.Results         = $null
$sync.Items           = $null
$sync.ScanDone        = $false
$sync.InstallDone     = $false
$sync.HistoryResults  = $null
$sync.HistoryDone     = $false
$sync.HistoryLoaded   = $false
$sync.DevicesResults  = $null
$sync.DevicesDone     = $false
$sync.DevicesLoaded   = $false
$sync.OemLabel        = ''
$sync.OemUrl          = ''
$sync.GpuLabel        = ''
$sync.GpuUrl          = ''
$sync.CurrentHwid     = ''
$sync.Busy            = $false
$sync.RebootRequired  = $false

# ------------------------------------------------------------------ XAML
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DriverDrop - Windows driver and update picker"
        Width="1120" Height="760" MinWidth="980" MinHeight="640"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanResize"
        Background="#FF17171B"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13">

  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="48" ResizeBorderThickness="6"
                  GlassFrameThickness="0" CornerRadius="0"
                  UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>

  <Window.Resources>
    <SolidColorBrush x:Key="PanelBrush"  Color="#FF212127"/>
    <SolidColorBrush x:Key="EdgeBrush"   Color="#FF2A2A31"/>
    <SolidColorBrush x:Key="TextBrush"   Color="#FFEDEDEF"/>
    <SolidColorBrush x:Key="MutedBrush"  Color="#FF9A9AA5"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#FF3D7EFF"/>

    <!-- primary buttons -->
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="Background" Value="#FF3D7EFF"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.7"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#FF3A3A42"/>
                <Setter Property="Foreground" Value="#FF8A8A93"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- small transparent text button -->
    <Style x:Key="GhostButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="6" Padding="9,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#22FFFFFF"/>
                <Setter Property="Foreground" Value="#FFEDEDEF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- clickable version pill -->
    <Style x:Key="PillButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="#FF26262D" CornerRadius="8" Padding="7,2">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#FF34343D"/>
                <Setter Property="Foreground" Value="#FFEDEDEF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- title bar caption buttons -->
    <Style x:Key="CaptionButton" TargetType="Button">
      <Setter Property="Width" Value="46"/>
      <Setter Property="Foreground" Value="#FFC9C9D2"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#22FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CaptionCloseButton" TargetType="Button">
      <Setter Property="Width" Value="46"/>
      <Setter Property="Foreground" Value="#FFC9C9D2"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#FFE81123"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- modern checkbox -->
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="box" Width="18" Height="18" CornerRadius="5" BorderThickness="1"
                      BorderBrush="#FF4A4A55" Background="#FF26262D" VerticalAlignment="Center">
                <TextBlock x:Name="check" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="11"
                           Foreground="#FFFFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"
                           Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="#FF3D7EFF"/>
                <Setter TargetName="box" Property="BorderBrush" Value="#FF3D7EFF"/>
                <Setter TargetName="check" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="box" Property="BorderBrush" Value="#FF6E6E7A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- toggle switch -->
    <Style x:Key="ToggleSwitch" TargetType="CheckBox">
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="track" Width="40" Height="21" CornerRadius="10.5"
                      Background="#FF3A3A42" VerticalAlignment="Center">
                <Ellipse x:Name="thumb" Width="15" Height="15" Fill="#FFC9C9D2"
                         HorizontalAlignment="Left" Margin="3,0,0,0"/>
              </Border>
              <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="#FF3D7EFF"/>
                <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="thumb" Property="Margin" Value="0,0,3,0"/>
                <Setter TargetName="thumb" Property="Fill" Value="#FFFFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- segmented control buttons -->
    <Style x:Key="SegmentButton" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="bd" CornerRadius="7" Padding="14,6" Background="Transparent">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#FF34343D"/>
                <Setter Property="Foreground" Value="#FFEDEDEF"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="#FFEDEDEF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- data grid -->
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Padding" Value="8,8"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="BorderBrush" Value="{StaticResource EdgeBrush}"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="MinHeight" Value="38"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#0FFFFFFF"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#1AFFFFFF"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="Transparent"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="CellText" TargetType="TextBlock">
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
    </Style>
    <Style x:Key="CellTextMuted" TargetType="TextBlock">
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
    </Style>

    <!-- slim scrollbars -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True"
                     Orientation="{TemplateBinding Orientation}">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0"
                                Focusable="False" IsTabStop="False"/>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0"
                                Focusable="False" IsTabStop="False"/>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="tb" Background="#FF3A3A42" CornerRadius="4" Margin="1"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="tb" Property="Background" Value="#FF55555F"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="Orientation" Value="Horizontal">
                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="Height" Value="8"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Border Name="RootBorder" Background="#FF17171B">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="48"/>
        <RowDefinition Height="3"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- custom title bar -->
      <DockPanel Grid.Row="0" LastChildFill="False">
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Left" Margin="14,0,0,0">
          <Border Width="26" Height="26" CornerRadius="7" Background="{StaticResource AccentBrush}"
                  VerticalAlignment="Center">
            <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                       Foreground="#FFFFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Text="DriverDrop" FontSize="15" FontWeight="SemiBold"
                     Foreground="{StaticResource TextBrush}" VerticalAlignment="Center" Margin="10,0,0,0"/>
          <Button Name="BtnVersion" Style="{StaticResource PillButton}" VerticalAlignment="Center"
                  Margin="8,0,0,0" WindowChrome.IsHitTestVisibleInChrome="True"
                  ToolTip="What is new - click to see the changelog">
            <TextBlock Name="BtnVersionText" Text="v1.5.0"/>
          </Button>
          <TextBlock Text="no ads - no paywall - your choice" FontSize="11"
                     Foreground="{StaticResource MutedBrush}" VerticalAlignment="Center" Margin="14,0,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
          <Button Name="BtnMin" Style="{StaticResource CaptionButton}"
                  WindowChrome.IsHitTestVisibleInChrome="True">
            <TextBlock Text="&#xE921;" FontFamily="Segoe MDL2 Assets" FontSize="10"/>
          </Button>
          <Button Name="BtnMax" Style="{StaticResource CaptionButton}"
                  WindowChrome.IsHitTestVisibleInChrome="True">
            <TextBlock Name="MaxIcon" Text="&#xE922;" FontFamily="Segoe MDL2 Assets" FontSize="10"/>
          </Button>
          <Button Name="BtnClose" Style="{StaticResource CaptionCloseButton}"
                  WindowChrome.IsHitTestVisibleInChrome="True">
            <TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="10"/>
          </Button>
        </StackPanel>
      </DockPanel>

      <!-- thin busy indicator -->
      <ProgressBar Name="TopProgress" Grid.Row="1" Height="3" IsIndeterminate="True"
                   Visibility="Collapsed" Background="Transparent"
                   Foreground="{StaticResource AccentBrush}" BorderThickness="0"/>

      <!-- main content -->
      <Grid Grid.Row="2" Margin="20,14,20,16">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="150"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- toolbar -->
        <DockPanel Grid.Row="0" Margin="0,0,0,14" LastChildFill="False">
          <Border DockPanel.Dock="Left" CornerRadius="9" Background="{StaticResource PanelBrush}"
                  Padding="3" VerticalAlignment="Center" Margin="0,0,12,0">
            <StackPanel Orientation="Horizontal">
              <RadioButton Name="ViewUpdates" Style="{StaticResource SegmentButton}"
                           Content="Available" IsChecked="True" GroupName="view"/>
              <RadioButton Name="ViewHistory" Style="{StaticResource SegmentButton}"
                           Content="History" GroupName="view" Margin="2,0,0,0"/>
              <RadioButton Name="ViewDevices" Style="{StaticResource SegmentButton}"
                           Content="Devices" GroupName="view" Margin="2,0,0,0"/>
            </StackPanel>
          </Border>
          <Button Name="BtnScan" DockPanel.Dock="Left" Height="36">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                         VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock Text="Scan for updates" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button Name="BtnHistoryRefresh" DockPanel.Dock="Left" Height="36" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                         VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock Text="Refresh history" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button Name="BtnDevicesRefresh" DockPanel.Dock="Left" Height="36" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                         VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock Text="Rescan devices" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Border Name="ScopeBox" DockPanel.Dock="Left" Margin="12,0,0,0" CornerRadius="9"
                  Background="{StaticResource PanelBrush}" Padding="3" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <RadioButton Name="RadDrivers" Style="{StaticResource SegmentButton}"
                           Content="Drivers only" IsChecked="True" GroupName="scope"/>
              <RadioButton Name="RadAll" Style="{StaticResource SegmentButton}"
                           Content="All updates" GroupName="scope" Margin="2,0,0,0"/>
            </StackPanel>
          </Border>
          <Button Name="BtnOem" Style="{StaticResource GhostButton}" DockPanel.Dock="Left"
                  Margin="12,0,0,0" Visibility="Collapsed" Content="PC vendor drivers"/>
          <Button Name="BtnGpu" Style="{StaticResource GhostButton}" DockPanel.Dock="Left"
                  Margin="4,0,0,0" Visibility="Collapsed" Content="GPU drivers"/>
          <Border DockPanel.Dock="Right" CornerRadius="9" Background="{StaticResource PanelBrush}"
                  BorderBrush="{StaticResource EdgeBrush}" BorderThickness="1"
                  Width="220" Height="34" Padding="12,0" VerticalAlignment="Center">
            <DockPanel VerticalAlignment="Center">
              <TextBlock DockPanel.Dock="Left" Text="&#xE721;" FontFamily="Segoe MDL2 Assets"
                         FontSize="12" Foreground="#FF6E6E7A" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <Grid>
                <TextBox Name="FilterBox" Background="Transparent" BorderThickness="0"
                         Foreground="{StaticResource TextBrush}" CaretBrush="#FFEDEDEF"
                         VerticalAlignment="Center" Padding="0"/>
                <TextBlock Name="FilterHint" Text="Filter list" Foreground="#FF6E6E7A"
                           VerticalAlignment="Center" IsHitTestVisible="False"/>
              </Grid>
            </DockPanel>
          </Border>
          <CheckBox Name="ChkSelectAll" Content="Select all" DockPanel.Dock="Right"
                    Margin="0,0,14,0"/>
        </DockPanel>

        <!-- list card -->
        <Border Grid.Row="1" Background="{StaticResource PanelBrush}" CornerRadius="10"
                BorderBrush="{StaticResource EdgeBrush}" BorderThickness="1">
          <Grid>
            <DataGrid Name="GridUpdates" AutoGenerateColumns="False" CanUserAddRows="False"
                      HeadersVisibility="Column" GridLinesVisibility="None"
                      Background="Transparent" BorderThickness="0" RowHeaderWidth="0"
                      SelectionMode="Extended" SelectionUnit="FullRow" Margin="6">
              <DataGrid.Columns>
                <DataGridTemplateColumn Width="44">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                                HorizontalAlignment="Center"/>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="Update" Binding="{Binding Title}" Width="*"
                                    IsReadOnly="True" ElementStyle="{StaticResource CellText}"/>
                <DataGridTextColumn Header="Device" Binding="{Binding Device}" Width="190"
                                    IsReadOnly="True" ElementStyle="{StaticResource CellText}"/>
                <DataGridTemplateColumn Header="Type" Width="84">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <Border x:Name="pill" CornerRadius="9" Padding="10,3" Background="#FF32323A"
                              HorizontalAlignment="Left" VerticalAlignment="Center">
                        <TextBlock x:Name="pillText" Text="{Binding Type}" FontSize="11"
                                   Foreground="#FFB9B9C3"/>
                      </Border>
                      <DataTemplate.Triggers>
                        <DataTrigger Binding="{Binding Type}" Value="Driver">
                          <Setter TargetName="pill" Property="Background" Value="#333D7EFF"/>
                          <Setter TargetName="pillText" Property="Foreground" Value="#FF9DBBFF"/>
                        </DataTrigger>
                      </DataTemplate.Triggers>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="Released" Binding="{Binding Released}" Width="96"
                                    IsReadOnly="True" ElementStyle="{StaticResource CellTextMuted}"/>
                <DataGridTextColumn Header="KB" Binding="{Binding KB}" Width="96"
                                    IsReadOnly="True" ElementStyle="{StaticResource CellTextMuted}"/>
                <DataGridTextColumn Header="Size" Binding="{Binding Size}" Width="76"
                                    IsReadOnly="True" ElementStyle="{StaticResource CellTextMuted}"/>
              </DataGrid.Columns>
            </DataGrid>

            <DataGrid Name="GridHistory" AutoGenerateColumns="False" CanUserAddRows="False"
                      HeadersVisibility="Column" GridLinesVisibility="None"
                      Background="Transparent" BorderThickness="0" RowHeaderWidth="0"
                      SelectionMode="Single" SelectionUnit="FullRow" IsReadOnly="True"
                      Margin="6" Visibility="Collapsed">
              <DataGrid.GroupStyle>
                <GroupStyle>
                  <GroupStyle.HeaderTemplate>
                    <DataTemplate>
                      <StackPanel Orientation="Horizontal" Margin="6,14,0,4">
                        <TextBlock Text="{Binding Name}" FontWeight="SemiBold" FontSize="12"
                                   Foreground="#FFC9C9D2" VerticalAlignment="Center"/>
                        <Border CornerRadius="8" Background="#FF32323A" Padding="7,1"
                                Margin="8,0,0,0" VerticalAlignment="Center">
                          <TextBlock Text="{Binding ItemCount}" FontSize="10" Foreground="#FF9A9AA5"/>
                        </Border>
                      </StackPanel>
                    </DataTemplate>
                  </GroupStyle.HeaderTemplate>
                </GroupStyle>
              </DataGrid.GroupStyle>
              <DataGrid.Columns>
                <DataGridTextColumn Header="Time" Binding="{Binding Time}" Width="64"
                                    ElementStyle="{StaticResource CellTextMuted}"/>
                <DataGridTextColumn Header="Update" Binding="{Binding Title}" Width="*"
                                    ElementStyle="{StaticResource CellText}"/>
                <DataGridTemplateColumn Header="Category" Width="130">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <Border x:Name="cpill" CornerRadius="9" Padding="10,3" Background="#FF32323A"
                              HorizontalAlignment="Left" VerticalAlignment="Center">
                        <TextBlock x:Name="cpillText" Text="{Binding Category}" FontSize="11"
                                   Foreground="#FFB9B9C3"/>
                      </Border>
                      <DataTemplate.Triggers>
                        <DataTrigger Binding="{Binding Kind}" Value="Driver">
                          <Setter TargetName="cpill" Property="Background" Value="#333D7EFF"/>
                          <Setter TargetName="cpillText" Property="Foreground" Value="#FF9DBBFF"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Kind}" Value="Store">
                          <Setter TargetName="cpill" Property="Background" Value="#338B5CF6"/>
                          <Setter TargetName="cpillText" Property="Foreground" Value="#FFC9B8F7"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Kind}" Value="Defender">
                          <Setter TargetName="cpill" Property="Background" Value="#332FA3A0"/>
                          <Setter TargetName="cpillText" Property="Foreground" Value="#FF8FD6D3"/>
                        </DataTrigger>
                      </DataTemplate.Triggers>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTemplateColumn Header="Result" Width="104">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <Border x:Name="rpill" CornerRadius="9" Padding="10,3" Background="#FF32323A"
                              HorizontalAlignment="Left" VerticalAlignment="Center">
                        <TextBlock x:Name="rpillText" Text="{Binding Result}" FontSize="11"
                                   Foreground="#FFB9B9C3"/>
                      </Border>
                      <DataTemplate.Triggers>
                        <DataTrigger Binding="{Binding Result}" Value="Succeeded">
                          <Setter TargetName="rpill" Property="Background" Value="#332FA35C"/>
                          <Setter TargetName="rpillText" Property="Foreground" Value="#FF8FD6A8"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Result}" Value="Failed">
                          <Setter TargetName="rpill" Property="Background" Value="#33E81123"/>
                          <Setter TargetName="rpillText" Property="Foreground" Value="#FFFF9AA3"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding Result}" Value="Removed">
                          <Setter TargetName="rpill" Property="Background" Value="#33E8A33D"/>
                          <Setter TargetName="rpillText" Property="Foreground" Value="#FFE8C08A"/>
                        </DataTrigger>
                      </DataTemplate.Triggers>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
                <DataGridTextColumn Header="KB" Binding="{Binding KB}" Width="96"
                                    ElementStyle="{StaticResource CellTextMuted}"/>
              </DataGrid.Columns>
            </DataGrid>

            <DataGrid Name="GridDevices" AutoGenerateColumns="False" CanUserAddRows="False"
                      HeadersVisibility="Column" GridLinesVisibility="None"
                      Background="Transparent" BorderThickness="0" RowHeaderWidth="0"
                      SelectionMode="Single" SelectionUnit="FullRow" IsReadOnly="True"
                      Margin="6" Visibility="Collapsed">
              <DataGrid.GroupStyle>
                <GroupStyle>
                  <GroupStyle.HeaderTemplate>
                    <DataTemplate>
                      <StackPanel Orientation="Horizontal" Margin="6,14,0,4">
                        <TextBlock Text="{Binding Name}" FontWeight="SemiBold" FontSize="12"
                                   Foreground="#FFC9C9D2" VerticalAlignment="Center"/>
                        <Border CornerRadius="8" Background="#FF32323A" Padding="7,1"
                                Margin="8,0,0,0" VerticalAlignment="Center">
                          <TextBlock Text="{Binding ItemCount}" FontSize="10" Foreground="#FF9A9AA5"/>
                        </Border>
                      </StackPanel>
                    </DataTemplate>
                  </GroupStyle.HeaderTemplate>
                </GroupStyle>
              </DataGrid.GroupStyle>
              <DataGrid.Columns>
                <DataGridTextColumn Header="Device" Binding="{Binding Name}" Width="*"
                                    ElementStyle="{StaticResource CellText}"/>
                <DataGridTextColumn Header="Class" Binding="{Binding Class}" Width="110"
                                    ElementStyle="{StaticResource CellTextMuted}"/>
                <DataGridTextColumn Header="Driver version" Binding="{Binding Version}" Width="130"
                                    ElementStyle="{StaticResource CellTextMuted}"/>
                <DataGridTextColumn Header="Driver date" Binding="{Binding DriverDate}" Width="96"
                                    ElementStyle="{StaticResource CellTextMuted}"/>
                <DataGridTemplateColumn Header="Status" Width="104">
                  <DataGridTemplateColumn.CellTemplate>
                    <DataTemplate>
                      <Border x:Name="spill" CornerRadius="9" Padding="10,3" Background="#FF32323A"
                              HorizontalAlignment="Left" VerticalAlignment="Center">
                        <TextBlock x:Name="spillText" Text="{Binding Status}" FontSize="11"
                                   Foreground="#FFB9B9C3"/>
                      </Border>
                      <DataTemplate.Triggers>
                        <DataTrigger Binding="{Binding StatusKind}" Value="Ok">
                          <Setter TargetName="spill" Property="Background" Value="#332FA35C"/>
                          <Setter TargetName="spillText" Property="Foreground" Value="#FF8FD6A8"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding StatusKind}" Value="NoDriver">
                          <Setter TargetName="spill" Property="Background" Value="#33E81123"/>
                          <Setter TargetName="spillText" Property="Foreground" Value="#FFFF9AA3"/>
                        </DataTrigger>
                        <DataTrigger Binding="{Binding StatusKind}" Value="Problem">
                          <Setter TargetName="spill" Property="Background" Value="#33E8A33D"/>
                          <Setter TargetName="spillText" Property="Foreground" Value="#FFE8C08A"/>
                        </DataTrigger>
                      </DataTemplate.Triggers>
                    </DataTemplate>
                  </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
              </DataGrid.Columns>
            </DataGrid>

            <!-- empty state overlay -->
            <StackPanel Name="EmptyState" VerticalAlignment="Center" HorizontalAlignment="Center"
                        IsHitTestVisible="False">
              <Border Width="64" Height="64" CornerRadius="32" Background="#FF26262D"
                      HorizontalAlignment="Center">
                <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="26"
                           Foreground="#FF6E6E7A" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock Name="EmptyTitle" Text="No updates listed yet" FontSize="15" FontWeight="SemiBold"
                         Foreground="#FFC9C9D2" HorizontalAlignment="Center" Margin="0,14,0,4"/>
              <TextBlock Name="EmptySub" Text="Click 'Scan for updates' to check Microsoft Update."
                         FontSize="12" Foreground="{StaticResource MutedBrush}" HorizontalAlignment="Center"/>
            </StackPanel>
          </Grid>
        </Border>

        <!-- details pane for the selected row -->
        <Border Name="DetailsCard" Grid.Row="2" Background="{StaticResource PanelBrush}"
                CornerRadius="10" BorderBrush="{StaticResource EdgeBrush}" BorderThickness="1"
                Padding="14,10" Margin="0,12,0,0" Visibility="Collapsed">
          <StackPanel>
            <TextBlock Name="DetailTitle" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}"
                       TextTrimming="CharacterEllipsis"/>
            <TextBlock Name="DetailMeta" FontSize="11" Foreground="{StaticResource MutedBrush}"
                       Margin="0,3,0,5" TextTrimming="CharacterEllipsis"/>
            <TextBlock Name="DetailDesc" FontSize="12" Foreground="#FFB9B9C3" TextWrapping="Wrap"
                       MaxHeight="50" TextTrimming="CharacterEllipsis"/>
            <StackPanel Name="DetailActions" Orientation="Horizontal" Margin="0,8,0,0"
                        Visibility="Collapsed">
              <Button Name="BtnCopyHwid" Style="{StaticResource GhostButton}"
                      Content="Copy hardware ID"/>
              <Button Name="BtnCatalog" Style="{StaticResource GhostButton}" Margin="8,0,0,0"
                      Content="Search Microsoft Update Catalog"/>
            </StackPanel>
          </StackPanel>
        </Border>

        <!-- restore point toggle + install -->
        <DockPanel Name="InstallBar" Grid.Row="3" Margin="0,12,0,14" LastChildFill="False">
          <CheckBox Name="ChkRestore" DockPanel.Dock="Left" IsChecked="True"
                    Style="{StaticResource ToggleSwitch}"
                    Content="Create a restore point before installing"/>
          <Button Name="BtnInstall" DockPanel.Dock="Right" Height="36"
                  Background="#FF2FA35C" IsEnabled="False">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="13"
                         VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock Name="BtnInstallText" Text="Install selected" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </DockPanel>

        <!-- activity log card -->
        <Border Grid.Row="4" Background="{StaticResource PanelBrush}" CornerRadius="10"
                BorderBrush="{StaticResource EdgeBrush}" BorderThickness="1">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <DockPanel Grid.Row="0" Margin="14,10,10,4" LastChildFill="False">
              <TextBlock Text="ACTIVITY" FontSize="10" FontWeight="SemiBold"
                         Foreground="{StaticResource MutedBrush}" VerticalAlignment="Center"
                         DockPanel.Dock="Left"/>
              <Button Name="BtnClearLog" Style="{StaticResource GhostButton}" Content="Clear"
                      DockPanel.Dock="Right"/>
            </DockPanel>
            <TextBox Name="LogBox" Grid.Row="1" Background="Transparent" Foreground="#FF9FD6AE"
                     BorderThickness="0" FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                     TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="12,2,12,10"/>
          </Grid>
        </Border>

        <!-- status bar -->
        <DockPanel Grid.Row="5" Margin="2,10,2,0" LastChildFill="False">
          <TextBlock Name="StatusText" Text="Ready." Foreground="{StaticResource MutedBrush}"
                     VerticalAlignment="Center" DockPanel.Dock="Left"/>
          <TextBlock Text="tip: click a row for details - double-click or Space to toggle" FontSize="11"
                     Foreground="#FF5E5E68" VerticalAlignment="Center" DockPanel.Dock="Right"/>
        </DockPanel>
      </Grid>

      <!-- changelog overlay -->
      <Grid Name="ChangelogOverlay" Grid.Row="0" Grid.RowSpan="3" Visibility="Collapsed">
        <Border Name="ChangelogBackdrop" Background="#CC101013"
                WindowChrome.IsHitTestVisibleInChrome="True"/>
        <Border Width="580" MaxHeight="540" Background="#FF212127" CornerRadius="12"
                BorderBrush="#FF3A3A42" BorderThickness="1"
                VerticalAlignment="Center" HorizontalAlignment="Center"
                WindowChrome.IsHitTestVisibleInChrome="True">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <DockPanel Grid.Row="0" Margin="20,16,12,6" LastChildFill="False">
              <StackPanel DockPanel.Dock="Left">
                <TextBlock Text="What is new" FontSize="16" FontWeight="SemiBold"
                           Foreground="{StaticResource TextBrush}"/>
                <TextBlock Text="Everything that changed, version by version" FontSize="11"
                           Foreground="{StaticResource MutedBrush}" Margin="0,2,0,0"/>
              </StackPanel>
              <Button Name="BtnChangelogClose" Style="{StaticResource GhostButton}"
                      DockPanel.Dock="Right" VerticalAlignment="Top">
                <TextBlock Text="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="11"/>
              </Button>
            </DockPanel>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="20,4,12,18">
              <StackPanel Name="ChangelogPanel" Margin="0,0,8,0"/>
            </ScrollViewer>
          </Grid>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($node in $xaml.SelectNodes('//*[@Name]')) {
    $sync[$node.Name] = $window.FindName($node.Name)
}
$sync.Window = $window
$sync.BtnVersionText.Text = "v$AppVer"

# per-view empty-state texts
$sync.UEmptyT = 'No updates listed yet'
$sync.UEmptyS = "Click 'Scan for updates' to check Microsoft Update."
$sync.HEmptyT = 'History not loaded yet'
$sync.HEmptyS = 'It loads automatically when you open this view.'
$sync.DEmptyT = 'Devices not scanned yet'
$sync.DEmptyS = 'It loads automatically when you open this view.'

# ----------------------------------------------------------- UI helpers
function Add-Log {
    param([string]$Message)
    $sync.LogQueue.Enqueue("[$((Get-Date).ToString('HH:mm:ss'))] $Message")
}

function Set-UpdatesEmpty {
    param([string]$Title, [string]$Sub)
    $sync.UEmptyT = $Title; $sync.UEmptyS = $Sub
}

function Set-HistoryEmpty {
    param([string]$Title, [string]$Sub)
    $sync.HEmptyT = $Title; $sync.HEmptyS = $Sub
}

function Set-DevicesEmpty {
    param([string]$Title, [string]$Sub)
    $sync.DEmptyT = $Title; $sync.DEmptyS = $Sub
}

function Get-ActiveView {
    if ($sync.ViewHistory.IsChecked) { return 'History' }
    if ($sync.ViewDevices.IsChecked) { return 'Devices' }
    return 'Updates'
}

function Refresh-EmptyState {
    $view = Get-ActiveView
    $source = $sync.GridUpdates.ItemsSource
    if ($view -eq 'History') { $source = $sync.GridHistory.ItemsSource }
    if ($view -eq 'Devices') { $source = $sync.GridDevices.ItemsSource }
    $hasRows = ($source -and $source.Count -gt 0)
    if ($hasRows) {
        $sync.EmptyState.Visibility = 'Collapsed'
    } else {
        if ($view -eq 'History') { $sync.EmptyTitle.Text = $sync.HEmptyT; $sync.EmptySub.Text = $sync.HEmptyS }
        elseif ($view -eq 'Devices') { $sync.EmptyTitle.Text = $sync.DEmptyT; $sync.EmptySub.Text = $sync.DEmptyS }
        else { $sync.EmptyTitle.Text = $sync.UEmptyT; $sync.EmptySub.Text = $sync.UEmptyS }
        $sync.EmptyState.Visibility = 'Visible'
    }
}

function Update-SelCount {
    $total = 0
    $sel   = 0
    if ($sync.Items) {
        $total = $sync.Items.Count
        $sel   = @($sync.Items | Where-Object { $_.IsSelected }).Count
    }
    if ($sel -gt 0) { $sync.BtnInstallText.Text = "Install $sel selected" }
    else            { $sync.BtnInstallText.Text = 'Install selected' }
    $sync.BtnInstall.IsEnabled   = (-not $sync.Busy) -and ($sel -gt 0)
    $sync.ChkSelectAll.IsChecked = ($total -gt 0 -and $sel -eq $total)
}

function Set-Busy {
    param([bool]$On, [string]$Status = '')
    $sync.BtnScan.IsEnabled           = -not $On
    $sync.BtnHistoryRefresh.IsEnabled = -not $On
    $sync.BtnDevicesRefresh.IsEnabled = -not $On
    $sync.RadDrivers.IsEnabled        = -not $On
    $sync.RadAll.IsEnabled            = -not $On
    $sync.ViewUpdates.IsEnabled       = -not $On
    $sync.ViewHistory.IsEnabled       = -not $On
    $sync.ViewDevices.IsEnabled       = -not $On
    $sync.ChkSelectAll.IsEnabled      = -not $On
    if ($On) {
        $sync.BtnInstall.IsEnabled   = $false
        $sync.TopProgress.Visibility = 'Visible'
    } else {
        $sync.TopProgress.Visibility = 'Collapsed'
        Update-SelCount
    }
    if ($Status) { $sync.StatusText.Text = $Status }
}

function Show-View {
    param([string]$View)
    # everything off first
    $sync.GridUpdates.Visibility       = 'Collapsed'
    $sync.GridHistory.Visibility       = 'Collapsed'
    $sync.GridDevices.Visibility       = 'Collapsed'
    $sync.BtnScan.Visibility           = 'Collapsed'
    $sync.BtnHistoryRefresh.Visibility = 'Collapsed'
    $sync.BtnDevicesRefresh.Visibility = 'Collapsed'
    $sync.ScopeBox.Visibility          = 'Collapsed'
    $sync.ChkSelectAll.Visibility      = 'Collapsed'
    $sync.InstallBar.Visibility        = 'Collapsed'
    $sync.DetailsCard.Visibility       = 'Collapsed'
    $sync.BtnOem.Visibility            = 'Collapsed'
    $sync.BtnGpu.Visibility            = 'Collapsed'

    if ($View -eq 'History') {
        $sync.GridHistory.Visibility       = 'Visible'
        $sync.BtnHistoryRefresh.Visibility = 'Visible'
    }
    elseif ($View -eq 'Devices') {
        $sync.GridDevices.Visibility       = 'Visible'
        $sync.BtnDevicesRefresh.Visibility = 'Visible'
        if ($sync.DevicesLoaded -and $sync.OemUrl) { $sync.BtnOem.Visibility = 'Visible' }
        if ($sync.DevicesLoaded -and $sync.GpuUrl) { $sync.BtnGpu.Visibility = 'Visible' }
        if ($sync.GridDevices.SelectedItem) { $sync.DetailsCard.Visibility = 'Visible' }
    }
    else {
        $sync.GridUpdates.Visibility  = 'Visible'
        $sync.BtnScan.Visibility      = 'Visible'
        $sync.ScopeBox.Visibility     = 'Visible'
        $sync.ChkSelectAll.Visibility = 'Visible'
        $sync.InstallBar.Visibility   = 'Visible'
        if ($sync.GridUpdates.SelectedItem) { $sync.DetailsCard.Visibility = 'Visible' }
    }
    Refresh-EmptyState
}

function Show-Changelog {
    $sync.ChangelogPanel.Children.Clear()
    $bullet = [string][char]0x2022
    $first  = $true
    foreach ($entry in $ChangeLog) {
        $header = New-Object System.Windows.Controls.StackPanel
        $header.Orientation = 'Horizontal'
        if ($first) { $header.Margin = '0,2,0,2' } else { $header.Margin = '0,16,0,2' }
        $first = $false

        $pillBorder = New-Object System.Windows.Controls.Border
        $pillBorder.CornerRadius = '8'
        $pillBorder.Background   = '#333D7EFF'
        $pillBorder.Padding      = '8,2,8,2'
        $pillText = New-Object System.Windows.Controls.TextBlock
        $pillText.Text       = "v$($entry.Version)"
        $pillText.FontSize   = 11
        $pillText.FontWeight = 'SemiBold'
        $pillText.Foreground = '#FF9DBBFF'
        $pillBorder.Child = $pillText
        [void]$header.Children.Add($pillBorder)

        $dateText = New-Object System.Windows.Controls.TextBlock
        $dateText.Text = $entry.Date
        $dateText.FontSize = 11
        $dateText.Foreground = '#FF9A9AA5'
        $dateText.Margin = '8,0,0,0'
        $dateText.VerticalAlignment = 'Center'
        [void]$header.Children.Add($dateText)
        [void]$sync.ChangelogPanel.Children.Add($header)

        foreach ($change in $entry.Changes) {
            $line = New-Object System.Windows.Controls.TextBlock
            $line.Text = "$bullet  $change"
            $line.TextWrapping = 'Wrap'
            $line.FontSize = 12
            $line.Foreground = '#FFB9B9C3'
            $line.Margin = '4,4,0,0'
            [void]$sync.ChangelogPanel.Children.Add($line)
        }
    }
    $sync.ChangelogOverlay.Visibility = 'Visible'
}

function Start-Worker {
    param([scriptblock]$Script, [hashtable]$Vars = @{})
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    foreach ($key in $Vars.Keys) { $rs.SessionStateProxy.SetVariable($key, $Vars[$key]) }
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Script)
    $sync.Busy = $true
    [void]$ps.BeginInvoke()
    return $ps
}

# ------------------------------------------------------- worker: scan
$ScanScript = {
    function Log { param($m) $sync.LogQueue.Enqueue("[$((Get-Date).ToString('HH:mm:ss'))] $m") }
    $ProgressPreference = 'SilentlyContinue'
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        if ($DriversOnly) { Log 'Scanning Microsoft Update for DRIVER updates... (can take a minute or two)' }
        else              { Log 'Scanning Microsoft Update for ALL updates... (can take a minute or two)' }

        $params = @{ MicrosoftUpdate = $true; ErrorAction = 'Stop' }
        if ($DriversOnly) { $params['UpdateType'] = 'Driver' }
        $found = @(Get-WindowsUpdate @params)

        $list = foreach ($u in $found) {
            $type = 'Software'
            if ($DriversOnly) { $type = 'Driver' }
            else {
                try { if (@($u.Categories | Where-Object { $_.Name -eq 'Drivers' }).Count -gt 0) { $type = 'Driver' } } catch {}
                try { if ($u.DriverClass) { $type = 'Driver' } } catch {}
            }
            $kb = ''
            try { if ($u.KB) { $kb = [string]$u.KB } } catch {}
            $id = ''
            try { $id = [string]$u.Identity.UpdateID } catch {}

            # what the update targets (drivers expose the device model)
            $device = ''
            try { if ($u.DriverModel) { $device = [string]$u.DriverModel } } catch {}
            $manu = ''
            try { if ($u.DriverManufacturer) { $manu = [string]$u.DriverManufacturer } } catch {}
            if (-not $manu) { try { if ($u.DriverProvider) { $manu = [string]$u.DriverProvider } } catch {} }

            # when the driver itself is from; falls back to the WU publish date
            $released = ''
            try { if ($u.DriverVerDate) { $released = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch {}
            if (-not $released) {
                try { if ($u.LastDeploymentChangeTime) { $released = ([datetime]$u.LastDeploymentChangeTime).ToString('yyyy-MM-dd') } } catch {}
            }

            $desc = ''
            try { if ($u.Description) { $desc = ([string]$u.Description) -replace '\s+', ' ' } } catch {}

            [pscustomobject]@{
                Title        = [string]$u.Title
                Device       = $device
                Type         = $type
                Released     = $released
                KB           = $kb
                Size         = [string]$u.Size
                UpdateID     = $id
                Manufacturer = $manu
                Description  = $desc
            }
        }
        $sync.Results = @($list)
        Log "Found $($sync.Results.Count) update(s)."
        if ($sync.Results.Count -eq 0) { Log 'Nothing to do - this machine looks up to date.' }
    }
    catch {
        $sync.Results = @()
        Log "ERROR while scanning: $($_.Exception.Message)"
    }
    finally {
        $sync.ScanDone = $true
        $sync.Busy = $false
    }
}

# ---------------------------------------------------- worker: history
$HistoryScript = {
    function Log { param($m) $sync.LogQueue.Enqueue("[$((Get-Date).ToString('HH:mm:ss'))] $m") }
    $ProgressPreference = 'SilentlyContinue'
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Log 'Loading Windows Update history...'
        $hist = $null
        try   { $hist = @(Get-WUHistory -Last 300 -ErrorAction Stop) }
        catch { $hist = @(Get-WUHistory -ErrorAction Stop | Select-Object -First 300) }

        $today     = (Get-Date).Date
        $yesterday = $today.AddDays(-1)

        $raw = foreach ($h in $hist) {
            $dt = $null
            try { $dt = [datetime]$h.Date } catch {}
            if (-not $dt) { continue }

            $day = $dt.ToString('d. MMMM yyyy')
            if ($dt.Date -eq $today)     { $day = 'Today' }
            elseif ($dt.Date -eq $yesterday) { $day = 'Yesterday' }

            $kb = ''
            try { if ($h.KB) { $kb = [string]$h.KB } } catch {}
            $title = ([string]$h.Title).Trim()
            if (-not $kb -and $title -match '(KB\d{5,})') { $kb = $Matches[1] }
            $op = ''
            try { $op = ([string]$h.Operationname).Trim() } catch {}
            $result = [string]$h.Result
            if ($op -match 'Uninstall' -and $result -eq 'Succeeded') { $result = 'Removed' }

            # ------- make the raw Windows Update title human readable -------
            $kind  = 'Update'
            $cat   = 'Update'
            $clean = $title

            if ($title -match '^[0-9A-Z]{10,14}-(?<name>.+)$') {
                # Store app entries like 9NRZT3Q9R3DL-Microsoft.WindowsAppRuntime.2
                $clean = $Matches['name']
                $kind  = 'Store'
                $cat   = 'Store app'
            }
            elseif ($title -match 'KB2267602' -or $title -match '(?i)defender') {
                $kind = 'Defender'
                $cat  = 'Defender'
            }
            elseif ($title -notmatch 'KB\d{5,}') {
                $parts = @($title -split ' - ')
                if ($parts.Count -ge 3) {
                    # driver-style title: Manufacturer - Class - <date?> - <device?> - <version?>
                    $kind = 'Driver'
                    $mfr  = $parts[0].Trim()
                    $cls  = $parts[1].Trim()
                    $cat  = $cls
                    $rest = @()
                    $ver  = ''
                    $drvDate = ''
                    foreach ($seg in $parts[2..($parts.Count - 1)]) {
                        $seg = $seg.Trim()
                        $parsed = [datetime]::MinValue
                        $isDate = [datetime]::TryParse($seg,
                                    [System.Globalization.CultureInfo]::InvariantCulture,
                                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
                        if ($isDate) {
                            # Intel dates some drivers 1968 on purpose; hide anything that old
                            if ($parsed.Year -ge 1990) { $drvDate = $parsed.ToString('yyyy-MM-dd') }
                            continue
                        }
                        if ($seg -match '^[vV]?\d+(\.\d+)+$') { $ver = $seg; continue }
                        $rest += $seg
                    }
                    if ($rest.Count -gt 0) {
                        $clean = ($rest -join ' - ')
                        if ($ver) { $clean += " $ver" }
                    } else {
                        $clean = "$mfr $cls driver"
                        if ($ver) { $clean += " $ver" }
                    }
                    if ($drvDate) { $clean += " (driver from $drvDate)" }
                }
            }

            [pscustomobject]@{
                SortKey  = $dt.ToString('yyyy-MM-dd HH:mm:ss')
                Day      = $day
                Time     = $dt.ToString('HH:mm')
                Title    = $clean
                Category = $cat
                Kind     = $kind
                Result   = $result
                KB       = $kb
                Op       = $op
            }
        }

        # collapse duplicates within the same day (same title + outcome)
        $final = foreach ($g in ($raw | Group-Object { $_.Day + '|' + $_.Title + '|' + $_.Result + '|' + $_.Op })) {
            $top = $g.Group | Sort-Object SortKey -Descending | Select-Object -First 1
            if ($g.Count -gt 1) { $top.Title = "$($top.Title)  (x$($g.Count))" }
            $top
        }

        $sync.HistoryResults = @($final | Sort-Object SortKey -Descending)
        Log "Loaded $($sync.HistoryResults.Count) history entries ($($raw.Count) raw, duplicates collapsed)."
    }
    catch {
        $sync.HistoryResults = @()
        Log "ERROR loading history: $($_.Exception.Message)"
    }
    finally {
        $sync.HistoryDone = $true
        $sync.Busy = $false
    }
}

# ---------------------------------------------------- worker: devices
$DevicesScript = {
    function Log { param($m) $sync.LogQueue.Enqueue("[$((Get-Date).ToString('HH:mm:ss'))] $m") }
    $ProgressPreference = 'SilentlyContinue'
    try {
        Log 'Scanning installed devices and drivers... (10-20 seconds)'

        # index signed drivers by device instance path
        $drv = @{}
        foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) {
            if ($d.DeviceID -and -not $drv.ContainsKey($d.DeviceID)) { $drv[$d.DeviceID] = $d }
        }

        $problems = 0
        $list = foreach ($e in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)) {
            $code = 0
            try { if ($null -ne $e.ConfigManagerErrorCode) { $code = [int]$e.ConfigManagerErrorCode } } catch {}
            $d = $null
            if ($e.PNPDeviceID -and $drv.ContainsKey($e.PNPDeviceID)) { $d = $drv[$e.PNPDeviceID] }

            # skip healthy entries that have no real driver (software/phantom devices)
            if ($code -eq 0 -and -not $d) { continue }

            $ver = ''; $date = ''; $prov = ''; $inf = ''
            if ($d) {
                $ver  = [string]$d.DriverVersion
                try { if ($d.DriverDate) { $date = ([datetime]$d.DriverDate).ToString('yyyy-MM-dd') } } catch {}
                $prov = [string]$d.DriverProviderName
                $inf  = [string]$d.InfName
            }

            $cls = [string]$e.PNPClass
            if (-not $cls) { $cls = 'Other' }

            $statusKind = 'Ok'; $status = 'OK'
            if ($code -eq 22)     { $statusKind = 'Disabled'; $status = 'Disabled' }
            elseif ($code -eq 28) { $statusKind = 'NoDriver'; $status = 'No driver' }
            elseif ($code -ne 0)  { $statusKind = 'Problem';  $status = "Error $code" }

            $grp = $cls
            if ($code -ne 0 -and $code -ne 22) { $grp = 'Needs attention'; $problems++ }

            $hwid = ''
            try { if ($e.HardwareID -and @($e.HardwareID).Count -gt 0) { $hwid = [string]@($e.HardwareID)[0] } } catch {}

            $name = [string]$e.Name
            if (-not $name) { $name = 'Unknown device' }

            [pscustomobject]@{
                SortA      = if ($grp -eq 'Needs attention') { 0 } else { 1 }
                Name       = $name
                Group      = $grp
                Class      = $cls
                Version    = $ver
                DriverDate = $date
                Status     = $status
                StatusKind = $statusKind
                HardwareID = $hwid
                Provider   = $prov
                Inf        = $inf
            }
        }
        $sync.DevicesResults = @($list | Sort-Object SortA, Group, Name)

        # vendor quick links (safe escape hatches for drivers WU does not carry)
        $oemLabel = ''; $oemUrl = ''
        try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            $manu  = ([string]$cs.Manufacturer).Trim()
            $model = ([string]$cs.Model).Trim()
            if ($manu -and $manu -notmatch '(?i)O\.?E\.?M|System manufacturer|To be filled') {
                $oemLabel = "$manu drivers"
                if     ($manu -match '(?i)dell')               { $oemUrl = 'https://www.dell.com/support/home/' }
                elseif ($manu -match '(?i)lenovo')             { $oemUrl = 'https://support.lenovo.com' }
                elseif ($manu -match '(?i)hp|hewlett')         { $oemUrl = 'https://support.hp.com' }
                elseif ($manu -match '(?i)asus')               { $oemUrl = 'https://www.asus.com/support/download-center/' }
                elseif ($manu -match '(?i)acer')               { $oemUrl = 'https://www.acer.com/support' }
                elseif ($manu -match '(?i)msi|micro-star')     { $oemUrl = 'https://www.msi.com/support' }
                elseif ($manu -match '(?i)gigabyte')           { $oemUrl = 'https://www.gigabyte.com/Support' }
                elseif ($manu -match '(?i)asrock')             { $oemUrl = 'https://www.asrock.com/support/' }
                elseif ($manu -match '(?i)microsoft')          { $oemUrl = 'https://support.microsoft.com/surface' }
                else { $oemUrl = 'https://www.google.com/search?q=' + [uri]::EscapeDataString("$manu $model drivers") }
            }
        } catch {}
        $sync.OemLabel = $oemLabel
        $sync.OemUrl   = $oemUrl

        $gpuLabel = ''; $gpuUrl = ''
        try {
            $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($gpu.Count -gt 0) {
                $gname = [string]$gpu[0].Name
                if     ($gname -match '(?i)nvidia|geforce|quadro') { $gpuLabel = 'NVIDIA drivers'; $gpuUrl = 'https://www.nvidia.com/Download/index.aspx' }
                elseif ($gname -match '(?i)amd|radeon')            { $gpuLabel = 'AMD drivers';    $gpuUrl = 'https://www.amd.com/en/support' }
                elseif ($gname -match '(?i)intel')                 { $gpuLabel = 'Intel drivers';  $gpuUrl = 'https://www.intel.com/content/www/us/en/support/detect.html' }
                elseif ($gname) { $gpuLabel = 'GPU drivers'; $gpuUrl = 'https://www.google.com/search?q=' + [uri]::EscapeDataString("$gname driver download") }
            }
        } catch {}
        $sync.GpuLabel = $gpuLabel
        $sync.GpuUrl   = $gpuUrl

        Log "Found $($sync.DevicesResults.Count) devices with drivers - $problems need attention."
        if ($problems -eq 0) { Log 'No problem devices detected. Nice and healthy!' }
        else { Log 'Tip: select a problem device and use "Search Microsoft Update Catalog" with its hardware ID.' }
    }
    catch {
        $sync.DevicesResults = @()
        Log "ERROR scanning devices: $($_.Exception.Message)"
    }
    finally {
        $sync.DevicesDone = $true
        $sync.Busy = $false
    }
}

# ---------------------------------------------------- worker: install
$InstallScript = {
    function Log { param($m) $sync.LogQueue.Enqueue("[$((Get-Date).ToString('HH:mm:ss'))] $m") }
    $ProgressPreference = 'SilentlyContinue'
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop

        if ($MakeRestorePoint) {
            Log 'Creating a system restore point first...'
            try {
                # best effort: make sure System Restore is enabled on the system drive
                Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' `
                    -MethodName 'Enable' -Arguments @{ Drive = "$env:SystemDrive\" } `
                    -ErrorAction SilentlyContinue | Out-Null
                # allow more than one restore point per 24 hours
                New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
                    -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force `
                    -ErrorAction SilentlyContinue | Out-Null

                $rp = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' `
                    -MethodName 'CreateRestorePoint' -Arguments @{
                        Description      = "DriverDrop before update $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"
                        RestorePointType = [uint32]10    # DEVICE_DRIVER_INSTALL
                        EventType        = [uint32]100   # BEGIN_SYSTEM_CHANGE
                    } -ErrorAction Stop
                if ($rp.ReturnValue -eq 0) { Log 'Restore point created successfully.' }
                else { Log "Restore point call returned code $($rp.ReturnValue) - continuing anyway." }
            }
            catch {
                Log "WARNING: could not create a restore point ($($_.Exception.Message)). Continuing without one."
            }
        }

        Log "Downloading and installing $($UpdateIDs.Count) update(s) - please leave the window open..."
        $output = Install-WindowsUpdate -MicrosoftUpdate -UpdateID $UpdateIDs `
                    -AcceptAll -IgnoreReboot -Confirm:$false -Verbose *>&1

        foreach ($o in $output) {
            if     ($o -is [System.Management.Automation.VerboseRecord]) { Log $o.Message }
            elseif ($o -is [System.Management.Automation.WarningRecord]) { Log "WARNING: $($o.Message)" }
            elseif ($o -is [System.Management.Automation.ErrorRecord])   { Log "ERROR: $($o.Exception.Message)" }
            elseif ($o.PSObject.Properties['Result'] -and $o.PSObject.Properties['Title']) {
                Log "$($o.Result): $($o.Title)"
            }
        }

        try { $sync.RebootRequired = [bool](Get-WURebootStatus -Silent) } catch { $sync.RebootRequired = $false }
        Log 'Install run finished.'
        if ($sync.RebootRequired) { Log 'A reboot is required to finish installing.' }
    }
    catch {
        Log "ERROR while installing: $($_.Exception.Message)"
    }
    finally {
        $sync.InstallDone = $true
        $sync.Busy = $false
    }
}

# ------------------------------------------------- window chrome events
$sync.BtnMin.Add_Click({ $sync.Window.WindowState = 'Minimized' })
$sync.BtnMax.Add_Click({
    if ($sync.Window.WindowState -eq 'Maximized') { $sync.Window.WindowState = 'Normal' }
    else { $sync.Window.WindowState = 'Maximized' }
})
$sync.BtnClose.Add_Click({ $sync.Window.Close() })
$window.Add_StateChanged({
    if ($sync.Window.WindowState -eq 'Maximized') {
        # compensate for the invisible resize border so content is not clipped
        $sync.RootBorder.Padding = New-Object System.Windows.Thickness 7
        $sync.MaxIcon.Text = [string][char]0xE923
    } else {
        $sync.RootBorder.Padding = New-Object System.Windows.Thickness 0
        $sync.MaxIcon.Text = [string][char]0xE922
    }
})

# --------------------------------------------------- changelog overlay
$sync.BtnVersion.Add_Click({ Show-Changelog })
$sync.BtnChangelogClose.Add_Click({ $sync.ChangelogOverlay.Visibility = 'Collapsed' })
$sync.ChangelogBackdrop.Add_MouseLeftButtonDown({ $sync.ChangelogOverlay.Visibility = 'Collapsed' })
$window.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq 'Escape' -and $sync.ChangelogOverlay.Visibility -eq 'Visible') {
        $sync.ChangelogOverlay.Visibility = 'Collapsed'
        $e.Handled = $true
    }
})

# --------------------------------------------- history / devices loading
function Start-HistoryLoad {
    if ($sync.Busy) { return }
    Set-HistoryEmpty 'Loading update history...' 'One moment.'
    Refresh-EmptyState
    Set-Busy $true 'Loading update history...'
    $null = Start-Worker -Script $HistoryScript
}

function Start-DevicesLoad {
    if ($sync.Busy) { return }
    Set-DevicesEmpty 'Scanning devices...' 'Collecting every installed driver, 10-20 seconds.'
    Refresh-EmptyState
    Set-Busy $true 'Scanning devices and drivers...'
    $null = Start-Worker -Script $DevicesScript
}

# ------------------------------------------------------------ UI events
$sync.ViewUpdates.Add_Click({ Show-View 'Updates' })
$sync.ViewHistory.Add_Click({
    Show-View 'History'
    if (-not $sync.HistoryLoaded) { Start-HistoryLoad }
})
$sync.ViewDevices.Add_Click({
    Show-View 'Devices'
    if (-not $sync.DevicesLoaded) { Start-DevicesLoad }
})
$sync.BtnHistoryRefresh.Add_Click({ Start-HistoryLoad })
$sync.BtnDevicesRefresh.Add_Click({ Start-DevicesLoad })

$sync.BtnOem.Add_Click({ if ($sync.OemUrl) { Start-Process $sync.OemUrl } })
$sync.BtnGpu.Add_Click({ if ($sync.GpuUrl) { Start-Process $sync.GpuUrl } })

$sync.BtnCopyHwid.Add_Click({
    if ($sync.CurrentHwid) {
        try {
            [System.Windows.Clipboard]::SetText($sync.CurrentHwid)
            $sync.StatusText.Text = "Hardware ID copied: $($sync.CurrentHwid)"
        } catch {}
    }
})
$sync.BtnCatalog.Add_Click({
    if ($sync.CurrentHwid) {
        $url = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' +
               [uri]::EscapeDataString($sync.CurrentHwid)
        Start-Process $url
    }
})

$sync.BtnScan.Add_Click({
    if ($sync.Busy) { return }
    $sync.Items = $null
    $sync.GridUpdates.ItemsSource = $null
    $sync.FilterBox.Text = ''
    Set-UpdatesEmpty 'Scanning Microsoft Update...' 'This can take a minute or two.'
    Refresh-EmptyState
    Set-Busy $true 'Scanning for updates...'
    Add-Log 'Starting scan...'
    $null = Start-Worker -Script $ScanScript -Vars @{ DriversOnly = [bool]$sync.RadDrivers.IsChecked }
})

$sync.ChkSelectAll.Add_Click({
    if (-not $sync.GridUpdates.ItemsSource) { $sync.ChkSelectAll.IsChecked = $false; return }
    $state = [bool]$sync.ChkSelectAll.IsChecked
    # apply to the visible (filtered) rows only
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($sync.GridUpdates.ItemsSource)
    foreach ($item in $view) { $item.IsSelected = $state }
    $view.Refresh()
    Update-SelCount
})

$sync.FilterBox.Add_TextChanged({
    if ([string]::IsNullOrEmpty($sync.FilterBox.Text)) { $sync.FilterHint.Visibility = 'Visible' }
    else { $sync.FilterHint.Visibility = 'Collapsed' }
    foreach ($grid in @($sync.GridUpdates, $sync.GridHistory, $sync.GridDevices)) {
        if ($grid.ItemsSource) {
            [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid.ItemsSource).Refresh()
        }
    }
})

# recount whenever a row checkbox (or column header) is clicked
$sync.GridUpdates.AddHandler(
    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
    [System.Windows.RoutedEventHandler]{ Update-SelCount })

# details pane follows the selected update row
$sync.GridUpdates.Add_SelectionChanged({
    $it = $sync.GridUpdates.SelectedItem
    if ($it -and (Get-ActiveView) -eq 'Updates') {
        $sync.DetailTitle.Text = $it.Title
        $meta = @()
        if ($it.Device)       { $meta += $it.Device }
        if ($it.Manufacturer -and $it.Manufacturer -ne $it.Device) { $meta += $it.Manufacturer }
        if ($it.Released)     { $meta += "driver date: $($it.Released)" }
        if ($it.KB)           { $meta += $it.KB }
        if ($it.Size)         { $meta += $it.Size }
        $sync.DetailMeta.Text = ($meta -join '   |   ')
        if ($it.Description) { $sync.DetailDesc.Text = $it.Description }
        else                 { $sync.DetailDesc.Text = 'No description provided by the publisher.' }
        $sync.DetailActions.Visibility = 'Collapsed'
        $sync.DetailsCard.Visibility = 'Visible'
    } elseif ((Get-ActiveView) -eq 'Updates') {
        $sync.DetailsCard.Visibility = 'Collapsed'
    }
})

# details pane follows the selected device row
$sync.GridDevices.Add_SelectionChanged({
    $it = $sync.GridDevices.SelectedItem
    if ($it -and (Get-ActiveView) -eq 'Devices') {
        $sync.DetailTitle.Text = $it.Name
        $meta = @()
        if ($it.Class)      { $meta += $it.Class }
        if ($it.Version)    { $meta += "version $($it.Version)" }
        if ($it.DriverDate) { $meta += "driver date: $($it.DriverDate)" }
        if ($it.Provider)   { $meta += $it.Provider }
        if ($it.Inf)        { $meta += $it.Inf }
        $meta += $it.Status
        $sync.DetailMeta.Text = ($meta -join '   |   ')
        if ($it.HardwareID) {
            $sync.DetailDesc.Text = "Hardware ID: $($it.HardwareID)"
            $sync.CurrentHwid = $it.HardwareID
            $sync.DetailActions.Visibility = 'Visible'
        } else {
            $sync.DetailDesc.Text = 'No hardware ID reported for this device.'
            $sync.CurrentHwid = ''
            $sync.DetailActions.Visibility = 'Collapsed'
        }
        $sync.DetailsCard.Visibility = 'Visible'
    } elseif ((Get-ActiveView) -eq 'Devices') {
        $sync.DetailsCard.Visibility = 'Collapsed'
    }
})

# double-click a row to toggle it
$sync.GridUpdates.Add_MouseDoubleClick({
    if ($sync.Busy) { return }
    $item = $sync.GridUpdates.SelectedItem
    if ($item) {
        $item.IsSelected = -not $item.IsSelected
        $sync.GridUpdates.Items.Refresh()
        Update-SelCount
    }
})

# Space toggles all highlighted rows
$sync.GridUpdates.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq 'Space' -and -not $sync.Busy -and $sync.GridUpdates.SelectedItems.Count -gt 0) {
        foreach ($item in $sync.GridUpdates.SelectedItems) { $item.IsSelected = -not $item.IsSelected }
        $sync.GridUpdates.Items.Refresh()
        Update-SelCount
        $e.Handled = $true
    }
})

$sync.BtnClearLog.Add_Click({ $sync.LogBox.Clear() })

$sync.BtnInstall.Add_Click({
    if ($sync.Busy) { return }
    if (-not $sync.Items -or $sync.Items.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show('Run a scan first.', $AppName, 'OK', 'Information')
        return
    }
    [void]$sync.GridUpdates.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)

    $selected = @($sync.Items | Where-Object { $_.IsSelected -and $_.UpdateID })
    if ($selected.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show('Nothing is ticked - select at least one update.', $AppName, 'OK', 'Information')
        return
    }

    $preview = ($selected | Select-Object -First 10 | ForEach-Object { ' - ' + $_.Title }) -join "`n"
    $msg = "Install these $($selected.Count) update(s)?`n`n$preview"
    if ($selected.Count -gt 10) { $msg += "`n   ...and $($selected.Count - 10) more" }
    if ($sync.ChkRestore.IsChecked) { $msg += "`n`nA system restore point will be created first." }

    $answer = [System.Windows.MessageBox]::Show($msg, 'Confirm install', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }

    Set-Busy $true 'Installing... this can take a while, the log below shows progress.'
    $null = Start-Worker -Script $InstallScript -Vars @{
        UpdateIDs        = [string[]]($selected | ForEach-Object { $_.UpdateID })
        MakeRestorePoint = [bool]$sync.ChkRestore.IsChecked
    }
})

$window.Add_Closing({
    param($s, $e)
    if ($sync.Busy) {
        $answer = [System.Windows.MessageBox]::Show(
            'Work is still running. Closing now may leave an install half finished. Close anyway?',
            $AppName, 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $e.Cancel = $true }
    }
})

# --------------------------------------------- timer: worker -> UI bridge
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    # drain log queue into the log box
    $line = $null
    while ($sync.LogQueue.TryDequeue([ref]$line)) {
        $sync.LogBox.AppendText($line + [Environment]::NewLine)
        $sync.LogBox.ScrollToEnd()
    }

    if ($sync.ScanDone) {
        $sync.ScanDone = $false
        $items = [System.Collections.ObjectModel.ObservableCollection[DriverDrop.UpdateItem]]::new()
        foreach ($r in $sync.Results) {
            $item = New-Object DriverDrop.UpdateItem
            $item.IsSelected   = $true
            $item.Title        = $r.Title
            $item.Device       = $r.Device
            $item.Type         = $r.Type
            $item.Released     = $r.Released
            $item.KB           = $r.KB
            $item.Size         = $r.Size
            $item.UpdateID     = $r.UpdateID
            $item.Manufacturer = $r.Manufacturer
            $item.Description  = $r.Description
            $items.Add($item)
        }
        $sync.Items = $items
        $sync.GridUpdates.ItemsSource = $items

        # live filter over the updates list
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($items)
        $view.Filter = [Predicate[object]]{
            param($obj)
            $text = $sync.FilterBox.Text
            if ([string]::IsNullOrWhiteSpace($text)) { return $true }
            $hit = $false
            if ($obj.Title  -and $obj.Title.IndexOf($text,  [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($obj.Device -and $obj.Device.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            return $hit
        }

        if ($items.Count -gt 0) {
            Set-Busy $false "Found $($items.Count) update(s). Untick anything you do not want, then install."
        } else {
            Set-UpdatesEmpty 'You are up to date!' 'No pending updates were found on Microsoft Update.'
            Set-Busy $false 'No updates found - you are up to date!'
        }
        Refresh-EmptyState
    }

    if ($sync.HistoryDone) {
        $sync.HistoryDone = $false
        $sync.HistoryLoaded = $true
        $items = [System.Collections.ObjectModel.ObservableCollection[DriverDrop.HistoryItem]]::new()
        foreach ($r in $sync.HistoryResults) {
            $item = New-Object DriverDrop.HistoryItem
            $item.Day      = $r.Day
            $item.Time     = $r.Time
            $item.Title    = $r.Title
            $item.Category = $r.Category
            $item.Kind     = $r.Kind
            $item.Result   = $r.Result
            $item.KB       = $r.KB
            $items.Add($item)
        }
        $sync.GridHistory.ItemsSource = $items

        # group rows by day + live filter
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($items)
        $view.GroupDescriptions.Clear()
        $view.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription 'Day'))
        $view.Filter = [Predicate[object]]{
            param($obj)
            $text = $sync.FilterBox.Text
            if ([string]::IsNullOrWhiteSpace($text)) { return $true }
            $hit = $false
            if ($obj.Title    -and $obj.Title.IndexOf($text,    [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($obj.KB       -and $obj.KB.IndexOf($text,       [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($obj.Category -and $obj.Category.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            return $hit
        }

        if ($items.Count -gt 0) {
            Set-Busy $false "History loaded - $($items.Count) entries, newest first."
        } else {
            Set-HistoryEmpty 'No history found' 'Windows has no recorded update history on this machine.'
            Set-Busy $false 'No update history found.'
        }
        Refresh-EmptyState
    }

    if ($sync.DevicesDone) {
        $sync.DevicesDone = $false
        $sync.DevicesLoaded = $true
        $items = [System.Collections.ObjectModel.ObservableCollection[DriverDrop.DeviceItem]]::new()
        $problems = 0
        foreach ($r in $sync.DevicesResults) {
            $item = New-Object DriverDrop.DeviceItem
            $item.Name       = $r.Name
            $item.Group      = $r.Group
            $item.Class      = $r.Class
            $item.Version    = $r.Version
            $item.DriverDate = $r.DriverDate
            $item.Status     = $r.Status
            $item.StatusKind = $r.StatusKind
            $item.HardwareID = $r.HardwareID
            $item.Provider   = $r.Provider
            $item.Inf        = $r.Inf
            if ($r.Group -eq 'Needs attention') { $problems++ }
            $items.Add($item)
        }
        $sync.GridDevices.ItemsSource = $items

        # group by class (problems first) + live filter
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($items)
        $view.GroupDescriptions.Clear()
        $view.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription 'Group'))
        $view.Filter = [Predicate[object]]{
            param($obj)
            $text = $sync.FilterBox.Text
            if ([string]::IsNullOrWhiteSpace($text)) { return $true }
            $hit = $false
            if ($obj.Name       -and $obj.Name.IndexOf($text,       [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($obj.Class      -and $obj.Class.IndexOf($text,      [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($obj.Version    -and $obj.Version.IndexOf($text,    [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            if ($obj.HardwareID -and $obj.HardwareID.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true }
            return $hit
        }

        # vendor quick links
        if ($sync.OemUrl) { $sync.BtnOem.Content = $sync.OemLabel }
        if ($sync.GpuUrl) { $sync.BtnGpu.Content = $sync.GpuLabel }
        if ((Get-ActiveView) -eq 'Devices') {
            if ($sync.OemUrl) { $sync.BtnOem.Visibility = 'Visible' }
            if ($sync.GpuUrl) { $sync.BtnGpu.Visibility = 'Visible' }
        }

        if ($items.Count -gt 0) {
            if ($problems -gt 0) { Set-Busy $false "Found $($items.Count) devices - $problems need attention (top of the list)." }
            else                 { Set-Busy $false "Found $($items.Count) devices - all healthy." }
        } else {
            Set-DevicesEmpty 'No devices found' 'The device scan returned nothing - try Rescan devices.'
            Set-Busy $false 'No devices found.'
        }
        Refresh-EmptyState
    }

    if ($sync.InstallDone) {
        $sync.InstallDone = $false
        $sync.GridUpdates.ItemsSource = $null
        $sync.Items = $null
        $sync.HistoryLoaded = $false   # history changed, reload next time it is opened
        Set-UpdatesEmpty 'Install finished' 'Run another scan to verify everything went through.'
        Set-Busy $false 'Install finished - run another scan to verify.'
        Refresh-EmptyState
        if ($sync.RebootRequired) {
            $sync.RebootRequired = $false
            $answer = [System.Windows.MessageBox]::Show(
                'A reboot is required to finish installing. Reboot now?',
                $AppName, 'YesNo', 'Question')
            if ($answer -eq 'Yes') { Restart-Computer -Force }
        } else {
            [void][System.Windows.MessageBox]::Show(
                'Done! The selected updates were processed - check the log for details.',
                $AppName, 'OK', 'Information')
        }
    }
})

# ------------------------------------------------------------------ start
Add-Log "$AppName v$AppVer ready on $env:COMPUTERNAME (PowerShell $($PSVersionTable.PSVersion))"
Add-Log 'Pick a scope, click "Scan for updates", tick what you want, then "Install selected".'
Add-Log 'New: the Devices view finds hardware Windows Update cannot help with - safe links included.'
$sync.StatusText.Text = 'Ready - click "Scan for updates" to begin.'
Update-SelCount
Refresh-EmptyState
$timer.Start()
[void]$window.ShowDialog()
$timer.Stop()

Write-Host ''
Write-Host "  Thanks for using $AppName! You can close this window." -ForegroundColor Green
