@echo off
setlocal

title hermes-agent-windows

set "SCRIPT_DIR=%~dp0"
set "LAUNCH_SCRIPT=%SCRIPT_DIR%hermes-agent-windows.ps1"
set "SELF_PATH=%~f0"

echo.
echo ========================================================
echo hermes-agent-windows
echo Smart Windows Setup Tool for Hermes Agent
echo ========================================================
echo.

if not exist "%LAUNCH_SCRIPT%" (
    echo ERROR: hermes-agent-windows.ps1 was not found.
    echo Expected: "%LAUNCH_SCRIPT%"
    echo.
    echo Make sure you extracted the full hermes-agent-windows folder before running this file.
    echo.
    pause
    exit /b 1
)

net session >nul 2>nul
if not "%ERRORLEVEL%"=="0" (
    echo Requesting Administrator permission...
    echo If Windows asks for permission, choose Yes.
    echo.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', '\"%SELF_PATH%\"' -WorkingDirectory '%SCRIPT_DIR%' -Verb RunAs"
    if errorlevel 1 (
        echo.
        echo ERROR: Could not request Administrator permission.
        echo Right-click this file and choose "Run as administrator".
        echo.
        pause
        exit /b 1
    )
    exit /b 0
)

where pwsh.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "PS_EXE=pwsh.exe"
    set "PS_ARGS=-NoProfile -ExecutionPolicy Bypass"
) else (
    set "PS_EXE=powershell.exe"
    set "PS_ARGS=-NoProfile -STA -ExecutionPolicy Bypass"
)

echo Launching hermes-agent-windows with %PS_EXE%...
echo.

%PS_EXE% %PS_ARGS% -File "%LAUNCH_SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo hermes-agent-windows exited with code %EXIT_CODE%.
    echo If the GUI did not open, try right-clicking this file and choosing "Run as administrator".
    echo.
    pause
)

exit /b %EXIT_CODE%

