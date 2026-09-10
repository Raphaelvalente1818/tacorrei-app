-- 0071 — Placar da operadora
--
-- A operadora vê a mesma composição do mês que o admin vê na aba Meta, com
-- duas diferenças: só os PRÓPRIOS pontos no detalhe (nada da colega além do
-- total consolidado da unidade) e sem a amostra de auditoria.
--
-- Para não manter duas cópias da mesma conta, o miolo vira `montar_meta()`
-- (interna, sem grant) e as duas funções públicas — `meta_do_mes` para o admin
-- e `placar_operadora` para a operadora — só decidem o que ela recebe.

create or replace function public.montar_meta(
  p_unidade      uuid,
  p_competencia  date,
  p_operadora    uuid,      -- nulo = tudo (admin); preenchido = só ela
  p_com_auditoria boolean
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_comp date; v_ini date; v_fim date; prm record;
  v_universo jsonb; v_realizado jsonb; v_detalhe jsonb; v_carteira jsonb;
  v_risco jsonb; v_auditoria jsonb; v_unidade jsonb; v_total_unidade jsonb;
  v_pend integer; v_renov integer;
begin
  v_comp := date_trunc('month', coalesce(p_competencia, current_date))::date;
  v_ini  := v_comp;
  v_fim  := (v_comp + interval '1 month')::date;

  select * into prm from public.parametros_pontos where id = 1;

  select jsonb_build_object('id', u.id, 'nome', u.nome, 'posto', u.posto_afericao)
    into v_unidade from public.unidades u where u.id = p_unidade;

  -- ── Universo: o que vence neste mês, por classe (estado ATUAL da base) ──────
  with v as (
    select c.id, c.empresa_id, e.situacao,
           public.posto_do_grupo(c.posto_afericao) as nosso,
           (c.data_ultima_afericao + interval '2 years')::date as venc,
           exists (select 1 from public.caminhoneiros x
                    where x.empresa_id = c.empresa_id and x.id <> c.id
                      and public.posto_do_grupo(x.posto_afericao)) as empresa_tem_nosso
    from public.caminhoneiros c
    left join public.empresas e on e.id = c.empresa_id
    where c.unidade_id = p_unidade and c.tem_tacografo
      and c.posto_afericao is not null and c.data_ultima_afericao is not null
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
    'vencidos_recuperaveis', count(*) filter (where not nosso and venc < current_date and venc >= current_date - 365),
    'vencidos_frios',        count(*) filter (where not nosso and venc < current_date - 365),
    'empresas_pe_na_porta',  (select count(distinct empresa_id) from v x
                               where x.empresa_id is not null and x.empresa_tem_nosso and not x.nosso
                                 and x.venc between current_date and current_date + 90)
  ) into v_universo from v;

  -- ── Realizado por operadora (ou só a dela) ────────────────────────────────
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

  -- ── Total consolidado da unidade (o que a operadora pode ver da colega) ──
  select jsonb_build_object(
    'afericoes', count(*),
    'pontos', coalesce(sum(p.pontos + p.bonus) filter (where p.operadora_id is not null), 0),
    'empresas_conquistadas', count(*) filter (where p.empresa_conquistada),
    'sem_atribuicao', count(*) filter (where p.operadora_id is null)
  ) into v_total_unidade
  from public.pontos p
  where p.unidade_id = p_unidade and p.competencia = v_comp;

  -- ── Detalhe: a origem de cada ponto ───────────────────────────────────────
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

  -- ── Carteira defendida ────────────────────────────────────────────────────
  select count(*) into v_pend
    from public.caminhoneiros c
   where c.unidade_id = p_unidade and c.tem_tacografo
     and public.posto_do_grupo(c.posto_afericao)
     and (c.data_ultima_afericao + interval '2 years')::date >= v_ini
     and (c.data_ultima_afericao + interval '2 years')::date <  v_fim;
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

  -- ── Risco: o que pode vazar nos próximos 90 dias ──────────────────────────
  select jsonb_build_object(
    'nossos_90d', count(*) filter (where venc between current_date and current_date + 90),
    'atrasados',  count(*) filter (where venc < current_date - 30),
    'empresas', coalesce((
      select jsonb_agg(jsonb_build_object('nome', nome, 'em_risco', n) order by n desc)
      from (
        select e.nome, count(*) n
        from public.caminhoneiros c join public.empresas e on e.id = c.empresa_id
        where c.unidade_id = p_unidade and c.tem_tacografo
          and public.posto_do_grupo(c.posto_afericao) and e.situacao <> 'contrato'
          and (c.data_ultima_afericao + interval '2 years')::date between current_date - 30 and current_date + 90
        group by e.nome order by n desc limit 10
      ) t), '[]'::jsonb)
  ) into v_risco
  from (
    select (c.data_ultima_afericao + interval '2 years')::date as venc
    from public.caminhoneiros c
    left join public.empresas e on e.id = c.empresa_id
    where c.unidade_id = p_unidade and c.tem_tacografo
      and public.posto_do_grupo(c.posto_afericao)
      and coalesce(e.situacao, '') <> 'contrato'
      and c.data_ultima_afericao is not null
  ) x;

  -- ── Auditoria: só para o admin ────────────────────────────────────────────
  if p_com_auditoria then
    select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into v_auditoria
    from (
      select p.id, p.data_afericao, c.placa_veiculo as placa, c.nome as dono,
             e.nome as empresa, p.classe, p.pontos + p.bonus as total, q.nome as operadora
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

  return jsonb_build_object(
    'competencia', v_comp,
    'unidade', v_unidade,
    'parametros', to_jsonb(prm),
    'universo', v_universo,
    'realizado', v_realizado,
    'total_unidade', v_total_unidade,
    'detalhe', v_detalhe,
    'carteira', v_carteira,
    'risco', v_risco,
    'auditoria', v_auditoria
  );
end $$;

revoke all on function public.montar_meta(uuid, date, uuid, boolean) from public, anon, authenticated;
grant execute on function public.montar_meta(uuid, date, uuid, boolean) to service_role;

-- O admin: tudo, com auditoria.
create or replace function public.meta_do_mes(
  p_unidade uuid,
  p_competencia date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if p_unidade is null then raise exception 'escolha uma unidade'; end if;
  if not (public.is_admin()
          or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then
    raise exception 'acesso negado';
  end if;
  return public.montar_meta(p_unidade, p_competencia, null, true);
end $$;

revoke all on function public.meta_do_mes(uuid, date) from public, anon;
grant execute on function public.meta_do_mes(uuid, date) to authenticated, service_role;

-- A operadora: a unidade dela, só os pontos dela, sem auditoria.
create or replace function public.placar_operadora(
  p_competencia date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_unidade := public.unidade_do_usuario();
  if v_unidade is null then raise exception 'usuario sem unidade'; end if;
  return public.montar_meta(v_unidade, p_competencia, auth.uid(), false);
end $$;

revoke all on function public.placar_operadora(date) from public, anon;
grant execute on function public.placar_operadora(date) to authenticated, service_role;
