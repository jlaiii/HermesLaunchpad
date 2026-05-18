if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'utils.ps1')
}
if (-not (Get-Command Test-CommandExists -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'checks.ps1')
}
if (-not (Get-Command Invoke-WslShell -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'wsl-manager.ps1')
}
if (-not (Get-Command Test-OllamaAvailable -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'ollama-manager.ps1')
}

$script:HermesWslInstallCommand = 'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup'
$script:HermesWslUser = 'admin'

function Invoke-HermesWslCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [int]$TimeoutSeconds = 120,
        [switch]$AsAdminUser
    )

    $user = if ($AsAdminUser) { $script:HermesWslUser } else { '' }
    $wrappedCommand = 'export PATH="$HOME/.local/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"; ' + $Command
    return Invoke-WslShell -Command $wrappedCommand -User $user -TimeoutSeconds $TimeoutSeconds
}

function Test-HermesInstalled {
    if (-not (Test-WslExists)) {
        return $false
    }

    $result = Invoke-HermesWslCommand -Command 'command -v hermes' -AsAdminUser -TimeoutSeconds 30
    if ($result.Status -ne 'Success' -or -not $result.Details) {
        return $false
    }

    # Verify the binary actually works, not just that a wrapper script exists
    $versionResult = Invoke-HermesWslCommand -Command 'hermes --version 2>/dev/null || echo "HERMES_BINARY_BROKEN"' -AsAdminUser -TimeoutSeconds 30
    if ($versionResult.Status -eq 'Success' -and $versionResult.Details -and $versionResult.Details -notmatch 'HERMES_BINARY_BROKEN|No such file|not found') {
        return $true
    }

    return $false
}

function Get-HermesVersion {
    if (-not (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Agent Version' -Status 'Missing' -Message 'Hermes Agent is not installed in WSL.' -Details 'The setup installs Hermes inside WSL with the official Nous Research Linux installer.'
    }

    $result = Invoke-HermesWslCommand -Command 'hermes --version' -AsAdminUser -TimeoutSeconds 60
    if ($result.Status -eq 'Success') {
        $details = $result.Details
        $configAge = Invoke-HermesWslCommand -Command 'test -f "$HOME/.hermes/config.yaml" && stat -c "%Y" "$HOME/.hermes/config.yaml" || echo ""' -AsAdminUser -TimeoutSeconds 15
        if ($configAge.Status -eq 'Success' -and $configAge.Details -match '^\d+$') {
            $epoch = [int]$configAge.Details.Trim()
            $configDate = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
            $ageText = if ($configDate -gt (Get-Date).AddMinutes(-10)) { 'just now' } else { (Get-Date) - $configDate | Select-Object -ExpandProperty TotalMinutes | ForEach-Object { "$([math]::Round($_,0)) minutes ago" } }
            $details = "$details`nConfig: $ageText"
        }
        return Format-StatusResult -Name 'Hermes Agent Version' -Status 'Installed' -Message 'Hermes Agent version retrieved from WSL.' -Details $details
    }

    return Format-StatusResult -Name 'Hermes Agent Version' -Status 'Error' -Message 'Could not read Hermes Agent version from WSL.' -Details $result.Details -ExitCode $result.ExitCode
}

function Get-HermesStatus {
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'Hermes Agent Status' -Status 'Missing' -Message 'WSL is required before Hermes can run.' -Details 'Install WSL first.'
    }

    $running = Invoke-HermesWslCommand -Command "ps -eo pid=,comm=,args= | awk '`$2 !~ /^(bash|sh|awk|ps)$/ && `$0 ~ /hermes/ {print}'" -AsAdminUser -TimeoutSeconds 30
    if ($running.Status -eq 'Success' -and $running.Details -match 'hermes') {
        return Format-StatusResult -Name 'Hermes Agent Status' -Status 'Running' -Message 'Hermes Agent process is running inside WSL.' -Details $running.Details
    }

    if (Test-HermesInstalled) {
        return Format-StatusResult -Name 'Hermes Agent Status' -Status 'Stopped' -Message 'Hermes Agent is installed in WSL but is not currently running.' -Details 'Use Start Hermes Agent or Enable Gateway.'
    }

    return Format-StatusResult -Name 'Hermes Agent Status' -Status 'Missing' -Message 'Hermes Agent is not installed in WSL.' -Details 'Use Install Hermes Agent.'
}

function Install-HermesAgent {
    $logFile = Get-LogFilePath -Kind 'app'
    if (-not (Test-WslExists)) {
        return Format-StatusResult -Name 'Hermes Install' -Status 'Missing' -Message 'WSL is required before installing Hermes Agent.' -Details 'Install WSL first.' -ExitCode 1
    }

    $admin = Ensure-WslAdminAccount
    if ($admin.Status -eq 'Error') {
        return $admin
    }

    if (Test-HermesInstalled) {
        return Format-StatusResult -Name 'Hermes Install' -Status 'Installed' -Message 'Hermes Agent is already installed in WSL.' -Details 'No installation was needed.'
    }

    Write-Log -Message 'Installing Hermes Agent inside WSL with the official Nous Research Linux installer.' -Level 'INFO' -LogFile $logFile | Out-Null
    $result = Invoke-HermesWslCommand -Command $script:HermesWslInstallCommand -AsAdminUser -TimeoutSeconds 1200
    if ($result.Status -eq 'Success' -and (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Install' -Status 'Installed' -Message 'Hermes Agent was installed inside WSL.' -Details $result.Details
    }

    # The upstream installer may have created a broken partial install (e.g. shim exists but venv is incomplete).
    # Run our non-interactive fallback to rebuild from scratch.
    if (Test-HermesInstalled) {
        return Format-StatusResult -Name 'Hermes Install' -Status 'Installed' -Message 'Hermes Agent was found after installer returned an error.' -Details $result.Details
    }

    Write-Log -Message 'Upstream installer did not produce a working hermes binary. Running safe non-interactive fallback rebuild.' -Level 'WARN' -LogFile $logFile | Out-Null
    $fallbackScript = @'
set -e
HERMES_DIR="$HOME/.hermes/hermes-agent"
BACKUP_DIR="$HOME/.hermes/hermes-agent-backup-$(date +%Y%m%d%H%M%S)"

# Backup existing config and .env so they survive the reinstall
if [ -f "$HERMES_DIR/.env" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HERMES_DIR/.env" "$BACKUP_DIR/"
fi
if [ -f "$HOME/.hermes/config.yaml" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.hermes/config.yaml" "$BACKUP_DIR/"
fi

# Remove stale checkout and clone fresh
rm -rf "$HERMES_DIR"
mkdir -p "$HERMES_DIR"
cd "$HERMES_DIR"

git clone --depth 1 --branch main https://github.com/NousResearch/hermes-agent.git "$HERMES_DIR-temp" 2>/dev/null || {
    echo "ERROR: git clone failed. Check network connectivity."
    exit 1
}
mv "$HERMES_DIR-temp"/* "$HERMES_DIR/" 2>/dev/null || true
mv "$HERMES_DIR-temp"/.* "$HERMES_DIR/" 2>/dev/null || true
rmdir "$HERMES_DIR-temp" 2>/dev/null || true
cd "$HERMES_DIR"

# Rebuild venv with pip-based install (avoids uv sync entry-point issues)
if command -v uv &>/dev/null; then
    export UV_NO_CONFIG=1
    uv venv venv --python 3.11 2>&1
    venv_python="$HERMES_DIR/venv/bin/python"
    "$venv_python" -m ensurepip --upgrade 2>&1 || true
    "$venv_python" -m pip install -e ".[all]" 2>&1
elif command -v python3 &>/dev/null; then
    python3 -m venv venv 2>&1
    venv_python="$HERMES_DIR/venv/bin/python"
    "$venv_python" -m ensurepip --upgrade 2>&1
    "$venv_python" -m pip install -e ".[all]" 2>&1
else
    echo "ERROR: Neither uv nor python3 available to create venv."
    exit 1
fi

# Verify the install actually worked
if ! "$HERMES_DIR/venv/bin/python" -m hermes_cli.main --version >/dev/null 2>&1; then
    echo "ERROR: Package install succeeded but hermes_cli module is not importable."
    exit 1
fi

# Restore backed-up config
if [ -d "$BACKUP_DIR" ]; then
    [ -f "$BACKUP_DIR/.env" ] && cp "$BACKUP_DIR/.env" "$HERMES_DIR/.env"
    [ -f "$BACKUP_DIR/config.yaml" ] && cp "$BACKUP_DIR/config.yaml" "$HOME/.hermes/config.yaml"
    echo "Config restored from backup."
fi

# Re-create the ~/.local/bin/hermes shim (always use python module for reliability)
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/hermes" <<'SHIM'
#!/usr/bin/env bash
unset PYTHONPATH
unset PYTHONHOME
SHIM_HERMES_DIR="$HOME/.hermes/hermes-agent"
exec "$SHIM_HERMES_DIR/venv/bin/python" -m hermes_cli.main "$@"
SHIM
chmod +x "$HOME/.local/bin/hermes"

echo "Reinstall complete."
'@
    $fallbackResult = Invoke-HermesWslCommand -Command $fallbackScript -AsAdminUser -TimeoutSeconds 900

    if ((Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Install' -Status 'Installed' -Message 'Hermes Agent was rebuilt and installed via fallback.' -Details $fallbackResult.Details
    }

    return Format-StatusResult -Name 'Hermes Install' -Status 'Error' -Message 'Hermes Agent installation in WSL failed. Both upstream installer and fallback rebuild failed.' -Details "Upstream: $($result.Details)`nFallback: $($fallbackResult.Details)" -ExitCode $fallbackResult.ExitCode
}

function Update-HermesAgent {
    if (-not (Test-HermesInstalled)) {
        return Install-HermesAgent
    }

    # Fast path: update in-place via git pull.
    # The NousResearch installer clones into ~/.hermes/hermes-agent and builds
    # a venv with uv.  uv venv does NOT include pip by default, so we use
    # ensurepip to bootstrap it, then install the updated package.
    $fastUpdate = @'
set +e
if [ -d "$HOME/.hermes/hermes-agent/.git" ]; then
    cd "$HOME/.hermes/hermes-agent"
    echo "Updating Hermes Agent from git..."
    git fetch origin
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    git reset --hard "origin/${current_branch}" 2>/dev/null || git reset --hard origin/main
    echo "Installing updated package..."

    venv_bin="$HOME/.hermes/hermes-agent/venv/bin"
    venv_python="$venv_bin/python"
    if [ ! -x "$venv_python" ]; then
        echo "ERROR: venv python not found at $venv_python"
        exit 1
    fi

    # uv venv creates venvs without pip — bootstrap it with ensurepip
    if ! "$venv_python" -m pip --version >/dev/null 2>&1; then
        echo "Bootstrapping pip into venv..."
        "$venv_python" -m ensurepip --upgrade 2>&1
    fi

    # Install updated package. Always use python -m pip because uv venvs
    # may only create pip3, not a pip symlink.
    "$venv_python" -m pip install -e . 2>&1
    pip_exit=$?

    if [ $pip_exit -eq 0 ]; then
        echo "In-place update complete."
    elif command -v uv &>/dev/null; then
        echo "pip install failed (exit $pip_exit), trying uv..."
        # uv sync does not always install setuptools entry points.
        # Use uv pip install -e for a proper editable install.
        uv pip install -e ".[all]" 2>&1
        uv_exit=$?
        if [ $uv_exit -eq 0 ]; then
            echo "In-place update complete via uv."
        else
            echo "uv install also failed (exit $uv_exit)."
            exit 1
        fi
    else
        echo "pip install failed (exit $pip_exit) and uv is not available."
        exit 1
    fi

    # Recreate the ~/.local/bin/hermes shim so it always points to python module
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/hermes" <<'SHIM'
#!/usr/bin/env bash
unset PYTHONPATH
unset PYTHONHOME
SHIM_HERMES_DIR="$HOME/.hermes/hermes-agent"
exec "$SHIM_HERMES_DIR/venv/bin/python" -m hermes_cli.main "$@"
SHIM
    chmod +x "$HOME/.local/bin/hermes"
    echo "Hermes shim recreated."
else
    echo "No git repository found; falling back to fresh clone."
    exit 1
fi
'@
    $result = Invoke-HermesWslCommand -Command $fastUpdate -AsAdminUser -TimeoutSeconds 300

    # Fallback: re-clone the repo and rebuild the venv from scratch,
    # using the original installer script but in a fully non-interactive way.
    # The upstream script has prompt_yes_no() that reads /dev/tty directly,
    # which deadlocks in a background PowerShell job.  Instead, we replicate
    # only the safe parts here (clone, re-create venv, install).
    if ($result.Status -ne 'Success') {
        $logFile = Get-LogFilePath -Kind 'app'
        Write-Log -Message 'Fast in-place update failed. Reinstalling from scratch (safe non-interactive fallback).' -Level 'WARN' -LogFile $logFile | Out-Null

        $fallbackScript = @'
set -e
HERMES_DIR="$HOME/.hermes/hermes-agent"
BACKUP_DIR="$HOME/.hermes/hermes-agent-backup-$(date +%Y%m%d%H%M%S)"

# Backup existing config and .env so they survive the reinstall
if [ -f "$HERMES_DIR/.env" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HERMES_DIR/.env" "$BACKUP_DIR/"
fi
if [ -f "$HOME/.hermes/config.yaml" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$HOME/.hermes/config.yaml" "$BACKUP_DIR/"
fi

# Remove stale checkout and clone fresh
rm -rf "$HERMES_DIR"
mkdir -p "$HERMES_DIR"
cd "$HERMES_DIR"

# Try SSH first, fall back to HTTPS
git clone --depth 1 --branch main https://github.com/NousResearch/hermes-agent.git "$HERMES_DIR-temp" 2>/dev/null || \
git clone --depth 1 --branch main git@github.com:NousResearch/hermes-agent.git "$HERMES_DIR-temp" 2>/dev/null || {
    echo "ERROR: git clone failed. Check network connectivity."
    exit 1
}
rm -rf "$HERMES_DIR"
mv "$HERMES_DIR-temp" "$HERMES_DIR"
cd "$HERMES_DIR"

# Rebuild venv.  uv is preferred because the upstream installer uses it.
if command -v uv &>/dev/null; then
    export UV_NO_CONFIG=1
    uv venv venv --python 3.11 2>&1
    venv_python="$HERMES_DIR/venv/bin/python"
    "$venv_python" -m ensurepip --upgrade 2>&1 || true
    # uv sync does not reliably create setuptools entry points.
    # Always use pip install -e to ensure hermes_cli is available.
    "$venv_python" -m pip install -e ".[all]" 2>&1
elif command -v python3 &>/dev/null; then
    python3 -m venv venv 2>&1
    venv_python="$HERMES_DIR/venv/bin/python"
    "$venv_python" -m ensurepip --upgrade 2>&1
    "$venv_python" -m pip install -e ".[all]" 2>&1
else
    echo "ERROR: Neither uv nor python3 available to create venv."
    exit 1
fi

# Verify the install actually worked
if ! "$HERMES_DIR/venv/bin/python" -m hermes_cli.main --version >/dev/null 2>&1; then
    echo "ERROR: Package install succeeded but hermes_cli module is not importable."
    exit 1
fi

# Restore backed-up config
if [ -d "$BACKUP_DIR" ]; then
    [ -f "$BACKUP_DIR/.env" ] && cp "$BACKUP_DIR/.env" "$HERMES_DIR/.env"
    [ -f "$BACKUP_DIR/config.yaml" ] && cp "$BACKUP_DIR/config.yaml" "$HOME/.hermes/config.yaml"
    echo "Config restored from backup."
fi

# Re-create the ~/.local/bin/hermes shim
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/hermes" <<'SHIM'
#!/usr/bin/env bash
unset PYTHONPATH
unset PYTHONHOME
SHIM_HERMES_DIR="$HOME/.hermes/hermes-agent"
exec "$SHIM_HERMES_DIR/venv/bin/python" -m hermes_cli.main "$@"
SHIM
chmod +x "$HOME/.local/bin/hermes"

echo "Reinstall complete."
'@
        $result = Invoke-HermesWslCommand -Command $fallbackScript -AsAdminUser -TimeoutSeconds 900
    }

    if ($result.Status -eq 'Success' -and (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Update' -Status 'Installed' -Message 'Hermes Agent was updated in WSL.' -Details $result.Details
    }

    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Hermes Update' -Status 'Installed' -Message 'Hermes Agent update completed.' -Details $result.Details
    }

    return Format-StatusResult -Name 'Hermes Update' -Status 'Error' -Message 'Hermes Agent update failed in WSL.' -Details $result.Details -ExitCode $result.ExitCode
}

function Start-HermesAgent {
    if (-not (Test-HermesInstalled)) {
        $install = Install-HermesAgent
        if ($install.Status -ne 'Installed') {
            return $install
        }
    }

    $command = 'mkdir -p "$HOME/.hermes"; nohup hermes > "$HOME/.hermes/hermes.log" 2>&1 & sleep 3; ps -eo pid=,comm=,args= | awk ''$2 !~ /^(bash|sh|awk|ps)$/ && $0 ~ /hermes/ {print}'''
    $result = Invoke-HermesWslCommand -Command $command -AsAdminUser -TimeoutSeconds 60
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Start Hermes Agent' -Status 'Running' -Message 'Hermes Agent was started inside WSL.' -Details 'Logs: /home/admin/.hermes/hermes.log'
    }

    return Format-StatusResult -Name 'Start Hermes Agent' -Status 'Error' -Message 'Hermes Agent did not start cleanly.' -Details $result.Details -ExitCode $result.ExitCode
}

function Stop-HermesAgent {
    $result = Invoke-HermesWslCommand -Command 'pkill -f "python.*hermes|venv/bin/hermes|hermes gateway" 2>/dev/null || true; sleep 1; ps -eo comm=,args= | awk ''$1 !~ /^(bash|sh|awk|ps)$/ && $0 ~ /hermes/ {found=1} END {exit found ? 1 : 0}''' -AsAdminUser -TimeoutSeconds 60
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Stop Hermes Agent' -Status 'Stopped' -Message 'Hermes Agent processes were stopped inside WSL.'
    }

    return Format-StatusResult -Name 'Stop Hermes Agent' -Status 'Error' -Message 'Failed to stop Hermes Agent cleanly.' -Details $result.Details -ExitCode $result.ExitCode
}

function Restart-HermesAgent {
    Stop-HermesAgent | Out-Null
    return Start-HermesAgent
}

function Invoke-HermesDoctor {
    if (-not (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Doctor' -Status 'Missing' -Message 'Hermes Agent is not installed in WSL.' -Details 'Install Hermes Agent first.' -ExitCode 1
    }

    $result = Invoke-HermesWslCommand -Command 'HERMES_ACCEPT_HOOKS=1 hermes doctor 2>&1' -AsAdminUser -TimeoutSeconds 900
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Hermes Doctor' -Status 'Installed' -Message 'Hermes Doctor completed.' -Details $result.Details
    }

    if ($result.ExitCode -eq 124) {
        return Format-StatusResult -Name 'Hermes Doctor' -Status 'Error' -Message 'Hermes Doctor did not finish within 15 minutes.' -Details 'The command may be waiting on an external dependency or provider check. Try opening the Hermes dashboard or running hermes doctor manually inside WSL for interactive prompts.' -ExitCode $result.ExitCode
    }

    return Format-StatusResult -Name 'Hermes Doctor' -Status 'Error' -Message 'Hermes Doctor found a problem or failed to run.' -Details $result.Details -ExitCode $result.ExitCode
}

function Open-HermesCli {
    if (-not (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Launch Hermes CLI' -Status 'Missing' -Message 'Hermes Agent is not installed in WSL.' -Details 'Install Hermes Agent first.' -ExitCode 1
    }

    $projectRoot = Get-ProjectRoot
    $logsPath = Join-Path $projectRoot 'logs'
    if (-not (Test-Path $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    }

    $launcherPath = Join-Path $logsPath 'Launch-HermesCli.cmd'
    $shellLauncherPath = Join-Path $logsPath 'launch-hermes-cli.sh'
    $projectRootForShell = $projectRoot -replace '\\', '/'
    if ($projectRootForShell -match '^([A-Za-z]):/(.*)$') {
        $driveLetter = $Matches[1].ToLowerInvariant()
        $pathPart = $Matches[2]
        $wslStartPath = "/mnt/$driveLetter/$pathPart"
    }
    else {
        $wslStartPath = '$HOME'
    }

    $shellLauncher = @'
#!/usr/bin/env bash
START_PATH="__HERMES_START_PATH__"
if [ -d "$START_PATH" ]; then
  cd "$START_PATH" || cd "$HOME" || exit 1
else
  cd "$HOME" || exit 1
fi

export PATH="$HOME/.local/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"
test -f "$HOME/.ollama-cloud.env" && . "$HOME/.ollama-cloud.env"
export HERMES_ACCEPT_HOOKS=1

echo "Starting Hermes Agent CLI..."
echo ""
echo "You can talk to Hermes here and ask it to inspect, edit, or explain files it can access."
echo "Working folder: $(pwd)"
echo "Provider/model come from your saved Hermes config."
echo ""
echo "Tip: type /help inside Hermes for chat commands, or Ctrl+C to stop."
echo ""
exec hermes chat --accept-hooks
'@
    $shellLauncher = $shellLauncher.Replace('__HERMES_START_PATH__', $wslStartPath)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($shellLauncherPath, ($shellLauncher -replace "`r`n", "`n"), $utf8NoBom)

    $shellLauncherForWsl = $shellLauncherPath -replace '\\', '/'
    if ($shellLauncherForWsl -match '^([A-Za-z]):/(.*)$') {
        $shellDriveLetter = $Matches[1].ToLowerInvariant()
        $shellPathPart = $Matches[2]
        $wslShellLauncherPath = "/mnt/$shellDriveLetter/$shellPathPart"
    }
    else {
        $wslShellLauncherPath = $shellLauncherPath
    }

    $launcherLines = @(
        '@echo off'
        'title Hermes Agent CLI'
        'echo Starting Hermes Agent CLI in WSL...'
        'echo.'
        'echo If Windows asks for WSL access or this fails, open hermes-agent-windows logs for details.'
        'echo.'
        "wsl.exe -u admin -e bash ""$wslShellLauncherPath"""
        'set "EXIT_CODE=%ERRORLEVEL%"'
        'echo.'
        'echo Hermes CLI session ended. Exit code: %EXIT_CODE%'
        'echo Press any key to close this window.'
        'pause >nul'
        'exit /b %EXIT_CODE%'
    )
    $launcherScript = $launcherLines -join "`r`n"
    Set-Content -Path $launcherPath -Value $launcherScript -Encoding ASCII
    $args = @('/k', "`"$launcherPath`"")

    try {
        Write-AppLog -Message "Opening interactive Hermes Agent CLI in Windows Command Prompt using $launcherPath." -Level 'INFO' | Out-Null
        Start-Process -FilePath 'cmd.exe' -ArgumentList $args -WorkingDirectory $projectRoot | Out-Null
        return Format-StatusResult -Name 'Launch Hermes CLI' -Status 'Running' -Message 'Opened the interactive Hermes Agent CLI.' -Details "Command: hermes chat --accept-hooks`nWSL user: admin`nLauncher: $launcherPath"
    }
    catch {
        return Format-StatusResult -Name 'Launch Hermes CLI' -Status 'Error' -Message 'Could not open the Hermes CLI terminal.' -Details $_.Exception.Message -ExitCode 1
    }
}

function Get-HermesGatewayStatus {
    if (-not (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Gateway' -Status 'Missing' -Message 'Hermes Agent is not installed in WSL.' -Details 'Install Hermes first.'
    }

    $status = Invoke-HermesWslCommand -Command 'hermes gateway status 2>&1 || true' -AsAdminUser -TimeoutSeconds 60
    if ($status.Status -eq 'Success' -and $status.Details -match 'Gateway is running|running') {
        $reachable = Test-WindowsGatewayReachable
        $details = if ($reachable) { "Gateway reachable from Windows at localhost:9119" } else { "Gateway running in WSL but not reachable from Windows" }
        return Format-StatusResult -Name 'Hermes Gateway' -Status 'Running' -Message 'Hermes Gateway is running.' -Details ($status.Details + "`n" + $details)
    }

    $process = Invoke-HermesWslCommand -Command "ps -eo pid=,comm=,args= | awk '`$2 !~ /^(bash|sh|awk|ps)$/ && `$0 ~ /gateway/ && `$0 ~ /hermes/ {print}'" -AsAdminUser -TimeoutSeconds 30
    if ($process.Status -eq 'Success' -and $process.Details -match 'gateway') {
        return Format-StatusResult -Name 'Hermes Gateway' -Status 'Running' -Message 'Hermes Gateway appears to be running inside WSL.' -Details $process.Details
    }

    $config = Invoke-HermesWslCommand -Command 'test -f "$HOME/.hermes/config.yaml" && grep -n "use_gateway" "$HOME/.hermes/config.yaml" || true' -AsAdminUser -TimeoutSeconds 30
    if ($config.Status -eq 'Success' -and $config.Details -match 'use_gateway') {
        return Format-StatusResult -Name 'Hermes Gateway' -Status 'Installed' -Message 'Hermes gateway setting was found in config.' -Details $config.Details
    }

    return Format-StatusResult -Name 'Hermes Gateway' -Status 'Stopped' -Message 'Hermes Gateway is not running.' -Details 'Use Enable Hermes Gateway to run hermes gateway setup/start.'
}

function Test-WindowsGatewayReachable {
    try {
        $request = [System.Net.WebRequest]::Create('http://localhost:9119/health')
        $request.Method = 'GET'
        $request.Timeout = 3000
        $response = $request.GetResponse()
        $status = [int]$response.StatusCode
        $response.Close()
        return ($status -ge 200 -and $status -lt 300)
    }
    catch {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect('127.0.0.1', 9119)
            $tcp.Close()
            return $true
        }
        catch {
            return $false
        }
    }
}

function Enable-HermesGateway {
    if (-not (Test-HermesInstalled)) {
        $install = Install-HermesAgent
        if ($install.Status -ne 'Installed') {
            return $install
        }
    }

    $current = Get-HermesGatewayStatus
    if ($current.Status -eq 'Running') {
        return Format-StatusResult -Name 'Hermes Gateway' -Status 'Running' -Message 'Hermes Gateway is already running.' -Details $current.Details
    }

    $command = @'
mkdir -p "$HOME/.hermes"
if hermes gateway --help >/dev/null 2>&1; then
  mkdir -p "$HOME/.hermes/logs"
  nohup hermes gateway run --replace --accept-hooks > "$HOME/.hermes/logs/gateway.log" 2>&1 &
  sleep 4
  hermes gateway status 2>&1 || true
else
  echo "Hermes gateway command is not available in this installed version."
  exit 1
fi
'@
    $result = Invoke-HermesWslCommand -Command $command -AsAdminUser -TimeoutSeconds 90
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Hermes Gateway' -Status 'Running' -Message 'Hermes Gateway run command was launched inside WSL.' -Details "Logs: /home/admin/.hermes/logs/gateway.log`n$($result.Details)"
    }

    return Format-StatusResult -Name 'Hermes Gateway' -Status 'Error' -Message 'Hermes Gateway did not start cleanly.' -Details $result.Details -ExitCode $result.ExitCode
}

function Open-HermesGateway {
    if (-not (Test-HermesInstalled)) {
        $install = Install-HermesAgent
        if ($install.Status -ne 'Installed') {
            return $install
        }
    }

    $command = @'
mkdir -p "$HOME/.hermes/logs"
if curl -fsS --max-time 3 http://127.0.0.1:9119 >/dev/null 2>&1; then
  echo "Dashboard already running at http://127.0.0.1:9119"
  exit 0
fi

# Stop any stale dashboard process safely (avoid pkill -f / hermes dashboard --stop,
# which match the full command line and would kill this bash process itself).
ps -eo pid=,comm=,args= | awk '$2 !~ /^(bash|sh|awk|ps)$/ && $0 ~ /hermes.*dashboard/ {print $1}' | while read pid; do
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
done
sleep 2

# Start the dashboard (auto-builds web UI if web_dist is missing)
nohup hermes dashboard --host 127.0.0.1 --port 9119 --no-open > "$HOME/.hermes/logs/dashboard.log" 2>&1 &
echo "Started dashboard (building web UI if needed — this may take 2-5 minutes)"

# Poll for readiness (up to 6 minutes)
for i in $(seq 1 72); do
  sleep 5
  if curl -fsS --max-time 3 http://127.0.0.1:9119 >/dev/null 2>&1; then
    echo "Dashboard is reachable after ${i} attempts"
    exit 0
  fi
  # Show last progress line from log
  tail -n 1 "$HOME/.hermes/logs/dashboard.log" 2>/dev/null || true
done

# Final check
if curl -fsS --max-time 5 http://127.0.0.1:9119 >/dev/null 2>&1; then
  echo "Hermes dashboard is reachable inside WSL at http://127.0.0.1:9119"
  exit 0
fi

echo "ERROR: Dashboard did not become reachable after 6 minutes. Check log: $HOME/.hermes/logs/dashboard.log"
exit 1
'@
    $dashboard = Invoke-HermesWslCommand -Command $command -AsAdminUser -TimeoutSeconds 420
    if ($dashboard.Status -ne 'Success') {
        return Format-StatusResult -Name 'Open Hermes Dashboard' -Status 'Error' -Message 'Hermes dashboard did not become reachable inside WSL.' -Details "Log: /home/admin/.hermes/logs/dashboard.log`n$($dashboard.Details)" -ExitCode $dashboard.ExitCode
    }

    $probe = Invoke-CommandSafe -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-Command', 'try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://localhost:9119; "OK $($r.StatusCode)" } catch { "ERR $($_.Exception.Message)"; exit 1 }') -LogFile (Get-LogFilePath -Kind 'app') -AllowFailure -TimeoutSeconds 15
    $url = 'http://localhost:9119'
    if ($probe.Status -ne 'Success') {
        $ipResult = Invoke-WslShell -Command "hostname -I | awk '{print `$1}'" -TimeoutSeconds 15
        if ($ipResult.Status -eq 'Success' -and $ipResult.Details) {
            $candidateUrl = "http://$($ipResult.Details.Trim()):9119"
            $probe = Invoke-CommandSafe -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-Command', "try { `$r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $candidateUrl; `"OK `$(`$r.StatusCode)`" } catch { `"ERR `$(`$_.Exception.Message)`"; exit 1 }") -LogFile (Get-LogFilePath -Kind 'app') -AllowFailure -TimeoutSeconds 15
            if ($probe.Status -eq 'Success') {
                $url = $candidateUrl
            }
        }
    }

    if ($probe.Status -ne 'Success') {
        return Format-StatusResult -Name 'Open Hermes Dashboard' -Status 'Error' -Message 'Hermes dashboard is running in WSL, but Windows cannot reach it.' -Details "Try opening http://localhost:9119 manually. Dashboard log: /home/admin/.hermes/logs/dashboard.log`n$($probe.Details)" -ExitCode $probe.ExitCode
    }

    try {
        Start-Process $url | Out-Null
        return Format-StatusResult -Name 'Open Hermes Dashboard' -Status 'Running' -Message 'Opened the Hermes web dashboard.' -Details "URL: $url`nProbe: $($probe.Message)`n$($dashboard.Details)"
    }
    catch {
        return Format-StatusResult -Name 'Open Hermes Dashboard' -Status 'Error' -Message 'Dashboard started, but Windows could not open the browser.' -Details "URL: $url`n$($_.Exception.Message)" -ExitCode 1
    }
}

function Open-HermesConfigFolder {
    $result = Invoke-HermesWslCommand -Command 'mkdir -p "$HOME/.hermes"; wslpath -w "$HOME/.hermes"' -AsAdminUser -TimeoutSeconds 30
    if ($result.Status -eq 'Success' -and $result.Details) {
        return Open-FolderSafe -Path (($result.Details -split "`r?`n" | Select-Object -First 1).Trim())
    }

    return Open-FolderSafe -Path (Join-Path (Get-ProjectRoot) 'config')
}

function Get-HermesReleaseCachePath {
    return Join-Path (Get-ProjectRoot) 'hermes-release-cache.json'
}

function Get-LatestHermesReleaseVersion {
    $cacheFile = Get-HermesReleaseCachePath
    $maxAge = [TimeSpan]::FromHours(1)

    if (Test-Path $cacheFile) {
        try {
            $cached = Get-Content -Path $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $cachedAt = [DateTime]$cached.CheckedAt
            if ((Get-Date) - $cachedAt -lt $maxAge) {
                return [pscustomobject]@{
                    Status   = 'Installed'
                    Message  = "Cached latest: $($cached.LatestVersion)"
                    Details  = "Checked at $($cached.CheckedAt)"
                    ExitCode = 0
                    Version  = $cached.LatestVersion
                }
            }
        }
        catch {
        }
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/NousResearch/hermes-agent/releases/latest' -TimeoutSec 30 -ErrorAction Stop
        $tag = $release.tag_name -replace '^v', ''

        $cacheEntry = @{
            LatestVersion = $tag
            CheckedAt     = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 3

        try {
            [System.IO.File]::WriteAllText($cacheFile, $cacheEntry, (New-Object System.Text.UTF8Encoding($false)))
        }
        catch {
        }

        return [pscustomobject]@{
            Status   = 'Installed'
            Message  = "Latest release: v$tag"
            Details  = 'Fetched from GitHub API.'
            ExitCode = 0
            Version  = $tag
        }
    }
    catch {
        return [pscustomobject]@{
            Status   = 'Error'
            Message  = 'Could not check GitHub for latest Hermes release.'
            Details  = $_.Exception.Message
            ExitCode = 1
            Version  = ''
        }
    }
}

function Get-HermesUpdateStatus {
    if (-not (Test-HermesInstalled)) {
        return Format-StatusResult -Name 'Hermes Update' -Status 'Missing' -Message 'Hermes Agent is not installed in WSL.' -Details 'Install Hermes Agent before checking for updates.'
    }

    # Compare git commits for a reliable update check. Version strings in the
    # codebase and GitHub release tags may diverge (e.g. tag = 2026.5.16,
    # hermes --version = 0.14.0), so comparing commits is the only accurate way.
    $localCommitResult = Invoke-HermesWslCommand -Command 'cd "$HOME/.hermes/hermes-agent" 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo "NO_GIT"' -AsAdminUser -TimeoutSeconds 30
    if ($localCommitResult.Status -ne 'Success' -or $localCommitResult.Details -match 'NO_GIT') {
        return Format-StatusResult -Name 'Hermes Update' -Status 'Unknown' -Message 'Cannot check for updates: no git repository found.' -Details 'Hermes may have been installed without git cloning.'
    }

    $localCommit = ($localCommitResult.Details -split "`r?`n" | Select-Object -First 1).Trim()

    $remoteCommitResult = Invoke-HermesWslCommand -Command 'cd "$HOME/.hermes/hermes-agent" 2>/dev/null && git ls-remote --heads origin main 2>/dev/null | awk ''{print $1}'' || echo "NO_REMOTE"' -AsAdminUser -TimeoutSeconds 30
    if ($remoteCommitResult.Status -ne 'Success' -or $remoteCommitResult.Details -match 'NO_REMOTE') {
        return Format-StatusResult -Name 'Hermes Update' -Status 'Unknown' -Message 'Could not reach GitHub to check for updates.' -Details 'Network may be unavailable or the git remote is misconfigured.'
    }

    $remoteCommit = ($remoteCommitResult.Details -split "`r?`n" | Select-Object -First 1).Trim()

    if ($localCommit -eq $remoteCommit) {
        $short = if ($localCommit.Length -ge 7) { $localCommit.Substring(0, 7) } else { $localCommit }
        return Format-StatusResult -Name 'Hermes Update' -Status 'Installed' -Message 'Hermes is up to date.' -Details "Commit: $short"
    }

    $shortLocal = if ($localCommit.Length -ge 7) { $localCommit.Substring(0, 7) } else { $localCommit }
    $shortRemote = if ($remoteCommit.Length -ge 7) { $remoteCommit.Substring(0, 7) } else { $remoteCommit }

    # Try to count commits behind (requires fetch, which may fail on shallow clones)
    $behindResult = Invoke-HermesWslCommand -Command 'cd "$HOME/.hermes/hermes-agent" && git fetch origin --depth=1 2>/dev/null; count=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0); echo "$count"' -AsAdminUser -TimeoutSeconds 60
    $behindCount = 0
    if ($behindResult.Status -eq 'Success') {
        $behindLine = ($behindResult.Details -split "`r?`n" | Select-Object -First 1).Trim()
        [int]::TryParse($behindLine, [ref]$behindCount) | Out-Null
    }

    $message = if ($behindCount -gt 0) { "Update available ($behindCount commits behind)" } else { 'Update available' }
    return Format-StatusResult -Name 'Hermes Update' -Status 'Needs Update' -Message $message -Details "Local: $shortLocal | Remote: $shortRemote"
}

function Get-HermesAgentWindowsUpdateInfo {
    $cacheFile = Join-Path (Get-ProjectRoot) 'version-cache.json'
    if (Test-Path $cacheFile) {
        try {
            $cached = Get-Content -Path $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($cached.LatestVersion -and $cached.CheckedAt) {
                $checkedAt = [DateTime]$cached.CheckedAt
                $age = (Get-Date) - $checkedAt
                $ageText = if ($age.TotalMinutes -lt 1) { 'just now' } elseif ($age.TotalMinutes -lt 60) { "$([math]::Round($age.TotalMinutes))m ago" } else { "$([math]::Round($age.TotalHours,1))h ago" }
                return [pscustomobject]@{
                    LatestVersion = $cached.LatestVersion
                    CheckedAt     = $cached.CheckedAt
                    AgeText       = $ageText
                }
            }
        }
        catch {
        }
    }
    return $null
}

