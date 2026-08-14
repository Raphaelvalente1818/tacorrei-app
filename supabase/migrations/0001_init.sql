-- App Tacógrafo — schema inicial
-- Gestão de ligações para atrair caminhoneiros para aferição do tacógrafo.

create extension if not exists pgcrypto;

-- ============================================================
-- Equipe (usuários internos que usam o painel)
-- ============================================================
create table if not exists equipe (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  papel text not null default 'operador' check (papel in ('admin', 'operador')),
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table equipe is 'Membros da equipe interna com acesso ao painel. Preencher manualmente após o primeiro login (auth.users -> equipe).';

-- ============================================================
-- Caminhoneiros (leads)
-- ============================================================
create table if not exists caminhoneiros (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  telefone text not null,
  telefone_e164 text,
  cidade text,
  uf char(2),
  placa_veiculo text,
  modelo_veiculo text,
  origem text not null default 'outro' check (
    origem in ('indicacao', 'campanha', 'cold_call', 'site', 'whatsapp', 'outro')
  ),
  status text not null default 'novo' check (
    status in ('novo', 'contatado', 'sem_resposta', 'agendado', 'aferido', 'recusado', 'invalido')
  ),
  observacoes text,
  responsavel_id uuid references equipe(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_caminhoneiros_status on caminhoneiros(status);
create index if not exists idx_caminhoneiros_responsavel on caminhoneiros(responsavel_id);
create index if not exists idx_caminhoneiros_created_at on caminhoneiros(created_at desc);

comment on table caminhoneiros is 'Leads de caminhoneiros a serem contatados para aferição do tacógrafo.';

-- ============================================================
-- Ligações (histórico de contatos)
-- ============================================================
create table if not exists ligacoes (
  id uuid primary key default gen_random_uuid(),
  caminhoneiro_id uuid not null references caminhoneiros(id) on delete cascade,
  operador_id uuid references equipe(user_id) on delete set null,
  resultado text not null check (
    resultado in ('atendeu', 'nao_atendeu', 'numero_invalido', 'recusou', 'agendou', 'reagendar')
  ),
  duracao_segundos int,
  notas text,
  proxima_acao_em timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_ligacoes_caminhoneiro on ligacoes(caminhoneiro_id);
create index if not exists idx_ligacoes_created_at on ligacoes(created_at desc);

comment on table ligacoes is 'Histórico de ligações feitas para cada caminhoneiro.';

-- ============================================================
-- Agendamentos (aferição do tacógrafo)
-- ============================================================
create table if not exists agendamentos (
  id uuid primary key default gen_random_uuid(),
  caminhoneiro_id uuid not null references caminhoneiros(id) on delete cascade,
  ligacao_id uuid references ligacoes(id) on delete set null,
  data_hora timestamptz not null,
  local text,
  status text not null default 'agendado' check (
    status in ('agendado', 'confirmado', 'realizado', 'cancelado', 'nao_compareceu')
  ),
  observacoes text,
  created_by uuid references equipe(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_agendamentos_caminhoneiro on agendamentos(caminhoneiro_id);
create index if not exists idx_agendamentos_data_hora on agendamentos(data_hora);
create index if not exists idx_agendamentos_status on agendamentos(status);

comment on table agendamentos is 'Agendamentos de aferição do tacógrafo.';

-- ============================================================
-- updated_at automático
-- ============================================================
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_caminhoneiros_updated_at on caminhoneiros;
create trigger trg_caminhoneiros_updated_at
  before update on caminhoneiros
  for each row execute function set_updated_at();

drop trigger if exists trg_agendamentos_updated_at on agendamentos;
create trigger trg_agendamentos_updated_at
  before update on agendamentos
  for each row execute function set_updated_at();

-- ============================================================
-- RLS — acesso restrito a membros ativos da equipe
-- ============================================================
alter table equipe enable row level security;
alter table caminhoneiros enable row level security;
alter table ligacoes enable row level security;
alter table agendamentos enable row level security;

create or replace function is_equipe_ativa()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from equipe where user_id = auth.uid() and ativo = true
  );
$$;

create policy "equipe: ver o próprio registro" on equipe
  for select using (user_id = auth.uid());

create policy "caminhoneiros: equipe ativa lê" on caminhoneiros
  for select using (is_equipe_ativa());
create policy "caminhoneiros: equipe ativa insere" on caminhoneiros
  for insert with check (is_equipe_ativa());
create policy "caminhoneiros: equipe ativa atualiza" on caminhoneiros
  for update using (is_equipe_ativa());

create policy "ligacoes: equipe ativa lê" on ligacoes
  for select using (is_equipe_ativa());
create policy "ligacoes: equipe ativa insere" on ligacoes
  for insert with check (is_equipe_ativa());

create policy "agendamentos: equipe ativa lê" on agendamentos
  for select using (is_equipe_ativa());
create policy "agendamentos: equipe ativa insere" on agendamentos
  for insert with check (is_equipe_ativa());
create policy "agendamentos: equipe ativa atualiza" on agendamentos
  for update using (is_equipe_ativa());
