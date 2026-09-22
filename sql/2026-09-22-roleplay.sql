-- =====================================================================
-- ROLEPLAY MV — Sprint 1A (MVP)
-- Rode INTEIRO no SQL Editor. Idempotente.
-- =====================================================================

-- 1) Tabela de sessões (usuarios.roleplay_liberado já foi criado antes)
create table if not exists roleplay_sessoes(
  id uuid primary key default gen_random_uuid(),
  consultor_id uuid not null references usuarios(id) on delete cascade,
  modulo varchar(30) not null,             -- 'completa','spin','ancoragem','objecao','fechamento','followup'
  perfil_cliente varchar(30) not null,     -- 'empresario_familia','senior','pf_pediatrica','pme'
  objecao_forte varchar(30),
  dificuldade int not null default 3,      -- 1 a 5
  qtd_mensagens int not null default 0,
  nota int,                                -- 0 a 10 (null até encerrar)
  duracao_seg int,
  pontos_positivos text[],
  pontos_desenvolver text[],
  feedback_texto text,
  transcricao text,
  iniciada_em timestamptz not null default now(),
  encerrada_em timestamptz
);

create index if not exists idx_roleplay_consultor on roleplay_sessoes(consultor_id, iniciada_em desc);
create index if not exists idx_roleplay_modulo on roleplay_sessoes(modulo, encerrada_em desc);

-- 2) RLS
alter table roleplay_sessoes enable row level security;

drop policy if exists "roleplay_select" on roleplay_sessoes;
create policy "roleplay_select" on roleplay_sessoes
  for select to authenticated using (
    consultor_id = auth.uid()
    or exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil in ('master','supervisor'))
  );

drop policy if exists "roleplay_insert" on roleplay_sessoes;
create policy "roleplay_insert" on roleplay_sessoes
  for insert to authenticated with check (consultor_id = auth.uid());

drop policy if exists "roleplay_update" on roleplay_sessoes;
create policy "roleplay_update" on roleplay_sessoes
  for update to authenticated using (consultor_id = auth.uid());

-- 3) Libera acesso pro Beher (master) testar
--    Troque pelo seu user_id se necessário, ou libere quem quiser
update usuarios set roleplay_liberado = true where nome ilike '%beher%';

-- 4) Verificação
select 'Tabela roleplay_sessoes existe' as tipo, 'sim' as valor
union all
select 'Consultores liberados', count(*)::text from usuarios where roleplay_liberado = true;
