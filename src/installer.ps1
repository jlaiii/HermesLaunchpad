if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'utils.ps1')
}
if (-not (Get-Command Get-SystemSummary -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'checks.ps1')
}
if (-not (Get-Command Test-WslExists -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'wsl-manager.ps1')
}
if (-not (Get-Command Test-OllamaAvailable -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'ollama-manager.ps1')
}
if (-not (Get-Command Test-HermesInstalled -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'hermes-manager.ps1')
}
if (-not (Get-Command Get-hermes-agent-windowsAppStatus -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'app-manager.ps1')
}

function Invoke-StatusCheck {
    $summary = Get-SystemSummary
    $windows = Get-WindowsVersionInfo
    $powershell = Get-PowerShellVersionInfo
    $wslStatus = Get-WslStatus
    $wslVersion = Get-WslVersion
    $wslDistros = Get-WslDistroList
    $wslAccount = Get-WslAccountInfo
    $ollamaAvailable = Test-OllamaAvailable
    $ollamaVersion = Get-OllamaVersion
    $ollamaRunning = Test-OllamaRunning
    $hermesStatus = Get-HermesStatus
    $hermesVersion = Get-HermesVersion
    $gatewayStatus = Get-HermesGatewayStatus
    $appStatus = Get-hermes-agent-windowsAppStatus
    $bootLaunch = Get-WindowsBootLaunchStatus
    $wslDisk = Get-WslDiskUsage
    $updateCheck = Get-HermesUpdateStatus

    $ollamaStatus = Format-StatusResult -Name 'Ollama Status' -Status $(if ($ollamaAvailable) { $ollamaRunning.Status } else { 'Missing' }) -Message $(if ($ollamaAvailable) { 'Ollama is installed inside WSL.' } else { 'Ollama is missing inside WSL.' }) -Details $(if ($ollamaAvailable) { $ollamaRunning.Details } else { 'Use Install Ollama in WSL.' })

    $statusLines = @(
        "Admin Check: $($summary.Admin)"
        "Windows Version: $($windows.Message)"
        "PowerShell Version: $($powershell.Message)"
        "WSL Status: $($wslStatus.Status) - $($wslStatus.Message)"
        "WSL Version: $($wslVersion.Status) - $($wslVersion.Message)"
        "WSL Distro: $($wslDistros.Status) - $($wslDistros.Message)"
        "WSL Account: $($wslAccount.Status) - $($wslAccount.Message)"
        "WSL Disk: $($wslDisk.Status) - $($wslDisk.Message)"
        "Ollama Status: $($ollamaStatus.Status) - $($ollamaStatus.Message)"
        "Ollama Version: $($ollamaVersion.Status) - $($ollamaVersion.Message)"
        "Hermes Status: $($hermesStatus.Status) - $($hermesStatus.Message)"
        "Hermes Version: $($hermesVersion.Status) - $($hermesVersion.Message)"
        "Hermes Gateway: $($gatewayStatus.Status) - $($gatewayStatus.Message)"
        "hermes-agent-windows App: $($appStatus.Status) - $($appStatus.Message)"
        "Boot Launch: $($bootLaunch.Status) - $($bootLaunch.Message)"
        "Update Status: $($updateCheck.Status) - $($updateCheck.Message)"
    )

    foreach ($line in $statusLines) {
        Write-Log -Message $line -Level 'INFO' -LogFile (Get-LogFilePath -Kind 'app') | Out-Null
    }

    return [pscustomobject]@{
        AdminCheck       = Format-StatusResult -Name 'Admin Check' -Status $(if ($summary.Admin) { 'Installed' } else { 'Missing' }) -Message $(if ($summary.Admin) { 'Administrator access confirmed.' } else { 'Administrator access is missing. WSL install/repair may need an elevated PowerShell.' })
        WindowsVersion   = [pscustomobject]$windows
        PowerShellVersion = [pscustomobject]$powershell
        WslStatus        = [pscustomobject]$wslStatus
        WslVersion       = [pscustomobject]$wslVersion
        WslDistro        = [pscustomobject]$wslDistros
        WslAccount       = [pscustomobject]$wslAccount
        OllamaStatus     = [pscustomobject]$ollamaStatus
        OllamaVersion    = [pscustomobject]$ollamaVersion
        OllamaRunning    = [pscustomobject]$ollamaRunning
        HermesStatus     = [pscustomobject]$hermesStatus
        HermesVersion    = [pscustomobject]$hermesVersion
        GatewayStatus    = [pscustomobject]$gatewayStatus
        AppStatus        = [pscustomobject]$appStatus
        WslDisk          = [pscustomobject]$wslDisk
        BootLaunch       = [pscustomobject]$bootLaunch
        Updates          = [pscustomobject]$updateCheck
        Summary          = "App: $($appStatus.Status) | WSL: $($wslDistros.Status) | Account: $($wslAccount.Status) | Ollama: $($ollamaStatus.Status) | Hermes: $($hermesStatus.Status) | Gateway: $($gatewayStatus.Status) | Updates: $($updateCheck.Status)"
    }
}

function Install-MissingRequirements {
    param(
        [pscustomobject]$StatusSummary,
        [switch]$Automatic
    )

    $results = New-Object System.Collections.Generic.List[object]
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not $StatusSummary) {
        $StatusSummary = Invoke-StatusCheck
    }

    $isAdmin = Test-IsAdmin
    if (-not (Test-WslExists)) {
        if (-not $isAdmin) {
            $message = 'WSL is missing and cannot be installed without Administrator access.'
            Write-Log -Message $message -Level 'ERROR' -LogFile $logFile | Out-Null
            return [pscustomobject]@{ Status = 'Error'; Message = $message; Details = 'Open PowerShell as Administrator, then rerun setup.'; ExitCode = 1; Results = $results }
        }

        $results.Add((Install-Wsl))
        if ($results[-1].Status -eq 'NeedsReboot') {
            return [pscustomobject]@{ Status = 'NeedsReboot'; Message = 'WSL installation requires a Windows restart.'; Details = $results[-1].Details; ExitCode = 0; Results = $results }
        }
    }
    else {
        $results.Add((Format-StatusResult -Name 'WSL Install' -Status 'Installed' -Message 'WSL is already available.'))
    }

    $results.Add((Start-WslDefaultDistro))
    $results.Add((Ensure-WslAdminAccount))
    if ($results[-1].Status -eq 'Error') {
        return [pscustomobject]@{ Status = 'Error'; Message = 'WSL admin/admin helper account could not be prepared.'; Details = $results[-1].Details; ExitCode = $results[-1].ExitCode; Results = $results }
    }

    if (-not (Test-OllamaAvailable)) {
        Write-Log -Message 'Ollama is missing inside WSL. Installing now.' -Level 'WARN' -LogFile $logFile | Out-Null
        $results.Add((Install-Ollama -OpenPageOnFailure:$false))
    }
    else {
        $results.Add((Format-StatusResult -Name 'Ollama Install' -Status 'Installed' -Message 'Ollama is already installed inside WSL.'))
    }

    $ollamaRunning = Test-OllamaRunning
    $results.Add($ollamaRunning)
    if ($ollamaRunning.Status -ne 'Running' -and $ollamaRunning.Status -ne 'Missing') {
        $results.Add((Start-Ollama))
    }

    if (-not (Test-HermesInstalled)) {
        Write-Log -Message 'Hermes Agent is missing inside WSL. Installing now.' -Level 'WARN' -LogFile $logFile | Out-Null
        $results.Add((Install-HermesAgent))
    }
    else {
        $results.Add((Format-StatusResult -Name 'Hermes Install' -Status 'Installed' -Message 'Hermes Agent is already installed inside WSL.'))
    }

    # Enable Gateway if it is not running (Hermes TUI cannot run headless)
    $gatewayStatus = Get-HermesGatewayStatus
    if ($gatewayStatus.Status -eq 'Stopped' -or $gatewayStatus.Status -eq 'Missing') {
        Write-Log -Message 'Hermes Gateway is not running. Enabling now.' -Level 'INFO' -LogFile $logFile | Out-Null
        $results.Add((Enable-HermesGateway))
    }
    else {
        $results.Add($gatewayStatus)
    }

    $errorCount = @($results | Where-Object { $_.Status -eq 'Error' }).Count
    return [pscustomobject]@{
        Status   = if ($errorCount -gt 0) { 'Error' } else { 'Installed' }
        Message  = 'WSL-first requirement flow completed.'
        Details  = ($results | ForEach-Object { "$($_.Name): $($_.Status)" }) -join '; '
        ExitCode = if ($errorCount -gt 0) { 1 } else { 0 }
        Results  = $results
    }
}

function Update-AllComponents {
    $logFile = Get-LogFilePath -Kind 'app'
    $results = New-Object System.Collections.Generic.List[object]

    if (Test-WslExists) {
        Write-Log -Message 'Attempting WSL platform update.' -Level 'INFO' -LogFile $logFile | Out-Null
        $results.Add((Invoke-WslCommand -Arguments @('--update') -LogFile $logFile -TimeoutSeconds 600))
        Write-Log -Message 'Attempting Ubuntu package metadata refresh inside WSL.' -Level 'INFO' -LogFile $logFile | Out-Null
        $results.Add((Invoke-WslRootShell -Command 'apt-get update' -TimeoutSeconds 600))
    }

    $results.Add((Update-HermesAgent))
    $errorCount = @($results | Where-Object { $_.Status -eq 'Error' }).Count
    return [pscustomobject]@{
        Status   = if ($errorCount -gt 0) { 'Error' } else { 'Installed' }
        Message  = 'Update flow completed.'
        Details  = ($results | ForEach-Object { $_.Status }) -join ', '
        ExitCode = if ($errorCount -gt 0) { 1 } else { 0 }
        Results  = $results
    }
}

function Start-FullSetup {
    Write-Log -Message 'Starting WSL-first full setup sequence.' -Level 'INFO' -LogFile (Get-LogFilePath -Kind 'app') | Out-Null
    $summary = Invoke-StatusCheck
    $actions = Install-MissingRequirements -StatusSummary $summary -Automatic
    $finalSummary = Invoke-StatusCheck

    $finalMessage = @(
        "Admin: $($finalSummary.AdminCheck.Status)"
        "WSL: $($finalSummary.WslStatus.Status)"
        "Account: $($finalSummary.WslAccount.Status)"
        "Ollama: $($finalSummary.OllamaStatus.Status)"
        "Hermes: $($finalSummary.HermesStatus.Status)"
        "Gateway: $($finalSummary.GatewayStatus.Status)"
    ) -join ' | '

    Write-Log -Message "Full setup summary: $finalMessage" -Level 'SUCCESS' -LogFile (Get-LogFilePath -Kind 'app') | Out-Null
    return [pscustomobject]@{
        Status   = $actions.Status
        Message  = if ($actions.Status -eq 'Error') { $actions.Message } else { 'Full WSL-first setup completed.' }
        Details  = $finalMessage
        ExitCode = $actions.ExitCode
        Initial  = $summary
        Actions  = $actions
        Final    = $finalSummary
    }
}

