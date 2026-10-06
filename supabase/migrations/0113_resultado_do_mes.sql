-- 0113 — RESULTADO DO MÊS: O RESUMO EXECUTIVO DENTRO DO APP (06/10)
--
-- O Emerson montou à mão, para os sócios, um quadro de setembro: por unidade e
-- operadora, aferições, pontos brutos, pontos finais (fator da carteira), a
-- parte individual (70%), o bolo (30%, liberado ou não), o total; embaixo, a
-- carteira defendida com o piso, o total da unidade, o que é pago e o que fica
-- com a casa; e a observação crítica — quantos clientes nossos venceram e não
-- renovaram. Pediu para isso existir no app, todo mês, e para a aba "Prêmio"
-- se chamar "Resultado".
--
-- UMA CONTA SÓ. A fórmula é a de `fechar_mes` (0083), copiada aqui como função
-- de LEITURA: nada é gravado. Mês já fechado devolve os números do fechamento
-- (eles têm anulações da auditoria; o cálculo ao vivo não tem). Mês em
-- observação (valor_ponto nulo) é SIMULADO com a próxima regra que paga — é o
-- que o Emerson fez para setembro com a regra de outubro — e a resposta diz
-- que é simulação, com qual vigência. Sem regra nenhuma à frente, devolve os
-- pontos e deixa o dinheiro nulo.
--
-- Quem vê: admin geral (qualquer unidade) e gestor (a dele). A operadora não
-- chama esta função — o placar dela continua em `placar_operadora`.

create or replace function public.resultado_do_mes(p_unidade uuid, p_competencia date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_comp date; v_fim date; prm record; par record; v_sim boolean := false; v_sim_vig date;
  v_pend integer; v_renov integer; v_carteira_pct integer; v_carteira_ok boolean;
  v_finais integer; v_brutos integer;
  v_total numeric(10,2); v_individual numeric(10,2); v_bolo numeric(10,2); v_pago numeric(10,2);
  v_n_bolo integer; v_ops jsonb; v_sozinho jsonb; v_fech jsonb; v_nome text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then
    raise exception 'acesso negado';
  end if;
  v_comp := date_trunc('month', p_competencia)::date;
  v_fim  := (v_comp + interval '1 month')::date;
  select nome into v_nome from public.unidades where id = p_unidade;

  -- Mês fechado: a foto oficial, com as anulações da auditoria.
  v_fech := public.resumo_fechamento(p_unidade, v_comp);
  if v_fech is not null then
    return jsonb_build_object(
      'unidade', v_nome, 'competencia', v_comp, 'fechado', true, 'simulado', false,
      'regra', jsonb_build_object('valor_ponto', v_fech->'valor_ponto', 'teto_mes', v_fech->'teto_mes',
                                  'pct_bolo', v_fech->'pct_bolo', 'vigencia', null),
      'carteira', jsonb_build_object('pct', v_fech->'carteira_pct', 'ok', v_fech->'carteira_ok',
                                     'renovaram', null, 'venciam', null, 'nao_renovaram', null,
                                     'piso', (select piso_carteira_pct from public.parametros_pontos where id = 1)),
      'pontos_brutos', v_fech->'pontos_brutos', 'pontos_finais', v_fech->'pontos_finais',
      'total_unidade', v_fech->'total_pago', 'individual', v_fech->'individual_pago',
      'bolo', v_fech->'bolo_pago', 'bolo_liberado', v_fech->'carteira_ok',
      'pago', v_fech->'total_pago', 'fica_com_a_casa', 0,
      'operadoras', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'nome', o->>'nome', 'afericoes', o->'afericoes', 'brutos', o->'pontos_brutos',
                 'finais', o->'pontos_finais', 'individual', o->'individual', 'bolo', o->'bolo',
                 'total', o->'total', 'anulada', o->'anulada'))
          from jsonb_array_elements(v_fech->'operadoras') o), '[]'::jsonb),
      'veio_sozinho', (
        select jsonb_build_object('afericoes', count(*), 'pontos', coalesce(sum(p.pontos + p.bonus), 0))
          from public.pontos p where p.unidade_id = p_unidade and p.competencia = v_comp and p.operadora_id is null),
      'observacao', v_fech->'observacoes');
  end if;

  select * into prm from public.parametros_pontos where id = 1;
  select * into par from public.parametros_premio(p_unidade, v_comp);

  -- Observação (ou sem regra): simula com a próxima regra que paga.
  if par.valor_ponto is null then
    select p.valor_ponto, p.teto_mes, p.pct_bolo, p.vigencia, p.observacao
      into par
      from public.parametros_unidade p
     where p.unidade_id = p_unidade and p.valor_ponto is not null and p.vigencia > v_comp
     order by p.vigencia asc limit 1;
    if par.valor_ponto is not null then v_sim := true; v_sim_vig := par.vigencia; end if;
  end if;

  -- Carteira: mesma conta do fechamento. `b.nosso and venc no mês` só sobra para
  -- quem NÃO renovou (quem renovou tem o vencimento jogado dois anos à frente).
  select count(*) into v_pend from public.base_trabalhavel(p_unidade) b
   where b.nosso and b.venc >= v_comp and b.venc < v_fim;
  select count(*) into v_renov from public.pontos p
   where p.unidade_id = p_unidade and p.competencia = v_comp and p.classe in ('renovacao', 'contrato');
  v_carteira_pct := case when v_renov + v_pend = 0 then null else round(100.0 * v_renov / (v_renov + v_pend)) end;
  v_carteira_ok  := v_carteira_pct is null or v_carteira_pct >= prm.piso_carteira_pct;

  -- Por operadora: brutos, finais (fator da carteira só nas conquistas).
  with q as (
    select p.operadora_id, coalesce(e.nome, 'Usuário removido') as nome,
           count(*)::int as afericoes,
           sum(p.pontos + p.bonus)::int as brutos,
           sum(case when p.classe like 'conquista_%' and not v_carteira_ok
                    then floor((p.pontos + p.bonus) * prm.fator_carteira)
                    else p.pontos + p.bonus end)::int as finais
      from public.pontos p
      left join public.equipe e on e.user_id = p.operadora_id
     where p.unidade_id = p_unidade and p.competencia = v_comp and p.operadora_id is not null
     group by p.operadora_id, e.nome
  )
  select coalesce(jsonb_agg(to_jsonb(q) order by q.finais desc, q.nome), '[]'::jsonb),
         coalesce(sum(q.brutos), 0), coalesce(sum(q.finais), 0), count(*)
    into v_ops, v_brutos, v_finais, v_n_bolo
    from q;

  if par.valor_ponto is null then
    v_total := null; v_individual := null; v_bolo := null; v_pago := null;
  else
    v_total := least(v_finais * par.valor_ponto, coalesce(par.teto_mes, v_finais * par.valor_ponto));
    v_individual := round(v_total * (100 - coalesce(par.pct_bolo, 30)) / 100.0, 2);
    v_bolo := round(v_total * coalesce(par.pct_bolo, 30) / 100.0, 2);
    v_pago := v_individual + case when v_carteira_ok then v_bolo else 0 end;
  end if;

  -- Rateio: individual proporcional aos finais; bolo em partes iguais (quando liberado).
  select coalesce(jsonb_agg(
           o || jsonb_build_object(
             'individual', case when v_individual is null or v_finais = 0 then null
                                else round(v_individual * (o->>'finais')::int / v_finais, 2) end,
             'bolo', case when v_bolo is null then null
                          when not v_carteira_ok or v_n_bolo = 0 then 0
                          else round(v_bolo / v_n_bolo, 2) end,
             'bolo_se_liberado', case when v_bolo is null or v_n_bolo = 0 then null else round(v_bolo / v_n_bolo, 2) end)
           order by (o->>'finais')::int desc, o->>'nome'), '[]'::jsonb)
    into v_ops
    from jsonb_array_elements(v_ops) o;
  select coalesce(jsonb_agg(o || jsonb_build_object(
           'total', case when (o->>'individual') is null then null
                         else (o->>'individual')::numeric + coalesce((o->>'bolo')::numeric, 0) end,
           'anulada', false)), '[]'::jsonb)
    into v_ops from jsonb_array_elements(v_ops) o;

  select jsonb_build_object('afericoes', count(*), 'pontos', coalesce(sum(p.pontos + p.bonus), 0))
    into v_sozinho
    from public.pontos p where p.unidade_id = p_unidade and p.competencia = v_comp and p.operadora_id is null;

  return jsonb_build_object(
    'unidade', v_nome, 'competencia', v_comp, 'fechado', false, 'simulado', v_sim,
    'regra', jsonb_build_object('valor_ponto', par.valor_ponto, 'teto_mes', par.teto_mes,
                                'pct_bolo', coalesce(par.pct_bolo, 30), 'vigencia', v_sim_vig),
    'carteira', jsonb_build_object('pct', v_carteira_pct, 'ok', v_carteira_ok, 'renovaram', v_renov,
                                   'venciam', v_renov + v_pend, 'nao_renovaram', v_pend,
                                   'piso', prm.piso_carteira_pct, 'fator', prm.fator_carteira),
    'pontos_brutos', v_brutos, 'pontos_finais', v_finais,
    'total_unidade', v_total, 'individual', v_individual, 'bolo', v_bolo,
    'bolo_liberado', v_carteira_ok, 'pago', v_pago,
    'fica_com_a_casa', case when v_total is null then null else v_total - v_pago end,
    'operadoras', v_ops, 'veio_sozinho', v_sozinho, 'observacao', null);
end $function$;

revoke all on function public.resultado_do_mes(uuid, date) from public, anon;
grant execute on function public.resultado_do_mes(uuid, date) to authenticated, service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- A FOTO DO MÊS É TIRADA NO DIA 5, SOZINHA — E DEPOIS O MÊS NÃO MUDA MAIS
--
-- Emerson (06/10): "essa foto deveria ficar estática por mês; mesmo que as
-- meninas tenham esquecido de atualizar alguma coisa, o esquecimento fica para
-- o próximo mês; o relatório sai todo dia 05 com a foto do mês anterior; assim
-- elas têm 5 dias para atualizar tudo."
--
-- O que muda em relação à 0083:
--   1. A auditoria deixa de ser obrigatória para fechar e passa a ter prazo:
--      do dia 1 ao 4 o gestor responde o que quiser (as respostas ficam
--      gravadas em `auditoria_respostas` na hora, não só no botão); o que não
--      foi respondido até a foto entra como válido. Reprovar continua anulando.
--   2. `fotografar_mes_anterior()` fecha o mês anterior de toda unidade ativa
--      que ainda não fechou, com as respostas gravadas. Agendada no pg_cron
--      para o dia 5 às 07:00 de Brasília (10:00 UTC). `fechado_por` fica nulo
--      = foto automática. O botão "Fechar" manual continua para admin/gestor
--      (antecipa a foto), sem exigir auditoria completa.
--   3. Aferição registrada depois da foto NÃO é mais recusada: a data da
--      aferição fica verdadeira (é ela que manda no vencimento), e o PONTO cai
--      na competência corrente, com `origem = 'atrasado'`. Quem esqueceu não
--      perde o ponto — recebe no mês seguinte. A foto não se mexe.

-- 1) respostas da auditoria gravadas na hora ------------------------------------
create table if not exists public.auditoria_respostas (
  ponto_id        uuid primary key references public.pontos(id) on delete cascade,
  unidade_id      uuid not null references public.unidades(id),
  competencia     date not null,
  ok              boolean not null,
  obs             text,
  respondido_por  uuid,
  respondido_em   timestamptz not null default now()
);
alter table public.auditoria_respostas enable row level security;
revoke all on public.auditoria_respostas from public, anon, authenticated;
grant select, insert, update, delete on public.auditoria_respostas to service_role;

create or replace function public.responder_auditoria(p_ponto uuid, p_ok boolean, p_obs text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_uni uuid; v_comp date;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select p.unidade_id, p.competencia into v_uni, v_comp from public.pontos p where p.id = p_ponto;
  if v_uni is null then raise exception 'afericao nao encontrada'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and v_uni = public.unidade_do_usuario())) then
    raise exception 'acesso negado';
  end if;
  if public.competencia_fechada(v_uni, v_comp) then
    raise exception 'a foto de % ja foi tirada; a auditoria nao muda mais', to_char(v_comp, 'MM/YYYY');
  end if;
  if not exists (select 1 from public.amostra_auditoria(v_uni, v_comp) s where s = p_ponto) then
    raise exception 'esta afericao nao esta na amostra sorteada do mes';
  end if;
  insert into public.auditoria_respostas (ponto_id, unidade_id, competencia, ok, obs, respondido_por)
  values (p_ponto, v_uni, v_comp, p_ok, nullif(btrim(coalesce(p_obs, '')), ''), auth.uid())
  on conflict (ponto_id) do update
    set ok = excluded.ok, obs = excluded.obs, respondido_por = excluded.respondido_por, respondido_em = now();
  return jsonb_build_object('ponto_id', p_ponto, 'ok', p_ok);
end $function$;
revoke all on function public.responder_auditoria(uuid, boolean, text) from public, anon;
grant execute on function public.responder_auditoria(uuid, boolean, text) to authenticated, service_role;

-- montar_meta: cada item da auditoria traz a resposta gravada (se houver)
do $$
declare v_def text; v_anc text := ') as marcado_por';
begin
  v_def := pg_get_functiondef('public.montar_meta(uuid, date, uuid, boolean)'::regprocedure);
  if (length(v_def) - length(replace(v_def, v_anc, ''))) / length(v_anc) <> 1 then
    raise exception '0113: ancora marcado_por nao e unica em montar_meta';
  end if;
  v_def := replace(v_def, v_anc,
    ') as marcado_por,
           (select jsonb_build_object(''ok'', r.ok, ''obs'', r.obs, ''em'', r.respondido_em)
              from public.auditoria_respostas r where r.ponto_id = p.id) as resposta');
  execute v_def;
end $$;

-- 2) o fechamento vira função interna; o manual e a foto chamam a mesma --------
create or replace function public.fechar_mes_interno(
  p_unidade uuid, p_competencia date, p_auditoria jsonb, p_whatsapp_restrito boolean,
  p_observacoes text, p_fechado_por uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_comp date; v_fim date; prm record; par record; v_fech uuid; v_aud jsonb;
  v_carteira_pct integer; v_carteira_ok boolean; v_pend integer; v_renov integer;
  v_pontos_brutos integer; v_pontos_finais integer;
  v_total numeric(10,2); v_individual numeric(10,2); v_bolo numeric(10,2);
  v_n_bolo integer;
begin
  v_comp := date_trunc('month', p_competencia)::date;
  v_fim  := (v_comp + interval '1 month')::date;
  if v_fim > current_date then raise exception 'o mes ainda nao terminou'; end if;
  if public.competencia_fechada(p_unidade, v_comp) then raise exception 'competencia ja fechada'; end if;

  -- Respostas: as que vieram no botão, senão as gravadas até agora. Quem não
  -- foi respondida entra como válida — a auditoria tem prazo, não é trava.
  v_aud := coalesce(nullif(p_auditoria, '[]'::jsonb), (
    select coalesce(jsonb_agg(jsonb_build_object('ponto_id', r.ponto_id, 'ok', r.ok, 'obs', r.obs)), '[]'::jsonb)
      from public.auditoria_respostas r where r.unidade_id = p_unidade and r.competencia = v_comp));

  select * into prm from public.parametros_pontos where id = 1;
  select * into par from public.parametros_premio(p_unidade, v_comp);

  select count(*) into v_pend from public.base_trabalhavel(p_unidade) b
   where b.nosso and b.venc >= v_comp and b.venc < v_fim;
  select count(*) into v_renov from public.pontos p
   where p.unidade_id = p_unidade and p.competencia = v_comp and p.classe in ('renovacao', 'contrato');
  v_carteira_pct := case when v_renov + v_pend = 0 then null else round(100.0 * v_renov / (v_renov + v_pend)) end;
  v_carteira_ok  := v_carteira_pct is null or v_carteira_pct >= prm.piso_carteira_pct;

  insert into public.fechamentos
    (unidade_id, competencia, fechado_por, whatsapp_restrito, observacoes,
     valor_ponto, teto_mes, pct_bolo, piso_carteira_pct, fator_carteira,
     carteira_pct, carteira_ok, pontos_brutos, pontos_finais, auditoria)
  values
    (p_unidade, v_comp, p_fechado_por, coalesce(p_whatsapp_restrito, false), nullif(btrim(coalesce(p_observacoes,'')), ''),
     par.valor_ponto, par.teto_mes, coalesce(par.pct_bolo, 30), prm.piso_carteira_pct, prm.fator_carteira,
     v_carteira_pct, v_carteira_ok, 0, 0, v_aud)
  returning id into v_fech;

  insert into public.fechamento_operadoras (fechamento_id, operadora_id, nome, afericoes, pontos_brutos, pontos_finais, anulada, motivo)
  select v_fech, q.operadora_id, q.nome, q.afericoes, q.brutos,
         case when q.anulada then 0 else q.finais end,
         q.anulada,
         case when q.anulada then 'aferição reprovada na auditoria' end
  from (
    select p.operadora_id, e.nome,
           count(*) as afericoes,
           sum(p.pontos + p.bonus)::int as brutos,
           sum(case when p.classe like 'conquista_%' and not v_carteira_ok
                    then floor((p.pontos + p.bonus) * prm.fator_carteira)
                    else p.pontos + p.bonus end)::int as finais,
           exists (select 1 from jsonb_array_elements(v_aud) x
                     join public.pontos px on px.id = (x->>'ponto_id')::uuid
                    where (x->>'ok')::boolean = false
                      and px.unidade_id = p_unidade and px.competencia = v_comp
                      and (px.registrado_por = p.operadora_id or px.operadora_id = p.operadora_id)) as anulada
      from public.pontos p
      left join public.equipe e on e.user_id = p.operadora_id
     where p.unidade_id = p_unidade and p.competencia = v_comp and p.operadora_id is not null
     group by p.operadora_id, e.nome
  ) q;

  select coalesce(sum(pontos_brutos),0), coalesce(sum(pontos_finais),0) into v_pontos_brutos, v_pontos_finais
    from public.fechamento_operadoras where fechamento_id = v_fech;

  if par.valor_ponto is null or coalesce(p_whatsapp_restrito, false) then
    v_total := case when coalesce(p_whatsapp_restrito, false) then 0 else null end;
    v_individual := v_total; v_bolo := case when v_total is null then null else 0 end;
  else
    v_total := least(v_pontos_finais * par.valor_ponto, coalesce(par.teto_mes, v_pontos_finais * par.valor_ponto));
    v_bolo := case when v_carteira_ok then round(v_total * coalesce(par.pct_bolo,30) / 100.0, 2) else 0 end;
    v_individual := round(v_total * (100 - coalesce(par.pct_bolo,30)) / 100.0, 2);
    if not v_carteira_ok then v_total := v_individual; end if;
  end if;

  select count(*) into v_n_bolo from public.fechamento_operadoras where fechamento_id = v_fech and not anulada;
  update public.fechamento_operadoras fo
     set individual = case when v_individual is null or v_pontos_finais = 0 then null
                           else round(v_individual * fo.pontos_finais / v_pontos_finais, 2) end,
         bolo       = case when v_bolo is null then null when fo.anulada or v_n_bolo = 0 then 0
                           else round(v_bolo / v_n_bolo, 2) end
   where fo.fechamento_id = v_fech;
  update public.fechamento_operadoras fo
     set total = case when individual is null then null else individual + coalesce(bolo, 0) end
   where fo.fechamento_id = v_fech;

  update public.fechamentos
     set pontos_brutos = v_pontos_brutos, pontos_finais = v_pontos_finais,
         total_pago = v_total, individual_pago = v_individual, bolo_pago = v_bolo
   where id = v_fech;

  return public.resumo_fechamento(p_unidade, v_comp);
end $function$;
revoke all on function public.fechar_mes_interno(uuid, date, jsonb, boolean, text, uuid) from public, anon, authenticated;
grant execute on function public.fechar_mes_interno(uuid, date, jsonb, boolean, text, uuid) to service_role;

-- o manual: mesmas permissões de antes, sem exigir auditoria completa
create or replace function public.fechar_mes(
  p_unidade uuid, p_competencia date, p_auditoria jsonb,
  p_whatsapp_restrito boolean default false, p_observacoes text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then
    raise exception 'acesso negado: so o gestor da unidade ou o admin geral fecha o mes';
  end if;
  return public.fechar_mes_interno(p_unidade, p_competencia, p_auditoria, p_whatsapp_restrito, p_observacoes, auth.uid());
end $function$;

-- a foto: todo dia 5, o mês anterior de cada unidade ativa que ainda não fechou
create or replace function public.fotografar_mes_anterior()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare u record; v_comp date; v_out jsonb := '[]'::jsonb; v_r jsonb;
begin
  v_comp := (date_trunc('month', current_date) - interval '1 month')::date;
  for u in select id, nome from public.unidades where suspensa_em is null order by nome loop
    if public.competencia_fechada(u.id, v_comp) then
      v_out := v_out || jsonb_build_object('unidade', u.nome, 'competencia', v_comp, 'ja_fechada', true);
      continue;
    end if;
    begin
      v_r := public.fechar_mes_interno(u.id, v_comp, null, false, 'Foto automática do dia 5.', null);
      v_out := v_out || jsonb_build_object('unidade', u.nome, 'competencia', v_comp, 'fechada', true,
                                           'pontos_finais', v_r->'pontos_finais', 'total_pago', v_r->'total_pago');
    exception when others then
      v_out := v_out || jsonb_build_object('unidade', u.nome, 'competencia', v_comp, 'erro', sqlerrm);
    end;
  end loop;
  return v_out;
end $function$;
revoke all on function public.fotografar_mes_anterior() from public, anon, authenticated;
grant execute on function public.fotografar_mes_anterior() to service_role;

-- agendamento no banco: dia 5, 07:00 de Brasília (10:00 UTC)
create extension if not exists pg_cron;
do $$
begin
  perform cron.unschedule('aferimais-foto-do-mes');
exception when others then null;
end $$;
select cron.schedule('aferimais-foto-do-mes', '0 10 5 * *', $$select public.fotografar_mes_anterior()$$);

-- 3) ponto atrasado cai no mês corrente, a aferição fica com a data verdadeira ----
alter table public.pontos drop constraint if exists pontos_origem_check;
alter table public.pontos add constraint pontos_origem_check
  check (origem = any (array['app', 'retroativo', 'atrasado']));

do $$
declare v_def text;
  v_anc1 text := 'if public.competencia_fechada(v_unidade, p_data) then raise exception ''o mes de % ja esta fechado nesta unidade; a data da afericao nao pode cair em mes fechado'', to_char(p_data, ''MM/YYYY''); end if;';
  v_anc2 text := 'date_trunc(''month'', p_data)::date, v_classe';
begin
  v_def := regexp_replace(pg_get_functiondef('public.pontuar_afericao'::regproc), '\s+', ' ', 'g');
  if position(v_anc1 in v_def) = 0 then raise exception '0113: ancora da trava nao encontrada em pontuar_afericao'; end if;
  if position(v_anc2 in v_def) = 0 then raise exception '0113: ancora da competencia nao encontrada em pontuar_afericao'; end if;
  v_def := replace(v_def, v_anc1, '');
  v_def := replace(v_def, v_anc2,
    'case when public.competencia_fechada(v_unidade, p_data) then date_trunc(''month'', current_date)::date else date_trunc(''month'', p_data)::date end, v_classe');
  -- origem: 'atrasado' quando a competência foi empurrada
  if position('registrado_por) values (' in v_def) = 0 then raise exception '0113: ancora do insert nao encontrada'; end if;
  v_def := replace(v_def, 'registrado_por) values (', 'registrado_por, origem) values (');
  if position('v_contato_em, auth.uid()) on conflict' in v_def) = 0 then raise exception '0113: ancora do fim do insert nao encontrada'; end if;
  v_def := replace(v_def, 'v_contato_em, auth.uid()) on conflict',
    'v_contato_em, auth.uid(), case when public.competencia_fechada(v_unidade, p_data) then ''atrasado'' else ''app'' end) on conflict');
  execute v_def;
end $$;
