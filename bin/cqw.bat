@echo off
set "IV=%~1"
if "%IV%"=="" set "IV=60"
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\claude-quota\check-quota.ps1" -Watch -Interval %IV%
