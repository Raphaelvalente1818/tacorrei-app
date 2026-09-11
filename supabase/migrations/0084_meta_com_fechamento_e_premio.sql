-- 0084 — Meta do mês com prêmio e fechamento
--
-- A tela "Meta do mês" / "Meu placar" passa a receber, no mesmo JSON:
--   premio     → parametros_premio(unidade, competência): valor do ponto, teto,
--                % do bolo e vigência. valor_ponto null = mês de observação.
--   fechamento → resumo_fechamento(unidade, competência), ou null enquanto o
--                mês está aberto. Para a operadora vem só a linha dela.
--   unidade.edita_premio → se o gestor da unidade pode mexer em valor/teto
--                (por padrão não — decisão de 10/09: só o admin geral).
--   auditoria[].marcado_por → quem marcou a aferição (registrado_por), além
--                de quem pontuou. Um registro falso anula o mês dos dois.
--
-- Depende de 0083 (parametros_unidade, fechamentos, fechar_mes, resumo_fechamento).
-- Aplicada em 11/09/2026. Conferência: conferencia_contagens() 24/24 ok,
-- testes_pontuacao() 14/14 ok.

create or replace function public.montar_meta(p_unidade uuid, p_competencia date, p_operadora uuid, p_com_auditoria boolean)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_comp date; v_ini date; v_fim date; prm record;
  v_universo jsonb; v_realizado jsonb; v_detalhe jsonb; v_carteira jsonb;
  v_risco jsonb; v_auditoria jsonb; v_unidade jsonb; v_total_unidade jsonb;
  v_pend integer; v_renov integer; v_frios integer; v_premio jsonb; v_fech jsonb;
begin
  v_comp := date_trunc('month', coalesce(p_competencia, current_date))::date;
  v_ini  := v_comp;
  v_fim  := (v_comp + interval '1 month')::date;
  select * into prm from public.parametros_pontos where id = 1;
  select jsonb_build_object('id', u.id, 'nome', u.nome, 'posto', u.posto_afericao, 'edita_premio', u.unidade_edita_premio)
    into v_unidade from public.unidades u where u.id = p_unidade;

  select count(*) into v_frios
    from public.caminhoneiros c
   where c.unidade_id = p_unidade and c.tem_tacografo
     and c.posto_afericao is not null and c.data_ultima_afericao is not null
     and not coalesce(public.posto_do_grupo(c.posto_afericao), false)
     and not public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao);

  with v as (
    select b.id, b.empresa_id, b.empresa_situacao as situacao, b.nosso, b.venc,
           exists (select 1 from public.caminhoneiros x
                    where x.empresa_id = b.empresa_id and x.id <> b.id
                      and public.posto_do_grupo(x.posto_afericao)) as empresa_tem_nosso
    from public.base_trabalhavel(p_unidade) b
    where b.posto_conhecido
  )
  select jsonb_build_object(
    'vencem_no_mes', jsonb_build_object(
      'contrato',          count(*) filter (where venc >= v_ini and venc < v_fim and situacao = 'contrato'),
      'nossos',            count(*) filter (where venc >= v_ini and venc < v_fim and coalesce(situacao,'') <> 'contrato' and nosso),
      'concorrente_mista', count(*) filter (where venc >= v_ini and venc < v_fim and coalesce(situacao,'') <> 'contrato' and not nosso and empresa_id is not null and empresa_tem_nosso),
      'concorrente_virgem',count(*) filter (where venc >= v_ini and venc < v_fim and coalesce(situacao,'') <> 'contrato' and not nosso and empresa_id is not null and not empresa_tem_nosso),
      'concorrente_avulso',count(*) filter (where venc >= v_ini and venc < v_fim and not nosso and empresa_id is null),
      'total',             count(*) filter (where venc >= v_ini and venc < v_fim)
    ),
    'vencidos_recuperaveis', count(*) filter (where not nosso and venc < current_date),
    'vencidos_frios',        v_frios,
    'empresas_pe_na_porta',  (select count(distinct empresa_id) from v x
                               where x.empresa_id is not null and x.empresa_tem_nosso and not x.nosso
                                 and x.venc between current_date and current_date + 90)
  ) into v_universo from v;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.total desc, r.nome), '[]'::jsonb) into v_realizado
  from (
    select p.operadora_id,
           coalesce(q.nome, case when p.operadora_id is null then 'Sem atribuição (veio sozinho)' else 'Usuário removido' end) as nome,
           coalesce(q.papel, '') as papel,
           count(*) as afericoes,
           sum(p.pontos) as pontos,
           sum(p.bonus) as bonus,
           sum(p.pontos + p.bonus) as total,
           count(*) filter (where p.classe = 'conquista_mista')  as conquista_mista,
           count(*) filter (where p.classe = 'conquista_virgem') as conquista_virgem,
           count(*) filter (where p.classe = 'conquista_avulso') as conquista_avulso,
           count(*) filter (where p.classe = 'vencido')          as vencido,
           count(*) filter (where p.classe = 'renovacao')        as renovacao,
           count(*) filter (where p.classe = 'contrato')         as contrato,
           count(*) filter (where p.empresa_conquistada)         as empresas_conquistadas
    from public.pontos p
    left join public.equipe q on q.user_id = p.operadora_id
    where p.unidade_id = p_unidade and p.competencia = v_comp
      and (p_operadora is null or p.operadora_id = p_operadora)
    group by p.operadora_id, q.nome, q.papel
  ) r;

  select jsonb_build_object(
    'afericoes', count(*),
    'pontos', coalesce(sum(p.pontos + p.bonus) filter (where p.operadora_id is not null), 0),
    'empresas_conquistadas', count(*) filter (where p.empresa_conquistada),
    'sem_atribuicao', count(*) filter (where p.operadora_id is null)
  ) into v_total_unidade
  from public.pontos p
  where p.unidade_id = p_unidade and p.competencia = v_comp;

  select coalesce(jsonb_agg(to_jsonb(d) order by d.data_afericao desc, d.registrado_em desc), '[]'::jsonb) into v_detalhe
  from (
    select p.id, p.data_afericao, p.registrado_em, p.classe, p.pontos, p.bonus,
           p.empresa_conquistada, p.origem, p.posto_anterior, p.venc_anterior,
           c.placa_veiculo as placa, c.nome as dono, e.nome as empresa,
           q.nome as operadora, p.contato_em,
           (select l.canal from public.ligacoes l where l.id = p.contato_id) as contato_canal,
           (select case when l.empresa_id is not null then 'empresa' else 'placa' end
              from public.ligacoes l where l.id = p.contato_id) as contato_alvo
    from public.pontos p
    join public.caminhoneiros c on c.id = p.caminhoneiro_id
    left join public.empresas e on e.id = p.empresa_id
    left join public.equipe q on q.user_id = p.operadora_id
    where p.unidade_id = p_unidade and p.competencia = v_comp
      and (p_operadora is null or p.operadora_id = p_operadora)
  ) d;

  select count(*) into v_pend
    from public.base_trabalhavel(p_unidade) b
   where b.nosso and b.venc >= v_ini and b.venc < v_fim;
  select count(*) into v_renov
    from public.pontos p
   where p.unidade_id = p_unidade and p.competencia = v_comp
     and p.classe in ('renovacao', 'contrato');
  v_carteira := jsonb_build_object(
    'renovados', v_renov,
    'pendentes', v_pend,
    'pct_defendida', case when v_renov + v_pend = 0 then null
                          else round(100.0 * v_renov / (v_renov + v_pend)) end,
    'piso_pct', prm.piso_carteira_pct,
    'fator', prm.fator_carteira,
    'mes_fechado', v_fim <= current_date
  );

  select jsonb_build_object(
    'nossos_90d', count(*) filter (where b.venc between current_date and current_date + 90),
    'atrasados',  count(*) filter (where b.venc < current_date - 30),
    'empresas', coalesce((
      select jsonb_agg(jsonb_build_object('nome', nome, 'em_risco', n) order by n desc)
      from (
        select x.empresa_nome as nome, count(*) n
        from public.base_trabalhavel(p_unidade) x
        where x.nosso and x.empresa_id is not null and coalesce(x.empresa_situacao,'') <> 'contrato'
          and x.venc between current_date - 30 and current_date + 90
        group by x.empresa_nome order by n desc limit 10
      ) t), '[]'::jsonb)
  ) into v_risco
  from public.base_trabalhavel(p_unidade) b
  where b.nosso and coalesce(b.empresa_situacao, '') <> 'contrato';

  if p_com_auditoria then
    select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into v_auditoria
    from (
      select p.id, p.data_afericao, c.placa_veiculo as placa, c.nome as dono,
             e.nome as empresa, p.classe, p.pontos + p.bonus as total, q.nome as operadora,
             (select e2.nome from public.equipe e2 where e2.user_id = p.registrado_por) as marcado_por
      from public.pontos p
      join public.caminhoneiros c on c.id = p.caminhoneiro_id
      left join public.empresas e on e.id = p.empresa_id
      left join public.equipe q on q.user_id = p.operadora_id
      where p.unidade_id = p_unidade and p.competencia = v_comp
      order by md5(p.id::text || v_comp::text)
      limit 10
    ) a;
  else
    v_auditoria := '[]'::jsonb;
  end if;

  select to_jsonb(x) into v_premio from public.parametros_premio(p_unidade, v_comp) x;
  v_fech := public.resumo_fechamento(p_unidade, v_comp);

  return jsonb_build_object(
    'competencia', v_comp,
    'unidade', v_unidade,
    'parametros', to_jsonb(prm),
    'premio', v_premio,
    'fechamento', v_fech,
    'universo', v_universo,
    'realizado', v_realizado,
    'total_unidade', v_total_unidade,
    'detalhe', v_detalhe,
    'carteira', v_carteira,
    'risco', v_risco,
    'auditoria', v_auditoria
  );
end $function$;
