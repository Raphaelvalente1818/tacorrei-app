-- 0091b — a classe do telefone vira coluna calculada
--
-- A 0091 deixou a fila de São Bernardo em 5,5 s (era ~2,1 s): dois regexp_replace por
-- linha, em 14 mil linhas, no WHERE e de novo no ORDER BY. A conta é sempre a mesma
-- para o mesmo telefone — então ela é gravada, não recalculada.
-- Depois desta: fila "Todos" 2,9 s, fila do mês 68 ms, contar_leads 2,3 s.
-- O que sobra de lento é o `pode_ler_lead` por linha (já conhecido, item à parte).

alter table public.caminhoneiros
  add column if not exists fone_cls integer
  generated always as (
    case length(regexp_replace(coalesce(telefone,''), '[^0-9]', '', 'g'))
      when 11 then 11 when 10 then 10 else 0 end
  ) stored;

alter table public.empresas
  add column if not exists fone_cls integer
  generated always as (
    case length(regexp_replace(coalesce(telefone,''), '[^0-9]', '', 'g'))
      when 11 then 11 when 10 then 10 else 0 end
  ) stored;

comment on column public.caminhoneiros.fone_cls is
  '11 = celular, 10 = fixo, 0 = sem telefone utilizavel. Calculada pelo banco.';

-- a fila usa a coluna; nada de regex por linha
create or replace function public.fila_leads(
  p_pagina integer default 1, p_tamanho integer default 100,
  p_filtro text default 'todos', p_busca text default null,
  p_unidade uuid default null, p_mes text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
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
    select c.*, e.nome as empresa_nome, e.situacao as empresa_situacao,
           public.posto_do_grupo(c.posto_afericao, c.unidade_id) as nosso,
           -- por onde dá para falar com ele hoje: 11 celular, 10 fixo, 0 nada
           greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                    coalesce(e.fone_cls, 0)) as fone
      from public.caminhoneiros c
      left join public.empresas e on e.id = c.empresa_id
     where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
       and (c.empresa_id is null or e.situacao = 'prospecto')
       and (p_unidade is null or c.unidade_id = p_unidade)
       and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                 when p_filtro = 'sem_telefone'  then c.tem_tacografo = true
                 else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
       and (v_busca is not null or c.tem_tacografo = false
            or public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao))
       and (v_busca is not null
            or p_filtro = 'sem_tacografo'
            or (case when p_filtro = 'sem_telefone'
                     then greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                   coalesce(e.fone_cls, 0)) = 0
                     else greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                   coalesce(e.fone_cls, 0)) > 0
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
revoke all on function public.fila_leads(integer,integer,text,text,uuid,text) from public, anon;
grant execute on function public.fila_leads(integer,integer,text,text,uuid,text) to authenticated, service_role;

create or replace function public.contar_leads(p_unidade uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select jsonb_build_object(
    'total',            count(*) filter (where contatavel),
    'novo',             count(*) filter (where contatavel and b.status = 'novo'),
    'mensagem_enviada', count(*) filter (where contatavel and b.status = 'mensagem_enviada'),
    'contatado',        count(*) filter (where contatavel and b.status = 'contatado'),
    'agendado',         count(*) filter (where contatavel and b.status = 'agendado'),
    'aferido',          count(*) filter (where contatavel and b.status = 'aferido'),
    'sem_telefone',     count(*) filter (where not contatavel)
  ) into v
  from (
    select b.status, b.unidade_id, b.data_ultima_afericao,
           greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                    coalesce(e.fone_cls, 0)) > 0 as contatavel
      from public.base_trabalhavel(p_unidade) b
      join public.caminhoneiros c on c.id = b.id
      left join public.empresas e on e.id = b.empresa_id
     where b.na_fila
  ) b
  where public.pode_ler_lead(b.unidade_id, true, b.data_ultima_afericao)
     or (b.status = 'aferido' and b.unidade_id = public.unidade_do_usuario());
  return v;
end $function$;
revoke all on function public.contar_leads(uuid) from public, anon;
grant execute on function public.contar_leads(uuid) to authenticated, service_role;

create or replace function public.meses_de_vencimento(p_unidade uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select coalesce(jsonb_agg(x order by x.mes), '[]'::jsonb) into v
  from (
    select to_char(b.venc,'YYYY-MM') as mes,
           count(*) as total, count(*) filter (where b.status = 'novo') as novos
    from public.base_trabalhavel(p_unidade) b
    join public.caminhoneiros c on c.id = b.id
    left join public.empresas e on e.id = b.empresa_id
    where b.na_fila
      and public.pode_ler_lead(b.unidade_id, true, b.data_ultima_afericao)
      and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                   coalesce(e.fone_cls, 0)) > 0
    group by 1) x;
  return v;
end $function$;
revoke all on function public.meses_de_vencimento(uuid) from public, anon;
grant execute on function public.meses_de_vencimento(uuid) to authenticated, service_role;

create index if not exists caminhoneiros_fila_idx
  on public.caminhoneiros (unidade_id, fone_cls desc, data_ultima_afericao)
  where tem_tacografo;

analyze public.caminhoneiros;
analyze public.empresas;
