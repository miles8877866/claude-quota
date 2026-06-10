@echo off
setlocal
if "%~1"=="" ( echo Usage: cc ^<number^>   e.g.  cc 6 & exit /b 1 )
set "CCDIR=%USERPROFILE%\.claude%~1"
if not exist "%CCDIR%" mkdir "%CCDIR%"
set "CLAUDE_CONFIG_DIR=%CCDIR%"
claude