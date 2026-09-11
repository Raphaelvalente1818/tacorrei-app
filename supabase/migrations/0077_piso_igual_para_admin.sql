-- 0077 — O piso da fila (12 meses) passa a valer para o admin também
--
-- Contexto (11/09/2026). Desde a 0028 (24/08) a operadora só vê vencido até
-- `unidades.piso_dias` (365) — o admin via tudo, inclusive 918 placas vencidas entre 2009 e
-- 2022. O Rapha, olhando a tela de admin, pediu "só vencidos de 01/09/2024 para cima"; a
-- análise mostrou que o público antigo responde 2% contra 7–8% do vencido recente, e que o
-- piso já existia para quem liga. Decisão do Emerson: fica 12 meses, e a visão do admin
-- passa a ser a mesma da operadora — o que se LISTA e CONTA respeita o piso da unidade.
--
-- O que NÃO muda: nada é apagado; a permissão de leitura (pode_ler_lead) do admin continua
-- total, então a busca por placa acha o caminhão antigo quando ele aparece na porta; a
-- lista de veículos da frota continua completa, com a marca `antigo` para o gestor da
-- frota poder dizer "esse eu vendi". Se um dia o piso mudar (24 meses), é um número em
-- `unidades.piso_dias` — vale para todo mundo ao mesmo tempo.

create or replace function public.piso_da_unidade(p_unidade uuid)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select u.piso_dias from public.unidades u where u.id = p_unidade), 365);
$$;
revoke execute on function public.piso_da_unidade(uuid) from public, anon;
grant execute on function public.piso_da_unidade(uuid) to authenticated, service_role;

-- "Trabalhável" = tem data e não venceu há mais tempo que o piso da unidade.
-- (o teto — quem vence daqui a mais de 45 dias — continua sendo só da operadora, via
-- pode_ler_lead: o admin precisa ver o que vence mês que vem para planejar)
create or replace function public.lead_trabalhavel(p_unidade uuid, p_data date)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_data is not null
     and (p_data + interval '2 years')::date >= current_date - public.piso_da_unidade(p_unidade);
$$;
revoke execute on function public.lead_trabalhavel(uuid, date) from public, anon;
grant execute on function public.lead_trabalhavel(uuid, date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Fila de leads: a busca (nome, placa, telefone, cidade, empresa) ignora o piso — é
-- por ela que se acha o caminhão antigo quando ele chega. Sem busca, o piso vale.
-- ---------------------------------------------------------------------------
create or replace function public.listar_leads(
  p_pagina integer default 1, p_tamanho integer default 100, p_filtro text default 'todos',
  p_busca text default null, p_unidade uuid default null, p_mes text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
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
      -- piso da unidade, igual para admin e operadora; a busca passa por cima
      and (v_busca is not null or c.tem_tacografo = false
           or public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao))
      and (v_mes is null
           or (v_mes = 'vencidos' and (c.data_ultima_afericao + interval '2 years')::date < current_date)
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

  perform public.registrar_acesso('listar', jsonb_array_length(v_linhas),
    jsonb_build_object('filtro',p_filtro,'busca',v_busca,'mes',v_mes,
                       'pagina',coalesce(p_pagina,1),'unidade',p_unidade));

  return jsonb_build_object('total', v_total, 'leads', v_linhas);
end $$;

create or replace function public.contar_leads(p_unidade uuid default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select jsonb_build_object(
    'total',            count(*),
    'novo',             count(*) filter (where status = 'novo'),
    'mensagem_enviada', count(*) filter (where status = 'mensagem_enviada'),
    'contatado',        count(*) filter (where status = 'contatado'),
    'agendado',         count(*) filter (where status = 'agendado'),
    'aferido',          count(*) filter (where status = 'aferido')
  ) into v
  from public.caminhoneiros c
  where c.tem_tacografo = true
    and (
      public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      or (c.status = 'aferido' and c.unidade_id = public.unidade_do_usuario())
    )
    and public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao)
    and (p_unidade is null or c.unidade_id = p_unidade);

  return v;
end $$;

create or replace function public.meses_de_vencimento(p_unidade uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select coalesce(jsonb_agg(x order by x.mes), '[]'::jsonb) into v
  from (
    select to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') as mes,
           count(*) as total, count(*) filter (where c.status = 'novo') as novos
    from public.caminhoneiros c
    where c.tem_tacografo and c.data_ultima_afericao is not null and c.empresa_id is null
      and public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      and public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao)
      and (p_unidade is null or c.unidade_id = p_unidade)
    group by 1) x;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Aba Empresas: "Veículos", "nossos", "a conquistar" e "vencidos" contam só o trabalhável.
-- (janela e risco já eram por natureza recentes — ficam iguais)
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

             count(c.id) filter (where c.tem_tacografo and t.ok) as veiculos,

             count(c.id) filter (
               where c.tem_tacografo and t.ok and public.posto_do_grupo(c.posto_afericao)
             ) as nossos,

             count(c.id) filter (
               where c.tem_tacografo and t.ok and c.posto_afericao is not null
                 and not public.posto_do_grupo(c.posto_afericao)
             ) as a_conquistar,

             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and date_trunc('month', (c.data_ultima_afericao + interval '2 years'))::date = v_comp
             ) as vencendo,

             count(c.id) filter (
               where c.tem_tacografo and t.ok
                 and (c.data_ultima_afericao + interval '2 years')::date < current_date
             ) as vencidos,

             -- o gatilho da ligacao: caminhao do concorrente que vence agora
             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and c.posto_afericao is not null
                 and not public.posto_do_grupo(c.posto_afericao)
                 and (c.data_ultima_afericao + interval '2 years')::date
                     between current_date and current_date + 90
             ) as janela,

             -- a defesa: caminhao NOSSO vencendo (ou vencido ha pouco)
             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and public.posto_do_grupo(c.posto_afericao)
                 and (c.data_ultima_afericao + interval '2 years')::date
                     between current_date - 30 and current_date + 90
             ) as risco,

             (select a.enviado_em from public.avisos_empresa a
               where a.empresa_id = e.id and a.competencia = v_comp) as avisada_em,

             greatest(
               max(c.data_ultimo_whatsapp),
               (select max(l.created_at) from public.ligacoes l where l.empresa_id = e.id),
               (select max(l.created_at) from public.ligacoes l
                 join public.caminhoneiros x on x.id = l.caminhoneiro_id
                where x.empresa_id = e.id)
             ) as ultima_abordagem

      from public.empresas e
      left join public.caminhoneiros c on c.empresa_id = e.id
      left join lateral (select public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao) as ok) t on true
      where e.ativo
        and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())
        and (p_unidade is null or e.unidade_id = p_unidade)
      group by e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao
    ) g
  ) y;

  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Lista de veículos da frota: continua completa, com a marca `antigo`.
-- ---------------------------------------------------------------------------
create or replace function public.frota_da_empresa(p_empresa uuid, p_busca text default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb; v_unidade uuid; v_busca text; v_placa text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select e.unidade_id into v_unidade from public.empresas e where e.id = p_empresa;
  if v_unidade is null then raise exception 'empresa nao encontrada'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_busca := nullif(btrim(coalesce(p_busca,'')),'');
  v_placa := case when v_busca is not null
                  then public.mercosul(public.normaliza_placa(v_busca)) end;

  select coalesce(jsonb_agg(x order by x.antigo, x.venc nulls last, x.numero_empresa), '[]'::jsonb) into v
  from (
    select c.id, c.placa_veiculo as placa, c.numero_empresa, c.modelo_veiculo as modelo,
           c.observacoes, c.data_ultima_afericao,
           (c.data_ultima_afericao + interval '2 years')::date as venc,
           (c.data_ultima_afericao is not null
            and not public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao)) as antigo
    from public.caminhoneiros c
    where c.empresa_id = p_empresa
      and (v_busca is null
           or c.placa_veiculo ilike '%'||v_busca||'%'
           or c.numero_empresa ilike '%'||v_busca||'%'
           or c.observacoes ilike '%'||v_busca||'%'
           or public.mercosul(public.normaliza_placa(c.placa_veiculo)) = v_placa)
  ) x;

  perform public.registrar_acesso('listar', jsonb_array_length(v),
    jsonb_build_object('frota', p_empresa, 'busca', v_busca));
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Painéis do admin: carteira, fila e abordados só do trabalhável.
-- ---------------------------------------------------------------------------
create or replace function public.unidades_painel()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
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
      count(c.id) filter (where c.tem_tacografo and t.ok) as carteira,
      count(c.id) filter (
        where c.tem_tacografo and t.ok
          and (u.janela_dias is null
               or (c.data_ultima_afericao + interval '2 years')::date <= current_date + u.janela_dias)
      ) as fila,
      count(c.id) filter (where c.tem_tacografo and t.ok and c.data_ultimo_whatsapp is not null) as abordados,
      count(c.id) filter (where c.status = 'aferido') as aferidos
    from public.unidades u
    left join public.caminhoneiros c on c.unidade_id = u.id
    left join lateral (select public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao) as ok) t on true
    where public.is_admin() or u.id = public.unidade_do_usuario()
    group by u.id, u.nome, u.janela_dias
  ) x;
  return v_res;
end $$;

create or replace function public.producao_unidades(p_dias integer default null)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  from (
    select
      u.id, u.nome,
      (select count(*) from public.caminhoneiros c where c.unidade_id = u.id and c.tem_tacografo
         and public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao)) as leads,
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
