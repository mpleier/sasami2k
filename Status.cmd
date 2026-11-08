@echo off
rem ---------------------------------------------------------------------------
rem  Show whether the filters are registered and whether they point at this
rem  folder (useful after moving the directory).
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" status
echo.
pause
