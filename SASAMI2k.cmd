@echo off
rem ---------------------------------------------------------------------------
rem  SASAMI2k portable launcher
rem  Registers the DirectShow filters from THIS folder if needed, then starts
rem  the player. Settings are stored in app\SASAMI2k.ini, so the folder is
rem  self-contained and can be moved (filters are re-pointed automatically).
rem
rem  Usage:  SASAMI2k.cmd
rem          SASAMI2k.cmd "D:\movie.avi"
rem          SASAMI2k.cmd /fullscreen "D:\movie.avi"
rem ---------------------------------------------------------------------------
setlocal
set "HERE=%~dp0"
pushd "%HERE%"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%HERE%tools\portable.ps1" launch %*
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (
    echo.
    echo Launcher exited with code %RC%.
    pause
)
exit /b %RC%
