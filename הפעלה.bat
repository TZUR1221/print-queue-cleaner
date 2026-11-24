@echo off
rem Opens the Hebrew settings window with administrator rights.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ui='%~dp0src\settings-ui.ps1'; $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if ($admin) { & $ui } else { Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$ui) }"
