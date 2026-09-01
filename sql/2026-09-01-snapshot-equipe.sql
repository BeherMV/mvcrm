-- =====================================================================
-- SNAPSHOT DE EQUIPE POR MÊS — SOLUÇÃO DEFINITIVA
-- Congela composição de equipe no fechamento do mês, para que mudanças
-- posteriores (movimentar/adicionar consultor) NÃO alterem histórico.
-- Rode este arquivo INTEIRO no SQL Editor do Supabase. Idempotente.
-- =====================================================================

-- 1) Adiciona coluna equipe_id em metas_mensais (snapshot da equipe naquele mês)
alter table metas_mensais add column if not exists equipe_id uuid references equipes(id);
create index if not exists idx_metas_equipe_mes on metas_mensais(equipe_id, mes, ano);

-- 2) BACKFILL: preenche equipe_id em rows existentes com o valor atual do consultor
-- Melhor esforço: usa composição atual como aproximação do snapshot histórico
update metas_mensais m
set equipe_id = u.equipe_id
from usuarios u
where m.consultor_id = u.id and m.equipe_id is null;

-- 3) Reescreve fechar_mes: se já travado, NÃO mexe (preserva snapshot original)
create or replace function public.fechar_mes(p_mes int, p_ano int)
returns table(metas_inseridas int, ja_travado boolean, log text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inseridos int := 0;
  v_travado_antes boolean;
begin
  select exists(select 1 from meses_travados where mes = p_mes and ano = p_ano)
    into v_travado_antes;

  -- Já travado? snapshot preservado, não faz nada
  if v_travado_antes then
    return query select 0, true,
      format('mês %s/%s: já travado, snapshot preservado', p_mes, p_ano);
    return;
  end if;

  -- Materializa faltantes com snapshot de equipe_id atual
  insert into metas_mensais (consultor_id, mes, ano, meta_vendas, meta_cotacoes, equipe_id)
  select u.id, p_mes, p_ano, 17000, 70, u.equipe_id
  from usuarios u
  where u.perfil in ('consultor','supervisor')
    and coalesce(u.ativo_meta, true) = true
    and not exists (
      select 1 from metas_mensais m
      where m.consultor_id = u.id and m.mes = p_mes and m.ano = p_ano
    );
  get diagnostics v_inseridos = row_count;

  -- Snapshot em rows já existentes (metas customizadas durante o mês) sem equipe_id
  update metas_mensais m
  set equipe_id = u.equipe_id
  from usuarios u
  where m.consultor_id = u.id
    and m.mes = p_mes and m.ano = p_ano
    and m.equipe_id is null;

  insert into meses_travados (mes, ano) values (p_mes, p_ano) on conflict do nothing;

  return query select v_inseridos, false,
    format('mês %s/%s: %s metas materializadas + snapshot equipe', p_mes, p_ano, v_inseridos);
end;
$$;

grant execute on function public.fechar_mes(int, int) to authenticated;

-- 4) RPC: meta total da equipe usando SNAPSHOT (composição congelada)
create or replace function public.get_meta_equipe_snapshot(p_equipe_id uuid, p_mes int, p_ano int)
returns numeric
language sql
security definer
set search_path = public
as $$
  select coalesce(sum(meta_vendas), 0)
  from metas_mensais
  where equipe_id = p_equipe_id and mes = p_mes and ano = p_ano
$$;
grant execute on function public.get_meta_equipe_snapshot(uuid, int, int) to authenticated;

-- 5) RPC: realizado da equipe usando SNAPSHOT (só leads de quem estava na equipe naquele mês)
create or replace function public.get_realizado_equipe_snapshot(p_equipe_id uuid, p_mes int, p_ano int)
returns numeric
language sql
security definer
set search_path = public
as $$
  select coalesce(sum(l.valor_meta), 0)
  from leads l
  where l.status = 'Proposta'
    and l.mes_fechamento = p_mes
    and l.ano_fechamento = p_ano
    and l.consultor_id in (
      select consultor_id from metas_mensais
      where equipe_id = p_equipe_id and mes = p_mes and ano = p_ano
    )
$$;
grant execute on function public.get_realizado_equipe_snapshot(uuid, int, int) to authenticated;

-- 6) Verificação
select 'Metas com equipe_id snapshot' as tipo, count(*)::text as valor
  from metas_mensais where equipe_id is not null
union all
select 'Metas SEM equipe_id (órfãs)', count(*)::text
  from metas_mensais where equipe_id is null
union all
select 'Meta snapshot Águias ago/2026',
  (select coalesce(sum(meta_vendas),0)::text from metas_mensais
   where mes=8 and ano=2026
     and equipe_id=(select id from equipes where nome ilike '%águia%' or nome ilike '%aguia%' limit 1));
