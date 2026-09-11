-- 0083 — Fechamento mensal: parâmetros do prêmio por unidade (com vigência), fechar_mes(),
--        e a trava "mês fechado não muda".
--
-- Regra (Emerson, 10–11/09/2026; metodo-de-pontuacao.md):
--   total pago = pontos da unidade × valor do ponto, limitado ao teto; sobra não acumula;
--   70% individual proporcional aos pontos de cada operadora; 30% bolo comum dividido igual
--   entre as operadoras ativas — só se a carteira defendida bateu o piso (60%); abaixo do
--   piso, pontos de conquista × 0,8 e sem bolo. Auditoria de dez aferições: uma falsa anula
--   o mês inteiro de quem marcou. WhatsApp restrito no mês: ninguém recebe.
--   Setembro/2026 é observação (valor definido pelos sócios no fechamento). A partir de
--   outubro: R$ 5/ponto; teto R$ 2.000 (SBC) e R$ 1.000 (SA); bolo 30%. Mudança de valor ou
--   teto vale a partir do mês seguinte, nunca no corrente (vigência por mês).
--   O admin de unidade só edita valor/teto se `unidades.unidade_edita_premio` (item 9 da
--   matriz) — nasce desligado.

-- ---------------------------------------------------------------------------
-- 1. Parâmetros do prêmio por unidade, com vigência
-- ---------------------------------------------------------------------------
alter table public.unidades add column if not exists unidade_edita_premio boolean not null default false;

create table if not exists public.parametros_unidade (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidades(id) on delete cascade,
  vigencia       date not null,                       -- 1º dia do mês a partir do qual vale
  valor_ponto    numeric(10,2),                       -- null = mês de observação (valor a definir)
  teto_mes       numeric(10,2),
  pct_bolo       integer not null default 30 check (pct_bolo between 0 and 100),
  observacao     text,
  criado_por     uuid,
  criado_em      timestamptz not null default now(),
  unique (unidade_id, vigencia),
  check (vigencia = date_trunc('month', vigencia)::date)
);
alter table public.parametros_unidade enable row level security;
drop policy if exists "parametros_unidade: le a propria unidade" on public.parametros_unidade;
create policy "parametros_unidade: le a propria unidade" on public.parametros_unidade
  for select to authenticated
  using (public.is_equipe_ativa() and (public.is_admin() or unidade_id = public.unidade_do_usuario()));
-- escrita só pelas funções (security definer)
revoke insert, update, delete on public.parametros_unidade from authenticated, anon;

-- parâmetros vigentes numa competência: a última vigência <= competência
create or replace function public.parametros_premio(p_unidade uuid, p_competencia date)
returns table (valor_ponto numeric, teto_mes numeric, pct_bolo integer, vigencia date, observacao text)
language sql stable security definer set search_path = public, pg_temp as $$
  select p.valor_ponto, p.teto_mes, p.pct_bolo, p.vigencia, p.observacao
    from public.parametros_unidade p
   where p.unidade_id = p_unidade
     and p.vigencia <= date_trunc('month', p_competencia)::date
   order by p.vigencia desc
   limit 1
$$;
revoke execute on function public.parametros_premio(uuid, date) from public, anon;
grant execute on function public.parametros_premio(uuid, date) to authenticated, service_role;

-- definir parâmetros: admin geral sempre; admin de unidade só se liberado; vigência nunca no mês corrente
create or replace function public.definir_parametros_premio(
  p_unidade uuid, p_vigencia date, p_valor_ponto numeric, p_teto_mes numeric, p_pct_bolo integer default 30, p_observacao text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_vig date; v_edita boolean;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_vig := date_trunc('month', p_vigencia)::date;
  select u.unidade_edita_premio into v_edita from public.unidades u where u.id = p_unidade;
  if v_edita is null then raise exception 'unidade nao encontrada'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario() and v_edita)) then
    raise exception 'acesso negado: valor do ponto e teto sao definidos pelo admin geral';
  end if;
  if v_vig <= date_trunc('month', current_date)::date and not public.is_admin() then
    raise exception 'a vigencia precisa ser um mes futuro (mudanca nunca vale no mes corrente)';
  end if;
  if p_valor_ponto is not null and p_valor_ponto < 0 then raise exception 'valor invalido'; end if;
  if p_teto_mes is not null and p_teto_mes < 0 then raise exception 'teto invalido'; end if;

  insert into public.parametros_unidade (unidade_id, vigencia, valor_ponto, teto_mes, pct_bolo, observacao, criado_por)
  values (p_unidade, v_vig, p_valor_ponto, p_teto_mes, coalesce(p_pct_bolo, 30), p_observacao, auth.uid())
  on conflict (unidade_id, vigencia) do update
    set valor_ponto = excluded.valor_ponto, teto_mes = excluded.teto_mes, pct_bolo = excluded.pct_bolo,
        observacao = excluded.observacao, criado_por = excluded.criado_por, criado_em = now();
  return (select to_jsonb(p) from public.parametros_unidade p where p.unidade_id = p_unidade and p.vigencia = v_vig);
end $$;
revoke execute on function public.definir_parametros_premio(uuid, date, numeric, numeric, integer, text) from public, anon;
grant execute on function public.definir_parametros_premio(uuid, date, numeric, numeric, integer, text) to authenticated, service_role;

-- sementes: setembro = observação; outubro em diante = valores decididos em 11/09
insert into public.parametros_unidade (unidade_id, vigencia, valor_ponto, teto_mes, pct_bolo, observacao)
select u.id, date '2026-09-01', null, null, 30, 'Mês de observação: valor definido pelos sócios no fechamento.'
  from public.unidades u
on conflict do nothing;
insert into public.parametros_unidade (unidade_id, vigencia, valor_ponto, teto_mes, pct_bolo, observacao)
select u.id, date '2026-10-01', 5.00,
       case when u.nome ilike '%bernardo%' then 2000.00 else 1000.00 end, 30,
       'Decisão de 11/09/2026 (Emerson): R$ 5/ponto; teto R$ 2.000 SBC, R$ 1.000 SA; bolo 30%.'
  from public.unidades u
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2. O fechamento
-- ---------------------------------------------------------------------------
create table if not exists public.fechamentos (
  id                 uuid primary key default gen_random_uuid(),
  unidade_id         uuid not null references public.unidades(id) on delete cascade,
  competencia        date not null,
  fechado_em         timestamptz not null default now(),
  fechado_por        uuid,
  whatsapp_restrito  boolean not null default false,
  observacoes        text,
  -- o que valia no mês
  valor_ponto        numeric(10,2),
  teto_mes           numeric(10,2),
  pct_bolo           integer not null,
  piso_carteira_pct  integer not null,
  fator_carteira     numeric(4,2) not null,
  -- o resultado
  carteira_pct       integer,            -- null = sem caminhão nosso vencendo no mês
  carteira_ok        boolean not null,
  pontos_brutos      integer not null,
  pontos_finais      integer not null,
  total_pago         numeric(10,2),      -- null = mês de observação (a definir)
  bolo_pago          numeric(10,2),
  individual_pago    numeric(10,2),
  auditoria          jsonb not null default '[]'::jsonb,   -- [{ponto_id, ok, obs}]
  unique (unidade_id, competencia)
);
create table if not exists public.fechamento_operadoras (
  fechamento_id      uuid not null references public.fechamentos(id) on delete cascade,
  operadora_id       uuid not null,
  nome               text,
  afericoes          integer not null default 0,
  pontos_brutos      integer not null default 0,
  pontos_finais      integer not null default 0,
  anulada            boolean not null default false,
  motivo             text,
  individual         numeric(10,2),
  bolo               numeric(10,2),
  total              numeric(10,2),
  primary key (fechamento_id, operadora_id)
);
alter table public.fechamentos enable row level security;
alter table public.fechamento_operadoras enable row level security;
drop policy if exists "fechamentos: le a propria unidade" on public.fechamentos;
create policy "fechamentos: le a propria unidade" on public.fechamentos
  for select to authenticated
  using (public.is_equipe_ativa() and (public.is_admin() or unidade_id = public.unidade_do_usuario()));
drop policy if exists "fechamento_operadoras: le a propria unidade" on public.fechamento_operadoras;
create policy "fechamento_operadoras: le a propria unidade" on public.fechamento_operadoras
  for select to authenticated
  using (exists (select 1 from public.fechamentos f where f.id = fechamento_id
                   and public.is_equipe_ativa() and (public.is_admin() or f.unidade_id = public.unidade_do_usuario())));
revoke insert, update, delete on public.fechamentos, public.fechamento_operadoras from authenticated, anon;

-- competência fechada?
create or replace function public.competencia_fechada(p_unidade uuid, p_data date)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.fechamentos f
                  where f.unidade_id = p_unidade and f.competencia = date_trunc('month', p_data)::date)
$$;
revoke execute on function public.competencia_fechada(uuid, date) from public, anon;
grant execute on function public.competencia_fechada(uuid, date) to authenticated, service_role;

-- as dez da auditoria (a mesma ordem da aba Meta: md5(id || competência))
create or replace function public.amostra_auditoria(p_unidade uuid, p_competencia date)
returns setof uuid language sql stable security definer set search_path = public, pg_temp as $$
  select p.id from public.pontos p
   where p.unidade_id = p_unidade and p.competencia = date_trunc('month', p_competencia)::date
   order by md5(p.id::text || date_trunc('month', p_competencia)::date::text)
   limit 10
$$;
revoke execute on function public.amostra_auditoria(uuid, date) from public, anon;
grant execute on function public.amostra_auditoria(uuid, date) to authenticated, service_role;

-- fechar o mês
create or replace function public.fechar_mes(
  p_unidade uuid, p_competencia date, p_auditoria jsonb, p_whatsapp_restrito boolean default false, p_observacoes text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_comp date; v_fim date; prm record; par record; v_fech uuid;
  v_carteira_pct integer; v_carteira_ok boolean; v_pend integer; v_renov integer;
  v_pontos_brutos integer; v_pontos_finais integer;
  v_total numeric(10,2); v_individual numeric(10,2); v_bolo numeric(10,2);
  v_n_bolo integer; a record; v_faltam integer;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then
    raise exception 'acesso negado: so o gestor da unidade ou o admin geral fecha o mes';
  end if;
  v_comp := date_trunc('month', p_competencia)::date;
  v_fim  := (v_comp + interval '1 month')::date;
  if v_fim > current_date then raise exception 'o mes ainda nao terminou'; end if;
  if public.competencia_fechada(p_unidade, v_comp) then raise exception 'competencia ja fechada'; end if;

  -- a auditoria precisa cobrir exatamente as dez sorteadas
  select count(*) into v_faltam
    from public.amostra_auditoria(p_unidade, v_comp) s
   where not exists (select 1 from jsonb_array_elements(coalesce(p_auditoria, '[]'::jsonb)) x
                      where (x->>'ponto_id')::uuid = s and (x->>'ok') is not null);
  if v_faltam > 0 then
    raise exception 'auditoria incompleta: % das afericoes sorteadas sem resposta', v_faltam;
  end if;

  select * into prm from public.parametros_pontos where id = 1;
  select * into par from public.parametros_premio(p_unidade, v_comp);

  -- carteira defendida (mesma conta da aba Meta)
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
    (p_unidade, v_comp, auth.uid(), coalesce(p_whatsapp_restrito, false), nullif(btrim(coalesce(p_observacoes,'')), ''),
     par.valor_ponto, par.teto_mes, coalesce(par.pct_bolo, 30), prm.piso_carteira_pct, prm.fator_carteira,
     v_carteira_pct, v_carteira_ok, 0, 0, coalesce(p_auditoria, '[]'::jsonb))
  returning id into v_fech;

  -- por operadora: pontos brutos, ajuste da carteira (conquistas × fator), anulação pela auditoria
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
           -- anula quem MARCOU (registrado_por) uma aferição reprovada; se a operadora do ponto
           -- for quem marcou, cai aqui
           exists (select 1 from jsonb_array_elements(coalesce(p_auditoria,'[]'::jsonb)) x
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

  -- a conta em reais (null = observação)
  if par.valor_ponto is null or coalesce(p_whatsapp_restrito, false) then
    v_total := case when coalesce(p_whatsapp_restrito, false) then 0 else null end;
    v_individual := v_total; v_bolo := case when v_total is null then null else 0 end;
  else
    v_total := least(v_pontos_finais * par.valor_ponto, coalesce(par.teto_mes, v_pontos_finais * par.valor_ponto));
    v_bolo := case when v_carteira_ok then round(v_total * coalesce(par.pct_bolo,30) / 100.0, 2) else 0 end;
    v_individual := round(v_total * (100 - coalesce(par.pct_bolo,30)) / 100.0, 2);
    -- sem bolo, o total pago é só a parte individual (a sobra não é de ninguém)
    if not v_carteira_ok then v_total := v_individual; end if;
  end if;

  -- reparte: individual proporcional aos pontos finais; bolo igual entre operadoras não anuladas
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
end $$;
revoke execute on function public.fechar_mes(uuid, date, jsonb, boolean, text) from public, anon;
grant execute on function public.fechar_mes(uuid, date, jsonb, boolean, text) to authenticated, service_role;

-- resumo de um fechamento (para a aba Meta e o Meu placar)
create or replace function public.resumo_fechamento(p_unidade uuid, p_competencia date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb; v_comp date;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or p_unidade = public.unidade_do_usuario()) then raise exception 'acesso negado'; end if;
  v_comp := date_trunc('month', p_competencia)::date;
  select jsonb_build_object(
    'id', f.id, 'competencia', f.competencia, 'fechado_em', f.fechado_em,
    'fechado_por', (select e.nome from public.equipe e where e.user_id = f.fechado_por),
    'whatsapp_restrito', f.whatsapp_restrito, 'observacoes', f.observacoes,
    'valor_ponto', f.valor_ponto, 'teto_mes', f.teto_mes, 'pct_bolo', f.pct_bolo,
    'carteira_pct', f.carteira_pct, 'carteira_ok', f.carteira_ok,
    'pontos_brutos', f.pontos_brutos, 'pontos_finais', f.pontos_finais,
    'total_pago', f.total_pago, 'individual_pago', f.individual_pago, 'bolo_pago', f.bolo_pago,
    'observacao_mes', f.valor_ponto is null,
    'auditoria', f.auditoria,
    'operadoras', coalesce((select jsonb_agg(to_jsonb(o) - 'fechamento_id' order by o.total desc nulls last, o.nome)
                             from public.fechamento_operadoras o where o.fechamento_id = f.id
                              and (public.is_admin() or public.is_admin_unidade() or o.operadora_id = auth.uid())), '[]'::jsonb)
  ) into v
  from public.fechamentos f where f.unidade_id = p_unidade and f.competencia = v_comp;
  return v;  -- null quando não há fechamento
end $$;
revoke execute on function public.resumo_fechamento(uuid, date) from public, anon;
grant execute on function public.resumo_fechamento(uuid, date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Mês fechado não muda: pontuar_afericao recusa competência fechada
-- ---------------------------------------------------------------------------
create or replace function public.pontuar_afericao(p_lead uuid, p_data date, p_ligacao uuid, p_posto_ant text, p_data_ant date)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  prm record;
  v_emp uuid; v_unidade uuid; v_situacao text; v_nossos_antes integer := 0;
  v_venc date; v_nosso boolean; v_classe text; v_pontos integer;
  v_bonus integer := 0; v_conq boolean := false;
  v_op uuid; v_contato uuid; v_contato_em timestamptz;
  v_ini timestamptz; v_fim timestamptz;
begin
  select * into prm from public.parametros_pontos where id = 1;

  select c.empresa_id, c.unidade_id into v_emp, v_unidade
    from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then return; end if;

  if public.competencia_fechada(v_unidade, p_data) then
    raise exception 'o mes de % ja esta fechado nesta unidade; a data da afericao nao pode cair em mes fechado',
      to_char(p_data, 'MM/YYYY');
  end if;

  if v_emp is not null then
    select e.situacao into v_situacao from public.empresas e where e.id = v_emp;
    select count(*) into v_nossos_antes
      from public.caminhoneiros x
     where x.empresa_id = v_emp and x.id <> p_lead
       and public.posto_do_grupo(x.posto_afericao);
  end if;

  v_venc  := (p_data_ant + interval '2 years')::date;
  v_nosso := public.posto_do_grupo(p_posto_ant);

  v_classe := case
    when v_situacao = 'contrato'                                         then 'contrato'
    when v_venc is not null
         and v_venc < p_data - prm.carencia_vencido_dias                 then 'vencido'
    when v_nosso                                                         then 'renovacao'
    when v_emp is null                                                   then 'conquista_avulso'
    when v_nossos_antes > 0                                              then 'conquista_mista'
    else                                                                      'conquista_virgem'
  end;

  v_pontos := case v_classe
    when 'contrato'         then prm.contrato
    when 'vencido'          then prm.vencido
    when 'renovacao'        then prm.renovacao
    when 'conquista_avulso' then prm.conquista_avulso
    when 'conquista_mista'  then prm.conquista_mista
    else                         prm.conquista_virgem
  end;

  if v_emp is not null
     and coalesce(v_situacao, '') <> 'contrato'
     and v_nossos_antes = 0
     and not v_nosso
     and not exists (select 1 from public.pontos p
                      where p.empresa_id = v_emp and p.empresa_conquistada) then
    v_conq  := true;
    v_bonus := prm.bonus_empresa;
  end if;

  v_ini := ((p_data - prm.janela_atribuicao_dias)::timestamp) at time zone 'America/Sao_Paulo';
  v_fim := ((p_data + 1)::timestamp) at time zone 'America/Sao_Paulo';

  select l.operador_id, l.id, l.created_at into v_op, v_contato, v_contato_em
    from public.ligacoes l
   where (l.caminhoneiro_id = p_lead or (v_emp is not null and l.empresa_id = v_emp))
     and l.canal in ('ligacao_ativa', 'ligacao_passiva', 'whatsapp')
     and l.resultado not in ('aferido', 'atualizacao')
     and l.operador_id is not null
     and l.created_at >= v_ini and l.created_at < v_fim
   order by l.created_at desc
   limit 1;

  insert into public.pontos
    (ligacao_id, caminhoneiro_id, empresa_id, unidade_id, data_afericao, competencia,
     classe, posto_anterior, venc_anterior, empresa_conquistada, pontos, bonus,
     operadora_id, contato_id, contato_em, registrado_por)
  values
    (p_ligacao, p_lead, v_emp, v_unidade, p_data, date_trunc('month', p_data)::date,
     v_classe, p_posto_ant, v_venc, v_conq, v_pontos, v_bonus,
     v_op, v_contato, v_contato_em, auth.uid())
  on conflict (ligacao_id) do nothing;
end $$;
