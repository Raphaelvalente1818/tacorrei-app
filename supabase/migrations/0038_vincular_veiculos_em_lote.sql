-- [aplicada no banco em 28/08/2026 18:50 — versão 20260828185014]
-- Empresa nova entrando: ela chega com uma lista de placas, não com um carro.
-- Digitar 40 veículos no formulário de lead não é trabalho de gente.
--
-- Boa parte dessas placas JÁ EXISTE na base (vieram do RNTRC como leads soltos).
-- Então a regra é: achou a placa, VINCULA — não cria de novo. Foi exatamente a
-- duplicata de placa que a busca por placa exata já vinha evitando no balcão.
create or replace function public.vincular_veiculos_empresa(
  p_empresa uuid, p_veiculos jsonb
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_unidade uuid; v_nome text; v_tel text;
  v_item jsonb; v_placa text; v_data date;
  v_id uuid; v_dona uuid;
  v_vinculados int := 0; v_criados int := 0; v_movidos int := 0; v_ignorados int := 0;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select e.unidade_id, e.nome, e.telefone into v_unidade, v_nome, v_tel
  from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_veiculos,'[]'::jsonb))
  loop
    v_placa := public.normaliza_placa(v_item->>'placa');
    if v_placa is null or length(v_placa) < 7 then
      v_ignorados := v_ignorados + 1;
      continue;
    end if;
    begin
      v_data := nullif(v_item->>'data','')::date;
    exception when others then
      v_data := null;
    end;

    select c.id, c.empresa_id into v_id, v_dona
    from public.caminhoneiros c
    where c.unidade_id = v_unidade
      and public.normaliza_placa(c.placa_veiculo) = v_placa
    limit 1;

    if v_id is not null then
      update public.caminhoneiros
         set empresa_id = p_empresa,
             data_ultima_afericao = coalesce(v_data, data_ultima_afericao),
             tem_tacografo = case when coalesce(v_data, data_ultima_afericao) is not null
                                  then true else tem_tacografo end
       where id = v_id;
      if v_dona is not null and v_dona <> p_empresa then
        v_movidos := v_movidos + 1;
      else
        v_vinculados := v_vinculados + 1;
      end if;
    else
      -- Veículo de contrato não é lead: nome e telefone são os da empresa, porque
      -- quem responde por ele é o contato dela — o motorista é qualquer um.
      insert into public.caminhoneiros
        (nome, telefone, placa_veiculo, data_ultima_afericao, tem_tacografo,
         unidade_id, empresa_id, origem, status)
      values (v_nome, coalesce(nullif(btrim(coalesce(v_tel,'')),''),'—'),
              v_placa, v_data, v_data is not null,
              v_unidade, p_empresa, 'outro', 'novo');
      v_criados := v_criados + 1;
    end if;
  end loop;

  return jsonb_build_object('vinculados', v_vinculados, 'criados', v_criados,
                            'movidos', v_movidos, 'ignorados', v_ignorados);
end $function$;

revoke execute on function public.vincular_veiculos_empresa(uuid,jsonb) from public;
grant execute on function public.vincular_veiculos_empresa(uuid,jsonb) to authenticated;
