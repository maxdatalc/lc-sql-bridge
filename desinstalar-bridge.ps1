# desinstalar-bridge.ps1
# Remove a tarefa agendada e opcionalmente apaga configuracoes e logs.
# Nao remove o Node.js. Nao apaga bridge.js ou package.json.

#Requires -Version 5.1
Set-StrictMode -Off

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
Set-Location $ScriptDir

$TaskName = "LC Gestor SQL Bridge"

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
Write-Host "LC Gestor — Desinstalacao da Bridge SQL" -ForegroundColor Cyan
Write-Host ""

# 1. Parar processo em execucao
try {
    $procs = Get-CimInstance Win32_Process -Filter "name = 'node.exe'" |
             Where-Object { $_.CommandLine -like "*bridge.js*" }
    if ($procs) {
        Write-Host "Bridge em execucao detectada (PID $($procs.ProcessId))." -ForegroundColor Yellow
        $confirmar = Read-Host "Encerrar processo agora? [S/N]"
        if ($confirmar -match '^[Ss]') {
            $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Write-Host "   Processo encerrado." -ForegroundColor Green
        } else {
            Write-Host "   Processo mantido em execucao." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Bridge nao esta em execucao." -ForegroundColor Gray
    }
} catch {
    Write-Host "   Nao foi possivel verificar processo: $_" -ForegroundColor Gray
}

# 2. Remover tarefa agendada
$tarefaExiste = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($tarefaExiste) {
    Write-Host "Removendo tarefa agendada '$TaskName'..." -NoNewline
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " FALHOU: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Tarefa agendada nao encontrada (ja removida ou nunca criada)." -ForegroundColor Gray
}

# 3. Perguntar sobre .env
$envFile = Join-Path $ScriptDir ".env"
if (Test-Path $envFile) {
    Write-Host ""
    Write-Host "ATENCAO: o arquivo .env contem o token e credenciais do cliente." -ForegroundColor Yellow
    $r = Read-Host "Apagar .env? [S/N] (padrao: N)"
    if ($r -match '^[Ss]') {
        Remove-Item $envFile -Force
        Write-Host "   .env removido." -ForegroundColor Green
    } else {
        Write-Host "   .env mantido." -ForegroundColor Gray
    }
}

# 4. Perguntar sobre logs
$logsDir = Join-Path $ScriptDir "logs"
if (Test-Path $logsDir) {
    $logFiles = Get-ChildItem $logsDir -File
    if ($logFiles.Count -gt 0) {
        Write-Host ""
        $r = Read-Host "Apagar pasta de logs ($($logFiles.Count) arquivo(s))? [S/N] (padrao: N)"
        if ($r -match '^[Ss]') {
            Remove-Item $logsDir -Recurse -Force
            Write-Host "   Logs removidos." -ForegroundColor Green
        } else {
            Write-Host "   Logs mantidos." -ForegroundColor Gray
        }
    }
}

# 5. Perguntar sobre configuracao-cliente.txt
$summaryFile = Join-Path $ScriptDir "configuracao-cliente.txt"
if (Test-Path $summaryFile) {
    $r = Read-Host "Apagar configuracao-cliente.txt? [S/N] (padrao: N)"
    if ($r -match '^[Ss]') {
        Remove-Item $summaryFile -Force
        Write-Host "   configuracao-cliente.txt removido." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Desinstalacao concluida." -ForegroundColor Green
Write-Host "Node.js e os arquivos da bridge foram mantidos." -ForegroundColor Gray
Write-Host ""
Read-Host "Pressione Enter para sair"
