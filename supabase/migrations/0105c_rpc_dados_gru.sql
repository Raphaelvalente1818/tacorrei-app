-- 0105c — Funções da GRU: dados_gru (o que falta + campos do formulário do Inmetro)
-- e salvar_dados_gru (completa CPF/CNPJ, chassi, ano). Aplicada em 23/09/2026
-- (migration rpc_dados_gru); reconciliada como arquivo (regra 13).
create or replace function public.salvar_dados_gru(p_lead uuid, p_documento text default null, p_chassi text default null, p_ano_fabricacao integer default null)
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare v_unidade uuid; v_doc text; v_chassi text; v_mud text := '';
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then raise exception 'acesso negado'; end if;

  v_doc := nullif(regexp_replace(coalesce(p_documento,''), '\D', '', 'g'), '');
  if v_doc is not null and v_doc !~ '^([0-9]{11}|[0-9]{14})$' then raise exception 'CPF deve ter 11 digitos e CNPJ 14'; end if;
  v_chassi := nullif(upper(regexp_replace(coalesce(p_chassi,''), '\s', '', 'g')), '');
  if v_chassi is not null and length(v_chassi) > 23 then raise exception 'chassi com mais de 23 caracteres'; end if;
  if p_ano_fabricacao is not null and p_ano_fabricacao not between 1950 and 2100 then raise exception 'ano de fabricacao invalido'; end if;

  update public.caminhoneiros
     set documento = coalesce(v_doc, documento),
         chassi = coalesce(v_chassi, chassi),
         ano_fabricacao = coalesce(p_ano_fabricacao::smallint, ano_fabricacao),
         updated_at = now()
   where id = p_lead;

  if v_doc is not null then v_mud := v_mud || 'CPF/CNPJ '; end if;
  if v_chassi is not null then v_mud := v_mud || 'chassi '; end if;
  if p_ano_fabricacao is not null then v_mud := v_mud || 'ano '; end if;
  if v_mud <> '' then
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
    values (p_lead, v_unidade, auth.uid(), 'sistema', 'atualizacao', 'Dados para a GRU atualizados: ' || btrim(v_mud));
  end if;
  return public.dados_gru(p_lead, false);
end $function$;

create or replace function public.dados_gru(p_lead uuid, p_registrar boolean default false)
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare c record; v_falta text[] := '{}'; v_tp int;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select * into c from public.caminhoneiros where id = p_lead;
  if c.id is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or c.unidade_id = public.unidade_do_usuario()) then raise exception 'acesso negado'; end if;

  v_tp := case when c.documento ~ '^[0-9]{11}$' then 1 when c.documento ~ '^[0-9]{14}$' then 2 end;
  if v_tp is null then v_falta := v_falta || 'CPF/CNPJ'; end if;
  if coalesce(c.chassi,'') = '' then v_falta := v_falta || 'Chassi'; end if;
  if coalesce(c.placa_veiculo,'') = '' then v_falta := v_falta || 'Placa'; end if;
  if coalesce(c.renavam,'') !~ '^[0-9]{11}$' then v_falta := v_falta || 'RENAVAM (11 dígitos)'; end if;

  if p_registrar and cardinality(v_falta) = 0 then
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
    values (p_lead, c.unidade_id, auth.uid(), 'sistema', 'atualizacao', 'GRU de verificação solicitada no site do Inmetro');
  end if;

  return jsonb_build_object(
    'pronto', cardinality(v_falta) = 0,
    'faltando', to_jsonb(v_falta),
    'url', 'https://cronotacografo.rbmlq.gov.br/grus/emitir_verificacao',
    'resumo', jsonb_build_object('documento', c.documento, 'placa', c.placa_veiculo, 'renavam', c.renavam, 'chassi', c.chassi, 'ano_fabricacao', c.ano_fabricacao),
    'campos', jsonb_build_object(
      'data[CrVeiculoProprietario][pai_id]', '2',
      'data[CrVeiculoProprietario][tp_pessoa]', coalesce(v_tp::text, ''),
      'data[CrVeiculoProprietario][nr_identificacao]', coalesce(c.documento, ''),
      'data[CrVeiculo][vet_id]', '1',
      'data[CrVeiculo][pai_id]', '2',
      'data[CrVeiculo][ds_chassi]', coalesce(c.chassi, ''),
      'data[CrVeiculo][ds_placa]', coalesce(public.normaliza_placa(c.placa_veiculo), ''),
      'data[CrVeiculo][ds_renavam]', coalesce(c.renavam, ''),
      'data[CrVeiculo][dt_ano]', coalesce(c.ano_fabricacao::text, '')));
end $function$;

revoke all on function public.dados_gru(uuid, boolean) from public, anon;
revoke all on function public.salvar_dados_gru(uuid, text, text, integer) from public, anon;
grant execute on function public.dados_gru(uuid, boolean) to authenticated, service_role;
grant execute on function public.salvar_dados_gru(uuid, text, text, integer) to authenticated, service_role;
