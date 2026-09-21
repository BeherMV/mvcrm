-- =====================================================================
-- CENTRAL DO CONSULTOR — V1 (Commit 1: infraestrutura)
-- Adiciona colunas em leads pra alimentar o motor de priorização.
-- Cria tabela de recusas com motivo (feed pro motor no futuro).
-- Rode INTEIRO no SQL Editor. Idempotente.
-- =====================================================================

-- 1) Novas colunas em leads
alter table leads add column if not exists ultimo_contato_em timestamptz;
alter table leads add column if not exists status_alterado_em timestamptz;
alter table leads add column if not exists criterio_decisao varchar(20);  -- 'preco','rede','cobertura','carencia','outro' (V1.5+)

-- 2) Backfill inicial:
-- status_alterado_em: se null, usa criado_em como proxy (aproximação; pra novos ficará correto)
update leads set status_alterado_em = criado_em where status_alterado_em is null;

-- 3) Tabela de recusas (feed do motor + auditoria)
create table if not exists lead_recusas(
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references leads(id) on delete cascade,
  consultor_id uuid not null references usuarios(id) on delete cascade,
  motivo varchar(50) not null,  -- valores esperados: 'retorno_agendado','fora_do_crm','aguardando_info','indisponivel','discordo'
  detalhe text,
  criada_em timestamptz not null default now()
);
create index if not exists idx_recusas_lead on lead_recusas(lead_id, criada_em desc);
create index if not exists idx_recusas_consultor on lead_recusas(consultor_id, criada_em desc);

-- 4) RLS: consultor CRUD suas próprias recusas; supervisor/master lêem da equipe/tudo
alter table lead_recusas enable row level security;
drop policy if exists "recusas_select" on lead_recusas;
create policy "recusas_select" on lead_recusas
  for select to authenticated using (
    consultor_id = auth.uid()
    or exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil in ('master','supervisor'))
  );
drop policy if exists "recusas_insert" on lead_recusas;
create policy "recusas_insert" on lead_recusas
  for insert to authenticated with check (consultor_id = auth.uid());
drop policy if exists "recusas_delete" on lead_recusas;
create policy "recusas_delete" on lead_recusas
  for delete to authenticated using (
    consultor_id = auth.uid()
    or exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil = 'master')
  );

-- 5) Índice pra otimizar a busca da fila (por consultor + status)
create index if not exists idx_leads_consultor_status on leads(consultor_id, status)
  where status not in ('Proposta','Negativa');

-- 6) Verificação
select 'Leads com status_alterado_em' as tipo, count(*)::text as valor from leads where status_alterado_em is not null
union all
select 'Leads com ultimo_contato_em', count(*)::text from leads where ultimo_contato_em is not null
union all
select 'Recusas registradas', count(*)::text from lead_recusas
union all
select 'RLS ativo em lead_recusas',
  case when relrowsecurity then 'sim' else 'nao' end
  from pg_class where relname='lead_recusas';
