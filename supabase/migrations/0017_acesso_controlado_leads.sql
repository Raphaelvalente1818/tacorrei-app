-- 0017_acesso_controlado_leads.sql
-- Fecha o achado CRITICO do scan de 19/08/2026: o navegador pedia registros
-- direto na tabela, sem teto de volume e sem deixar rastro.
--
-- DECISAO DE PROJETO: as funcoes de leitura sao SECURITY INVOKER, nao DEFINER.
-- DEFINER rodaria como dono da tabela e IGNORARIA a RLS -- seria preciso
-- reescrever a regra de visibilidade aqui dentro, e qualquer erro vazaria lead
-- de uma unidade para outra. Como INVOKER, a RLS segue sendo a unica fonte da
-- verdade; a funcao so acrescenta TETO DE PAGINA e REGISTRO DE ACESSO.

create table if not exists public.acessos_lead (
  id          bigserial primary key,
  user_id     uuid,
  acao        text        not null check (acao in ('listar','abrir')),
  quantidade  integer     not null default 0,
  detalhe     jsonb,
  criado_em   timestamptz not null default now()
);

create index if not exists acessos_lead_user_data_idx on public.acessos_lead (user_id, criado_em desc);
create index if not exists acessos_lead_data_idx      on public.acessos_lead (criado_em desc);

alter table public.acessos_lead enable row level security;

-- So admin le. Ninguem altera ou apaga: log editavel nao vale como prova.
drop policy if exists acessos_lead_admin_le on public.acessos_lead;
create policy acessos_lead_admin_le on public.acessos_lead
  for select using (public.is_admin());

revoke all    on public.acessos_lead from anon, authenticated;
grant  select on public.acessos_lead to authenticated;

create or replace function public.registrar_acesso(
  p_acao text, p_quantidade integer, p_detalhe jsonb default null
) returns void
language sql security definer set search_path = public, pg_temp
as $$
  insert into public.acessos_lead (user_id, acao, quantidade, detalhe)
  values (auth.uid(), p_acao, coalesce(p_quantidade, 0), p_detalhe);
$$;

revoke execute on function public.registrar_acesso(text, integer, jsonb) from public, anon;
grant  execute on function public.registrar_acesso(text, integer, jsonb) to authenticated;

create or replace function public.listar_leads(
  p_pagina  integer default 1,
  p_tamanho integer default 100,
  p_filtro  text    default 'todos',
  p_busca   text    default null,
  p_unidade uuid    default null
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  v_tam integer; v_ini integer; v_busca text; v_total bigint; v_linhas jsonb;
begin
  -- TETO RIGIDO: pedido acima de 100 e RECUSADO, nao truncado em silencio.
  -- Truncar esconderia a tentativa; recusar deixa rastro.
  if p_tamanho is not null and p_tamanho > 100 then
    raise exception 'tamanho de pagina acima do permitido (maximo 100)';
  end if;

  v_tam := least(greatest(coalesce(p_tamanho, 100), 1), 100);
  v_ini := greatest(coalesce(p_pagina, 1) - 1, 0) * v_tam;
  v_busca := nullif(btrim(coalesce(p_busca, '')), '');

  with visiveis as (
    select c.* from public.caminhoneiros c      -- RLS aplica aqui
    where (p_unidade is null or c.unidade_id = p_unidade)
      and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
      and (v_busca is null
           or c.nome ilike '%'||v_busca||'%' or c.telefone ilike '%'||v_busca||'%'
           or c.cidade ilike '%'||v_busca||'%' or c.placa_veiculo ilike '%'||v_busca||'%')
  )
  select (select count(*) from visiveis),
         coalesce((select jsonb_agg(to_jsonb(p) order by p.data_ultima_afericao asc nulls last, p.id)
                   from (select * from visiveis
                         order by data_ultima_afericao asc nulls last, id
                         offset v_ini limit v_tam) p), '[]'::jsonb)
  into v_total, v_linhas;

  perform public.registrar_acesso('listar', jsonb_array_length(v_linhas),
    jsonb_build_object('filtro', p_filtro, 'busca', v_busca,
                       'pagina', coalesce(p_pagina,1), 'unidade', p_unidade));

  return jsonb_build_object('total', v_total, 'leads', v_linhas);
end $$;

revoke execute on function public.listar_leads(integer, integer, text, text, uuid) from public, anon;
grant  execute on function public.listar_leads(integer, integer, text, text, uuid) to authenticated;

create or replace function public.obter_lead(p_id uuid)
returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare v_lead jsonb;
begin
  select to_jsonb(c) into v_lead from public.caminhoneiros c where c.id = p_id;  -- RLS aplica
  if v_lead is null then return null; end if;
  perform public.registrar_acesso('abrir', 1, jsonb_build_object('lead', p_id));
  return v_lead;
end $$;

revoke execute on function public.obter_lead(uuid) from public, anon;
grant  execute on function public.obter_lead(uuid) to authenticated;
