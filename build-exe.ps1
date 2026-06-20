# build-exe.ps1
# Gera LCBRIDGE-INSTALL.exe e o pacote ZIP para distribuicao ao tecnico.
# Execute sempre que quiser publicar nova versao do instalador.
#
# Requisito: acesso a internet na primeira execucao (instala ps2exe da PSGallery).
# O LCBRIDGE-INSTALL.exe gerado e auto-suficiente e exige UAC ao ser executado.

#Requires -Version 5.1
Set-StrictMode -Off
Set-Location $PSScriptRoot

$InputFile  = Join-Path $PSScriptRoot "instalar.ps1"
$OutputFile = Join-Path $PSScriptRoot "LCBRIDGE-INSTALL.exe"
$PngFile    = Join-Path $PSScriptRoot "lc-logo.png"
$IcoFile    = Join-Path $PSScriptRoot "lc-logo.ico"
$ZipFile    = Join-Path $PSScriptRoot "LC-Bridge-Tecnico.zip"

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
Write-Host "[1/4] Verificando modulo ps2exe..." -ForegroundColor Cyan
$ps2exe = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue
if (-not $ps2exe) {
    Write-Host "   Instalando ps2exe (requer internet)..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "   OK: ps2exe instalado." -ForegroundColor Green
    } catch {
        Write-Host "   ERRO: nao foi possivel instalar ps2exe: $_" -ForegroundColor Red
        Read-Host "Pressione Enter para sair"
        exit 1
    }
} else {
    Write-Host "   OK: ps2exe ja instalado." -ForegroundColor Green
}

# 3. Converter lc-logo.png -> lc-logo.ico (se PNG presente)
$iconParam = $null
if (Test-Path $PngFile) {
    Write-Host "[2/4] Convertendo lc-logo.png -> lc-logo.ico..." -ForegroundColor Cyan
    try {
        Add-Type -AssemblyName System.Drawing

        function Convert-PngToIco([string]$src, [string]$dst) {
            $sizes = @(256, 48, 32, 16)
            $chunks = @{}
            foreach ($sz in $sizes) {
                $orig = [System.Drawing.Image]::FromFile($src)
                $bmp  = New-Object System.Drawing.Bitmap $sz, $sz
                $g    = [System.Drawing.Graphics]::FromImage($bmp)
                $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.Clear([System.Drawing.Color]::Transparent)
                $g.DrawImage($orig, 0, 0, $sz, $sz)
                $g.Dispose(); $orig.Dispose()
                $ms = New-Object System.IO.MemoryStream
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                $chunks[$sz] = $ms.ToArray()
                $ms.Dispose()
            }
            $out = New-Object System.IO.MemoryStream
            $bw  = New-Object System.IO.BinaryWriter($out)
            $bw.Write([uint16]0)
            $bw.Write([uint16]1)
            $bw.Write([uint16]$sizes.Count)
            $offset = [uint32](6 + $sizes.Count * 16)
            foreach ($sz in $sizes) {
                $d  = $chunks[$sz]
                if ($sz -lt 256) { $wh = [byte]$sz } else { $wh = [byte]0 }
                $bw.Write($wh); $bw.Write($wh)
                $bw.Write([byte]0); $bw.Write([byte]0)
                $bw.Write([uint16]0); $bw.Write([uint16]32)
                $bw.Write([uint32]$d.Length)
                $bw.Write($offset)
                $offset += [uint32]$d.Length
            }
            foreach ($sz in $sizes) { $bw.Write($chunks[$sz]) }
            $bw.Flush()
            [System.IO.File]::WriteAllBytes($dst, $out.ToArray())
            $bw.Dispose(); $out.Dispose()
        }

        Convert-PngToIco $PngFile $IcoFile
        Write-Host "   OK: lc-logo.ico gerado." -ForegroundColor Green
        $iconParam = $IcoFile
    } catch {
        Write-Host "   AVISO: falha ao converter icone: $_" -ForegroundColor Yellow
        Write-Host "   O .exe sera gerado sem icone personalizado." -ForegroundColor Yellow
    }
} else {
    Write-Host "[2/4] lc-logo.png nao encontrado - .exe sem icone personalizado." -ForegroundColor Yellow
}

# 4. Garantir UTF-8 BOM no instalar.ps1
$bom = [System.IO.File]::ReadAllBytes($InputFile)
if (-not ($bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF)) {
    $content = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($InputFile, $content, [System.Text.UTF8Encoding]::new($true))
    Write-Host "   BOM UTF-8 adicionado ao instalar.ps1" -ForegroundColor Yellow
}

# 5. Compilar
Write-Host "[3/4] Compilando instalar.ps1 -> LCBRIDGE-INSTALL.exe..." -ForegroundColor Cyan
try {
    $ps2exeArgs = @{
        InputFile   = $InputFile
        OutputFile  = $OutputFile
        requireAdmin = $true
        noConsole   = $true
        title       = "LC Gestor - Instalador Bridge SQL"
        description = "Instala a lc-sql-bridge na maquina do cliente"
        company     = "LC Tecnologias"
        product     = "LC Gestor Bridge"
        version     = "1.2.0"
    }
    if ($null -ne $iconParam) { $ps2exeArgs['iconFile'] = $iconParam }
    Invoke-ps2exe @ps2exeArgs

    if (Test-Path $OutputFile) {
        $sizeMB = [math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
        Write-Host "   OK: LCBRIDGE-INSTALL.exe gerado ($sizeMB MB)" -ForegroundColor Green
    } else {
        Write-Host "   AVISO: arquivo nao encontrado apos compilacao." -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ERRO na compilacao: $_" -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

# 6. Gerar ZIP do pacote do tecnico
Write-Host "[4/4] Gerando pacote ZIP para tecnico..." -ForegroundColor Cyan
$zipFiles = @(
    @{ Name = 'LCBRIDGE-INSTALL.exe'; Required = $true }
    @{ Name = 'bridge.js';            Required = $true }
    @{ Name = 'package.json';         Required = $true }
    @{ Name = 'LEIA-ME.txt';          Required = $false }
)

$missing = $zipFiles | Where-Object { $_.Required -and -not (Test-Path (Join-Path $PSScriptRoot $_.Name)) }
if ($missing) {
    Write-Host "   AVISO: arquivos obrigatorios nao encontrados:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "   - $($_.Name)" -ForegroundColor Yellow }
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipFile, 'Create')
    foreach ($f in $zipFiles) {
        $full = Join-Path $PSScriptRoot $f.Name
        if (Test-Path $full) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $full, $f.Name) | Out-Null
            Write-Host "   + $($f.Name)" -ForegroundColor Gray
        }
    }
    $zip.Dispose()

    $sizeKB = [math]::Round((Get-Item $ZipFile).Length / 1KB, 0)
    Write-Host "   OK: LC-Bridge-Tecnico.zip gerado ($sizeKB KB)" -ForegroundColor Green
} catch {
    Write-Host "   ERRO ao gerar ZIP: $_" -ForegroundColor Red
}

# [+] Gerar pacote OfflineNode (apenas se vendor\node\ estiver presente)
$VendorNodeExe = Join-Path $PSScriptRoot "vendor\node\node.exe"
$VendorNpmCli  = Join-Path $PSScriptRoot "vendor\node\node_modules\npm\bin\npm-cli.js"
$ZipOffline    = Join-Path $PSScriptRoot "LC-Bridge-Tecnico-OfflineNode.zip"
$offlineGerado = $false

if ((Test-Path $VendorNodeExe) -and (Test-Path $VendorNpmCli)) {
    Write-Host ""
    Write-Host "[+] Node portátil encontrado: gerando pacote OfflineNode..." -ForegroundColor Cyan
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        if (Test-Path $ZipOffline) { Remove-Item $ZipOffline -Force }
        $zipOff = [System.IO.Compression.ZipFile]::Open($ZipOffline, 'Create')

        foreach ($f in $zipFiles) {
            $full = Join-Path $PSScriptRoot $f.Name
            if (Test-Path $full) {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipOff, $full, $f.Name) | Out-Null
                Write-Host "   + $($f.Name)" -ForegroundColor Gray
            }
        }

        $vendorNodeDir = Join-Path $PSScriptRoot "vendor\node"
        $allVendorFiles = Get-ChildItem $vendorNodeDir -Recurse -File
        Write-Host "   + vendor\node\ ($($allVendorFiles.Count) arquivos)..." -ForegroundColor Gray
        foreach ($file in $allVendorFiles) {
            $relPath = $file.FullName.Substring($PSScriptRoot.Length).TrimStart('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipOff, $file.FullName, $relPath) | Out-Null
        }

        $zipOff.Dispose()
        $sizeMBOff = [math]::Round((Get-Item $ZipOffline).Length / 1MB, 1)
        Write-Host "   OK: LC-Bridge-Tecnico-OfflineNode.zip gerado ($sizeMBOff MB)" -ForegroundColor Green
        $offlineGerado = $true
    } catch {
        if ($null -ne $zipOff) { try { $zipOff.Dispose() } catch {} }
        Write-Host "   ERRO ao gerar pacote OfflineNode: $_" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "[+] vendor\node\ nao encontrado - pacote OfflineNode nao gerado." -ForegroundColor Yellow
    if (-not (Test-Path $VendorNodeExe)) {
        Write-Host "    Para habilitar: coloque node.exe em vendor\node\ e node_modules\npm\ ao lado." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Pronto! Pacotes gerados:" -ForegroundColor White
Write-Host ""
Write-Host "  LC-Bridge-Tecnico.zip" -ForegroundColor Yellow
Write-Host "    Clientes com internet: Node via winget" -ForegroundColor Gray
if ($offlineGerado) {
    Write-Host ""
    Write-Host "  LC-Bridge-Tecnico-OfflineNode.zip" -ForegroundColor Yellow
    Write-Host "    Clientes RDP/sem winget: Node portátil embutido" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Conteudo base dos dois pacotes:" -ForegroundColor White
Write-Host "    LCBRIDGE-INSTALL.exe  <- duplo clique para instalar" -ForegroundColor Gray
Write-Host "    bridge.js" -ForegroundColor Gray
Write-Host "    package.json" -ForegroundColor Gray
Write-Host "    LEIA-ME.txt" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione Enter para sair"
