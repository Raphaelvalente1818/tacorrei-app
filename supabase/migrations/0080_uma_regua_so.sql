-- 0080 — Uma régua só: `base_trabalhavel()` define o que está na carteira, e todas as
--        contagens leem dela. E `conferencia_contagens()` prova que batem.
--
-- Contexto (11/09/2026). O Emerson viu "Vencidos 67" com a lista em 300 e, depois das
-- correções pontuais (0077–0079), disse: "fiquei preocupado com essas diferenças". Com
-- razão: a definição de "o que está na fila" estava copiada em seis funções, cada uma
-- escrita numa data, e nenhuma era comparada com as outras.
--
-- A régua: um caminhão é TRABALHÁVEL se tem tacógrafo, tem data de aferição e não venceu
-- há mais tempo que o piso da unidade (`unidades.piso_dias`, 365). Está NA FILA se, além
-- disso, não está sob contrato (autônomo ou empresa prospecto). Só isso, num lugar só.
--
-- Quem lê a régua: listar_leads (via fila_leads), contar_leads, meses_de_vencimento,
-- empresas_painel, unidades_painel, producao_unidades, montar_meta. Permissão (quem pode
-- ver qual lead) continua sendo pode_ler_lead — a régua diz o que EXISTE para trabalhar;
-- a permissão diz quem enxerga.
--
-- A conferência: conferencia_contagens() roda como o admin geral, chama as mesmas funções
-- que as telas chamam e compara: botão × lista, contador × lista, painéis × régua, Meta ×
-- régua. Retorna uma linha por checagem com ok = true/false. Roda-se depois de cada
-- migration que toque em contagem:   select * from public.conferencia_contagens();
-- Só o papel de leitura do Claude e o postgres podem chamá-la (ela assume a identidade
-- do admin para ler; por isso não é para o app). Primeira rodada, 11/09: 24 checagens, 24 ok.

-- ---------------------------------------------------------------------------
-- 1. A régua
-- ---------------------------------------------------------------------------
create or replace function public.base_trabalhavel(p_unidade uuid default null)
returns table (
  id uuid, unidade_id uuid, empresa_id uuid, empresa_situacao text, empresa_nome text,
  status text, posto_afericao text, posto_conhecido boolean, nosso boolean,
  data_ultima_afericao date, venc date, na_fila boolean
)
language sql stable as $$
  select c.id, c.unidade_id, c.empresa_id, e.situacao, e.nome,
         c.status, c.posto_afericao,
         (c.posto_afericao is not null),
         coalesce(public.posto_do_grupo(c.posto_afericao), false),
         c.data_ultima_afericao,
         (c.data_ultima_afericao + interval '2 years')::date,
         (c.empresa_id is null or e.situacao = 'prospecto')
  from public.caminhoneiros c
  left join public.empresas e on e.id = c.empresa_id
  where c.tem_tacografo
    and public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao)
    and (p_unidade is null or c.unidade_id = p_unidade)
$$;
-- security INVOKER e SEM "set search_path", de propósito: só assim o planejador inlina a
-- função, e quem a chama paga o custo de um select comum (com SET ela virou uma varredura
-- por linha e a fila deu timeout — 0080b, já incorporada aqui). Os nomes dentro são todos
-- qualificados com "public.".
revoke execute on function public.base_trabalhavel(uuid) from public, anon;
grant execute on function public.base_trabalhavel(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. A fila: fila_leads (pura) + listar_leads (registra o acesso e devolve)
-- ---------------------------------------------------------------------------
create or replace function public.fila_leads(
  p_pagina integer default 1, p_tamanho integer default 100, p_filtro text default 'todos',
  p_busca text default null, p_unidade uuid default null, p_mes text default null
) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_tam integer; v_ini integer; v_busca text; v_mes text; v_total bigint; v_linhas jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if p_tamanho is not null and p_tamanho > 100 then
    raise exception 'tamanho de pagina acima do permitido (maximo 100)';
  end if;

  v_tam := least(greatest(coalesce(p_tamanho,100),1),100);
  v_ini := greatest(coalesce(p_pagina,1)-1,0) * v_tam;
  v_busca := nullif(btrim(coalesce(p_busca,'')),'');
  v_mes := nullif(btrim(coalesce(p_mes,'')),'');

  with visiveis as (
    select c.*, e.nome as empresa_nome, e.situacao as empresa_situacao
    from public.caminhoneiros c
    left join public.empresas e on e.id = c.empresa_id
    where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      -- some da fila só quem está sob contrato; prospecto continua aparecendo
      and (c.empresa_id is null or e.situacao = 'prospecto')
      and (p_unidade is null or c.unidade_id = p_unidade)
      and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
      -- a régua (o mesmo predicado de base_trabalhavel, chamado direto — por linha, um
      -- "exists" na função custava uma varredura); a busca passa por cima
      and (v_busca is not null or c.tem_tacografo = false
           or public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao))
      and (v_mes is null
           or (v_mes = 'vencidos'
               and (c.data_ultima_afericao + interval '2 years')::date < date_trunc('month', current_date)::date)
           or to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') = v_mes)
      and (v_busca is null
           or c.nome ilike '%'||v_busca||'%' or c.telefone ilike '%'||v_busca||'%'
           or c.cidade ilike '%'||v_busca||'%' or c.placa_veiculo ilike '%'||v_busca||'%'
           or e.nome ilike '%'||v_busca||'%')
  )
  select (select count(*) from visiveis),
         coalesce((select jsonb_agg(to_jsonb(p) order by p.data_ultima_afericao asc nulls last, p.id)
                   from (select * from visiveis order by data_ultima_afericao asc nulls last, id
                         offset v_ini limit v_tam) p), '[]'::jsonb)
  into v_total, v_linhas;

  return jsonb_build_object('total', v_total, 'leads', v_linhas);
end $$;
revoke execute on function public.fila_leads(integer, integer, text, text, uuid, text) from public, anon;
grant execute on function public.fila_leads(integer, integer, text, text, uuid, text) to authenticated, service_role;

create or replace function public.listar_leads(
  p_pagina integer default 1, p_tamanho integer default 100, p_filtro text default 'todos',
  p_busca text default null, p_unidade uuid default null, p_mes text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  v := public.fila_leads(p_pagina, p_tamanho, p_filtro, p_busca, p_unidade, p_mes);
  perform public.registrar_acesso('listar', jsonb_array_length(v->'leads'),
    jsonb_build_object('filtro',p_filtro,'busca',nullif(btrim(coalesce(p_busca,'')),''),
                       'mes',nullif(btrim(coalesce(p_mes,'')),''),
                       'pagina',coalesce(p_pagina,1),'unidade',p_unidade));
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Contadores da fila
-- ---------------------------------------------------------------------------
create or replace function public.contar_leads(p_unidade uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select jsonb_build_object(
    'total',            count(*),
    'novo',             count(*) filter (where b.status = 'novo'),
    'mensagem_enviada', count(*) filter (where b.status = 'mensagem_enviada'),
    'contatado',        count(*) filter (where b.status = 'contatado'),
    'agendado',         count(*) filter (where b.status = 'agendado'),
    'aferido',          count(*) filter (where b.status = 'aferido')
  ) into v
  from public.base_trabalhavel(p_unidade) b
  where b.na_fila
    and (public.pode_ler_lead(b.unidade_id, true, b.data_ultima_afericao)
         or (b.status = 'aferido' and b.unidade_id = public.unidade_do_usuario()));
  return v;
end $$;

create or replace function public.meses_de_vencimento(p_unidade uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select coalesce(jsonb_agg(x order by x.mes), '[]'::jsonb) into v
  from (
    select to_char(b.venc,'YYYY-MM') as mes,
           count(*) as total, count(*) filter (where b.status = 'novo') as novos
    from public.base_trabalhavel(p_unidade) b
    where b.na_fila
      and public.pode_ler_lead(b.unidade_id, true, b.data_ultima_afericao)
    group by 1) x;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Aba Empresas
-- ---------------------------------------------------------------------------
create or replace function public.empresas_painel(p_unidade uuid default null, p_competencia date default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb; v_comp date;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_comp := coalesce(p_competencia, date_trunc('month', current_date + interval '1 month')::date);

  select coalesce(jsonb_agg(to_jsonb(y) order by y.vencendo desc, y.nome), '[]'::jsonb) into v
  from (
    select g.*,
           case when g.situacao = 'contrato' then 'contrato'
                when g.nossos > 0            then 'mista'
                when g.a_conquistar > 0      then 'virgem'
                else 'sem_dados' end as classe
    from (
      select e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao,
             v_comp as competencia,
             count(b.id) as veiculos,
             count(b.id) filter (where b.nosso) as nossos,
             count(b.id) filter (where b.posto_conhecido and not b.nosso) as a_conquistar,
             count(b.id) filter (where date_trunc('month', b.venc)::date = v_comp) as vencendo,
             count(b.id) filter (where b.venc < current_date) as vencidos,
             -- o gatilho da ligacao: caminhao do concorrente que vence agora
             count(b.id) filter (
               where b.posto_conhecido and not b.nosso
                 and b.venc between current_date and current_date + 90
             ) as janela,
             -- a defesa: caminhao NOSSO vencendo (ou vencido ha pouco)
             count(b.id) filter (
               where b.nosso and b.venc between current_date - 30 and current_date + 90
             ) as risco,
             (select a.enviado_em from public.avisos_empresa a
               where a.empresa_id = e.id and a.competencia = v_comp) as avisada_em,
             greatest(
               (select max(x.data_ultimo_whatsapp) from public.caminhoneiros x where x.empresa_id = e.id),
               (select max(l.created_at) from public.ligacoes l where l.empresa_id = e.id),
               (select max(l.created_at) from public.ligacoes l
                 join public.caminhoneiros x on x.id = l.caminhoneiro_id
                where x.empresa_id = e.id)
             ) as ultima_abordagem
      from public.empresas e
      left join public.base_trabalhavel(e.unidade_id) b on b.empresa_id = e.id
      where e.ativo
        and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())
        and (p_unidade is null or e.unidade_id = p_unidade)
      group by e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao
    ) g
  ) y;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Painéis do admin
-- ---------------------------------------------------------------------------
create or replace function public.unidades_painel()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_res jsonb;
begin
  if not (public.is_admin() or public.is_admin_unidade()) then
    raise exception 'acesso negado';
  end if;
  select coalesce(jsonb_agg(x order by x.carteira desc, x.nome), '[]'::jsonb) into v_res
  from (
    select
      u.id, u.nome, u.janela_dias,
      (select string_agg(uc.cidade, ' · ' order by uc.cidade)
         from public.unidade_cidades uc where uc.unidade_id = u.id) as cidades,
      (select count(*) from public.base_trabalhavel(u.id) b) as carteira,
      (select count(*) from public.base_trabalhavel(u.id) b
        where u.janela_dias is null or b.venc <= current_date + u.janela_dias) as fila,
      (select count(*) from public.base_trabalhavel(u.id) b
         join public.caminhoneiros c on c.id = b.id
        where c.data_ultimo_whatsapp is not null) as abordados,
      (select count(*) from public.caminhoneiros c
        where c.unidade_id = u.id and c.status = 'aferido') as aferidos
    from public.unidades u
    where public.is_admin() or u.id = public.unidade_do_usuario()
  ) x;
  return v_res;
end $$;

create or replace function public.producao_unidades(p_dias integer default null)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  from (
    select
      u.id, u.nome,
      (select count(*) from public.base_trabalhavel(u.id) b) as leads,
      (select count(*) from public.caminhoneiros c where c.unidade_id = u.id and c.tem_tacografo and c.status = 'aferido') as aferidos,
      (select count(*) from public.caminhoneiros c where c.unidade_id = u.id and c.tem_tacografo and c.status = 'agendado') as agendados_total,
      (select count(*) from public.ligacoes l where l.unidade_id = u.id
         and (p_dias is null or l.created_at >= now() - (p_dias || ' days')::interval)) as contatos,
      (select count(*) from public.ligacoes l where l.unidade_id = u.id and l.canal = 'whatsapp'
         and (p_dias is null or l.created_at >= now() - (p_dias || ' days')::interval)) as whatsapp,
      (select count(*) from public.agendamentos a where a.unidade_id = u.id
         and (p_dias is null or a.created_at >= now() - (p_dias || ' days')::interval)) as agendados
    from public.unidades u
    where is_admin()
    order by u.nome
  ) t;
$$;

-- ---------------------------------------------------------------------------
-- 6. Meta: universo, carteira e risco lidos da régua. (realizado/detalhe/auditoria
--    vêm da tabela pontos e não mudam)
-- ---------------------------------------------------------------------------
create or replace function public.montar_meta(p_unidade uuid, p_competencia date, p_operadora uuid, p_com_auditoria boolean)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_comp date; v_ini date; v_fim date; prm record;
  v_universo jsonb; v_realizado jsonb; v_detalhe jsonb; v_carteira jsonb;
  v_risco jsonb; v_auditoria jsonb; v_unidade jsonb; v_total_unidade jsonb;
  v_pend integer; v_renov integer; v_frios integer;
begin
  v_comp := date_trunc('month', coalesce(p_competencia, current_date))::date;
  v_ini  := v_comp;
  v_fim  := (v_comp + interval '1 month')::date;
  select * into prm from public.parametros_pontos where id = 1;
  select jsonb_build_object('id', u.id, 'nome', u.nome, 'posto', u.posto_afericao)
    into v_unidade from public.unidades u where u.id = p_unidade;

  -- fora da régua, só para informação: vencidos além do piso (não são fila de ninguém)
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

-- ---------------------------------------------------------------------------
-- 7. A conferência
-- ---------------------------------------------------------------------------
create or replace function public.conferencia_contagens()
returns table (unidade text, checagem text, a bigint, b bigint, ok boolean)
language plpgsql security definer set search_path = public, pg_temp as $$
declare u record; v_admin uuid; v_mes text; m record; v_comp date;
begin
  select e.user_id into v_admin from public.equipe e
   where e.papel = 'admin' and e.ativo and e.unidade_id is null order by e.nome limit 1;
  if v_admin is null then raise exception 'sem admin geral para a conferencia'; end if;
  -- assume a identidade do admin geral só dentro desta transação
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_mes := to_char(current_date, 'YYYY-MM');
  v_comp := date_trunc('month', current_date)::date;

  for u in select id, nome from public.unidades order by nome loop
    -- botão Vencidos (soma dos meses anteriores) × lista com m=vencidos
    unidade := u.nome; checagem := 'botao Vencidos = lista Vencidos';
    select coalesce(sum((x->>'total')::bigint), 0) into a
      from jsonb_array_elements(public.meses_de_vencimento(u.id)) x where (x->>'mes') < v_mes;
    b := (public.fila_leads(1, 1, 'todos', null, u.id, 'vencidos')->>'total')::bigint;
    ok := a = b; return next;

    -- cada botão de mês (os 3 primeiros à frente) × lista daquele mês
    for m in select (x->>'mes') mes, (x->>'total')::bigint total
               from jsonb_array_elements(public.meses_de_vencimento(u.id)) x
              where (x->>'mes') >= v_mes order by 1 limit 3 loop
      checagem := 'botao ' || m.mes || ' = lista ' || m.mes;
      a := m.total;
      b := (public.fila_leads(1, 1, 'todos', null, u.id, m.mes)->>'total')::bigint;
      ok := a = b; return next;
    end loop;

    -- contador "Todos" × lista sem filtro
    checagem := 'contar_leads.total = lista Todos';
    a := (public.contar_leads(u.id)->>'total')::bigint;
    b := (public.fila_leads(1, 1, 'todos', null, u.id, null)->>'total')::bigint;
    ok := a = b; return next;

    -- soma dos meses × lista sem filtro (os botões cobrem a lista inteira?)
    checagem := 'soma dos botoes = lista Todos';
    select coalesce(sum((x->>'total')::bigint), 0) into a
      from jsonb_array_elements(public.meses_de_vencimento(u.id)) x;
    ok := a = b; return next;

    -- aba Empresas: soma de "Veículos" × régua (veículos de empresa)
    checagem := 'Empresas.veiculos = regua (com empresa)';
    select coalesce(sum((x->>'veiculos')::bigint), 0) into a
      from jsonb_array_elements(public.empresas_painel(u.id, null)) x;
    select count(*) into b from public.base_trabalhavel(u.id) t
      join public.empresas e on e.id = t.empresa_id where e.ativo;
    ok := a = b; return next;

    -- aba Empresas: soma de "vencidos" × régua
    checagem := 'Empresas.vencidos = regua (com empresa, vencidos)';
    select coalesce(sum((x->>'vencidos')::bigint), 0) into a
      from jsonb_array_elements(public.empresas_painel(u.id, null)) x;
    select count(*) into b from public.base_trabalhavel(u.id) t
      join public.empresas e on e.id = t.empresa_id where e.ativo and t.venc < current_date;
    ok := a = b; return next;

    -- aba Unidades: carteira × régua
    checagem := 'Unidades.carteira = regua';
    select (x->>'carteira')::bigint into a
      from jsonb_array_elements(public.unidades_painel()) x where (x->>'id')::uuid = u.id;
    select count(*) into b from public.base_trabalhavel(u.id);
    ok := a = b; return next;

    -- Produção: leads × régua
    checagem := 'Producao.leads = regua';
    select (x->>'leads')::bigint into a
      from jsonb_array_elements(public.producao_unidades(null)) x where (x->>'id')::uuid = u.id;
    ok := a = b; return next;

    -- Meta: vencidos recuperáveis × régua (concorrente, posto conhecido, vencido)
    checagem := 'Meta.vencidos_recuperaveis = regua';
    a := ((public.meta_do_mes(u.id, v_comp))->'universo'->>'vencidos_recuperaveis')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t
      where t.posto_conhecido and not t.nosso and t.venc < current_date;
    ok := a = b; return next;

    -- Meta: total que vence no mês × régua
    checagem := 'Meta.vencem_no_mes.total = regua';
    a := ((public.meta_do_mes(u.id, v_comp))->'universo'->'vencem_no_mes'->>'total')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t
      where t.posto_conhecido and t.venc >= v_comp and t.venc < (v_comp + interval '1 month')::date;
    ok := a = b; return next;
  end loop;
end $$;
revoke execute on function public.conferencia_contagens() from public, anon, authenticated;
grant execute on function public.conferencia_contagens() to supabase_read_only_user, service_role;
