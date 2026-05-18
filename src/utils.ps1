function Get-ProjectRoot {
    if ($global:HermesAgentWindowsRoot -and (Test-Path $global:HermesAgentWindowsRoot)) {
        return $global:HermesAgentWindowsRoot
    }

    if ($PSScriptRoot) {
        $parent = Split-Path -Parent $PSScriptRoot
        if ($parent) {
            return $parent
        }
    }

    $fallback = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'hermes-agent-windows'
    return $fallback
}

function Get-LogFilePath {
    param(
        [ValidateSet('install', 'app')]
        [string]$Kind = 'app'
    )

    if ($Kind -eq 'install') {
        return (Join-Path (Get-ProjectRoot) 'logs\install.log')
    }

    return (Join-Path (Get-ProjectRoot) 'logs\app.log')
}

function Get-ActiveLogFile {
    if ($global:HermesAgentWindowsLogPath) {
        return $global:HermesAgentWindowsLogPath
    }

    return (Get-LogFilePath -Kind 'app')
}

function ConvertTo-GuiSafeText {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return ''
        }

        $text = if ($InputObject -is [string]) {
            $InputObject
        }
        else {
            try {
                $InputObject | Out-String
            }
            catch {
                [string]$InputObject
            }
        }

        $text = $text -replace '\u0000', ''
        $text = $text -replace '[\u0001-\u0008\u000B\u000C\u000E-\u001F]', ''
        return $text.TrimEnd()
    }
}

function Format-StatusResult {
    param(
        [string]$Name,
        [ValidateSet('Installed', 'Missing', 'Running', 'Stopped', 'Needs Update', 'Error', 'Unknown', 'NeedsReboot')]
        [string]$Status = 'Unknown',
        [string]$Message = '',
        [string]$Details = '',
        [int]$ExitCode = 0
    )

    [pscustomobject]@{
        Name      = $Name
        Status    = $Status
        Message   = $Message
        Details   = $Details
        ExitCode  = $ExitCode
        Timestamp = Get-Date
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',
        [string]$LogFile = (Get-ActiveLogFile)
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$timestamp][$Level] $Message"
    $safeLine = ConvertTo-GuiSafeText $line

    switch ($Level) {
        'SUCCESS' { Write-Host $safeLine -ForegroundColor Green }
        'WARN'    { Write-Host $safeLine -ForegroundColor Yellow }
        'ERROR'   { Write-Host $safeLine -ForegroundColor Red }
        'DEBUG'   { Write-Host $safeLine -ForegroundColor DarkGray }
        default   { Write-Host $safeLine }
    }

    try {
        $logDir = Split-Path -Parent $LogFile
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        Add-Content -Path $LogFile -Value $safeLine -Encoding UTF8
    }
    catch {
        Write-Host "[$timestamp][ERROR] Failed to write log file: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $safeLine
}

function Write-AppLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    return Write-Log -Message $Message -Level $Level -LogFile (Get-LogFilePath -Kind 'app')
}

function New-ProjectFolder {
    param(
        [string]$RootPath = (Get-ProjectRoot)
    )

    $paths = @(
        $RootPath,
        (Join-Path $RootPath 'src'),
        (Join-Path $RootPath 'docs'),
        (Join-Path $RootPath 'logs')
    )

    foreach ($path in $paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $installLog = Join-Path $RootPath 'logs\install.log'
    $appLog = Join-Path $RootPath 'logs\app.log'
    foreach ($file in @($installLog, $appLog)) {
        if (-not (Test-Path $file)) {
            New-Item -ItemType File -Path $file -Force | Out-Null
        }
    }

    [pscustomobject]@{
        RootPath   = $RootPath
        Created    = $true
        Paths      = $paths
        LogFiles   = @($installLog, $appLog)
    }
}

function Open-FolderSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }

        Start-Process explorer.exe -ArgumentList "`"$Path`""
        return Format-StatusResult -Name 'Open Folder' -Status 'Installed' -Message "Opened $Path"
    }
    catch {
        return Format-StatusResult -Name 'Open Folder' -Status 'Error' -Message 'Failed to open folder.' -Details $_.Exception.Message -ExitCode 1
    }
}

function Invoke-CommandSafe {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [string]$LogFile = (Get-ActiveLogFile),
        [switch]$AllowFailure,
        [int]$TimeoutSeconds = 0
    )

    $commandLabel = if ($Arguments.Count -gt 0) {
        "$FilePath $($Arguments -join ' ')"
    }
    else {
        $FilePath
    }

    Write-Log -Message "Running command: $commandLabel" -Level 'INFO' -LogFile $LogFile | Out-Null

    try {
        if ($TimeoutSeconds -gt 0) {
            $quoteArgument = {
                param([string]$Value)
                if ($null -eq $Value) { return '""' }
                if ($Value -match '[\s"`|&<>]') {
                    return '"' + ($Value -replace '"', '\"') + '"'
                }
                return $Value
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $FilePath
            $psi.Arguments = (($Arguments | ForEach-Object { & $quoteArgument $_ }) -join ' ')
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            if ($WorkingDirectory) {
                $psi.WorkingDirectory = $WorkingDirectory
            }

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi

            $stdoutBuilder = New-Object System.Text.StringBuilder
            $stderrBuilder = New-Object System.Text.StringBuilder

            $process.add_OutputDataReceived({
                if ($EventArgs.Data -ne $null) {
                    [void]$stdoutBuilder.AppendLine($EventArgs.Data)
                }
            })
            $process.add_ErrorDataReceived({
                if ($EventArgs.Data -ne $null) {
                    [void]$stderrBuilder.AppendLine($EventArgs.Data)
                }
            })

            [void]$process.Start()
            $process.BeginOutputReadLine()
            $process.BeginErrorReadLine()

            $completed = $process.WaitForExit($TimeoutSeconds * 1000)

            if (-not $completed) {
                try {
                    $process.Kill()
                }
                catch {
                }

                # Give async handlers a moment to flush whatever they already received
                Start-Sleep -Milliseconds 300

                $partialOutput = ConvertTo-GuiSafeText (($stdoutBuilder.ToString(), $stderrBuilder.ToString() | Where-Object { $_ }) -join [Environment]::NewLine)
                $message = "Command timed out after $TimeoutSeconds seconds."
                Write-Log -Message "$commandLabel => $message" -Level 'ERROR' -LogFile $LogFile | Out-Null
                return [pscustomobject]@{
                    Status   = 'Error'
                    Message  = $message
                    Details  = if ($partialOutput) { "$message`nPartial output:`n$partialOutput" } else { $message }
                    ExitCode = 124
                    Output   = $partialOutput
                }
            }

            # Brief wait so any trailing async events can flush
            Start-Sleep -Milliseconds 300

            $stdout = $stdoutBuilder.ToString()
            $stderr = $stderrBuilder.ToString()
            $exitCode = $process.ExitCode
            $textOutput = ConvertTo-GuiSafeText (($stdout, $stderr | Where-Object { $_ }) -join [Environment]::NewLine)

            if ($textOutput) {
                foreach ($line in ($textOutput -split "`r?`n")) {
                    if ($line.Trim()) {
                        Write-Log -Message "$commandLabel => $line" -Level 'DEBUG' -LogFile $LogFile | Out-Null
                    }
                }
            }

            if ($exitCode -eq 0) {
                return [pscustomobject]@{
                    Status   = 'Success'
                    Message  = 'Command completed successfully.'
                    Details  = $textOutput
                    ExitCode = $exitCode
                    Output   = $textOutput
                }
            }

            return [pscustomobject]@{
                Status   = 'Error'
                Message  = 'Command returned a non-zero exit code.'
                Details  = $textOutput
                ExitCode = $exitCode
                Output   = $textOutput
            }
        }

        $previousLocation = $null
        if ($WorkingDirectory) {
            $previousLocation = Get-Location
            Set-Location $WorkingDirectory
        }

        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }

        if ($previousLocation) {
            Set-Location $previousLocation
        }

        $textOutput = ConvertTo-GuiSafeText $output
        if ($textOutput) {
            foreach ($line in ($textOutput -split "`r?`n")) {
                if ($line.Trim()) {
                    Write-Log -Message "$commandLabel => $line" -Level 'DEBUG' -LogFile $LogFile | Out-Null
                }
            }
        }

        if ($exitCode -eq 0) {
            return [pscustomobject]@{
                Status   = 'Success'
                Message  = 'Command completed successfully.'
                Details  = $textOutput
                ExitCode = $exitCode
                Output   = $output
            }
        }

        $result = [pscustomobject]@{
            Status   = 'Error'
            Message  = 'Command returned a non-zero exit code.'
            Details  = $textOutput
            ExitCode = $exitCode
            Output   = $output
        }

        if ($AllowFailure) {
            return $result
        }

        return $result
    }
    catch {
        if ($previousLocation) {
            Set-Location $previousLocation
        }

        $message = $_.Exception.Message
        Write-Log -Message "Command failed: $commandLabel :: $message" -Level 'ERROR' -LogFile $LogFile | Out-Null
        return [pscustomobject]@{
            Status   = 'Error'
            Message  = 'Command failed.'
            Details  = $message
            ExitCode = 1
            Output   = $null
        }
    }
}

function Show-ErrorMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = 'hermes-agent-windows'
    )

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop | Out-Null
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
    }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
            [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
        }
        catch {
            Write-Host "${Title}: $Message" -ForegroundColor Red
        }
    }
}

function Show-InfoMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = 'hermes-agent-windows'
    )

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop | Out-Null
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
    }
    catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
            [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
        }
        catch {
            Write-Host "${Title}: $Message"
        }
    }
}

