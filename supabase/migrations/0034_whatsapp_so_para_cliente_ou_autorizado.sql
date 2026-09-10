-- [aplicada no banco em 28/08/2026 18:31 — versão 20260828183107]
-- Quem pode receber mensagem, depois do bloqueio de 28/08:
--   • cliente do grupo (já aferiu na Tacorrei ou na Lacre) — há relação prévia;
--   • quem AUTORIZOU na ligação — há consentimento explícito.
-- Cliente de concorrente sem autorização não recebe: é abordagem fria, e foi ela
-- que restringiu o número (16 das 20 mensagens daquele dia).
-- Some-se a cadência mínima: 20 envios em 31 minutos é assinatura de robô.
create or replace function public.registrar_envio_whatsapp(
  p_lead uuid, p_mensagem text
) returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_unidade uuid; v_venc date; v_janela integer; v_piso integer;
  v_limite integer; v_intervalo integer; v_usadas integer;
  v_marco timestamptz; v_ja integer; v_ultimo timestamptz;
  v_posto text; v_autorizou boolean; v_falta integer;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id, (c.data_ultima_afericao + interval '2 years')::date,
         c.posto_afericao, c.autorizou_whatsapp
    into v_unidade, v_venc, v_posto, v_autorizou
  from public.caminhoneiros c where c.id = p_lead;

  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  -- 1) RELAÇÃO: cliente do grupo ou autorização colhida na ligação
  if not (public.posto_do_grupo(v_posto) or coalesce(v_autorizou,false)) then
    raise exception 'este lead e cliente de concorrente: ligue primeiro e marque "autorizou receber mensagem"';
  end if;

  select u.janela_dias, u.piso_dias, u.limite_whatsapp_dia, u.intervalo_whatsapp_min
    into v_janela, v_piso, v_limite, v_intervalo
  from public.unidades u where u.id = v_unidade;

  -- 2) FAIXA de vencimento
  if v_venc is null then
    raise exception 'sem data de afericao: este veiculo nao tem tacografo';
  end if;
  if v_janela is not null and v_venc > current_date + v_janela then
    raise exception 'ainda cedo: este certificado so vence em %', to_char(v_venc,'DD/MM/YYYY');
  end if;
  if v_venc < current_date - coalesce(v_piso,365) then
    raise exception 'vencido ha mais de % meses (em %): fora da faixa de contato',
      round(coalesce(v_piso,365)/30.0), to_char(v_venc,'DD/MM/YYYY');
  end if;

  -- 3) UMA por lead por ciclo (zera quando afere)
  select max(l.created_at) into v_marco
  from public.ligacoes l where l.caminhoneiro_id = p_lead and l.resultado = 'aferido';
  select count(*) into v_ja
  from public.ligacoes l
  where l.caminhoneiro_id = p_lead and l.canal = 'whatsapp'
    and (v_marco is null or l.created_at > v_marco);
  if v_ja > 0 then raise exception 'este lead ja recebeu mensagem neste ciclo'; end if;

  -- 4) COTA do dia, por unidade
  select count(*), max(l.created_at) into v_usadas, v_ultimo
  from public.ligacoes l
  where l.unidade_id = v_unidade and l.canal = 'whatsapp'
    and (l.created_at at time zone 'America/Sao_Paulo')::date
        = (now() at time zone 'America/Sao_Paulo')::date;
  if v_usadas >= v_limite then
    raise exception 'cota diaria de % mensagens ja foi usada nesta unidade', v_limite;
  end if;

  -- 5) RITMO: intervalo mínimo desde o último envio DA UNIDADE
  if v_intervalo > 0 and v_ultimo is not null then
    v_falta := ceil(extract(epoch from (v_ultimo + make_interval(mins => v_intervalo) - now()))/60.0);
    if v_falta > 0 then
      raise exception 'aguarde % min para o proximo envio (ritmo de % em % min protege o numero)',
        v_falta, 1, v_intervalo;
    end if;
  end if;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'whatsapp', 'whatsapp_enviado', p_mensagem);

  update public.caminhoneiros
     set data_ultimo_whatsapp = now(),
         status = case when status in ('novo','sem_resposta') then 'mensagem_enviada' else status end
   where id = p_lead;

  return jsonb_build_object('limite', v_limite, 'usadas', v_usadas + 1,
                            'restantes', greatest(v_limite - v_usadas - 1, 0),
                            'intervalo', v_intervalo);
end $function$;
