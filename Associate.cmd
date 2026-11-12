@echo off
rem ---------------------------------------------------------------------------
rem  Opt in to per-user file associations for the SASAMI file types.
rem  Writes only under HKCU\Software\Classes; Unassociate.cmd reverses it and
rem  restores any handler it shadowed. Extra extensions can be passed, e.g.
rem    Associate.cmd .mpg .avi
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" associate %*
echo.
pause
