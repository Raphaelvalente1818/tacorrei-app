-- [aplicada no banco em 28/08/2026 19:21 — versão 20260828192117]
-- Cada unidade cola a própria base. A unidade NÃO vem na planilha — vem de quem
-- está logado, que é a única forma de uma não invadir a área da outra.
--
-- Uma passada só faz as duas coisas: cria/atualiza a empresa pelo CNPJ e pendura
-- o veículo pela placa. Sem isso, seriam 80 cadastros manuais antes de colar a
-- primeira placa.
--
-- Regra que evita o estrago silencioso: placa que JÁ EXISTE na unidade é
-- vinculada, nunca duplicada. Boa parte dessas placas está na base como lead
-- solto vindo do RNTRC; duplicar faria o carro sumir da relação da empresa.
--
-- ⚠️ O fallback `unidade_do_usuario()` daqui mandou 6.128 veículos para a unidade
-- errada em 09/09. Foi removido na 0064.
create or replace function public.importar_base_empresas(
  p_linhas jsonb, p_unidade uuid default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_unidade uuid; v_item jsonb;
  v_cnpj text; v_nome text; v_contato text; v_tel text; v_obs text;
  v_placa text; v_data date; v_modelo text;
  v_empresa uuid; v_id uuid; v_dona uuid;
  v_emp_novas int := 0; v_emp_atualizadas int := 0;
  v_vinculados int := 0; v_criados int := 0; v_movidos int := 0; v_ignorados int := 0;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  -- Admin pode escolher a unidade; qualquer outro papel importa só para a sua.
  if public.is_admin() and p_unidade is not null then
    v_unidade := p_unidade;
  else
    v_unidade := public.unidade_do_usuario();
  end if;
  if v_unidade is null then raise exception 'sem unidade definida para a importacao'; end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_linhas,'[]'::jsonb))
  loop
    v_cnpj   := nullif(regexp_replace(coalesce(v_item->>'cnpj',''), '\D', '', 'g'), '');
    v_nome   := nullif(btrim(coalesce(v_item->>'empresa','')),'');
    v_contato:= nullif(btrim(coalesce(v_item->>'contato','')),'');
    v_tel    := nullif(btrim(coalesce(v_item->>'telefone','')),'');
    v_obs    := nullif(btrim(coalesce(v_item->>'observacoes','')),'');
    v_modelo := nullif(btrim(coalesce(v_item->>'modelo','')),'');
    v_placa  := public.normaliza_placa(v_item->>'placa');
    begin
      v_data := nullif(v_item->>'data','')::date;
    exception when others then
      v_data := null;
    end;

    -- Sem empresa identificável a linha não serve para nada aqui.
    if v_nome is null and v_cnpj is null then
      v_ignorados := v_ignorados + 1;
      continue;
    end if;

    -- Acha a empresa: por CNPJ quando houver (chave de verdade), senão por nome.
    v_empresa := null;
    if v_cnpj is not null then
      select e.id into v_empresa from public.empresas e
      where e.unidade_id = v_unidade
        and regexp_replace(coalesce(e.cnpj,''),'\D','','g') = v_cnpj
      limit 1;
    end if;
    if v_empresa is null and v_nome is not null then
      select e.id into v_empresa from public.empresas e
      where e.unidade_id = v_unidade and upper(btrim(e.nome)) = upper(v_nome)
      limit 1;
    end if;

    if v_empresa is null then
      insert into public.empresas (unidade_id, cnpj, nome, contato, telefone, observacoes)
      values (v_unidade, v_item->>'cnpj', coalesce(v_nome, v_cnpj), v_contato, v_tel, v_obs)
      returning id into v_empresa;
      v_emp_novas := v_emp_novas + 1;
    else
      -- Só preenche o que estiver vazio: a planilha não apaga o que já foi ajustado na mão.
      update public.empresas
         set contato = coalesce(contato, v_contato),
             telefone = coalesce(telefone, v_tel),
             observacoes = coalesce(observacoes, v_obs),
             cnpj = coalesce(cnpj, v_item->>'cnpj'),
             updated_at = now()
       where id = v_empresa
         and (contato is null or telefone is null or observacoes is null or cnpj is null);
      if found then v_emp_atualizadas := v_emp_atualizadas + 1; end if;
    end if;

    -- Linha só de cabeçalho de empresa (sem placa) é legítima: cadastra e segue.
    if v_placa is null or length(v_placa) < 7 then
      continue;
    end if;

    select c.id, c.empresa_id into v_id, v_dona
    from public.caminhoneiros c
    where c.unidade_id = v_unidade
      and public.normaliza_placa(c.placa_veiculo) = v_placa
    limit 1;

    if v_id is not null then
      update public.caminhoneiros
         set empresa_id = v_empresa,
             data_ultima_afericao = coalesce(v_data, data_ultima_afericao),
             modelo_veiculo = coalesce(modelo_veiculo, v_modelo),
             tem_tacografo = case when coalesce(v_data, data_ultima_afericao) is not null
                                  then true else tem_tacografo end
       where id = v_id;
      if v_dona is not null and v_dona <> v_empresa then
        v_movidos := v_movidos + 1;
      else
        v_vinculados := v_vinculados + 1;
      end if;
    else
      insert into public.caminhoneiros
        (nome, telefone, placa_veiculo, modelo_veiculo, data_ultima_afericao,
         tem_tacografo, unidade_id, empresa_id, origem, status)
      values (coalesce(v_nome, v_cnpj), coalesce(v_tel,'—'), v_placa, v_modelo, v_data,
              v_data is not null, v_unidade, v_empresa, 'outro', 'novo');
      v_criados := v_criados + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'empresas_novas', v_emp_novas, 'empresas_atualizadas', v_emp_atualizadas,
    'vinculados', v_vinculados, 'criados', v_criados,
    'movidos', v_movidos, 'ignorados', v_ignorados);
end $function$;

revoke execute on function public.importar_base_empresas(jsonb,uuid) from public;
grant execute on function public.importar_base_empresas(jsonb,uuid) to authenticated;
