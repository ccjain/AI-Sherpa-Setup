@echo off
:: AI Sherpa — Windows setup launcher
:: Requires PowerShell 5.1+ (pre-installed on Windows 10/11)
:: Usage:
::   setup.bat              — first-time setup
::   setup.bat --update     — update core skills and settings only

:: Force the console codepage to UTF-8 so the PowerShell banner (box-drawing
:: chars) renders correctly on PS 5.1 / conhost. Without this the bytes get
:: re-interpreted under the legacy OEM codepage and you see mojibake (â–ˆ).
chcp 65001 >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo [AI Sherpa] Setup failed. See error above.
    echo Press any key to close this window...
    pause > nul
    exit /b %ERRORLEVEL%
)
