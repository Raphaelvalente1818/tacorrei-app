-- [aplicada no banco em 28/08/2026 18:34 — versão 20260828183401]
-- Veículo que pertence a empresa com contrato SAI da fila de prospecção.
-- A regra de visibilidade (`pode_ler_lead`) continua a mesma — isto aqui é escopo,
-- não permissão: o carro não some, ele muda de tela, indo para Empresas.
-- (O `empresa_id is null` daqui foi revisto na 0043: passou a esconder só contrato.)
create or replace function public.listar_leads(
  p_pagina integer default 1, p_tamanho integer default 100,
  p_filtro text default 'todos', p_busca text default null,
  p_unidade uuid default null, p_mes text default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare v_tam integer; v_ini integer; v_busca text; v_mes text; v_total bigint; v_linhas jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if p_tamanho is not null and p_tamanho > 100 then
    raise exception 'tamanho de pagina acima do permitido (maximo 100)';
  end if;

  v_tam := least(greatest(coalesce(p_tamanho,100),1),100);
  v_ini := greatest(coalesce(p_pagina,1)-1,0) * v_tam;
  v_busca := nullif(btrim(coalesce(p_busca,'')),'');
  v_mes := nullif(btrim(coalesce(p_mes,'')),'');

  with visiveis as (
    select c.* from public.caminhoneiros c
    where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      and c.empresa_id is null
      and (p_unidade is null or c.unidade_id = p_unidade)
      and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
      and (v_mes is null
           or to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') = v_mes)
      and (v_busca is null
           or c.nome ilike '%'||v_busca||'%' or c.telefone ilike '%'||v_busca||'%'
           or c.cidade ilike '%'||v_busca||'%' or c.placa_veiculo ilike '%'||v_busca||'%')
  )
  select (select count(*) from visiveis),
         coalesce((select jsonb_agg(to_jsonb(p) order by p.data_ultima_afericao asc nulls last, p.id)
                   from (select * from visiveis order by data_ultima_afericao asc nulls last, id
                         offset v_ini limit v_tam) p), '[]'::jsonb)
  into v_total, v_linhas;

  perform public.registrar_acesso('listar', jsonb_array_length(v_linhas),
    jsonb_build_object('filtro',p_filtro,'busca',v_busca,'mes',v_mes,
                       'pagina',coalesce(p_pagina,1),'unidade',p_unidade));

  return jsonb_build_object('total', v_total, 'leads', v_linhas);
end $function$;

create or replace function public.meses_de_vencimento(p_unidade uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select coalesce(jsonb_agg(x order by x.mes), '[]'::jsonb) into v
  from (
    select to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') as mes,
           count(*) as total, count(*) filter (where c.status = 'novo') as novos
    from public.caminhoneiros c
    where c.tem_tacografo and c.data_ultima_afericao is not null and c.empresa_id is null
      and public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      and (p_unidade is null or c.unidade_id = p_unidade)
    group by 1) x;
  return v;
end $function$;

-- ── Painel das empresas ──────────────────────────────────────────────────────
-- Uma linha por empresa: quantos veículos tem, quantos vencem na competência
-- pedida, e se já foi avisada naquele mês.
create or replace function public.empresas_painel(
  p_unidade uuid default null, p_competencia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare v jsonb; v_comp date;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  -- padrão: o mês QUE VEM, que é o que se avisa
  v_comp := coalesce(p_competencia, date_trunc('month', current_date + interval '1 month')::date);

  select coalesce(jsonb_agg(x order by x.vencendo desc, x.nome), '[]'::jsonb) into v
  from (
    select e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id,
           v_comp as competencia,
           count(c.id) filter (where c.tem_tacografo) as veiculos,
           count(c.id) filter (
             where c.tem_tacografo and c.data_ultima_afericao is not null
               and date_trunc('month', (c.data_ultima_afericao + interval '2 years'))::date = v_comp
           ) as vencendo,
           (select a.enviado_em from public.avisos_empresa a
             where a.empresa_id = e.id and a.competencia = v_comp) as avisada_em
    from public.empresas e
    left join public.caminhoneiros c on c.empresa_id = e.id
    where e.ativo
      and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())
      and (p_unidade is null or e.unidade_id = p_unidade)
    group by e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id
  ) x;
  return v;
end $function$;

-- Os veículos daquela empresa que vencem na competência — é a relação que vai na
-- mensagem, e a mesma lista que fica gravada no registro do aviso.
create or replace function public.veiculos_da_empresa(
  p_empresa uuid, p_competencia date default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare v jsonb; v_comp date; v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select e.unidade_id into v_unidade from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_comp := coalesce(p_competencia, date_trunc('month', current_date + interval '1 month')::date);

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'placa', c.placa_veiculo, 'modelo', c.modelo_veiculo,
           'vence', (c.data_ultima_afericao + interval '2 years')::date)
         order by (c.data_ultima_afericao + interval '2 years')::date), '[]'::jsonb)
    into v
  from public.caminhoneiros c
  where c.empresa_id = p_empresa and c.tem_tacografo
    and c.data_ultima_afericao is not null
    and date_trunc('month', (c.data_ultima_afericao + interval '2 years'))::date = v_comp;

  return v;
end $function$;

create or replace function public.registrar_aviso_empresa(
  p_empresa uuid, p_competencia date, p_mensagem text default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare v_unidade uuid; v_veiculos jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select e.unidade_id into v_unidade from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_veiculos := public.veiculos_da_empresa(p_empresa, p_competencia);
  if jsonb_array_length(v_veiculos) = 0 then
    raise exception 'esta empresa nao tem veiculos vencendo nesta competencia';
  end if;

  insert into public.avisos_empresa (empresa_id, competencia, operador_id, veiculos, mensagem)
  values (p_empresa, date_trunc('month', p_competencia)::date, auth.uid(), v_veiculos, p_mensagem)
  on conflict (empresa_id, competencia) do nothing;

  return jsonb_build_object('veiculos', v_veiculos);
end $function$;

revoke execute on function public.empresas_painel(uuid,date) from public;
grant execute on function public.empresas_painel(uuid,date) to authenticated;
revoke execute on function public.veiculos_da_empresa(uuid,date) from public;
grant execute on function public.veiculos_da_empresa(uuid,date) to authenticated;
revoke execute on function public.registrar_aviso_empresa(uuid,date,text) from public;
grant execute on function public.registrar_aviso_empresa(uuid,date,text) to authenticated;
