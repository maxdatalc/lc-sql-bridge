# instalar.ps1
# Instalador completo da lc-sql-bridge.
# Cria o usuario SQL lc_dashboard e configura a bridge em uma so execucao.
#
# Como usar:
#   Duplo clique em INSTALAR.exe  (recomendado — UAC automatico)
#   Duplo clique em INSTALAR.bat  (alternativa sem exe gerado)

#Requires -Version 5.1
Set-StrictMode -Off

# $PSScriptRoot fica vazio quando compilado como .exe via ps2exe — usa o caminho do processo como fallback
$BridgeDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
Set-Location $BridgeDir

# ── Constantes ────────────────────────────────────────────────────────────────
$TaskName    = "LC Gestor SQL Bridge"
$EnvFile     = Join-Path $BridgeDir ".env"
$BridgeFile  = Join-Path $BridgeDir "bridge.js"
$PackageFile = Join-Path $BridgeDir "package.json"
$SummaryFile = Join-Path $BridgeDir "configuracao-cliente.txt"
$TotalSteps  = 8

# Credenciais SQL fixas — iguais em todos os clientes
$SQL_USER       = 'lc_dashboard'
$SQL_PASS       = 'Max@1225'
$SQL_ADMIN_USER = 'sa'
$SQL_ADMIN_PASS = 'macro01'

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Step($n, $msg) {
    Write-Host ""
    Write-Host "[$n/$TotalSteps] $msg" -ForegroundColor Cyan
}
function Write-OK($msg)   { Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   AVISO: $msg" -ForegroundColor Yellow }
function Abort($msg) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "   INSTALACAO CANCELADA" -ForegroundColor Red
    Write-Host "   $msg" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host ""
    Read-Host "Pressione Enter para sair"
    exit 1
}

trap {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "   ERRO INESPERADO — INSTALACAO INTERROMPIDA" -ForegroundColor Red
    Write-Host "   $_" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Dica: verifique se esta executando como Administrador." -ForegroundColor Gray
    Write-Host ""
    Read-Host "Pressione Enter para sair"
    exit 1
}

# ── Banner ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   LC Gestor -- Instalador da Bridge SQL  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ── PASSO 1: Ambiente ─────────────────────────────────────────────────────────
Write-Step 1 "Verificando ambiente"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdmin) {
    Write-OK "Executando como Administrador."
} else {
    Write-Warn "Sem privilegios de Administrador."
    Write-Host "   Para startup automatico sem login e criacao do usuario SQL," -ForegroundColor Yellow
    Write-Host "   execute INSTALAR.exe ou INSTALAR.bat (solicita UAC automaticamente)." -ForegroundColor Yellow
}

# Detectar reinstalacao
$isReinstall = Test-Path $EnvFile
if ($isReinstall) {
    Write-Warn "Instalacao existente detectada."
    Write-Host ""
    Write-Host "   O que deseja fazer?" -ForegroundColor White
    Write-Host "   [1] Reparar (manter .env e token existentes)" -ForegroundColor White
    Write-Host "   [2] Reconfigurar (novo .env, opcao de novo token)" -ForegroundColor White
    Write-Host "   [3] Cancelar" -ForegroundColor White
    Write-Host ""
    $op = Read-Host "   Escolha [1/2/3]"
    switch ($op) {
        '3' { Write-Host "Cancelado." -ForegroundColor Gray; Read-Host "Pressione Enter para sair"; exit 0 }
        '2' { $isReinstall = $false }
        default { $isReinstall = $true }
    }
}

# ── PASSO 2: Node.js ──────────────────────────────────────────────────────────
Write-Step 2 "Verificando Node.js"

$nodeOk   = $false
$nodeFull = $null

try {
    $nodeVersion = & node -v 2>&1
    if ($nodeVersion -match 'v\d+') {
        Write-OK "Node.js encontrado: $nodeVersion"
        $nodeOk = $true
        $nc = Get-Command node.exe -ErrorAction SilentlyContinue
        if ($nc) { $nodeFull = $nc.Source }
    }
} catch { }

if (-not $nodeOk) {
    Write-Warn "Node.js nao encontrado."
    Write-Host ""
    $wingetOk = $false
    try { $wg = & winget -v 2>&1; if ($wg -match '\d+\.\d+') { $wingetOk = $true } } catch { }

    if ($wingetOk) {
        $r = Read-Host "   Instalar Node.js LTS automaticamente via winget? [S/N]"
        if ($r -match '^[Ss]') {
            Write-Host "   Instalando Node.js LTS (aguarde)..." -ForegroundColor Cyan
            try {
                & winget install OpenJS.NodeJS.LTS --scope machine --accept-package-agreements --accept-source-agreements
                $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                            [System.Environment]::GetEnvironmentVariable('PATH', 'User')
                $nodeVersion = & node -v 2>&1
                $nc2 = Get-Command node.exe -ErrorAction SilentlyContinue
                if ($nc2) { $nodeFull = $nc2.Source }
                if ($nodeVersion -match 'v\d+') {
                    Write-OK "Node.js instalado: $nodeVersion"
                    $nodeOk = $true
                } else {
                    Write-Host ""
                    Write-Host "   Node.js instalado mas requer novo terminal para funcionar." -ForegroundColor Yellow
                    Write-Host "   Feche esta janela e execute INSTALAR.exe novamente." -ForegroundColor Yellow
                    Read-Host "Pressione Enter para sair"
                    exit 1
                }
            } catch { Abort "Falha ao instalar Node.js via winget: $_" }
        } else { Abort "Node.js LTS e obrigatorio. Baixe em: https://nodejs.org" }
    } else {
        Write-Host ""
        Write-Host "   winget nao disponivel. Instale o Node.js LTS manualmente:" -ForegroundColor Yellow
        Write-Host "   https://nodejs.org  ->  botao LTS" -ForegroundColor White
        Read-Host "Pressione Enter para sair"
        exit 1
    }
}

try {
    $npmVersion = & npm.cmd -v 2>&1
    Write-OK "npm encontrado: v$npmVersion"
} catch { Abort "npm nao encontrado. Reinstale o Node.js." }

if (-not $nodeFull) {
    $nc3 = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nc3) { $nodeFull = $nc3.Source }
    if (-not $nodeFull) {
        foreach ($c in @(
            "$env:ProgramFiles\nodejs\node.exe",
            "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
        )) {
            if (Test-Path $c) { $nodeFull = $c; break }
        }
    }
}

# ── PASSO 3: Arquivos e dependencias ──────────────────────────────────────────
Write-Step 3 "Validando arquivos e instalando dependencias"

if (-not (Test-Path $BridgeFile))  { Abort "bridge.js nao encontrado em $BridgeDir" }
if (-not (Test-Path $PackageFile)) { Abort "package.json nao encontrado em $BridgeDir" }
Write-OK "bridge.js e package.json encontrados."

try {
    Push-Location $BridgeDir
    & npm.cmd install 2>&1 | Out-Null
    Pop-Location
    Write-OK "Dependencias instaladas."
} catch {
    Pop-Location -ErrorAction SilentlyContinue
    Abort "Falha ao executar npm install: $_"
}

# ── PASSO 4: Configuracoes ────────────────────────────────────────────────────
Write-Step 4 "Coletando configuracoes"

$clienteNome   = ''
$dbHost        = 'localhost'
$dbPort        = '1433'
$dbName        = ''
$bridgePort    = '3055'
$existingToken = ''

if ($isReinstall) {
    Write-Host "   Mantendo configuracoes do .env existente." -ForegroundColor Gray
    $envVars = @{}
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([^#=][^=]*)=(.*)$') {
            $envVars[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    if ($envVars['DB_HOST'])      { $dbHost     = $envVars['DB_HOST'] }
    if ($envVars['DB_PORT'])      { $dbPort     = $envVars['DB_PORT'] }
    if ($envVars['DB_NAME'])      { $dbName     = $envVars['DB_NAME'] }
    if ($envVars['PORT'])         { $bridgePort = $envVars['PORT'] }
    if ($envVars['BRIDGE_TOKEN']) { $existingToken = $envVars['BRIDGE_TOKEN'] }
    Write-OK "Host: $dbHost  |  Banco: $dbName  |  Porta bridge: $bridgePort"

    $regen = Read-Host "   Gerar novo token de seguranca? [S/N] (padrao: N)"
    if ($regen -match '^[Ss]') {
        $existingToken = ''
        Write-Warn "Novo token sera gerado. Atualize no Supabase apos a instalacao."
    } else {
        Write-OK "Token existente preservado."
    }
} else {
    Write-Host ""
    $clienteNome = Read-Host "   Nome do cliente (para identificacao)"

    Write-Host ""
    Write-Host "   Configuracoes do SQL Server:" -ForegroundColor White
    $inp = Read-Host "   Host do SQL Server [localhost]"
    if ($inp.Trim() -ne '') { $dbHost = $inp.Trim() }

    while ($dbName.Trim() -eq '') { $dbName = Read-Host "   Nome do banco de dados" }

    Write-Host ""
    Write-Host "   Configuracoes da bridge:" -ForegroundColor White
    $inp = Read-Host "   Porta da bridge [3055]"
    if ($inp.Trim() -ne '') { $bridgePort = $inp.Trim() }
}

# ── PASSO 5: Criar usuario SQL ────────────────────────────────────────────────
Write-Step 5 "Criando usuario SQL ($SQL_USER)"

# Script SQL idempotente com as credenciais fixas
$scriptSQL = @"
USE [master];

IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = N'$SQL_USER')
    CREATE LOGIN [$SQL_USER]
        WITH PASSWORD        = N'$SQL_PASS',
             CHECK_POLICY    = OFF,
             CHECK_EXPIRATION = OFF;
ELSE
    ALTER LOGIN [$SQL_USER] WITH PASSWORD = N'$SQL_PASS';
GO

USE [$dbName];

IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'$SQL_USER')
    CREATE USER [$SQL_USER] FOR LOGIN [$SQL_USER];
GO

EXEC sp_addrolemember 'db_datareader', '$SQL_USER';
DENY INSERT, UPDATE, DELETE, EXECUTE, ALTER TO [$SQL_USER];
GO
"@

# Salva script para referencia/execucao manual
$sqlFile = Join-Path $BridgeDir "criar-usuario.sql"
[System.IO.File]::WriteAllText($sqlFile, $scriptSQL, [System.Text.UTF8Encoding]::new($false))

# Localizar sqlcmd
$sqlcmd = $null
$scCmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if ($scCmd) { $sqlcmd = $scCmd.Source }

if (-not $sqlcmd) {
    $candidatos = @(
        "${env:ProgramFiles}\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
        "${env:ProgramFiles}\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
        "${env:ProgramFiles}\Microsoft SQL Server\130\Tools\Binn\sqlcmd.exe",
        "${env:ProgramFiles}\Microsoft SQL Server\120\Tools\Binn\sqlcmd.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
    )
    foreach ($c in $candidatos) {
        if (Test-Path $c) { $sqlcmd = $c; break }
    }
}

$serverArg = if ($dbPort -eq '1433') { $dbHost } else { "$dbHost,$dbPort" }

if (-not $sqlcmd) {
    Write-Warn "sqlcmd nao encontrado."
    Write-Host "   Execute o script SQL manualmente no SSMS antes de usar a bridge:" -ForegroundColor Yellow
    Write-Host "   Arquivo: criar-usuario.sql" -ForegroundColor White
} else {
    $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tmpSql, $scriptSQL, [System.Text.UTF8Encoding]::new($false))

    try {
        Write-Host "   Executando script SQL (sa)..." -ForegroundColor Gray
        $resultado = & $sqlcmd -S $serverArg -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASS -i $tmpSql 2>&1
        $exitCode  = $LASTEXITCODE
        $resultado | ForEach-Object {
            if ($_.Trim() -ne '') { Write-Host "   $_" -ForegroundColor Gray }
        }
        if ($exitCode -ne 0) {
            Write-Warn "sqlcmd retornou erro (codigo $exitCode). Verifique as mensagens acima."
            Write-Host "   Se preferir, execute criar-usuario.sql manualmente no SSMS." -ForegroundColor Yellow
        } else {
            Write-OK "Usuario '$SQL_USER' criado/atualizado no banco '$dbName'."
        }
    } finally {
        Remove-Item $tmpSql -ErrorAction SilentlyContinue
    }
}
Write-Host "   Script SQL salvo em: criar-usuario.sql" -ForegroundColor Gray

# ── PASSO 6: Porta e .env ─────────────────────────────────────────────────────
Write-Step 6 "Preparando configuracao (.env)"

try {
    $conns = Get-NetTCPConnection -LocalPort ([int]$bridgePort) -State Listen -ErrorAction SilentlyContinue
    if ($conns) {
        $proc = Get-Process -Id $conns[0].OwningProcess -ErrorAction SilentlyContinue
        $procNome = if ($proc) { $proc.Name } else { "PID $($conns[0].OwningProcess)" }
        Write-Warn "Porta $bridgePort em uso por '$procNome'."
        $outra = Read-Host "   Informe outra porta (ou Enter para continuar mesmo assim)"
        if ($outra.Trim() -ne '') { $bridgePort = $outra.Trim() }
    } else {
        Write-OK "Porta $bridgePort disponivel."
    }
} catch {
    Write-OK "Porta $bridgePort (verificacao ignorada)."
}

if ($existingToken -eq '') {
    $tb = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($tb)
    $novoToken = [System.BitConverter]::ToString($tb).Replace('-', '').ToLower()
} else {
    $novoToken = $existingToken
}

$envContent = "BRIDGE_TOKEN=$novoToken`nDB_HOST=$dbHost`nDB_PORT=$dbPort`nDB_NAME=$dbName`nDB_USER=$SQL_USER`nDB_PASS=$SQL_PASS`nPORT=$bridgePort"
$utf8NoBom  = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($EnvFile, $envContent, $utf8NoBom)
Write-OK ".env criado (usuario SQL: $SQL_USER)."

$gi = Join-Path $BridgeDir ".gitignore"
if (Test-Path $gi) {
    $giContent = Get-Content $gi -Raw
    if ($giContent -notmatch '(^|\n)\.env(\r|\n|$)') { Add-Content $gi "`n.env" }
}

# ── PASSO 7: Inicializacao automatica ────────────────────────────────────────
Write-Step 7 "Configurando inicializacao automatica (Agendador de Tarefas)"

$autoStartMode = 'manual (use iniciar-bridge.ps1)'

if (-not $nodeFull) {
    Write-Warn "node.exe nao localizado — startup automatico nao configurado."
} else {
    $nodePerUser      = $nodeFull.ToLower().Contains($env:LOCALAPPDATA.ToLower())
    $useSystemAccount = $isAdmin -and (-not $nodePerUser)

    if ($isAdmin -and $nodePerUser) {
        Write-Warn "Node.js esta na pasta do usuario — SYSTEM nao teria acesso."
        Write-Host "   Para startup sem login, reinstale com:" -ForegroundColor Gray
        Write-Host "   winget install OpenJS.NodeJS.LTS --scope machine" -ForegroundColor Gray
    }

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

        $action = New-ScheduledTaskAction `
            -Execute $nodeFull `
            -Argument "bridge.js" `
            -WorkingDirectory $BridgeDir

        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit 0 `
            -MultipleInstances  IgnoreNew `
            -RestartCount       3 `
            -RestartInterval    (New-TimeSpan -Minutes 2) `
            -StartWhenAvailable

        if ($useSystemAccount) {
            $principal = New-ScheduledTaskPrincipal `
                -UserId    "SYSTEM" `
                -RunLevel  Highest `
                -LogonType ServiceAccount
            $triggers = @(
                (New-ScheduledTaskTrigger -AtStartup),
                (New-ScheduledTaskTrigger -AtLogOn)
            )
            Register-ScheduledTask `
                -TaskName   $TaskName `
                -Action     $action `
                -Trigger    $triggers `
                -Settings   $settings `
                -Principal  $principal `
                -Description "LC Gestor - Bridge SQL Server (porta $bridgePort)" `
                -Force | Out-Null
            $autoStartMode = 'SYSTEM — inicia com o Windows, sem login necessario'
            Write-OK "Tarefa criada como SYSTEM."
            Write-Host "   Reinicia automaticamente em caso de falha (ate 3x, intervalo 2 min)." -ForegroundColor Gray
        } else {
            $principal = New-ScheduledTaskPrincipal `
                -UserId    "$env:USERDOMAIN\$env:USERNAME" `
                -LogonType Interactive `
                -RunLevel  Limited
            Register-ScheduledTask `
                -TaskName   $TaskName `
                -Action     $action `
                -Trigger    (New-ScheduledTaskTrigger -AtLogOn) `
                -Settings   $settings `
                -Principal  $principal `
                -Description "LC Gestor - Bridge SQL Server (porta $bridgePort)" `
                -Force | Out-Null
            $autoStartMode = "login de $env:USERNAME"
            Write-OK "Tarefa criada para $env:USERNAME."
            Write-Warn "Para startup sem login, execute INSTALAR.exe como Administrador."
        }
    } catch {
        Write-Warn "Nao foi possivel criar tarefa: $_ — use iniciar-bridge.ps1 manualmente."
    }
}

# ── PASSO 8: Iniciar e testar ─────────────────────────────────────────────────
Write-Step 8 "Iniciando bridge e testando conexao"

$baseUrl = "http://localhost:$bridgePort"
$testeOk = $false
$sqlOk   = $false

if (-not $nodeFull) {
    Write-Warn "node.exe nao localizado. Use iniciar-bridge.ps1 para iniciar manualmente."
} else {
    $env:BRIDGE_TOKEN = $novoToken
    $env:DB_HOST      = $dbHost
    $env:DB_PORT      = $dbPort
    $env:DB_NAME      = $dbName
    $env:DB_USER      = $SQL_USER
    $env:DB_PASS      = $SQL_PASS
    $env:PORT         = $bridgePort

    try {
        Start-Process -FilePath $nodeFull `
            -ArgumentList "bridge.js" `
            -WorkingDirectory $BridgeDir `
            -WindowStyle Hidden
    } catch {
        Write-Warn "Nao foi possivel iniciar a bridge automaticamente: $_"
    }

    Start-Sleep -Seconds 3

    # Health check
    try {
        $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method GET -TimeoutSec 5
        if ($health.ok) {
            Write-OK "Bridge online. Banco: $($health.db)"
            $testeOk = $true
        }
    } catch {
        Write-Warn "Bridge nao respondeu ao health check."
    }

    # Query de teste
    if ($testeOk) {
        $queryPadrao = "SELECT TOP 1 vedId FROM venda"
        Write-Host ""
        $customQ = Read-Host "   Query de teste [$queryPadrao] (Enter para usar padrao)"
        if ($customQ.Trim() -ne '') { $queryPadrao = $customQ.Trim() }

        try {
            $headers   = @{ Authorization = "Bearer $novoToken"; 'Content-Type' = 'application/json' }
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(("{""sql"":""{0}""}" -f ($queryPadrao -replace '"', '\"')))
            $resp      = Invoke-RestMethod -Uri "$baseUrl/query" -Method POST `
                         -Headers $headers -Body $bodyBytes -TimeoutSec 15
            if ($null -ne $resp.rows) {
                Write-OK "SQL Server acessivel. $($resp.rows.Count) linha(s) retornada(s)."
                $sqlOk = $true
            }
        } catch {
            $sc = $null; try { $sc = $_.Exception.Response.StatusCode.value__ } catch {}
            $eb = ''; try { $eb = $_.ErrorDetails.Message } catch {}
            $sqlErro = switch ($sc) {
                401 { "Token invalido" }
                403 { "Query bloqueada — verifique se e um SELECT puro" }
                500 {
                    if     ($eb -match 'Login failed')          { "Login SQL recusado — usuario ou senha incorretos" }
                    elseif ($eb -match 'Cannot open database')  { "Banco '$dbName' nao encontrado no SQL Server" }
                    elseif ($eb -match 'Invalid object')        { "Tabela nao encontrada — verifique o nome do banco" }
                    elseif ($eb -match 'network-related')       { "SQL Server inacessivel — verifique DB_HOST e firewall" }
                    elseif ($eb -match 'Timeout')               { "Timeout — SQL Server lento ou fora do ar" }
                    else                                        { "Erro SQL: $eb" }
                }
                default { "Bridge nao respondeu (PID iniciado mas porta nao responde)" }
            }
            Write-Warn "Teste falhou: $sqlErro"
        }
    }
}

# ── Resultado final ───────────────────────────────────────────────────────────
$data = Get-Date -Format "dd/MM/yyyy HH:mm"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
if ($testeOk -and $sqlOk) {
    Write-Host "   Instalacao concluida com sucesso!" -ForegroundColor Green
} elseif ($testeOk) {
    Write-Host "   Bridge online — SQL com aviso (veja acima)" -ForegroundColor Yellow
} else {
    Write-Host "   Instalacao com pendencias (veja avisos acima)" -ForegroundColor Yellow
}
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Banco:               $dbName" -ForegroundColor White
Write-Host "  Porta bridge:        $bridgePort" -ForegroundColor White
Write-Host "  Usuario SQL:         $SQL_USER" -ForegroundColor White
Write-Host "  Inicializacao auto:  $autoStartMode" -ForegroundColor White
Write-Host "  Data:                $data" -ForegroundColor White
Write-Host ""
Write-Host "  TOKEN DE SEGURANCA (copie para o Supabase):" -ForegroundColor Yellow
Write-Host "  $novoToken" -ForegroundColor White
Write-Host ""

$copiar = Read-Host "  Copiar token para a area de transferencia? [S/N]"
if ($copiar -match '^[Ss]') {
    try { $novoToken | Set-Clipboard; Write-Host "  Token copiado." -ForegroundColor Green }
    catch { Write-Host "  Nao foi possivel copiar. Copie manualmente acima." -ForegroundColor Yellow }
}

# Sugestao de subdominio baseada no nome do cliente
$slugCliente = $clienteNome -replace '[^a-zA-Z0-9]', '-' -replace '-+', '-' -replace '^-|-$', ''
if (-not $slugCliente) { $slugCliente = 'nomecliente' }
$slugCliente = $slugCliente.ToLower()

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   PROXIMO PASSO: Cloudflare Tunnel        " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Acesse: https://one.dash.cloudflare.com" -ForegroundColor White
Write-Host "     Zero Trust -> Networks -> Tunnels" -ForegroundColor Gray
Write-Host "     Clique no tunnel do cliente -> Edit -> Public Hostname -> Add" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Preencha:" -ForegroundColor White
Write-Host "     Subdomain : sql-$slugCliente" -ForegroundColor Yellow
Write-Host "     Domain    : lcgestor.com.br" -ForegroundColor Yellow
Write-Host "     Type      : HTTP" -ForegroundColor Yellow
Write-Host "     URL       : localhost:$bridgePort" -ForegroundColor Yellow
Write-Host ""
Write-Host "  3. Cadastre no painel LC Gestor:" -ForegroundColor White
Write-Host "     URL do cliente : https://sql-$slugCliente.lcgestor.com.br" -ForegroundColor Yellow
Write-Host "     Token          : (o token exibido acima)" -ForegroundColor Yellow
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

# Resumo sem token
$summary = @"
LC Gestor -- Configuracao da Bridge SQL
=======================================
Cliente:             $clienteNome
Host SQL Server:     $dbHost
Porta SQL Server:    $dbPort
Banco de dados:      $dbName
Usuario SQL:         $SQL_USER
Porta bridge:        $bridgePort
URL local:           http://localhost:$bridgePort
Inicializacao auto:  $autoStartMode
Status do teste:     $(if ($sqlOk) { 'OK' } elseif ($testeOk) { 'Bridge OK / SQL com aviso' } else { 'Verificar' })
Data de instalacao:  $data

IMPORTANTE: O token de seguranca NAO esta neste arquivo.
Ele esta no arquivo .env e foi exibido na tela durante a instalacao.
Cadastre o token no painel Supabase do LC Gestor.
"@

[System.IO.File]::WriteAllText($SummaryFile, $summary, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "  Resumo salvo em: configuracao-cliente.txt (sem token)" -ForegroundColor Gray
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione Enter para sair"
