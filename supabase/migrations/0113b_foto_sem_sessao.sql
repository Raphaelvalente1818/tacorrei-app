-- 0113b — A FOTO AUTOMÁTICA NÃO TEM SESSÃO (06/10)
--
-- A 0113 fazia fechar_mes_interno devolver resumo_fechamento(), que exige um
-- usuário logado (is_equipe_ativa). Quando o pg_cron tira a foto do dia 5 não há
-- ninguém logado, e a foto falhava com "acesso negado". Agora o interno devolve
-- a própria linha do fechamento; só o fechar_mes (chamado pela tela, com sessão)
-- continua devolvendo o resumo completo.

create or replace function public.fechar_mes_interno(
  p_unidade uuid, p_competencia date, p_auditoria jsonb,
  p_whatsapp_restrito boolean, p_observacoes text, p_fechado_por uuid)
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

  -- auditoria: a que veio na chamada, ou as respostas gravadas até o dia 4
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

  -- sem sessão: devolve a linha, não o resumo (que exige is_equipe_ativa)
  return (select jsonb_build_object('id', f.id, 'competencia', f.competencia, 'pontos_brutos', f.pontos_brutos,
             'pontos_finais', f.pontos_finais, 'total_pago', f.total_pago, 'carteira_pct', f.carteira_pct,
             'carteira_ok', f.carteira_ok) from public.fechamentos f where f.id = v_fech);
end $function$;

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
  perform public.fechar_mes_interno(p_unidade, p_competencia, p_auditoria, p_whatsapp_restrito, p_observacoes, auth.uid());
  return public.resumo_fechamento(p_unidade, date_trunc('month', p_competencia)::date);
end $function$;
