@echo off
echo Monitoring C:\Windows11UpgradeLog.txt
set "LOG=C:\Windows11UpgradeLog.txt"

powershell -NoLogo -NoProfile -Command "Get-Content '%LOG%' -Wait | ForEach-Object { if ($_ -match '\[ERROR\]') { Write-Host $_ -ForegroundColor Red } elseif ($_ -match '\[WARN\]') { Write-Host $_ -ForegroundColor Yellow } elseif ($_ -match '\[VERBOSE\]') { Write-Host $_ -ForegroundColor Cyan } else { Write-Host $_ } }"
