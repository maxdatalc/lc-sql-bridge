# desinstalar-bridge.ps1
# Remove a tarefa agendada e opcionalmente apaga configuracoes e logs.
# Nao remove o Node.js. Nao apaga bridge.js ou package.json.

Set-Location $PSScriptRoot

$TaskName = "LC Gestor SQL Bridge"

Write-Host ""
Write-Host "LC Gestor — Desinstalacao da Bridge SQL" -ForegroundColor Cyan
Write-Host ""

# 1. Parar processo em execucao
$processoRodando = $false
try {
    $procs = Get-CimInstance Win32_Process -Filter "name = 'node.exe'" |
             Where-Object { $_.CommandLine -like "*bridge.js*" }
    if ($procs) {
        $processoRodando = $true
        Write-Host "Bridge em execucao detectada (PID $($procs.ProcessId))." -ForegroundColor Yellow
        $confirmar = Read-Host "Encerrar processo agora? [S/N]"
        if ($confirmar -match '^[Ss]') {
            $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Write-Host "   Processo encerrado." -ForegroundColor Green
        } else {
            Write-Host "   Processo mantido em execucao." -ForegroundColor Yellow
        }
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
        Write-Host " FALHOU" -ForegroundColor Red
        Write-Host "   Tente executar como Administrador se necessario." -ForegroundColor Yellow
    }
} else {
    Write-Host "Tarefa agendada nao encontrada (ja removida ou nunca criada)." -ForegroundColor Gray
}

# 3. Perguntar sobre .env
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Write-Host ""
    Write-Host "ATENCAO: o arquivo .env contem o token e credenciais do cliente." -ForegroundColor Yellow
    $removerEnv = Read-Host "Apagar .env? [S/N] (padrao: N)"
    if ($removerEnv -match '^[Ss]') {
        Remove-Item $envFile -Force
        Write-Host "   .env removido." -ForegroundColor Green
    } else {
        Write-Host "   .env mantido." -ForegroundColor Gray
    }
}

# 4. Perguntar sobre logs
$logsDir = Join-Path $PSScriptRoot "logs"
if (Test-Path $logsDir) {
    $logFiles = Get-ChildItem $logsDir -File
    if ($logFiles.Count -gt 0) {
        Write-Host ""
        $removerLogs = Read-Host "Apagar pasta de logs ($($logFiles.Count) arquivo(s))? [S/N] (padrao: N)"
        if ($removerLogs -match '^[Ss]') {
            Remove-Item $logsDir -Recurse -Force
            Write-Host "   Logs removidos." -ForegroundColor Green
        } else {
            Write-Host "   Logs mantidos." -ForegroundColor Gray
        }
    }
}

# 5. Perguntar sobre configuracao-cliente.txt
$summaryFile = Join-Path $PSScriptRoot "configuracao-cliente.txt"
if (Test-Path $summaryFile) {
    $removerSummary = Read-Host "Apagar configuracao-cliente.txt? [S/N] (padrao: N)"
    if ($removerSummary -match '^[Ss]') {
        Remove-Item $summaryFile -Force
        Write-Host "   configuracao-cliente.txt removido." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Desinstalacao concluida." -ForegroundColor Green
Write-Host "Node.js e os arquivos da bridge foram mantidos." -ForegroundColor Gray
Write-Host ""
Read-Host "Pressione Enter para sair"
