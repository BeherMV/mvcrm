-- =====================================================================
-- Trava anti-duplicata de LEAD por telefone — dentro do funil do CONSULTOR
-- Regra: se o consultor já tem um lead com o mesmo telefone (normalizado
-- pra só dígitos), bloqueia. Não bloqueia se o duplicado está com outro
-- consultor — cada um gerencia seu próprio funil.
-- Rode INTEIRO como master no SQL Editor. Idempotente.
-- =====================================================================

create or replace function public.lead_duplicado_meu(
  p_telefone text,
  p_excluir_lead_id uuid default null
)
returns table(
  lead_id uuid,
  lead_nome text,
  mes_cotacao int,
  ano_cotacao int,
  status text,
  criado_em timestamptz
)
language sql
stable
set search_path = public
as $$
  with tel as (
    select regexp_replace(coalesce(p_telefone,''), '[^0-9]', '', 'g') as digits
  )
  select l.id, l.nome, l.mes_cotacao, l.ano_cotacao, l.status, l.criado_em
  from leads l
  cross join tel
  where tel.digits <> ''
    and l.consultor_id = auth.uid()
    and regexp_replace(coalesce(l.telefone,''), '[^0-9]', '', 'g') = tel.digits
    and (p_excluir_lead_id is null or l.id <> p_excluir_lead_id)
  order by l.criado_em desc
  limit 1
$$;

grant execute on function public.lead_duplicado_meu(text, uuid) to authenticated;

-- Verificação
select 'função criada' as tipo, 'ok' as valor;
