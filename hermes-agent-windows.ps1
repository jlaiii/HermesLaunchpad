[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$isWindowsHost = ($env:OS -eq 'Windows_NT') -or ($PSVersionTable.PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)

function Test-LauncherAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Start-LauncherElevated {
    param(
        [switch]$RequireSta
    )

    $launcher = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { (Get-Command pwsh.exe).Source } else { (Get-Command powershell.exe).Source }
    $arguments = @('-NoProfile')
    if ($RequireSta -and $launcher -notmatch 'pwsh\.exe$') {
        $arguments += '-STA'
    }
    $arguments += @('-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    Start-Process -FilePath $launcher -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $PSCommandPath) -Verb RunAs
}

$currentApartment = [System.Threading.Thread]::CurrentThread.ApartmentState
if ($isWindowsHost -and (-not (Test-LauncherAdmin))) {
    Write-Host 'hermes-agent-windows needs Administrator permission for WSL install, repair, and service actions.' -ForegroundColor Yellow
    Write-Host 'Windows will ask for permission now. Choose Yes to continue.' -ForegroundColor Yellow
    Start-LauncherElevated -RequireSta:($currentApartment -ne 'STA')
    return
}

if ($isWindowsHost -and $currentApartment -ne 'STA') {
    $launcher = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { (Get-Command pwsh.exe).Source } else { (Get-Command powershell.exe).Source }
    $arguments = @('-NoProfile')
    if ($launcher -notmatch 'pwsh\.exe$') {
        $arguments += '-STA'
    }
    $arguments += @('-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    Start-Process -FilePath $launcher -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $PSCommandPath)
    return
}

$global:HermesAgentWindowsRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$global:HermesAgentWindowsLogPath = Join-Path $global:HermesAgentWindowsRoot 'logs\app.log'

if (-not (Test-Path (Join-Path $global:HermesAgentWindowsRoot 'src\utils.ps1'))) {
    Write-Host 'Required project files are missing. Please run install.ps1 again.' -ForegroundColor Red
    throw 'Missing required project files.'
}

. (Join-Path $global:HermesAgentWindowsRoot 'src\utils.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\checks.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\wsl-manager.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\ollama-manager.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\hermes-manager.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\app-manager.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\bot-manager.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\installer.ps1')
. (Join-Path $global:HermesAgentWindowsRoot 'src\gui.ps1')

Write-Host '========================================================' -ForegroundColor Cyan
Write-Host 'hermes-agent-windows' -ForegroundColor Cyan
Write-Host 'Smart Windows Setup Tool for Hermes Agent' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan
Write-Log -Message 'hermes-agent-windows launcher started.' -Level 'INFO' -LogFile (Get-LogFilePath -Kind 'app') | Out-Null

try {
    Start-hermes-agent-windowsGui
}
catch {
    Write-Log -Message "Launcher error: $($_.Exception.Message)" -Level 'ERROR' -LogFile (Get-LogFilePath -Kind 'app') | Out-Null
    Show-ErrorMessage -Message $_.Exception.Message -Title 'hermes-agent-windows'
    throw
}

