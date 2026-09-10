-- [aplicada no banco em 09/09/2026 19:23 — versão 20260909192325]
-- ── 0061 — a importação passa a entender posto, e-mail e situação ───────────
--
-- Três lacunas que a base do RNTRC expôs:
--
-- 1. SITUAÇÃO. A função nascia sempre com o default 'contrato', que TIRA os
--    caminhões da fila. Importar 6.128 veículos de frotas a prospectar assim
--    os esconderia de quem deve trabalhá-los — o oposto do objetivo.
-- 2. POSTO. É o campo que separa cliente de concorrente e decide o canal
--    (mensagem x ligação). Sem ele, 3.227 caminhões entrariam sem relação.
-- 3. E-MAIL. 567 das 635 empresas têm e-mail na base. E-mail não passa pela
--    Meta, não bloqueia e não exige opt-in de WhatsApp — para relação mensal
--    de frota é canal melhor que o WhatsApp.
--
-- E uma regra que a base obrigou a afinar: "sem data = sem tacógrafo" nasceu
-- para autônomo. Aqui, 47% não têm data — e são dois casos diferentes:
--   'NENHUM RESULTADO' / '-'  → o INMETRO foi consultado e não achou nada
--   posto em branco           → provavelmente nunca foi consultado
-- Os dois ficam escondidos da fila (tem_tacografo = false), mas a observação
-- guarda a diferença: o segundo grupo é estoque a resolver, não descarte.

alter table public.empresas add column if not exists email text;
comment on column public.empresas.email is
  'Canal alternativo para a relação mensal. Não passa pela Meta, não bloqueia.';

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
  v_empresa uuid; v_id uuid; v_dona uuid; v_tem boolean; v_obs_veic text;
  v_emp_novas int := 0; v_emp_atualizadas int := 0;
  v_vinculados int := 0; v_criados int := 0; v_movidos int := 0; v_ignorados int := 0;
  v_sem_data int := 0; v_nunca_consultados int := 0;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_sit := lower(btrim(coalesce(p_situacao,'contrato')));
  if v_sit not in ('contrato','prospecto') then
    raise exception 'situacao invalida: use contrato ou prospecto';
  end if;

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
    v_email  := nullif(btrim(coalesce(v_item->>'email','')),'');
    v_obs    := nullif(btrim(coalesce(v_item->>'observacoes','')),'');
    v_modelo := nullif(btrim(coalesce(v_item->>'modelo','')),'');
    v_num    := nullif(btrim(coalesce(v_item->>'numero','')),'');
    v_posto  := nullif(btrim(coalesce(v_item->>'posto','')),'');
    v_placa  := public.normaliza_placa(v_item->>'placa');
    begin
      v_data := nullif(v_item->>'data','')::date;
    exception when others then
      v_data := null;
    end;

    -- "NENHUM RESULTADO" e "-" NÃO são postos: são o INMETRO dizendo que não
    -- achou certificado. Guardá-los como posto faria o veículo parecer cliente
    -- de um posto chamado "-".
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
    else
      -- Só preenche o que estiver vazio: a planilha não apaga ajuste feito na mão.
      -- A SITUAÇÃO nunca é sobrescrita — quem decidiu que a empresa tem contrato
      -- foi uma pessoa, e uma reimportação não pode desfazer isso em silêncio.
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
      if found then v_emp_atualizadas := v_emp_atualizadas + 1; end if;
    end if;

    if v_placa is null or length(v_placa) < 7 then
      continue;
    end if;

    -- Sem data não entra na fila. Mas a razão fica registrada, porque as duas
    -- razões pedem ações diferentes lá na frente.
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
             -- O posto SÓ é atualizado quando a linha traz um posto de verdade
             -- e uma data mais nova. É essa passagem que o gatilho de fuga lê.
             posto_afericao = case
               when v_posto_ok is not null
                and (data_ultima_afericao is null or v_data > data_ultima_afericao)
               then v_posto_ok else posto_afericao end,
             modelo_veiculo = coalesce(modelo_veiculo, v_modelo),
             numero_empresa = coalesce(numero_empresa, v_num),
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
        (nome, telefone, placa_veiculo, modelo_veiculo, data_ultima_afericao,
         posto_afericao, observacoes, tem_tacografo, unidade_id, empresa_id,
         numero_empresa, origem, status)
      values (coalesce(v_nome, v_cnpj), coalesce(v_tel,''), v_placa, v_modelo, v_data,
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

drop function if exists public.importar_base_empresas(jsonb, uuid);
revoke execute on function public.importar_base_empresas(jsonb, uuid, text) from public, anon;
grant execute on function public.importar_base_empresas(jsonb, uuid, text) to authenticated, service_role;
