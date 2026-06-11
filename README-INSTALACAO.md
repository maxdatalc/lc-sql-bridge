# LC Gestor — Bridge SQL Server

Guia de instalação para técnicos.

---

## O que é isso?

Um programa pequeno que fica rodando na máquina do cliente e permite que o painel LC Gestor acesse o banco de dados da empresa de forma segura, pela internet.

A porta 1433 do SQL Server **nunca é exposta** — apenas a porta 3055 da bridge é acessível externamente, e somente com o token correto.

---

## Requisitos

- Windows 10 ou 11 (64 bits)
- Node.js LTS (o instalador instala automaticamente se não estiver presente)
- SQL Server do cliente rodando localmente
- Cloudflare Tunnel configurado para apontar para a porta 3055
- Acesso de Administrador local

---

## Instalação (tudo em uma etapa)

1. Copie a pasta `lc-sql-bridge` para o computador do cliente (ex: `C:\LC\lc-sql-bridge`)
2. **Duplo clique em `LCBRIDGE-INSTALL.exe`**
   - O Windows pedirá confirmação de Administrador — clique em **Sim**
   - Siga as instruções na tela
3. Ao final, copie o **token** exibido e cadastre no painel do LC Gestor

O instalador faz tudo automaticamente:
- Verifica/instala o Node.js
- Instala as dependências
- Coleta o nome do cliente e as configurações do SQL Server
- Cria o usuário SQL `lc_dashboard` com permissão somente leitura
- Gera o token de segurança e cria o arquivo `.env`
- Configura a inicialização automática (sobe com o Windows, sem precisar de login)
- Testa a conexão completa

> **Sem exe gerado ainda?** Use `INSTALAR.bat` como alternativa — funciona da mesma forma.

---

## Gerar LCBRIDGE-INSTALL.exe (uma vez, na máquina de desenvolvimento)

```powershell
# Execute no computador de desenvolvimento (requer internet na primeira vez)
powershell.exe -ExecutionPolicy Bypass -File build-exe.ps1
```

O `LCBRIDGE-INSTALL.exe` gerado inclui o UAC manifest — ao dar duplo clique, o Windows já pede elevação automaticamente. Adicione o exe ao ZIP de distribuição. Ele **não vai para o git** (está no `.gitignore`).

---

## Fluxo de atualização

Ao atualizar `bridge.js` ou `instalar.ps1`:

```bash
git add .
git commit -m "..."
git push
```

O técnico baixa o novo ZIP do GitHub, extrai por cima da pasta existente e roda `LCBRIDGE-INSTALL.exe` novamente → escolhe **Reparar** para atualizar sem perder o token.

---

## Utilitários

| Arquivo | Quando usar |
|---|---|
| `iniciar-bridge.ps1` | Iniciar manualmente se a bridge parou |
| `testar-bridge.ps1` | Verificar se está funcionando (lê token do `.env` automaticamente) |
| `desinstalar-bridge.ps1` | Remover o serviço e limpar configurações |

---

## Verificar os logs

```powershell
Get-Content logs\bridge.log -Tail 50
```

Cada linha é um registro JSON:
```json
{"ts":"2025-06-11T10:00:00.000Z","level":"info","msg":"lc-sql-bridge iniciado","port":3055}
{"ts":"2025-06-11T10:01:00.000Z","level":"warn","msg":"Autenticação falhou","ip":"127.0.0.1"}
```

---

## Configurar o Cloudflare Tunnel

Após a instalação, aponte uma rota do Cloudflare Tunnel para a bridge:

1. Acesse o painel Cloudflare → Zero Trust → Networks → Tunnels
2. Clique no tunnel do cliente → **Public Hostname** → **Add a public hostname**
3. Preencha:
   - Subdomain: `sql-nomecliente`
   - Domain: `lctecnologias.com.br`
   - Type: `HTTP`
   - URL: `localhost:3055`
4. Salvar

A URL resultante (`https://sql-nomecliente.lctecnologias.com.br`) e o token devem ser cadastrados no painel admin do LC Gestor.

---

## Erros comuns

| Erro | Causa provável |
|---|---|
| Node.js não encontrado | Instalado, mas requer novo terminal — feche e abra novamente |
| Login failed | SQL Server não tem o usuário `lc_dashboard` — rode o instalador novamente |
| Cannot open database | Nome do banco incorreto digitado na instalação |
| Tabela 'venda' não encontrada | Banco correto mas schema diferente — altere a query de teste |
| Bridge não respondeu | Porta 3055 em uso ou Node.js não iniciou |
| Timeout | SQL Server lento ou firewall bloqueando porta 1433 |
| 401 Unauthorized | Token no Supabase diferente do token no `.env` |

---

## Segurança

- O SQL Server **nunca é exposto** diretamente na internet
- Apenas consultas `SELECT` são aceitas — escrita é bloqueada no código e no usuário SQL
- O token é verificado em toda requisição
- As credenciais SQL ficam apenas no arquivo `.env` na máquina do cliente
- O `.env` nunca é enviado ao Git (está no `.gitignore`)
- Os logs nunca registram senhas, tokens completos ou conteúdo das consultas

---

## Cadastrar no LC Gestor após a instalação

Informe ao suporte da LC Tecnologias:

1. **URL da bridge**: `https://sql-nomecliente.lctecnologias.com.br`
2. **Token**: exibido ao final da instalação (ou copie do `.env` se necessário)

Esses dados são cadastrados no painel admin do LC Gestor e **não são compartilhados com o cliente**.
