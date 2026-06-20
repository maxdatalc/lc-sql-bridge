# iniciar-bridge.ps1
# Inicia ou reinicia a bridge via servico Windows.
# Use apenas para manutencao manual — em operacao normal o servico sobe automaticamente.

#Requires -Version 5.1
Set-StrictMode -Off

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else {
    Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
Set-Location $ScriptDir

$SvcName = 'LCGestorSQLBridge'

if (-not (Test-Path (Join-Path $ScriptDir ".env"))) {
    Write-Host "ERRO: arquivo .env nao encontrado." -ForegroundColor Red
    Write-Host "Execute LCBRIDGE-INSTALL.exe primeiro." -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq 'Running') {
        Write-Host "Bridge ja esta em execucao. Reiniciando..." -ForegroundColor Yellow
        Restart-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Iniciando servico '$SvcName'..." -NoNewline
        Start-Service -Name $SvcName -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    $svc.Refresh()
    if ($svc.Status -eq 'Running') {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FALHOU" -ForegroundColor Red
        Write-Host "Verifique o log em logs\bridge.log" -ForegroundColor Yellow
    }
} else {
    Write-Host "Servico '$SvcName' nao encontrado." -ForegroundColor Yellow
    Write-Host "Execute LCBRIDGE-INSTALL.exe para instalar o servico." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Pressione Enter para sair"
