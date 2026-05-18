if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'utils.ps1')
}

function Get-hermes-agent-windowsShortcutInfo {
    $projectRoot = Get-ProjectRoot
    $desktop = [Environment]::GetFolderPath('Desktop')
    $programs = [Environment]::GetFolderPath('Programs')
    $startMenuFolder = Join-Path $programs 'hermes-agent-windows'

    [pscustomobject]@{
        ProjectRoot       = $projectRoot
        DesktopShortcut   = Join-Path $desktop 'hermes-agent-windows.bat'
        StartMenuFolder   = $startMenuFolder
        StartMenuShortcut = Join-Path $startMenuFolder 'hermes-agent-windows.bat'
    }
}

function New-hermes-agent-windowsBat {
    param(
        [Parameter(Mandatory)]
        [string]$BatPath,
        [string]$Description = 'hermes-agent-windows'
    )

    $batDir = Split-Path -Parent $BatPath
    if ($batDir -and -not (Test-Path $batDir)) {
        New-Item -ItemType Directory -Path $batDir -Force | Out-Null
    }

    @"
@echo off
:: $Description — Self-updating launcher
:: Double-click to install/update from GitHub

net session >nul 2>&1
if %errorLevel% == 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://jlaiii.github.io/hermes-agent-windows/install.ps1 | iex"
) else (
    powershell.exe -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c ""%~f0""' -Verb runAs"
)
"@ | Set-Content -Path $BatPath -Encoding ASCII -Force
}

function Install-hermes-agent-windowsApp {
    $logFile = Get-LogFilePath -Kind 'app'
    $info = Get-hermes-agent-windowsShortcutInfo

    try {
        Write-Log -Message 'Installing hermes-agent-windows shortcuts.' -Level 'INFO' -LogFile $logFile | Out-Null
        New-hermes-agent-windowsBat -BatPath $info.DesktopShortcut -Description 'Update hermes-agent-windows from GitHub'
        New-hermes-agent-windowsBat -BatPath $info.StartMenuShortcut -Description 'Update hermes-agent-windows from GitHub'

        return Format-StatusResult -Name 'Install hermes-agent-windows App' -Status 'Installed' -Message 'hermes-agent-windows shortcuts were installed.' -Details "Desktop: $($info.DesktopShortcut)`nStart Menu: $($info.StartMenuShortcut)"
    }
    catch {
        return Format-StatusResult -Name 'Install hermes-agent-windows App' -Status 'Error' -Message 'Failed to install hermes-agent-windows shortcuts.' -Details $_.Exception.Message -ExitCode 1
    }
}

function Uninstall-hermes-agent-windowsApp {
    $logFile = Get-LogFilePath -Kind 'app'
    $info = Get-hermes-agent-windowsShortcutInfo
    $removed = New-Object System.Collections.Generic.List[string]

    try {
        foreach ($path in @($info.DesktopShortcut, $info.StartMenuShortcut)) {
            if (Test-Path $path) {
                Remove-Item -LiteralPath $path -Force
                $removed.Add($path)
            }
        }

        if ((Test-Path $info.StartMenuFolder) -and -not (Get-ChildItem -LiteralPath $info.StartMenuFolder -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $info.StartMenuFolder -Force
        }

        Write-Log -Message 'hermes-agent-windows shortcuts were removed.' -Level 'SUCCESS' -LogFile $logFile | Out-Null
        return Format-StatusResult -Name 'Uninstall hermes-agent-windows App' -Status 'Stopped' -Message 'hermes-agent-windows shortcuts were removed.' -Details (($removed | ForEach-Object { $_ }) -join "`n")
    }
    catch {
        return Format-StatusResult -Name 'Uninstall hermes-agent-windows App' -Status 'Error' -Message 'Failed to remove hermes-agent-windows shortcuts.' -Details $_.Exception.Message -ExitCode 1
    }
}

function Get-hermes-agent-windowsAppStatus {
    $info = Get-hermes-agent-windowsShortcutInfo
    $installed = (Test-Path $info.DesktopShortcut) -or (Test-Path $info.StartMenuShortcut)

    if ($installed) {
        return Format-StatusResult -Name 'hermes-agent-windows App' -Status 'Installed' -Message 'hermes-agent-windows shortcuts are installed.' -Details "Desktop: $([bool](Test-Path $info.DesktopShortcut))`nStart Menu: $([bool](Test-Path $info.StartMenuShortcut))"
    }

    return Format-StatusResult -Name 'hermes-agent-windows App' -Status 'Missing' -Message 'hermes-agent-windows shortcuts are not installed.' -Details 'Use Install hermes-agent-windows App to add Desktop and Start Menu shortcuts.'
}

function Get-WindowsBootLaunchStatus {
    $taskName = 'hermes-agent-windows-boot'
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        if ($task.State -eq 'Ready') {
            return Format-StatusResult -Name 'Boot Launch' -Status 'Enabled' -Message 'hermes-agent-windows launches on Windows boot.' -Details 'Task Scheduler entry exists and is active.'
        }
        return Format-StatusResult -Name 'Boot Launch' -Status 'Disabled' -Message 'hermes-agent-windows boot task exists but is not enabled.' -Details 'The scheduled task may be disabled.'
    }
    catch {
        return Format-StatusResult -Name 'Boot Launch' -Status 'Disabled' -Message 'hermes-agent-windows does not launch on boot.' -Details 'No scheduled task found. Toggle on to create one.'
    }
}

function Set-WindowsBootLaunch {
    param([bool]$Enable)

    $taskName = 'hermes-agent-windows-boot'
    $taskPath = '\'
    $projectRoot = Get-ProjectRoot
    $guiScript = Join-Path $projectRoot 'src' 'gui.ps1'
    $launcher = Join-Path $projectRoot 'launch-gui.ps1'
    # Ensure a launcher script exists (lightweight wrapper that dot-sources everything)
    if (-not (Test-Path $launcher)) {
        $safePath = $projectRoot -replace "'", "''"
        @"
# hermes-agent-windows GUI launcher - auto-generated
`$PSScriptRoot = '$safePath'
. (Join-Path `$PSScriptRoot 'src' 'gui.ps1')
Start-hermes-agent-windowsGui
"@ | Set-Content -Path $launcher -Encoding UTF8 -Force
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
    $trigger = New-ScheduledTaskTrigger -AtLogon
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    try {
        if ($Enable) {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            $task = Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
            return Format-StatusResult -Name 'Boot Launch' -Status 'Enabled' -Message 'hermes-agent-windows will auto-launch on Windows login.' -Details "Task: $taskName"
        }
        else {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false | Out-Null
            return Format-StatusResult -Name 'Boot Launch' -Status 'Disabled' -Message 'hermes-agent-windows will no longer auto-launch on boot.' -Details "Task removed."
        }
    }
    catch {
        return Format-StatusResult -Name 'Boot Launch' -Status 'Error' -Message 'Failed to toggle boot launch.' -Details $_.Exception.Message -ExitCode 1
    }
}

function Get-WslDiskUsage {
    $result = Invoke-WslShell -Command 'df -h / 2>/dev/null' -TimeoutSeconds 10
    if ($result.Status -eq 'Success') {
        $lines = $result.Details -split "`r?`n" | Where-Object { $_.Trim() }
        $mainLine = $lines | Where-Object { $_ -match '(/$|/dev/root)' } | Select-Object -First 1
        if (-not $mainLine) {
            $mainLine = $lines | Where-Object { $_ -match '^/dev/' } | Select-Object -First 1
        }
        if ($mainLine) {
            $parts = $mainLine -split '\s+' -ne ''
            if ($parts.Count -ge 6) {
                $total = $parts[1]
                $used = $parts[2]
                $avail = $parts[3]
                $percent = $parts[4]
                return Format-StatusResult -Name 'WSL Disk' -Status 'Installed' -Message "WSL disk: $used used / $total total ($percent)" -Details "Available: $avail"
            }
        }
        return Format-StatusResult -Name 'WSL Disk' -Status 'Unknown' -Message 'WSL disk usage returned unparsable output.' -Details $result.Details
    }
    return Format-StatusResult -Name 'WSL Disk' -Status 'Unknown' -Message 'Could not retrieve WSL disk usage.' -Details $result.Details -ExitCode $result.ExitCode
}

