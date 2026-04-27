@echo off
setlocal
title OCI Free Tier Installer

cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [FAIL] powershell.exe 를 찾을 수 없습니다.
    echo Windows 10 / 11 의 기본 PowerShell 이 필요합니다.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
exit /b %ERRORLEVEL%
