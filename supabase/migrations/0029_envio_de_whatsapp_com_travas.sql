-- [aplicada no banco em 24/08/2026 19:55 — versão 20260824195538]
-- O envio deixa de ser um INSERT solto do navegador e passa a ter porteiro.
-- As três travas ficam AQUI, não na tela: o botão pode falhar, a regra não.
create or replace function public.registrar_envio_whatsapp(
  p_lead uuid, p_mensagem text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $function$
declare
  v_unidade  uuid;
  v_venc     date;
  v_janela   integer;
  v_piso     integer;
  v_limite   integer;
  v_usadas   integer;
  v_marco    timestamptz;
  v_ja       integer;
  v_status   text;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  select c.unidade_id, (c.data_ultima_afericao + interval '2 years')::date, c.status
    into v_unidade, v_venc, v_status
  from public.caminhoneiros c where c.id = p_lead;

  if v_unidade is null then
    raise exception 'lead nao encontrado';
  end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  -- A cota e a faixa são SEMPRE da unidade do lead: é o número dela que envia,
  -- e é ele que corre risco de bloqueio. Vale igual para o admin.
  select u.janela_dias, u.piso_dias, u.limite_whatsapp_dia
    into v_janela, v_piso, v_limite
  from public.unidades u where u.id = v_unidade;

  -- 1) FAIXA: nem vencido demais, nem longe demais de vencer.
  if v_venc is null then
    raise exception 'sem data de afericao: este veiculo nao tem tacografo';
  end if;
  if v_janela is not null and v_venc > current_date + v_janela then
    raise exception 'ainda cedo: este certificado so vence em %', to_char(v_venc,'DD/MM/YYYY');
  end if;
  if v_venc < current_date - coalesce(v_piso, 365) then
    raise exception 'vencido ha mais de % meses (em %): fora da faixa de contato',
      round(coalesce(v_piso,365)/30.0), to_char(v_venc,'DD/MM/YYYY');
  end if;

  -- 2) UMA MENSAGEM POR LEAD, por ciclo. O marco é a última aferição registrada:
  -- depois que o cliente afere, o ciclo recomeça e ele pode ser abordado de novo
  -- daqui a 2 anos. Sem isso, a trava mataria a recompra.
  select max(l.created_at) into v_marco
  from public.ligacoes l where l.caminhoneiro_id = p_lead and l.resultado = 'aferido';

  select count(*) into v_ja
  from public.ligacoes l
  where l.caminhoneiro_id = p_lead and l.canal = 'whatsapp'
    and (v_marco is null or l.created_at > v_marco);

  if v_ja > 0 then
    raise exception 'este lead ja recebeu mensagem neste ciclo';
  end if;

  -- 3) COTA DIÁRIA DA UNIDADE (fuso de São Paulo).
  select count(*) into v_usadas
  from public.ligacoes l
  where l.unidade_id = v_unidade and l.canal = 'whatsapp'
    and (l.created_at at time zone 'America/Sao_Paulo')::date
        = (now() at time zone 'America/Sao_Paulo')::date;

  if v_usadas >= v_limite then
    raise exception 'cota diaria de % mensagens ja foi usada nesta unidade', v_limite;
  end if;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'whatsapp', 'whatsapp_enviado', p_mensagem);

  update public.caminhoneiros
     set data_ultimo_whatsapp = now(),
         status = case when status in ('novo','sem_resposta') then 'mensagem_enviada' else status end
   where id = p_lead;

  return jsonb_build_object(
    'limite', v_limite, 'usadas', v_usadas + 1,
    'restantes', greatest(v_limite - v_usadas - 1, 0));
end $function$;

-- versão com unidade explícita, para o admin que está olhando outra unidade
create or replace function public.cota_whatsapp_hoje(p_unidade uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $function$
declare v_unidade uuid; v_limite integer; v_usadas integer;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  v_unidade := coalesce(p_unidade, public.unidade_do_usuario());
  if v_unidade is null then
    return jsonb_build_object('limite', null, 'usadas', 0, 'restantes', null);
  end if;

  select limite_whatsapp_dia into v_limite from public.unidades where id = v_unidade;

  select count(*) into v_usadas
  from public.ligacoes l
  where l.unidade_id = v_unidade and l.canal = 'whatsapp'
    and (l.created_at at time zone 'America/Sao_Paulo')::date
        = (now() at time zone 'America/Sao_Paulo')::date;

  return jsonb_build_object(
    'limite', v_limite, 'usadas', v_usadas,
    'restantes', greatest(v_limite - v_usadas, 0));
end $function$;

drop function if exists public.cota_whatsapp_hoje();

revoke execute on function public.registrar_envio_whatsapp(uuid, text) from public;
grant execute on function public.registrar_envio_whatsapp(uuid, text) to authenticated;
revoke execute on function public.cota_whatsapp_hoje(uuid) from public;
grant execute on function public.cota_whatsapp_hoje(uuid) to authenticated;
