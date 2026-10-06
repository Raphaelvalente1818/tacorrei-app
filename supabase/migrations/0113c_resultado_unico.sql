-- 0113c — RESULTADO DO MÊS, VERSÃO ÚNICA: FOTO OU PRÉVIA, COM SIMULAÇÃO (06/10)
--
-- A 0113 tinha dois caminhos (mês fechado → resumo do fechamento; aberto →
-- cálculo ao vivo) e o fechado perdia a simulação: setembro de São Bernardo é
-- mês de observação, a foto grava total_pago nulo, e o quadro ficava sem
-- dinheiro — exatamente o que o Emerson quer ver (setembro com a regra de
-- outubro). Agora é uma função só: os PONTOS vêm congelados do fechamento quando
-- há foto (com as anulações da auditoria), ou ao vivo quando não há; e o
-- DINHEIRO usa a regra do mês, ou, se o mês é de observação, a próxima regra que
-- paga — marcado como simulação, com a vigência usada.

create or replace function public.resultado_do_mes(p_unidade uuid, p_competencia date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_comp date; v_fim date; prm record; par record; f record;
  v_fechado boolean := false; v_sim boolean := false; v_sim_vig date;
  v_pend integer; v_renov integer; v_carteira_pct integer; v_carteira_ok boolean;
  v_finais integer; v_brutos integer; v_n_bolo integer;
  v_total numeric(10,2); v_individual numeric(10,2); v_bolo numeric(10,2); v_pago numeric(10,2);
  v_ops jsonb; v_sozinho jsonb; v_nome text; v_obs text; v_fechado_em timestamptz; v_fechado_por text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then
    raise exception 'acesso negado';
  end if;
  v_comp := date_trunc('month', p_competencia)::date;
  v_fim  := (v_comp + interval '1 month')::date;
  select nome into v_nome from public.unidades where id = p_unidade;
  select * into prm from public.parametros_pontos where id = 1;

  select * into f from public.fechamentos x where x.unidade_id = p_unidade and x.competencia = v_comp;

  if f.id is not null then
    -- A FOTO: pontos e carteira congelados, com as anulações da auditoria.
    v_fechado := true;
    v_obs := f.observacoes; v_fechado_em := f.fechado_em;
    select e.nome into v_fechado_por from public.equipe e where e.user_id = f.fechado_por;
    v_carteira_pct := f.carteira_pct; v_carteira_ok := f.carteira_ok;
    v_renov := null; v_pend := null;
    select coalesce(jsonb_agg(jsonb_build_object('nome', o.nome, 'afericoes', o.afericoes, 'brutos', o.pontos_brutos,
                                                  'finais', o.pontos_finais, 'anulada', o.anulada)
                              order by o.pontos_finais desc, o.nome), '[]'::jsonb),
           coalesce(sum(o.pontos_brutos), 0), coalesce(sum(o.pontos_finais), 0), count(*) filter (where not o.anulada)
      into v_ops, v_brutos, v_finais, v_n_bolo
      from public.fechamento_operadoras o where o.fechamento_id = f.id;
    select f.valor_ponto as valor_ponto, f.teto_mes as teto_mes, f.pct_bolo as pct_bolo,
           null::date as vigencia, null::text as observacao into par;
  else
    -- A PRÉVIA: ao vivo, mesma conta do fechamento.
    select * into par from public.parametros_premio(p_unidade, v_comp);
    select count(*) into v_pend from public.base_trabalhavel(p_unidade) b
     where b.nosso and b.venc >= v_comp and b.venc < v_fim;
    select count(*) into v_renov from public.pontos p
     where p.unidade_id = p_unidade and p.competencia = v_comp and p.classe in ('renovacao', 'contrato');
    v_carteira_pct := case when v_renov + v_pend = 0 then null else round(100.0 * v_renov / (v_renov + v_pend)) end;
    v_carteira_ok  := v_carteira_pct is null or v_carteira_pct >= prm.piso_carteira_pct;
    with q as (
      select coalesce(e.nome, 'Usuário removido') as nome,
             count(*)::int as afericoes,
             sum(p.pontos + p.bonus)::int as brutos,
             sum(case when p.classe like 'conquista_%' and not v_carteira_ok
                      then floor((p.pontos + p.bonus) * prm.fator_carteira)
                      else p.pontos + p.bonus end)::int as finais,
             false as anulada
        from public.pontos p
        left join public.equipe e on e.user_id = p.operadora_id
       where p.unidade_id = p_unidade and p.competencia = v_comp and p.operadora_id is not null
       group by p.operadora_id, e.nome
    )
    select coalesce(jsonb_agg(to_jsonb(q) order by q.finais desc, q.nome), '[]'::jsonb),
           coalesce(sum(q.brutos), 0), coalesce(sum(q.finais), 0), count(*)
      into v_ops, v_brutos, v_finais, v_n_bolo
      from q;
  end if;

  -- Mês de observação (ou sem regra): simula com a próxima regra que paga.
  if par.valor_ponto is null then
    select p.valor_ponto, p.teto_mes, p.pct_bolo, p.vigencia, p.observacao into par
      from public.parametros_unidade p
     where p.unidade_id = p_unidade and p.valor_ponto is not null and p.vigencia > v_comp
     order by p.vigencia asc limit 1;
    if par.valor_ponto is not null then v_sim := true; v_sim_vig := par.vigencia; end if;
  end if;

  if par.valor_ponto is null then
    v_total := null; v_individual := null; v_bolo := null; v_pago := null;
  elsif v_fechado and f.whatsapp_restrito then
    v_total := 0; v_individual := 0; v_bolo := 0; v_pago := 0;
  else
    v_total := least(v_finais * par.valor_ponto, coalesce(par.teto_mes, v_finais * par.valor_ponto));
    v_individual := round(v_total * (100 - coalesce(par.pct_bolo, 30)) / 100.0, 2);
    v_bolo := round(v_total * coalesce(par.pct_bolo, 30) / 100.0, 2);
    v_pago := v_individual + case when v_carteira_ok then v_bolo else 0 end;
  end if;

  select coalesce(jsonb_agg(
           o || jsonb_build_object(
             'individual', case when v_individual is null or v_finais = 0 or (o->>'anulada')::boolean then
                                  case when v_individual is null then null else 0 end
                                else round(v_individual * (o->>'finais')::int / v_finais, 2) end,
             'bolo', case when v_bolo is null then null
                          when not v_carteira_ok or v_n_bolo = 0 or (o->>'anulada')::boolean then 0
                          else round(v_bolo / v_n_bolo, 2) end,
             'bolo_se_liberado', case when v_bolo is null or v_n_bolo = 0 then null else round(v_bolo / v_n_bolo, 2) end)
           order by (o->>'finais')::int desc, o->>'nome'), '[]'::jsonb)
    into v_ops from jsonb_array_elements(v_ops) o;
  select coalesce(jsonb_agg(o || jsonb_build_object(
           'total', case when (o->>'individual') is null then null
                         else (o->>'individual')::numeric + coalesce((o->>'bolo')::numeric, 0) end)), '[]'::jsonb)
    into v_ops from jsonb_array_elements(v_ops) o;

  select jsonb_build_object('afericoes', count(*), 'pontos', coalesce(sum(p.pontos + p.bonus), 0))
    into v_sozinho
    from public.pontos p where p.unidade_id = p_unidade and p.competencia = v_comp and p.operadora_id is null;

  return jsonb_build_object(
    'unidade', v_nome, 'competencia', v_comp,
    'fechado', v_fechado, 'fechado_em', v_fechado_em, 'fechado_por', v_fechado_por,
    'simulado', v_sim,
    'regra', jsonb_build_object('valor_ponto', par.valor_ponto, 'teto_mes', par.teto_mes,
                                'pct_bolo', coalesce(par.pct_bolo, 30), 'vigencia', v_sim_vig),
    'carteira', jsonb_build_object('pct', v_carteira_pct, 'ok', v_carteira_ok, 'renovaram', v_renov,
                                   'venciam', case when v_renov is null then null else v_renov + v_pend end,
                                   'nao_renovaram', v_pend, 'piso', prm.piso_carteira_pct, 'fator', prm.fator_carteira),
    'pontos_brutos', v_brutos, 'pontos_finais', v_finais,
    'total_unidade', v_total, 'individual', v_individual, 'bolo', v_bolo,
    'bolo_liberado', v_carteira_ok, 'pago', v_pago,
    'fica_com_a_casa', case when v_total is null then null else v_total - v_pago end,
    'operadoras', v_ops, 'veio_sozinho', v_sozinho, 'observacao', v_obs);
end $function$;

-- a foto guarda também renovaram/venciam para o quadro não perder o "29 de 84"
alter table public.fechamentos
  add column if not exists carteira_renovaram integer,
  add column if not exists carteira_venciam integer;

do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.fechar_mes_interno(uuid, date, jsonb, boolean, text, uuid)'::regprocedure);
  if position('carteira_pct, carteira_ok, pontos_brutos, pontos_finais, auditoria)' in v_def) = 0
     or position('v_carteira_pct, v_carteira_ok, 0, 0, v_aud)' in v_def) = 0 then
    raise exception '0113c: ancoras do insert nao encontradas';
  end if;
  v_def := replace(v_def, 'carteira_pct, carteira_ok, pontos_brutos, pontos_finais, auditoria)',
                          'carteira_pct, carteira_ok, pontos_brutos, pontos_finais, auditoria, carteira_renovaram, carteira_venciam)');
  v_def := replace(v_def, 'v_carteira_pct, v_carteira_ok, 0, 0, v_aud)',
                          'v_carteira_pct, v_carteira_ok, 0, 0, v_aud, v_renov, v_renov + v_pend)');
  execute v_def;
end $$;

-- e o resultado lê de lá quando é foto
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.resultado_do_mes(uuid, date)'::regprocedure);
  if position('v_renov := null; v_pend := null;' in v_def) = 0 then raise exception '0113c: ancora carteira nao encontrada'; end if;
  v_def := replace(v_def, 'v_renov := null; v_pend := null;',
                          'v_renov := f.carteira_renovaram; v_pend := case when f.carteira_venciam is null then null else f.carteira_venciam - f.carteira_renovaram end;');
  execute v_def;
end $$;
