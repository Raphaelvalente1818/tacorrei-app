-- 0091 — A fila só entrega quem dá para ligar
--
-- 13/09: das 108 ligações da Fernanda em 02–03/09, 84 deram "número inválido" (78%).
-- Dessas, 17 eram leads SEM TELEFONE NENHUM — o app pôs na frente dela um caminhão
-- sem número para discar. Outras 51 eram fixo de 10 dígitos do RNTRC.
-- Três mudanças, todas no banco:
--   1. quem não tem telefone útil sai da fila do dia (vai para o filtro "Sem telefone");
--   2. a fila entrega celular antes de fixo;
--   3. "número inválido" queima o telefone — ele não volta amanhã igual.
-- A régua (base_trabalhavel) NÃO muda: carteira, Empresas, Unidades, Produção e Meta
-- continuam contando a base inteira. Quem passa a filtrar é só a FILA.
--
-- ⚠️ Esta migration deixou a fila de SBC em 5,5 s (dois regexp_replace por linha em
-- 14 mil linhas, no WHERE e de novo no ORDER BY). A 0091b troca isso por uma coluna
-- calculada e devolve a fila a ~2,9 s. Aplicar as duas, nesta ordem.

-- 1. classe do telefone: 11 = celular, 10 = fixo, 0 = inútil ------------------
-- sql/immutable e sem SET, para o planejador inlinar (lição 19).
create or replace function public.fone_classe(p_tel text)
returns integer
language sql
immutable
as $$
  select case length(regexp_replace(coalesce(p_tel,''), '[^0-9]', '', 'g'))
           when 11 then 11
           when 10 then 10
           else 0
         end
$$;
revoke all on function public.fone_classe(text) from public, anon;
grant execute on function public.fone_classe(text) to authenticated, service_role;

-- 2. telefone queimado --------------------------------------------------------
alter table public.caminhoneiros
  add column if not exists telefone_invalido_em timestamptz;

comment on column public.caminhoneiros.telefone_invalido_em is
  'Quando alguém registrou "número inválido" neste lead. Sai da fila enquanto estiver '
  'preenchido; volta sozinho se o número for trocado ou se alguém atender.';

-- backfill: vale quando o ÚLTIMO contato do lead foi "número inválido".
with ultimo as (
  select distinct on (l.caminhoneiro_id)
         l.caminhoneiro_id, l.resultado, l.created_at
    from public.ligacoes l
   where l.caminhoneiro_id is not null
   order by l.caminhoneiro_id, l.created_at desc
)
update public.caminhoneiros c
   set telefone_invalido_em = u.created_at
  from ultimo u
 where u.caminhoneiro_id = c.id
   and u.resultado = 'numero_invalido'
   and c.telefone_invalido_em is null;

-- o gatilho mantém a marca em dia daqui para a frente
create or replace function public.marca_telefone_invalido()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.caminhoneiro_id is null then return new; end if;

  if new.resultado = 'numero_invalido' then
    update public.caminhoneiros
       set telefone_invalido_em = coalesce(telefone_invalido_em, now())
     where id = new.caminhoneiro_id;

  -- alguém atendeu: o número presta, desmarca
  elsif new.resultado in ('atendeu','agendou','reagendar','recusou','autorizou_whatsapp') then
    update public.caminhoneiros
       set telefone_invalido_em = null
     where id = new.caminhoneiro_id and telefone_invalido_em is not null;
  end if;

  return new;
end $$;

drop trigger if exists trg_telefone_invalido on public.ligacoes;
create trigger trg_telefone_invalido
  after insert on public.ligacoes
  for each row execute function public.marca_telefone_invalido();

-- trocar o telefone limpa a marca (número novo merece uma chance)
create or replace function public.limpa_marca_ao_trocar_telefone()
returns trigger
language plpgsql
as $$
begin
  if new.telefone is distinct from old.telefone
     and new.telefone_invalido_em is not distinct from old.telefone_invalido_em then
    new.telefone_invalido_em := null;
  end if;
  return new;
end $$;

drop trigger if exists trg_limpa_marca_telefone on public.caminhoneiros;
create trigger trg_limpa_marca_telefone
  before update on public.caminhoneiros
  for each row execute function public.limpa_marca_ao_trocar_telefone();

-- 3. a fila --------------------------------------------------------------------
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
           -- por onde dá para falar com ele hoje: 11 celular, 10 fixo, 0 nada.
           greatest(
             case when c.telefone_invalido_em is null then public.fone_classe(c.telefone) else 0 end,
             public.fone_classe(e.telefone)
           ) as fone
      from public.caminhoneiros c
      left join public.empresas e on e.id = c.empresa_id
     where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
       and (c.empresa_id is null or e.situacao = 'prospecto')
       and (p_unidade is null or c.unidade_id = p_unidade)
       and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                 when p_filtro = 'sem_telefone'  then c.tem_tacografo = true
                 else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
       -- a régua (mesmo predicado de base_trabalhavel); a busca passa por cima
       and (v_busca is not null or c.tem_tacografo = false
            or public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao))
       -- contatável: a fila do dia não entrega quem não tem para onde ligar.
       -- "Sem telefone" é o avesso disso — é onde esses leads ficam visíveis.
       and (v_busca is not null
            or p_filtro = 'sem_tacografo'
            or (case when p_filtro = 'sem_telefone'
                     then greatest(case when c.telefone_invalido_em is null
                                        then public.fone_classe(c.telefone) else 0 end,
                                   public.fone_classe(e.telefone)) = 0
                     else greatest(case when c.telefone_invalido_em is null
                                        then public.fone_classe(c.telefone) else 0 end,
                                   public.fone_classe(e.telefone)) > 0
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

-- 4. os contadores acompanham a fila -------------------------------------------
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
    -- fora do total: é o buraco, não a fila
    'sem_telefone',     count(*) filter (where not contatavel)
  ) into v
  from (
    select b.status, b.unidade_id, b.data_ultima_afericao,
           greatest(case when c.telefone_invalido_em is null
                         then public.fone_classe(c.telefone) else 0 end,
                    public.fone_classe(e.telefone)) > 0 as contatavel
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
      and greatest(case when c.telefone_invalido_em is null
                        then public.fone_classe(c.telefone) else 0 end,
                   public.fone_classe(e.telefone)) > 0
    group by 1) x;
  return v;
end $function$;
revoke all on function public.meses_de_vencimento(uuid) from public, anon;
grant execute on function public.meses_de_vencimento(uuid) to authenticated, service_role;

-- 5. a conferência ganha a checagem nova ---------------------------------------
create or replace function public.conferencia_contagens()
returns table(unidade text, checagem text, a bigint, b bigint, ok boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare u record; v_admin uuid; v_mes text; m record; v_comp date;
begin
  select e.user_id into v_admin from public.equipe e
   where e.papel = 'admin' and e.ativo and e.unidade_id is null order by e.nome limit 1;
  if v_admin is null then raise exception 'sem admin geral para a conferencia'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_mes := to_char(current_date, 'YYYY-MM');
  v_comp := date_trunc('month', current_date)::date;

  for u in select id, nome from public.unidades order by nome loop
    unidade := u.nome; checagem := 'botao Vencidos = lista Vencidos';
    select coalesce(sum((x->>'total')::bigint), 0) into a
      from jsonb_array_elements(public.meses_de_vencimento(u.id)) x where (x->>'mes') < v_mes;
    b := (public.fila_leads(1, 1, 'todos', null, u.id, 'vencidos')->>'total')::bigint;
    ok := a = b; return next;

    for m in select (x->>'mes') mes, (x->>'total')::bigint total
               from jsonb_array_elements(public.meses_de_vencimento(u.id)) x
              where (x->>'mes') >= v_mes order by 1 limit 3 loop
      checagem := 'botao ' || m.mes || ' = lista ' || m.mes;
      a := m.total;
      b := (public.fila_leads(1, 1, 'todos', null, u.id, m.mes)->>'total')::bigint;
      ok := a = b; return next;
    end loop;

    checagem := 'contar_leads.total = lista Todos';
    a := (public.contar_leads(u.id)->>'total')::bigint;
    b := (public.fila_leads(1, 1, 'todos', null, u.id, null)->>'total')::bigint;
    ok := a = b; return next;

    checagem := 'soma dos botoes = lista Todos';
    select coalesce(sum((x->>'total')::bigint), 0) into a
      from jsonb_array_elements(public.meses_de_vencimento(u.id)) x;
    ok := a = b; return next;

    -- novo em 0091: o que saiu da fila por falta de telefone tem de aparecer inteiro
    -- no filtro "Sem telefone" — nada pode simplesmente sumir.
    checagem := 'contar_leads.sem_telefone = lista Sem telefone';
    a := (public.contar_leads(u.id)->>'sem_telefone')::bigint;
    b := (public.fila_leads(1, 1, 'sem_telefone', null, u.id, null)->>'total')::bigint;
    ok := a = b; return next;

    checagem := 'fila + sem telefone = regua na fila';
    a := (public.contar_leads(u.id)->>'total')::bigint
       + (public.contar_leads(u.id)->>'sem_telefone')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t where t.na_fila;
    ok := a = b; return next;

    checagem := 'Empresas.veiculos = regua (com empresa)';
    select coalesce(sum((x->>'veiculos')::bigint), 0) into a
      from jsonb_array_elements(public.empresas_painel(u.id, null)) x;
    select count(*) into b from public.base_trabalhavel(u.id) t
      join public.empresas e on e.id = t.empresa_id where e.ativo;
    ok := a = b; return next;

    checagem := 'Empresas.vencidos = regua (com empresa, vencidos)';
    select coalesce(sum((x->>'vencidos')::bigint), 0) into a
      from jsonb_array_elements(public.empresas_painel(u.id, null)) x;
    select count(*) into b from public.base_trabalhavel(u.id) t
      join public.empresas e on e.id = t.empresa_id where e.ativo and t.venc < current_date;
    ok := a = b; return next;

    checagem := 'Unidades.carteira = regua';
    select (x->>'carteira')::bigint into a
      from jsonb_array_elements(public.unidades_painel()) x where (x->>'id')::uuid = u.id;
    select count(*) into b from public.base_trabalhavel(u.id);
    ok := a = b; return next;

    checagem := 'Producao.leads = regua';
    select (x->>'leads')::bigint into a
      from jsonb_array_elements(public.producao_unidades(null)) x where (x->>'id')::uuid = u.id;
    ok := a = b; return next;

    checagem := 'Meta.vencidos_recuperaveis = regua';
    a := ((public.meta_do_mes(u.id, v_comp))->'universo'->>'vencidos_recuperaveis')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t
      where t.posto_conhecido and not t.nosso and t.venc < current_date;
    ok := a = b; return next;

    checagem := 'Meta.vencem_no_mes.total = regua';
    a := ((public.meta_do_mes(u.id, v_comp))->'universo'->'vencem_no_mes'->>'total')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t
      where t.posto_conhecido and t.venc >= v_comp and t.venc < (v_comp + interval '1 month')::date;
    ok := a = b; return next;
  end loop;
end $function$;
revoke all on function public.conferencia_contagens() from public, anon;
grant execute on function public.conferencia_contagens() to authenticated, service_role;

-- índice para o filtro novo não virar varredura
create index if not exists caminhoneiros_tel_invalido_idx
  on public.caminhoneiros (unidade_id) where telefone_invalido_em is not null;
