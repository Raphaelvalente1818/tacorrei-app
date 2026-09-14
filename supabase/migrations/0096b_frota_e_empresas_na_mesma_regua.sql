-- 0096b — a frota e a lista de empresas obedecem a mesma régua.
--
-- Sem isto, a 0096 seria enfeite. Medido em 14/09/2026:
--
--   a) a tabela `empresas` estava aberta para leitura direta. A política dela é
--      uma linha só — "é da minha unidade" — e o papel `authenticated` tinha
--      select em todas as colunas. Qualquer pessoa logada da unidade (gestor OU
--      operadora) pedia uma vez pela API e recebia:
--          São Bernardo  639 frotas, 628 com telefone
--          Santo André   266 frotas, 261 com telefone
--      Sem janela, sem paginação. E para frota, o telefone da empresa É o lead.
--      Em `caminhoneiros` esse buraco já tinha sido fechado (o papel logado só
--      lê a coluna `id`); em `empresas`, não.
--
--   b) frota_da_empresa devolvia a frota inteira, de qualquer horizonte, para
--      quem pedisse — sem passar por pode_ler_lead.
--
-- O que muda:
--   1. `empresas` passa a dar leitura direta só das colunas que as telas usam
--      (id, nome, unidade_id, ativo, situacao). CNPJ, contato e TELEFONE saem
--      da API — quem precisa deles são as funções do painel, que são
--      SECURITY DEFINER e continuam enxergando tudo.
--   2. frota_da_empresa e veiculos_da_empresa passam pela régua do gestor.
--   3. O gestor ganha o panorama do ano: a contagem de vencimentos mês a mês,
--      os doze meses, sem nome, sem placa, sem telefone. Número não se disca —
--      é o que faz ele entender o tamanho do ativo sem alcançar as fichas.
--
-- Para a operadora nada muda: as telas dela não leem essas colunas direto, e a
-- frota continua inteira na ficha, que é como ela trabalha.

-- 1. A pergunta "esta frota está em jogo agora?", para quem precisa dela uma
--    vez só. Nas listas a mesma pergunta é feita como conjunto (0096).
create or replace function public.frota_em_jogo(p_empresa uuid)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select not public.is_admin_unidade()
      or exists (
        select 1
          from public.caminhoneiros f
         where f.empresa_id = p_empresa
           and f.tem_tacografo
           and f.data_ultima_afericao is not null
           and (f.data_ultima_afericao + interval '2 years')::date
               between current_date - coalesce(public.piso_do_usuario(), 365)
                   and current_date + coalesce(public.janela_gestor_do_usuario(), 60));
$$;

revoke all on function public.frota_em_jogo(uuid) from public, anon;
grant execute on function public.frota_em_jogo(uuid) to authenticated, service_role;

-- 2. A leitura direta de `empresas` fica só nas colunas que as telas usam.
--    EmpresaModal grava e lê de volta id,nome; NovoLeadModal lista id,nome
--    filtrando por ativo. Nada no navegador precisa de telefone, cnpj ou
--    contato — isso vem por empresas_painel / obter_lead / frota_da_empresa.
revoke select on public.empresas from authenticated;
grant select (id, nome, unidade_id, ativo, situacao) on public.empresas to authenticated;

-- 3. frota_da_empresa e veiculos_da_empresa passam pela régua do gestor.
--    Reescrita programática a partir da definição no banco: substituição exata,
--    e falha se o trecho não existir — nunca "quase aplicou".
do $$
declare v_def text; v_velho text; v_novo text;
begin
  -- --- frota_da_empresa ---
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'frota_da_empresa';
  if v_def is null then raise exception 'frota_da_empresa nao encontrada'; end if;

  v_velho := '  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception ''acesso negado'';
  end if;';
  v_novo := '  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception ''acesso negado'';
  end if;
  -- régua do gestor: frota que não está em jogo agora não abre (0096b)
  if not public.frota_em_jogo(p_empresa) then
    raise exception ''acesso negado'';
  end if;';
  if position(v_velho in v_def) = 0 then
    raise exception 'guarda de acesso nao encontrada em frota_da_empresa';
  end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '    where c.empresa_id = p_empresa
      and (v_busca is null';
  v_novo := '    where c.empresa_id = p_empresa
      and (not public.is_admin_unidade()
           or (c.data_ultima_afericao is not null
               and (c.data_ultima_afericao + interval ''2 years'')::date
                   <= current_date + coalesce(public.agrupamento_gestor_do_usuario(), 365)))
      and (v_busca is null';
  if position(v_velho in v_def) = 0 then
    raise exception 'filtro da lista nao encontrado em frota_da_empresa';
  end if;
  v_def := replace(v_def, v_velho, v_novo);
  execute v_def;

  -- --- veiculos_da_empresa ---
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'veiculos_da_empresa';
  if v_def is null then raise exception 'veiculos_da_empresa nao encontrada'; end if;

  v_velho := '  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception ''acesso negado'';
  end if;';
  v_novo := '  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception ''acesso negado'';
  end if;
  -- régua do gestor: frota que não está em jogo agora não abre (0096b)
  if not public.frota_em_jogo(p_empresa) then
    raise exception ''acesso negado'';
  end if;';
  if position(v_velho in v_def) = 0 then
    raise exception 'guarda de acesso nao encontrada em veiculos_da_empresa';
  end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '  where c.empresa_id = p_empresa and c.tem_tacografo
    and c.data_ultima_afericao is not null';
  v_novo := '  where c.empresa_id = p_empresa and c.tem_tacografo
    and c.data_ultima_afericao is not null
    and (not public.is_admin_unidade()
         or (c.data_ultima_afericao + interval ''2 years'')::date
             <= current_date + coalesce(public.agrupamento_gestor_do_usuario(), 365))';
  if position(v_velho in v_def) = 0 then
    raise exception 'filtro da lista nao encontrado em veiculos_da_empresa';
  end if;
  v_def := replace(v_def, v_velho, v_novo);
  execute v_def;
end $$;

-- 4. O panorama do ano: só números. O gestor vê quantos caminhões vencem em
--    cada mês dos próximos doze — e nenhum deles. É o que sustenta a conversa
--    de investimento sem entregar a base.
create or replace function public.panorama_do_ano(p_unidade uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_uni uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_uni := coalesce(p_unidade, public.unidade_do_usuario());
  if not (public.is_admin() or v_uni = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  select jsonb_build_object(
    'meses', coalesce(jsonb_agg(jsonb_build_object('mes', x.mes, 'total', x.total)
                                order by x.mes), '[]'::jsonb),
    'total', coalesce(sum(x.total), 0)
  ) into v
  from (
    select to_char(b.venc, 'YYYY-MM') as mes, count(*) as total
      from public.base_trabalhavel(v_uni) b
     where b.na_fila
       and b.venc >= date_trunc('month', current_date)::date
       and b.venc < (date_trunc('month', current_date) + interval '12 months')::date
     group by 1
  ) x;

  perform public.registrar_acesso('panorama', 0, jsonb_build_object('unidade', v_uni));
  return v;
end $function$;

revoke all on function public.panorama_do_ano(uuid) from public, anon;
grant execute on function public.panorama_do_ano(uuid) to authenticated, service_role;

-- 5. A conferência ganha duas checagens por unidade (de 15 para 17; 34 no total).
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'conferencia_contagens';
  if v_def is null then raise exception 'conferencia_contagens nao encontrada'; end if;

  v_velho := '    ok := a = b; return next;
  end loop;';

  v_novo := '    ok := a = b; return next;

    checagem := ''Panorama do ano = regua na fila nos 12 meses'';
    a := (public.panorama_do_ano(u.id)->>''total'')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t
     where t.na_fila
       and t.venc >= date_trunc(''month'', current_date)::date
       and t.venc < (date_trunc(''month'', current_date) + interval ''12 months'')::date;
    ok := a = b; return next;

    checagem := ''Regua do gestor nunca e mais apertada que a da operadora'';
    select 1 into a;
    select case when u.janela_gestor_dias >= u.janela_dias
                 and u.agrupamento_gestor_dias >= u.janela_gestor_dias
                then 1 else 0 end into b
      from public.unidades where id = u.id;
    ok := a = b; return next;
  end loop;';

  if position(v_velho in v_def) = 0 then
    raise exception 'o fecho do laco nao foi encontrado em conferencia_contagens';
  end if;

  execute replace(v_def, v_velho, v_novo);
end $$;

revoke all on function public.conferencia_contagens() from public, anon;
grant execute on function public.conferencia_contagens() to authenticated, service_role;
