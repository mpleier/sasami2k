@echo off
rem ---------------------------------------------------------------------------
rem  Remove the SASAMI2k DirectShow filter registration (machine-wide and
rem  per-user). Will ask for administrator rights when needed.
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" unregister -Machine
echo.
pause
