-- [aplicada no banco em 09/09/2026 21:05 — versão 20260909210541]
-- ── 0064 — a importação passa a EXIGIR a unidade do admin ───────────────────
--
-- Causa raiz do erro de hoje: para um admin com p_unidade nulo, a função caía
-- em `unidade_do_usuario()`. Adivinhar por quem enxerga todas as unidades é o
-- que faz 6.128 veículos entrarem no lugar errado sem ninguém perceber.
--
-- Agora recusa e diz o que fazer. Operador comum segue igual: ele só tem uma
-- unidade, não há o que adivinhar.
--
-- De quebra: `empresas_atualizadas` contava LINHA, não EMPRESA — uma frota de
-- 400 veículos aparecia como "400 atualizadas". E a importação passa a gravar
-- CIDADE e UF quando a planilha trouxer, o que dá ao gatilho de unidade uma
-- segunda chance de acertar sozinho.
create or replace function public.importar_base_empresas(
  p_linhas jsonb,
  p_unidade uuid default null,
  p_situacao text default 'contrato')
returns jsonb language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare
  v_unidade uuid; v_item jsonb; v_sit text;
  v_cnpj text; v_nome text; v_contato text; v_tel text; v_obs text; v_email text;
  v_placa text; v_data date; v_modelo text; v_posto text; v_posto_ok text; v_num text;
  v_cidade text; v_uf text;
  v_empresa uuid; v_id uuid; v_dona uuid; v_tem boolean; v_obs_veic text;
  v_emp_novas int := 0; v_emp_atualizadas int := 0;
  v_vinculados int := 0; v_criados int := 0; v_movidos int := 0; v_ignorados int := 0;
  v_sem_data int := 0; v_nunca_consultados int := 0;
  v_vistas uuid[] := '{}';
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_sit := lower(btrim(coalesce(p_situacao,'contrato')));
  if v_sit not in ('contrato','prospecto') then
    raise exception 'situacao invalida: use contrato ou prospecto';
  end if;

  if public.is_admin() then
    if p_unidade is null then
      raise exception 'escolha a unidade antes de importar: no topo da tela, troque "Todas as unidades" pela unidade dona desta base';
    end if;
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
    v_email  := nullif(btrim(coalesce(v_item->>'email','')),'');
    v_obs    := nullif(btrim(coalesce(v_item->>'observacoes','')),'');
    v_modelo := nullif(btrim(coalesce(v_item->>'modelo','')),'');
    v_num    := nullif(btrim(coalesce(v_item->>'numero','')),'');
    v_posto  := nullif(btrim(coalesce(v_item->>'posto','')),'');
    v_cidade := nullif(btrim(coalesce(v_item->>'cidade','')),'');
    v_uf     := nullif(btrim(coalesce(v_item->>'uf','')),'');
    v_placa  := public.normaliza_placa(v_item->>'placa');
    begin
      v_data := nullif(v_item->>'data','')::date;
    exception when others then
      v_data := null;
    end;

    v_posto_ok := case
      when v_posto is null then null
      when upper(v_posto) in ('NENHUM RESULTADO','NENHUM RESULTADO.','-','--','N/A') then null
      else v_posto
    end;

    if v_nome is null and v_cnpj is null then
      v_ignorados := v_ignorados + 1;
      continue;
    end if;

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
      insert into public.empresas (unidade_id, cnpj, nome, contato, telefone, email, situacao, observacoes)
      values (v_unidade, v_item->>'cnpj', coalesce(v_nome, v_cnpj), v_contato, v_tel, v_email, v_sit, v_obs)
      returning id into v_empresa;
      v_emp_novas := v_emp_novas + 1;
      v_vistas := v_vistas || v_empresa;
    else
      update public.empresas
         set contato = coalesce(contato, v_contato),
             telefone = coalesce(telefone, v_tel),
             email = coalesce(email, v_email),
             observacoes = coalesce(observacoes, v_obs),
             cnpj = coalesce(cnpj, v_item->>'cnpj'),
             updated_at = now()
       where id = v_empresa
         and (contato is null or telefone is null or email is null
              or observacoes is null or cnpj is null);
      if not (v_empresa = any(v_vistas)) then
        v_emp_atualizadas := v_emp_atualizadas + 1;
        v_vistas := v_vistas || v_empresa;
      end if;
    end if;

    if v_placa is null or length(v_placa) < 7 then
      continue;
    end if;

    v_tem := v_data is not null;
    v_obs_veic := case
      when v_data is not null then null
      when v_posto is not null then 'INMETRO consultado e sem certificado ('||v_posto||'). Fora da fila até haver aferição.'
      else 'Sem consulta ao INMETRO: pode ter tacógrafo. Fora da fila até ser verificado.'
    end;
    if v_data is null then
      v_sem_data := v_sem_data + 1;
      if v_posto is null then v_nunca_consultados := v_nunca_consultados + 1; end if;
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
             posto_afericao = case
               when v_posto_ok is not null
                and (data_ultima_afericao is null or v_data > data_ultima_afericao)
               then v_posto_ok else posto_afericao end,
             modelo_veiculo = coalesce(modelo_veiculo, v_modelo),
             numero_empresa = coalesce(numero_empresa, v_num),
             cidade = coalesce(cidade, v_cidade),
             uf = coalesce(uf, v_uf),
             observacoes = coalesce(observacoes, v_obs_veic),
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
        (nome, telefone, cidade, uf, placa_veiculo, modelo_veiculo, data_ultima_afericao,
         posto_afericao, observacoes, tem_tacografo, unidade_id, empresa_id,
         numero_empresa, origem, status)
      values (coalesce(v_nome, v_cnpj), coalesce(v_tel,''), v_cidade, v_uf, v_placa, v_modelo, v_data,
              v_posto_ok, v_obs_veic, v_tem, v_unidade, v_empresa, v_num, 'outro', 'novo');
      v_criados := v_criados + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'empresas_novas', v_emp_novas, 'empresas_atualizadas', v_emp_atualizadas,
    'vinculados', v_vinculados, 'criados', v_criados,
    'movidos', v_movidos, 'ignorados', v_ignorados,
    'sem_data', v_sem_data, 'nunca_consultados', v_nunca_consultados);
end $function$;

revoke execute on function public.importar_base_empresas(jsonb, uuid, text) from public, anon;
grant execute on function public.importar_base_empresas(jsonb, uuid, text) to authenticated, service_role;
