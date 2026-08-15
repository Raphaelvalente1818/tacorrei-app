-- 0005: multi-unidade com isolamento por RLS. Base única; cada unidade só vê o que é dela.
-- Admin (papel='admin') vê todas as unidades. Dados existentes -> "Santo André".
-- Aplicada em 15/08/2026. App NÃO precisa de redeploy: os triggers preenchem unidade_id.

create table if not exists public.unidades (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  created_at timestamptz not null default now()
);

insert into public.unidades (nome) values ('Santo André') on conflict (nome) do nothing;

alter table public.equipe        add column if not exists unidade_id uuid references public.unidades(id);
alter table public.caminhoneiros add column if not exists unidade_id uuid references public.unidades(id);
alter table public.ligacoes      add column if not exists unidade_id uuid references public.unidades(id);
alter table public.agendamentos  add column if not exists unidade_id uuid references public.unidades(id);

-- backfill: tudo que já existe fica em Santo André
update public.equipe        set unidade_id = (select id from public.unidades where nome='Santo André') where unidade_id is null;
update public.caminhoneiros set unidade_id = (select id from public.unidades where nome='Santo André') where unidade_id is null;
update public.ligacoes      set unidade_id = (select id from public.unidades where nome='Santo André') where unidade_id is null;
update public.agendamentos  set unidade_id = (select id from public.unidades where nome='Santo André') where unidade_id is null;

-- garante que Raphael e Emerson sejam admin (veem todas as unidades)
update public.equipe e set papel = 'admin'
  from auth.users u
  where e.user_id = u.id
    and u.email in ('emerson1001@gmail.com','raphaelvalentegomes@hotmail.com');

alter table public.caminhoneiros alter column unidade_id set not null;
alter table public.ligacoes      alter column unidade_id set not null;
alter table public.agendamentos  alter column unidade_id set not null;

create index if not exists idx_caminhoneiros_unidade on public.caminhoneiros(unidade_id);
create index if not exists idx_ligacoes_unidade on public.ligacoes(unidade_id);
create index if not exists idx_agendamentos_unidade on public.agendamentos(unidade_id);

-- helpers (SECURITY DEFINER: ignoram RLS, sem recursão)
create or replace function public.unidade_do_usuario()
returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $$
  select unidade_id from public.equipe where user_id = auth.uid() and ativo = true limit 1;
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$
  select exists (select 1 from public.equipe where user_id = auth.uid() and ativo = true and papel = 'admin');
$$;

-- triggers: preenchem unidade_id sozinhos no insert (app não precisa mudar)
create or replace function public.set_unidade_caminhoneiro()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if new.unidade_id is null then new.unidade_id := public.unidade_do_usuario(); end if;
  return new;
end; $$;

create or replace function public.set_unidade_filho()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if new.unidade_id is null then
    new.unidade_id := (select unidade_id from public.caminhoneiros where id = new.caminhoneiro_id);
  end if;
  return new;
end; $$;

drop trigger if exists trg_unidade_caminhoneiro on public.caminhoneiros;
create trigger trg_unidade_caminhoneiro before insert on public.caminhoneiros
  for each row execute function public.set_unidade_caminhoneiro();

drop trigger if exists trg_unidade_ligacao on public.ligacoes;
create trigger trg_unidade_ligacao before insert on public.ligacoes
  for each row execute function public.set_unidade_filho();

drop trigger if exists trg_unidade_agendamento on public.agendamentos;
create trigger trg_unidade_agendamento before insert on public.agendamentos
  for each row execute function public.set_unidade_filho();

-- RLS caminhoneiros
drop policy if exists "caminhoneiros: equipe ativa lê" on public.caminhoneiros;
drop policy if exists "caminhoneiros: equipe ativa insere" on public.caminhoneiros;
drop policy if exists "caminhoneiros: equipe ativa atualiza" on public.caminhoneiros;
create policy "caminhoneiros: le unidade" on public.caminhoneiros for select
  using (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));
create policy "caminhoneiros: insere unidade" on public.caminhoneiros for insert
  with check (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));
create policy "caminhoneiros: atualiza unidade" on public.caminhoneiros for update
  using (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()))
  with check (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));

-- RLS ligacoes
drop policy if exists "ligacoes: equipe ativa lê" on public.ligacoes;
drop policy if exists "ligacoes: equipe ativa insere" on public.ligacoes;
drop policy if exists "ligacoes: equipe ativa exclui" on public.ligacoes;
create policy "ligacoes: le unidade" on public.ligacoes for select
  using (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));
create policy "ligacoes: insere unidade" on public.ligacoes for insert
  with check (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));
create policy "ligacoes: exclui unidade" on public.ligacoes for delete
  using (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));

-- RLS agendamentos
drop policy if exists "agendamentos: equipe ativa lê" on public.agendamentos;
drop policy if exists "agendamentos: equipe ativa insere" on public.agendamentos;
drop policy if exists "agendamentos: equipe ativa atualiza" on public.agendamentos;
create policy "agendamentos: le unidade" on public.agendamentos for select
  using (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));
create policy "agendamentos: insere unidade" on public.agendamentos for insert
  with check (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));
create policy "agendamentos: atualiza unidade" on public.agendamentos for update
  using (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()))
  with check (is_equipe_ativa() and (is_admin() or unidade_id = unidade_do_usuario()));

-- RLS unidades: equipe ativa lê; só admin cria/edita
alter table public.unidades enable row level security;
drop policy if exists "unidades: equipe ativa lê" on public.unidades;
create policy "unidades: equipe ativa lê" on public.unidades for select using (is_equipe_ativa());
drop policy if exists "unidades: admin insere" on public.unidades;
create policy "unidades: admin insere" on public.unidades for insert with check (is_admin());
drop policy if exists "unidades: admin atualiza" on public.unidades;
create policy "unidades: admin atualiza" on public.unidades for update using (is_admin()) with check (is_admin());

-- equipe: admin pode ler todos (gestão futura); mantém "ver o próprio registro"
drop policy if exists "equipe: admin lê todos" on public.equipe;
create policy "equipe: admin lê todos" on public.equipe for select using (is_admin());
