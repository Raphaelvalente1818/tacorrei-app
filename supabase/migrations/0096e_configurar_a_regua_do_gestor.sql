-- 0096e — os dois parâmetros da régua do gestor entram na tela de configuração.
--
-- Eles entram na lista `v_geral`, que só o admin geral pode gravar. É de
-- propósito: quem tem o papel admin_unidade não pode alargar a própria janela.
-- Se pudesse, a régua não seria uma régua — seria um pedido.
--
-- Os limites: janela do gestor entre 1 e 365 dias; agrupamento entre 1 e 3650.
-- A conferência (0096b) ainda exige, por unidade, que a janela do gestor não
-- seja menor que a da operadora e que o agrupamento não seja menor que a
-- janela — uma régua de gestor mais apertada que a de quem liga não faz sentido
-- e derruba o portão na hora.
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'configurar_unidade';
  if v_def is null then raise exception 'configurar_unidade nao encontrada'; end if;

  v_velho := '''cooldown_telefone_dias'',''agrupamento_dias'',''unidade_edita_premio''];';
  v_novo  := '''cooldown_telefone_dias'',''agrupamento_dias'',''unidade_edita_premio'',
                          ''janela_gestor_dias'',''agrupamento_gestor_dias''];';
  if position(v_velho in v_def) = 0 then
    raise exception 'a lista de campos gerais nao foi encontrada';
  end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '        if k = ''agrupamento_dias'' and (v_int is null or v_int < 0 or v_int > 365) then raise exception ''agrupamento entre 0 e 365 dias''; end if;';
  v_novo  := '        if k = ''agrupamento_dias'' and (v_int is null or v_int < 0 or v_int > 365) then raise exception ''agrupamento entre 0 e 365 dias''; end if;
        if k = ''janela_gestor_dias'' and (v_int is null or v_int < 1 or v_int > 365) then raise exception ''janela do gestor entre 1 e 365 dias''; end if;
        if k = ''agrupamento_gestor_dias'' and (v_int is null or v_int < 1 or v_int > 3650) then raise exception ''agrupamento do gestor entre 1 e 3650 dias''; end if;';
  if position(v_velho in v_def) = 0 then
    raise exception 'a validacao do agrupamento nao foi encontrada';
  end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;

revoke all on function public.configurar_unidade(uuid, jsonb) from public, anon;
grant execute on function public.configurar_unidade(uuid, jsonb) to authenticated, service_role;
