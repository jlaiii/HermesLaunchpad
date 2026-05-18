if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'utils.ps1')
}
if (-not (Get-Command Test-CommandExists -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'checks.ps1')
}

function Test-WslExists {
    try {
        if (Test-CommandExists -Name 'wsl.exe') {
            return $true
        }

        $systemPath = Join-Path $env:SystemRoot 'System32\wsl.exe'
        return (Test-Path $systemPath)
    }
    catch {
        return $false
    }
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$LogFile = (Get-LogFilePath -Kind 'app'),
        [int]$TimeoutSeconds = 0
    )

    if (-not (Test-WslExists)) {
        return [pscustomobject]@{
            Status   = 'Missing'
            Message  = 'wsl.exe was not found.'
            Details  = 'WSL is not installed or not available on this system.'
            ExitCode = 1
            Output   = @()
        }
    }

    $result = Invoke-CommandSafe -FilePath 'wsl.exe' -Arguments $Arguments -LogFile $LogFile -AllowFailure -TimeoutSeconds $TimeoutSeconds
    return $result
}

function Get-WslStatus {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'WSL Status' -Status 'Missing' -Message 'WSL is not installed.' -Details 'wsl.exe was not found.'
    }

    $result = Invoke-WslCommand -Arguments @('--status') -LogFile $logFile
    if ($result.Status -eq 'Success') {
        $details = if ($result.Details) { $result.Details } else { '' }
        return Format-StatusResult -Name 'WSL Status' -Status 'Installed' -Message 'WSL status retrieved successfully.' -Details $details
    }

    return Format-StatusResult -Name 'WSL Status' -Status 'Error' -Message 'WSL status check failed.' -Details $result.Details -ExitCode $result.ExitCode
}

function Get-WslVersion {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'WSL Version' -Status 'Missing' -Message 'WSL is not installed.' -Details 'wsl.exe was not found.'
    }

    $result = Invoke-WslCommand -Arguments @('--version') -LogFile $logFile
    if ($result.Status -eq 'Success') {
        $details = if ($result.Details) { $result.Details } else { '' }
        return Format-StatusResult -Name 'WSL Version' -Status 'Installed' -Message 'WSL version retrieved successfully.' -Details $details
    }

    return Format-StatusResult -Name 'WSL Version' -Status 'Unknown' -Message 'WSL version information is unavailable.' -Details $result.Details -ExitCode $result.ExitCode
}

function Get-WslDistroList {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'WSL Distro' -Status 'Missing' -Message 'WSL is not installed.' -Details 'wsl.exe was not found.'
    }

    $result = Invoke-WslCommand -Arguments @('-l', '-v') -LogFile $logFile
    if ($result.Status -eq 'Success') {
        $details = if ($result.Details) { $result.Details } else { '' }
        if ($details -match 'no installed distributions|no distributions are installed') {
            return Format-StatusResult -Name 'WSL Distro' -Status 'Missing' -Message 'No WSL distro is installed.' -Details $details
        }

        $diskResult = Invoke-WslCommand -Arguments @('-e', 'sh', '-lc', 'df -h / 2>/dev/null || echo unknown') -LogFile $logFile -TimeoutSeconds 10
        if ($diskResult.Status -eq 'Success' -and $diskResult.Details -and $diskResult.Details -notmatch 'unknown') {
            $diskUsage = ($diskResult.Details -split "`r?`n" | Where-Object { $_ -match '^/dev/' } | Select-Object -First 1).Trim()
            if ($diskUsage) {
                $details = "$details`nDisk usage: $diskUsage"
            }
        }

        return Format-StatusResult -Name 'WSL Distro' -Status 'Installed' -Message 'WSL distro list retrieved.' -Details $details
    }

    if ($result.Details -match 'no installed distributions|no distributions are installed') {
        return Format-StatusResult -Name 'WSL Distro' -Status 'Missing' -Message 'No WSL distro is installed.' -Details $result.Details -ExitCode $result.ExitCode
    }

    return Format-StatusResult -Name 'WSL Distro' -Status 'Unknown' -Message 'WSL distro list is unavailable.' -Details $result.Details -ExitCode $result.ExitCode
}

function Start-WslDefaultDistro {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'WSL Start' -Status 'Missing' -Message 'WSL is not installed.' -Details 'wsl.exe was not found.' -ExitCode 1
    }

    Write-Log -Message 'Starting the default WSL distro with a quick health command.' -Level 'INFO' -LogFile $logFile | Out-Null
    $result = Invoke-WslCommand -Arguments @('-e', 'sh', '-lc', 'uname -a') -LogFile $logFile -TimeoutSeconds 60
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'WSL Start' -Status 'Running' -Message 'Default WSL distro started successfully.' -Details $result.Details
    }

    return Format-StatusResult -Name 'WSL Start' -Status 'Error' -Message 'Default WSL distro did not start cleanly.' -Details $result.Details -ExitCode $result.ExitCode
}

function Test-RebootRequired {
    $pendingKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    foreach ($key in $pendingKeys) {
        if (Test-Path $key) {
            return $true
        }
    }

    try {
        $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
        if ($sessionManager.PendingFileRenameOperations) {
            return $true
        }
    }
    catch {
    }

    return $false
}

function Install-Wsl {
    param(
        [switch]$Force
    )

    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        Write-Log -Message 'WSL is not currently available. Attempting install command anyway in case Windows exposes wsl.exe later.' -Level 'WARN' -LogFile $logFile | Out-Null
    }

    $result = Invoke-WslCommand -Arguments @('--install') -LogFile $logFile
    $rebootRequired = Test-RebootRequired

    if ($result.Status -eq 'Success' -and $rebootRequired) {
        Write-Log -Message 'WSL installation appears to require a reboot.' -Level 'WARN' -LogFile $logFile | Out-Null
        return [pscustomobject]@{
            Status   = 'NeedsReboot'
            Message  = 'WSL installation completed but a reboot is required.'
            Details  = $result.Details
            ExitCode = 0
            Output   = $result.Output
            RebootRequired = $true
        }
    }

    if ($result.Status -eq 'Success') {
        return [pscustomobject]@{
            Status   = 'Installed'
            Message  = 'WSL installation command completed.'
            Details  = $result.Details
            ExitCode = 0
            Output   = $result.Output
            RebootRequired = $rebootRequired
        }
    }

    return [pscustomobject]@{
        Status   = 'Error'
        Message  = 'WSL installation failed.'
        Details  = $result.Details
        ExitCode = $result.ExitCode
        Output   = $result.Output
        RebootRequired = $rebootRequired
    }
}

function Invoke-WslShell {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [int]$TimeoutSeconds = 120,
        [string]$User = ''
    )

    $args = @()
    if ($User) {
        $args += @('-u', $User)
    }
    $args += @('-e', 'bash', '-lc', $Command)
    return Invoke-WslCommand -Arguments $args -LogFile (Get-LogFilePath -Kind 'app') -TimeoutSeconds $TimeoutSeconds
}

function Invoke-WslRootShell {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [int]$TimeoutSeconds = 300
    )

    return Invoke-WslShell -Command $Command -User 'root' -TimeoutSeconds $TimeoutSeconds
}

function Get-WslAccountInfo {
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'WSL Account' -Status 'Missing' -Message 'WSL is not installed.' -Details 'wsl.exe was not found.'
    }

    $command = @'
default_user="$(whoami 2>/dev/null || true)"
admin_line="$(getent passwd admin || true)"
users="$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1 " (uid " $3 ")"}' /etc/passwd | paste -sd ', ' -)"
printf 'Default user: %s\nAdmin user: %s\nLocal users: %s\n' "$default_user" "$(if [ -n "$admin_line" ]; then echo present; else echo missing; fi)" "${users:-none}"
'@
    $result = Invoke-WslShell -Command $command -TimeoutSeconds 60
    if ($result.Status -eq 'Success') {
        $status = if ($result.Details -match 'Admin user:\s+present') { 'Installed' } else { 'Missing' }
        return Format-StatusResult -Name 'WSL Account' -Status $status -Message 'WSL account information retrieved.' -Details $result.Details
    }

    return Format-StatusResult -Name 'WSL Account' -Status 'Unknown' -Message 'Could not read WSL account information.' -Details $result.Details -ExitCode $result.ExitCode
}

function Ensure-WslAdminAccount {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'WSL Admin Account' -Status 'Missing' -Message 'WSL is required before creating the admin account.' -ExitCode 1
    }

    Write-Log -Message 'Ensuring WSL admin/admin helper account exists.' -Level 'WARN' -LogFile $logFile | Out-Null
    $command = @'
set -e
if ! id -u admin >/dev/null 2>&1; then
  useradd -m -s /bin/bash -g sudo -G sudo admin
fi
echo 'admin:admin' | chpasswd
mkdir -p /etc/sudoers.d
printf 'admin ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/hermes-agent-windows-admin
chmod 0440 /etc/sudoers.d/hermes-agent-windows-admin
id admin
'@
    $result = Invoke-WslRootShell -Command $command -TimeoutSeconds 120
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'WSL Admin Account' -Status 'Installed' -Message 'WSL admin/admin helper account is ready.' -Details $result.Details
    }

    return Format-StatusResult -Name 'WSL Admin Account' -Status 'Error' -Message 'Failed to create or reset the WSL admin account.' -Details $result.Details -ExitCode $result.ExitCode
}

function Restart-Wsl {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'Restart WSL' -Status 'Missing' -Message 'WSL is not installed.' -ExitCode 1
    }

    Write-Log -Message 'Restarting WSL with wsl --shutdown, then starting the default distro.' -Level 'INFO' -LogFile $logFile | Out-Null
    $shutdown = Invoke-WslCommand -Arguments @('--shutdown') -LogFile $logFile -TimeoutSeconds 60
    Start-Sleep -Seconds 2
    $start = Start-WslDefaultDistro

    if ($start.Status -eq 'Running') {
        return Format-StatusResult -Name 'Restart WSL' -Status 'Running' -Message 'WSL restarted successfully.' -Details "Shutdown: $($shutdown.Message)`nStart: $($start.Details)"
    }

    return Format-StatusResult -Name 'Restart WSL' -Status 'Error' -Message 'WSL restart did not finish cleanly.' -Details "Shutdown: $($shutdown.Details)`nStart: $($start.Details)" -ExitCode $start.ExitCode
}

function Clear-HermesWslFiles {
    $command = @'
set -e
pkill -f hermes 2>/dev/null || true
rm -rf "$HOME/.hermes" "$HOME/.config/hermes" "$HOME/hermes-agent"
rm -f "$HOME/.local/bin/hermes" "$HOME/.local/bin/hermes-agent"
printf 'Removed user-level Hermes files for %s\n' "$(whoami)"
'@
    $result = Invoke-WslShell -Command $command -TimeoutSeconds 120
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Clean Hermes WSL Files' -Status 'Installed' -Message 'Hermes user files were removed inside WSL.' -Details $result.Details
    }

    return Format-StatusResult -Name 'Clean Hermes WSL Files' -Status 'Error' -Message 'Failed to clean Hermes files inside WSL.' -Details $result.Details -ExitCode $result.ExitCode
}

function Get-DefaultWslDistroName {
    $list = Invoke-WslCommand -Arguments @('-l', '-q') -LogFile (Get-LogFilePath -Kind 'app') -TimeoutSeconds 30
    if ($list.Status -ne 'Success' -or -not $list.Details) {
        return ''
    }

    $lines = @($list.Details -split "`r?`n" | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($lines.Count -gt 0) {
        return $lines[0]
    }

    return ''
}

function Unregister-DefaultWslDistro {
    $distro = Get-DefaultWslDistroName
    if (-not $distro) {
        return Format-StatusResult -Name 'Wipe WSL Distro' -Status 'Missing' -Message 'No default WSL distro was found.' -ExitCode 1
    }

    $result = Invoke-WslCommand -Arguments @('--unregister', $distro) -LogFile (Get-LogFilePath -Kind 'app') -TimeoutSeconds 300
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Wipe WSL Distro' -Status 'Installed' -Message "Unregistered WSL distro '$distro'." -Details 'This deletes that distro data. Install WSL again to recreate it.'
    }

    return Format-StatusResult -Name 'Wipe WSL Distro' -Status 'Error' -Message "Failed to unregister WSL distro '$distro'." -Details $result.Details -ExitCode $result.ExitCode
}

function Reinstall-DefaultWslDistro {
    $wipe = Unregister-DefaultWslDistro
    if ($wipe.Status -eq 'Error') {
        return $wipe
    }

    $install = Install-Wsl
    return [pscustomobject]@{
        Name     = 'Reinstall WSL Distro'
        Status   = $install.Status
        Message  = 'WSL distro reinstall command completed.'
        Details  = "Wipe: $($wipe.Message)`nInstall: $($install.Details)"
        ExitCode = $install.ExitCode
    }
}

