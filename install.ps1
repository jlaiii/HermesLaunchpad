[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Get-InstallerRoot {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    if ($MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }

    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'hermes-agent-windows')
}

function Write-InstallStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    switch ($Level) {
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        'WARN'    { Write-Host $Message -ForegroundColor Yellow }
        'ERROR'   { Write-Host $Message -ForegroundColor Red }
        default   { Write-Host $Message -ForegroundColor Cyan }
    }
}

function Stop-Installer {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [int]$ExitCode = 1
    )

    $global:LASTEXITCODE = $ExitCode
    Write-InstallStatus -Message "hermes-agent-windows install failed: $Message" -Level 'ERROR'
    throw $Message
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-File {
    param([Parameter(Mandatory)][string]$Path)

    $dir = Split-Path -Parent $Path
    if ($dir) {
        Ensure-Directory -Path $dir
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

function Test-Admin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Start-InstallerAsAdmin {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot
    )

    $launcherExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { (Get-Command pwsh.exe).Source } else { (Get-Command powershell.exe).Source }

    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        Write-InstallStatus -Message 'Administrator permission is required. Windows will ask for permission now.' -Level 'WARN'
        Start-Process -FilePath $launcherExe -ArgumentList $arguments -WorkingDirectory $InstallerRoot -Verb RunAs | Out-Null
        return $true
    }

    $baseUrl = $env:HERMES_AGENT_WINDOWS_BASE_URL
    if (-not $baseUrl) {
        $baseUrl = 'https://jlaiii.github.io/hermes-agent-windows'
    }

    if ($baseUrl -and ($baseUrl -notmatch 'example\\.com')) {
        $installUrl = "$baseUrl/install.ps1"
        $command = "& { irm '$installUrl' | iex }"
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command)
        Write-InstallStatus -Message 'Administrator permission is required. Windows will ask for permission now.' -Level 'WARN'
        Start-Process -FilePath $launcherExe -ArgumentList $arguments -WorkingDirectory $InstallerRoot -Verb RunAs | Out-Null
        return $true
    }

    Write-InstallStatus -Message 'Administrator permission is required, but the bootstrap base URL is not set.' -Level 'ERROR'
    Write-InstallStatus -Message 'Run PowerShell as Administrator, then run the install command again. Or set HERMES_AGENT_WINDOWS_BASE_URL as a backup download source.' -Level 'ERROR'
    return $false
}

function Get-LocalPowerShellVersion {
    return $PSVersionTable.PSVersion
}

function Download-ProjectFile {
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $downloadUrl = "$BaseUrl/$RelativePath"
    Write-InstallStatus -Message "Downloading $RelativePath"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
    }

    Invoke-WebRequest -Uri $downloadUrl -OutFile $TargetPath -UseBasicParsing
}

try {
    $installerRoot = Get-InstallerRoot
    $global:HermesAgentWindowsRoot = $installerRoot
    $global:HermesAgentWindowsLogPath = Join-Path $installerRoot 'logs\install.log'

    Write-InstallStatus -Message 'hermes-agent-windows bootstrap starting...'

    Ensure-Directory -Path $installerRoot
    Ensure-Directory -Path (Join-Path $installerRoot 'src')
    Ensure-Directory -Path (Join-Path $installerRoot 'docs')
    Ensure-Directory -Path (Join-Path $installerRoot 'logs')
    Ensure-File -Path (Join-Path $installerRoot 'logs\install.log')
    Ensure-File -Path (Join-Path $installerRoot 'logs\app.log')

    if (-not (Test-Admin)) {
        Add-Content -Path $global:HermesAgentWindowsLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][WARN] Installer is not elevated. Requesting Administrator permission." -Encoding UTF8
        if (Start-InstallerAsAdmin -InstallerRoot $installerRoot) {
            Add-Content -Path $global:HermesAgentWindowsLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][INFO] Elevated installer process requested." -Encoding UTF8
            return
        }

        Stop-Installer -Message 'Administrator permission is required to install or repair WSL and system components.' -ExitCode 1
    }

    $psVersion = Get-LocalPowerShellVersion
    Write-InstallStatus -Message "Current PowerShell: $psVersion"
    if ($psVersion.Major -lt 5) {
        Stop-Installer -Message 'PowerShell 5.1 or newer is required.' -ExitCode 1
    }

    $baseUrl = $env:HERMES_AGENT_WINDOWS_BASE_URL
    if (-not $baseUrl) {
        $baseUrl = 'https://jlaiii.github.io/hermes-agent-windows'
    }

    $projectFiles = @(
        'hermes-agent-windows.ps1',
        'hermes-agent-windows.bat',
        'README.md',
        'LICENSE',
        'docs/setup-guide.md',
        'src/gui.ps1',
        'src/checks.ps1',
        'src/installer.ps1',
        'src/wsl-manager.ps1',
        'src/ollama-manager.ps1',
        'src/hermes-manager.ps1',
        'src/app-manager.ps1',
        'src/utils.ps1',
        'src/bot-manager.ps1'
    )

    $hasPlaceholderBaseUrl = ($baseUrl -match 'example\\.com')
    if ($hasPlaceholderBaseUrl) {
        Write-InstallStatus -Message 'Base URL still contains a placeholder. Local files will be used if they already exist.' -Level 'WARN'
    }

    foreach ($relativePath in $projectFiles) {
        $target = Join-Path $installerRoot $relativePath
        if (-not (Test-Path $target)) {
            if ($hasPlaceholderBaseUrl) {
                Stop-Installer -Message "Missing file: $relativePath. The base URL is a placeholder. Provide the full local project files." -ExitCode 1
            }
        }
        else {
            Write-InstallStatus -Message "Refreshing $relativePath" -Level 'INFO'
        }
        Download-ProjectFile -BaseUrl $baseUrl -RelativePath $relativePath -TargetPath $target
    }

    $requiredScripts = @(
        'src\utils.ps1',
        'src\checks.ps1',
        'src\wsl-manager.ps1',
        'src\ollama-manager.ps1',
        'src\hermes-manager.ps1',
        'src\app-manager.ps1',
        'src\installer.ps1'
    )

    foreach ($relativePath in $requiredScripts) {
        $target = Join-Path $installerRoot $relativePath
        if (-not (Test-Path $target)) {
            Stop-Installer -Message "Required script missing after preparation: $relativePath" -ExitCode 1
        }
    }

    $global:HermesAgentWindowsLogPath = Join-Path $installerRoot 'logs\install.log'
    Add-Content -Path $global:HermesAgentWindowsLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][INFO] Installer entry point started." -Encoding UTF8
    Add-Content -Path $global:HermesAgentWindowsLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][SUCCESS] Project folder prepared at $installerRoot" -Encoding UTF8

    $launchScript = Join-Path $installerRoot 'hermes-agent-windows.ps1'
    if (-not (Test-Path $launchScript)) {
        Stop-Installer -Message 'hermes-agent-windows.ps1 was not found after preparation.' -ExitCode 1
    }

    $launcherExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { (Get-Command pwsh.exe).Source } else { (Get-Command powershell.exe).Source }
    $launchArgs = @('-ExecutionPolicy', 'Bypass', '-File', $launchScript)
    if ($launcherExe -notmatch 'pwsh\.exe$') {
        $launchArgs = @('-STA') + $launchArgs
    }

    Add-Content -Path $global:HermesAgentWindowsLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][INFO] Launching main app using $launcherExe" -Encoding UTF8
    Start-Process -FilePath $launcherExe -ArgumentList $launchArgs -WorkingDirectory $installerRoot | Out-Null
    Add-Content -Path $global:HermesAgentWindowsLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][SUCCESS] Launcher process started." -Encoding UTF8

    Write-InstallStatus -Message 'hermes-agent-windows bootstrap finished.' -Level 'SUCCESS'
}
catch {
    $global:LASTEXITCODE = 1
    Write-InstallStatus -Message "hermes-agent-windows install error: $($_.Exception.Message)" -Level 'ERROR'
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    throw
}

