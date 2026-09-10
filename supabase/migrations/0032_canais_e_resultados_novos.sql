-- [aplicada no banco em 28/08/2026 18:30 — versão 20260828183019]
-- 'sistema' registra o que o app anotou sozinho (troca de proprietário), separado
-- do que a operadora fez. 'autorizou_whatsapp' é o consentimento colhido na ligação.
alter table public.ligacoes drop constraint if exists ligacoes_canal_check;
alter table public.ligacoes add constraint ligacoes_canal_check
  check (canal = any (array['ligacao_ativa','ligacao_passiva','whatsapp','presencial','sistema']));

alter table public.ligacoes drop constraint if exists ligacoes_resultado_check;
alter table public.ligacoes add constraint ligacoes_resultado_check
  check (resultado = any (array['atendeu','nao_atendeu','numero_invalido','recusou',
                               'agendou','reagendar','whatsapp_enviado','aferido',
                               'autorizou_whatsapp','atualizacao']));

create or replace function public.atualizar_proprietario(
  p_lead uuid, p_nome text, p_telefone text default null
) returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_unidade uuid; v_antigo text; v_novo text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_novo := nullif(btrim(coalesce(p_nome,'')),'');
  if v_novo is null then raise exception 'informe o nome do proprietario'; end if;

  select c.unidade_id, c.nome into v_unidade, v_antigo
  from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  update public.caminhoneiros
     set nome = v_novo,
         telefone = coalesce(nullif(btrim(coalesce(p_telefone,'')),''), telefone),
         autorizou_whatsapp = false, autorizado_em = null, autorizado_por = null
   where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'sistema', 'atualizacao',
          'Proprietário alterado de "' || coalesce(v_antigo,'—') || '" para "' || v_novo || '"');

  return (select to_jsonb(c) from public.caminhoneiros c where c.id = p_lead);
end $function$;

create or replace function public.registrar_autorizacao(
  p_lead uuid, p_autorizou boolean, p_notas text default null
) returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  update public.caminhoneiros
     set autorizou_whatsapp = coalesce(p_autorizou,false),
         autorizado_em  = case when p_autorizou then now() else null end,
         autorizado_por = case when p_autorizou then auth.uid() else null end,
         status = case when status = 'novo' then 'contatado' else status end
   where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'ligacao_ativa',
          case when p_autorizou then 'autorizou_whatsapp' else 'atendeu' end,
          nullif(btrim(coalesce(p_notas,'')),''));

  return (select to_jsonb(c) from public.caminhoneiros c where c.id = p_lead);
end $function$;
