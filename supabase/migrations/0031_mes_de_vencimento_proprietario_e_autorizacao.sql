-- [aplicada no banco em 28/08/2026 18:29 — versão 20260828182951]
-- ── 1. Autorização de contato ────────────────────────────────────────────────
-- Cliente do grupo já tem relação: mensagem é lembrete de fornecedor.
-- Cliente de concorrente não tem relação nenhuma — para esse, o caminho é LIGAR,
-- e só depois de ele dizer "pode mandar" o WhatsApp abre. Ligação atendida não é
-- permissão; a autorização explícita é. É isso que esta coluna guarda.
alter table public.caminhoneiros
  add column if not exists autorizou_whatsapp boolean not null default false,
  add column if not exists autorizado_em timestamptz,
  add column if not exists autorizado_por uuid;

-- ── 2. Ritmo de envio ────────────────────────────────────────────────────────
-- 20 mensagens em 31 minutos, uma a cada 90 segundos, derrubaram o número da
-- Tacorrei em 28/08. Não foi o volume — foi a cadência de metrônomo. O intervalo
-- mínimo é a trava que faltava.
alter table public.unidades
  add column if not exists intervalo_whatsapp_min integer not null default 3;

alter table public.unidades drop constraint if exists unidades_intervalo_check;
alter table public.unidades add constraint unidades_intervalo_check
  check (intervalo_whatsapp_min between 0 and 120);

update public.unidades set limite_whatsapp_dia = 30, intervalo_whatsapp_min = 3;

-- ── 3. Troca de proprietário ─────────────────────────────────────────────────
-- O veículo é o que persiste; o dono muda. Quando alguém responde "não é mais
-- meu", a operadora corrige na hora — e a troca fica no histórico, porque saber
-- que o dono mudou explica um telefone que parou de atender.
-- (As duas funções abaixo foram reescritas na 0032 com os canais definitivos.)
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
         -- dono novo é relação nova: a autorização do dono anterior não vale,
         -- e o veículo volta a poder ser abordado uma vez.
         autorizou_whatsapp = false,
         autorizado_em = null,
         autorizado_por = null
   where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'outro', 'atualizacao',
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
  values (p_lead, v_unidade, auth.uid(), 'ligacao',
          case when p_autorizou then 'autorizou_whatsapp' else 'contatado' end,
          nullif(btrim(coalesce(p_notas,'')),''));

  return (select to_jsonb(c) from public.caminhoneiros c where c.id = p_lead);
end $function$;

revoke execute on function public.atualizar_proprietario(uuid,text,text) from public;
grant execute on function public.atualizar_proprietario(uuid,text,text) to authenticated;
revoke execute on function public.registrar_autorizacao(uuid,boolean,text) from public;
grant execute on function public.registrar_autorizacao(uuid,boolean,text) to authenticated;
