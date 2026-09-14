-- 0096 — a régua do gestor: a unidade vê o que está em jogo agora, não a base inteira.
--        (e, de quebra, a fila deixa de levar 8 segundos)
--
-- 1) ALCANCE. Medido em 14/09/2026, São Bernardo:
--      operadora (papel operador)      →   817 fichas, set/25 a out/26
--      gestor    (papel admin_unidade) → 4.595 fichas, set/25 a set/28
--    A operadora nunca teve esse alcance: o pode_ler_lead já a limitava a
--    janela_dias (45). O gestor não tinha janela nenhuma — lia a unidade toda.
--
-- 2) VELOCIDADE. A mesma contagem, com os mesmos 902 resultados:
--      com pode_ler_lead chamado por linha ....... 7.524 ms
--      com a régua resolvida uma vez, em coluna ..     7 ms
--    É a Lição 19 cobrando juros: pode_ler_lead é SECURITY DEFINER com
--    search_path fixo, logo não é inlined; e dentro dele há outras seis funções
--    iguais. São ~14 mil linhas × sete consultas, a cada tela.
--
-- A régua nova do gestor tem duas perguntas, e o lead só aparece se as duas passam:
--   1) a FROTA está em jogo — tem algum caminhão vencendo entre o piso e a
--      janela do gestor (padrão 60 dias). Autônomo responde por si mesmo.
--   2) ESTE caminhão cabe na conversa — vence dentro do horizonte de
--      agrupamento do gestor (padrão 365 dias).
--
-- Por que a frota inteira e não só a placa que vence: a operadora liga uma vez
-- e resolve a frota. Liberar só quem vence faria a lista de veículos mentir na
-- ficha e a unidade trabalhar pior.
--
-- Por que o teto de 365 dias: sem ele, um irmão de placa vencendo em novembro
-- abriria fichas de 2028. Medido antes de escrever — eram 683 fichas com mais
-- de um ano de horizonte, a mais distante em set/2028.
--
-- Nada muda para a operadora nem para o admin geral. Conferido no ensaio:
-- operadora 817 antes e depois, 14 meses, último out/26.
--
-- Como foi feito: a régua do usuário passa a ser resolvida UMA vez por chamada
-- (regua_do_usuario) e vira comparação de coluna dentro de fila_leads,
-- contar_leads e meses_de_vencimento. A pergunta da frota também é resolvida
-- uma vez, como conjunto (frotas_em_jogo), não por linha. pode_ler_lead
-- continua sendo a política de leitura da tabela e o caminho de UMA ficha
-- (obter_lead), onde custar uma consulta não tem importância.

alter table public.unidades
  add column if not exists janela_gestor_dias integer not null default 60,
  add column if not exists agrupamento_gestor_dias integer not null default 365;

comment on column public.unidades.janela_gestor_dias is
  'Quantos dias a frente o gestor da unidade enxerga. Uma frota entra na vista dele quando tem algum caminhao vencendo nesse prazo.';
comment on column public.unidades.agrupamento_gestor_dias is
  'Ate onde vai o caminhao que entra de carona na frota. Alem disso a placa nao aparece para o gestor, mesmo que um irmao dela venca amanha.';

create or replace function public.janela_gestor_do_usuario()
returns integer
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select u.janela_gestor_dias
  from public.equipe e join public.unidades u on u.id = e.unidade_id
  where e.user_id = auth.uid() and e.ativo = true
  limit 1;
$$;

create or replace function public.agrupamento_gestor_do_usuario()
returns integer
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select u.agrupamento_gestor_dias
  from public.equipe e join public.unidades u on u.id = e.unidade_id
  where e.user_id = auth.uid() and e.ativo = true
  limit 1;
$$;

-- A régua de quem está pedindo, em datas prontas. Uma chamada por consulta.
-- chao/teto nulos = sem limite daquele lado. teto_frota só existe para gestor.
create or replace function public.regua_do_usuario()
returns table(admin boolean, gestor boolean, unidade uuid,
              chao date, teto date, teto_frota date)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select
    public.is_admin(),
    public.is_admin_unidade(),
    public.unidade_do_usuario(),
    case when public.is_admin() then null
         when public.is_admin_unidade()
           then current_date - coalesce(public.piso_do_usuario(), 365)
         when public.janela_do_usuario() is null then null
         else current_date - coalesce(public.piso_do_usuario(), 365) end,
    case when public.is_admin() then null
         when public.is_admin_unidade()
           then current_date + coalesce(public.agrupamento_gestor_do_usuario(), 365)
         when public.janela_do_usuario() is null then null
         else current_date + public.janela_do_usuario() end,
    case when public.is_admin() then null
         when public.is_admin_unidade()
           then current_date + coalesce(public.janela_gestor_do_usuario(), 60)
         else null end;
$$;

revoke all on function public.janela_gestor_do_usuario() from public, anon;
revoke all on function public.agrupamento_gestor_do_usuario() from public, anon;
revoke all on function public.regua_do_usuario() from public, anon;
grant execute on function public.janela_gestor_do_usuario() to authenticated, service_role;
grant execute on function public.agrupamento_gestor_do_usuario() to authenticated, service_role;
grant execute on function public.regua_do_usuario() to authenticated, service_role;

-- pode_ler_lead ganha um quarto argumento: a frota do lead. Default null, então
-- quem chamar com três continua funcionando — e se comporta como autônomo, que
-- é o lado seguro.
drop policy if exists "caminhoneiros: le unidade" on public.caminhoneiros;
drop function if exists public.pode_ler_lead(uuid, boolean, date);

create or replace function public.pode_ler_lead(
  p_unidade_id uuid,
  p_tem_tacografo boolean,
  p_data_afericao date,
  p_empresa_id uuid default null)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select public.is_equipe_ativa() and (
    public.is_admin()
    or (
      p_unidade_id = public.unidade_do_usuario()
      and p_tem_tacografo = true
      and p_data_afericao is not null
      and case
        -- ---- gestor da unidade ----
        when public.is_admin_unidade() then
          (p_data_afericao + interval '2 years')::date
            >= current_date - coalesce(public.piso_do_usuario(), 365)
          and (p_data_afericao + interval '2 years')::date
            <= current_date + coalesce(public.agrupamento_gestor_do_usuario(), 365)
          and case
            when p_empresa_id is null then
              (p_data_afericao + interval '2 years')::date
                <= current_date + coalesce(public.janela_gestor_do_usuario(), 60)
            else exists (
              select 1
                from public.caminhoneiros f
               where f.empresa_id = p_empresa_id
                 and f.tem_tacografo
                 and f.data_ultima_afericao is not null
                 and (f.data_ultima_afericao + interval '2 years')::date
                     between current_date - coalesce(public.piso_do_usuario(), 365)
                         and current_date + coalesce(public.janela_gestor_do_usuario(), 60))
          end
        -- ---- operadora: exatamente como era antes ----
        else
          public.janela_do_usuario() is null
          or ( (p_data_afericao + interval '2 years')::date
                 <= current_date + public.janela_do_usuario()
           and (p_data_afericao + interval '2 years')::date
                 >= current_date - coalesce(public.piso_do_usuario(), 365) )
      end
    )
  );
$$;

revoke all on function public.pode_ler_lead(uuid, boolean, date, uuid) from public, anon;
grant execute on function public.pode_ler_lead(uuid, boolean, date, uuid) to authenticated, service_role;

create policy "caminhoneiros: le unidade" on public.caminhoneiros
  for select
  using (public.pode_ler_lead(unidade_id, tem_tacografo, data_ultima_afericao, empresa_id));

create or replace function public.fila_leads(
  p_pagina integer default 1, p_tamanho integer default 100,
  p_filtro text default 'todos', p_busca text default null,
  p_unidade uuid default null, p_mes text default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tam integer; v_ini integer; v_busca text; v_mes text;
  v_total bigint; v_linhas jsonb; v_r record;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if p_tamanho is not null and p_tamanho > 100 then
    raise exception 'tamanho de pagina acima do permitido (maximo 100)';
  end if;

  v_tam := least(greatest(coalesce(p_tamanho,100),1),100);
  v_ini := greatest(coalesce(p_pagina,1)-1,0) * v_tam;
  v_busca := nullif(btrim(coalesce(p_busca,'')),'');
  v_mes := nullif(btrim(coalesce(p_mes,'')),'');

  -- a régua de quem pediu, uma vez só
  select * into v_r from public.regua_do_usuario();

  with frotas as (
    -- as frotas em jogo agora. Só existe quando quem pede é o gestor;
    -- para os outros papéis a consulta devolve zero linhas na hora.
    select distinct f.empresa_id
      from public.caminhoneiros f
     where v_r.gestor
       and f.empresa_id is not null
       and f.unidade_id = v_r.unidade
       and f.tem_tacografo
       and f.data_ultima_afericao is not null
       and (f.data_ultima_afericao + interval '2 years')::date
           between v_r.chao and v_r.teto_frota
  ),
  visiveis as (
    select c.*, e.nome as empresa_nome, e.situacao as empresa_situacao,
           public.posto_do_grupo(c.posto_afericao, c.unidade_id) as nosso,
           greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                    coalesce(e.fone_cls, 0)) as fone
      from public.caminhoneiros c
      left join public.empresas e on e.id = c.empresa_id
     -- a régua, em coluna (era pode_ler_lead por linha)
     where ( v_r.admin
             or ( c.unidade_id = v_r.unidade
              and c.tem_tacografo = true
              and c.data_ultima_afericao is not null
              and (v_r.chao is null
                   or (c.data_ultima_afericao + interval '2 years')::date >= v_r.chao)
              and (v_r.teto is null
                   or (c.data_ultima_afericao + interval '2 years')::date <= v_r.teto)
              and ( not v_r.gestor
                    or case when c.empresa_id is null
                         then (c.data_ultima_afericao + interval '2 years')::date <= v_r.teto_frota
                         else c.empresa_id in (select empresa_id from frotas) end ) ) )
       and (c.empresa_id is null or e.situacao = 'prospecto')
       and (p_unidade is null or c.unidade_id = p_unidade)
       and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                 when p_filtro in ('sem_telefone','fora_de_area') then c.tem_tacografo = true
                 else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
       and (v_busca is not null or c.tem_tacografo = false
            or public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao))
       -- os três baldes; a busca passa por cima de todos
       and (v_busca is not null
            or p_filtro = 'sem_tacografo'
            or (case
                  when p_filtro = 'fora_de_area' then c.fora_de_area_em is not null
                  when p_filtro = 'sem_telefone' then c.fora_de_area_em is null
                       and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                    coalesce(e.fone_cls,0)) = 0
                  else c.fora_de_area_em is null
                       and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                    coalesce(e.fone_cls,0)) > 0
                end))
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
         coalesce((select jsonb_agg(to_jsonb(p) order by p.fone desc, p.data_ultima_afericao asc nulls last, p.id)
                   from (select * from visiveis
                          order by fone desc, data_ultima_afericao asc nulls last, id
                          offset v_ini limit v_tam) p), '[]'::jsonb)
  into v_total, v_linhas;

  return jsonb_build_object('total', v_total, 'leads', v_linhas);
end $function$;

create or replace function public.contar_leads(p_unidade uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_r record;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select * into v_r from public.regua_do_usuario();

  with frotas as (
    select distinct f.empresa_id
      from public.caminhoneiros f
     where v_r.gestor
       and f.empresa_id is not null
       and f.unidade_id = v_r.unidade
       and f.tem_tacografo
       and f.data_ultima_afericao is not null
       and (f.data_ultima_afericao + interval '2 years')::date
           between v_r.chao and v_r.teto_frota
  ),
  b as (
    select b.status, b.unidade_id, b.data_ultima_afericao, b.empresa_id,
           c.fora_de_area_em is not null as fora,
           greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                    coalesce(e.fone_cls, 0)) > 0 as tem_fone,
           c.fora_de_area_em is null
             and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                          coalesce(e.fone_cls, 0)) > 0 as trabalhavel
      from public.base_trabalhavel(p_unidade) b
      join public.caminhoneiros c on c.id = b.id
      left join public.empresas e on e.id = b.empresa_id
     where b.na_fila
  )
  select jsonb_build_object(
    'total',            count(*) filter (where trabalhavel),
    'novo',             count(*) filter (where trabalhavel and b.status = 'novo'),
    'mensagem_enviada', count(*) filter (where trabalhavel and b.status = 'mensagem_enviada'),
    'contatado',        count(*) filter (where trabalhavel and b.status = 'contatado'),
    'agendado',         count(*) filter (where trabalhavel and b.status = 'agendado'),
    'aferido',          count(*) filter (where trabalhavel and b.status = 'aferido'),
    -- fora do total: são os buracos, não a fila
    'sem_telefone',     count(*) filter (where not fora and not tem_fone),
    'fora_de_area',     count(*) filter (where fora)
  ) into v
  from b
  where ( v_r.admin
          or ( b.unidade_id = v_r.unidade
           and b.data_ultima_afericao is not null
           and (v_r.chao is null
                or (b.data_ultima_afericao + interval '2 years')::date >= v_r.chao)
           and (v_r.teto is null
                or (b.data_ultima_afericao + interval '2 years')::date <= v_r.teto)
           and ( not v_r.gestor
                 or case when b.empresa_id is null
                      then (b.data_ultima_afericao + interval '2 years')::date <= v_r.teto_frota
                      else b.empresa_id in (select empresa_id from frotas) end ) ) )
     or (b.status = 'aferido' and b.unidade_id = v_r.unidade);
  return v;
end $function$;

create or replace function public.meses_de_vencimento(p_unidade uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_r record;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select * into v_r from public.regua_do_usuario();

  with frotas as (
    select distinct f.empresa_id
      from public.caminhoneiros f
     where v_r.gestor
       and f.empresa_id is not null
       and f.unidade_id = v_r.unidade
       and f.tem_tacografo
       and f.data_ultima_afericao is not null
       and (f.data_ultima_afericao + interval '2 years')::date
           between v_r.chao and v_r.teto_frota
  )
  select coalesce(jsonb_agg(x order by x.mes), '[]'::jsonb) into v
  from (
    select to_char(b.venc,'YYYY-MM') as mes,
           count(*) as total, count(*) filter (where b.status = 'novo') as novos
    from public.base_trabalhavel(p_unidade) b
    join public.caminhoneiros c on c.id = b.id
    left join public.empresas e on e.id = b.empresa_id
    where b.na_fila
      and c.fora_de_area_em is null
      and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                   coalesce(e.fone_cls, 0)) > 0
      and ( v_r.admin
            or ( b.unidade_id = v_r.unidade
             and b.data_ultima_afericao is not null
             and (v_r.chao is null or b.venc >= v_r.chao)
             and (v_r.teto is null or b.venc <= v_r.teto)
             and ( not v_r.gestor
                   or case when b.empresa_id is null
                        then b.venc <= v_r.teto_frota
                        else b.empresa_id in (select empresa_id from frotas) end ) ) )
    group by 1) x;
  return v;
end $function$;

-- obter_lead: a ficha continua passando por pode_ler_lead (uma linha, uma
-- consulta — ali o custo não importa), mas agora informando a frota. E a lista
-- de veículos da frota respeita o horizonte do gestor. Para a operadora nada
-- muda: é com ela que a frota é trabalhada.
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'obter_lead';
  if v_def is null then raise exception 'obter_lead nao encontrada'; end if;

  v_velho := 'public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)';
  v_novo  := 'public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao, c.empresa_id)';
  if position(v_velho in v_def) = 0 then
    raise exception 'a chamada de pode_ler_lead nao foi encontrada em obter_lead';
  end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '        where x.empresa_id = e.id and x.tem_tacografo
          and x.data_ultima_afericao is not null), ''[]''::jsonb)';
  v_novo  := '        where x.empresa_id = e.id and x.tem_tacografo
          and x.data_ultima_afericao is not null
          and (not public.is_admin_unidade()
               or (x.data_ultima_afericao + interval ''2 years'')::date
                   <= current_date + coalesce(public.agrupamento_gestor_do_usuario(), 365))), ''[]''::jsonb)';
  if position(v_velho in v_def) = 0 then
    raise exception 'o trecho da lista de veiculos nao foi encontrado em obter_lead';
  end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;

revoke all on function public.fila_leads(integer, integer, text, text, uuid, text) from public, anon;
revoke all on function public.contar_leads(uuid) from public, anon;
revoke all on function public.meses_de_vencimento(uuid) from public, anon;
grant execute on function public.fila_leads(integer, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function public.contar_leads(uuid) to authenticated, service_role;
grant execute on function public.meses_de_vencimento(uuid) to authenticated, service_role;
