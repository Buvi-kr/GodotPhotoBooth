@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-FromBundle.ps1"
exit /b %ERRORLEVEL%
