# iniciar-bridge.ps1
# Inicia a lc-sql-bridge manualmente.
# Pode ser executado por duplo clique, Agendador de Tarefas ou terminal.

Set-Location $PSScriptRoot

if (-not (Test-Path (Join-Path $PSScriptRoot ".env"))) {
    Write-Host "ERRO: arquivo .env nao encontrado." -ForegroundColor Red
    Write-Host "Execute instalar-bridge.ps1 primeiro." -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

if (-not (Test-Path (Join-Path $PSScriptRoot "node_modules"))) {
    Write-Host "AVISO: node_modules ausente. Instalando dependencias..." -ForegroundColor Yellow
    npm.cmd install
}

Write-Host "Iniciando lc-sql-bridge..." -ForegroundColor Cyan
node bridge.js
