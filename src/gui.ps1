if (-not (Get-Command Write-AppLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'utils.ps1')
}
if (-not (Get-Command Invoke-StatusCheck -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'installer.ps1')
}
if (-not (Get-Command Install-hermes-agent-windowsApp -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'app-manager.ps1')
}

function Start-hermes-agent-windowsGui {
    $projectRoot = Get-ProjectRoot
    $global:HermesAgentWindowsRoot = $projectRoot
    $global:HermesAgentWindowsLogPath = Get-LogFilePath -Kind 'app'

    if (-not (Test-Path (Join-Path $projectRoot 'logs'))) {
        New-ProjectFolder -RootPath $projectRoot | Out-Null
    }

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop | Out-Null
    }
    catch {
        Show-ErrorMessage -Message 'WPF is not available on this system. hermes-agent-windows needs Windows desktop PowerShell support.' -Title 'hermes-agent-windows'
        return
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="hermes-agent-windows"
        Height="800"
        Width="1260"
        MinHeight="720"
        MinWidth="1020"
        WindowStartupLocation="CenterScreen"
        Background="#0F1115"
        Foreground="#E2E5EB"
        FontFamily="Segoe UI Variable, Segoe UI, Arial">
    <Window.Resources>
        <!-- Brushes -->
        <SolidColorBrush x:Key="CardBorder" Color="#252A32" />
        <SolidColorBrush x:Key="CardFill" Color="#171A20" />
        <SolidColorBrush x:Key="CardFillAlt" Color="#13151A" />
        <SolidColorBrush x:Key="Accent" Color="#3B82F6" />
        <SolidColorBrush x:Key="AccentHover" Color="#5A9AF8" />
        <SolidColorBrush x:Key="AccentGlow" Color="#1E3A5F" />
        <SolidColorBrush x:Key="Good" Color="#3ECF7A" />
        <SolidColorBrush x:Key="Warn" Color="#F59E0B" />
        <SolidColorBrush x:Key="Bad" Color="#E74C3C" />
        <SolidColorBrush x:Key="Muted" Color="#8B919D" />
        <SolidColorBrush x:Key="MutedBg" Color="#111318" />
        <SolidColorBrush x:Key="TextMain" Color="#E2E5EB" />
        <SolidColorBrush x:Key="TextSecondary" Color="#8B919D" />

        <!-- Default Button -->
        <Style TargetType="Button">
            <Setter Property="Margin" Value="3" />
            <Setter Property="Padding" Value="10,6" />
            <Setter Property="Background" Value="#1B2130" />
            <Setter Property="Foreground" Value="#E2E5EB" />
            <Setter Property="BorderBrush" Value="#2A3242" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="MinHeight" Value="34" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="ToolTipService.ShowDuration" Value="8000" />
        </Style>

        <!-- Primary Button -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Margin" Value="3" />
            <Setter Property="Padding" Value="16,8" />
            <Setter Property="Background" Value="#3B82F6" />
            <Setter Property="Foreground" Value="#FFFFFF" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="FontSize" Value="12.5" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="MinHeight" Value="38" />
            <Setter Property="Cursor" Value="Hand" />
        </Style>

        <!-- Danger Button -->
        <Style x:Key="DangerButton" TargetType="Button">
            <Setter Property="Margin" Value="3" />
            <Setter Property="Padding" Value="10,6" />
            <Setter Property="Background" Value="#3A1515" />
            <Setter Property="Foreground" Value="#E2E5EB" />
            <Setter Property="BorderBrush" Value="#5A2525" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="MinHeight" Value="34" />
            <Setter Property="Cursor" Value="Hand" />
        </Style>

        <!-- Ghost Button -->
        <Style x:Key="GhostButton" TargetType="Button">
            <Setter Property="Margin" Value="2" />
            <Setter Property="Padding" Value="8,4" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="Foreground" Value="#8B919D" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="FontSize" Value="11" />
            <Setter Property="MinHeight" Value="26" />
            <Setter Property="Cursor" Value="Hand" />
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#0E1014" />
            <Setter Property="Foreground" Value="#E2E5EB" />
            <Setter Property="BorderBrush" Value="#252A32" />
            <Setter Property="FontFamily" Value="Consolas" />
            <Setter Property="FontSize" Value="12" />
        </Style>
        <Style TargetType="PasswordBox">
            <Setter Property="Background" Value="#0E1014" />
            <Setter Property="Foreground" Value="#E2E5EB" />
            <Setter Property="BorderBrush" Value="#252A32" />
            <Setter Property="FontFamily" Value="Consolas" />
            <Setter Property="FontSize" Value="12" />
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#0E1014" />
            <Setter Property="Foreground" Value="#111418" />
            <Setter Property="BorderBrush" Value="#252A32" />
            <Setter Property="FontSize" Value="12" />
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="BorderThickness" Value="0" />
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="FontSize" Value="12.5" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Foreground" Value="#8B919D" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="Padding" Value="14,8" />
            <Setter Property="BorderThickness" Value="0" />
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- Header -->
        <DockPanel Grid.Row="0" Margin="0,0,0,14">
            <StackPanel DockPanel.Dock="Left">
                <TextBlock Text="hermes-agent-windows" FontSize="24" FontWeight="Bold" Foreground="#F8FAFC" />
                <TextBlock Text="Smart Windows Setup Tool for Hermes Agent" FontSize="13" Foreground="#8B919D" Margin="0,2,0,0" />
            </StackPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <ProgressBar x:Name="MainProgressBar" Width="180" Height="6" Background="#1C2028" Foreground="#3B82F6"
                             BorderThickness="0" IsIndeterminate="False" Margin="0,0,12,0" Visibility="Collapsed" />
                <TextBlock x:Name="TopStatusText" VerticalAlignment="Center" Foreground="#8B919D" Text="Ready." FontSize="13" />
            </StackPanel>
        </DockPanel>

        <!-- Primary Action + API Row -->
        <Border Grid.Row="1" Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="10" Padding="12" Margin="0,0,0,14">
            <DockPanel>
                <DockPanel DockPanel.Dock="Left">
                    <Button x:Name="StartSetupButton" Content="Start Hermes Agent Setup" Width="220" Height="42"
                            Style="{StaticResource PrimaryButton}"
                            ToolTip="Run the full automated setup: WSL, account, Ollama, Hermes Agent, and Gateway." />
                    <Button x:Name="CheckStatusButton" Content="Check Status" Width="120" Height="36" Margin="8,0,0,0"
                            ToolTip="Refresh all status cards and system component checks." />
                    <Button x:Name="InstallShortcutButton" Content="Install Shortcut" Width="130" Height="36" Margin="8,0,0,0"
                            ToolTip="Add Desktop and Start Menu .bat shortcuts that auto-update from GitHub." />
                    <Button x:Name="UninstallShortcutButton" Content="Uninstall Shortcut" Width="140" Height="36" Margin="8,0,0,0"
                            ToolTip="Remove the .bat shortcuts from Desktop and Start Menu." Visibility="Collapsed" />
                    <Button x:Name="LaunchHermesCliButton" Content="Launch Hermes CLI" Width="140" Height="36" Margin="8,0,0,0"
                            Style="{StaticResource PrimaryButton}"
                            ToolTip="Open a Windows Command Prompt with the Hermes Agent CLI ready inside WSL." />
                </DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock Text="Ollama API Key" VerticalAlignment="Center" Foreground="#8B919D" Margin="0,0,10,0" FontSize="11" />
                    <PasswordBox x:Name="OllamaApiKeyBox" Width="240" Height="32"
                                 ToolTip="Paste your Ollama cloud API key here, then click Save." />
                    <TextBlock Text="Model" VerticalAlignment="Center" Foreground="#8B919D" Margin="12,0,10,0" FontSize="11" />
                    <ComboBox x:Name="OllamaModelBox" Width="210" Height="32" IsEditable="True" Text="kimi-k2.6:cloud"
                              ToolTip="Select or type the Ollama cloud model to use." />
                    <Button x:Name="SaveOllamaCloudButton" Content="Save Key" Width="90" Height="32" Margin="4,0,0,0"
                            ToolTip="Save the API key and model in WSL and Hermes config files." />
                    <Button x:Name="RefreshOllamaModelsButton" Content="Refresh Models" Width="110" Height="32" Margin="4,0,0,0"
                            ToolTip="Fetch the latest Ollama model list from ollama.com." />
                    <Button x:Name="TestOllamaCloudButton" Content="Test API" Width="90" Height="32" Margin="4,0,0,0"
                            ToolTip="Send a test request to verify the API key works." />
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Status Cards + Live Log -->
        <Grid Grid.Row="3" Margin="0,0,0,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2.4*" />
                <ColumnDefinition Width="1*" />
            </Grid.ColumnDefinitions>

            <!-- Status Cards -->
            <Border Grid.Column="0" Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="10" Padding="10" Margin="0,0,8,0">
                <ScrollViewer HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">
                    <UniformGrid Columns="4" Margin="0,0,0,4">
                        <Border x:Name="AppStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="App Shortcut" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="AppStatusValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="AppStatusDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="AdminStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Admin Rights" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="AdminValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="AdminDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="WindowsStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Windows" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="WindowsValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="WindowsDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="PowerShellStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="PowerShell" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="PowerShellValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="PowerShellDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="WslStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="WSL" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="WslStatusValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="WslStatusDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="WslDistroBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="WSL Distro" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="WslDistroValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="WslDistroDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="WslAccountBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="WSL Account" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="WslAccountValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="WslAccountDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="OllamaStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Ollama Status" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="OllamaStatusValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="OllamaStatusDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="OllamaVersionBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Ollama Version" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="OllamaVersionValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="OllamaVersionDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="HermesStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Hermes Status" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="HermesStatusValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="HermesStatusDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="HermesVersionBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Hermes Version" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="HermesVersionValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="HermesVersionDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="GatewayStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Gateway" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="GatewayValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="GatewayDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="UpdatesStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Updates" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="UpdatesValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="UpdatesDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                        <Border x:Name="WslDiskStatusBorder" Background="{StaticResource CardFillAlt}" BorderBrush="#2B3138" BorderThickness="1" CornerRadius="8" Margin="0,0,6,6" Padding="10">
                            <StackPanel>
                                <TextBlock Text="Disk" Foreground="{StaticResource Accent}" FontSize="11" FontWeight="SemiBold" />
                                <TextBlock x:Name="WslDiskValue" Text="Unknown" FontSize="15" FontWeight="Bold" Margin="0,3,0,0" />
                                <TextBlock x:Name="WslDiskDetail" Text="Waiting for check." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="10" MaxHeight="38" TextTrimming="CharacterEllipsis" />
                            </StackPanel>
                        </Border>
                    </UniformGrid>
                </ScrollViewer>
            </Border>

            <!-- Live Log -->
            <Border Grid.Column="1" Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="10" Padding="10">
                <DockPanel>
                    <TextBlock Text="Live Log" DockPanel.Dock="Top" FontSize="12" FontWeight="SemiBold" Foreground="#8B919D" Margin="0,0,0,6" />
                    <TextBox x:Name="LogBox"
                             AcceptsReturn="True"
                             IsReadOnly="True"
                             TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             FontSize="11.5"
                             Background="#111318" />
                </DockPanel>
            </Border>
        </Grid>

        <!-- Bottom Tab Actions -->
        <TabControl Grid.Row="4" Background="Transparent">
            <TabItem Header="Setup" ToolTip="Installation and update actions.">
                <Border Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="0,0,10,10" Padding="10" Margin="0,-1,0,0">
                    <WrapPanel>
                        <Button x:Name="InstallHermesButton" Content="Install Hermes Agent"
                                ToolTip="Download and install Hermes Agent inside WSL using the official Nous Research installer." />
                        <Button x:Name="UpdateHermesButton" Content="Update Hermes Agent"
                                ToolTip="Update the existing Hermes Agent installation inside WSL." />
                        <Button x:Name="HermesDoctorButton" Content="Hermes Doctor"
                                ToolTip="Run Hermes Agent health checks to diagnose common issues." />
                        <Button x:Name="InstallOllamaButton" Content="Install Ollama in WSL"
                                ToolTip="Install the Ollama server inside WSL." />
                        <Button x:Name="StartOllamaButton" Content="Start Ollama"
                                ToolTip="Start the Ollama server inside WSL and verify it responds." />
                    </WrapPanel>
                </Border>
            </TabItem>
            <TabItem Header="Services" ToolTip="Start, stop, and control Hermes services.">
                <Border Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="0,0,10,10" Padding="10" Margin="0,-1,0,0">
                    <WrapPanel>
                        <Button x:Name="StartHermesButton" Content="Start Hermes Agent"
                                ToolTip="Start the Hermes Agent service inside WSL." />
                        <Button x:Name="StopHermesButton" Content="Stop Hermes Agent"
                                ToolTip="Stop the running Hermes Agent service inside WSL." />
                        <Button x:Name="RestartHermesButton" Content="Restart Hermes Agent"
                                ToolTip="Restart the Hermes Agent service to apply config changes." />
                        <Button x:Name="EnableGatewayButton" Content="Enable Gateway"
                                ToolTip="Start the Hermes Gateway inside WSL." />
                        <Button x:Name="OpenGatewayButton" Content="Open Dashboard"
                                ToolTip="Open the Hermes web dashboard in your default browser at localhost:9119." />
                    </WrapPanel>
                </Border>
            </TabItem>
            <TabItem Header="WSL" ToolTip="WSL installation, restart, and reset operations.">
                <Border Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="0,0,10,10" Padding="10" Margin="0,-1,0,0">
                    <WrapPanel>
                        <Button x:Name="InstallWslButton" Content="Install WSL"
                                ToolTip="Install Windows Subsystem for Linux if it is missing on this machine." />
                        <Button x:Name="RestartWslButton" Content="Restart WSL"
                                ToolTip="Restart the default WSL distro to clear memory or fix a stuck state." />
                        <Button x:Name="AdminAccountButton" Content="Create/Reset WSL Admin"
                                ToolTip="Create or reset a helper account named admin with password admin inside WSL." />
                        <Button x:Name="ReinstallWslButton" Content="Reinstall Default Distro"
                                Style="{DynamicResource DangerButton}"
                                ToolTip="Unregister and reinstall the default WSL distro. Requires backup first due to possible data loss." />
                        <Button x:Name="WipeWslButton" Content="Wipe WSL"
                                Style="{DynamicResource DangerButton}"
                                ToolTip="DANGER: Completely unregister and delete the default WSL distro. Data cannot be recovered." />
                        <Button x:Name="CleanHermesButton" Content="Clean Hermes WSL Files"
                                Style="{DynamicResource DangerButton}"
                                ToolTip="Remove only Hermes user files inside WSL. Does not wipe the entire WSL distro." />
                    </WrapPanel>
                </Border>
            </TabItem>
            <TabItem Header="Config" ToolTip="Shortcuts, folders, and system configuration.">
                <Border Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="0,0,10,10" Padding="10" Margin="0,-1,0,0">
                    <WrapPanel>
                        <Button x:Name="OpenConfigButton" Content="Open Config Folder"
                                ToolTip="Open the Hermes configuration folder inside WSL in Windows Explorer." />
                        <Button x:Name="BootLaunchButton" Content="Boot Launch: OFF"
                                ToolTip="Toggle whether hermes-agent-windows starts automatically when Windows boots." />
                        <Button x:Name="OpenLogsButton" Content="Open Logs Folder"
                                ToolTip="Open the local application logs folder in Windows Explorer." />
                        <Button x:Name="GitHubButton" Content="Built by jlaiii"
                                Style="{DynamicResource GhostButton}"
                                ToolTip="Open the project GitHub page in your browser." />
                        <Button x:Name="ExitButton" Content="Exit"
                                Style="{DynamicResource GhostButton}"
                                ToolTip="Close this window. All running WSL services remain active." />
                    </WrapPanel>
                </Border>
            </TabItem>
            <TabItem Header="Bots" ToolTip="Telegram and Discord bot configuration.">
                <Border Background="#171B20" BorderBrush="#252A32" BorderThickness="1" CornerRadius="0,0,10,10" Padding="12" Margin="0,-1,0,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*" />
                            <ColumnDefinition Width="*" />
                        </Grid.ColumnDefinitions>
                        <!-- Telegram -->
                        <StackPanel Grid.Column="0" Margin="0,0,8,0">
                            <TextBlock Text="Telegram Bot" FontSize="13" FontWeight="SemiBold" Foreground="#3B82F6" Margin="0,0,0,8" />
                            <DockPanel Margin="0,0,0,6">
                                <TextBlock Text="Bot Token" Width="70" VerticalAlignment="Center" Foreground="#8B919D" FontSize="11" />
                                <PasswordBox x:Name="TelegramTokenBox" Width="320" Height="30"
                                             ToolTip="Paste your Telegram bot token from @BotFather." />
                            </DockPanel>
                            <DockPanel Margin="0,0,0,8">
                                <TextBlock Text="Chat ID" Width="70" VerticalAlignment="Center" Foreground="#8B919D" FontSize="11" />
                                <TextBox x:Name="TelegramChatIdBox" Width="320" Height="30"
                                         ToolTip="Enter the Telegram chat or user ID." />
                            </DockPanel>
                            <WrapPanel>
                                <Button x:Name="SaveTelegramButton" Content="Save Telegram" Width="120" Height="34" Margin="0,0,6,0"
                                        ToolTip="Save the Telegram bot token and chat ID in WSL." />
                                <Button x:Name="TestTelegramButton" Content="Test Telegram" Width="120" Height="34" Margin="0,0,6,0"
                                        ToolTip="Send a test request to verify the Telegram bot token works." />
                            </WrapPanel>
                        </StackPanel>
                        <!-- Discord -->
                        <StackPanel Grid.Column="1" Margin="8,0,0,0">
                            <TextBlock Text="Discord Bot" FontSize="13" FontWeight="SemiBold" Foreground="#5865F2" Margin="0,0,0,8" />
                            <DockPanel Margin="0,0,0,6">
                                <TextBlock Text="Bot Token" Width="70" VerticalAlignment="Center" Foreground="#8B919D" FontSize="11" />
                                <PasswordBox x:Name="DiscordTokenBox" Width="320" Height="30"
                                             ToolTip="Paste your Discord bot token from the Developer Portal." />
                            </DockPanel>
                            <DockPanel Margin="0,0,0,8">
                                <TextBlock Text="Channel ID" Width="70" VerticalAlignment="Center" Foreground="#8B919D" FontSize="11" />
                                <TextBox x:Name="DiscordChannelIdBox" Width="320" Height="30"
                                         ToolTip="Enter the Discord channel ID where the bot should operate." />
                            </DockPanel>
                            <WrapPanel>
                                <Button x:Name="SaveDiscordButton" Content="Save Discord" Width="120" Height="34" Margin="0,0,6,0"
                                        ToolTip="Save the Discord bot token and channel ID in WSL." />
                                <Button x:Name="TestDiscordButton" Content="Test Discord" Width="120" Height="34" Margin="0,0,6,0"
                                        ToolTip="Send a test request to verify the Discord bot token works." />
                            </WrapPanel>
                            <Button x:Name="InstallBotDepsButton" Content="Install Bot Dependencies" Width="180" Height="34"
                                    Margin="0,12,0,0" HorizontalAlignment="Left"
                                    ToolTip="Install python-telegram-bot and discord.py inside the Hermes WSL venv." />
                        </StackPanel>
                    </Grid>
                </Border>
            </TabItem>
        </TabControl>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{
        StartSetupButton    = $window.FindName('StartSetupButton')
        InstallShortcutButton = $window.FindName('InstallShortcutButton')
        UninstallShortcutButton = $window.FindName('UninstallShortcutButton')
        OllamaApiKeyBox     = $window.FindName('OllamaApiKeyBox')
        OllamaModelBox      = $window.FindName('OllamaModelBox')
        SaveOllamaCloudButton = $window.FindName('SaveOllamaCloudButton')
        RefreshOllamaModelsButton = $window.FindName('RefreshOllamaModelsButton')
        TestOllamaCloudButton = $window.FindName('TestOllamaCloudButton')
        TopStatusText       = $window.FindName('TopStatusText')
        MainProgressBar     = $window.FindName('MainProgressBar')
        AppStatusValue      = $window.FindName('AppStatusValue')
        AppStatusDetail     = $window.FindName('AppStatusDetail')
        AppStatusBorder     = $window.FindName('AppStatusBorder')
        AdminValue          = $window.FindName('AdminValue')
        AdminDetail         = $window.FindName('AdminDetail')
        AdminStatusBorder   = $window.FindName('AdminStatusBorder')
        WindowsValue        = $window.FindName('WindowsValue')
        WindowsDetail       = $window.FindName('WindowsDetail')
        WindowsStatusBorder = $window.FindName('WindowsStatusBorder')
        PowerShellValue     = $window.FindName('PowerShellValue')
        PowerShellDetail    = $window.FindName('PowerShellDetail')
        PowerShellStatusBorder = $window.FindName('PowerShellStatusBorder')
        WslStatusValue      = $window.FindName('WslStatusValue')
        WslStatusDetail     = $window.FindName('WslStatusDetail')
        WslStatusBorder     = $window.FindName('WslStatusBorder')
        WslDistroValue      = $window.FindName('WslDistroValue')
        WslDistroDetail     = $window.FindName('WslDistroDetail')
        WslDistroBorder     = $window.FindName('WslDistroBorder')
        WslAccountValue     = $window.FindName('WslAccountValue')
        WslAccountDetail    = $window.FindName('WslAccountDetail')
        WslAccountBorder    = $window.FindName('WslAccountBorder')
        OllamaStatusValue   = $window.FindName('OllamaStatusValue')
        OllamaStatusDetail  = $window.FindName('OllamaStatusDetail')
        OllamaStatusBorder  = $window.FindName('OllamaStatusBorder')
        OllamaVersionValue  = $window.FindName('OllamaVersionValue')
        OllamaVersionDetail = $window.FindName('OllamaVersionDetail')
        OllamaVersionBorder = $window.FindName('OllamaVersionBorder')
        HermesStatusValue   = $window.FindName('HermesStatusValue')
        HermesStatusDetail  = $window.FindName('HermesStatusDetail')
        HermesStatusBorder  = $window.FindName('HermesStatusBorder')
        HermesVersionValue  = $window.FindName('HermesVersionValue')
        HermesVersionDetail = $window.FindName('HermesVersionDetail')
        HermesVersionBorder = $window.FindName('HermesVersionBorder')
        GatewayValue        = $window.FindName('GatewayValue')
        GatewayDetail       = $window.FindName('GatewayDetail')
        GatewayStatusBorder = $window.FindName('GatewayStatusBorder')
        UpdatesValue        = $window.FindName('UpdatesValue')
        UpdatesDetail       = $window.FindName('UpdatesDetail')
        UpdatesStatusBorder = $window.FindName('UpdatesStatusBorder')
        WslDiskValue        = $window.FindName('WslDiskValue')
        WslDiskDetail       = $window.FindName('WslDiskDetail')
        WslDiskStatusBorder = $window.FindName('WslDiskStatusBorder')
        LogBox              = $window.FindName('LogBox')
        CheckStatusButton   = $window.FindName('CheckStatusButton')
        InstallWslButton    = $window.FindName('InstallWslButton')
        RestartWslButton    = $window.FindName('RestartWslButton')
        AdminAccountButton  = $window.FindName('AdminAccountButton')
        InstallOllamaButton = $window.FindName('InstallOllamaButton')
        StartOllamaButton   = $window.FindName('StartOllamaButton')
        InstallHermesButton = $window.FindName('InstallHermesButton')
        UpdateHermesButton  = $window.FindName('UpdateHermesButton')
        HermesDoctorButton  = $window.FindName('HermesDoctorButton')
        LaunchHermesCliButton = $window.FindName('LaunchHermesCliButton')
        EnableGatewayButton = $window.FindName('EnableGatewayButton')
        OpenGatewayButton   = $window.FindName('OpenGatewayButton')
        StartHermesButton   = $window.FindName('StartHermesButton')
        StopHermesButton    = $window.FindName('StopHermesButton')
        RestartHermesButton = $window.FindName('RestartHermesButton')
        CleanHermesButton   = $window.FindName('CleanHermesButton')
        ReinstallWslButton  = $window.FindName('ReinstallWslButton')
        WipeWslButton       = $window.FindName('WipeWslButton')
        OpenConfigButton    = $window.FindName('OpenConfigButton')
        OpenLogsButton      = $window.FindName('OpenLogsButton')
        BootLaunchButton    = $window.FindName('BootLaunchButton')
        ExitButton          = $window.FindName('ExitButton')
        GitHubButton        = $window.FindName('GitHubButton')
        TelegramTokenBox    = $window.FindName('TelegramTokenBox')
        TelegramChatIdBox   = $window.FindName('TelegramChatIdBox')
        SaveTelegramButton  = $window.FindName('SaveTelegramButton')
        TestTelegramButton  = $window.FindName('TestTelegramButton')
        DiscordTokenBox     = $window.FindName('DiscordTokenBox')
        DiscordChannelIdBox = $window.FindName('DiscordChannelIdBox')
        SaveDiscordButton   = $window.FindName('SaveDiscordButton')
        TestDiscordButton   = $window.FindName('TestDiscordButton')
        InstallBotDepsButton = $window.FindName('InstallBotDepsButton')
    }

    $script:GuiState = @{
        ProjectRoot = $projectRoot
        LastLogLineCount = 0
        Jobs = @{}
        Window = $window
        Controls = $controls
    }

    function Add-GuiLogLine {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) {
            return
        }

        $line = ConvertTo-GuiSafeText $Text
        if (-not $line) {
            return
        }

        $controls.LogBox.AppendText($line + [Environment]::NewLine)
        $controls.LogBox.ScrollToEnd()
    }

    function Set-StatusVisual {
        param(
            [System.Windows.Controls.TextBlock]$ValueControl,
            [System.Windows.Controls.TextBlock]$DetailControl,
            [System.Windows.Controls.Border]$BorderControl = $null,
            [string]$Status,
            [string]$Message,
            [string]$Details
        )

        $ValueControl.Text = if ($Status) { $Status } else { 'Unknown' }
        $DetailControl.Text = if ($Details) { "$Message`n$Details" } else { $Message }

        $statusColor = switch ($Status) {
            'Installed' { [System.Windows.Media.Brushes]::LightGreen }
            'Running' { [System.Windows.Media.Brushes]::LightGreen }
            'Stopped' { [System.Windows.Media.Brushes]::Khaki }
            'Missing' { [System.Windows.Media.Brushes]::OrangeRed }
            'Needs Update' { [System.Windows.Media.Brushes]::Gold }
            'NeedsReboot' { [System.Windows.Media.Brushes]::LightSalmon }
            'Error' { [System.Windows.Media.Brushes]::Tomato }
            default { [System.Windows.Media.Brushes]::LightGray }
        }
        $ValueControl.Foreground = $statusColor

        if ($BorderControl) {
            $borderBrush = switch ($Status) {
                'Installed' { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 35, 100, 60)) }
                'Running'   { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 35, 100, 60)) }
                'Stopped'   { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 100, 90, 40)) }
                'Missing'   { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 120, 50, 40)) }
                'Needs Update' { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 120, 100, 40)) }
                'NeedsReboot' { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 140, 100, 70)) }
                'Error'     { [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 140, 50, 40)) }
                default     { $BorderControl.BorderBrush }
            }
            $BorderControl.BorderBrush = $borderBrush
        }
    }

    function Update-FromSummary {
        param([pscustomobject]$Summary)
        if (-not $Summary) { return }

        Set-StatusVisual $controls.AppStatusValue $controls.AppStatusDetail $controls.AppStatusBorder $Summary.AppStatus.Status $Summary.AppStatus.Message $Summary.AppStatus.Details

        # Smart visibility: shortcut buttons
        if ($Summary.AppStatus -and $Summary.AppStatus.Status -eq 'Installed') {
            $controls.InstallShortcutButton.Visibility  = 'Collapsed'
            $controls.UninstallShortcutButton.Visibility = 'Visible'
        }
        else {
            $controls.InstallShortcutButton.Visibility  = 'Visible'
            $controls.UninstallShortcutButton.Visibility = 'Collapsed'
        }

        # Smart visibility: setup button only before Hermes is installed
        # Get-HermesStatus returns Running, Stopped, or Missing (never Installed)
        if ($Summary.HermesStatus -and ($Summary.HermesStatus.Status -eq 'Running' -or $Summary.HermesStatus.Status -eq 'Stopped')) {
            $controls.StartSetupButton.Visibility = 'Collapsed'
        }
        else {
            $controls.StartSetupButton.Visibility = 'Visible'
        }
        Set-StatusVisual $controls.AdminValue $controls.AdminDetail $controls.AdminStatusBorder $Summary.AdminCheck.Status $Summary.AdminCheck.Message $Summary.AdminCheck.Details
        Set-StatusVisual $controls.WindowsValue $controls.WindowsDetail $controls.WindowsStatusBorder $Summary.WindowsVersion.Status $Summary.WindowsVersion.Message ($Summary.WindowsVersion.Message)
        Set-StatusVisual $controls.PowerShellValue $controls.PowerShellDetail $controls.PowerShellStatusBorder $Summary.PowerShellVersion.Status $Summary.PowerShellVersion.Message ($Summary.PowerShellVersion.Message)
        Set-StatusVisual $controls.WslStatusValue $controls.WslStatusDetail $controls.WslStatusBorder $Summary.WslStatus.Status $Summary.WslStatus.Message $Summary.WslStatus.Details
        Set-StatusVisual $controls.WslDistroValue $controls.WslDistroDetail $controls.WslDistroBorder $Summary.WslDistro.Status $Summary.WslDistro.Message $Summary.WslDistro.Details
        Set-StatusVisual $controls.WslAccountValue $controls.WslAccountDetail $controls.WslAccountBorder $Summary.WslAccount.Status $Summary.WslAccount.Message $Summary.WslAccount.Details
        Set-StatusVisual $controls.OllamaStatusValue $controls.OllamaStatusDetail $controls.OllamaStatusBorder $Summary.OllamaStatus.Status $Summary.OllamaStatus.Message $Summary.OllamaStatus.Details
        Set-StatusVisual $controls.OllamaVersionValue $controls.OllamaVersionDetail $controls.OllamaVersionBorder $Summary.OllamaVersion.Status $Summary.OllamaVersion.Message $Summary.OllamaVersion.Details
        Set-StatusVisual $controls.HermesStatusValue $controls.HermesStatusDetail $controls.HermesStatusBorder $Summary.HermesStatus.Status $Summary.HermesStatus.Message $Summary.HermesStatus.Details
        Set-StatusVisual $controls.HermesVersionValue $controls.HermesVersionDetail $controls.HermesVersionBorder $Summary.HermesVersion.Status $Summary.HermesVersion.Message $Summary.HermesVersion.Details
        Set-StatusVisual $controls.GatewayValue $controls.GatewayDetail $controls.GatewayStatusBorder $Summary.GatewayStatus.Status $Summary.GatewayStatus.Message $Summary.GatewayStatus.Details
        Set-StatusVisual $controls.UpdatesValue $controls.UpdatesDetail $controls.UpdatesStatusBorder $Summary.Updates.Status $Summary.Updates.Message $Summary.Updates.Details
        Set-StatusVisual $controls.WslDiskValue $controls.WslDiskDetail $controls.WslDiskStatusBorder $Summary.WslDisk.Status $Summary.WslDisk.Message $Summary.WslDisk.Details

        # Update-available indicator: gold text in top status bar when an update is detected
        if ($Summary.Updates.Status -eq 'Needs Update') {
            $controls.TopStatusText.Foreground = [System.Windows.Media.Brushes]::Gold
            $controls.TopStatusText.Text = "UPDATE AVAILABLE - $($Summary.Updates.Message)"
        }
        else {
            $controls.TopStatusText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(255, 139, 145, 157))
            $controls.TopStatusText.Text = $Summary.Summary
        }

        # Sync boot-launch button label from status check
        if ($Summary.BootLaunch.Status -eq 'Running') {
            $controls.BootLaunchButton.Content = 'Boot Launch: ON'
        }
        elseif ($Summary.BootLaunch.Status -eq 'Stopped' -or $Summary.BootLaunch.Status -eq 'Missing') {
            $controls.BootLaunchButton.Content = 'Boot Launch: OFF'
        }
        else {
            $controls.BootLaunchButton.Content = 'Boot Launch: ?'
        }
    }

    function Refresh-AppLogTail {
        $logFile = Get-LogFilePath -Kind 'app'
        if (-not (Test-Path $logFile)) {
            return
        }

        try {
            $lines = @(Get-Content -Path $logFile -ErrorAction SilentlyContinue)
            if ($null -eq $lines) { return }
            if ($lines.Count -gt $script:GuiState.LastLogLineCount) {
                $newLines = $lines[$script:GuiState.LastLogLineCount..($lines.Count - 1)]
                foreach ($line in $newLines) {
                    Add-GuiLogLine $line
                }
                $script:GuiState.LastLogLineCount = $lines.Count
            }
        }
        catch {
        }
    }

    function Start-GuiJob {
        param(
            [string]$TaskName,
            [string]$FunctionName,
            [object[]]$FunctionArguments = @()
        )

        if ($script:GuiState.Jobs.ContainsKey($TaskName)) {
            Add-GuiLogLine "[$TaskName] Task already running."
            return
        }

        Write-AppLog -Message "Starting task: $TaskName" -Level 'INFO' | Out-Null
        $controls.TopStatusText.Text = "$TaskName in progress..."
        $controls.MainProgressBar.Visibility = 'Visible'
        $controls.MainProgressBar.IsIndeterminate = $true

        $job = Start-Job -Name $TaskName -ArgumentList $script:GuiState.ProjectRoot, $FunctionName, $FunctionArguments -ScriptBlock {
            param($root, $funcName, $funcArgs)
            $global:HermesAgentWindowsRoot = $root
            $global:HermesAgentWindowsLogPath = Join-Path $root 'logs\app.log'
            . (Join-Path $root 'src\utils.ps1')
            . (Join-Path $root 'src\checks.ps1')
            . (Join-Path $root 'src\wsl-manager.ps1')
            . (Join-Path $root 'src\ollama-manager.ps1')
            . (Join-Path $root 'src\hermes-manager.ps1')
            . (Join-Path $root 'src\app-manager.ps1')
            . (Join-Path $root 'src\bot-manager.ps1')
            . (Join-Path $root 'src\installer.ps1')
            & $funcName @funcArgs
        }

        $script:GuiState.Jobs[$TaskName] = $job
    }

    function Start-StatusCheckJob {
        Start-GuiJob -TaskName 'CheckStatus' -FunctionName 'Invoke-StatusCheck'
    }

    function Start-InstallAppJob {
        Start-GuiJob -TaskName 'InstallApp' -FunctionName 'Install-hermes-agent-windowsApp'
    }

    function Start-UninstallAppJob {
        Start-GuiJob -TaskName 'UninstallApp' -FunctionName 'Uninstall-hermes-agent-windowsApp'
    }

    function Start-InstallWslJob {
        Start-GuiJob -TaskName 'InstallWsl' -FunctionName 'Install-Wsl'
    }

    function Start-RestartWslJob {
        Start-GuiJob -TaskName 'RestartWsl' -FunctionName 'Restart-Wsl'
    }

    function Start-AdminAccountJob {
        Start-GuiJob -TaskName 'AdminAccount' -FunctionName 'Ensure-WslAdminAccount'
    }

    function Start-InstallOllamaJob {
        Start-GuiJob -TaskName 'InstallOllama' -FunctionName 'Install-Ollama'
    }

    function Start-OllamaJob {
        Start-GuiJob -TaskName 'StartOllama' -FunctionName 'Start-Ollama'
    }

    function Start-SaveOllamaCloudJob {
        $apiKey = $controls.OllamaApiKeyBox.Password
        $model = $controls.OllamaModelBox.Text
        Start-GuiJob -TaskName 'SaveOllamaCloud' -FunctionName 'Set-OllamaCloudConfig' -FunctionArguments @($apiKey, $model)
    }

    function Start-RefreshOllamaModelsJob {
        Start-GuiJob -TaskName 'RefreshOllamaModels' -FunctionName 'Get-OllamaCloudModels'
    }

    function Start-TestOllamaCloudJob {
        $model = $controls.OllamaModelBox.Text
        Start-GuiJob -TaskName 'TestOllamaCloud' -FunctionName 'Test-OllamaCloudApi' -FunctionArguments @($model)
    }

    function Start-SaveTelegramJob {
        $token = $controls.TelegramTokenBox.Password
        $chatId = $controls.TelegramChatIdBox.Text
        Start-GuiJob -TaskName 'SaveTelegram' -FunctionName 'Set-TelegramBotConfig' -FunctionArguments @($token, $chatId)
    }

    function Start-TestTelegramJob {
        $token = $controls.TelegramTokenBox.Password
        Start-GuiJob -TaskName 'TestTelegram' -FunctionName 'Test-TelegramBotApi' -FunctionArguments @($token)
    }

    function Start-SaveDiscordJob {
        $token = $controls.DiscordTokenBox.Password
        $channelId = $controls.DiscordChannelIdBox.Text
        Start-GuiJob -TaskName 'SaveDiscord' -FunctionName 'Set-DiscordBotConfig' -FunctionArguments @($token, $channelId)
    }

    function Start-TestDiscordJob {
        $token = $controls.DiscordTokenBox.Password
        Start-GuiJob -TaskName 'TestDiscord' -FunctionName 'Test-DiscordBotApi' -FunctionArguments @($token)
    }

    function Start-InstallBotDepsJob {
        Start-GuiJob -TaskName 'InstallBotDeps' -FunctionName 'Install-BotDependencies'
    }

    function Start-InstallHermesJob {
        Start-GuiJob -TaskName 'InstallHermes' -FunctionName 'Install-HermesAgent'
    }

    function Start-UpdateHermesJob {
        Start-GuiJob -TaskName 'UpdateHermes' -FunctionName 'Update-HermesAgent'
    }

    function Start-HermesDoctorJob {
        Start-GuiJob -TaskName 'HermesDoctor' -FunctionName 'Invoke-HermesDoctor'
    }

    function Start-ToggleBootLaunchJob {
        # Determine current state from the button label and toggle
        $currentLabel = $controls.BootLaunchButton.Content
        $enable = if ($currentLabel -match 'OFF') { $true } else { $false }
        Start-GuiJob -TaskName 'ToggleBootLaunch' -FunctionName 'Set-WindowsBootLaunch' -FunctionArguments @($enable)
    }

    function Start-EnableGatewayJob {
        Start-GuiJob -TaskName 'EnableGateway' -FunctionName 'Enable-HermesGateway'
    }

    function Start-CleanHermesJob {
        Start-GuiJob -TaskName 'CleanHermes' -FunctionName 'Clear-HermesWslFiles'
    }

    function Start-ReinstallWslJob {
        Start-GuiJob -TaskName 'ReinstallWsl' -FunctionName 'Reinstall-DefaultWslDistro'
    }

    function Start-WipeWslJob {
        Start-GuiJob -TaskName 'WipeWsl' -FunctionName 'Unregister-DefaultWslDistro'
    }

    function Start-FullSetupJob {
        Start-GuiJob -TaskName 'FullSetup' -FunctionName 'Start-FullSetup'
    }

    function Start-HermesControlJob {
        param(
            [string]$TaskName,
            [string]$FunctionName
        )
        Start-GuiJob -TaskName $TaskName -FunctionName $FunctionName
    }

    function Start-GuidedSetup {
        Add-GuiLogLine 'Starting full automated setup.'
        Start-FullSetupJob
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(700)
    $timer.Add_Tick({
        Refresh-AppLogTail

        $hasActiveJob = $false
        foreach ($entry in @($script:GuiState.Jobs.GetEnumerator())) {
            $taskName = $entry.Key
            $job = $entry.Value
            if ($job.State -in 'Completed', 'Failed', 'Stopped') {
                try {
                    $output = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
                    $outputItems = @($output)
                    if ($outputItems.Count -gt 0) {
                        foreach ($item in $outputItems) {
                            if ($item -is [string]) {
                                Add-GuiLogLine $item
                            }
                        }
                    }

                    if ($outputItems.Count -gt 0 -and $outputItems[0] -is [pscustomobject]) {
                        $result = $outputItems | Select-Object -First 1
                        if ($taskName -eq 'CheckStatus') {
                            Update-FromSummary $result
                        }
                        elseif ($taskName -eq 'RefreshOllamaModels') {
                            $controls.TopStatusText.Text = "$taskName finished with $($result.Status)."
                            Add-GuiLogLine "[$taskName] $($result.Message)"
                            if ($result.Models) {
                                $controls.OllamaModelBox.Items.Clear()
                                foreach ($modelName in @($result.Models)) {
                                    [void]$controls.OllamaModelBox.Items.Add($modelName)
                                }
                                if (-not $controls.OllamaModelBox.Text) {
                                    $controls.OllamaModelBox.Text = 'kimi-k2.6:cloud'
                                }
                            }
                        }
                        elseif ($taskName -eq 'SaveOllamaCloud' -or $taskName -eq 'TestOllamaCloud' -or $taskName -eq 'InstallApp' -or $taskName -eq 'UninstallApp' -or $taskName -eq 'InstallWsl' -or $taskName -eq 'RestartWsl' -or $taskName -eq 'AdminAccount' -or $taskName -eq 'InstallOllama' -or $taskName -eq 'StartOllama' -or $taskName -eq 'InstallHermes' -or $taskName -eq 'UpdateHermes' -or $taskName -eq 'HermesDoctor' -or $taskName -eq 'EnableGateway' -or $taskName -eq 'CleanHermes' -or $taskName -eq 'ReinstallWsl' -or $taskName -eq 'WipeWsl' -or $taskName -eq 'FullSetup') {
                            $controls.TopStatusText.Text = "$taskName finished with $($result.Status)."
                            Add-GuiLogLine "[$taskName] $($result.Message)"
                            Start-StatusCheckJob
                        }
                        elseif ($taskName -eq 'SaveTelegram' -or $taskName -eq 'TestTelegram' -or $taskName -eq 'SaveDiscord' -or $taskName -eq 'TestDiscord' -or $taskName -eq 'InstallBotDeps') {
                            $controls.TopStatusText.Text = "$taskName finished with $($result.Status)."
                            Add-GuiLogLine "[$taskName] $($result.Message)"
                        }
                        elseif ($taskName -eq 'ToggleBootLaunch') {
                            $controls.TopStatusText.Text = "$taskName finished with $($result.Status)."
                            Add-GuiLogLine "[$taskName] $($result.Message)"
                            # Update button label to reflect new state
                            if ($result.Status -eq 'Enabled') {
                                $controls.BootLaunchButton.Content = 'Boot Launch: ON'
                            }
                            elseif ($result.Status -eq 'Disabled') {
                                $controls.BootLaunchButton.Content = 'Boot Launch: OFF'
                            }
                            else {
                                $controls.BootLaunchButton.Content = 'Boot Launch: ERROR'
                            }
                            Start-StatusCheckJob
                        }
                        elseif ($taskName -eq 'StartHermes' -or $taskName -eq 'StopHermes' -or $taskName -eq 'RestartHermes') {
                            $controls.TopStatusText.Text = "$taskName finished with $($result.Status)."
                            Start-StatusCheckJob
                        }
                    }
                    elseif ($taskName -eq 'CheckStatus' -and $outputItems.Count -gt 0) {
                        Update-FromSummary $outputItems[0]
                    }
                }
                finally {
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    $script:GuiState.Jobs.Remove($taskName) | Out-Null
                }
            }
            else {
                $hasActiveJob = $true
            }
        }

        if (-not $hasActiveJob) {
            $controls.MainProgressBar.Visibility = 'Collapsed'
            $controls.MainProgressBar.IsIndeterminate = $false
        }
    })
    $timer.Start()

    $controls.StartSetupButton.Add_Click({
        Start-GuidedSetup
    })
    $controls.InstallShortcutButton.Add_Click({
        Start-InstallAppJob
    })
    $controls.UninstallShortcutButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('Remove the hermes-agent-windows Desktop and Start Menu shortcuts? This will not delete the project folder or WSL data.', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-UninstallAppJob }
    })
    $controls.CheckStatusButton.Add_Click({
        Start-StatusCheckJob
    })
    $controls.InstallWslButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('Install WSL now? A reboot may be required.', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-InstallWslJob }
    })
    $controls.RestartWslButton.Add_Click({
        Start-RestartWslJob
    })
    $controls.AdminAccountButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('Create or reset the WSL admin account to username admin and password admin? This is convenient for setup but should be changed later on shared machines.', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-AdminAccountJob }
    })
    $controls.InstallOllamaButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('Install Ollama inside WSL now?', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-InstallOllamaJob }
    })
    $controls.StartOllamaButton.Add_Click({
        Start-OllamaJob
    })
    $controls.SaveOllamaCloudButton.Add_Click({
        Start-SaveOllamaCloudJob
    })
    $controls.RefreshOllamaModelsButton.Add_Click({
        Start-RefreshOllamaModelsJob
    })
    $controls.TestOllamaCloudButton.Add_Click({
        Start-TestOllamaCloudJob
    })
    $controls.SaveTelegramButton.Add_Click({
        Start-SaveTelegramJob
    })
    $controls.TestTelegramButton.Add_Click({
        Start-TestTelegramJob
    })
    $controls.SaveDiscordButton.Add_Click({
        Start-SaveDiscordJob
    })
    $controls.TestDiscordButton.Add_Click({
        Start-TestDiscordJob
    })
    $controls.InstallBotDepsButton.Add_Click({
        Start-InstallBotDepsJob
    })
    $controls.InstallHermesButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('Install Hermes Agent inside WSL now?', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-InstallHermesJob }
    })
    $controls.UpdateHermesButton.Add_Click({
        Start-UpdateHermesJob
    })
    $controls.HermesDoctorButton.Add_Click({
        Start-HermesDoctorJob
    })
    $controls.LaunchHermesCliButton.Add_Click({
        $result = Open-HermesCli
        Add-GuiLogLine "Launch Hermes CLI: $($result.Message)"
    })
    $controls.EnableGatewayButton.Add_Click({
        Start-EnableGatewayJob
    })
    $controls.OpenGatewayButton.Add_Click({
        $result = Open-HermesGateway
        Add-GuiLogLine "Open Dashboard: $($result.Message)"
    })
    $controls.StartHermesButton.Add_Click({
        Start-HermesControlJob -TaskName 'StartHermes' -FunctionName 'Start-HermesAgent'
    })
    $controls.StopHermesButton.Add_Click({
        Start-HermesControlJob -TaskName 'StopHermes' -FunctionName 'Stop-HermesAgent'
    })
    $controls.RestartHermesButton.Add_Click({
        Start-HermesControlJob -TaskName 'RestartHermes' -FunctionName 'Restart-HermesAgent'
    })
    $controls.CleanHermesButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('Remove Hermes user files inside WSL? This does not wipe the whole WSL distro.', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-CleanHermesJob }
    })
    $controls.ReinstallWslButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('This will unregister the default WSL distro and reinstall WSL. It can delete Linux files in that distro. Continue only if you have backups.', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Error)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-ReinstallWslJob }
    })
    $controls.WipeWslButton.Add_Click({
        $choice = [System.Windows.MessageBox]::Show('DANGER: This unregisters the default WSL distro and deletes its Linux filesystem. This cannot be undone. Continue?', 'hermes-agent-windows', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Error)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { Start-WipeWslJob }
    })
    $controls.OpenConfigButton.Add_Click({
        $result = Open-HermesConfigFolder
        Add-GuiLogLine "Open Config Folder: $($result.Message)"
    })
    $controls.OpenLogsButton.Add_Click({
        $result = Open-FolderSafe -Path (Join-Path $script:GuiState.ProjectRoot 'logs')
        Add-GuiLogLine "Open Logs Folder: $($result.Message)"
    })
    $controls.BootLaunchButton.Add_Click({
        Start-ToggleBootLaunchJob
    })
    $controls.ExitButton.Add_Click({
        $window.Close()
    })

    $controls.GitHubButton.Add_Click({
        try {
            Start-Process 'https://github.com/jlaiii/hermes-agent-windows' | Out-Null
        }
        catch {
            Add-GuiLogLine "Could not open browser: $($_.Exception.Message)"
        }
    })

    Add-GuiLogLine 'hermes-agent-windows GUI started.'

    # Always pre-fill model dropdown: cache first, then hardcoded fallback.
    # The 'Refresh Models' button still works for an on-demand re-fetch.
    $cached = Import-OllamaCloudModels
    if ($cached.Status -eq 'Installed' -and $cached.Models) {
        $controls.OllamaModelBox.Items.Clear()
        foreach ($modelName in $cached.Models) {
            [void]$controls.OllamaModelBox.Items.Add($modelName)
        }
        if ([string]::IsNullOrWhiteSpace($controls.OllamaModelBox.Text)) {
            $controls.OllamaModelBox.Text = 'kimi-k2.6:cloud'
        }
        Add-GuiLogLine "Loaded $($cached.Models.Count) cached models (fetched $($cached.Details))."
    }
    else {
        $defaultModels = @('kimi-k2.6:cloud', 'qwen3:cloud', 'qwq:cloud', 'gemma3:cloud', 'mistral-small:cloud', 'llama3.3:cloud', 'qwen2.5:cloud', 'deepseek-r1:cloud', 'phi4:cloud', 'granite3.2:cloud')
        $controls.OllamaModelBox.Items.Clear()
        foreach ($modelName in $defaultModels) {
            [void]$controls.OllamaModelBox.Items.Add($modelName)
        }
        if ([string]::IsNullOrWhiteSpace($controls.OllamaModelBox.Text)) {
            $controls.OllamaModelBox.Text = 'kimi-k2.6:cloud'
        }
        Add-GuiLogLine "Loaded $($defaultModels.Count) default models."
    }

    # Auto-refresh model list in background so user never has to press Refresh manually
    Add-GuiLogLine 'Checking for newer model list from ollama.com (background)...'
    Start-RefreshOllamaModelsJob

    Start-StatusCheckJob

    # Make the Updates card clickable when an update is detected
    $controls.UpdatesStatusBorder.Cursor = 'Hand'
    $controls.UpdatesStatusBorder.Add_MouseLeftButtonDown({
        Start-UpdateHermesJob
    })
    $controls.UpdatesStatusBorder.ToolTip = 'Click to update Hermes Agent.'

    $window.Add_Closed({
        $timer.Stop()
        foreach ($entry in @($script:GuiState.Jobs.GetEnumerator())) {
            try {
                Stop-Job -Job $entry.Value -ErrorAction SilentlyContinue | Out-Null
                Remove-Job -Job $entry.Value -Force -ErrorAction SilentlyContinue
            }
            catch {
            }
        }
    })

    $window.ShowDialog() | Out-Null
}