-- =====================================================================
-- SNAPSHOT DE TOTAIS IMUTÁVEIS POR EQUIPE × MÊS
-- Grava meta_total e realizado_total finais no fechamento.
-- Depois disso, NADA mais recalcula — leitura direta da tabela.
-- Rode INTEIRO no SQL Editor. Idempotente.
-- =====================================================================

-- 1) Tabela imutável de totais por equipe × mês
create table if not exists snapshots_equipe_mes(
  equipe_id uuid references equipes(id) on delete cascade,
  mes int not null,
  ano int not null,
  meta_total numeric not null default 0,
  realizado_total numeric not null default 0,
  n_consultores int not null default 0,
  fechado_em timestamptz not null default now(),
  primary key(equipe_id, mes, ano)
);
create index if not exists idx_snap_mes_ano on snapshots_equipe_mes(mes, ano);

alter table snapshots_equipe_mes enable row level security;
drop policy if exists "snapshots read all authenticated" on snapshots_equipe_mes;
create policy "snapshots read all authenticated" on snapshots_equipe_mes
  for select to authenticated using (true);

-- 2) RPC: snapshot dos totais de um mês (todas equipes)
create or replace function public.snapshot_totais_equipes(p_mes int, p_ano int)
returns int
language plpgsql security definer set search_path = public
as $$
declare v_count int := 0;
begin
  insert into snapshots_equipe_mes(equipe_id, mes, ano, meta_total, realizado_total, n_consultores)
  select
    e.id,
    p_mes,
    p_ano,
    public.get_meta_equipe_snapshot(e.id, p_mes, p_ano),
    public.get_realizado_equipe_snapshot(e.id, p_mes, p_ano),
    (select count(*) from metas_mensais mm
       join usuarios u on u.id = mm.consultor_id
      where mm.equipe_id = e.id and mm.mes = p_mes and mm.ano = p_ano
        and u.perfil = 'consultor')
  from equipes e
  on conflict (equipe_id, mes, ano) do update
    set meta_total = excluded.meta_total,
        realizado_total = excluded.realizado_total,
        n_consultores = excluded.n_consultores,
        fechado_em = now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function public.snapshot_totais_equipes(int, int) to authenticated;

-- 3) BACKFILL: snapshot todos os meses já travados com valores atuais
do $$
declare r record;
begin
  for r in select mes, ano from meses_travados order by ano, mes loop
    perform public.snapshot_totais_equipes(r.mes, r.ano);
  end loop;
end $$;

-- 4) Reescreve fechar_mes: no fechamento, ao final, dispara snapshot dos totais
create or replace function public.fechar_mes(p_mes int, p_ano int)
returns table(metas_inseridas int, ja_travado boolean, log text)
language plpgsql security definer set search_path = public
as $$
declare
  v_inseridos int := 0;
  v_travado_antes boolean;
begin
  select exists(select 1 from meses_travados where mes = p_mes and ano = p_ano)
    into v_travado_antes;

  if v_travado_antes then
    return query select 0, true,
      format('mês %s/%s: já travado, snapshot preservado', p_mes, p_ano);
    return;
  end if;

  -- Materializa faltantes com snapshot equipe_id atual
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

  -- Snapshot equipe_id em rows existentes sem valor
  update metas_mensais m
  set equipe_id = u.equipe_id
  from usuarios u
  where m.consultor_id = u.id
    and m.mes = p_mes and m.ano = p_ano
    and m.equipe_id is null;

  -- Trava o mês
  insert into meses_travados (mes, ano) values (p_mes, p_ano) on conflict do nothing;

  -- Snapshotar totais finais IMUTÁVEIS
  perform public.snapshot_totais_equipes(p_mes, p_ano);

  return query select v_inseridos, false,
    format('mês %s/%s: %s metas materializadas + totais congelados', p_mes, p_ano, v_inseridos);
end;
$$;
grant execute on function public.fechar_mes(int, int) to authenticated;

-- 5) Verificação
select 'Meses com snapshot de totais' as tipo,
       (select count(distinct (mes||'-'||ano))::text from snapshots_equipe_mes) as valor
union all
select 'Linhas equipe × mês', count(*)::text from snapshots_equipe_mes
union all
select 'Águias em ago/2026 (meta / realizado)',
  coalesce((select meta_total::text || ' / ' || realizado_total::text
            from snapshots_equipe_mes
            where mes=8 and ano=2026
              and equipe_id=(select id from equipes where nome ilike '%águia%' or nome ilike '%aguia%' limit 1)),
           'não encontrado');
