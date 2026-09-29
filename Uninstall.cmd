@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SeekerbotRadar\Setup.ps1" -Uninstall
echo.
pause
