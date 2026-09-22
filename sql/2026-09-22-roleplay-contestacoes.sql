-- =====================================================================
-- ROLEPLAY — Contestações + base de aprendizado da IA
-- Consultor discorda da avaliação → master analisa → aprova/rejeita
-- Aprovadas alimentam base pra afinar prompt/RAG no futuro
-- Rode INTEIRO no SQL Editor. Idempotente.
-- =====================================================================

-- 1) Tabela de contestações
create table if not exists roleplay_contestacoes(
  id uuid primary key default gen_random_uuid(),
  sessao_id uuid not null references roleplay_sessoes(id) on delete cascade,
  consultor_id uuid not null references usuarios(id),
  motivo text not null,
  status varchar(20) not null default 'pendente',  -- 'pendente' | 'aprovada' | 'rejeitada'
  revisada_por uuid references usuarios(id),
  resposta_master text,
  criada_em timestamptz not null default now(),
  revisada_em timestamptz
);

create index if not exists idx_contest_status on roleplay_contestacoes(status, criada_em desc);
create index if not exists idx_contest_consultor on roleplay_contestacoes(consultor_id, criada_em desc);

alter table roleplay_contestacoes enable row level security;

drop policy if exists "contest_select" on roleplay_contestacoes;
create policy "contest_select" on roleplay_contestacoes for select to authenticated
  using (consultor_id = auth.uid()
    or exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil in ('master','supervisor')));

drop policy if exists "contest_insert" on roleplay_contestacoes;
create policy "contest_insert" on roleplay_contestacoes for insert to authenticated
  with check (consultor_id = auth.uid());

drop policy if exists "contest_update_master" on roleplay_contestacoes;
create policy "contest_update_master" on roleplay_contestacoes for update to authenticated
  using (exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil = 'master'));

-- 2) Tabela de aprendizado — contestações aprovadas alimentam a base
create table if not exists ia_aprendizado(
  id uuid primary key default gen_random_uuid(),
  origem varchar(30) not null default 'roleplay_contest',
  sessao_id uuid references roleplay_sessoes(id) on delete set null,
  contestacao_id uuid references roleplay_contestacoes(id) on delete set null,
  contexto text not null,
  nota_ia integer,
  ajuste_manual text,
  criada_em timestamptz not null default now(),
  criada_por uuid references usuarios(id)
);

create index if not exists idx_apr_criada on ia_aprendizado(criada_em desc);

alter table ia_aprendizado enable row level security;

drop policy if exists "apr_select_master" on ia_aprendizado;
create policy "apr_select_master" on ia_aprendizado for select to authenticated
  using (exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil = 'master'));

drop policy if exists "apr_insert_master" on ia_aprendizado;
create policy "apr_insert_master" on ia_aprendizado for insert to authenticated
  with check (exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil = 'master'));

-- 3) Verificação
select 'Tabela roleplay_contestacoes' as tipo, 'ok' as valor
union all
select 'Tabela ia_aprendizado', 'ok'
union all
select 'Contestações pendentes', count(*)::text from roleplay_contestacoes where status='pendente';
