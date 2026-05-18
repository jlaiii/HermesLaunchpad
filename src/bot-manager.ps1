if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'utils.ps1')
}
if (-not (Get-Command Test-CommandExists -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'checks.ps1')
}
if (-not (Get-Command Invoke-WslShell -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'wsl-manager.ps1')
}
if (-not (Get-Command ConvertTo-WslWindowsPath -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'ollama-manager.ps1')
}

function Invoke-WslAdminShell {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [int]$TimeoutSeconds = 120
    )
    return Invoke-WslCommand -Arguments @('-u', 'admin', '-e', 'bash', '-lc', $Command) -LogFile (Get-LogFilePath -Kind 'app') -TimeoutSeconds $TimeoutSeconds
}

function Set-TelegramBotConfig {
    param(
        [Parameter(Mandatory)]
        [string]$BotToken,
        [Parameter(Mandatory)]
        [string]$ChatId
    )

    if ([string]::IsNullOrWhiteSpace($BotToken)) {
        return Format-StatusResult -Name 'Telegram Bot Config' -Status 'Error' -Message 'Telegram bot token is empty.' -Details 'Paste a bot token from @BotFather before saving.' -ExitCode 1
    }
    if ([string]::IsNullOrWhiteSpace($ChatId)) {
        return Format-StatusResult -Name 'Telegram Bot Config' -Status 'Error' -Message 'Telegram chat ID is empty.' -Details 'Enter the chat or user ID where the bot should operate.' -ExitCode 1
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-agent-windows-telegram-{0}.env" -f ([guid]::NewGuid().ToString('N')))
    try {
        $content = @(
            '# Created by hermes-agent-windows. Do not commit this file.'
            "export TELEGRAM_BOT_TOKEN='$($BotToken.Replace("'", "'\''"))'"
            "export TELEGRAM_CHAT_ID='$($ChatId.Replace("'", "'\''"))'"
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding ASCII -Force
        $source = ConvertTo-WslWindowsPath -Path $tempFile
        $result = Invoke-WslAdminShell -Command "set -e; mkdir -p `"`$HOME`" `"`$HOME/.hermes`"; cp '$source' `"`$HOME/.telegram-bot.env`"; chmod 600 `"`$HOME/.telegram-bot.env`"; . `"`$HOME/.telegram-bot.env`"; env_file=`"`$HOME/.hermes/.env`"; touch `"`$env_file`"; tmp=`"`$(mktemp)`"; grep -v -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID)=' `"`$env_file`" > `"`$tmp`" || true; cat `"`$tmp`" > `"`$env_file`"; printf 'TELEGRAM_BOT_TOKEN=%s\n' `"`$TELEGRAM_BOT_TOKEN`" >> `"`$env_file`"; printf 'TELEGRAM_CHAT_ID=%s\n' `"`$TELEGRAM_CHAT_ID`" >> `"`$env_file`"; chmod 600 `"`$env_file`"; rm -f `"`$tmp`"; echo 'Telegram bot config saved'" -TimeoutSeconds 60
        if ($result.Status -eq 'Success') {
            return Format-StatusResult -Name 'Telegram Bot Config' -Status 'Installed' -Message 'Telegram bot token and chat ID were saved in WSL.' -Details "Chat ID: $ChatId`nFile: /home/admin/.telegram-bot.env"
        }
        return Format-StatusResult -Name 'Telegram Bot Config' -Status 'Error' -Message 'Failed to save Telegram bot config in WSL.' -Details $result.Details -ExitCode $result.ExitCode
    }
    catch {
        return Format-StatusResult -Name 'Telegram Bot Config' -Status 'Error' -Message 'Failed to save Telegram bot config.' -Details $_.Exception.Message -ExitCode 1
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Set-DiscordBotConfig {
    param(
        [Parameter(Mandatory)]
        [string]$BotToken,
        [Parameter(Mandatory)]
        [string]$ChannelId
    )

    if ([string]::IsNullOrWhiteSpace($BotToken)) {
        return Format-StatusResult -Name 'Discord Bot Config' -Status 'Error' -Message 'Discord bot token is empty.' -Details 'Paste a bot token from the Discord Developer Portal before saving.' -ExitCode 1
    }
    if ([string]::IsNullOrWhiteSpace($ChannelId)) {
        return Format-StatusResult -Name 'Discord Bot Config' -Status 'Error' -Message 'Discord channel ID is empty.' -Details 'Enter the channel ID where the bot should operate.' -ExitCode 1
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-agent-windows-discord-{0}.env" -f ([guid]::NewGuid().ToString('N')))
    try {
        $content = @(
            '# Created by hermes-agent-windows. Do not commit this file.'
            "export DISCORD_BOT_TOKEN='$($BotToken.Replace("'", "'\''"))'"
            "export DISCORD_CHANNEL_ID='$($ChannelId.Replace("'", "'\''"))'"
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding ASCII -Force
        $source = ConvertTo-WslWindowsPath -Path $tempFile
        $result = Invoke-WslAdminShell -Command "set -e; mkdir -p `"`$HOME`" `"`$HOME/.hermes`"; cp '$source' `"`$HOME/.discord-bot.env`"; chmod 600 `"`$HOME/.discord-bot.env`"; . `"`$HOME/.discord-bot.env`"; env_file=`"`$HOME/.hermes/.env`"; touch `"`$env_file`"; tmp=`"`$(mktemp)`"; grep -v -E '^(DISCORD_BOT_TOKEN|DISCORD_CHANNEL_ID)=' `"`$env_file`" > `"`$tmp`" || true; cat `"`$tmp`" > `"`$env_file`"; printf 'DISCORD_BOT_TOKEN=%s\n' `"`$DISCORD_BOT_TOKEN`" >> `"`$env_file`"; printf 'DISCORD_CHANNEL_ID=%s\n' `"`$DISCORD_CHANNEL_ID`" >> `"`$env_file`"; chmod 600 `"`$env_file`"; rm -f `"`$tmp`"; echo 'Discord bot config saved'" -TimeoutSeconds 60
        if ($result.Status -eq 'Success') {
            return Format-StatusResult -Name 'Discord Bot Config' -Status 'Installed' -Message 'Discord bot token and channel ID were saved in WSL.' -Details "Channel ID: $ChannelId`nFile: /home/admin/.discord-bot.env"
        }
        return Format-StatusResult -Name 'Discord Bot Config' -Status 'Error' -Message 'Failed to save Discord bot config in WSL.' -Details $result.Details -ExitCode $result.ExitCode
    }
    catch {
        return Format-StatusResult -Name 'Discord Bot Config' -Status 'Error' -Message 'Failed to save Discord bot config.' -Details $_.Exception.Message -ExitCode 1
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-TelegramBotConfig {
    $result = Invoke-WslAdminShell -Command 'if [ -f "$HOME/.telegram-bot.env" ]; then . "$HOME/.telegram-bot.env"; printf "Token: %s\nChat: %s\n" "$(if [ -n "$TELEGRAM_BOT_TOKEN" ]; then echo saved; else echo missing; fi)" "${TELEGRAM_CHAT_ID:-not set}"; else echo "Token: missing"; echo "Chat: not set"; fi' -TimeoutSeconds 30
    if ($result.Status -eq 'Success') {
        $status = if ($result.Details -match 'Token:\s+saved') { 'Installed' } else { 'Missing' }
        return Format-StatusResult -Name 'Telegram Bot Config' -Status $status -Message 'Telegram bot config checked.' -Details $result.Details
    }
    return Format-StatusResult -Name 'Telegram Bot Config' -Status 'Unknown' -Message 'Could not check Telegram bot config.' -Details $result.Details -ExitCode $result.ExitCode
}

function Get-DiscordBotConfig {
    $result = Invoke-WslAdminShell -Command 'if [ -f "$HOME/.discord-bot.env" ]; then . "$HOME/.discord-bot.env"; printf "Token: %s\nChannel: %s\n" "$(if [ -n "$DISCORD_BOT_TOKEN" ]; then echo saved; else echo missing; fi)" "${DISCORD_CHANNEL_ID:-not set}"; else echo "Token: missing"; echo "Channel: not set"; fi' -TimeoutSeconds 30
    if ($result.Status -eq 'Success') {
        $status = if ($result.Details -match 'Token:\s+saved') { 'Installed' } else { 'Missing' }
        return Format-StatusResult -Name 'Discord Bot Config' -Status $status -Message 'Discord bot config checked.' -Details $result.Details
    }
    return Format-StatusResult -Name 'Discord Bot Config' -Status 'Unknown' -Message 'Could not check Discord bot config.' -Details $result.Details -ExitCode $result.ExitCode
}

function Test-TelegramBotApi {
    param([string]$BotToken = '')
    if ([string]::IsNullOrWhiteSpace($BotToken)) {
        $result = Invoke-WslAdminShell -Command 'if [ -f "$HOME/.telegram-bot.env" ]; then . "$HOME/.telegram-bot.env"; fi; test -n "$TELEGRAM_BOT_TOKEN" || { echo "TELEGRAM_BOT_TOKEN is missing"; exit 2; }; curl -4 -fsS --max-time 30 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | head -c 800' -TimeoutSeconds 60
    } else {
        $safeToken = $BotToken.Replace("'", "'\''")
        $result = Invoke-WslAdminShell -Command "curl -4 -fsS --max-time 30 'https://api.telegram.org/bot$safeToken/getMe' | head -c 800" -TimeoutSeconds 60
    }
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Telegram Bot Test' -Status 'Installed' -Message 'Telegram API test succeeded. Bot token is valid.' -Details $result.Details
    }
    return Format-StatusResult -Name 'Telegram Bot Test' -Status 'Error' -Message 'Telegram API test failed.' -Details $result.Details -ExitCode $result.ExitCode
}

function Test-DiscordBotApi {
    param([string]$BotToken = '')
    if ([string]::IsNullOrWhiteSpace($BotToken)) {
        $result = Invoke-WslAdminShell -Command 'if [ -f "$HOME/.discord-bot.env" ]; then . "$HOME/.discord-bot.env"; fi; test -n "$DISCORD_BOT_TOKEN" || { echo "DISCORD_BOT_TOKEN is missing"; exit 2; }; curl -4 -fsS --max-time 30 -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" https://discord.com/api/v10/users/@me | head -c 800' -TimeoutSeconds 60
    } else {
        $safeToken = $BotToken.Replace("'", "'\''")
        $result = Invoke-WslAdminShell -Command "curl -4 -fsS --max-time 30 -H 'Authorization: Bot $safeToken' https://discord.com/api/v10/users/@me | head -c 800" -TimeoutSeconds 60
    }
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Discord Bot Test' -Status 'Installed' -Message 'Discord API test succeeded. Bot token is valid.' -Details $result.Details
    }
    return Format-StatusResult -Name 'Discord Bot Test' -Status 'Error' -Message 'Discord API test failed.' -Details $result.Details -ExitCode $result.ExitCode
}

function Install-BotDependencies {
    $logFile = Get-LogFilePath -Kind 'app'
    $result = Invoke-WslAdminShell -Command 'export PATH="$HOME/.local/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"; venv_pip="$HOME/.hermes/hermes-agent/venv/bin/pip"; if [ -x "$venv_pip" ]; then "$venv_pip" install python-telegram-bot discord.py 2>&1; else pip3 install python-telegram-bot discord.py 2>&1; fi' -TimeoutSeconds 300
    if ($result.Status -eq 'Success') {
        return Format-StatusResult -Name 'Bot Dependencies' -Status 'Installed' -Message 'python-telegram-bot and discord.py were installed in the Hermes venv.' -Details $result.Details
    }
    return Format-StatusResult -Name 'Bot Dependencies' -Status 'Error' -Message 'Failed to install bot dependencies in WSL.' -Details $result.Details -ExitCode $result.ExitCode
}
