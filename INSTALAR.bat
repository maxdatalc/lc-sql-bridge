@echo off
chcp 65001 > nul
title LC Gestor - Bridge SQL

:: ── Se nao e admin, relanca este mesmo .bat como admin ──────────────────────
net session > nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  Solicitando permissao de Administrador...
    echo  Uma janela de confirmacao vai aparecer. Clique em "Sim".
    echo.
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
    exit /b
)

:: ── Ja e admin: executa o instalador ────────────────────────────────────────
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"

:: ── Mantem janela aberta mesmo se o script falhar ────────────────────────────
echo.
pause
