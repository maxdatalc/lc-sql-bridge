# testar-bridge.ps1
# Testa se a bridge esta respondendo corretamente.
# Le token e porta automaticamente do .env — nao precisa copiar nada.

Set-Location $PSScriptRoot

$EnvFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "ERRO: .env nao encontrado. Execute instalar-bridge.ps1 primeiro." -ForegroundColor Red
    exit 1
}

# Le variaveis do .env
$envVars = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim()
    }
}

$token = $envVars['BRIDGE_TOKEN']
$port  = if ($envVars['PORT']) { $envVars['PORT'] } else { '3055' }

if (-not $token) {
    Write-Host "ERRO: BRIDGE_TOKEN nao encontrado no .env." -ForegroundColor Red
    exit 1
}

$baseUrl = "http://localhost:$port"

Write-Host ""
Write-Host "LC Gestor — Teste da Bridge SQL" -ForegroundColor Cyan
Write-Host "URL: $baseUrl" -ForegroundColor White
Write-Host ""

# 1. Health check
Write-Host "[1/3] Health check... " -NoNewline
try {
    $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method GET -TimeoutSec 5
    if ($health.ok) {
        Write-Host "OK  (banco: $($health.db))" -ForegroundColor Green
    } else {
        Write-Host "FALHOU" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "FALHOU — bridge nao esta rodando" -ForegroundColor Red
    Write-Host "   Execute iniciar-bridge.ps1 ou verifique o Agendador de Tarefas." -ForegroundColor Yellow
    exit 1
}

# 2. Autenticacao com token errado (deve retornar 401)
Write-Host "[2/3] Verificando autenticacao... " -NoNewline
try {
    $r = Invoke-WebRequest -Uri "$baseUrl/query" -Method POST `
        -Headers @{ Authorization = "Bearer token_invalido"; 'Content-Type' = 'application/json' } `
        -Body '{"sql":"SELECT 1"}' -TimeoutSec 5 -ErrorAction SilentlyContinue
    Write-Host "AVISO — retornou $($r.StatusCode) (esperado 401)" -ForegroundColor Yellow
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        Write-Host "OK  (token invalido rejeitado corretamente)" -ForegroundColor Green
    } else {
        Write-Host "AVISO — resposta inesperada: $_" -ForegroundColor Yellow
    }
}

# 3. Query real
$queryPadrao = "SELECT TOP 1 vedId FROM venda"
Write-Host "[3/3] Executando query de teste... " -NoNewline
Write-Host ""
$customQuery = Read-Host "   Query [$queryPadrao] (Enter para usar padrao)"
if ($customQuery.Trim() -ne '') { $queryPadrao = $customQuery.Trim() }

try {
    $headers = @{
        Authorization  = "Bearer $token"
        'Content-Type' = 'application/json'
    }
    $body = [System.Text.Encoding]::UTF8.GetBytes(("{""sql"":""{0}""}" -f ($queryPadrao -replace '"', '\"')))
    $response = Invoke-RestMethod -Uri "$baseUrl/query" -Method POST `
        -Headers $headers -Body $body -TimeoutSec 15

    if ($null -ne $response.rows) {
        Write-Host "   OK  — $($response.rows.Count) linha(s) retornada(s)" -ForegroundColor Green
        if ($response.rows.Count -gt 0) {
            Write-Host "   Primeira linha: $($response.rows[0] | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   AVISO — resposta sem campo 'rows'" -ForegroundColor Yellow
    }
} catch {
    $statusCode = $_.Exception.Response?.StatusCode?.value__
    $errBody    = ''
    try { $errBody = $_.ErrorDetails.Message } catch {}

    Write-Host "   FALHOU (HTTP $statusCode)" -ForegroundColor Red

    switch ($statusCode) {
        401 { Write-Host "   Causa provavel: token incorreto no .env." -ForegroundColor Yellow }
        403 { Write-Host "   Causa provavel: query bloqueada (nao e SELECT puro)." -ForegroundColor Yellow }
        500 {
            if ($errBody -match 'Login failed')          { Write-Host "   Causa: usuario SQL sem acesso ao banco." -ForegroundColor Yellow }
            elseif ($errBody -match 'Cannot open database') { Write-Host "   Causa: banco nao encontrado. Verifique DB_NAME no .env." -ForegroundColor Yellow }
            elseif ($errBody -match 'Invalid object')    { Write-Host "   Causa: tabela 'venda' nao existe neste banco." -ForegroundColor Yellow }
            elseif ($errBody -match 'Invalid column')    { Write-Host "   Causa: coluna 'vedId' nao encontrada." -ForegroundColor Yellow }
            elseif ($errBody -match 'Timeout')           { Write-Host "   Causa: timeout. SQL Server lento ou inacessivel." -ForegroundColor Yellow }
            else { Write-Host "   Detalhe: $errBody" -ForegroundColor Gray }
        }
        $null { Write-Host "   Bridge nao respondeu. Verifique se esta rodando." -ForegroundColor Yellow }
    }
    exit 1
}

Write-Host ""
Write-Host "Bridge funcionando corretamente." -ForegroundColor Green
Write-Host ""
