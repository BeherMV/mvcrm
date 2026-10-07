-- =====================================================================
-- MASTER — alterar senha de qualquer usuário pela tela de Gestão de Usuários
-- RPC security definer: só executa se quem chama for perfil 'master'.
-- Derruba as sessões abertas do usuário (precisa logar com a senha nova).
-- Rode INTEIRO como master no SQL Editor. Idempotente.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_alterar_senha(p_user_id uuid, p_senha text)
returns void
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
begin
  if not exists (select 1 from public.usuarios where id = auth.uid() and perfil = 'master') then
    raise exception 'Apenas o master pode alterar senhas.';
  end if;
  if p_senha is null or length(p_senha) < 8 then
    raise exception 'A senha deve ter no mínimo 8 caracteres.';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_user_id;
  if not found then
    raise exception 'Usuário não encontrado.';
  end if;

  -- Encerra sessões abertas do usuário
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;
end;
$$;

revoke all on function public.admin_alterar_senha(uuid, text) from public, anon;
grant execute on function public.admin_alterar_senha(uuid, text) to authenticated;
