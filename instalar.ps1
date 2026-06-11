# instalar.ps1
# Instalador completo da lc-sql-bridge.
# Cria o usuario SQL lc_dashboard e configura a bridge em uma so execucao.
#
# Como usar:
#   Duplo clique em LCBRIDGE-INSTALL.exe  (recomendado - UAC automatico)
#   Duplo clique em INSTALAR.bat          (alternativa)

#Requires -Version 5.1
Set-StrictMode -Off

# $PSScriptRoot fica vazio quando compilado como .exe via ps2exe
$BridgeDir = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
Set-Location $BridgeDir

# ── Constantes ────────────────────────────────────────────────────────────────
$TaskName       = "LC Gestor SQL Bridge"
$EnvFile        = Join-Path $BridgeDir ".env"
$BridgeFile     = Join-Path $BridgeDir "bridge.js"
$PackageFile    = Join-Path $BridgeDir "package.json"
$SummaryFile    = Join-Path $BridgeDir "configuracao-cliente.txt"
$TotalSteps     = 8
$SQL_USER       = 'lc_dashboard'
$SQL_PASS       = 'Max@1225'
$SQL_ADMIN_USER = 'sa'
$SQL_ADMIN_PASS = 'macro01'
$W              = 74   # largura interna da caixa (linha total = W+4 = 78)

# ── UI Helpers ────────────────────────────────────────────────────────────────

function Center-Text($text, $width) {
    $pad = [Math]::Floor(($width - $text.Length) / 2)
    return (" " * [Math]::Max(0, $pad) + $text).PadRight($width)
}

function Write-BoxTop  ($c = 'Cyan')   { Write-Host ("  ╔" + "═" * $W + "╗") -ForegroundColor $c }
function Write-BoxBot  ($c = 'Cyan')   { Write-Host ("  ╚" + "═" * $W + "╝") -ForegroundColor $c }
function Write-BoxDiv  ($c = 'Cyan')   { Write-Host ("  ╠" + "═" * $W + "╣") -ForegroundColor $c }
function Write-BoxEmpty($c = 'Cyan')   { Write-Host ("  ║" + " " * $W + "║") -ForegroundColor $c }

function Write-BoxRow($text, $tc = 'White', $bc = 'Cyan') {
    Write-Host -NoNewline "  ║" -ForegroundColor $bc
    Write-Host -NoNewline $text.PadRight($W) -ForegroundColor $tc
    Write-Host "║" -ForegroundColor $bc
}

function Write-Banner {
    Write-Host ""
    Write-BoxTop
    Write-BoxEmpty
    Write-BoxRow (Center-Text "LC GESTOR  -  Bridge SQL" $W) 'White'
    Write-BoxRow (Center-Text "Instalador  v1.1" $W) 'DarkCyan'
    Write-BoxEmpty
    Write-BoxBot
    Write-Host ""
}

function Write-Step($n, $msg) {
    Write-Host ""
    Write-Host ("  ┌─[ $n/$TotalSteps ]  " + $msg) -ForegroundColor Cyan
    Write-Host "  │" -ForegroundColor DarkCyan
}

function Write-OK($msg)   { Write-Host "  │  ✓  $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  │  !  $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "  │     $msg" -ForegroundColor Gray }
function Write-Err($msg)  { Write-Host "  │  ✗  $msg" -ForegroundColor Red }

function Write-SectionTitle($title) {
    Write-Host ""
    Write-Host ("  ┌─ " + $title) -ForegroundColor DarkCyan
    Write-Host "  │" -ForegroundColor DarkCyan
}

function Write-Prompt($label) {
    return "  │  ▸  $label"
}

function Abort($msg) {
    Write-Host ""
    Write-BoxTop 'Red'
    Write-BoxRow ("  INSTALACAO CANCELADA") 'Red' 'Red'
    Write-BoxRow ("  $msg") 'Yellow' 'Red'
    Write-BoxBot 'Red'
    Write-Host ""
    Read-Host "  Pressione Enter para sair"
    exit 1
}

trap {
    Write-Host ""
    Write-BoxTop 'Red'
    Write-BoxRow "  ERRO INESPERADO - INSTALACAO INTERROMPIDA" 'Red' 'Red'
    Write-BoxRow "  $_" 'Yellow' 'Red'
    Write-BoxBot 'Red'
    Write-Host ""
    Write-Host "  Dica: verifique se esta executando como Administrador." -ForegroundColor Gray
    Write-Host ""
    Read-Host "  Pressione Enter para sair"
    exit 1
}

# ── Inicio ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Banner

# ── PASSO 1: Ambiente ─────────────────────────────────────────────────────────
Write-Step 1 "Verificando ambiente"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdmin) {
    Write-OK "Executando como Administrador."
} else {
    Write-Warn "Sem privilegios de Administrador."
    Write-Info "Execute LCBRIDGE-INSTALL.exe para obtencao automatica de UAC."
}

$isReinstall = Test-Path $EnvFile
if ($isReinstall) {
    Write-Warn "Instalacao existente detectada."
    Write-Host ""
    Write-Host "  │" -ForegroundColor DarkCyan
    Write-Host "  │   O que deseja fazer?" -ForegroundColor White
    Write-Host "  │   [1] Reparar (manter .env e token existentes)" -ForegroundColor White
    Write-Host "  │   [2] Reconfigurar (novo .env, opcao de novo token)" -ForegroundColor White
    Write-Host "  │   [3] Cancelar" -ForegroundColor White
    Write-Host "  │" -ForegroundColor DarkCyan
    $op = Read-Host (Write-Prompt "Escolha [1/2/3]")
    switch ($op) {
        '3' { Write-Host "  Cancelado." -ForegroundColor Gray; Read-Host "  Pressione Enter para sair"; exit 0 }
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
    Write-Host "  │" -ForegroundColor DarkCyan
    $wingetOk = $false
    try { $wg = & winget -v 2>&1; if ($wg -match '\d+\.\d+') { $wingetOk = $true } } catch { }

    if ($wingetOk) {
        $r = Read-Host (Write-Prompt "Instalar Node.js LTS automaticamente via winget? [S/N]")
        if ($r -match '^[Ss]') {
            Write-Info "Instalando Node.js LTS (aguarde)..."
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
                    Write-Warn "Node.js instalado mas requer novo terminal."
                    Write-Info "Feche esta janela e execute LCBRIDGE-INSTALL.exe novamente."
                    Read-Host "  Pressione Enter para sair"
                    exit 1
                }
            } catch { Abort "Falha ao instalar Node.js via winget: $_" }
        } else { Abort "Node.js LTS e obrigatorio. Baixe em: https://nodejs.org" }
    } else {
        Write-Warn "winget nao disponivel."
        Write-Info "Instale o Node.js LTS manualmente: https://nodejs.org"
        Read-Host "  Pressione Enter para sair"
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
        foreach ($c in @("$env:ProgramFiles\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")) {
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
Write-Step 4 "Configuracoes"

$clienteNome   = ''
$dbHost        = 'localhost'
$dbPort        = '1433'
$dbName        = ''
$bridgePort    = '3055'
$existingToken = ''

if ($isReinstall) {
    Write-Info "Mantendo configuracoes do .env existente."
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
    Write-OK "Host: $dbHost  |  Banco: $dbName  |  Porta: $bridgePort"

    $regen = Read-Host (Write-Prompt "Gerar novo token de seguranca? [S/N] (padrao: N)")
    if ($regen -match '^[Ss]') {
        $existingToken = ''
        Write-Warn "Novo token sera gerado. Atualize no Supabase apos a instalacao."
    } else {
        Write-OK "Token existente preservado."
    }
} else {
    Write-Host "  │" -ForegroundColor DarkCyan
    Write-SectionTitle "Identificacao do Cliente"
    $clienteNome = Read-Host (Write-Prompt "Nome do cliente                  ")
    Write-Host "  │" -ForegroundColor DarkCyan
    Write-SectionTitle "Conexao com o SQL Server"
    $inp = Read-Host (Write-Prompt "Host do SQL Server  [localhost]  ")
    if ($inp.Trim() -ne '') { $dbHost = $inp.Trim() }
    while ($dbName.Trim() -eq '') {
        $dbName = Read-Host (Write-Prompt "Nome do banco de dados           ")
    }
    Write-Host "  │" -ForegroundColor DarkCyan
    Write-SectionTitle "Configuracao da Bridge"
    $inp = Read-Host (Write-Prompt "Porta da bridge     [3055]       ")
    if ($inp.Trim() -ne '') { $bridgePort = $inp.Trim() }
}

# ── PASSO 5: Criar usuario SQL ────────────────────────────────────────────────
Write-Step 5 "Criando usuario SQL ($SQL_USER)"

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

$sqlFile = Join-Path $BridgeDir "criar-usuario.sql"
[System.IO.File]::WriteAllText($sqlFile, $scriptSQL, [System.Text.UTF8Encoding]::new($false))

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
    foreach ($c in $candidatos) { if (Test-Path $c) { $sqlcmd = $c; break } }
}

$serverArg = if ($dbPort -eq '1433') { $dbHost } else { "$dbHost,$dbPort" }

if (-not $sqlcmd) {
    Write-Warn "sqlcmd nao encontrado."
    Write-Info "Execute criar-usuario.sql manualmente no SSMS antes de usar a bridge."
} else {
    $tmpSql = [System.IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tmpSql, $scriptSQL, [System.Text.UTF8Encoding]::new($false))
    try {
        Write-Info "Executando script SQL com usuario sa..."
        $resultado = & $sqlcmd -S $serverArg -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASS -i $tmpSql 2>&1
        $exitCode  = $LASTEXITCODE
        $resultado | ForEach-Object { if ($_.Trim() -ne '') { Write-Info $_ } }
        if ($exitCode -ne 0) {
            Write-Warn "sqlcmd retornou erro (codigo $exitCode). Verifique as mensagens acima."
            Write-Info "Se preferir, execute criar-usuario.sql manualmente no SSMS."
        } else {
            Write-OK "Usuario '$SQL_USER' criado/atualizado no banco '$dbName'."
        }
    } finally {
        Remove-Item $tmpSql -ErrorAction SilentlyContinue
    }
}
Write-Info "Script SQL salvo em: criar-usuario.sql"

# ── PASSO 6: Porta e .env ─────────────────────────────────────────────────────
Write-Step 6 "Preparando configuracao"

try {
    $conns = Get-NetTCPConnection -LocalPort ([int]$bridgePort) -State Listen -ErrorAction SilentlyContinue
    if ($conns) {
        $proc = Get-Process -Id $conns[0].OwningProcess -ErrorAction SilentlyContinue
        $procNome = if ($proc) { $proc.Name } else { "PID $($conns[0].OwningProcess)" }
        Write-Warn "Porta $bridgePort em uso por '$procNome'."
        $outra = Read-Host (Write-Prompt "Informe outra porta (ou Enter para continuar mesmo assim)")
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
Write-OK ".env criado  (usuario: $SQL_USER)."

$gi = Join-Path $BridgeDir ".gitignore"
if (Test-Path $gi) {
    $giContent = Get-Content $gi -Raw
    if ($giContent -notmatch '(^|\n)\.env(\r|\n|$)') { Add-Content $gi "`n.env" }
}

# ── PASSO 7: Inicializacao automatica ────────────────────────────────────────
Write-Step 7 "Configurando inicializacao automatica"

$autoStartMode   = 'Manual - use iniciar-bridge.ps1'
$autoStartShort  = 'Manual'

if (-not $nodeFull) {
    Write-Warn "node.exe nao localizado - startup automatico nao configurado."
} else {
    $nodePerUser      = $nodeFull.ToLower().Contains($env:LOCALAPPDATA.ToLower())
    $useSystemAccount = $isAdmin -and (-not $nodePerUser)

    if ($isAdmin -and $nodePerUser) {
        Write-Warn "Node.js esta na pasta do usuario - SYSTEM nao teria acesso."
        Write-Info "Para startup sem login: winget install OpenJS.NodeJS.LTS --scope machine"
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
            $autoStartMode  = 'SYSTEM - inicia com o Windows, sem login necessario'
            $autoStartShort = 'SYSTEM (sem login)'
            Write-OK "Tarefa criada como SYSTEM - inicia com o Windows."
            Write-Info "Reinicia automaticamente em falha (ate 3x, intervalo 2 min)."
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
            $autoStartMode  = "Login do usuario $env:USERNAME"
            $autoStartShort = "Login do usuario"
            Write-OK "Tarefa criada para $env:USERNAME."
            Write-Warn "Para startup sem login, execute LCBRIDGE-INSTALL.exe como Administrador."
        }
    } catch {
        Write-Warn "Nao foi possivel criar tarefa: $_ - use iniciar-bridge.ps1 manualmente."
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
    $env:DB_HOST = $dbHost; $env:DB_PORT = $dbPort
    $env:DB_NAME = $dbName; $env:DB_USER = $SQL_USER
    $env:DB_PASS = $SQL_PASS; $env:PORT  = $bridgePort

    try {
        Start-Process -FilePath $nodeFull `
            -ArgumentList "bridge.js" `
            -WorkingDirectory $BridgeDir `
            -WindowStyle Hidden
    } catch {
        Write-Warn "Nao foi possivel iniciar a bridge automaticamente: $_"
    }

    Start-Sleep -Seconds 3

    try {
        $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method GET -TimeoutSec 5
        if ($health.ok) {
            Write-OK "Bridge online  (banco: $($health.db))."
            $testeOk = $true
        }
    } catch {
        Write-Warn "Bridge nao respondeu ao health check."
    }

    if ($testeOk) {
        $queryPadrao = "SELECT TOP 1 vedId FROM venda"
        Write-Host "  │" -ForegroundColor DarkCyan
        $customQ = Read-Host (Write-Prompt "Query de teste  [$queryPadrao]  (Enter para padrao)")
        if ($customQ.Trim() -ne '') { $queryPadrao = $customQ.Trim() }

        try {
            $headers   = @{ Authorization = "Bearer $novoToken"; 'Content-Type' = 'application/json' }
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(("{""sql"":""{0}""}" -f ($queryPadrao -replace '"', '\"')))
            $resp      = Invoke-RestMethod -Uri "$baseUrl/query" -Method POST `
                         -Headers $headers -Body $bodyBytes -TimeoutSec 15
            if ($null -ne $resp.rows) {
                Write-OK "SQL Server acessivel - $($resp.rows.Count) linha(s) retornada(s)."
                $sqlOk = $true
            }
        } catch {
            $sc = $null; try { $sc = $_.Exception.Response.StatusCode.value__ } catch {}
            $eb = '';    try { $eb = $_.ErrorDetails.Message } catch {}
            $sqlErro = switch ($sc) {
                401 { "Token invalido" }
                403 { "Query bloqueada - verifique se e um SELECT puro" }
                500 {
                    if     ($eb -match 'Login failed')         { "Login SQL recusado - usuario ou senha incorretos" }
                    elseif ($eb -match 'Cannot open database') { "Banco '$dbName' nao encontrado no SQL Server" }
                    elseif ($eb -match 'Invalid object')       { "Tabela nao encontrada - verifique o nome do banco" }
                    elseif ($eb -match 'network-related')      { "SQL Server inacessivel - verifique DB_HOST e firewall" }
                    elseif ($eb -match 'Timeout')              { "Timeout - SQL Server lento ou fora do ar" }
                    else                                       { "Erro SQL: $eb" }
                }
                default { "Bridge nao respondeu" }
            }
            Write-Warn "Teste falhou: $sqlErro"
        }
    }
}

# ── Resultado ─────────────────────────────────────────────────────────────────
$data = Get-Date -Format "dd/MM/yyyy HH:mm"

$statusText = if ($testeOk -and $sqlOk) { "INSTALACAO CONCLUIDA COM SUCESSO!" }
              elseif ($testeOk)          { "Bridge online - SQL com aviso (veja acima)" }
              else                       { "Instalacao com pendencias (veja avisos acima)" }

$statusColor = if ($testeOk -and $sqlOk) { 'Green' } elseif ($testeOk) { 'Yellow' } else { 'Red' }

function Write-ResultRow($lbl, $val) {
    $content = "  " + $lbl.PadRight(20) + ":  " + $val
    Write-BoxRow $content.PadRight($W)
}

Write-Host ""
Write-BoxTop
Write-BoxRow (Center-Text $statusText $W) $statusColor
Write-BoxDiv
Write-ResultRow "Banco"             $dbName
Write-ResultRow "Porta bridge"      $bridgePort
Write-ResultRow "Usuario SQL"       $SQL_USER
Write-ResultRow "Auto-inicio"       $autoStartShort
Write-ResultRow "Data"              $data
Write-BoxDiv
Write-BoxRow "  TOKEN DE SEGURANCA" 'Yellow'
Write-BoxRow "  $novoToken" 'White'
Write-BoxBot
Write-Host ""

$copiar = Read-Host "  Copiar token para a area de transferencia? [S/N]"
if ($copiar -match '^[Ss]') {
    try { $novoToken | Set-Clipboard; Write-Host "  Token copiado." -ForegroundColor Green }
    catch { Write-Host "  Nao foi possivel copiar. Copie manualmente acima." -ForegroundColor Yellow }
}

# ── Cloudflare ────────────────────────────────────────────────────────────────
$slugCliente = ($clienteNome -replace '[^a-zA-Z0-9]', '-' -replace '-+', '-' -replace '^-|-$', '').ToLower()
if (-not $slugCliente) { $slugCliente = 'nomecliente' }

$cfUrl = "https://sql-$slugCliente.lcgestor.com.br"

Write-Host ""
Write-BoxTop 'DarkCyan'
Write-BoxRow (Center-Text "PROXIMO PASSO - Cloudflare Tunnel" $W) 'Cyan' 'DarkCyan'
Write-BoxDiv 'DarkCyan'
Write-BoxRow "  1. Acesse: one.dash.cloudflare.com" 'Gray' 'DarkCyan'
Write-BoxRow "     Zero Trust > Networks > Tunnels > [cliente] > Edit" 'DarkGray' 'DarkCyan'
Write-BoxRow "     Public Hostname > Add a public hostname" 'DarkGray' 'DarkCyan'
Write-BoxDiv 'DarkCyan'
Write-BoxRow "  2. Preencha os campos:" 'White' 'DarkCyan'
Write-BoxRow ("     Subdomain  :  sql-" + $slugCliente) 'Yellow' 'DarkCyan'
Write-BoxRow "     Domain     :  lcgestor.com.br" 'Yellow' 'DarkCyan'
Write-BoxRow "     Type       :  HTTP" 'Yellow' 'DarkCyan'
Write-BoxRow "     URL        :  localhost:$bridgePort" 'Yellow' 'DarkCyan'
Write-BoxDiv 'DarkCyan'
Write-BoxRow "  3. Cadastre no painel LC Gestor:" 'White' 'DarkCyan'
Write-BoxRow "     URL    :  $cfUrl" 'Yellow' 'DarkCyan'
Write-BoxRow "     Token  :  (o token exibido acima)" 'Yellow' 'DarkCyan'
Write-BoxBot 'DarkCyan'

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
URL Cloudflare:      $cfUrl
Auto-inicio:         $autoStartMode
Teste:               $(if ($sqlOk) { 'OK' } elseif ($testeOk) { 'Bridge OK / SQL com aviso' } else { 'Verificar' })
Data de instalacao:  $data

IMPORTANTE: O token de seguranca NAO esta neste arquivo.
Ele esta no arquivo .env e foi exibido na tela durante a instalacao.
Cadastre o token no painel Supabase do LC Gestor.
"@

[System.IO.File]::WriteAllText($SummaryFile, $summary, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "  Resumo salvo em: configuracao-cliente.txt (sem token)" -ForegroundColor DarkGray
Write-Host ""
Read-Host "  Pressione Enter para sair"
