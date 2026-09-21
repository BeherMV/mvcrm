-- =====================================================================
-- CADÊNCIA DE FOLLOW-UP (D+1, D+3, D+5, D+10)
-- Adiciona coluna contatos_feitos em leads.
-- Rode INTEIRO no SQL Editor. Idempotente.
-- =====================================================================

alter table leads add column if not exists contatos_feitos int not null default 0;

-- Backfill: leads que já têm followup_date mas não têm contatos_feitos ficam com 0
-- (a cadência começa a valer a partir do próximo clique em "Fiz contato")
-- Nada a fazer aqui — default 0 cobre tudo.

-- Verificação
select 'Leads com followup pendente' as tipo, count(*)::text as valor
  from leads where followup_date is not null and status not in ('Proposta','Negativa')
union all
select 'Leads com followup atrasado', count(*)::text
  from leads where followup_date < current_date and status not in ('Proposta','Negativa')
union all
select 'Distribuição de contatos_feitos',
  string_agg(distinct contatos_feitos::text, ',' order by contatos_feitos::text)
  from leads where status not in ('Proposta','Negativa');
