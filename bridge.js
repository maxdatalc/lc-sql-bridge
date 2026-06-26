/**
 * lc-sql-bridge v1.1
 * Proxy HTTP seguro entre o Next.js da LC e o SQL Server do cliente.
 * Roda na máquina do cliente, exposto via Cloudflare Tunnel (HTTP).
 * Só aceita SELECT — nunca escreve no banco.
 */

'use strict'

// Carrega .env relativo ao diretório do bridge.js (garante funcionar como serviço/SYSTEM)
try { require('dotenv').config({ path: require('path').join(__dirname, '.env') }) } catch (_) {}

const http = require('http')
const fs   = require('fs')
const path = require('path')
const sql  = require('mssql')

// ── Configuração ──────────────────────────────────────────────────────────────
const TOKEN             = process.env.BRIDGE_TOKEN
const DB_HOST           = process.env.DB_HOST  || 'localhost'
const DB_PORT           = parseInt(process.env.DB_PORT  || '1433')
const DB_NAME           = process.env.DB_NAME
const DB_USER           = process.env.DB_USER
const DB_PASS           = process.env.DB_PASS
const PORT              = parseInt(process.env.PORT || '3055')
const QUERY_TIMEOUT_MS  = parseInt(process.env.QUERY_TIMEOUT_MS || '30000')
const MAX_BODY_BYTES    = 64 * 1024  // 64KB — queries SQL nunca precisam de mais

if (!TOKEN || !DB_NAME || !DB_USER || !DB_PASS) {
  console.error('[bridge] BRIDGE_TOKEN, DB_NAME, DB_USER e DB_PASS são obrigatórios')
  process.exit(1)
}

// ── Logging ───────────────────────────────────────────────────────────────────
const LOG_DIR      = path.join(__dirname, 'logs')
const LOG_FILE     = path.join(LOG_DIR, 'bridge.log')
const MAX_LOG_SIZE = 5 * 1024 * 1024  // 5 MB

function ensureLogDir() {
  if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true })
}

function rotateIfNeeded() {
  if (!fs.existsSync(LOG_FILE)) return
  if (fs.statSync(LOG_FILE).size < MAX_LOG_SIZE) return

  const archived = path.join(LOG_DIR, `bridge.${Date.now()}.log`)
  fs.renameSync(LOG_FILE, archived)

  // Mantém apenas os últimos 3 arquivos arquivados
  const old = fs.readdirSync(LOG_DIR)
    .filter(f => /^bridge\.\d+\.log$/.test(f))
    .sort()
    .slice(0, -3)
  old.forEach(f => fs.unlinkSync(path.join(LOG_DIR, f)))
}

function writeLog(level, msg, meta) {
  ensureLogDir()
  rotateIfNeeded()
  const entry = { ts: new Date().toISOString(), level, msg, ...meta }
  fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n')
  const tag = level === 'error' ? '[ERRO]' : level === 'warn' ? '[AVISO]' : '[INFO]'
  console.log(`${entry.ts} ${tag} ${msg}`)
}

const log = {
  info:  (msg, meta) => writeLog('info',  msg, meta),
  warn:  (msg, meta) => writeLog('warn',  msg, meta),
  error: (msg, meta) => writeLog('error', msg, meta),
}

// ── Segurança SQL — validação robusta ─────────────────────────────────────────
const BLOCKED_PATTERNS = [
  /\bINSERT\b/i,
  /\bUPDATE\b/i,
  /\bDELETE\b/i,
  /\bDROP\b/i,
  /\bALTER\b/i,
  /\bTRUNCATE\b/i,
  /\bEXEC(UTE)?\b/i,
  /\bMERGE\b/i,
  /\bCREATE\b/i,
  /\bGRANT\b/i,
  /\bREVOKE\b/i,
  /\bDENY\b/i,
  /\bBACKUP\b/i,
  /\bRESTORE\b/i,
  /\bBULK\b/i,
  /\bOPENROWSET\b/i,
  /\bOPENQUERY\b/i,
  /\bOPENDATASOURCE\b/i,
  /\bXP_\w+/i,                     // xp_cmdshell e similares
  /\bSP_\w+/i,                     // stored procedures do sistema
]

function stripSqlComments(q) {
  return q
    .replace(/--[^\n\r]*/g, ' ')     // comentários de linha
    .replace(/\/\*[\s\S]*?\*\//g, ' ') // comentários de bloco
}

function isSafeQuery(raw) {
  if (typeof raw !== 'string') return false
  if (raw.length > 32000) return false

  const stripped = stripSqlComments(raw).trim()

  // Bloqueia múltiplos statements
  if (stripped.includes(';')) return false

  // Deve começar com SELECT ou WITH
  if (!/^(SELECT|WITH)\s/i.test(stripped)) return false

  // Bloqueia SELECT INTO (cria tabela) — sintaxe: SELECT ... INTO tabela FROM ...
  if (/^SELECT\b/i.test(stripped) && /\bINTO\b/i.test(stripped)) return false

  // Verifica palavras-chave proibidas
  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.test(stripped)) return false
  }

  return true
}

// ── Pool SQL Server ───────────────────────────────────────────────────────────
let pool          = null
let _connected    = false  // true após primeira conexão bem-sucedida
let _retryPending = false  // evita múltiplos timers de retry simultâneos

async function getPool() {
  if (pool && pool.connected) return pool
  pool = await sql.connect({
    server: DB_HOST,
    port: DB_PORT,
    database: DB_NAME,
    user: DB_USER,
    password: DB_PASS,
    options: { trustServerCertificate: true, enableArithAbort: true },
    connectionTimeout: 15000,
    requestTimeout: QUERY_TIMEOUT_MS,
    pool: { max: 5, min: 0, idleTimeoutMillis: 30000 },
  })
  if (!_connected) log.info('SQL Server conectado', { host: DB_HOST, db: DB_NAME, port: DB_PORT })
  _connected = true
  return pool
}

// Retry em background com delay exponencial (5s → 10s → 20s → ... → 60s máx)
function scheduleRetry(delaySec) {
  if (_retryPending) return
  _retryPending = true
  setTimeout(async () => {
    _retryPending = false
    try {
      await getPool()
    } catch (err) {
      _connected = false
      const next = Math.min(delaySec * 2, 60)
      log.warn('SQL indisponivel, nova tentativa em ' + next + 's', { error: err.message })
      scheduleRetry(next)
    }
  }, delaySec * 1000)
}

// ── HTTP Server ───────────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json')
  const ip = req.socket.remoteAddress

  // Health check público (sem auth)
  if (req.method === 'GET' && req.url === '/health') {
    return res.end(JSON.stringify({ ok: true, db: DB_NAME, port: PORT, sql: _connected }))
  }

  // Autenticação Bearer — não loga o token, só o IP em caso de falha
  const auth = req.headers['authorization'] || ''
  if (auth !== `Bearer ${TOKEN}`) {
    log.warn('Autenticação falhou', { ip })
    res.statusCode = 401
    return res.end(JSON.stringify({ error: 'Unauthorized' }))
  }

  // Aceita apenas POST /query
  if (req.method !== 'POST' || req.url !== '/query') {
    res.statusCode = 404
    return res.end(JSON.stringify({ error: 'Not found' }))
  }

  // Lê body com limite de tamanho
  let body = ''
  let bodySize = 0

  req.on('data', chunk => {
    bodySize += chunk.length
    if (bodySize > MAX_BODY_BYTES) {
      res.statusCode = 413
      res.end(JSON.stringify({ error: 'Payload muito grande' }))
      req.destroy()
      return
    }
    body += chunk
  })

  req.on('end', async () => {
    const start = Date.now()
    let queryPreview = ''

    try {
      let parsed
      try {
        parsed = JSON.parse(body)
      } catch {
        res.statusCode = 400
        return res.end(JSON.stringify({ error: 'JSON inválido' }))
      }

      const { sql: queryStr, params } = parsed

      if (!queryStr || typeof queryStr !== 'string') {
        res.statusCode = 400
        return res.end(JSON.stringify({ error: 'Campo "sql" obrigatório' }))
      }

      queryPreview = queryStr.slice(0, 120).replace(/\s+/g, ' ')

      if (!isSafeQuery(queryStr)) {
        log.warn('Query bloqueada', { ip, query: queryPreview })
        res.statusCode = 403
        return res.end(JSON.stringify({ error: 'Apenas SELECT é permitido' }))
      }

      const p = await getPool()
      const request = p.request()
      request.timeout = QUERY_TIMEOUT_MS

      if (params && typeof params === 'object') {
        for (const [key, value] of Object.entries(params)) {
          request.input(key, value)
        }
      }

      const result = await request.query(queryStr)
      const ms = Date.now() - start

      log.info('Query executada', { ms, rows: result.recordset.length, query: queryPreview })
      res.end(JSON.stringify({ rows: result.recordset }))

    } catch (err) {
      const ms = Date.now() - start
      log.error('Erro na query', { ms, query: queryPreview, error: err.message })
      pool = null
      _connected = false
      scheduleRetry(5)  // reconecta em background sem esperar próximo request

      res.statusCode = 500
      res.end(JSON.stringify({ error: err.message }))
    }
  })
})

server.listen(PORT, () => {
  log.info('lc-sql-bridge iniciado', {
    port: PORT,
    host: DB_HOST,
    db: DB_NAME,
    token: TOKEN.slice(0, 8) + '...',
    timeout_ms: QUERY_TIMEOUT_MS,
  })
  // Tenta conectar ao SQL imediatamente; se falhar, retry em background
  getPool().catch(err => {
    _connected = false
    log.warn('SQL indisponivel na inicializacao, tentando em background...', { error: err.message })
    scheduleRetry(5)
  })
})

process.on('unhandledRejection', err => {
  log.error('Erro não tratado', { error: err?.message ?? String(err) })
  pool = null
  _connected = false
  scheduleRetry(5)
})

process.on('SIGTERM', () => {
  log.info('Bridge encerrada (SIGTERM)')
  process.exit(0)
})

process.on('SIGINT', () => {
  log.info('Bridge encerrada (SIGINT)')
  process.exit(0)
})
