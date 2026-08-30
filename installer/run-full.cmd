@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" -Mode full
if errorlevel 1 pause

