@echo off
setlocal
set "SCRIPT=%~dp0IT-SwissArmyKnife-v2.6.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command ^
  "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -STA -File ""%SCRIPT%""'"

exit /b
