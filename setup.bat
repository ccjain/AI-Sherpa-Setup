@echo off
:: AI Sherpa — Windows setup launcher
:: Requires PowerShell 5.1+ (pre-installed on Windows 10/11)
:: Usage:
::   setup.bat              — first-time setup
::   setup.bat --update     — update core skills and settings only

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo [AI Sherpa] Setup failed. See error above.
    echo Press any key to close this window...
    pause > nul
    exit /b %ERRORLEVEL%
)
