# iniciar-bridge.ps1
# Inicia a lc-sql-bridge manualmente.

#Requires -Version 5.1
Set-StrictMode -Off

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
Set-Location $ScriptDir

if (-not (Test-Path (Join-Path $ScriptDir ".env"))) {
    Write-Host "ERRO: arquivo .env nao encontrado." -ForegroundColor Red
    Write-Host "Execute LCBRIDGE-INSTALL.exe primeiro." -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

if (-not (Test-Path (Join-Path $ScriptDir "node_modules"))) {
    Write-Host "AVISO: node_modules ausente. Instalando dependencias..." -ForegroundColor Yellow
    npm.cmd install
}

Write-Host "Iniciando lc-sql-bridge..." -ForegroundColor Cyan
node bridge.js
