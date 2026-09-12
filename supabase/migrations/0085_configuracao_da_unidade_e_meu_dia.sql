-- 0085 — Configuração da unidade (aba Unidade) e "Meu dia" do gestor
--
-- Matriz de permissões (PRD, seção 8, decidida em 11/09):
--   Admin geral   → nome, posto, marca, endereço, telefone, janela, piso, cota e
--                   intervalo do WhatsApp, e a marcação "unidade edita prêmio" (itens 3, 5, 6, 9).
--   Admin unidade → só os textos variáveis das mensagens (itens 11 e 12): a linha do
--                   credenciamento, os dois convites e o texto do aviso mensal das frotas
--                   com contrato. A estrutura de quatro blocos e a porta de saída ficam
--                   fixas no código — é o que protege o número.
-- Marca e endereço saem do mapa fixo do código (LeadDetail.tsx / Empresas.tsx) e
-- passam a viver aqui: unidade nova = cadastro, não deploy.
--
-- meu_dia(unidade): as quatro perguntas da rotina de 10 minutos do gestor.
-- (No banco aplicada como 0085 + 0085b; este arquivo é a versão final.)

alter table public.unidades
  add column if not exists marca text,
  add column if not exists endereco text,
  add column if not exists telefone text,
  add column if not exists msg_credencial text,
  add column if not exists msg_convite_vencido text,
  add column if not exists msg_convite_a_vencer text,
  add column if not exists msg_aviso_contrato text;

-- O que estava no código, agora no banco (mesmos textos aprovados em 24/08).
update public.unidades set
  marca = 'Tacorrei Tacógrafos',
  endereco = 'Rua dos Feltrins, 1300, bairro Demarchi, São Bernardo/SP'
where id = '265f0c74-123e-4886-9683-b70793c30b61' and marca is null;

update public.unidades set
  marca = 'Lacre Tacógrafos',
  endereco = 'Av. dos Estados, 7050, Santo André/SP'
where id = '146237d6-5983-4986-b4bd-51f9e1d690c3' and marca is null;

-- ── configurar_unidade ──────────────────────────────────────────────────────
-- Um ponto de entrada só, que aplica a matriz. Campos fora da lista do papel são
-- recusados (não ignorados) para o erro aparecer na tela em vez de sumir.
create or replace function public.configurar_unidade(p_unidade uuid, p_campos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k text;
  v_admin boolean; v_gestor boolean;
  v_geral text[] := array['nome','posto_afericao','marca','endereco','telefone',
                          'janela_dias','piso_dias','limite_whatsapp_dia','intervalo_whatsapp_min',
                          'cooldown_telefone_dias','agrupamento_dias','unidade_edita_premio'];
  v_msgs  text[] := array['msg_credencial','msg_convite_vencido','msg_convite_a_vencer','msg_aviso_contrato'];
  v_txt text; v_int integer;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_admin  := public.is_admin();
  v_gestor := public.is_admin_unidade() and p_unidade = public.unidade_do_usuario();
  if not (v_admin or v_gestor) then raise exception 'acesso negado'; end if;
  if p_campos is null or jsonb_typeof(p_campos) <> 'object' then raise exception 'campos invalidos'; end if;
  if not exists (select 1 from public.unidades where id = p_unidade) then raise exception 'unidade nao encontrada'; end if;

  for k in select jsonb_object_keys(p_campos) loop
    if k = any(v_msgs) then
      v_txt := nullif(btrim(p_campos->>k), '');
      if length(coalesce(v_txt, '')) > 240 then
        raise exception 'texto de % passa de 240 caracteres', k;
      end if;
      execute format('update public.unidades set %I = $1 where id = $2', k) using v_txt, p_unidade;

    elsif k = any(v_geral) then
      if not v_admin then
        raise exception 'acesso negado: % e configurado pelo admin geral', k;
      end if;
      if k in ('nome','posto_afericao','marca','endereco','telefone') then
        v_txt := nullif(btrim(p_campos->>k), '');
        if k = 'nome' and v_txt is null then raise exception 'nome obrigatorio'; end if;
        if length(coalesce(v_txt, '')) > 200 then raise exception '% muito longo', k; end if;
        execute format('update public.unidades set %I = $1 where id = $2', k) using v_txt, p_unidade;
      elsif k = 'unidade_edita_premio' then
        execute 'update public.unidades set unidade_edita_premio = $1 where id = $2'
          using coalesce((p_campos->>k)::boolean, false), p_unidade;
      else
        v_int := (p_campos->>k)::integer;
        if k = 'janela_dias' and v_int is not null and (v_int < 1 or v_int > 3650) then raise exception 'janela entre 1 e 3650 dias (ou vazia = base toda)'; end if;
        if k = 'piso_dias' and (v_int is null or v_int < 30 or v_int > 3650) then raise exception 'piso entre 30 e 3650 dias'; end if;
        if k = 'limite_whatsapp_dia' and (v_int is null or v_int < 1 or v_int > 500) then raise exception 'cota entre 1 e 500 por dia'; end if;
        if k = 'intervalo_whatsapp_min' and (v_int is null or v_int < 0 or v_int > 120) then raise exception 'intervalo entre 0 e 120 minutos'; end if;
        if k = 'cooldown_telefone_dias' and (v_int is null or v_int < 0 or v_int > 365) then raise exception 'cooldown entre 0 e 365 dias'; end if;
        if k = 'agrupamento_dias' and (v_int is null or v_int < 0 or v_int > 365) then raise exception 'agrupamento entre 0 e 365 dias'; end if;
        execute format('update public.unidades set %I = $1 where id = $2', k) using v_int, p_unidade;
      end if;
    else
      raise exception 'campo desconhecido: %', k;
    end if;
  end loop;

  return (select to_jsonb(u) from public.unidades u where u.id = p_unidade);
end $$;

revoke all on function public.configurar_unidade(uuid, jsonb) from public, anon;
grant execute on function public.configurar_unidade(uuid, jsonb) to authenticated, service_role;

-- ── configuracao_unidade ────────────────────────────────────────────────────
-- Tudo que a aba Unidade mostra, numa chamada: a unidade, as cidades e o histórico
-- de parâmetros do prêmio. Gestor vê a dele; admin vê qualquer uma.
create or replace function public.configuracao_unidade(p_unidade uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or p_unidade = public.unidade_do_usuario()) then raise exception 'acesso negado'; end if;
  return jsonb_build_object(
    'unidade', (select to_jsonb(u) from public.unidades u where u.id = p_unidade),
    'cidades', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'cidade', c.cidade) order by c.cidade)
                           from public.unidade_cidades c where c.unidade_id = p_unidade), '[]'::jsonb),
    'premios', coalesce((select jsonb_agg(jsonb_build_object(
                             'id', p.id, 'vigencia', p.vigencia, 'valor_ponto', p.valor_ponto,
                             'teto_mes', p.teto_mes, 'pct_bolo', p.pct_bolo, 'observacao', p.observacao,
                             'criado_em', p.criado_em,
                             'criado_por', (select e.nome from public.equipe e where e.user_id = p.criado_por))
                           order by p.vigencia desc)
                           from public.parametros_unidade p where p.unidade_id = p_unidade), '[]'::jsonb),
    'pode_editar_premio', public.is_admin()
                          or (public.is_admin_unidade()
                              and (select u.unidade_edita_premio from public.unidades u where u.id = p_unidade))
  );
end $$;

revoke all on function public.configuracao_unidade(uuid) from public, anon;
grant execute on function public.configuracao_unidade(uuid) to authenticated, service_role;

-- ── meu_dia ─────────────────────────────────────────────────────────────────
-- As quatro perguntas do gestor (manual do gestor, rotina de 10 minutos):
--   1. Quantos pontos cada operadora fez até ontem?
--   2. Quais empresas "pé na porta" estão sem contato há mais de 7 dias?
--   3. Quantos "Novo" ainda restam na fila do mês?
--   4. O que foi marcado como aferido ontem — confere com as ordens de serviço?
create or replace function public.meu_dia(p_unidade uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_comp date := date_trunc('month', current_date)::date;
  v_fim  date := (date_trunc('month', current_date) + interval '1 month')::date;
  v_pontos jsonb; v_pe jsonb; v_novos jsonb; v_ontem jsonb; v_painel jsonb; v_pe_total integer;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then
    raise exception 'acesso negado';
  end if;

  -- 1. Pontos no mês por operadora (só os que têm dona), e quantos foram ontem.
  select coalesce(jsonb_agg(to_jsonb(r) order by r.pontos desc, r.nome), '[]'::jsonb) into v_pontos
  from (
    select e.nome, e.user_id as operadora_id,
           coalesce(sum(p.pontos + p.bonus), 0)::int as pontos,
           coalesce(sum(p.pontos + p.bonus) filter (where p.data_afericao = current_date - 1), 0)::int as ontem,
           count(p.id)::int as afericoes
    from public.equipe e
    left join public.pontos p on p.operadora_id = e.user_id and p.unidade_id = p_unidade and p.competencia = v_comp
    where e.unidade_id = p_unidade and e.ativo and e.papel = 'operador'
    group by e.nome, e.user_id
  ) r;

  -- 2. Pé na porta (empresa mista com caminhão do concorrente vencendo em 90 dias)
  --    sem abordagem há mais de 7 dias.
  v_painel := public.empresas_painel(p_unidade, null);
  -- Quantas pé na porta têm caminhão vencendo em 90 dias (0085b: para a tela saber se
  -- "nenhuma pendente" quer dizer "todas abordadas" ou "não existe nenhuma").
  select count(*) into v_pe_total
  from jsonb_array_elements(v_painel) x
  where x->>'classe' = 'mista' and (x->>'janela')::int > 0;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x->>'id', 'nome', x->>'nome', 'janela', (x->>'janela')::int,
           'ultima_abordagem', x->>'ultima_abordagem')
           order by (x->>'janela')::int desc, x->>'nome'), '[]'::jsonb) into v_pe
  from jsonb_array_elements(v_painel) x
  where x->>'classe' = 'mista'
    and (x->>'janela')::int > 0
    and (x->>'ultima_abordagem' is null or (x->>'ultima_abordagem')::timestamptz < now() - interval '7 days');

  -- 3. "Novo" que ainda restam na fila deste mês (vence no mês ou já venceu, sem contato).
  select jsonb_build_object(
           'novos', count(*) filter (where b.status = 'novo'),
           'total', count(*)
         ) into v_novos
  from public.base_trabalhavel(p_unidade) b
  where b.na_fila and b.venc < v_fim;

  -- 4. Aferidos marcados ontem (pela data da aferição) — para bater com a OS.
  select coalesce(jsonb_agg(jsonb_build_object(
           'placa', c.placa_veiculo, 'dono', c.nome, 'empresa', e.nome,
           'operadora', (select q.nome from public.equipe q where q.user_id = p.operadora_id),
           'marcado_por', (select q.nome from public.equipe q where q.user_id = p.registrado_por),
           'total', p.pontos + p.bonus)
           order by c.placa_veiculo), '[]'::jsonb) into v_ontem
  from public.pontos p
  join public.caminhoneiros c on c.id = p.caminhoneiro_id
  left join public.empresas e on e.id = p.empresa_id
  where p.unidade_id = p_unidade and p.data_afericao = current_date - 1;

  return jsonb_build_object(
    'hoje', current_date,
    'competencia', v_comp,
    'pontos', v_pontos,
    'pe_na_porta', v_pe,
    'pe_na_porta_total', v_pe_total,
    'fila', v_novos,
    'aferidos_ontem', v_ontem
  );
end $$;

revoke all on function public.meu_dia(uuid) from public, anon;
grant execute on function public.meu_dia(uuid) to authenticated, service_role;
