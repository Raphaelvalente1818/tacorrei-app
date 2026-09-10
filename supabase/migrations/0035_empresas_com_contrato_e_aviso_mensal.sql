-- [aplicada no banco em 28/08/2026 18:33 — versão 20260828183324]
-- ── EMPRESAS COM CONTRATO ────────────────────────────────────────────────────
-- São o oposto do lead: já são clientes, não se prospecta. O trabalho é AVISAR
-- quais carros vencem no mês seguinte para a empresa mandar os certos.
-- Por isso elas não entram no funil, não têm taxa de conversão e não recebem
-- mensagem de abordagem — têm tela e mensagem próprias.
--
-- A chave é o CNPJ, não o nome: "MBK" aparece com quatro grafias diferentes só na
-- base do RNTRC, e por nome viraria quatro empresas. O veículo pendura pela placa.
create table if not exists public.empresas (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidades(id) on delete restrict,
  cnpj text,
  nome text not null,
  contato text,
  telefone text,
  ativo boolean not null default true,
  observacoes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- CNPJ só com dígitos, único por unidade. Empresa sem CNPJ é aceita (cadastro
-- manual), mas aí não há dedupe automática na importação.
create unique index if not exists uq_empresas_cnpj
  on public.empresas (unidade_id, regexp_replace(coalesce(cnpj,''), '\D', '', 'g'))
  where cnpj is not null;

alter table public.caminhoneiros
  add column if not exists empresa_id uuid references public.empresas(id) on delete set null;
create index if not exists idx_caminhoneiros_empresa on public.caminhoneiros (empresa_id);

-- Registro de que a empresa foi avisada naquela competência. O índice único é a
-- trava: um aviso por empresa por mês, nunca dois.
create table if not exists public.avisos_empresa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  competencia date not null,
  enviado_em timestamptz not null default now(),
  operador_id uuid,
  veiculos jsonb,
  mensagem text
);
create unique index if not exists uq_aviso_empresa_competencia
  on public.avisos_empresa (empresa_id, competencia);

alter table public.empresas enable row level security;
alter table public.avisos_empresa enable row level security;

drop policy if exists empresas_leitura on public.empresas;
create policy empresas_leitura on public.empresas for select to authenticated
  using (public.is_admin() or unidade_id = public.unidade_do_usuario());

drop policy if exists empresas_escrita on public.empresas;
create policy empresas_escrita on public.empresas for all to authenticated
  using (public.is_admin() or unidade_id = public.unidade_do_usuario())
  with check (public.is_admin() or unidade_id = public.unidade_do_usuario());

drop policy if exists avisos_leitura on public.avisos_empresa;
create policy avisos_leitura on public.avisos_empresa for select to authenticated
  using (exists (select 1 from public.empresas e where e.id = empresa_id
                 and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())));

revoke all on public.empresas from anon;
revoke all on public.avisos_empresa from anon;
