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

function Get-CallerName {
    $callStack = Get-PSCallStack
    if ($callStack.Count -ge 3) {
        $caller = $callStack[2]
        if ($caller.FunctionName -and $caller.FunctionName -ne '<ScriptBlock>') {
            return $caller.FunctionName
        }
    }
    return 'script'
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
        [string]$LogFile = (Get-ActiveLogFile),
        [string]$Caller = (Get-CallerName)
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $prefix = if ($Caller -and $Caller -ne 'Write-Log') { "[$Caller] " } else { '' }
    $line = "[$timestamp][$Level] $prefix$Message"
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

function Write-ErrorLog {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Context = '',
        [string]$LogFile = (Get-ActiveLogFile)
    )

    $caller = Get-CallerName
    $ex = $ErrorRecord.Exception
    $scriptName = $ErrorRecord.InvocationInfo.ScriptName
    $lineNumber = $ErrorRecord.InvocationInfo.ScriptLineNumber
    $offset = $ErrorRecord.InvocationInfo.OffsetInLine

    $contextSuffix = if ($Context) { " | Context: $Context" } else { '' }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Exception in $caller$contextSuffix")
    $lines.Add("  Type: $($ex.GetType().FullName)")
    $lines.Add("  Message: $($ex.Message)")
    $lines.Add("  Location: ${scriptName}:${lineNumber}:${offset}")

    if ($ex.StackTrace) {
        $trimmedStack = ($ex.StackTrace -split "`r?`n" | Select-Object -First 5) -join "`n  "
        $lines.Add("  StackTrace: $trimmedStack")
    }

    if ($ex.InnerException) {
        $lines.Add("  InnerException: $($ex.InnerException.Message)")
    }

    $fullMessage = $lines -join "`n"
    Write-Log -Message $fullMessage -Level 'ERROR' -LogFile $LogFile -Caller $caller | Out-Null
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

            $stdoutFile = [System.IO.Path]::GetTempFileName()
            $stderrFile = [System.IO.Path]::GetTempFileName()

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
            [void]$process.Start()

            # Read streams asynchronously in background threads to avoid deadlock
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()

            $completed = $process.WaitForExit($TimeoutSeconds * 1000)

            if (-not $completed) {
                try { $process.Kill() } catch { }
                try { $stdoutTask.Wait(500) } catch { }
                try { $stderrTask.Wait(500) } catch { }

                $partialOutput = ConvertTo-GuiSafeText ((try { $stdoutTask.Result } catch { '' }), (try { $stderrTask.Result } catch { '' }) | Where-Object { $_ }) -join [Environment]::NewLine
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

            # Wait for async reads to finish (they usually complete quickly after process exits)
            try { $stdoutTask.Wait(2000) } catch { }
            try { $stderrTask.Wait(2000) } catch { }

            $stdout = try { $stdoutTask.Result } catch { '' }
            $stderr = try { $stderrTask.Result } catch { '' }
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

            Write-Log -Message "Command exited with code $exitCode`: $commandLabel`nOutput: $textOutput" -Level 'WARN' -LogFile $LogFile | Out-Null
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

        Write-Log -Message "Command exited with code $exitCode`: $commandLabel`nOutput: $textOutput" -Level 'WARN' -LogFile $LogFile | Out-Null
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

        Write-ErrorLog -ErrorRecord $_ -Context "Command: $commandLabel" -LogFile $LogFile
        return [pscustomobject]@{
            Status   = 'Error'
            Message  = 'Command failed.'
            Details  = $_.Exception.Message
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

