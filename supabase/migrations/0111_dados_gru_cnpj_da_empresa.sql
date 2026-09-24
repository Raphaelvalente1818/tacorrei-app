-- 0111: dados_gru usa o CNPJ da empresa quando a placa não tem documento (24/09/2026)
--
-- Contexto: as cargas feitas por importar_base_empresas antes da 0105 não gravavam
-- documento na placa — só na empresa. Em São Bernardo isso deixou 7.083 placas ETC
-- "faltando CPF/CNPJ" no modal Emitir GRU, embora o CNPJ estivesse em empresas.cnpj.
-- Nesta data as 7.083 foram preenchidas por update (só onde vazio; linha em importacoes
-- "Documento (CNPJ da empresa) nas placas ETC de SBC sem documento (24/09)").
-- Esta migration fecha a brecha para o futuro: dados_gru cai no CNPJ da empresa
-- (só dígitos) quando caminhoneiros.documento está vazio.

create or replace function public.dados_gru(p_lead uuid, p_registrar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare c record; v_falta text[] := '{}'; v_tp int; v_doc text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select * into c from public.caminhoneiros where id = p_lead;
  if c.id is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or c.unidade_id = public.unidade_do_usuario()) then raise exception 'acesso negado'; end if;

  -- documento da placa; se vazio, CNPJ da empresa dona (só dígitos)
  v_doc := nullif(regexp_replace(coalesce(c.documento,''), '\D', '', 'g'), '');
  if v_doc is null and c.empresa_id is not null then
    select nullif(regexp_replace(coalesce(e.cnpj,''), '\D', '', 'g'), '') into v_doc
    from public.empresas e where e.id = c.empresa_id;
  end if;

  v_tp := case when v_doc ~ '^[0-9]{11}$' then 1 when v_doc ~ '^[0-9]{14}$' then 2 end;
  if v_tp is null then v_falta := array_append(v_falta, 'CPF/CNPJ'); end if;
  if coalesce(c.chassi,'') = '' then v_falta := array_append(v_falta, 'Chassi'); end if;
  if coalesce(c.placa_veiculo,'') = '' then v_falta := array_append(v_falta, 'Placa'); end if;
  if coalesce(c.renavam,'') !~ '^[0-9]{11}$' then v_falta := array_append(v_falta, 'RENAVAM (11 dígitos)'); end if;

  if p_registrar and cardinality(v_falta) = 0 then
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
    values (p_lead, c.unidade_id, auth.uid(), 'sistema', 'atualizacao', 'GRU de verificação solicitada no site do Inmetro');
  end if;

  return jsonb_build_object(
    'pronto', cardinality(v_falta) = 0,
    'faltando', to_jsonb(v_falta),
    'url', 'https://cronotacografo.rbmlq.gov.br/grus/emitir_verificacao',
    'resumo', jsonb_build_object('documento', v_doc, 'placa', c.placa_veiculo, 'renavam', c.renavam, 'chassi', c.chassi, 'ano_fabricacao', c.ano_fabricacao),
    'campos', jsonb_build_object(
      'data[CrVeiculoProprietario][pai_id]', '2',
      'data[CrVeiculoProprietario][tp_pessoa]', coalesce(v_tp::text, ''),
      'data[CrVeiculoProprietario][nr_identificacao]', coalesce(v_doc, ''),
      'data[CrVeiculo][vet_id]', '1',
      'data[CrVeiculo][pai_id]', '2',
      'data[CrVeiculo][ds_chassi]', coalesce(c.chassi, ''),
      'data[CrVeiculo][ds_placa]', coalesce(public.normaliza_placa(c.placa_veiculo), ''),
      'data[CrVeiculo][ds_renavam]', coalesce(c.renavam, ''),
      'data[CrVeiculo][dt_ano]', coalesce(c.ano_fabricacao::text, '')));
end $function$;
