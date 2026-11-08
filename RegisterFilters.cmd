@echo off
rem ---------------------------------------------------------------------------
rem  Register the three SASAMI2k DirectShow filters for all users.
rem  Runs the bundled 32-bit regsvr32.exe and will ask for administrator rights.
rem  Only needed once per folder location; SASAMI2k.cmd does it automatically.
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" register -Machine
echo.
pause
