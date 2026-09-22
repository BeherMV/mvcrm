-- =====================================================================
-- ROLEPLAY — RLS pra Master e Supervisor atualizarem roleplay_liberado
-- Master: qualquer usuário. Supervisor: só consultores da própria equipe.
-- Rode INTEIRO no SQL Editor. Idempotente.
-- =====================================================================

-- Cria/atualiza policy específica pra liberação de Roleplay
-- (mantém as outras policies existentes de usuarios intactas — a policy abaixo é ADICIONAL)

drop policy if exists "usuarios_update_roleplay_liberado" on usuarios;
create policy "usuarios_update_roleplay_liberado" on usuarios
  for update to authenticated
  using (
    -- Master pode atualizar qualquer usuário
    exists (select 1 from usuarios u where u.id = auth.uid() and u.perfil = 'master')
    OR
    -- Supervisor pode atualizar consultores/supervisores da PRÓPRIA equipe
    exists (
      select 1 from usuarios sv
      where sv.id = auth.uid()
        and sv.perfil = 'supervisor'
        and sv.equipe_id = usuarios.equipe_id
        and usuarios.perfil in ('consultor','supervisor')
    )
  );

-- Verificação: rode como master primeiro pra listar o estado atual
select id, nome, perfil, equipe_id, roleplay_liberado
  from usuarios
  where perfil in ('consultor','supervisor')
  order by nome
  limit 20;
