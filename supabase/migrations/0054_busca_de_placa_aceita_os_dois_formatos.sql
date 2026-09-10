-- [aplicada no banco em 09/09/2026 18:36 — versão 20260909183611]
-- ── 0054 — buscar placa nos DOIS formatos ───────────────────────────────────
--
-- Consequência de guardar a placa como está no cadastro do cliente: agora a
-- base tem FFA-5029 (antiga) e SWS2F95 (Mercosul) convivendo. E no balcão a
-- menina digita o que está pregado no caminhão — que pode ser o outro formato.
-- Sem isto ela busca, não acha, e cria um cadastro duplicado: exatamente o erro
-- que o índice único e a fusão da migration 0041 existiram para consertar.
--
-- A regra é bijetiva, então basta comparar as duas formas canônicas.

create or replace function public.mercosul(p text)
returns text language sql immutable as $$
  select case
    when p ~ '^[A-Z]{3}[0-9]{4}$'
    then left(p,4) || translate(substr(p,5,1), '0123456789', 'ABCDEFGHIJ') || right(p,2)
    else p
  end;
$$;

comment on function public.mercosul(text) is
  'Converte placa antiga para Mercosul: 5º caractere de dígito para letra. Par de desmercosul().';

create index if not exists idx_caminhoneiros_placa_mercosul
  on public.caminhoneiros (unidade_id,
    public.mercosul(upper(regexp_replace(coalesce(placa_veiculo,''),'[^A-Z0-9]','','g'))));

create or replace function public.buscar_por_placa(p_placa text)
returns jsonb language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare v_placa text; v_merc text; v_lead jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_placa := public.normaliza_placa(p_placa);
  if v_placa is null or length(v_placa) < 7 then
    raise exception 'informe a placa completa (7 caracteres)';
  end if;
  -- Forma canônica: qualquer formato digitado vira Mercosul só para comparar.
  v_merc := public.mercosul(v_placa);

  select to_jsonb(c) || jsonb_build_object(
           'empresa_nome', e.nome,
           'empresa_contato', e.contato,
           'empresa_telefone', e.telefone)
    into v_lead
  from public.caminhoneiros c
  left join public.empresas e on e.id = c.empresa_id
  where public.mercosul(public.normaliza_placa(c.placa_veiculo)) = v_merc
    and (public.is_admin() or c.unidade_id = public.unidade_do_usuario())
  order by c.data_ultima_afericao desc nulls last
  limit 1;

  perform public.registrar_acesso('placa', case when v_lead is null then 0 else 1 end,
    jsonb_build_object('placa', v_placa, 'achou', v_lead is not null));

  return v_lead;
end $function$;

-- A busca dentro da frota também: ela pode digitar o formato do caminhão.
create or replace function public.frota_da_empresa(
  p_empresa uuid, p_busca text default null)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_temp' as $function$
declare v jsonb; v_unidade uuid; v_busca text; v_placa text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select e.unidade_id into v_unidade from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_busca := nullif(btrim(coalesce(p_busca,'')),'');
  v_placa := case when v_busca is not null
                  then public.mercosul(public.normaliza_placa(v_busca)) end;

  select coalesce(jsonb_agg(x order by x.venc nulls last, x.numero_empresa), '[]'::jsonb) into v
  from (
    select c.id, c.placa_veiculo as placa, c.numero_empresa, c.modelo_veiculo as modelo,
           c.observacoes, c.data_ultima_afericao,
           (c.data_ultima_afericao + interval '2 years')::date as venc
    from public.caminhoneiros c
    where c.empresa_id = p_empresa
      and (v_busca is null
           or c.placa_veiculo ilike '%'||v_busca||'%'
           or c.numero_empresa ilike '%'||v_busca||'%'
           or c.observacoes ilike '%'||v_busca||'%'
           or public.mercosul(public.normaliza_placa(c.placa_veiculo)) = v_placa)
  ) x;

  perform public.registrar_acesso('listar', jsonb_array_length(v),
    jsonb_build_object('frota', p_empresa, 'busca', v_busca));
  return v;
end $function$;

revoke execute on function public.mercosul(text) from public, anon;
revoke execute on function public.desmercosul(text) from public, anon;
grant execute on function public.mercosul(text) to authenticated, service_role;
grant execute on function public.desmercosul(text) to authenticated, service_role;
