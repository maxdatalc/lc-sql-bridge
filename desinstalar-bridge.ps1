# desinstalar-bridge.ps1
# Remove o servico Windows e os arquivos gerados pela instalacao.
# Nao remove bridge.js, package.json nem o Node.js.

#Requires -Version 5.1
Set-StrictMode -Off

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else {
    Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
Set-Location $ScriptDir

$SvcName = 'LCGestorSQLBridge'

# Auto-elevacao: relanca como admin se necessario
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    $script = $MyInvocation.MyCommand.Path
    if (-not $script) { $script = Join-Path $ScriptDir "desinstalar-bridge.ps1" }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs -Wait
    exit
}

Write-Host ""
Write-Host "LC Gestor - Desinstalacao da Bridge SQL" -ForegroundColor Cyan
Write-Host ""

# 1. Encerrar monitor de bandeja (bridge-monitor.ps1) se estiver rodando
try {
    $monitores = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -match 'bridge-monitor\.ps1' }
    if ($monitores) {
        Write-Host "Encerrando monitor de bandeja..." -NoNewline
        $monitores | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Write-Host " OK" -ForegroundColor Green
    }
} catch {}

# Remove entrada de auto-inicio do monitor (HKCU Run)
Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
    -Name 'LCGestorBridgeMonitor' -ErrorAction SilentlyContinue

# 2. Parar e remover o servico Windows
$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Parando servico '$SvcName'..." -NoNewline
    sc.exe stop $SvcName 2>&1 | Out-Null
    Start-Sleep -Milliseconds 2000
    Write-Host " OK" -ForegroundColor Green

    Write-Host "Removendo servico '$SvcName'..." -NoNewline
    sc.exe delete $SvcName 2>&1 | Out-Null
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host "Servico '$SvcName' nao encontrado (ja removido ou nunca instalado)." -ForegroundColor Gray
}

# Remove entradas legadas (Task Scheduler e HKLM Run de versoes anteriores)
schtasks.exe /delete /f /tn 'LC Gestor SQL Bridge' 2>$null | Out-Null
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
    -Name 'LCGestorSQLBridge' -ErrorAction SilentlyContinue

# 3. Remover arquivos gerados pela instalacao
Write-Host ""
Write-Host "Removendo arquivos de instalacao..." -ForegroundColor Cyan
$removed = @()
@(
    'bridge-svc.exe',
    'bridge-monitor.ps1',
    '.env',
    'criar-usuario.sql',
    'configuracao-cliente.txt',
    'install-log.txt'
) | ForEach-Object {
    $p = Join-Path $ScriptDir $_
    if (Test-Path $p) {
        try { Remove-Item $p -Force; $removed += $_; Write-Host "   Removido: $_" -ForegroundColor Green }
        catch { Write-Host "   Falha ao remover $_`: $_" -ForegroundColor Yellow }
    }
}

# 4. Remover runtime\ (node.exe portavel copiado pela instalacao)
$runtimeDir = Join-Path $ScriptDir 'runtime'
if (Test-Path $runtimeDir) {
    Write-Host "   Removendo runtime\ (node.exe portavel)..." -NoNewline
    try { Remove-Item $runtimeDir -Recurse -Force; Write-Host " OK" -ForegroundColor Green }
    catch { Write-Host " FALHOU: $_" -ForegroundColor Yellow }
}

# 5. Perguntar sobre logs
$logsDir = Join-Path $ScriptDir 'logs'
if (Test-Path $logsDir) {
    $n = (Get-ChildItem $logsDir -File -ErrorAction SilentlyContinue).Count
    Write-Host ""
    $r = Read-Host "Apagar pasta de logs ($n arquivo(s))? [S/N] (padrao: N)"
    if ($r -match '^[Ss]') {
        try { Remove-Item $logsDir -Recurse -Force; Write-Host "   Logs removidos." -ForegroundColor Green }
        catch { Write-Host "   Falha ao remover logs: $_" -ForegroundColor Yellow }
    } else {
        Write-Host "   Logs mantidos." -ForegroundColor Gray
    }
}

# 6. Perguntar sobre node_modules
$nmDir = Join-Path $ScriptDir 'node_modules'
if (Test-Path $nmDir) {
    Write-Host ""
    $r = Read-Host "Apagar node_modules/ (dependencias instaladas)? [S/N] (padrao: N)"
    if ($r -match '^[Ss]') {
        Write-Host "   Removendo node_modules/ (aguarde)..." -NoNewline
        try { Remove-Item $nmDir -Recurse -Force; Write-Host " OK" -ForegroundColor Green }
        catch { Write-Host " FALHOU: $_" -ForegroundColor Yellow }
    } else {
        Write-Host "   node_modules/ mantido." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Desinstalacao concluida." -ForegroundColor Green
Write-Host "bridge.js e package.json foram mantidos." -ForegroundColor Gray
Write-Host ""
Read-Host "Pressione Enter para sair"
