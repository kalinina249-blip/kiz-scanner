@echo off
title CHZ helper - ne zakryvat
echo Skachivayu svezhuyu versiyu pomoshchnika...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=3072; try { Invoke-WebRequest 'https://kalinina249-blip.github.io/kiz-scanner/cz-helper.ps1?v=%RANDOM%' -OutFile \"$env:TEMP\cz-helper.ps1\" -UseBasicParsing -TimeoutSec 30 } catch { Write-Host 'Ne udalos skachat (net interneta?)' -ForegroundColor Red }"
if exist "%TEMP%\cz-helper.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\cz-helper.ps1"
) else if exist "%~dp0cz-helper.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cz-helper.ps1"
) else (
  echo.
  echo OSHIBKA: ne udalos poluchit cz-helper.ps1. Proverte internet i zapustite snova.
)
pause
