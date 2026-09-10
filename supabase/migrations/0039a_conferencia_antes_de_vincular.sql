-- [aplicada no banco em 28/08/2026 19:33 — versão 20260828193341]
-- Nada é gravado sem a pessoa ver o que vai acontecer. A colagem passa a ter duas
-- etapas: primeiro esta análise, que só LÊ, depois o vínculo.
--
-- O caso que exige olho humano é a placa que já pertence a OUTRA empresa. Mover
-- em silêncio tiraria o caminhão da relação mensal da empresa antiga — ela pararia
-- de ser avisada daquele veículo e ninguém descobriria até o cliente reclamar.
create or replace function public.analisar_veiculos_empresa(
  p_empresa uuid, p_veiculos jsonb
) returns jsonb
language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_unidade uuid; v_item jsonb; v_placa text;
  v_id uuid; v_dona uuid; v_dona_nome text; v_dono text;
  v_novas jsonb := '[]'::jsonb;
  v_leads jsonb := '[]'::jsonb;
  v_mesma jsonb := '[]'::jsonb;
  v_outras jsonb := '[]'::jsonb;
  v_invalidas jsonb := '[]'::jsonb;
  v_vistas text[] := '{}';
  v_repetidas jsonb := '[]'::jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select e.unidade_id into v_unidade from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_veiculos,'[]'::jsonb))
  loop
    v_placa := public.normaliza_placa(v_item->>'placa');

    if v_placa is null or length(v_placa) < 7 then
      v_invalidas := v_invalidas || jsonb_build_array(coalesce(v_item->>'placa','(vazio)'));
      continue;
    end if;

    -- Placa repetida dentro da própria colagem: erro de planilha, avisa.
    if v_placa = any(v_vistas) then
      v_repetidas := v_repetidas || jsonb_build_array(v_placa);
      continue;
    end if;
    v_vistas := v_vistas || v_placa;

    select c.id, c.empresa_id, c.nome into v_id, v_dona, v_dono
    from public.caminhoneiros c
    where c.unidade_id = v_unidade
      and public.normaliza_placa(c.placa_veiculo) = v_placa
    limit 1;

    if v_id is null then
      v_novas := v_novas || jsonb_build_array(jsonb_build_object('placa', v_placa));
    elsif v_dona is null then
      v_leads := v_leads || jsonb_build_array(
        jsonb_build_object('placa', v_placa, 'dono', v_dono));
    elsif v_dona = p_empresa then
      v_mesma := v_mesma || jsonb_build_array(jsonb_build_object('placa', v_placa));
    else
      select e.nome into v_dona_nome from public.empresas e where e.id = v_dona;
      v_outras := v_outras || jsonb_build_array(
        jsonb_build_object('placa', v_placa, 'empresa', v_dona_nome));
    end if;
  end loop;

  return jsonb_build_object(
    'novas', v_novas, 'leads', v_leads, 'mesma_empresa', v_mesma,
    'outras_empresas', v_outras, 'invalidas', v_invalidas, 'repetidas', v_repetidas);
end $function$;

revoke execute on function public.analisar_veiculos_empresa(uuid,jsonb) from public;
grant execute on function public.analisar_veiculos_empresa(uuid,jsonb) to authenticated;
