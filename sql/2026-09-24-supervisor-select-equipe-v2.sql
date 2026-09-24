-- =====================================================================
-- FIX RLS v2 — Supervisor lê usuários da equipe (sem recursão)
-- v1 causou recursão infinita (policy SELECT em usuarios consultando usuarios).
-- v2 usa funções SECURITY DEFINER que bypassam RLS ao ler o próprio user.
-- Rode INTEIRO como master no SQL Editor. Idempotente.
-- =====================================================================

-- 1) Função helper: perfil do usuário logado (bypassa RLS)
create or replace function public.get_meu_perfil()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select perfil from usuarios where id = auth.uid()
$$;

-- 2) Função helper: equipe_id do usuário logado (bypassa RLS)
create or replace function public.get_minha_equipe()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select equipe_id from usuarios where id = auth.uid()
$$;

grant execute on function public.get_meu_perfil() to authenticated;
grant execute on function public.get_minha_equipe() to authenticated;

-- 3) Policy SELECT: supervisor lê consultores/supervisores da PRÓPRIA equipe
drop policy if exists "usuarios_select_supervisor_equipe" on usuarios;
create policy "usuarios_select_supervisor_equipe" on usuarios
  for select to authenticated
  using (
    get_meu_perfil() = 'supervisor'
    and equipe_id = get_minha_equipe()
  );

-- 4) Policy SELECT: master lê qualquer usuário
drop policy if exists "usuarios_select_master" on usuarios;
create policy "usuarios_select_master" on usuarios
  for select to authenticated
  using (get_meu_perfil() = 'master');

-- 5) Verificação
select policyname, cmd
  from pg_policies
  where schemaname='public' and tablename='usuarios'
  order by cmd, policyname;
