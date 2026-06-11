# build-exe.ps1
# Gera INSTALAR.exe a partir de instalar.ps1 usando o modulo ps2exe.
# Execute este script UMA VEZ no computador de desenvolvimento sempre que
# quiser publicar uma nova versao do instalador.
#
# Requisito: acesso a internet na primeira execucao (instala ps2exe da PSGallery).
# O INSTALAR.exe gerado e auto-suficiente e exige UAC ao ser executado.

#Requires -Version 5.1
Set-StrictMode -Off
Set-Location $PSScriptRoot

$InputFile  = Join-Path $PSScriptRoot "instalar.ps1"
$OutputFile = Join-Path $PSScriptRoot "LCBRIDGE-INSTALL.exe"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   LC Gestor -- Build do INSTALAR.exe     " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar instalar.ps1
if (-not (Test-Path $InputFile)) {
    Write-Host "ERRO: instalar.ps1 nao encontrado." -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

# 2. Instalar ps2exe se necessario
Write-Host "[1/3] Verificando modulo ps2exe..." -ForegroundColor Cyan
$ps2exe = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue
if (-not $ps2exe) {
    Write-Host "   Instalando ps2exe (requer internet)..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "   OK: ps2exe instalado." -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "   ERRO: nao foi possivel instalar ps2exe: $_" -ForegroundColor Red
        Write-Host "   Tente manualmente:" -ForegroundColor Yellow
        Write-Host "   Install-Module -Name ps2exe -Scope CurrentUser -Force" -ForegroundColor White
        Read-Host "Pressione Enter para sair"
        exit 1
    }
} else {
    Write-Host "   OK: ps2exe ja instalado." -ForegroundColor Green
}

# 3. Compilar
Write-Host "[2/3] Compilando instalar.ps1 -> INSTALAR.exe..." -ForegroundColor Cyan
try {
    Invoke-ps2exe `
        -InputFile   $InputFile `
        -OutputFile  $OutputFile `
        -requireAdmin `
        -title       "LC Gestor - Instalador Bridge SQL" `
        -description "Instala a lc-sql-bridge na maquina do cliente" `
        -company     "LC Tecnologias" `
        -product     "LC Gestor Bridge" `
        -version     "1.1.0"

    if (Test-Path $OutputFile) {
        $sizeMB = [math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
        Write-Host "   OK: INSTALAR.exe gerado ($sizeMB MB)" -ForegroundColor Green
    } else {
        Write-Host "   AVISO: arquivo nao encontrado apos compilacao." -ForegroundColor Yellow
    }
} catch {
    Write-Host ""
    Write-Host "   ERRO na compilacao: $_" -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

# 4. Resumo
Write-Host "[3/3] Pronto!" -ForegroundColor Green
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Distribua estes arquivos para o cliente:" -ForegroundColor White
Write-Host ""
Write-Host "  LCBRIDGE-INSTALL.exe   <- duplo clique para instalar" -ForegroundColor Yellow
Write-Host "  bridge.js" -ForegroundColor White
Write-Host "  package.json" -ForegroundColor White
Write-Host "  iniciar-bridge.ps1" -ForegroundColor White
Write-Host "  testar-bridge.ps1" -ForegroundColor White
Write-Host "  desinstalar-bridge.ps1" -ForegroundColor White
Write-Host "  LEIA-ME.txt" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione Enter para sair"
