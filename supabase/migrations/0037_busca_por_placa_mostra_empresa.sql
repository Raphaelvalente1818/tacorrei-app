-- [aplicada no banco em 28/08/2026 18:46 — versão 20260828184659]
-- Na empresa, quem recebe o aviso é sempre a mesma pessoa; quem traz o caminhão é
-- qualquer motorista. Ou seja: no balcão a PLACA é a única identidade disponível.
-- A busca por placa passa a devolver de quem é o veículo, para a atendente ver na
-- hora que aquele caminhão é de contrato — e registrar a aferição no lugar certo.
create or replace function public.buscar_por_placa(p_placa text)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_placa text; v_lead jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_placa := public.normaliza_placa(p_placa);
  if v_placa is null or length(v_placa) < 7 then
    raise exception 'informe a placa completa (7 caracteres)';
  end if;

  select to_jsonb(c) || jsonb_build_object(
           'empresa_nome', e.nome,
           'empresa_contato', e.contato,
           'empresa_telefone', e.telefone)
    into v_lead
  from public.caminhoneiros c
  left join public.empresas e on e.id = c.empresa_id
  where public.normaliza_placa(c.placa_veiculo) = v_placa
    and (public.is_admin() or c.unidade_id = public.unidade_do_usuario())
  order by c.data_ultima_afericao desc nulls last
  limit 1;

  perform public.registrar_acesso('placa', case when v_lead is null then 0 else 1 end,
    jsonb_build_object('placa', v_placa, 'achou', v_lead is not null));

  return v_lead;
end $function$;
