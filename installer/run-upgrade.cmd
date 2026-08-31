@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Mode upgrade
exit /b %errorlevel%
