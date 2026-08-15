-- Operador (funcionária) só enxerga leads COM tacógrafo da sua unidade.
-- Admin continua vendo tudo (inclusive os sem tacógrafo). Aplicada em 15/08/2026.
drop policy if exists "caminhoneiros: le unidade" on public.caminhoneiros;
create policy "caminhoneiros: le unidade" on public.caminhoneiros for select
  using (
    is_equipe_ativa() and (
      is_admin()
      or (unidade_id = unidade_do_usuario() and tem_tacografo = true)
    )
  );
