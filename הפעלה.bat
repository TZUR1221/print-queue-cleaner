@echo off
rem Opens the Hebrew settings window (asks for administrator rights).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\launch.ps1"
