-- 0095 — o resultado da ligação é que manda na ficha
--
-- 14/09, o Emerson estudou a ficha do lead e apontou três coisas, que são a mesma:
--   1. "Liguei — autorizou mensagem" parece aceso, como se já tivesse sido feito;
--   2. "Aferido" idem;
--   3. o resultado da ligação deveria acionar sozinho o botão correspondente.
-- O fundo é que a tela usava COR para duas coisas diferentes — "ação disponível" e
-- "isto já aconteceu". A regra agora é: botão neutro = ação; botão aceso = estado.
-- E a operadora deixa de precisar saber qual botão apertar: ela conta o que aconteceu
-- na ligação e o sistema faz o resto.
--
-- Item novo pedido por ele: "Caminhão de outra localidade" — o dono tem caminhão aqui
-- e caminhão em outra praça, e afere cada um no seu lugar. Esse veículo não é alvo.
-- Decisão dele: sai da fila, mas fica visível num filtro próprio (mesmo padrão do
-- "Sem telefone" da 0091), para dar para desfazer e para medir quanto da base é de fora.
--
-- Duas coisas que NÃO passaram para o resultado da ligação, de propósito:
--   • o envio de WhatsApp — tem seis travas (cota, intervalo, cooldown, relação) e foi
--     mensagem fora de trava que derrubou o número em 28/08. "Autorizou mensagem" apenas
--     LIBERA o botão; quem envia é a operadora, na ficha.
--   • o botão "Aferido" — é usado no balcão, quando o caminhão chega. Não tem ligação
--     envolvida. O que virou desfecho de ligação é o "já aferiu no concorrente".
--
-- Ensaio com rollback antes de aplicar: fora_de_area tira da fila e aparece no filtro
-- (817→816, filtro=1, some de "Todos", a soma dos três baldes se conserva) e o desfazer
-- devolve; aferiu_fora grava data e posto e o gatilho registra 'fuga'; autorizou libera;
-- numero_invalido queima o telefone (gatilho da 0091); resultado inexistente é recusado.
-- Conferência depois: 30/30.

-- 1. fora de área -------------------------------------------------------------
alter table public.caminhoneiros
  add column if not exists fora_de_area_em timestamptz,
  add column if not exists fora_de_area_por uuid references public.equipe(user_id) on delete set null;

comment on column public.caminhoneiros.fora_de_area_em is
  'O dono afere ESTE veículo em outra praça. Sai da fila; continua visível no filtro '
  '"Fora de área". Desmarcar é só limpar a coluna.';

-- 2. dois resultados novos ----------------------------------------------------
alter table public.ligacoes drop constraint if exists ligacoes_resultado_check;
alter table public.ligacoes add constraint ligacoes_resultado_check
  check (resultado = any (array[
    'atendeu','nao_atendeu','numero_invalido','recusou','agendou','reagendar',
    'whatsapp_enviado','aferido','autorizou_whatsapp','atualizacao',
    -- 0095
    'aferiu_fora',    -- disse na ligação que aferiu no concorrente
    'fora_de_area'    -- este caminhão roda e afere em outra praça
  ]));

-- 3. um caminho só para registrar o que aconteceu na ligação -------------------
-- Antes o front inseria direto em `ligacoes` e dava update no status; a autorização,
-- o "aferiu em outro posto" e o agendamento eram botões separados. Agora é uma função
-- só: ela grava o contato E aplica o efeito, sem o front precisar saber a regra.
create or replace function public.registrar_contato(
  p_lead uuid,
  p_canal text,
  p_resultado text,
  p_notas text default null,
  p_data date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_unidade uuid; v_status text; v_notas text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;
  if p_canal not in ('ligacao_ativa','ligacao_passiva') then
    raise exception 'canal invalido para registro de contato: %', p_canal;
  end if;

  v_notas := nullif(btrim(coalesce(p_notas,'')), '');

  -- o status que cada desfecho deixa no lead
  v_status := case p_resultado
    when 'nao_atendeu'        then 'sem_resposta'
    when 'numero_invalido'    then 'invalido'
    when 'recusou'            then 'recusado'
    when 'agendou'            then 'agendado'
    when 'reagendar'          then 'contatado'
    when 'atendeu'            then 'contatado'
    when 'autorizou_whatsapp' then 'contatado'
    when 'aferiu_fora'        then 'novo'   -- volta a zero: o ciclo dele recomeça em 2 anos
    when 'fora_de_area'       then 'novo'   -- sai da fila pela marca, não pelo status
    else null end;
  if v_status is null then raise exception 'resultado invalido: %', p_resultado; end if;

  -- efeitos por desfecho
  if p_resultado = 'autorizou_whatsapp' then
    update public.caminhoneiros
       set autorizou_whatsapp = true, autorizado_em = now(), autorizado_por = auth.uid()
     where id = p_lead;

  elsif p_resultado = 'aferiu_fora' then
    if p_data is null then raise exception 'informe a data em que ele aferiu'; end if;
    if p_data > current_date then raise exception 'a data da afericao nao pode ser no futuro'; end if;
    -- a troca de posto (fuga, se era nosso) fica por conta do gatilho trg_troca_de_posto
    update public.caminhoneiros
       set data_ultima_afericao = p_data,
           posto_afericao = 'OUTRO POSTO (concorrente)'
     where id = p_lead;
    v_notas := 'Aferiu em outro posto em ' || to_char(p_data,'DD/MM/YYYY')
               || coalesce('. ' || v_notas, '');

  elsif p_resultado = 'fora_de_area' then
    update public.caminhoneiros
       set fora_de_area_em = now(), fora_de_area_por = auth.uid()
     where id = p_lead;
    v_notas := coalesce(v_notas, 'Afere em outra praça — fora do nosso alvo.');
  end if;

  update public.caminhoneiros set status = v_status, updated_at = now() where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), p_canal, p_resultado, v_notas);

  return (select to_jsonb(c) from public.caminhoneiros c where c.id = p_lead);
end $$;
revoke all on function public.registrar_contato(uuid,text,text,text,date) from public, anon;
grant execute on function public.registrar_contato(uuid,text,text,text,date) to authenticated, service_role;

-- desfazer o "fora de área" (foi engano, ou o dono passou a trazer o veículo)
create or replace function public.desmarcar_fora_de_area(p_lead uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  update public.caminhoneiros
     set fora_de_area_em = null, fora_de_area_por = null, updated_at = now()
   where id = p_lead;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo)
  values (auth.uid(), v_unidade, 'desmarcar_fora_de_area', 'lead', p_lead,
          nullif(btrim(coalesce(p_motivo,'')),''));

  return (select to_jsonb(c) from public.caminhoneiros c where c.id = p_lead);
end $$;
revoke all on function public.desmarcar_fora_de_area(uuid,text) from public, anon;
grant execute on function public.desmarcar_fora_de_area(uuid,text) to authenticated, service_role;

-- 4. a fila ganha o terceiro balde ---------------------------------------------
-- fila + sem telefone + fora de área = régua na fila. Os três são disjuntos, e a
-- conferência (0095b) guarda essa soma.
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
           greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                    coalesce(e.fone_cls, 0)) as fone
      from public.caminhoneiros c
      left join public.empresas e on e.id = c.empresa_id
     where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
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
  from (
    select b.status, b.unidade_id, b.data_ultima_afericao,
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
      and c.fora_de_area_em is null
      and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                   coalesce(e.fone_cls, 0)) > 0
    group by 1) x;
  return v;
end $function$;
revoke all on function public.meses_de_vencimento(uuid) from public, anon;
grant execute on function public.meses_de_vencimento(uuid) to authenticated, service_role;

create index if not exists caminhoneiros_fora_de_area_idx
  on public.caminhoneiros (unidade_id) where fora_de_area_em is not null;
