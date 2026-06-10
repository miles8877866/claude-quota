@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\claude-quota\check-quota.ps1" %*
