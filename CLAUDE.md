# MV CRM — guia para o Claude

CRM interno da MV Corretora (leads, funil, metas, comissão, feed da equipe, roleplay de vendas com IA). SPA single-page em `index.html` (~9k linhas) + painel de TV em `tv.html`, com Supabase como backend. Deploy automático no Vercel a cada push na `main`.

## Arquitetura em uma frase

HTML/CSS/JS puro num arquivo monolítico, cliente Supabase global `sb`, usuário logado em `CU` (linha da tabela `usuarios`). A tela é montada por perfil em `setupMaster()` / `setupSupervisor()` / `setupConsultor()`, que escrevem a sidebar (`#sb-nav`) e as páginas (`#pages-wrap`); `navTo('p-xxx', btn, 'Título')` troca de página.

## Arquivos

- `index.html` — o CRM inteiro. Seções marcadas com banners `// ═══ NOME ═══` (CONSULTOR — LEADS, SUPERVISOR, MASTER, CURVAS, ROLEPLAY, DRIVES, FEED...). Use `grep -n "^// ═\|^// ──" index.html` pra se localizar.
- `tv.html` — painel de TV (rota `/tv` via `vercel.json`), lê `rpc('get_dados_tv')` e `rpc('get_vendas_tv')`.
- `api/followup.js` — função serverless Vercel que só repassa o body pra `api.anthropic.com/v1/messages` usando `ANTHROPIC_API_KEY` (env var no Vercel). Usada pelo follow-up com IA e pelo Roleplay.
- `sql/AAAA-MM-DD-descricao.sql` — migrações manuais, rodadas **inteiras** no SQL Editor do Supabase. Todas são idempotentes (`if not exists`, `create or replace`). Toda mudança de schema/RLS/RPC ganha um arquivo novo aqui.
- `deploy.bat` — atalho Windows: `git add -A` + commit `update <data>` + push direto na `main`. Não usar pra trabalho do Claude (ver convenções de commit).

## Backend Supabase

- **Projeto correto do CRM:** `nfldasoaverzplbowjdn`. O Cotador usa outro projeto (`jwvgonxipbgdbdtukqvg`) — **NUNCA** rodar SQL do CRM no Cotador nem vice-versa.
- Auth: Supabase Auth nativo (`sb.auth.signInWithPassword`) e depois carrega o perfil em `usuarios` pelo `id`. Sessão restaurada no load via `sb.auth.getSession()`.
- Tabelas principais: `usuarios`, `equipes`, `leads`, `historico_leads`, `lead_recusas`, `agendamentos`, `metas_mensais`, `historico_mensal`, `meses_travados`, `snapshots_equipe_mes`, `provisionamentos` + `provisionamento_parcelas` (comissão de leads), `provisionamentos_equipe` (meta/realizado do supervisor), `curvas`, `drives`, `notificacoes`, feed (`posts`, `comentarios`, `curtidas`, `enquete_votos`, `denuncias`), roleplay (`roleplay_sessoes`, `roleplay_contestacoes`, `ia_aprendizado`).
- RPCs (`SECURITY DEFINER` pra contornar RLS): `fechar_mes`, `get_consultores_equipe`, `get_meta_equipe_mes`, `get_meta_equipe_snapshot`, `get_metas_equipe`, `get_realizado_equipe_snapshot`, `get_receita_mes`, `get_resultado_equipe`, `get_resultado_equipe_ativos`, `get_todos_usuarios_ids`, `lead_duplicado_meu`, `set_ativo_meta`, `get_dados_tv`, `get_vendas_tv`.
- **RLS em `usuarios`:** policy de SELECT que consulta a própria `usuarios` causa recursão infinita (aconteceu na v1 de `2026-09-24-supervisor-select-equipe`). Use funções helper `SECURITY DEFINER` pra ler o perfil do usuário logado.

## Perfis e permissões

Campo `usuarios.perfil`: `master` / `supervisor` / `consultor`.

- **Master:** gestão de usuários, curvas, drives, recusas consolidadas, análise de contestações do Roleplay, fechamento de mês.
- **Supervisor:** visão da própria equipe (metas, recusas, engajamento, dashboard de Roleplay) + "Meus leads" (produção própria). Libera Roleplay só pros consultores da equipe.
- **Consultor:** painel, leads, funil, agenda, drives (leitura), histórico, feed, comissão. Roleplay só aparece se `usuarios.roleplay_liberado`.

## Regras de negócio que importam

- **Meta / multiplicadores** (`calcMeta`, `PME_MULT`): só PME multiplica, exceto Unimed (PME 3×, Adesão 2×, PF 1×), MedSênior (sempre 2×), Qualicorp (sempre 1×), Leve Saúde (PME 2×, sem Adesão — `OPS_SEM_ADESAO`).
- **Status de lead** (`STATUS_LEADS`): Não responderam AB → Não responderam mais → Analisando → Pela Boa → Ard Documento → Proposta / Negativa. Cores em `S_BG`/`S_CLR`.
- **Cadência de follow-up:** D+1, D+3, D+5, D+10 a partir de `criado_em` (`FOLLOWUP_CADENCE`, coluna `leads.contatos_feitos`). Esgotou as 4 → sem próximo follow-up.
- **Motor de priorização (Central do Consultor):** score determinístico por status (`SCORE_BASE_STATUS`), não exibido — só ordena a fila. Cooldown de 2h após "Fiz contato" (`COOLDOWN_HORAS`). Proposta/Negativa ficam fora.
- **Lead duplicado:** bloqueia telefone repetido (só dígitos) **dentro do funil do mesmo consultor** (`rpc('lead_duplicado_meu')`). Outro consultor com o mesmo telefone não bloqueia.
- **Fechamento de mês:** `rpc('fechar_mes')` congela metas, composição da equipe (`metas_mensais.equipe_id`) e totais (`snapshots_equipe_mes`). Depois de fechado, **nada recalcula** — histórico lê direto do snapshot. Dispara automático no 1º login do mês (`_autoFecharMesAnterior`) e via agendamento no banco (dia 1, 00:05 BRT).
- Foco geográfico: Curitiba / RMC / PR (personas do Roleplay seguem isso).

## IA (Claude)

- Front chama `fetch('/api/followup', {body: {model, messages, ...}})`.
- Follow-up usa `claude-haiku-4-5-20251001`; Roleplay tenta `claude-sonnet-4-5` e cai pro Haiku se falhar.
- A chave fica **só** no Vercel (`ANTHROPIC_API_KEY`). Nunca colocar chave no HTML.

## Toast de nova versão

`_iniciarChecagemVersao()` (chamada no fim de `iniciarApp`) faz `HEAD` no `index.html` a cada 5 min comparando ETag/Last-Modified; mudou → toast azul "Nova versão disponível" com botão Atualizar. Mesmo mecanismo do Cotador.

## Preview local

Servir a pasta e abrir `http://localhost:8765/index.html`:

- Qualquer SO com Python: `python -m http.server 8765`
- Windows sem Python: copiar o `preview-server.ps1` do repo do Cotador pra cá e rodar `powershell -ExecutionPolicy Bypass -File preview-server.ps1`

O preview conversa com o Supabase de produção — cuidado ao testar escrita (criar lead, fechar mês, etc.). `/api/followup` não existe no preview estático (só no Vercel ou com `vercel dev`).

## Convenções de commit

Sempre resumir alterações e **perguntar antes de commitar/pushar**. Mensagens em português, formato `feat/fix(escopo):` com corpo explicando o quê + por quê quando não trivial. Co-author do Claude vai nos commits. Mudança de banco = arquivo novo em `sql/` no mesmo commit do código que depende dele.

## O que NÃO fazer

- Não rodar SQL no projeto do Cotador pensando que é o CRM. Confirmar `nfldasoaverzplbowjdn` sempre.
- Não editar um `.sql` já aplicado — criar um novo com data.
- Não recalcular meses fechados nem escrever em snapshots fora do `fechar_mes`.
- Não criar policy RLS em `usuarios` que faça SELECT em `usuarios` (recursão).
- Não usar `git push --force` em main sem pedir confirmação explícita.
- Não commitar arquivo em `.claude/` do projeto.
