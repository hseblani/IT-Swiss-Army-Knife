@echo off
setlocal
set "SCRIPT=%~dp0ModulesManager.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command ^
  "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -File ""%SCRIPT%""'"

exit /b
