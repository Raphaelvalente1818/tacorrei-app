-- 0067 — Motor de pontos
--
-- Recompensa por RESULTADO: a aferição feita no nosso posto. O ponto é gravado
-- no instante em que a aferição é registrada, porque é o único momento em que
-- o estado ANTERIOR do caminhão (posto e vencimento) ainda existe — o update
-- que registra a aferição apaga esse estado. Por isso a classificação não pode
-- ser recalculada depois: é um evento, e fica congelado em `pontos`.
--
-- Classes (o que o caminhão ERA antes de vir):
--   conquista_mista   — do concorrente, numa empresa que já tinha caminhão nosso
--   conquista_virgem  — do concorrente, numa empresa sem nenhum nosso
--   conquista_avulso  — do concorrente, autônomo (sem empresa)
--   vencido           — certificado vencido há mais que a carência, qualquer posto
--   renovacao         — já era nosso e voltou em dia
--   contrato          — frota com contrato (rotina)
--
-- Atribuição: a operadora que registrou contato no caminhão OU na empresa
-- dele nos `janela_atribuicao_dias` anteriores à data da aferição. A mais
-- recente leva. Sem contato, ninguém pontua — o caminhão veio sozinho — mas
-- a linha fica gravada, para o relatório mostrar quanto veio sem esforço.
--
-- De quebra corrige um bug antigo: `registrar_afericao` (botão Aferido da
-- ficha) não trocava o posto para o nosso. Um caminhão do concorrente aferido
-- aqui continuava contando como concorrente em todos os painéis.

-- ── 1. Posto oficial de cada unidade ─────────────────────────────────────────
-- É o texto que aparece na coluna W do RNTRC. Nunca mais fixo no código.
alter table public.unidades add column if not exists posto_afericao text;
update public.unidades set posto_afericao = 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.'
 where nome = 'Tacorrei São Bernardo' and posto_afericao is null;
update public.unidades set posto_afericao = 'LACRE CRONOTACOGRAFOS LTDA ME'
 where nome = 'Santo André' and posto_afericao is null;

-- ── 2. Parâmetros (uma linha só) ─────────────────────────────────────────────
create table if not exists public.parametros_pontos (
  id                      integer primary key default 1 check (id = 1),
  conquista_mista         integer not null default 6,
  conquista_virgem        integer not null default 5,
  conquista_avulso        integer not null default 5,
  vencido                 integer not null default 3,
  renovacao               integer not null default 2,
  contrato                integer not null default 1,
  bonus_empresa           integer not null default 15,
  janela_atribuicao_dias  integer not null default 45,
  carencia_vencido_dias   integer not null default 60,
  piso_carteira_pct       integer not null default 60,
  fator_carteira          numeric not null default 0.8,
  atualizado_em           timestamptz not null default now()
);
insert into public.parametros_pontos (id) values (1) on conflict (id) do nothing;

alter table public.parametros_pontos enable row level security;
drop policy if exists "parametros: le equipe" on public.parametros_pontos;
create policy "parametros: le equipe" on public.parametros_pontos
  for select using (public.is_equipe_ativa());
drop policy if exists "parametros: admin edita" on public.parametros_pontos;
create policy "parametros: admin edita" on public.parametros_pontos
  for update using (public.is_admin()) with check (public.is_admin());
grant select on public.parametros_pontos to authenticated;
grant update on public.parametros_pontos to authenticated;

-- ── 3. Os pontos (um evento por aferição) ────────────────────────────────────
create table if not exists public.pontos (
  id                  uuid primary key default gen_random_uuid(),
  -- a linha 'presencial/aferido' de ligacoes. Apagar a aferição apaga o ponto.
  ligacao_id          uuid not null unique references public.ligacoes(id) on delete cascade,
  caminhoneiro_id     uuid not null references public.caminhoneiros(id) on delete cascade,
  empresa_id          uuid references public.empresas(id) on delete set null,
  unidade_id          uuid not null references public.unidades(id),
  data_afericao       date not null,
  competencia         date not null,
  classe              text not null check (classe in
                        ('conquista_mista','conquista_virgem','conquista_avulso',
                         'vencido','renovacao','contrato')),
  posto_anterior      text,
  venc_anterior       date,
  empresa_conquistada boolean not null default false,
  pontos              integer not null,
  bonus               integer not null default 0,
  operadora_id        uuid,
  contato_id          uuid references public.ligacoes(id) on delete set null,
  contato_em          timestamptz,
  registrado_por      uuid,
  registrado_em       timestamptz not null default now(),
  origem              text not null default 'app' check (origem in ('app','retroativo'))
);
create index if not exists idx_pontos_unidade_comp on public.pontos (unidade_id, competencia);
create index if not exists idx_pontos_operadora_comp on public.pontos (operadora_id, competencia);
create index if not exists idx_pontos_empresa on public.pontos (empresa_id) where empresa_id is not null;

alter table public.pontos enable row level security;
drop policy if exists "pontos: le unidade" on public.pontos;
create policy "pontos: le unidade" on public.pontos
  for select using (
    public.is_equipe_ativa() and (public.is_admin() or unidade_id = public.unidade_do_usuario())
  );
-- Sem policy de escrita: só as funções SECURITY DEFINER gravam.
grant select on public.pontos to authenticated;

-- ── 4. Classificar e pontuar ─────────────────────────────────────────────────
-- Interna. Chamada pelas duas funções de registro de aferição, com o estado
-- ANTERIOR do caminhão em mãos.
create or replace function public.pontuar_afericao(
  p_lead      uuid,
  p_data      date,
  p_ligacao   uuid,
  p_posto_ant text,
  p_data_ant  date
) returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
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

  -- Empresa conquistada: primeiro caminhão de uma empresa que tinha ZERO
  -- conosco. Uma vez por empresa, para sempre.
  if v_emp is not null
     and coalesce(v_situacao, '') <> 'contrato'
     and v_nossos_antes = 0
     and not v_nosso
     and not exists (select 1 from public.pontos p
                      where p.empresa_id = v_emp and p.empresa_conquistada) then
    v_conq  := true;
    v_bonus := prm.bonus_empresa;
  end if;

  -- Atribuição: contato no caminhão ou na empresa, dentro da janela, o mais
  -- recente. As datas de contato são UTC; a data da aferição é o dia local.
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

revoke all on function public.pontuar_afericao(uuid, date, uuid, text, date) from public, anon, authenticated;
grant execute on function public.pontuar_afericao(uuid, date, uuid, text, date) to service_role;

-- ── 5. registrar_afericao (botão Aferido da ficha) ───────────────────────────
create or replace function public.registrar_afericao(
  p_lead uuid, p_data date, p_notas text default null, p_marcar_aferido boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_unidade uuid; v_posto_unidade text; v_posto_ant text; v_data_ant date;
  v_ligacao uuid; v_lead jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id, c.posto_afericao, c.data_ultima_afericao
    into v_unidade, v_posto_ant, v_data_ant
    from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;

  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;
  if p_data is not null and p_data > current_date then
    raise exception 'a data da afericao nao pode ser no futuro';
  end if;

  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  if p_marcar_aferido then
    -- Aferição de verdade: data, status E posto — a partir de agora este
    -- caminhão é nosso em todos os painéis.
    update public.caminhoneiros
       set data_ultima_afericao = p_data,
           status = 'aferido',
           posto_afericao = coalesce(v_posto_unidade, posto_afericao),
           updated_at = now()
     where id = p_lead;

    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
    values (p_lead, v_unidade, auth.uid(), 'presencial', 'aferido',
            nullif(btrim(coalesce(p_notas, '')), ''))
    returning id into v_ligacao;

    if p_data is not null then
      perform public.pontuar_afericao(p_lead, p_data, v_ligacao, v_posto_ant, v_data_ant);
    end if;
  else
    -- Só correção de data: não muda posto, não pontua.
    update public.caminhoneiros
       set data_ultima_afericao = p_data, updated_at = now()
     where id = p_lead;
  end if;

  select to_jsonb(c) into v_lead from public.caminhoneiros c where c.id = p_lead;
  return v_lead;
end $$;

revoke all on function public.registrar_afericao(uuid, date, text, boolean) from public, anon;
grant execute on function public.registrar_afericao(uuid, date, text, boolean) to authenticated, service_role;

-- ── 6. registrar_afericao_frota (botão Aferido na lista da frota) ────────────
create or replace function public.registrar_afericao_frota(
  p_lead uuid, p_data date default null, p_notas text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_unidade uuid; v_emp uuid; v_data date; v_anterior date; v_placa text;
  v_posto_ant text; v_posto_unidade text; v_ligacao uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id, c.empresa_id, c.data_ultima_afericao, c.placa_veiculo, c.posto_afericao
    into v_unidade, v_emp, v_anterior, v_placa, v_posto_ant
    from public.caminhoneiros c where c.id = p_lead;

  if v_unidade is null then raise exception 'veiculo nao encontrado'; end if;
  if v_emp is null then
    raise exception 'este veiculo nao e de frota: use o botao Aferido na ficha do lead';
  end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_data := coalesce(p_data, (now() at time zone 'America/Sao_Paulo')::date);
  if v_data > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'data no futuro (%): confira o ano', to_char(v_data, 'DD/MM/YYYY');
  end if;
  if v_anterior is not null and v_data < v_anterior then
    raise exception 'a aferição anterior é de % — uma nova não pode ser anterior a ela',
      to_char(v_anterior, 'DD/MM/YYYY');
  end if;

  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  -- Não mexe em `status` de propósito (0049): o caminhão de frota não passa
  -- pelo funil, e marcá-lo como aferido contaminaria a taxa de conversão.
  update public.caminhoneiros
     set data_ultima_afericao = v_data,
         posto_afericao = coalesce(v_posto_unidade, posto_afericao),
         updated_at = now()
   where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'presencial', 'aferido',
          coalesce(p_notas, 'Aferição registrada na lista da frota.'))
  returning id into v_ligacao;

  perform public.pontuar_afericao(p_lead, v_data, v_ligacao, v_posto_ant, v_anterior);

  return jsonb_build_object(
    'data', v_data,
    'venc', (v_data + interval '2 years')::date,
    'anterior', v_anterior,
    'placa', v_placa);
end $$;

revoke all on function public.registrar_afericao_frota(uuid, date, text) from public, anon;
grant execute on function public.registrar_afericao_frota(uuid, date, text) to authenticated, service_role;
