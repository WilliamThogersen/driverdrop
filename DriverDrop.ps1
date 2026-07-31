<#  =====================================================================
    DriverDrop  -  free, open-source Windows driver & update picker
    ---------------------------------------------------------------------
    * Scans Microsoft Update for driver updates (or all updates)
    * Lets you tick exactly what you want installed - nothing more
    * Optional system restore point before installing
    * No ads, no paywall, no telemetry, one readable .ps1 file

    Run straight from GitHub (any PowerShell window, it self-elevates):

        irm "https://raw.githubusercontent.com/YOURUSER/YOURREPO/main/DriverDrop.ps1" | iex

    Or run the file locally:

        powershell -ExecutionPolicy Bypass -File .\DriverDrop.ps1
    ===================================================================== #>

# ---------------------------------------------------------------- config
# EDIT THIS after you publish the repo - it is used to self-elevate
# when the script is run from memory via  irm | iex
$ScriptUrl = 'https://raw.githubusercontent.com/YOURUSER/YOURREPO/main/DriverDrop.ps1'
$AppName   = 'DriverDrop'
$AppVer    = '1.0.0'

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

# ------------------------------------------------------------- row class
# A tiny .NET class so WPF checkbox binding is 100% reliable
if (-not ([System.Management.Automation.PSTypeName]'DriverDrop.UpdateItem').Type) {
    Add-Type -TypeDefinition @"
namespace DriverDrop {
    public class UpdateItem {
        public bool   IsSelected { get; set; }
        public string Title      { get; set; }
        public string Type       { get; set; }
        public string KB         { get; set; }
        public string Size       { get; set; }
        public string UpdateID   { get; set; }
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
$sync.Busy            = $false
$sync.RebootRequired  = $false

# ------------------------------------------------------------------ XAML
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DriverDrop - Windows driver and update picker"
        Width="1000" Height="680" MinWidth="840" MinHeight="560"
        WindowStartupLocation="CenterScreen"
        Background="#FF17171B" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <SolidColorBrush x:Key="PanelBrush"  Color="#FF212127"/>
    <SolidColorBrush x:Key="TextBrush"   Color="#FFEDEDEF"/>
    <SolidColorBrush x:Key="MutedBrush"  Color="#FF9A9AA5"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#FF3D7EFF"/>

    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="Background" Value="#FF3D7EFF"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
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

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#FF2A2A31"/>
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="BorderBrush" Value="#FF3A3A42"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="#FF212127"/>
      <Style.Triggers>
        <Trigger Property="ItemsControl.AlternationIndex" Value="1">
          <Setter Property="Background" Value="#FF1C1C22"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#FF2E4A80"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Foreground" Value="#FFEDEDEF"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="Background" Value="Transparent"/>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="Transparent"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="130"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- header -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
      <TextBlock Text="DriverDrop" FontSize="26" FontWeight="Bold"
                 Foreground="{StaticResource TextBrush}"/>
      <TextBlock Text="  free driver updater - no ads, no paywall, your choice"
                 FontSize="14" Foreground="{StaticResource MutedBrush}"
                 VerticalAlignment="Bottom" Margin="8,0,0,5"/>
    </StackPanel>

    <!-- toolbar -->
    <DockPanel Grid.Row="1" Margin="0,0,0,10" LastChildFill="False">
      <Button Name="BtnScan" Content="Scan for updates" DockPanel.Dock="Left" Width="170"/>
      <StackPanel Orientation="Horizontal" Margin="18,0,0,0" DockPanel.Dock="Left">
        <RadioButton Name="RadDrivers" Content="Drivers only" IsChecked="True"
                     GroupName="scope" Margin="0,0,16,0"/>
        <RadioButton Name="RadAll" Content="All updates (Windows + drivers)" GroupName="scope"/>
      </StackPanel>
      <CheckBox Name="ChkSelectAll" Content="Select all" DockPanel.Dock="Right"/>
    </DockPanel>

    <!-- update list -->
    <Border Grid.Row="2" Background="{StaticResource PanelBrush}" CornerRadius="8" Padding="1">
      <DataGrid Name="GridUpdates" AutoGenerateColumns="False" CanUserAddRows="False"
                HeadersVisibility="Column" GridLinesVisibility="None"
                Background="Transparent" BorderThickness="0"
                RowHeaderWidth="0" AlternationCount="2" SelectionMode="Extended">
        <DataGrid.Columns>
          <DataGridTemplateColumn Width="44">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                          HorizontalAlignment="Center"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTextColumn Header="Update" Binding="{Binding Title}" Width="*"   IsReadOnly="True"/>
          <DataGridTextColumn Header="Type"   Binding="{Binding Type}"  Width="90"  IsReadOnly="True"/>
          <DataGridTextColumn Header="KB"     Binding="{Binding KB}"    Width="110" IsReadOnly="True"/>
          <DataGridTextColumn Header="Size"   Binding="{Binding Size}"  Width="90"  IsReadOnly="True"/>
        </DataGrid.Columns>
      </DataGrid>
    </Border>

    <!-- restore point + install -->
    <DockPanel Grid.Row="3" Margin="0,12,0,12" LastChildFill="False">
      <CheckBox Name="ChkRestore" DockPanel.Dock="Left" IsChecked="True"
                Content="Create a system restore point before installing (recommended)"/>
      <Button Name="BtnInstall" Content="Install selected" DockPanel.Dock="Right"
              Width="180" Background="#FF2FA35C"/>
    </DockPanel>

    <!-- log -->
    <Border Grid.Row="4" Background="{StaticResource PanelBrush}" CornerRadius="8">
      <TextBox Name="LogBox" Background="Transparent" Foreground="#FFB9E8C5"
               BorderThickness="0" FontFamily="Consolas" FontSize="12"
               IsReadOnly="True" TextWrapping="Wrap"
               VerticalScrollBarVisibility="Auto" Padding="10"/>
    </Border>

    <!-- status bar -->
    <DockPanel Grid.Row="5" Margin="0,10,0,0">
      <ProgressBar Name="Progress" Width="180" Height="10" DockPanel.Dock="Right"
                   Background="#FF2A2A31" Foreground="{StaticResource AccentBrush}"
                   BorderThickness="0"/>
      <TextBlock Name="StatusText" Text="Ready." Foreground="{StaticResource MutedBrush}"
                 VerticalAlignment="Center"/>
    </DockPanel>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($node in $xaml.SelectNodes('//*[@Name]')) {
    $sync[$node.Name] = $window.FindName($node.Name)
}
$sync.Window = $window

# ----------------------------------------------------------- UI helpers
function Add-Log {
    param([string]$Message)
    $sync.LogQueue.Enqueue("[$((Get-Date).ToString('HH:mm:ss'))] $Message")
}

function Set-Busy {
    param([bool]$On, [string]$Status = '')
    $sync.BtnScan.IsEnabled        = -not $On
    $sync.BtnInstall.IsEnabled     = -not $On
    $sync.RadDrivers.IsEnabled     = -not $On
    $sync.RadAll.IsEnabled         = -not $On
    $sync.Progress.IsIndeterminate = $On
    if ($Status) { $sync.StatusText.Text = $Status }
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
            [pscustomobject]@{
                Title    = [string]$u.Title
                Type     = $type
                KB       = $kb
                Size     = [string]$u.Size
                UpdateID = $id
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

# ------------------------------------------------------------ UI events
$sync.BtnScan.Add_Click({
    if ($sync.Busy) { return }
    $sync.Items = $null
    $sync.GridUpdates.ItemsSource = $null
    Set-Busy $true 'Scanning for updates...'
    Add-Log 'Starting scan...'
    $null = Start-Worker -Script $ScanScript -Vars @{ DriversOnly = [bool]$sync.RadDrivers.IsChecked }
})

$sync.ChkSelectAll.Add_Click({
    if (-not $sync.Items) { return }
    $state = [bool]$sync.ChkSelectAll.IsChecked
    foreach ($item in $sync.Items) { $item.IsSelected = $state }
    $sync.GridUpdates.Items.Refresh()
})

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
            $item.IsSelected = $true
            $item.Title      = $r.Title
            $item.Type       = $r.Type
            $item.KB         = $r.KB
            $item.Size       = $r.Size
            $item.UpdateID   = $r.UpdateID
            $items.Add($item)
        }
        $sync.Items = $items
        $sync.GridUpdates.ItemsSource = $items
        $sync.ChkSelectAll.IsChecked = ($items.Count -gt 0)
        if ($items.Count -gt 0) {
            Set-Busy $false "Found $($items.Count) update(s). Untick anything you do not want, then click Install."
        } else {
            Set-Busy $false 'No updates found - you are up to date!'
        }
    }

    if ($sync.InstallDone) {
        $sync.InstallDone = $false
        Set-Busy $false 'Install finished - run another scan to verify.'
        $sync.GridUpdates.ItemsSource = $null
        $sync.Items = $null
        $sync.ChkSelectAll.IsChecked = $false
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
$sync.StatusText.Text = 'Ready - click "Scan for updates" to begin.'
$timer.Start()
[void]$window.ShowDialog()
$timer.Stop()

Write-Host ''
Write-Host "  Thanks for using $AppName! You can close this window." -ForegroundColor Green
