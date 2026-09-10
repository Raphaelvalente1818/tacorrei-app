-- [aplicada no banco em 08/09/2026 16:13 — versão 20260908161323]
-- ── 0040 — uma mensagem por TELEFONE, não por placa ─────────────────────────
--
-- Motivo, medido na base em 08/09/2026: São Bernardo tem 41 telefones que
-- aparecem em 3 ou mais leads de donos DIFERENTES, segurando 232 leads. O
-- maior tem 16 nomes distintos; um deles é o placeholder (11) 99000-0000.
-- Como a fila lista uma linha por placa, nada impedia a operadora de mandar
-- 16 mensagens para o mesmo WhatsApp, cada uma falando do caminhão de outra
-- pessoa. É o padrão que faz o destinatário denunciar o número.
--
-- A trava é por unidade, como as demais: cada unidade manda do seu próprio
-- número, e é o número que se quer proteger.

-- 1) Forma canônica do telefone --------------------------------------------
-- DDD + os 8 últimos dígitos. Ignorar o 9 é de propósito: o mesmo assinante
-- aparece na base ora como (11) 9999-9999, ora como (11) 99999-9999, e os
-- dois têm de colidir. Sem DDD suficiente, devolve null e a trava não se
-- aplica — não dá para proteger o que não dá para identificar.
create or replace function public.normaliza_fone(p text)
returns text
language sql
immutable
as $$
  with d as (
    select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as n
  ),
  s as (
    select case when length(n) >= 12 and left(n, 2) = '55' then substr(n, 3) else n end as n
    from d
  )
  select case when length(n) between 10 and 11 then left(n, 2) || right(n, 8) end
  from s;
$$;

comment on function public.normaliza_fone(text) is
  'DDD + 8 últimos dígitos. Faz (11) 9999-9999 e (11) 99999-9999 colidirem.';

create index if not exists idx_caminhoneiros_fone
  on public.caminhoneiros (unidade_id, public.normaliza_fone(telefone));

-- 2) O prazo, regulável por unidade ----------------------------------------
alter table public.unidades
  add column if not exists cooldown_telefone_dias integer not null default 30;

comment on column public.unidades.cooldown_telefone_dias is
  'Dias mínimos entre duas mensagens para o MESMO telefone, ainda que sejam placas diferentes.';

-- 3) A trava, dentro da função que já existe -------------------------------
create or replace function public.registrar_envio_whatsapp(p_lead uuid, p_mensagem text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_unidade uuid; v_venc date; v_janela integer; v_piso integer;
  v_limite integer; v_intervalo integer; v_usadas integer;
  v_marco timestamptz; v_ja integer; v_ultimo timestamptz;
  v_posto text; v_autorizou boolean; v_falta integer;
  v_fone text; v_cooldown integer;
  v_irmao record; v_placas text; v_quantos integer;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id, (c.data_ultima_afericao + interval '2 years')::date,
         c.posto_afericao, c.autorizou_whatsapp, public.normaliza_fone(c.telefone)
    into v_unidade, v_venc, v_posto, v_autorizou, v_fone
  from public.caminhoneiros c where c.id = p_lead;

  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  -- 1) RELAÇÃO: cliente do grupo ou autorização colhida na ligação
  if not (public.posto_do_grupo(v_posto) or coalesce(v_autorizou,false)) then
    raise exception 'este lead e cliente de concorrente: ligue primeiro e marque "autorizou receber mensagem"';
  end if;

  select u.janela_dias, u.piso_dias, u.limite_whatsapp_dia, u.intervalo_whatsapp_min,
         u.cooldown_telefone_dias
    into v_janela, v_piso, v_limite, v_intervalo, v_cooldown
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

  -- 3b) UMA por TELEFONE — a trava nova.
  -- Não basta barrar: o erro devolve quem já recebeu e as outras placas do
  -- mesmo número, para a operadora falar de todas numa conversa só. É assim
  -- que ela descobre a frota — no instante em que ia duplicar a mensagem.
  if v_fone is not null and coalesce(v_cooldown,0) > 0 then
    select c.placa_veiculo, c.nome, c.data_ultimo_whatsapp
      into v_irmao
    from public.caminhoneiros c
    where c.id <> p_lead
      and c.unidade_id = v_unidade
      and public.normaliza_fone(c.telefone) = v_fone
      and c.data_ultimo_whatsapp is not null
      and c.data_ultimo_whatsapp > now() - make_interval(days => v_cooldown)
    order by c.data_ultimo_whatsapp desc
    limit 1;

    if found then
      select count(*), string_agg(x.placa_veiculo, ', ' order by x.placa_veiculo)
        into v_quantos, v_placas
      from (
        select c.placa_veiculo
        from public.caminhoneiros c
        where c.id <> p_lead
          and c.unidade_id = v_unidade
          and public.normaliza_fone(c.telefone) = v_fone
          and c.placa_veiculo is not null
        order by c.placa_veiculo
        limit 6
      ) x;

      raise exception
        'este telefone ja recebeu mensagem em % , sobre a placa % (%). Mesmo numero em mais % lead(s): %. Fale de todas na mesma conversa em vez de mandar outra mensagem.',
        to_char(v_irmao.data_ultimo_whatsapp at time zone 'America/Sao_Paulo', 'DD/MM'),
        coalesce(v_irmao.placa_veiculo, '(sem placa)'),
        coalesce(v_irmao.nome, 'sem nome'),
        coalesce(v_quantos, 0),
        coalesce(v_placas, '—');
    end if;
  end if;

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
