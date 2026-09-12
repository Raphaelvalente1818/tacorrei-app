-- 0088 — Suspender unidade (item 19), correções com registro (16–18) e trilha de acessos (20)
--
-- Fecha o bloco P0 da matriz de permissões (PRD, seção 8):
--   19. suspender_unidade(unidade, suspender, motivo) — admin geral. Logins da unidade
--       bloqueados (is_equipe_ativa() passa a olhar unidades.suspensa_em); dados intactos;
--       reativar é a mesma função.
--   16. apagar_contato_empresa(ligacao, motivo) — admin geral ou gestor da unidade. Só
--       contato lançado NA EMPRESA (a ficha da placa já apaga o próprio). Recusa se o
--       contato já trouxe uma aferição pontuada.
--   17. desfazer_afericao(lead, motivo) — desfaz o último "Aferido": volta data e posto
--       anteriores (guardados no ponto), apaga a ligação (o ponto cai junto) e a linha do
--       histórico de posto que a aferição criou. Mês fechado: só admin geral.
--   18. mudança de situação da empresa (prospecto ↔ contrato) fica registrada por gatilho.
--   20. trilha_acessos(dias) — quem listou, buscou e abriu o quê (sobre acessos_lead).
-- Tudo o que corrige deixa linha em `correcoes` (quem, quando, o quê, como estava).
-- Toda deleção tem confirmação na tela (pedido do Emerson, 12/09) — e aqui, registro.

-- ── registro ────────────────────────────────────────────────────────────────
create table if not exists public.correcoes (
  id uuid primary key default gen_random_uuid(),
  quando timestamptz not null default now(),
  quem uuid,
  unidade_id uuid,
  acao text not null,
  alvo_tipo text,
  alvo_id uuid,
  motivo text,
  detalhe jsonb
);
create index if not exists idx_correcoes_unidade_quando on public.correcoes (unidade_id, quando desc);
alter table public.correcoes enable row level security;
drop policy if exists "correcoes: admin le tudo, gestor le a unidade" on public.correcoes;
create policy "correcoes: admin le tudo, gestor le a unidade" on public.correcoes
  for select using (public.is_admin() or (public.is_admin_unidade() and unidade_id = public.unidade_do_usuario()));
revoke all on public.correcoes from anon, authenticated;
grant select on public.correcoes to authenticated;

-- ── 19. suspender ───────────────────────────────────────────────────────────
alter table public.unidades add column if not exists suspensa_em timestamptz;

-- O portão de tudo: equipe ativa E unidade não suspensa. Admin geral não tem unidade.
create or replace function public.is_equipe_ativa()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.equipe e
      left join public.unidades u on u.id = e.unidade_id
     where e.user_id = auth.uid() and e.ativo = true
       and (u.id is null or u.suspensa_em is null)
  );
$$;

create or replace function public.suspender_unidade(p_unidade uuid, p_suspender boolean, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_antes timestamptz; v_nome text;
begin
  if not public.is_admin() then raise exception 'acesso negado: so o admin geral suspende ou reativa unidade'; end if;
  select suspensa_em, nome into v_antes, v_nome from public.unidades where id = p_unidade;
  if v_nome is null then raise exception 'unidade nao encontrada'; end if;
  if p_suspender and v_antes is not null then raise exception 'a unidade % ja esta suspensa', v_nome; end if;
  if not p_suspender and v_antes is null then raise exception 'a unidade % nao esta suspensa', v_nome; end if;

  update public.unidades set suspensa_em = case when p_suspender then now() else null end where id = p_unidade;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo, detalhe)
  values (auth.uid(), p_unidade, case when p_suspender then 'suspender_unidade' else 'reativar_unidade' end,
          'unidade', p_unidade, nullif(btrim(coalesce(p_motivo,'')), ''),
          jsonb_build_object('nome', v_nome, 'suspensa_em_antes', v_antes));

  return (select to_jsonb(u) from public.unidades u where u.id = p_unidade);
end $$;
revoke all on function public.suspender_unidade(uuid, boolean, text) from public, anon;
grant execute on function public.suspender_unidade(uuid, boolean, text) to authenticated, service_role;

-- ── 16. apagar contato de empresa ───────────────────────────────────────────
create or replace function public.apagar_contato_empresa(p_ligacao uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare l record; v_pontos int;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select * into l from public.ligacoes where id = p_ligacao;
  if l.id is null then raise exception 'contato nao encontrado'; end if;
  if l.empresa_id is null then raise exception 'este contato e de uma placa, nao da empresa: apague pela ficha do caminhao'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and l.unidade_id = public.unidade_do_usuario())) then
    raise exception 'acesso negado: so o gestor da unidade ou o admin geral apaga contato de empresa';
  end if;
  select count(*) into v_pontos from public.pontos p where p.contato_id = p_ligacao;
  if v_pontos > 0 then
    raise exception 'este contato ja trouxe % afericao(oes) pontuada(s); nao pode ser apagado', v_pontos;
  end if;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo, detalhe)
  values (auth.uid(), l.unidade_id, 'apagar_contato_empresa', 'ligacao', p_ligacao,
          nullif(btrim(coalesce(p_motivo,'')), ''), to_jsonb(l));

  delete from public.ligacoes where id = p_ligacao;
  return jsonb_build_object('ok', true, 'empresa_id', l.empresa_id);
end $$;
revoke all on function public.apagar_contato_empresa(uuid, text) from public, anon;
grant execute on function public.apagar_contato_empresa(uuid, text) to authenticated, service_role;

-- ── 17. desfazer aferição ───────────────────────────────────────────────────
-- O gatilho de troca de posto pula quando esta chave está ligada: desfazer não é
-- movimento de mercado, é correção — e a linha que a aferição criou é apagada.
create or replace function public.registra_troca_de_posto()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_mov text; v_era_nosso boolean; v_e_nosso boolean;
begin
  if current_setting('aferimais.sem_historico', true) = '1' then return new; end if;
  if coalesce(new.posto_afericao,'') = coalesce(old.posto_afericao,'') then
    return new;
  end if;

  v_era_nosso := public.posto_do_grupo(old.posto_afericao, new.unidade_id);
  v_e_nosso   := public.posto_do_grupo(new.posto_afericao, new.unidade_id);

  v_mov := case
    when old.posto_afericao is null then 'primeira_afericao'
    when v_era_nosso and not v_e_nosso then 'fuga'
    when not v_era_nosso and v_e_nosso then 'conquista'
    else 'troca_concorrente'
  end;

  insert into public.historico_posto
    (caminhoneiro_id, unidade_id, empresa_id, posto_anterior, posto_novo,
     data_anterior, data_nova, movimento)
  values (new.id, new.unidade_id, new.empresa_id, old.posto_afericao, new.posto_afericao,
          old.data_ultima_afericao, new.data_ultima_afericao, v_mov);

  return new;
end $$;

create or replace function public.desfazer_afericao(p_lead uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c record; l record; p record;
  v_data_ant date; v_posto_ant text; v_status text; v_hist int;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select * into c from public.caminhoneiros where id = p_lead;
  if c.id is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or (public.is_admin_unidade() and c.unidade_id = public.unidade_do_usuario())) then
    raise exception 'acesso negado: so o gestor da unidade ou o admin geral desfaz uma afericao';
  end if;

  -- A última aferição marcada no app (a ligação presencial/aferido mais recente).
  select * into l from public.ligacoes
   where caminhoneiro_id = p_lead and canal = 'presencial' and resultado = 'aferido'
   order by created_at desc limit 1;
  if l.id is null then raise exception 'este caminhao nao tem afericao marcada pelo app para desfazer'; end if;

  select * into p from public.pontos where ligacao_id = l.id;
  if p.id is not null then
    if public.competencia_fechada(c.unidade_id, p.data_afericao) and not public.is_admin() then
      raise exception 'o mes de % ja esta fechado: so o admin geral desfaz', to_char(p.data_afericao, 'MM/YYYY');
    end if;
    v_posto_ant := p.posto_anterior;
    v_data_ant  := case when p.venc_anterior is null then null else (p.venc_anterior - interval '2 years')::date end;
  else
    -- Aferição sem ponto (registrada sem data, ou anterior ao motor): usa o histórico de posto.
    select h.posto_anterior, h.data_anterior into v_posto_ant, v_data_ant
      from public.historico_posto h
     where h.caminhoneiro_id = p_lead and h.detectado_em >= l.created_at - interval '1 minute'
     order by h.detectado_em asc limit 1;
    if not found then
      v_posto_ant := c.posto_afericao; v_data_ant := null;
    end if;
  end if;

  v_status := case when exists (select 1 from public.ligacoes x
                                 where x.caminhoneiro_id = p_lead and x.id <> l.id
                                   and x.canal in ('ligacao_ativa','ligacao_passiva','whatsapp'))
                   then 'contatado' else 'novo' end;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo, detalhe)
  values (auth.uid(), c.unidade_id, 'desfazer_afericao', 'caminhoneiro', p_lead,
          nullif(btrim(coalesce(p_motivo,'')), ''),
          jsonb_build_object('placa', c.placa_veiculo, 'ligacao', to_jsonb(l), 'ponto', to_jsonb(p),
                             'data_antes', c.data_ultima_afericao, 'posto_antes', c.posto_afericao,
                             'status_antes', c.status, 'volta_para',
                             jsonb_build_object('data', v_data_ant, 'posto', v_posto_ant, 'status', v_status)));

  -- A linha do histórico de posto que a aferição criou sai; o gatilho fica calado.
  delete from public.historico_posto h
   where h.caminhoneiro_id = p_lead
     and h.detectado_em >= l.created_at - interval '1 minute'
     and h.detectado_em <= l.created_at + interval '1 minute';
  get diagnostics v_hist = row_count;

  perform set_config('aferimais.sem_historico', '1', true);
  update public.caminhoneiros
     set data_ultima_afericao = v_data_ant,
         posto_afericao = v_posto_ant,
         status = v_status,
         tem_tacografo = case when v_data_ant is null then tem_tacografo else true end,
         updated_at = now()
   where id = p_lead;
  perform set_config('aferimais.sem_historico', '0', true);

  delete from public.ligacoes where id = l.id;   -- o ponto cai junto (FK on delete cascade)

  return jsonb_build_object('ok', true, 'data', v_data_ant, 'posto', v_posto_ant, 'status', v_status,
                            'pontos_removidos', (p.id is not null), 'historico_removido', v_hist);
end $$;
revoke all on function public.desfazer_afericao(uuid, text) from public, anon;
grant execute on function public.desfazer_afericao(uuid, text) to authenticated, service_role;

-- ── 18. situação da empresa: registro por gatilho ───────────────────────────
create or replace function public.registra_situacao_empresa()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(new.situacao,'') <> coalesce(old.situacao,'') then
    insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, detalhe)
    values (auth.uid(), new.unidade_id, 'situacao_empresa', 'empresa', new.id,
            jsonb_build_object('empresa', new.nome, 'de', old.situacao, 'para', new.situacao));
  end if;
  return new;
end $$;
drop trigger if exists trg_situacao_empresa on public.empresas;
create trigger trg_situacao_empresa after update of situacao on public.empresas
  for each row execute function public.registra_situacao_empresa();

-- ── 20. trilha de acessos e registro de correções para a tela ───────────────
create or replace function public.trilha_acessos(p_dias integer default 7, p_unidade uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_resumo jsonb; v_ultimos jsonb; v_corr jsonb;
begin
  if not public.is_admin() then raise exception 'acesso negado: a trilha e do admin geral'; end if;

  -- Por pessoa e dia: quantas listagens (e quantos leads vistos), buscas por placa, fichas abertas.
  select coalesce(jsonb_agg(to_jsonb(r) order by r.dia desc, r.nome), '[]'::jsonb) into v_resumo
  from (
    select (a.criado_em at time zone 'America/Sao_Paulo')::date as dia,
           coalesce(e.nome, 'usuário removido') as nome, e.papel,
           (select u.nome from public.unidades u where u.id = e.unidade_id) as unidade,
           count(*) filter (where a.acao = 'listar') as listagens,
           coalesce(sum(a.quantidade) filter (where a.acao = 'listar'), 0)::int as leads_listados,
           count(*) filter (where a.acao = 'placa') as buscas_placa,
           count(*) filter (where a.acao = 'abrir') as fichas_abertas,
           min(a.criado_em) as primeiro, max(a.criado_em) as ultimo
      from public.acessos_lead a
      left join public.equipe e on e.user_id = a.user_id
     where a.criado_em > now() - make_interval(days => coalesce(p_dias, 7))
       and (p_unidade is null or e.unidade_id = p_unidade)
     group by 1, 2, 3, e.unidade_id
  ) r;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.criado_em desc), '[]'::jsonb) into v_ultimos
  from (
    select a.criado_em, coalesce(e.nome, 'usuário removido') as nome, a.acao, a.quantidade, a.detalhe
      from public.acessos_lead a
      left join public.equipe e on e.user_id = a.user_id
     where (p_unidade is null or e.unidade_id = p_unidade)
     order by a.criado_em desc limit 100
  ) r;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.quando desc), '[]'::jsonb) into v_corr
  from (
    select c.quando, coalesce(e.nome, '—') as quem, c.acao, c.alvo_tipo, c.alvo_id, c.motivo, c.detalhe,
           (select u.nome from public.unidades u where u.id = c.unidade_id) as unidade
      from public.correcoes c
      left join public.equipe e on e.user_id = c.quem
     where (p_unidade is null or c.unidade_id = p_unidade)
     order by c.quando desc limit 100
  ) r;

  return jsonb_build_object('dias', coalesce(p_dias, 7), 'resumo', v_resumo, 'ultimos', v_ultimos, 'correcoes', v_corr);
end $$;
revoke all on function public.trilha_acessos(integer, uuid) from public, anon;
grant execute on function public.trilha_acessos(integer, uuid) to authenticated, service_role;

-- Gestor vê as correções da própria unidade (para o "quem apagou o quê" do dia a dia).
create or replace function public.correcoes_da_unidade(p_unidade uuid, p_limite integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when not (public.is_admin() or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario())) then null else
    coalesce((select jsonb_agg(to_jsonb(r) order by r.quando desc)
              from (select c.quando, coalesce(e.nome, '—') as quem, c.acao, c.alvo_tipo, c.alvo_id, c.motivo, c.detalhe
                      from public.correcoes c left join public.equipe e on e.user_id = c.quem
                     where c.unidade_id = p_unidade
                     order by c.quando desc limit least(coalesce(p_limite, 50), 200)) r), '[]'::jsonb) end
$$;
revoke all on function public.correcoes_da_unidade(uuid, integer) from public, anon;
grant execute on function public.correcoes_da_unidade(uuid, integer) to authenticated, service_role;
