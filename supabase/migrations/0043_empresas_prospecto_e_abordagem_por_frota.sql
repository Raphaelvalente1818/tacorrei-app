-- [aplicada no banco em 08/09/2026 17:59 — versão 20260908175932]
-- ── 0043 — empresa deixa de significar "não mexer" ──────────────────────────
--
-- Até aqui, `empresa_id is not null` queria dizer "cliente com contrato, fora
-- da fila". Isso misturava duas coisas diferentes: SER FROTA e TER CONTRATO.
-- Agora entram empresas de 3+ caminhões que aferem no concorrente — elas
-- precisam ser trabalhadas, não escondidas.
--
-- Duas chaves, dois trabalhos:
--   • quem é o cliente  → a empresa
--   • quem recebe a mensagem → o contato da empresa, não o telefone do RNTRC
--     (que é do motorista da vez e muda a cada viagem)
--
-- E os caminhões não vencem juntos. Por isso a abordagem é UMA, mas cobre
-- vários veículos: o que vence agora e os que vencem dentro da janela de
-- agrupamento. Vir tudo numa viagem só é argumento de venda, não concessão.

-- 1) O estado da empresa -----------------------------------------------------
alter table public.empresas
  add column if not exists situacao text not null default 'contrato';

do $$ begin
  alter table public.empresas add constraint empresas_situacao_ck
    check (situacao in ('contrato','prospecto'));
exception when duplicate_object then null; end $$;

comment on column public.empresas.situacao is
  'contrato = fora da fila, só relação mensal. prospecto = entra na fila e é trabalhada.';

-- Janela de agrupamento: até quantos dias à frente um irmão entra na mesma
-- conversa. Além disso ele fica quieto e gera abordagem própria mais tarde.
alter table public.unidades
  add column if not exists agrupamento_dias integer not null default 60;

-- 2) A fila esconde só quem tem contrato -------------------------------------
create or replace function public.listar_leads(
  p_pagina integer default 1, p_tamanho integer default 100,
  p_filtro text default 'todos', p_busca text default null,
  p_unidade uuid default null, p_mes text default null)
returns jsonb language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
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
end $function$;

-- 3) A ficha do lead traz a frota inteira ------------------------------------
-- Sem isto a operadora não teria como saber que existe irmão vencendo, e a
-- trava por empresa pareceria arbitrária.
create or replace function public.obter_lead(p_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare v_lead jsonb; v_emp uuid; v_empresa jsonb; v_agrup integer; v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select to_jsonb(c), c.empresa_id, c.unidade_id into v_lead, v_emp, v_unidade
  from public.caminhoneiros c
  where c.id = p_id
    and public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao);

  if v_lead is null then return null; end if;

  if v_emp is not null then
    select coalesce(u.agrupamento_dias, 60) into v_agrup from public.unidades u where u.id = v_unidade;

    select jsonb_build_object(
      'id', e.id, 'nome', e.nome, 'cnpj', e.cnpj,
      'contato', e.contato, 'telefone', e.telefone,
      'situacao', e.situacao, 'agrupamento_dias', v_agrup,
      -- "herda o melhor": se UM caminhão da frota já aferiu conosco, a pessoa
      -- nos conhece. O opt-in é dela, não da placa.
      'ja_e_cliente', exists (
        select 1 from public.caminhoneiros x
        where x.empresa_id = e.id
          and (public.posto_do_grupo(x.posto_afericao) or coalesce(x.autorizou_whatsapp,false))),
      'veiculos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'placa', x.placa_veiculo,
                 'venc', (x.data_ultima_afericao + interval '2 years')::date,
                 'dias', (x.data_ultima_afericao + interval '2 years')::date - current_date,
                 'este', x.id = p_id)
               order by (x.data_ultima_afericao + interval '2 years')::date)
        from public.caminhoneiros x
        where x.empresa_id = e.id and x.tem_tacografo
          and x.data_ultima_afericao is not null), '[]'::jsonb)
    ) into v_empresa
    from public.empresas e where e.id = v_emp;

    v_lead := v_lead || jsonb_build_object('empresa', v_empresa);
  end if;

  perform public.registrar_acesso('abrir', 1, jsonb_build_object('lead', p_id));
  return v_lead;
end $function$;

-- 4) Uma abordagem, vários caminhões -----------------------------------------
create or replace function public.registrar_envio_whatsapp(
  p_lead uuid, p_mensagem text, p_leads uuid[] default null)
returns jsonb language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare
  v_unidade uuid; v_venc date; v_janela integer; v_piso integer;
  v_limite integer; v_intervalo integer; v_usadas integer;
  v_marco timestamptz; v_ja integer; v_ultimo timestamptz;
  v_posto text; v_autorizou boolean; v_falta integer;
  v_fone text; v_cooldown integer; v_emp uuid; v_emp_nome text; v_emp_sit text;
  v_irmao record; v_placas text; v_quantos integer; v_alvos uuid[]; v_extras integer;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id, (c.data_ultima_afericao + interval '2 years')::date,
         c.posto_afericao, c.autorizou_whatsapp, public.normaliza_fone(c.telefone), c.empresa_id
    into v_unidade, v_venc, v_posto, v_autorizou, v_fone, v_emp
  from public.caminhoneiros c where c.id = p_lead;

  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  select u.janela_dias, u.piso_dias, u.limite_whatsapp_dia, u.intervalo_whatsapp_min,
         u.cooldown_telefone_dias
    into v_janela, v_piso, v_limite, v_intervalo, v_cooldown
  from public.unidades u where u.id = v_unidade;

  if v_emp is not null then
    select e.nome, e.situacao into v_emp_nome, v_emp_sit from public.empresas e where e.id = v_emp;
    if v_emp_sit = 'contrato' then
      raise exception 'a % tem contrato: o caminho e a relacao mensal na aba Empresas, nao mensagem avulsa', v_emp_nome;
    end if;
  end if;

  -- 1) RELAÇÃO — numa frota, basta UM caminhão nosso para a pessoa nos conhecer
  if v_emp is not null then
    if not exists (select 1 from public.caminhoneiros x where x.empresa_id = v_emp
                    and (public.posto_do_grupo(x.posto_afericao) or coalesce(x.autorizou_whatsapp,false))) then
      raise exception 'nenhum caminhao da % aferiu conosco: ligue primeiro e marque "autorizou receber mensagem"', v_emp_nome;
    end if;
  elsif not (public.posto_do_grupo(v_posto) or coalesce(v_autorizou,false)) then
    raise exception 'este lead e cliente de concorrente: ligue primeiro e marque "autorizou receber mensagem"';
  end if;

  -- 2) FAIXA de vencimento (do caminhão que abre a conversa)
  if v_venc is null then raise exception 'sem data de afericao: este veiculo nao tem tacografo'; end if;
  if v_janela is not null and v_venc > current_date + v_janela then
    raise exception 'ainda cedo: este certificado so vence em %', to_char(v_venc,'DD/MM/YYYY');
  end if;
  if v_venc < current_date - coalesce(v_piso,365) then
    raise exception 'vencido ha mais de % meses (em %): fora da faixa de contato',
      round(coalesce(v_piso,365)/30.0), to_char(v_venc,'DD/MM/YYYY');
  end if;

  -- 3) UMA por lead por ciclo (zera quando afere)
  select max(l.created_at) into v_marco
  from public.ligacoes l where l.caminhoneiro_id = p_lead and l.resultado = 'aferido';
  select count(*) into v_ja
  from public.ligacoes l
  where l.caminhoneiro_id = p_lead and l.resultado = 'whatsapp_enviado'
    and (v_marco is null or l.created_at > v_marco);
  if v_ja > 0 then raise exception 'este lead ja recebeu mensagem neste ciclo'; end if;

  -- 3a) UMA por EMPRESA — a frota é uma pessoa só, ainda que sejam 7 caminhões
  if v_emp is not null and coalesce(v_cooldown,0) > 0 then
    select x.placa_veiculo, x.data_ultimo_whatsapp into v_irmao
    from public.caminhoneiros x
    where x.empresa_id = v_emp and x.id <> p_lead
      and x.data_ultimo_whatsapp > now() - make_interval(days => v_cooldown)
    order by x.data_ultimo_whatsapp desc limit 1;
    if found then
      raise exception 'a % ja foi abordada em % (placa %). Sao % dias entre abordagens: fale de todos os caminhoes na mesma conversa.',
        v_emp_nome, to_char(v_irmao.data_ultimo_whatsapp at time zone 'America/Sao_Paulo','DD/MM'),
        v_irmao.placa_veiculo, v_cooldown;
    end if;
  end if;

  -- 3b) UMA por TELEFONE — só para lead solto; na empresa quem manda é a trava 3a
  if v_emp is null and v_fone is not null and coalesce(v_cooldown,0) > 0 then
    select c.placa_veiculo, c.nome, c.data_ultimo_whatsapp into v_irmao
    from public.caminhoneiros c
    where c.id <> p_lead and c.unidade_id = v_unidade
      and public.normaliza_fone(c.telefone) = v_fone
      and c.data_ultimo_whatsapp > now() - make_interval(days => v_cooldown)
    order by c.data_ultimo_whatsapp desc limit 1;

    if found then
      select count(*), string_agg(x.placa_veiculo, ', ' order by x.placa_veiculo)
        into v_quantos, v_placas
      from (select c.placa_veiculo from public.caminhoneiros c
            where c.id <> p_lead and c.unidade_id = v_unidade
              and public.normaliza_fone(c.telefone) = v_fone and c.placa_veiculo is not null
            order by c.placa_veiculo limit 6) x;

      raise exception
        'este telefone ja recebeu mensagem em %, sobre a placa % (%). Mesmo numero em mais % lead(s): %. Fale de todas na mesma conversa em vez de mandar outra mensagem.',
        to_char(v_irmao.data_ultimo_whatsapp at time zone 'America/Sao_Paulo','DD/MM'),
        coalesce(v_irmao.placa_veiculo,'(sem placa)'), coalesce(v_irmao.nome,'sem nome'),
        coalesce(v_quantos,0), coalesce(v_placas,'—');
    end if;
  end if;

  -- 4) COTA do dia — a abordagem conta 1, tenha ela 1 ou 7 caminhões
  select count(*), max(l.created_at) into v_usadas, v_ultimo
  from public.ligacoes l
  where l.unidade_id = v_unidade and l.canal = 'whatsapp'
    and (l.created_at at time zone 'America/Sao_Paulo')::date
        = (now() at time zone 'America/Sao_Paulo')::date;
  if v_usadas >= v_limite then
    raise exception 'cota diaria de % mensagens ja foi usada nesta unidade', v_limite;
  end if;

  -- 5) RITMO
  if v_intervalo > 0 and v_ultimo is not null then
    v_falta := ceil(extract(epoch from (v_ultimo + make_interval(mins => v_intervalo) - now()))/60.0);
    if v_falta > 0 then
      raise exception 'aguarde % min para o proximo envio (ritmo de % em % min protege o numero)',
        v_falta, 1, v_intervalo;
    end if;
  end if;

  -- Os caminhões cobertos: o que abriu a conversa e os irmãos que ela marcou.
  -- Só valem irmãos da MESMA empresa — não dá para varrer a base por aqui.
  v_alvos := array[p_lead];
  if p_leads is not null and v_emp is not null then
    select array_agg(distinct x.id) into v_alvos
    from public.caminhoneiros x
    where (x.id = p_lead or (x.id = any(p_leads) and x.empresa_id = v_emp and x.unidade_id = v_unidade));
  end if;
  v_extras := coalesce(array_length(v_alvos,1),1) - 1;

  -- A conversa em si conta na cota (canal whatsapp). Os irmãos entram como
  -- 'sistema': ficam no histórico de cada caminhão sem inflar o contador.
  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'whatsapp', 'whatsapp_enviado', p_mensagem);

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  select x, v_unidade, auth.uid(), 'sistema', 'whatsapp_enviado',
         'Coberto pela mensagem enviada para a frota.'
  from unnest(v_alvos) x where x <> p_lead;

  update public.caminhoneiros
     set data_ultimo_whatsapp = now(),
         status = case when status in ('novo','sem_resposta') then 'mensagem_enviada' else status end
   where id = any(v_alvos);

  return jsonb_build_object('limite', v_limite, 'usadas', v_usadas + 1,
                            'restantes', greatest(v_limite - v_usadas - 1, 0),
                            'intervalo', v_intervalo, 'cobertos', coalesce(array_length(v_alvos,1),1),
                            'extras', v_extras);
end $function$;

-- 5) O painel de empresas separa contrato de prospecto -----------------------
create or replace function public.empresas_painel(
  p_unidade uuid default null, p_competencia date default null)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_temp' as $function$
declare v jsonb; v_comp date;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_comp := coalesce(p_competencia, date_trunc('month', current_date + interval '1 month')::date);

  select coalesce(jsonb_agg(x order by x.vencendo desc, x.nome), '[]'::jsonb) into v
  from (
    select e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao,
           v_comp as competencia,
           count(c.id) filter (where c.tem_tacografo) as veiculos,
           count(c.id) filter (
             where c.tem_tacografo and c.data_ultima_afericao is not null
               and date_trunc('month', (c.data_ultima_afericao + interval '2 years'))::date = v_comp
           ) as vencendo,
           count(c.id) filter (
             where c.tem_tacografo and c.data_ultima_afericao is not null
               and (c.data_ultima_afericao + interval '2 years')::date < current_date
           ) as vencidos,
           (select a.enviado_em from public.avisos_empresa a
             where a.empresa_id = e.id and a.competencia = v_comp) as avisada_em,
           max(c.data_ultimo_whatsapp) as ultima_abordagem
    from public.empresas e
    left join public.caminhoneiros c on c.empresa_id = e.id
    where e.ativo
      and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())
      and (p_unidade is null or e.unidade_id = p_unidade)
    group by e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao
  ) x;
  return v;
end $function$;
