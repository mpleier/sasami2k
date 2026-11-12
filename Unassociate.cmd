@echo off
rem ---------------------------------------------------------------------------
rem  Remove the per-user file associations added by Associate.cmd and restore
rem  the handlers they replaced.
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" unassociate %*
echo.
pause
