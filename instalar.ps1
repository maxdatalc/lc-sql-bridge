# instalar.ps1  - LC Gestor Bridge SQL Installer  v1.2  (WinForms)
#Requires -Version 5.1
Set-StrictMode -Off

# ── Working directory ─────────────────────────────────────────────────────────
$BridgeDir = if ($PSScriptRoot -and ($PSScriptRoot -ne '')) {
    $PSScriptRoot
} else {
    Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
Set-Location $BridgeDir

# ── Constants ─────────────────────────────────────────────────────────────────
$SvcName        = 'LCGestorSQLBridge'
$EnvFile        = Join-Path $BridgeDir '.env'
$BridgeFile     = Join-Path $BridgeDir 'bridge.js'
$PackageFile    = Join-Path $BridgeDir 'package.json'
$SummaryFile    = Join-Path $BridgeDir 'configuracao-cliente.txt'
$SQL_USER       = 'lc_dashboard'
$SQL_PASS       = 'Max@1225'
$SQL_ADMIN_USER = 'sa'
$SQL_ADMIN_PASS = 'macro01'

# ── WinForms ──────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ── Color palette ─────────────────────────────────────────────────────────────
$cHdrBg     = [System.Drawing.Color]::FromArgb(13,  71,  161)   # blue-900
$cHdrSub    = [System.Drawing.Color]::FromArgb(187, 222, 251)   # blue-100
$cAccent    = [System.Drawing.Color]::FromArgb(25,  118, 210)   # blue-700
$cBg        = [System.Drawing.Color]::FromArgb(248, 250, 252)
$cCard      = [System.Drawing.Color]::White
$cText      = [System.Drawing.Color]::FromArgb(15,  23,  42)
$cMuted     = [System.Drawing.Color]::FromArgb(100, 116, 139)
$cBorder    = [System.Drawing.Color]::FromArgb(226, 232, 240)
$cGreen     = [System.Drawing.Color]::FromArgb(22,  163, 74)
$cAmber     = [System.Drawing.Color]::FromArgb(217, 119, 6)
$cRed       = [System.Drawing.Color]::FromArgb(220, 38,  38)
$cLogBg     = [System.Drawing.Color]::FromArgb(15,  23,  42)
$cLogNorm   = [System.Drawing.Color]::FromArgb(203, 213, 225)
$cLogOk     = [System.Drawing.Color]::FromArgb(74,  222, 128)
$cLogWarn   = [System.Drawing.Color]::FromArgb(251, 191, 36)
$cLogErr    = [System.Drawing.Color]::FromArgb(252, 165, 165)
$cTokenBg   = [System.Drawing.Color]::FromArgb(240, 253, 244)
$cTokenFg   = [System.Drawing.Color]::FromArgb(21,  128, 61)
$cInfoBg    = [System.Drawing.Color]::FromArgb(239, 246, 255)
$cSlate100  = [System.Drawing.Color]::FromArgb(241, 245, 249)
$cSlate700  = [System.Drawing.Color]::FromArgb(51,  65,  85)
$cWhite     = [System.Drawing.Color]::White

# ── Fonts ─────────────────────────────────────────────────────────────────────
$fH1    = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$fH2    = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$fBold  = New-Object System.Drawing.Font('Segoe UI', 9,  [System.Drawing.FontStyle]::Bold)
$fBody  = New-Object System.Drawing.Font('Segoe UI', 9)
$fSmall = New-Object System.Drawing.Font('Segoe UI', 8)
$fHSub  = New-Object System.Drawing.Font('Segoe UI', 9)
$fInput = New-Object System.Drawing.Font('Segoe UI', 10)
$fMono  = New-Object System.Drawing.Font('Consolas', 9)
$fToken = New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold)

# ── Shared state ──────────────────────────────────────────────────────────────
$script:IsReinstall    = Test-Path $EnvFile
$script:Token          = ''
$script:Slug           = 'cliente'
$script:BridgePort     = '3055'
$script:NodeFull       = $null
$script:ActiveStep     = -1
$script:SpinFrame      = 0
$script:StepLabels     = @()
$script:SpinChars      = @('-', '+', 'x', '+')
$script:UninstallMode  = $false
$script:RemovedItems   = @()
$script:copyResetTimer = $null
$script:LogFile        = Join-Path $BridgeDir 'install-log.txt'

$script:StepNames = @(
    'Verificando ambiente',
    'Verificando Node.js',
    'Instalando dependencias',
    'Configurando usuario SQL',
    'Criando arquivo .env',
    'Registrando servico Windows',
    'Testando conexao'
)

# ── Helpers ───────────────────────────────────────────────────────────────────

function Invoke-Proc([string]$Exe, [string]$Arguments = '', [string]$Dir = $BridgeDir, [int]$TimeoutSec = 120) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName                = $Exe
    $psi.Arguments               = $Arguments
    $psi.WorkingDirectory        = $Dir
    $psi.UseShellExecute         = $false
    $psi.RedirectStandardOutput  = $true
    $psi.RedirectStandardError   = $true
    $psi.RedirectStandardInput   = $true
    $psi.CreateNoWindow          = $true

    try { $proc = [System.Diagnostics.Process]::Start($psi) } catch { $proc = $null }

    if ($null -eq $proc) {
        return [PSCustomObject]@{ ExitCode = -1; Out = ''; Err = "Falha ao iniciar processo: $Exe" }
    }

    try { $proc.StandardInput.Close() } catch {}
    $ot = $proc.StandardOutput.ReadToEndAsync()
    $et = $proc.StandardError.ReadToEndAsync()

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while (-not $proc.WaitForExit(100)) {
        [System.Windows.Forms.Application]::DoEvents()
        if ((Get-Date) -gt $deadline) {
            try { $proc.Kill() } catch { }
            break
        }
    }
    # Aguarda leitura dos streams com timeout de 10s para nao travar apos kill
    [System.Threading.Tasks.Task]::WaitAll(@($ot, $et), 10000) | Out-Null

    return [PSCustomObject]@{
        ExitCode = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
        Out      = if ($ot.IsCompleted) { $ot.Result } else { '' }
        Err      = if ($et.IsCompleted) { $et.Result } else { '' }
    }
}

function New-Lbl([System.Windows.Forms.Control]$p, $t, $x, $y, $w, $h,
                 $font = $fBody, $color = $null, $align = 'MiddleLeft') {
    $l            = New-Object System.Windows.Forms.Label
    $l.Text       = $t
    $l.Location   = [System.Drawing.Point]::new($x, $y)
    $l.Size       = [System.Drawing.Size]::new($w, $h)
    $l.Font       = $font
    $l.ForeColor  = if ($color) { $color } else { $cText }
    $l.BackColor  = [System.Drawing.Color]::Transparent
    $l.TextAlign  = [System.Drawing.ContentAlignment]::$align
    $l.AutoEllipsis = $false
    $p.Controls.Add($l)
    return $l
}

function New-Btn([System.Windows.Forms.Control]$p, $t, $x, $y, $w = 120, $h = 36, $primary = $true) {
    $b            = New-Object System.Windows.Forms.Button
    $b.Text       = $t
    $b.Location   = [System.Drawing.Point]::new($x, $y)
    $b.Size       = [System.Drawing.Size]::new($w, $h)
    $b.Font       = $fBold
    $b.FlatStyle  = [System.Windows.Forms.FlatStyle]::Flat
    $b.Cursor     = [System.Windows.Forms.Cursors]::Hand
    if ($primary) {
        $b.BackColor = $cAccent
        $b.ForeColor = $cWhite
        $b.FlatAppearance.BorderSize          = 0
        $b.FlatAppearance.MouseOverBackColor  = $cHdrBg
    } else {
        $b.BackColor = $cSlate100
        $b.ForeColor = $cSlate700
        $b.FlatAppearance.BorderSize          = 1
        $b.FlatAppearance.BorderColor         = $cBorder
        $b.FlatAppearance.MouseOverBackColor  = $cBorder
    }
    $p.Controls.Add($b)
    return $b
}

function New-Input([System.Windows.Forms.Control]$p, $x, $y, $w, $def = '') {
    $tb             = New-Object System.Windows.Forms.TextBox
    $tb.Location    = [System.Drawing.Point]::new($x, $y)
    $tb.Size        = [System.Drawing.Size]::new($w, 28)
    $tb.Font        = $fInput
    $tb.BackColor   = $cCard
    $tb.ForeColor   = $cText
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    if ($def -ne '') { $tb.Text = $def }
    $p.Controls.Add($tb)
    return $tb
}

function New-Card([System.Windows.Forms.Control]$p, $x, $y, $w, $h) {
    $c              = New-Object System.Windows.Forms.Panel
    $c.Location     = [System.Drawing.Point]::new($x, $y)
    $c.Size         = [System.Drawing.Size]::new($w, $h)
    $c.BackColor    = $cCard
    $c.BorderStyle  = [System.Windows.Forms.BorderStyle]::FixedSingle
    $p.Controls.Add($c)
    return $c
}

# ── FORM ──────────────────────────────────────────────────────────────────────
$form                   = New-Object System.Windows.Forms.Form
$form.Text              = 'LC Gestor  - Instalador Bridge SQL'
$form.ClientSize        = [System.Drawing.Size]::new(520, 620)
$form.StartPosition     = 'CenterScreen'
$form.FormBorderStyle   = 'FixedSingle'
$form.MaximizeBox       = $false
$form.BackColor         = $cBg
$form.Icon              = [System.Drawing.SystemIcons]::Application

# ── HEADER ────────────────────────────────────────────────────────────────────
$pHdr               = New-Object System.Windows.Forms.Panel
$pHdr.Dock          = 'Top'
$pHdr.Height        = 78
$pHdr.BackColor     = $cHdrBg
$form.Controls.Add($pHdr)

New-Lbl $pHdr 'LC GESTOR' 22 8 260 42 $fH1 $cWhite 'MiddleLeft' | Out-Null
New-Lbl $pHdr 'Bridge SQL Installer  v1.2' 24 50 280 22 $fHSub $cHdrSub 'MiddleLeft' | Out-Null

# ── FOOTER ────────────────────────────────────────────────────────────────────
$pFtr               = New-Object System.Windows.Forms.Panel
$pFtr.Dock          = 'Bottom'
$pFtr.Height        = 58
$pFtr.BackColor     = $cCard

$pFtrLine           = New-Object System.Windows.Forms.Panel
$pFtrLine.Dock      = 'Top'
$pFtrLine.Height    = 1
$pFtrLine.BackColor = $cBorder
$pFtr.Controls.Add($pFtrLine)

$form.Controls.Add($pFtr)

$btnCancel  = New-Btn $pFtr 'Cancelar'    12  11 110 36 $false
$btnBack    = New-Btn $pFtr '← Voltar'    12  11 110 36 $false
$btnNext    = New-Btn $pFtr 'Proximo →'  388  11 108 36 $true
$btnInstall = New-Btn $pFtr 'Instalar'   388  11 108 36 $true
$btnClose   = New-Btn $pFtr 'Fechar'     388  11 108 36 $true
$btnCopy    = New-Btn $pFtr 'Copiar Token' 258 11 130 36 $false

# ── CONTENT CONTAINER ────────────────────────────────────────────────────────
$pContent           = New-Object System.Windows.Forms.Panel
$pContent.Location  = [System.Drawing.Point]::new(0, 78)
$pContent.Size      = [System.Drawing.Size]::new(520, 484)
$pContent.BackColor = $cBg
$form.Controls.Add($pContent)

# ════════════════════════════════════════════════════════════════════════════
# PAGE 1  - WELCOME
# ════════════════════════════════════════════════════════════════════════════
$pgWelcome              = New-Object System.Windows.Forms.Panel
$pgWelcome.Dock         = 'Fill'
$pgWelcome.BackColor    = $cBg
$pContent.Controls.Add($pgWelcome)

New-Lbl $pgWelcome 'Bem-vindo ao instalador' 30 22 440 32 $fH2 $cText 'MiddleLeft' | Out-Null
New-Lbl $pgWelcome 'Este assistente ira configurar a Bridge SQL do LC Gestor nesta maquina.' 30 56 440 22 $fBody $cMuted 'MiddleLeft' | Out-Null

$cardFeat = New-Card $pgWelcome 30 90 456 148
$fi = 0
@(
    'Verifica e instala Node.js automaticamente',
    'Cria usuario SQL lc_dashboard (somente leitura)',
    'Gera token de seguranca exclusivo',
    'Configura inicializacao automatica com o Windows',
    'Testa a conexao ao final da instalacao'
) | ForEach-Object {
    $fy = 14 + $fi * 25
    New-Lbl $cardFeat 'v'  14 $fy  20 22 $fBold $cGreen   'MiddleLeft' | Out-Null
    New-Lbl $cardFeat $_ 36 $fy 410 22 $fBody $cText    'MiddleLeft' | Out-Null
    $fi++
}

# Reinstall card (shown only when .env exists)
$cardReinstall              = New-Card $pgWelcome 30 256 456 152
$cardReinstall.Visible      = $script:IsReinstall
New-Lbl $cardReinstall '! Instalacao existente detectada' 14 10 420 24 $fBold $cAmber 'MiddleLeft' | Out-Null

$rbRepair           = New-Object System.Windows.Forms.RadioButton
$rbRepair.Text      = 'Reparar  (manter .env e token existentes)'
$rbRepair.Location  = [System.Drawing.Point]::new(14, 40)
$rbRepair.Size      = [System.Drawing.Size]::new(420, 22)
$rbRepair.Font      = $fBody
$rbRepair.ForeColor = $cText
$rbRepair.Checked   = $true
$rbRepair.BackColor = $cCard
$cardReinstall.Controls.Add($rbRepair)

$rbReconfig           = New-Object System.Windows.Forms.RadioButton
$rbReconfig.Text      = 'Reconfigurar  (novas configuracoes, token novo opcional)'
$rbReconfig.Location  = [System.Drawing.Point]::new(14, 68)
$rbReconfig.Size      = [System.Drawing.Size]::new(420, 22)
$rbReconfig.Font      = $fBody
$rbReconfig.ForeColor = $cText
$rbReconfig.BackColor = $cCard
$cardReinstall.Controls.Add($rbReconfig)

$rbUninstall          = New-Object System.Windows.Forms.RadioButton
$rbUninstall.Text     = 'Desinstalar  (remove servico, .env, logs e node_modules)'
$rbUninstall.Location = [System.Drawing.Point]::new(14, 96)
$rbUninstall.Size     = [System.Drawing.Size]::new(420, 22)
$rbUninstall.Font     = $fBody
$rbUninstall.ForeColor= $cRed
$rbUninstall.BackColor= $cCard
$cardReinstall.Controls.Add($rbUninstall)

New-Lbl $cardReinstall 'A desinstalacao nao remove bridge.js nem package.json.' 30 124 400 20 $fSmall $cMuted 'MiddleLeft' | Out-Null

# ════════════════════════════════════════════════════════════════════════════
# PAGE 2  - CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════
$pgConfig               = New-Object System.Windows.Forms.Panel
$pgConfig.Dock          = 'Fill'
$pgConfig.BackColor     = $cBg
$pgConfig.Visible       = $false
$pContent.Controls.Add($pgConfig)

New-Lbl $pgConfig 'Configuracao do cliente' 30 22 440 30 $fH2 $cText 'MiddleLeft' | Out-Null
New-Lbl $pgConfig 'Preencha os dados de conexao com o SQL Server.' 30 54 440 22 $fBody $cMuted 'MiddleLeft' | Out-Null

$cardCfg = New-Card $pgConfig 30 88 456 222

function Add-Field([System.Windows.Forms.Control]$panel, $lbl, $x, $y, $w, $def = '', $req = $false) {
    $mark = if ($req) { ' *' } else { '' }
    New-Lbl $panel ($lbl + $mark) $x $y $w 22 $fBold $cMuted 'MiddleLeft' | Out-Null
    return New-Input $panel $x ($y + 24) $w $def
}

$tbDbName   = Add-Field $cardCfg 'Banco de dados'       16  16 422 '' $true
$tbDbHost   = Add-Field $cardCfg 'Host do SQL Server'   16  90 198 'localhost'
$tbDbPort   = Add-Field $cardCfg 'Porta SQL'            228  90 80  '1433'
$tbBridgeP  = Add-Field $cardCfg 'Porta bridge'         322  90 116 '3055'

New-Lbl $pgConfig '* Campo obrigatorio' 30 316 220 20 $fSmall $cMuted 'MiddleLeft' | Out-Null

# ════════════════════════════════════════════════════════════════════════════
# PAGE 3  - PROGRESS
# ════════════════════════════════════════════════════════════════════════════
$pgProgress             = New-Object System.Windows.Forms.Panel
$pgProgress.Dock        = 'Fill'
$pgProgress.BackColor   = $cBg
$pgProgress.Visible     = $false
$pContent.Controls.Add($pgProgress)

$lblProgTitle = New-Lbl $pgProgress 'Instalando...' 30 18 340 28 $fH2 $cText 'MiddleLeft'
$lblProgStep  = New-Lbl $pgProgress ''             30 48 456 20 $fBody $cAccent 'MiddleLeft'

$pb             = New-Object System.Windows.Forms.ProgressBar
$pb.Location    = [System.Drawing.Point]::new(30, 74)
$pb.Size        = [System.Drawing.Size]::new(456, 14)
$pb.Minimum     = 0
$pb.Maximum     = $script:StepNames.Count
$pb.Value       = 0
$pb.Style       = 'Continuous'
$pgProgress.Controls.Add($pb)

# Steps list card
$cardSteps              = New-Card $pgProgress 30 100 214 ($script:StepNames.Count * 30 + 14)
$script:StepLabels      = @()
for ($i = 0; $i -lt $script:StepNames.Count; $i++) {
    $sl = New-Lbl $cardSteps ('  o  ' + $script:StepNames[$i]) 4 (4 + $i * 30) 204 30 $fBody $cMuted 'MiddleLeft'
    $script:StepLabels += $sl
}

# Log area
New-Lbl $pgProgress 'Log' 260 100 226 20 $fBold $cMuted 'MiddleLeft' | Out-Null

$rtbLog             = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = [System.Drawing.Point]::new(260, 122)
$rtbLog.Size        = [System.Drawing.Size]::new(226, ($script:StepNames.Count * 30 + 14 - 22))
$rtbLog.BackColor   = $cLogBg
$rtbLog.ForeColor   = $cLogNorm
$rtbLog.Font        = $fMono
$rtbLog.ReadOnly    = $true
$rtbLog.BorderStyle = 'FixedSingle'
$rtbLog.ScrollBars  = 'Vertical'
$pgProgress.Controls.Add($rtbLog)

# ── Log helper
function Add-Log([string]$msg, [string]$level = 'info') {
    $ts    = Get-Date -Format 'HH:mm:ss'
    $color = switch ($level) {
        'ok'   { $cLogOk   }
        'warn' { $cLogWarn }
        'err'  { $cLogErr  }
        default{ $cLogNorm }
    }
    if ($rtbLog.IsHandleCreated) {
        $rtbLog.SelectionStart  = $rtbLog.TextLength
        $rtbLog.SelectionLength = 0
        $rtbLog.SelectionColor  = $color
        $rtbLog.AppendText("[$ts] $msg`n")
        $rtbLog.ScrollToCaret()
    }
    try {
        $tag = switch ($level) { 'ok' { 'OK  ' }; 'warn' { 'WARN' }; 'err' { 'ERR ' }; default { 'INFO' } }
        Add-Content -Path $script:LogFile -Value "[$ts] [$tag] $msg" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
    [System.Windows.Forms.Application]::DoEvents()
}

# ── Step status helper
function Set-Step([int]$i, [string]$status) {
    $labels = $script:StepLabels
    $names  = $script:StepNames
    if ($null -eq $labels -or $i -lt 0 -or $i -ge $labels.Count) { return }
    $l = $labels[$i]
    if ($null -eq $l) { return }
    $n = if ($null -ne $names -and $i -lt $names.Count) { $names[$i] } else { "Passo $i" }
    try {
        switch ($status) {
            'active' { $l.Text = '  > ' + $n; $l.ForeColor = $cAccent; $l.Font = $fBold  }
            'done'   { $l.Text = '  v ' + $n; $l.ForeColor = $cGreen;  $l.Font = $fBody  }
            'warn'   { $l.Text = '  ! ' + $n; $l.ForeColor = $cAmber;  $l.Font = $fBody  }
            'error'  { $l.Text = '  x ' + $n; $l.ForeColor = $cRed;    $l.Font = $fBody  }
            default  { $l.Text = '  o ' + $n; $l.ForeColor = $cMuted;  $l.Font = $fBody  }
        }
        [System.Windows.Forms.Application]::DoEvents()
    } catch {}
}

# ── Progress bar helper
function Set-Prog([int]$step, [string]$msg = '') {
    $pb.Value        = [Math]::Min($step, $pb.Maximum)
    $lblProgStep.Text = $msg
    [System.Windows.Forms.Application]::DoEvents()
}

# ── Spinner timer (fires during active steps)
$spinTimer          = New-Object System.Windows.Forms.Timer
$spinTimer.Interval = 180
$spinTimer.add_Tick({
    try {
        $labels = $script:StepLabels
        $names  = $script:StepNames
        $i      = $script:ActiveStep
        if ($null -eq $labels -or $null -eq $i -or $i -lt 0 -or $i -ge $labels.Count) { return }
        $lbl = $labels[$i]
        if ($null -eq $lbl) { return }
        $c = $script:SpinChars[$script:SpinFrame % 4]
        $script:SpinFrame++
        $n = if ($null -ne $names -and $i -lt $names.Count) { $names[$i] } else { '' }
        $lbl.Text = "  $c $n"
    } catch {}
})

# ════════════════════════════════════════════════════════════════════════════
# PAGE 4  - COMPLETE
# ════════════════════════════════════════════════════════════════════════════
$pgDone             = New-Object System.Windows.Forms.Panel
$pgDone.Dock        = 'Fill'
$pgDone.BackColor   = $cBg
$pgDone.Visible     = $false
$pContent.Controls.Add($pgDone)

$lblDoneIcon  = New-Lbl $pgDone 'v' 30 18 48 44 $fH1 $cGreen 'MiddleCenter'
$lblDoneTitle = New-Lbl $pgDone 'Instalacao concluida!' 84 18 380 44 $fH2 $cGreen 'MiddleLeft'

# ── Painel de resultado de INSTALACAO ─────────────────────────────────────────
$pInstallResult             = New-Object System.Windows.Forms.Panel
$pInstallResult.Location    = [System.Drawing.Point]::new(0, 70)
$pInstallResult.Size        = [System.Drawing.Size]::new(516, 408)
$pInstallResult.BackColor   = [System.Drawing.Color]::Transparent
$pgDone.Controls.Add($pInstallResult)

New-Lbl $pInstallResult 'Token de seguranca' 30 10 440 22 $fBold $cMuted 'MiddleLeft' | Out-Null

$pTokenBox              = New-Card $pInstallResult 30 34 456 50
$pTokenBox.BackColor    = $cTokenBg

$tbToken                = New-Object System.Windows.Forms.TextBox
$tbToken.Location       = [System.Drawing.Point]::new(10, 8)
$tbToken.Size           = [System.Drawing.Size]::new(348, 32)
$tbToken.Font           = $fToken
$tbToken.BackColor      = $cTokenBg
$tbToken.ForeColor      = $cTokenFg
$tbToken.BorderStyle    = 'None'
$tbToken.ReadOnly       = $true
$tbToken.TabStop        = $false
$pTokenBox.Controls.Add($tbToken)

$btnCopyInline              = New-Object System.Windows.Forms.Button
$btnCopyInline.Location     = [System.Drawing.Point]::new(366, 7)
$btnCopyInline.Size         = [System.Drawing.Size]::new(80, 34)
$btnCopyInline.Text         = 'Copiar'
$btnCopyInline.Font         = $fBold
$btnCopyInline.BackColor    = $cAccent
$btnCopyInline.ForeColor    = $cWhite
$btnCopyInline.FlatStyle    = 'Flat'
$btnCopyInline.FlatAppearance.BorderSize = 0
$btnCopyInline.Cursor       = [System.Windows.Forms.Cursors]::Hand
$pTokenBox.Controls.Add($btnCopyInline)

$btnCopyInline.Add_Click({
    if ($script:Token -ne '') {
        try {
            $script:Token | Set-Clipboard
            $btnCopyInline.Text      = 'Copiado!'
            $btnCopyInline.BackColor = $cGreen
            # $script: garante que o timer seja acessivel no tick handler apos o click handler retornar
            if ($null -ne $script:copyResetTimer) {
                try { $script:copyResetTimer.Stop(); $script:copyResetTimer.Dispose() } catch {}
            }
            $script:copyResetTimer = New-Object System.Windows.Forms.Timer
            $script:copyResetTimer.Interval = 2000
            $script:copyResetTimer.add_Tick({
                try {
                    $btnCopyInline.Text      = 'Copiar'
                    $btnCopyInline.BackColor = $cAccent
                } catch {}
                try { $script:copyResetTimer.Stop(); $script:copyResetTimer.Dispose() } catch {}
                $script:copyResetTimer = $null
            })
            $script:copyResetTimer.Start()
        } catch {}
    }
})

New-Lbl $pInstallResult 'Cadastre este token e a URL no painel admin do LC Gestor.' 30 92 456 20 $fBody $cMuted 'MiddleLeft' | Out-Null

$cardCF             = New-Card $pInstallResult 30 120 456 96
$cardCF.BackColor   = $cInfoBg

New-Lbl $cardCF 'Cloudflare Tunnel  - configure o Public Hostname no OneDash' 14 12 428 22 $fBold $cAccent 'MiddleLeft' | Out-Null
$lblCfFields = New-Lbl $cardCF '' 14 40 428 44 $fMono $cText 'TopLeft'

New-Lbl $pInstallResult 'Log da instalacao' 30 226 440 20 $fBold $cMuted 'MiddleLeft' | Out-Null
$rtbDoneLog             = New-Object System.Windows.Forms.RichTextBox
$rtbDoneLog.Location    = [System.Drawing.Point]::new(30, 250)
$rtbDoneLog.Size        = [System.Drawing.Size]::new(456, 148)
$rtbDoneLog.BackColor   = $cLogBg
$rtbDoneLog.ForeColor   = $cLogNorm
$rtbDoneLog.Font        = $fMono
$rtbDoneLog.ReadOnly    = $true
$rtbDoneLog.BorderStyle = 'FixedSingle'
$rtbDoneLog.ScrollBars  = 'Vertical'
$pInstallResult.Controls.Add($rtbDoneLog)

# ── Painel de resultado de DESINSTALACAO ──────────────────────────────────────
$pUninstResult              = New-Object System.Windows.Forms.Panel
$pUninstResult.Location     = [System.Drawing.Point]::new(0, 70)
$pUninstResult.Size         = [System.Drawing.Size]::new(516, 408)
$pUninstResult.BackColor    = [System.Drawing.Color]::Transparent
$pUninstResult.Visible      = $false
$pgDone.Controls.Add($pUninstResult)

$cardUninstSummary          = New-Card $pUninstResult 30 10 456 120
New-Lbl $cardUninstSummary 'O que foi removido' 14 10 420 22 $fBold $cText 'MiddleLeft' | Out-Null
$lblUninstItems = New-Lbl $cardUninstSummary '' 14 36 428 68 $fMono $cGreen 'TopLeft'

$cardUninstNote             = New-Card $pUninstResult 30 144 456 72
$cardUninstNote.BackColor   = [System.Drawing.Color]::FromArgb(255, 251, 235)
New-Lbl $cardUninstNote '! Mantido intacto' 14 10 420 22 $fBold $cAmber 'MiddleLeft' | Out-Null
New-Lbl $cardUninstNote 'bridge.js, package.json e os scripts .ps1 permanecem na pasta.' 14 34 428 20 $fBody $cMuted 'MiddleLeft' | Out-Null

New-Lbl $pUninstResult 'Pode executar LCBRIDGE-INSTALL.exe novamente para reinstalar.' 30 228 456 22 $fBody $cMuted 'MiddleLeft' | Out-Null

# ════════════════════════════════════════════════════════════════════════════
# NAVIGATION
# ════════════════════════════════════════════════════════════════════════════
$AllPages = @($pgWelcome, $pgConfig, $pgProgress, $pgDone)

function Show-Page([int]$idx) {
    foreach ($pg in $AllPages) { $pg.Visible = $false }
    $AllPages[$idx].Visible = $true

    $btnCancel.Visible  = ($idx -lt 2)
    $btnBack.Visible    = ($idx -eq 1)
    $btnNext.Visible    = ($idx -eq 0)
    $btnInstall.Visible = ($idx -eq 1)
    $btnClose.Visible   = ($idx -eq 3)
    $btnCopy.Visible    = ($idx -eq 3 -and -not $script:UninstallMode)

    # Alterna paineis de conclusao conforme o modo
    if ($idx -eq 3) {
        $pInstallResult.Visible = (-not $script:UninstallMode)
        $pUninstResult.Visible  = $script:UninstallMode
        # Copia o log de instalacao para o painel de conclusao
        if (-not $script:UninstallMode -and $rtbLog.IsHandleCreated) {
            $rtbDoneLog.Rtf = $rtbLog.Rtf
            $rtbDoneLog.SelectionStart = $rtbDoneLog.TextLength
            $rtbDoneLog.ScrollToCaret()
        }
    }

    [System.Windows.Forms.Application]::DoEvents()
}

Show-Page 0

# ════════════════════════════════════════════════════════════════════════════
# INSTALLATION LOGIC
# ════════════════════════════════════════════════════════════════════════════
# UNINSTALL LOGIC
# ════════════════════════════════════════════════════════════════════════════
function Uninstall-Bridge {
    $script:UninstallMode = $true
    $btnNext.Enabled      = $false
    $btnCancel.Enabled    = $false

    # Prepara pagina de progresso para o modo desinstalacao
    $cardSteps.Visible      = $false
    $lblProgTitle.Text      = 'Desinstalando...'
    $lblProgTitle.ForeColor = $cRed
    $lblProgStep.Text       = ''
    $pb.Maximum             = 4
    $pb.Value               = 0

    Add-Log "Desinstalacao da Bridge SQL iniciada."

    # ── Passo 1: Encerrar processo bridge ─────────────────────────────────────
    Set-Prog 1 'Encerrando processo bridge...'
    Add-Log "Procurando node.exe rodando bridge.js..."

    try {
        $nodeProcs = @(Get-Process -Name 'node' -ErrorAction SilentlyContinue)
        $killed = 0
        foreach ($proc in $nodeProcs) {
            try {
                $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
                if ($wmiProc -and $wmiProc.CommandLine -match 'bridge\.js') {
                    $proc.Kill()
                    $killed++
                    Add-Log "Processo encerrado (PID $($proc.Id))." 'ok'
                }
            } catch { }
        }
        if ($killed -eq 0) { Add-Log "Nenhum processo bridge.js em execucao." 'ok' }
    } catch {
        Add-Log "Erro ao encerrar processos: $_" 'warn'
    }
    Start-Sleep -Milliseconds 600
    [System.Windows.Forms.Application]::DoEvents()

    # ── Passo 2: Remover servico e monitor ───────────────────────────────────
    Set-Prog 2 'Removendo servico Windows...'
    Add-Log "Parando e removendo servico '$SvcName'..."

    # Encerra processo do monitor de bandeja (se estiver rodando)
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'bridge-monitor\.ps1' } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
    } catch {}

    # Remove entrada de logon do monitor
    Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'LCGestorBridgeMonitor' -ErrorAction SilentlyContinue

    try {
        sc.exe stop $SvcName 2>&1 | Out-Null
        Start-Sleep -Milliseconds 2000
        sc.exe delete $SvcName 2>&1 | Out-Null
        Add-Log "Servico removido." 'ok'
    } catch {
        Add-Log "Aviso ao remover servico: $_" 'warn'
    }

    # Remove entradas legadas (Task Scheduler e HKLM Run de versoes anteriores)
    schtasks.exe /delete /f /tn 'LC Gestor SQL Bridge' 2>$null | Out-Null
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'LCGestorSQLBridge' -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::DoEvents()

    # ── Passo 3: Remover arquivos de configuracao ─────────────────────────────
    Set-Prog 3 'Removendo arquivos de configuracao...'
    Add-Log "Removendo arquivos gerados pela instalacao..."

    $script:RemovedItems = @()
    $failedItems = @()

    @(
        @{ P = $EnvFile;                                              N = '.env' },
        @{ P = (Join-Path $BridgeDir 'bridge-svc.exe');               N = 'bridge-svc.exe' },
        @{ P = (Join-Path $BridgeDir 'bridge-monitor.ps1');           N = 'bridge-monitor.ps1' },
        @{ P = (Join-Path $BridgeDir 'criar-usuario.sql');            N = 'criar-usuario.sql' },
        @{ P = (Join-Path $BridgeDir 'configuracao-cliente.txt');     N = 'configuracao-cliente.txt' }
    ) | ForEach-Object {
        if (Test-Path $_.P) {
            try {
                Remove-Item $_.P -Force
                $script:RemovedItems += $_.N
                Add-Log "Removido: $($_.N)" 'ok'
            } catch {
                $failedItems += $_.N
                Add-Log "Falha ao remover $($_.N): $_" 'warn'
            }
        }
    }

    $logsDir = Join-Path $BridgeDir 'logs'
    if (Test-Path $logsDir) {
        try {
            Remove-Item $logsDir -Recurse -Force
            $script:RemovedItems += 'pasta logs/'
            Add-Log "Removido: pasta logs/" 'ok'
        } catch {
            $failedItems += 'logs/'
            Add-Log "Falha ao remover logs/: $_" 'warn'
        }
    }

    $nmDir = Join-Path $BridgeDir 'node_modules'
    if (Test-Path $nmDir) {
        Set-Prog 3 'Removendo node_modules (aguarde)...'
        Add-Log "Removendo node_modules/ (pode demorar alguns segundos)..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            Remove-Item $nmDir -Recurse -Force
            $script:RemovedItems += 'node_modules/'
            Add-Log "Removido: node_modules/" 'ok'
        } catch {
            $failedItems += 'node_modules/'
            Add-Log "Falha ao remover node_modules/: $_" 'warn'
        }
    }

    $runtimeDir2 = Join-Path $BridgeDir 'runtime'
    if (Test-Path $runtimeDir2) {
        Set-Prog 3 'Removendo runtime (node portavel)...'
        Add-Log "Removendo runtime/ (node.exe portavel)..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            Remove-Item $runtimeDir2 -Recurse -Force
            $script:RemovedItems += 'runtime/'
            Add-Log "Removido: runtime/" 'ok'
        } catch {
            $failedItems += 'runtime/'
            Add-Log "Falha ao remover runtime/: $_" 'warn'
        }
    }

    # ── Passo 4: Conclusao ────────────────────────────────────────────────────
    Set-Prog 4 'Desinstalacao concluida!'
    Add-Log "Desinstalacao finalizada." 'ok'

    if ($failedItems.Count -gt 0) {
        Add-Log "Itens com falha: $($failedItems -join ', ')" 'warn'
    }

    $lblProgTitle.Text      = 'Desinstalacao concluida!'
    $lblProgTitle.ForeColor = $cGreen

    # Atualiza painel de resultado
    $lblDoneTitle.Text      = 'Desinstalacao concluida!'
    $lblDoneTitle.ForeColor = $cGreen
    $lblDoneIcon.Text       = 'v'

    if ($script:RemovedItems.Count -gt 0) {
        $lblUninstItems.Text = ($script:RemovedItems | ForEach-Object { "  v  $_" }) -join "`n"
    } else {
        $lblUninstItems.Text = '  (nenhum arquivo encontrado)'
    }

    Start-Sleep -Milliseconds 600
    Show-Page 3
}

# ════════════════════════════════════════════════════════════════════════════
# Seleção assistida de banco de dados
# ════════════════════════════════════════════════════════════════════════════
function Show-DbPicker([string]$DbHost, [string]$DbPort) {
    # Retorna: nome do banco selecionado | '' para digitacao manual | $null se indisponivel

    # Localiza sqlcmd
    $sqlcmdBin = $null
    $sc2 = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($sc2) { $sqlcmdBin = $sc2.Source }
    if (-not $sqlcmdBin) {
        foreach ($c in @(
            "${env:ProgramFiles}\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\130\Tools\Binn\sqlcmd.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\120\Tools\Binn\sqlcmd.exe"
        )) { if (Test-Path $c) { $sqlcmdBin = $c; break } }
    }
    if (-not $sqlcmdBin) { return $null }

    $serverArg = if ($DbPort -eq '' -or $DbPort -eq '1433') { $DbHost } else { "$DbHost,$DbPort" }
    $sysNames  = @('master','model','msdb','tempdb')
    $dbs       = @()

    try {
        $q = "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE state_desc='ONLINE' ORDER BY name"
        $r = Invoke-Proc $sqlcmdBin "-S $serverArg -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASS -Q `"$q`" -h -1 -W -l 5 -t 10" -TimeoutSec 20
        if ($r.ExitCode -eq 0) {
            $dbs = ($r.Out -split "`r?`n") |
                   ForEach-Object { $_.Trim() } |
                   Where-Object   { $_ -ne '' -and $_ -notmatch '^[\s\-]+$' -and $_ -notmatch 'rows? affected' }
        }
    } catch {}

    if ($dbs.Count -eq 0) { return $null }

    $userDbs = @($dbs | Where-Object { $sysNames -notcontains $_.ToLower() })
    $sysDbs2 = @($dbs | Where-Object { $sysNames -contains  $_.ToLower() })

    $script:pickerResult = $null

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Selecionar banco de dados'
    $dlg.ClientSize      = [System.Drawing.Size]::new(440, 490)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedSingle'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = $cBg

    $hdrD = New-Object System.Windows.Forms.Panel
    $hdrD.Dock      = 'Top'
    $hdrD.Height    = 60
    $hdrD.BackColor = $cHdrBg
    $dlg.Controls.Add($hdrD)
    New-Lbl $hdrD 'Selecionar banco de dados'       16  8 400 28 $fH2   $cWhite  'MiddleLeft' | Out-Null
    New-Lbl $hdrD "$($dbs.Count) banco(s) em $DbHost" 18 38 400 18 $fSmall $cHdrSub 'MiddleLeft' | Out-Null

    New-Lbl $dlg 'Bancos de dados disponiveis (duplo clique para confirmar):' 20 74 396 20 $fBold $cText 'MiddleLeft' | Out-Null

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location    = [System.Drawing.Point]::new(20, 98)
    $lb.Size        = [System.Drawing.Size]::new(396, 286)
    $lb.Font        = $fBody
    $lb.BackColor   = $cCard
    $lb.ForeColor   = $cText
    $lb.BorderStyle = 'FixedSingle'
    $dlg.Controls.Add($lb)

    foreach ($db in $userDbs) { $lb.Items.Add($db) | Out-Null }
    foreach ($db in $sysDbs2) { $lb.Items.Add("$db  [sistema]") | Out-Null }
    $lb.Items.Add('[ Digitar manualmente ]') | Out-Null
    if ($lb.Items.Count -gt 0) { $lb.SelectedIndex = 0 }

    $lblSel = New-Lbl $dlg '' 20 394 396 24 $fBold $cGreen 'MiddleLeft'

    $lb.add_SelectedIndexChanged({
        $s = if ($lb.SelectedItem) { $lb.SelectedItem.ToString() } else { '' }
        if ($s -eq '[ Digitar manualmente ]') {
            $lblSel.Text      = 'Voce ira preencher o nome do banco manualmente'
            $lblSel.ForeColor = $cAmber
        } elseif ($s -like '*  [sistema]') {
            $lblSel.Text      = 'Selecionado: ' + ($s -replace '  \[sistema\]$','') + '  (banco de sistema)'
            $lblSel.ForeColor = $cAmber
        } elseif ($s -ne '') {
            $lblSel.Text      = "Selecionado: $s"
            $lblSel.ForeColor = $cGreen
        } else {
            $lblSel.Text = ''
        }
    })

    $lb.add_DoubleClick({
        if (-not $lb.SelectedItem) { return }
        $s = $lb.SelectedItem.ToString()
        if ($s -eq '[ Digitar manualmente ]') { $script:pickerResult = '' }
        else { $script:pickerResult = $s -replace '  \[sistema\]$','' }
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $btnConf = New-Btn $dlg 'Confirmar'         300 450 120 30 $true
    $btnDig  = New-Btn $dlg 'Digitar manualmente' 20 450 190 30 $false

    $btnConf.add_Click({
        if (-not $lb.SelectedItem) {
            [System.Windows.Forms.MessageBox]::Show('Selecione um banco da lista.',
                '', [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $s       = $lb.SelectedItem.ToString()
        $isSys   = $s -like '*  [sistema]'
        $clean   = $s -replace '  \[sistema\]$',''
        if ($s -eq '[ Digitar manualmente ]') {
            $script:pickerResult = ''
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close(); return
        }
        if ($isSys) {
            $r2 = [System.Windows.Forms.MessageBox]::Show(
                "'$clean' e um banco de sistema do SQL Server.`nDeseja realmente usa-lo?",
                'Banco de sistema',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($r2 -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        $script:pickerResult = $clean
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $btnDig.add_Click({
        $script:pickerResult = ''
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $dlg.AcceptButton = $btnConf
    $dlg.ShowDialog($form) | Out-Null
    return $script:pickerResult
}

# ════════════════════════════════════════════════════════════════════════════
function Install-Bridge {
    param(
        [string]$DbName,
        [string]$DbHost,
        [string]$DbPort,
        [string]$BPort,
        [bool]$Repair
    )

    $script:BridgePort = $BPort
    $btnInstall.Enabled = $false
    $btnBack.Enabled    = $false
    $btnCancel.Enabled  = $false

    try {
        $logHdr = "LC Gestor Bridge SQL - Instalacao | $(Get-Date -Format 'dd/MM/yyyy HH:mm') | $DbHost`:$DbPort | Banco: $DbName | Porta Bridge: $BPort"
        [System.IO.File]::WriteAllText($script:LogFile, $logHdr + "`n" + ('=' * 60) + "`n", [System.Text.UTF8Encoding]::new($false))
    } catch {}
    Add-Log "LC Gestor Bridge SQL v1.2  - iniciando instalacao"

    # ── STEP 0: Ambiente ──────────────────────────────────────────────────────
    $script:ActiveStep = 0; $spinTimer.Start()
    Set-Step 0 'active'; Set-Prog 0 'Verificando ambiente...'
    Add-Log "Verificando privilegios de Administrador..."

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    Start-Sleep -Milliseconds 500

    $spinTimer.Stop()
    if ($isAdmin) {
        Add-Log "Executando como Administrador." 'ok'
        Set-Step 0 'done'
    } else {
        Add-Log "Sem privilegios de Administrador  - algumas funcoes podem falhar." 'warn'
        Set-Step 0 'warn'
    }

    # ── STEP 1: Node.js ───────────────────────────────────────────────────────
    $script:ActiveStep = 1; $spinTimer.Start()
    Set-Step 1 'active'; Set-Prog 1 'Verificando Node.js...'
    Add-Log "Procurando instalacao do Node.js..."

    $nodeOk = $false
    # Node portavel bundled em vendor\node\ tem prioridade absoluta — sem MSI, sem PATH
    $portableNode = Join-Path $BridgeDir 'vendor\node\node.exe'
    if (Test-Path $portableNode) {
        $runtimeDir  = Join-Path $BridgeDir 'runtime'
        $runtimeNode = Join-Path $runtimeDir 'node.exe'
        try {
            if (-not (Test-Path $runtimeDir)) { New-Item $runtimeDir -ItemType Directory -Force | Out-Null }
            if (-not (Test-Path $runtimeNode)) {
                Add-Log "Copiando node.exe portavel para runtime\ (aguarde)..."
                Copy-Item $portableNode $runtimeNode -Force -ErrorAction Stop
                Add-Log "node.exe copiado para runtime\node.exe" 'ok'
            } else {
                Add-Log "runtime\node.exe ja presente." 'ok'
            }
            $script:NodeFull = $runtimeNode
        } catch {
            Add-Log "Aviso: falha ao copiar para runtime\, usando vendor diretamente." 'warn'
            $script:NodeFull = $portableNode
        }
        $nodeOk = $true
        Add-Log "Node portavel ativo: $($script:NodeFull)" 'ok'
    }
    if (-not $nodeOk) { try {
        $nv = & node -v 2>&1
        if ($nv -match 'v\d+') {
            Add-Log "Node.js encontrado: $nv" 'ok'
            $nodeOk = $true
            $nc = Get-Command node.exe -ErrorAction SilentlyContinue
            if ($nc) { $script:NodeFull = $nc.Source }
        }
    } catch { } }

    if (-not $nodeOk) {
        Add-Log "Node.js nao encontrado. Tentando instalar via winget..." 'warn'
        $wingetOk = $false
        try { $wg = & winget -v 2>&1; if ($wg -match '\d+\.\d+') { $wingetOk = $true } } catch { }

        if ($wingetOk) {
            Add-Log "Executando: winget install OpenJS.NodeJS.LTS..."
            $r = Invoke-Proc 'winget' 'install OpenJS.NodeJS.LTS --scope machine --accept-package-agreements --accept-source-agreements'
            if ($r.ExitCode -eq 0) {
                $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' +
                            [System.Environment]::GetEnvironmentVariable('PATH','User')
                $nv2 = & node -v 2>&1
                if ($nv2 -match 'v\d+') {
                    Add-Log "Node.js instalado: $nv2" 'ok'
                    $nc2 = Get-Command node.exe -ErrorAction SilentlyContinue
                    if ($nc2) { $script:NodeFull = $nc2.Source }
                    $nodeOk = $true
                } else {
                    Add-Log "Node.js instalado mas PATH nao atualizado. Reabra o instalador." 'warn'
                }
            } else {
                Add-Log "Falha ao instalar Node.js via winget. Instale manualmente em nodejs.org" 'err'
            }
        } else {
            Add-Log "winget nao disponivel. Instale Node.js LTS em nodejs.org" 'err'
        }
    }

    if (-not $script:NodeFull) {
        foreach ($c in @(
            "$env:ProgramFiles\nodejs\node.exe",
            "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
        )) { if (Test-Path $c) { $script:NodeFull = $c; break } }
    }

    $spinTimer.Stop()
    if ($nodeOk) { Set-Step 1 'done' } else { Set-Step 1 'warn' }

    # ── STEP 2: npm install ───────────────────────────────────────────────────
    $script:ActiveStep = 2; $spinTimer.Start()
    Set-Step 2 'active'; Set-Prog 2 'Instalando dependencias npm...'

    if (-not (Test-Path $BridgeFile))  { Add-Log "ERRO: bridge.js nao encontrado em $BridgeDir" 'err' }
    if (-not (Test-Path $PackageFile)) { Add-Log "ERRO: package.json nao encontrado" 'err' }

    # Remove node_modules antes de instalar para evitar conflito com versao anterior
    $nmDir = Join-Path $BridgeDir 'node_modules'
    if (Test-Path $nmDir) {
        Add-Log "Removendo node_modules anterior..."
        try { Remove-Item $nmDir -Recurse -Force } catch { Add-Log "Aviso ao limpar node_modules: $_" 'warn' }
    }

    # Invoca o npm-cli.js diretamente para evitar o problema de prefix detection do npm.cmd no Node.js v24
    $npmCli = $null
    # Pacote OfflineNode: vendor\node\ contem npm junto, independente do caminho do runtime
    $vendorNpm = Join-Path $BridgeDir 'vendor\node\node_modules\npm\bin\npm-cli.js'
    if (Test-Path $vendorNpm) {
        $npmCli = $vendorNpm
        Add-Log "npm detectado em vendor\node\ (modo portavel)" 'ok'
    } elseif ($script:NodeFull) {
        $nodeDir = Split-Path $script:NodeFull -Parent
        $candidate = Join-Path $nodeDir 'node_modules\npm\bin\npm-cli.js'
        if (Test-Path $candidate) { $npmCli = $candidate }
    }

    Add-Log "Executando npm install..."
    # --prefix forca instalacao local em $BridgeDir independente do perfil do usuario/SYSTEM
    $npmFlags = "install --prefix `"$BridgeDir`" --no-audit --no-fund --loglevel=error"
    if ($npmCli) {
        $npmR = Invoke-Proc $script:NodeFull "`"$npmCli`" $npmFlags" -TimeoutSec 300
    } else {
        $npmR = Invoke-Proc 'npm.cmd' $npmFlags -TimeoutSec 300
    }
    $spinTimer.Stop()

    $mssqlCheck = Test-Path (Join-Path $BridgeDir 'node_modules\mssql')
    if ($npmR.ExitCode -eq 0 -and $mssqlCheck) {
        Add-Log "Dependencias instaladas com sucesso." 'ok'
        Set-Step 2 'done'
    } else {
        if ($npmR.ExitCode -ne 0) {
            Add-Log "npm install retornou codigo $($npmR.ExitCode)." 'warn'
            if ($npmR.Err.Trim() -ne '') { Add-Log $npmR.Err.Trim() 'warn' }
        } else {
            Add-Log "npm concluiu mas mssql nao foi encontrado em $BridgeDir\node_modules" 'warn'
            if ($npmR.Out.Trim() -ne '') { Add-Log (($npmR.Out.Trim() -split "`n" | Select-Object -First 3) -join ' | ') 'warn' }
        }
        Set-Step 2 'warn'
    }

    # ── STEP 3: Criar usuario SQL ─────────────────────────────────────────────
    $script:ActiveStep = 3; $spinTimer.Start()
    Set-Step 3 'active'; Set-Prog 3 'Configurando usuario SQL...'
    Add-Log "Criando usuario SQL '$SQL_USER' no banco '$DbName'..."

    $scriptSQL = @"
USE [master];
-- Remove login antigo incompativel (ex: Windows auth) e recria como SQL login
IF EXISTS (SELECT name FROM sys.server_principals WHERE name = N'$SQL_USER' AND type_desc <> 'SQL_LOGIN')
BEGIN
    IF EXISTS (SELECT name FROM sys.database_principals WHERE name = N'$SQL_USER')
    BEGIN
        USE [$DbName];
        DROP USER [$SQL_USER];
        USE [master];
    END
    DROP LOGIN [$SQL_USER];
END
-- Cria ou atualiza o SQL login
IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = N'$SQL_USER')
    CREATE LOGIN [$SQL_USER] WITH PASSWORD=N'$SQL_PASS', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF;
ELSE
    ALTER LOGIN [$SQL_USER] WITH PASSWORD=N'$SQL_PASS', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF;
ALTER LOGIN [$SQL_USER] ENABLE;
GO
USE [$DbName];
IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'$SQL_USER')
    CREATE USER [$SQL_USER] FOR LOGIN [$SQL_USER];
ELSE
    ALTER USER [$SQL_USER] WITH LOGIN=[$SQL_USER];
GO
EXEC sp_addrolemember 'db_datareader', '$SQL_USER';
DENY INSERT, UPDATE, DELETE, EXECUTE, ALTER TO [$SQL_USER];
GO
"@

    $sqlFile = Join-Path $BridgeDir 'criar-usuario.sql'
    [System.IO.File]::WriteAllText($sqlFile, $scriptSQL, [System.Text.UTF8Encoding]::new($false))

    $sqlcmd = $null
    $scCmd  = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($scCmd) { $sqlcmd = $scCmd.Source }
    if (-not $sqlcmd) {
        foreach ($c in @(
            "${env:ProgramFiles}\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\130\Tools\Binn\sqlcmd.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\120\Tools\Binn\sqlcmd.exe"
        )) { if (Test-Path $c) { $sqlcmd = $c; break } }
    }

    $serverArg = if ($DbPort -eq '1433') { $DbHost } else { "$DbHost,$DbPort" }

    if ($sqlcmd) {
        $tmpSql = [System.IO.Path]::GetTempFileName() + '.sql'
        [System.IO.File]::WriteAllText($tmpSql, $scriptSQL, [System.Text.UTF8Encoding]::new($false))
        try {
            $sqlR = Invoke-Proc $sqlcmd "-S $serverArg -U $SQL_ADMIN_USER -P $SQL_ADMIN_PASS -l 10 -t 15 -i `"$tmpSql`""
            $spinTimer.Stop()
            if ($sqlR.ExitCode -eq 0) {
                Add-Log "Usuario '$SQL_USER' criado/atualizado com sucesso." 'ok'
                Set-Step 3 'done'
            } else {
                Add-Log "sqlcmd retornou erro (codigo $($sqlR.ExitCode))." 'warn'
                Add-Log "Execute criar-usuario.sql manualmente no SSMS se necessario." 'warn'
                Set-Step 3 'warn'
            }
        } finally {
            Remove-Item $tmpSql -ErrorAction SilentlyContinue
        }
    } else {
        $spinTimer.Stop()
        Add-Log "sqlcmd nao encontrado. Execute criar-usuario.sql no SSMS." 'warn'
        Set-Step 3 'warn'
    }

    # ── STEP 4: .env ─────────────────────────────────────────────────────────
    $script:ActiveStep = 4
    Set-Step 4 'active'; Set-Prog 4 'Criando arquivo .env...'
    Add-Log "Gerando configuracao e token..."

    $existingToken = ''
    if ($Repair -and (Test-Path $EnvFile)) {
        $envVars = @{}
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match '^\s*([^#=][^=]*)=(.*)$') {
                $envVars[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        if ($envVars.ContainsKey('BRIDGE_TOKEN') -and $envVars['BRIDGE_TOKEN'] -ne '') {
            $existingToken = $envVars['BRIDGE_TOKEN']
        }
    }

    if ($existingToken -ne '') {
        $script:Token = $existingToken
        Add-Log "Token existente preservado." 'ok'
    } else {
        $tb2 = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($tb2)
        $script:Token = [System.BitConverter]::ToString($tb2).Replace('-','').ToLower()
        Add-Log "Novo token de 256 bits gerado." 'ok'
    }

    $envContent = "BRIDGE_TOKEN=$($script:Token)`nDB_HOST=$DbHost`nDB_PORT=$DbPort`nDB_NAME=$DbName`nDB_USER=$SQL_USER`nDB_PASS=$SQL_PASS`nPORT=$BPort"
    [System.IO.File]::WriteAllText($EnvFile, $envContent, [System.Text.UTF8Encoding]::new($false))

    $gi = Join-Path $BridgeDir '.gitignore'
    if (Test-Path $gi) {
        $giContent = Get-Content $gi -Raw -ErrorAction SilentlyContinue
        if ($giContent -and $giContent -notmatch '(^|\n)\.env(\r|\n|$)') {
            Add-Content $gi "`n.env"
        }
    }

    Add-Log ".env escrito com sucesso." 'ok'
    Set-Step 4 'done'; Set-Prog 4 ''
    [System.Windows.Forms.Application]::DoEvents()

    # ── STEP 5: Windows Service ───────────────────────────────────────────────
    $script:ActiveStep = 5; $spinTimer.Start()
    Set-Step 5 'active'; Set-Prog 5 'Instalando servico Windows...'
    Add-Log "Compilando e registrando servico Windows..."

    $svcExePath = Join-Path $BridgeDir 'bridge-svc.exe'

    if (-not $script:NodeFull) {
        $spinTimer.Stop()
        Add-Log "node.exe nao localizado  - servico nao configurado." 'warn'
        Set-Step 5 'warn'
    } else {
        try {
            # Para e remove servico anterior se existir
            sc.exe stop $SvcName 2>$null | Out-Null
            Start-Sleep -Milliseconds 1500
            sc.exe delete $SvcName 2>$null | Out-Null
            Start-Sleep -Milliseconds 800

            $bridgeJsFull = Join-Path $BridgeDir 'bridge.js'

            $svcSource = @"
using System;
using System.Diagnostics;
using System.ServiceProcess;
using System.Threading;

public class BridgeSvc : ServiceBase {
    static readonly string NodeExe  = @"$($script:NodeFull)";
    static readonly string BridgeJs = @"$bridgeJsFull";
    static readonly string WorkDir  = @"$BridgeDir";

    Process _node;
    volatile bool _stopping;

    public BridgeSvc() { ServiceName = "LCGestorSQLBridge"; CanStop = true; AutoLog = false; }

    void StartNode() {
        var psi = new ProcessStartInfo(NodeExe, "\"" + BridgeJs + "\"") {
            WorkingDirectory = WorkDir,
            UseShellExecute  = false,
            CreateNoWindow   = true,
        };
        _node = new Process { StartInfo = psi };
        _node.EnableRaisingEvents = true;
        _node.Exited += OnNodeExited;
        _node.Start();
    }

    void OnNodeExited(object sender, EventArgs e) {
        if (!_stopping) {
            Thread.Sleep(5000);
            try { StartNode(); } catch {}
        }
    }

    protected override void OnStart(string[] args) {
        _stopping = false;
        StartNode();
    }

    protected override void OnStop() {
        _stopping = true;
        try { if (_node != null && !_node.HasExited) { _node.Kill(); _node.WaitForExit(5000); } } catch {}
    }

    static void Main() { ServiceBase.Run(new BridgeSvc()); }
}
"@
            Add-Log "Compilando bridge-svc.exe (aguarde)..."
            [System.Windows.Forms.Application]::DoEvents()

            Add-Type -TypeDefinition $svcSource -Language CSharp `
                -ReferencedAssemblies 'System.ServiceProcess' `
                -OutputAssembly $svcExePath `
                -OutputType ConsoleApplication `
                -ErrorAction Stop

            Add-Log "bridge-svc.exe compilado." 'ok'

            $scOut = sc.exe create $SvcName binPath= "`"$svcExePath`"" start= auto DisplayName= "LC Gestor SQL Bridge" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sc create falhou: $scOut" }

            # Reinicializacao automatica em falha: tenta 3 vezes a cada 60s
            sc.exe failure $SvcName reset= 86400 actions= restart/60000/restart/60000/restart/60000 2>$null | Out-Null

            Add-Log "Servico registrado (inicio automatico + reinicio em falha)." 'ok'

            # ── Gerar script do monitor de bandeja ────────────────────────────
            $monitorPath = Join-Path $BridgeDir 'bridge-monitor.ps1'
            $monitorContent = @'
#Requires -Version 5.1
# LC Gestor Bridge Monitor - Icone de bandeja do sistema
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:SvcName   = 'LCGestorSQLBridge'
$script:BridgeDir = $PSScriptRoot

function New-CircleIcon([string]$hexRGB) {
    try {
        $r = [Convert]::ToByte($hexRGB.Substring(0,2),16)
        $g = [Convert]::ToByte($hexRGB.Substring(2,2),16)
        $b = [Convert]::ToByte($hexRGB.Substring(4,2),16)
        $bmp = New-Object System.Drawing.Bitmap 16,16
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gfx.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($r,$g,$b))
        $gfx.FillEllipse($brush, 1, 1, 13, 13)
        $brush.Dispose(); $gfx.Dispose()
        $h = $bmp.GetHicon(); $bmp.Dispose()
        return [System.Drawing.Icon]::FromHandle($h)
    } catch { return [System.Drawing.SystemIcons]::Application }
}

function Get-BridgeRunning {
    try {
        $svc = Get-Service -Name $script:SvcName -ErrorAction SilentlyContinue
        return ($null -ne $svc -and $svc.Status.ToString() -eq 'Running')
    } catch { return $false }
}

function Update-Status {
    try {
        $running = Get-BridgeRunning
        $script:notify.Icon = if ($running) { $script:icoGreen } else { $script:icoRed }
        if ($running) {
            $script:notify.Text       = 'LC Gestor Bridge - Ativo'
            $script:menuStart.Enabled = $false
            $script:menuStop.Enabled  = $true
        } else {
            $script:notify.Text       = 'LC Gestor Bridge - Parado'
            $script:menuStart.Enabled = $true
            $script:menuStop.Enabled  = $false
        }
    } catch {}
}

$script:icoGreen  = New-CircleIcon '22C55E'
$script:icoRed    = New-CircleIcon 'EF4444'

$script:notify    = New-Object System.Windows.Forms.NotifyIcon
$script:notify.Icon    = $script:icoRed
$script:notify.Text    = 'LC Gestor Bridge'
$script:notify.Visible = $true

$script:menuStart = New-Object System.Windows.Forms.ToolStripMenuItem 'Iniciar Bridge'
$script:menuStop  = New-Object System.Windows.Forms.ToolStripMenuItem 'Parar Bridge'
$menuLog          = New-Object System.Windows.Forms.ToolStripMenuItem 'Abrir Log'
$menuSep          = New-Object System.Windows.Forms.ToolStripSeparator
$menuExit         = New-Object System.Windows.Forms.ToolStripMenuItem 'Sair'

$script:menuStart.add_Click({ try { Start-Service $script:SvcName -ErrorAction SilentlyContinue } catch {}; Update-Status })
$script:menuStop.add_Click({  try { Stop-Service  $script:SvcName -Force -ErrorAction SilentlyContinue } catch {}; Update-Status })
$menuLog.add_Click({
    try { $f = Join-Path $script:BridgeDir 'logs\bridge.log'; if (Test-Path $f) { Start-Process notepad.exe $f } } catch {}
})
$script:mainForm = New-Object System.Windows.Forms.Form
$script:mainForm.ShowInTaskbar = $false
$script:mainForm.WindowState   = [System.Windows.Forms.FormWindowState]::Minimized
$script:mainForm.Opacity       = 0
$script:mainForm.Width         = 1
$script:mainForm.Height        = 1
$script:mainForm.Left          = -9999
$script:mainForm.Top           = -9999
$script:mainForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$script:mainForm.add_FormClosed({
    try { $script:statusTimer.Stop(); $script:statusTimer.Dispose() } catch {}
    try { $script:notify.Visible = $false; $script:notify.Dispose() } catch {}
})

$menuExit.add_Click({ try { $script:mainForm.Close() } catch {} })

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add($script:menuStart) | Out-Null
$menu.Items.Add($script:menuStop)  | Out-Null
$menu.Items.Add($menuSep)          | Out-Null
$menu.Items.Add($menuLog)          | Out-Null
$menu.Items.Add($menuExit)         | Out-Null
$script:notify.ContextMenuStrip = $menu

$script:statusTimer = New-Object System.Windows.Forms.Timer
$script:statusTimer.Interval = 5000
$script:statusTimer.add_Tick({ Update-Status })
$script:statusTimer.Start()
Update-Status
[System.Windows.Forms.Application]::Run($script:mainForm)
'@
            try {
                [System.IO.File]::WriteAllText($monitorPath, $monitorContent, [System.Text.UTF8Encoding]::new($false))
                Add-Log "bridge-monitor.ps1 gerado." 'ok'
            } catch { Add-Log "Aviso ao gerar monitor: $_" 'warn' }

            # Registrar monitor no logon do usuario atual
            $psExe   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            $trayCmd = "`"$psExe`" -NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$monitorPath`""
            try {
                Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
                    -Name 'LCGestorBridgeMonitor' -Value $trayCmd -ErrorAction Stop
                Add-Log "Icone de bandeja configurado para iniciar no proximo logon." 'ok'
            } catch { Add-Log "Aviso ao registrar monitor: $_" 'warn' }

            $spinTimer.Stop()
            Set-Step 5 'done'
        } catch {
            $spinTimer.Stop()
            Add-Log "Erro ao registrar servico: $_" 'warn'
            Set-Step 5 'warn'
        }
    }

    # ── STEP 6: Start service + test ─────────────────────────────────────────
    $script:ActiveStep = 6; $spinTimer.Start()
    Set-Step 6 'active'; Set-Prog 6 'Iniciando bridge e testando conexao...'
    Add-Log "Iniciando servico e aguardando bridge..."

    $baseUrl = "http://localhost:$BPort"
    $testeOk = $false
    $sqlOk   = $false

    if ($script:NodeFull) {
        # Verifica se dependencias estao instaladas antes de iniciar
        $mssqlDir = Join-Path $BridgeDir 'node_modules\mssql'
        if (-not (Test-Path $mssqlDir)) {
            Add-Log "ERRO: node_modules\mssql nao encontrado." 'err'
            Add-Log "npm install nao instalou as dependencias." 'err'
        }

        # Verifica se a porta da bridge esta disponivel
        try {
            $portBusy = & netstat -an 2>$null | Select-String ":${BPort}[^0-9]" | Where-Object { $_ -match 'LISTENING' }
            if ($portBusy) { Add-Log "AVISO: porta $BPort ja esta em uso por outro processo." 'warn' }
        } catch {}

        # Inicia o servico Windows
        $scStartOut = sc.exe start $SvcName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-Log "Servico iniciado." 'ok'
        } else {
            Add-Log "Aviso ao iniciar servico: $scStartOut" 'warn'
        }

        # Polling da bridge ate 30s (servico precisa de alguns segundos para iniciar node.exe)
        Add-Log "Aguardando bridge responder..."
        $pollDeadline = (Get-Date).AddSeconds(30)
        while (-not $testeOk -and (Get-Date) -lt $pollDeadline) {
            $waitEnd = (Get-Date).AddSeconds(2)
            while ((Get-Date) -lt $waitEnd) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 100
            }
            try {
                $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method GET -TimeoutSec 2 -ErrorAction Stop
                if ($health.ok) {
                    Add-Log "Bridge online  - banco: $($health.db)" 'ok'
                    $testeOk = $true
                }
            } catch {}
        }

        if (-not $testeOk) {
            Add-Log "Bridge nao respondeu (30s). Verifique o log em logs\bridge.log." 'warn'
        }

        if ($testeOk) {
            Add-Log "Testando autenticacao e query no SQL Server..."
            try {
                $headers   = @{ Authorization = "Bearer $($script:Token)"; 'Content-Type' = 'application/json' }
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes('{"sql":"SELECT 1 AS ok"}')
                $resp      = Invoke-RestMethod -Uri "$baseUrl/query" -Method POST `
                             -Headers $headers -Body $bodyBytes -TimeoutSec 10
                if ($null -ne $resp.rows) {
                    Add-Log "SQL Server acessivel  - token e conexao validados." 'ok'
                    $sqlOk = $true
                }
            } catch {
                $eb  = ''; try { $eb = $_.ErrorDetails.Message } catch {}
                $sc2 = $null; try { $sc2 = $_.Exception.Response.StatusCode.value__ } catch {}
                $msg = switch ($sc2) {
                    401 { 'Token invalido' }
                    403 { 'Query bloqueada' }
                    500 {
                        if     ($eb -match 'Login failed')         { 'Login SQL recusado  - usuario ou senha incorretos' }
                        elseif ($eb -match 'Cannot open database') { "Banco '$DbName' nao encontrado" }
                        elseif ($eb -match 'network-related')      { 'SQL Server inacessivel  - verifique DB_HOST e firewall' }
                        else                                       { "Erro SQL: $eb" }
                    }
                    default { 'Bridge nao respondeu' }
                }
                Add-Log "Teste falhou: $msg" 'warn'
            }
        }
    } else {
        Add-Log "node.exe nao localizado  - teste ignorado." 'warn'
    }

    $spinTimer.Stop()
    $script:ActiveStep = -1

    if ($testeOk -and $sqlOk) { Set-Step 6 'done' }
    else                       { Set-Step 6 'warn' }

    Set-Prog $script:StepNames.Count 'Instalacao finalizada!'
    Add-Log "Instalacao finalizada." 'ok'

    # ── Atualizar titulo do progresso ─────────────────────────────────────────
    if ($testeOk -and $sqlOk) {
        $lblProgTitle.Text      = 'Instalacao concluida com sucesso!'
        $lblProgTitle.ForeColor = $cGreen
    } else {
        $lblProgTitle.Text      = 'Instalacao concluida com avisos'
        $lblProgTitle.ForeColor = $cAmber
    }

    # ── Salvar resumo ─────────────────────────────────────────────────────────
    $summary = @"
LC Gestor -- Configuracao da Bridge SQL
=======================================
Host SQL Server:  $DbHost
Porta SQL Server: $DbPort
Banco de dados:   $DbName
Usuario SQL:      $SQL_USER
Porta bridge:     $BPort
Data:             $(Get-Date -Format 'dd/MM/yyyy HH:mm')

IMPORTANTE: O token NAO esta neste arquivo.
Ele esta no .env e foi exibido na tela ao final da instalacao.
"@
    [System.IO.File]::WriteAllText($SummaryFile, $summary, [System.Text.UTF8Encoding]::new($false))

    # ── Preencher pagina de conclusao ─────────────────────────────────────────
    $tbToken.Text     = $script:Token
    $lblCfFields.Text = "  Type : HTTP`n  URL  : localhost:$BPort`n`n  Configure o Public Hostname no Cloudflare One Dashboard."

    if ($testeOk -and $sqlOk) {
        $lblDoneTitle.Text = 'Instalacao concluida com sucesso!'
    } else {
        $lblDoneTitle.Text = 'Instalacao concluida com avisos'
    }

    Start-Sleep -Milliseconds 600
    Show-Page 3
}

# ════════════════════════════════════════════════════════════════════════════
# BUTTON EVENTS
# ════════════════════════════════════════════════════════════════════════════

$btnCancel.Add_Click({ $form.Close() })

$btnNext.Add_Click({
    if ($script:IsReinstall -and $rbUninstall.Checked) {
        # Desinstalar: confirmar antes de prosseguir
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Isso ira remover o servico, .env, logs e node_modules.`n`nDeseja continuar?",
            'Confirmar desinstalacao',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Show-Page 2
        $form.Refresh()
        Uninstall-Bridge

    } elseif ($script:IsReinstall -and $rbRepair.Checked) {
        # Repair: ler .env e ir direto para progresso
        $envVars = @{}
        if (Test-Path $EnvFile) {
            Get-Content $EnvFile | ForEach-Object {
                if ($_ -match '^\s*([^#=][^=]*)=(.*)$') {
                    $envVars[$matches[1].Trim()] = $matches[2].Trim()
                }
            }
        }

        $dn = if ($envVars.ContainsKey('DB_NAME') -and $envVars['DB_NAME'] -ne '') { $envVars['DB_NAME'] } else { 'banco' }
        $dh = if ($envVars.ContainsKey('DB_HOST') -and $envVars['DB_HOST'] -ne '') { $envVars['DB_HOST'] } else { 'localhost' }
        $dp = if ($envVars.ContainsKey('DB_PORT') -and $envVars['DB_PORT'] -ne '') { $envVars['DB_PORT'] } else { '1433' }
        $bp = if ($envVars.ContainsKey('PORT')    -and $envVars['PORT']    -ne '') { $envVars['PORT']    } else { '3055' }

        Show-Page 2
        $form.Refresh()

        Install-Bridge -DbName $dn -DbHost $dh -DbPort $dp -BPort $bp -Repair $true
    } else {
        Show-Page 1
    }
})

$btnBack.Add_Click({ Show-Page 0 })

$btnInstall.Add_Click({
    $dh = $tbDbHost.Text.Trim(); if ($dh -eq '') { $dh = 'localhost' }
    $dp = $tbDbPort.Text.Trim(); if ($dp -eq '') { $dp = '1433' }
    $bp = $tbBridgeP.Text.Trim(); if ($bp -eq '') { $bp = '3055' }

    # Seleção assistida de banco apenas se o campo ainda estiver vazio
    if ($tbDbName.Text.Trim() -eq '') {
        $btnInstall.Enabled = $false
        $btnInstall.Text    = 'Conectando...'
        $btnBack.Enabled    = $false
        $btnCancel.Enabled  = $false
        [System.Windows.Forms.Application]::DoEvents()

        $picked = Show-DbPicker -DbHost $dh -DbPort $dp

        $btnInstall.Enabled = $true
        $btnInstall.Text    = 'Instalar'
        $btnBack.Enabled    = $true
        $btnCancel.Enabled  = $true

        if ($null -ne $picked -and $picked -ne '') {
            $tbDbName.Text = $picked
        }
    }

    if ($tbDbName.Text.Trim() -eq '') {
        $errMsg = 'Nome do banco de dados e obrigatorio.'
        if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
            $errMsg += "`nComo sqlcmd nao foi encontrado, preencha o nome manualmente."
        }
        [System.Windows.Forms.MessageBox]::Show(
            $errMsg, 'Campo obrigatorio',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    Show-Page 2
    $form.Refresh()

    Install-Bridge `
        -DbName      $tbDbName.Text.Trim() `
        -DbHost      $dh `
        -DbPort      $dp `
        -BPort       $bp `
        -Repair      $false
})

$btnClose.Add_Click({ $form.Close() })

$btnCopy.Add_Click({
    if ($script:Token -ne '') {
        try {
            $script:Token | Set-Clipboard
            $btnCopy.Text     = 'Copiado!'
            $btnCopy.BackColor = $cGreen
            $btnCopy.ForeColor = $cWhite

            $resetT = New-Object System.Windows.Forms.Timer
            $resetT.Interval = 2000
            $resetT.add_Tick({
                $btnCopy.Text      = 'Copiar Token'
                $btnCopy.BackColor = $cSlate100
                $btnCopy.ForeColor = $cSlate700
                $resetT.Stop(); $resetT.Dispose()
            })
            $resetT.Start()
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                'Nao foi possivel copiar. Copie manualmente do campo acima.',
                'Erro',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    }
})

# ════════════════════════════════════════════════════════════════════════════
# RUN
# ════════════════════════════════════════════════════════════════════════════
[System.Windows.Forms.Application]::Run($form)
