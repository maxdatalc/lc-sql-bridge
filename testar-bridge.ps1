# testar-bridge.ps1
# Testa se a bridge esta respondendo corretamente.
# Le token e porta automaticamente do .env.

#Requires -Version 5.1
Set-StrictMode -Off

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
Set-Location $ScriptDir

$EnvFile = Join-Path $ScriptDir ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "ERRO: .env nao encontrado. Execute LCBRIDGE-INSTALL.exe primeiro." -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

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
    Read-Host "Pressione Enter para sair"
    exit 1
}

$baseUrl = "http://localhost:$port"

Write-Host ""
Write-Host "LC Gestor - Teste da Bridge SQL" -ForegroundColor Cyan
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
        Read-Host "Pressione Enter para sair"
        exit 1
    }
} catch {
    Write-Host "FALHOU - bridge nao esta rodando" -ForegroundColor Red
    Write-Host "   Verifique o servico Windows: Get-Service LCGestorSQLBridge" -ForegroundColor Yellow
    Write-Host "   Ou inicie via: Start-Service LCGestorSQLBridge" -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

# 2. Autenticacao com token errado (deve retornar 401)
Write-Host "[2/3] Verificando autenticacao... " -NoNewline
try {
    $r = Invoke-WebRequest -Uri "$baseUrl/query" -Method POST `
        -Headers @{ Authorization = "Bearer token_invalido"; 'Content-Type' = 'application/json' } `
        -Body '{"sql":"SELECT 1"}' -TimeoutSec 5 -ErrorAction SilentlyContinue
    Write-Host "AVISO - retornou $($r.StatusCode) (esperado 401)" -ForegroundColor Yellow
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        Write-Host "OK  (token invalido rejeitado corretamente)" -ForegroundColor Green
    } else {
        Write-Host "AVISO - resposta inesperada: $_" -ForegroundColor Yellow
    }
}

# 3. Query real
$queryPadrao = "SELECT TOP 1 vedId FROM venda"
Write-Host "[3/3] Executando query de teste..."
$customQuery = Read-Host "   Query [$queryPadrao] (Enter para usar padrao)"
if ($customQuery.Trim() -ne '') { $queryPadrao = $customQuery.Trim() }

try {
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
    $body    = [System.Text.Encoding]::UTF8.GetBytes(("{""sql"":""{0}""}" -f ($queryPadrao -replace '"', '\"')))
    $resp    = Invoke-RestMethod -Uri "$baseUrl/query" -Method POST `
               -Headers $headers -Body $body -TimeoutSec 15

    if ($null -ne $resp.rows) {
        $nRows = $resp.rows.Count
        Write-Host "   OK - $nRows linha(s) retornada(s)" -ForegroundColor Green
        if ($resp.rows.Count -gt 0) {
            Write-Host "   Primeira linha: $($resp.rows[0] | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   AVISO - resposta sem campo rows" -ForegroundColor Yellow
    }
} catch {
    $sc  = $null; try { $sc  = $_.Exception.Response.StatusCode.value__ } catch {}
    $eb  = '';    try { $eb  = $_.ErrorDetails.Message } catch {}

    Write-Host "   FALHOU (HTTP $sc)" -ForegroundColor Red
    switch ($sc) {
        401    { Write-Host "   Causa: token incorreto no .env." -ForegroundColor Yellow }
        403    { Write-Host "   Causa: query bloqueada (nao e SELECT puro)." -ForegroundColor Yellow }
        500    {
            if     ($eb -match 'Login failed')          { Write-Host "   Causa: usuario SQL sem acesso ao banco." -ForegroundColor Yellow }
            elseif ($eb -match 'Cannot open database')  { Write-Host "   Causa: banco nao encontrado. Verifique DB_NAME no .env." -ForegroundColor Yellow }
            elseif ($eb -match 'Invalid object')        { Write-Host "   Causa: tabela nao existe neste banco." -ForegroundColor Yellow }
            elseif ($eb -match 'Invalid column')        { Write-Host "   Causa: coluna nao encontrada." -ForegroundColor Yellow }
            elseif ($eb -match 'Timeout')               { Write-Host "   Causa: timeout. SQL Server lento ou inacessivel." -ForegroundColor Yellow }
            else                                        { Write-Host "   Detalhe: $eb" -ForegroundColor Gray }
        }
        $null  { Write-Host "   Bridge nao respondeu. Verifique se esta rodando." -ForegroundColor Yellow }
    }
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host ""
Write-Host "Bridge funcionando corretamente." -ForegroundColor Green
Write-Host ""
Read-Host "Pressione Enter para sair"
