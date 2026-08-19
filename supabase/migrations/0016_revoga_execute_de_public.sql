-- 0016_revoga_execute_de_public.sql
-- A 0015 revogou de `anon`, mas nao adiantou: o PostgreSQL concede EXECUTE a
-- `public` por padrao, e `anon` herda dai. O certo e revogar de `public` e
-- devolver so para `authenticated`.
--
-- ATENCAO: `is_admin`, `is_equipe_ativa`, `unidade_do_usuario`, `janela_do_usuario`
-- e `gere_unidade` sao chamadas DENTRO das policies de RLS. O usuario que consulta
-- precisa de EXECUTE nelas, senao TODA consulta quebra. Por isso continuam
-- liberadas para `authenticated` -- o aviso do linter para esse papel e esperado,
-- nao e falha: sem isso a RLS nao funciona.
do $$
declare f text;
begin
  foreach f in array array[
    'public.is_admin()','public.is_admin_unidade()','public.is_equipe_ativa()',
    'public.unidade_do_usuario()','public.janela_do_usuario()','public.gere_unidade(uuid)',
    'public.placar_unidades()','public.unidades_painel()',
    'public.producao_unidades(integer)','public.producao_operadores(integer)',
    'public.resync_cobertura()'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant  execute on function %s to authenticated', f);
  end loop;
end $$;
