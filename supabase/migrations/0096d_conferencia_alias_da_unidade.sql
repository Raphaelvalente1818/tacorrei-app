-- 0096d — conserta a checagem nova da conferência: o apelido da tabela perdia
-- para o registro do laço.
--
-- Erro pego ao rodar o portão:
--   record "u" has no field "janela_gestor_dias"
--
-- A checagem que a 0096b acrescentou escreveu `from public.unidades where id = u.id`
-- e comparou `u.janela_gestor_dias`. Dentro de plpgsql, `u` já é o registro do
-- laço (que traz só algumas colunas) e ele GANHA do apelido implícito da tabela
-- na consulta. O resultado não é um erro de digitação: é a função lendo o campo
-- do lugar errado — e, se o registro do laço tivesse um campo de mesmo nome,
-- teria passado silenciosamente com o valor errado.
--
-- Lição: em plpgsql, toda tabela consultada dentro de um laço FOR precisa de
-- apelido explícito diferente do nome do registro.
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'conferencia_contagens';
  if v_def is null then raise exception 'conferencia_contagens nao encontrada'; end if;

  v_velho := '    select case when u.janela_gestor_dias >= u.janela_dias
                 and u.agrupamento_gestor_dias >= u.janela_gestor_dias
                then 1 else 0 end into b
      from public.unidades where id = u.id;';

  v_novo := '    select case when x.janela_gestor_dias >= x.janela_dias
                 and x.agrupamento_gestor_dias >= x.janela_gestor_dias
                then 1 else 0 end into b
      from public.unidades x where x.id = u.id;';

  if position(v_velho in v_def) = 0 then
    raise exception 'a checagem da regua do gestor nao foi encontrada';
  end if;

  execute replace(v_def, v_velho, v_novo);
end $$;

revoke all on function public.conferencia_contagens() from public, anon;
grant execute on function public.conferencia_contagens() to authenticated, service_role;
