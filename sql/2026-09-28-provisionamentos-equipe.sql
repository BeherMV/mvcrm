-- =====================================================================
-- FIX — cria tabela dedicada pra meta/realizado do SUPERVISOR
-- Sintoma: "Could not find the 'ano' column of 'provisionamentos'"
-- Causa: código do supervisor tentava escrever meta/realizado/mes/ano na
--        tabela `provisionamentos` (que é de LEADS/comissões), onde essas
--        colunas nunca existiram. Dados nunca foram salvos.
-- Fix: tabela nova provisionamentos_equipe (não mistura com leads).
-- Rode INTEIRO como master no SQL Editor. Idempotente.
-- =====================================================================

create table if not exists provisionamentos_equipe(
  id uuid primary key default gen_random_uuid(),
  equipe_id uuid not null references equipes(id) on delete cascade,
  mes smallint not null check (mes between 1 and 12),
  ano smallint not null check (ano between 2020 and 2100),
  meta numeric(14,2) not null default 0,
  realizado numeric(14,2) not null default 0,
  observacao text,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references usuarios(id),
  unique (equipe_id, mes, ano)
);

create index if not exists idx_prov_eq_periodo on provisionamentos_equipe(ano desc, mes desc);
create index if not exists idx_prov_eq_equipe on provisionamentos_equipe(equipe_id);

alter table provisionamentos_equipe enable row level security;

-- SELECT: supervisor lê sua própria equipe, master lê tudo
drop policy if exists "prov_eq_select" on provisionamentos_equipe;
create policy "prov_eq_select" on provisionamentos_equipe
  for select to authenticated
  using (
    get_meu_perfil() = 'master'
    or (get_meu_perfil() = 'supervisor' and equipe_id = get_minha_equipe())
  );

-- INSERT: supervisor da própria equipe, ou master
drop policy if exists "prov_eq_insert" on provisionamentos_equipe;
create policy "prov_eq_insert" on provisionamentos_equipe
  for insert to authenticated
  with check (
    get_meu_perfil() = 'master'
    or (get_meu_perfil() = 'supervisor' and equipe_id = get_minha_equipe())
  );

-- UPDATE: supervisor da própria equipe, ou master
drop policy if exists "prov_eq_update" on provisionamentos_equipe;
create policy "prov_eq_update" on provisionamentos_equipe
  for update to authenticated
  using (
    get_meu_perfil() = 'master'
    or (get_meu_perfil() = 'supervisor' and equipe_id = get_minha_equipe())
  );

-- Verificação
select 'Tabela criada' as tipo, 'ok' as valor
union all
select 'Policies ativas', count(*)::text from pg_policies
  where schemaname='public' and tablename='provisionamentos_equipe';
