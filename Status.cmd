@echo off
rem ---------------------------------------------------------------------------
rem  Show whether the filters are registered and whether they point at this
rem  folder (useful after moving the directory). Pass "verify" to check every
rem  shipped file against HASHES.txt instead.
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
set "ACTION=status"
if not "%~1"=="" set "ACTION=%~1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" %ACTION%
echo.
pause
