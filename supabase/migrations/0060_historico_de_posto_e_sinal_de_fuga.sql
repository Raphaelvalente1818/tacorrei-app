-- [aplicada no banco em 09/09/2026 19:22 — versão 20260909192230]
-- ── 0060 — histórico de posto: a memória que hoje não existe ────────────────
--
-- `caminhoneiros.posto_afericao` é SOBRESCRITO a cada importação nova do RNTRC.
-- Hoje, quando um caminhão que era nosso aparece com posto de concorrente, o
-- valor anterior simplesmente some — e com ele a única prova de que o cliente
-- começou a ir embora.
--
-- Uma frota não abandona de uma vez: manda UM caminhão no concorrente para
-- experimentar. Saber disso na semana em que acontece dá tempo de ligar e
-- perguntar o que houve; saber quando os onze já foram é pós-morte.
--
-- Esta tabela só recebe linha quando o posto MUDA. Em base parada, ela fica
-- vazia — é de propósito: o que interessa é a transição, não o estado.

create table if not exists public.historico_posto (
  id uuid primary key default gen_random_uuid(),
  caminhoneiro_id uuid not null references public.caminhoneiros(id) on delete cascade,
  unidade_id uuid not null references public.unidades(id),
  empresa_id uuid references public.empresas(id) on delete set null,
  posto_anterior text,
  posto_novo text,
  data_anterior date,
  data_nova date,
  -- Classificação no momento da mudança. Guardada e não calculada porque a
  -- lista de postos do grupo pode mudar (uma unidade nova, uma razão social
  -- diferente) e isso reescreveria o passado.
  movimento text not null check (movimento in ('fuga','conquista','troca_concorrente','primeira_afericao')),
  detectado_em timestamptz not null default now()
);

create index if not exists idx_historico_posto_empresa on public.historico_posto (empresa_id, detectado_em desc);
create index if not exists idx_historico_posto_lead on public.historico_posto (caminhoneiro_id, detectado_em desc);
alter table public.historico_posto enable row level security;

create policy historico_posto_leitura on public.historico_posto
  for select to authenticated
  using (public.is_admin() or unidade_id = public.unidade_do_usuario());

comment on table public.historico_posto is
  'Só grava quando o posto de aferição muda. fuga = era nosso e foi para concorrente.';

-- O gatilho. Fica no banco e não na importação de propósito: qualquer caminho
-- que altere o posto — importação, tela, correção manual — passa por aqui.
create or replace function public.registra_troca_de_posto()
returns trigger language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare v_mov text; v_era_nosso boolean; v_e_nosso boolean;
begin
  -- Só interessa mudança real de posto. Data mudando sozinha é aferição normal.
  if coalesce(new.posto_afericao,'') = coalesce(old.posto_afericao,'') then
    return new;
  end if;

  v_era_nosso := public.posto_do_grupo(old.posto_afericao);
  v_e_nosso   := public.posto_do_grupo(new.posto_afericao);

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
end $function$;

drop trigger if exists trg_troca_de_posto on public.caminhoneiros;
create trigger trg_troca_de_posto
  after update of posto_afericao on public.caminhoneiros
  for each row execute function public.registra_troca_de_posto();

-- ── O painel de sinais ───────────────────────────────────────────────────────
-- Dois sinais, e eles chegam em momentos diferentes:
--   ATRASO — caminhão nosso, vencido, não voltou. Chega ANTES da fuga, quando
--            ainda dá para reagir. Não depende de importação nova.
--   FUGA   — a placa apareceu com posto de concorrente e data mais nova. É
--            prova, não suspeita, e só aparece após uma extração nova.
create or replace function public.sinais_de_fuga(p_unidade uuid default null, p_dias integer default 90)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_temp' as $function$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select coalesce(jsonb_agg(x order by x.fugas desc, x.atrasados desc, x.nome), '[]'::jsonb) into v
  from (
    select e.id, e.nome, e.situacao, e.telefone, e.contato,
           count(c.id) filter (where c.tem_tacografo) as veiculos,
           count(c.id) filter (where public.posto_do_grupo(c.posto_afericao)) as nossos,
           -- ATRASO: é nosso, já venceu, e ainda consta como nosso (não foi embora
           -- nem voltou). Quanto mais novo o vencimento, mais quente o alerta.
           count(c.id) filter (
             where public.posto_do_grupo(c.posto_afericao)
               and c.data_ultima_afericao is not null
               and (c.data_ultima_afericao + interval '2 years')::date < current_date
           ) as atrasados,
           (select count(*) from public.historico_posto h
             where h.empresa_id = e.id and h.movimento = 'fuga'
               and h.detectado_em > now() - make_interval(days => p_dias)) as fugas,
           (select max(h.detectado_em) from public.historico_posto h
             where h.empresa_id = e.id and h.movimento = 'fuga') as ultima_fuga
    from public.empresas e
    join public.caminhoneiros c on c.empresa_id = e.id
    where e.ativo
      and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())
      and (p_unidade is null or e.unidade_id = p_unidade)
    group by e.id, e.nome, e.situacao, e.telefone, e.contato
  ) x
  where x.nossos > 0 and (x.fugas > 0 or x.atrasados > 0);

  return v;
end $function$;

revoke execute on function public.sinais_de_fuga(uuid, integer) from public, anon;
revoke execute on function public.registra_troca_de_posto() from public, anon;
grant execute on function public.sinais_de_fuga(uuid, integer) to authenticated, service_role;
