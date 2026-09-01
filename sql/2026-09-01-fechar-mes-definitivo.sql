-- =====================================================================
-- FECHAMENTO DE MÊS — VERSÃO DEFINITIVA
-- Cria RPC `fechar_mes(mes,ano)` com security definer (bypass RLS),
-- corrige histórico e agenda execução automática dia 1 às 00:05 (BRT).
-- Rode este arquivo INTEIRO no SQL Editor do Supabase.
-- Idempotente: pode rodar quantas vezes quiser.
-- =====================================================================

-- 1) RPC principal: materializa metas faltantes com fallback 17k/70 e trava o mês
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

  -- Materializa metas faltantes para todo consultor/supervisor ativo
  insert into metas_mensais (consultor_id, mes, ano, meta_vendas, meta_cotacoes)
  select u.id, p_mes, p_ano, 17000, 70
  from usuarios u
  where u.perfil in ('consultor','supervisor')
    and coalesce(u.ativo_meta, true) = true
    and not exists (
      select 1 from metas_mensais m
      where m.consultor_id = u.id
        and m.mes = p_mes
        and m.ano = p_ano
    );

  get diagnostics v_inseridos = row_count;

  -- Trava o mês (idempotente)
  insert into meses_travados (mes, ano)
  values (p_mes, p_ano)
  on conflict do nothing;

  return query select
    v_inseridos,
    v_travado_antes,
    format('mês %s/%s: %s metas inseridas (já travado antes: %s)',
           p_mes, p_ano, v_inseridos, v_travado_antes);
end;
$$;

grant execute on function public.fechar_mes(int, int) to authenticated;

-- 2) CORREÇÃO HISTÓRICA: reprocessa todo mês travado que tem metas faltantes.
--    Também garante que agosto/2026 seja processado mesmo se não estava travado.
do $$
declare
  r record;
begin
  -- Todos os meses já travados
  for r in select mes, ano from meses_travados order by ano, mes loop
    perform public.fechar_mes(r.mes, r.ano);
  end loop;
  -- Fecha agosto/2026 se ainda estiver aberto (fallback)
  perform public.fechar_mes(8, 2026);
end $$;

-- 3) AGENDAMENTO — dia 1 de cada mês às 00:05 BRT (= 03:05 UTC)
--    Requer extensão pg_cron. Se der erro "extension does not exist",
--    ative em Dashboard → Database → Extensions → pg_cron.
create extension if not exists pg_cron;

-- Remove agendamento antigo (se existir) pra reagendar limpo
select cron.unschedule('fechar_mes_anterior')
  where exists(select 1 from cron.job where jobname = 'fechar_mes_anterior');

-- Agenda: dia 1 às 03:05 UTC, chama fechar_mes do mês anterior
select cron.schedule(
  'fechar_mes_anterior',
  '5 3 1 * *',
  $CRON$
  select public.fechar_mes(
    case when extract(month from (now() at time zone 'America/Sao_Paulo'))::int = 1
         then 12
         else extract(month from (now() at time zone 'America/Sao_Paulo'))::int - 1 end,
    case when extract(month from (now() at time zone 'America/Sao_Paulo'))::int = 1
         then extract(year from (now() at time zone 'America/Sao_Paulo'))::int - 1
         else extract(year from (now() at time zone 'America/Sao_Paulo'))::int end
  );
  $CRON$
);

-- 4) Verificação — mostra o que aconteceu
select 'Meses travados' as tipo, count(*)::text as valor from meses_travados
union all
select 'Metas em agosto/2026', count(*)::text from metas_mensais where mes=8 and ano=2026
union all
select 'Consultores/supervisores ativos', count(*)::text
  from usuarios where perfil in ('consultor','supervisor') and coalesce(ativo_meta,true)=true
union all
select 'Job pg_cron agendado', coalesce((select schedule from cron.job where jobname='fechar_mes_anterior'),'NÃO AGENDADO');
