-- [aplicada no banco em 09/09/2026 14:45 — versão 20260909144519]
-- ── 0048 — a frota inteira, e a observação por placa ────────────────────────
--
-- `veiculos_da_empresa` só devolve os que vencem NAQUELE mês — é a função da
-- relação mensal, e continua assim. Faltava enxergar a frota INTEIRA, com o
-- número interno (que é como o cliente chama o caminhão) e um campo de
-- observação por placa: "está na oficina", "motorista sumiu com o documento",
-- "esse é reboque". Sem isso a informação vive no WhatsApp da menina.

create or replace function public.frota_da_empresa(
  p_empresa uuid, p_busca text default null)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_temp' as $function$
declare v jsonb; v_unidade uuid; v_busca text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select e.unidade_id into v_unidade from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_busca := nullif(btrim(coalesce(p_busca,'')),'');

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
           or c.observacoes ilike '%'||v_busca||'%')
  ) x;

  perform public.registrar_acesso('listar', jsonb_array_length(v),
    jsonb_build_object('frota', p_empresa, 'busca', v_busca));
  return v;
end $function$;

-- Grava a observação de UM veículo. Vai por RPC e não por update direto para
-- ficar no log de acesso e para a checagem de unidade acontecer no servidor.
create or replace function public.salvar_obs_veiculo(p_lead uuid, p_obs text)
returns void language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'veiculo nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  update public.caminhoneiros
     set observacoes = nullif(btrim(coalesce(p_obs,'')),''), updated_at = now()
   where id = p_lead;
end $function$;

revoke execute on function public.frota_da_empresa(uuid, text) from public, anon;
revoke execute on function public.salvar_obs_veiculo(uuid, text) from public, anon;
grant execute on function public.frota_da_empresa(uuid, text) to authenticated, service_role;
grant execute on function public.salvar_obs_veiculo(uuid, text) to authenticated, service_role;
