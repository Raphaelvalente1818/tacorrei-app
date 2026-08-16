-- Cobertura (territorio): liga cidades a uma unidade + janela por unidade (30/60 dias ou base toda).

-- Janela por unidade: 30/60 dias ou NULL = base toda. Novas unidades nascem com 30.
alter table public.unidades
  add column if not exists janela_dias integer default 30
  check (janela_dias is null or janela_dias in (30, 60));

-- Nao mudar o comportamento atual da unidade de producao (Santo Andre segue "base toda").
update public.unidades set janela_dias = null where nome = 'Santo André';

-- Cobertura: cidades atendidas por cada unidade. Cada cidade pertence a UMA unidade.
create table if not exists public.unidade_cidades (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidades(id) on delete cascade,
  cidade text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists unidade_cidades_cidade_uidx
  on public.unidade_cidades (lower(cidade));

alter table public.unidade_cidades enable row level security;

drop policy if exists "cobertura: equipe le" on public.unidade_cidades;
create policy "cobertura: equipe le" on public.unidade_cidades
  for select using (public.is_equipe_ativa());

drop policy if exists "cobertura: admin gerencia" on public.unidade_cidades;
create policy "cobertura: admin gerencia" on public.unidade_cidades
  for all using (public.is_admin()) with check (public.is_admin());

-- Janela (dias) da unidade do usuario logado. NULL = base toda.
create or replace function public.janela_do_usuario()
returns integer language sql stable security definer
set search_path to 'public','pg_temp' as $$
  select u.janela_dias
  from public.equipe e join public.unidades u on u.id = e.unidade_id
  where e.user_id = auth.uid() and e.ativo = true
  limit 1;
$$;

-- No insert, se a unidade nao vier, atribui pela cidade (mapa de cobertura); senao, unidade do usuario.
create or replace function public.set_unidade_caminhoneiro()
returns trigger language plpgsql security definer
set search_path to 'public','pg_temp' as $$
begin
  if new.unidade_id is null then
    if new.cidade is not null then
      select uc.unidade_id into new.unidade_id
      from public.unidade_cidades uc
      where lower(uc.cidade) = lower(new.cidade)
      limit 1;
    end if;
    if new.unidade_id is null then
      new.unidade_id := public.unidade_do_usuario();
    end if;
  end if;
  return new;
end; $$;

-- Re-sincronizar leads existentes conforme o mapa de cobertura (uso deliberado do admin).
create or replace function public.resync_cobertura()
returns integer language plpgsql security definer
set search_path to 'public','pg_temp' as $$
declare n integer;
begin
  if not public.is_admin() then
    raise exception 'apenas admin';
  end if;
  update public.caminhoneiros c
     set unidade_id = uc.unidade_id
  from public.unidade_cidades uc
  where lower(c.cidade) = lower(uc.cidade)
    and c.unidade_id is distinct from uc.unidade_id;
  get diagnostics n = row_count;
  return n;
end; $$;

-- Leitura de leads agora respeita a janela (alem de unidade e tacografo). Admin ve tudo.
drop policy if exists "caminhoneiros: le unidade" on public.caminhoneiros;
create policy "caminhoneiros: le unidade" on public.caminhoneiros
for select using (
  public.is_equipe_ativa() and (
    public.is_admin() or (
      unidade_id = public.unidade_do_usuario()
      and tem_tacografo = true
      and (
        public.janela_do_usuario() is null
        or (
          data_ultima_afericao is not null
          and (data_ultima_afericao + interval '2 years')::date <= current_date + public.janela_do_usuario()
        )
      )
    )
  )
);
