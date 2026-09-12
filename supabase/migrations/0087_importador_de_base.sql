-- 0087 — Importador da base (extração do RNTRC) pela tela — só admin geral
--
-- Item 8 da matriz: a base é o produto; quem importa é o Aferi+, nunca a unidade.
-- Até aqui cada carga era uma migration minha em lotes. Agora: o admin geral cola a
-- extração (uma linha por placa, ou até 12 placas por linha) em Administração →
-- Importar base, vê a conferência ANTES de gravar (novas, existentes, sem data,
-- fora da cobertura, duplicadas) e confirma. Fica registro de quem importou o quê.
--
-- Regras que não mudam (decisoes-e-progresso.md, "Regras que não se discutem mais"):
--   • placa existente na unidade é ATUALIZADA, nunca duplicada (índice único por
--     placa normalizada + unidade);
--   • sem data de aferição = sem tacógrafo (entra, mas fora da fila);
--   • placa fica no formato em que veio (não converte para Mercosul);
--   • posto só é trocado quando a data nova é mais recente que a gravada (troca com
--     data igual seria só grafia — e o gatilho registraria uma "fuga" falsa);
--   • cidade fora da cobertura da unidade não entra, a menos que o admin marque.
--
-- Colunas aceitas (o front normaliza os cabeçalhos; ver ImportarBaseModal.tsx):
--   nome, cpf_cnpj, rntrc, telefone, celular, email, cidade, uf, placa, tipo,
--   renavam, data (DATA_AFERICAO / DATA_TACOGRAFO), posto (POSTO_AFERICAO).

create table if not exists public.importacoes (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidades(id),
  importado_por uuid,
  importado_em timestamptz not null default now(),
  rotulo text,
  linhas integer not null default 0,
  criados integer not null default 0,
  atualizados integer not null default 0,
  sem_data integer not null default 0,
  fora_cobertura integer not null default 0,
  ignorados integer not null default 0,
  resumo jsonb
);
alter table public.importacoes enable row level security;
drop policy if exists "importacoes: admin le" on public.importacoes;
create policy "importacoes: admin le" on public.importacoes for select using (public.is_admin());
revoke all on public.importacoes from anon, authenticated;
grant select on public.importacoes to authenticated;

-- Sem unaccent no projeto: tira os acentos comuns para comparar cidade.
create or replace function public.normaliza_texto(p text)
returns text
language sql
immutable
as $$
  select upper(btrim(translate(coalesce(p, ''),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')))
$$;

-- ── preparar_base (interna): normaliza as linhas numa tabela temporária ─────
-- Devolve uma linha por placa válida, já com o "veredito" de cada uma.
create or replace function public.preparar_base(p_unidade uuid, p_linhas jsonb)
returns table (
  placa text, nome text, telefone text, cidade text, uf text, rntrc text, renavam text,
  modelo text, data date, posto text, cpf_cnpj text,
  na_cobertura boolean, duplicada boolean,
  existente_id uuid, existente_data date, existente_posto text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with brutas as (
    select public.normaliza_placa(x.placa) as placa,
           nullif(btrim(coalesce(x.nome, '')), '') as nome,
           nullif(btrim(coalesce(nullif(btrim(coalesce(x.celular,'')), ''), x.telefone, '')), '') as telefone,
           nullif(btrim(coalesce(x.cidade, '')), '') as cidade,
           nullif(upper(btrim(coalesce(x.uf, ''))), '') as uf,
           nullif(regexp_replace(coalesce(x.rntrc, ''), '\D', '', 'g'), '') as rntrc,
           nullif(regexp_replace(coalesce(x.renavam, ''), '\D', '', 'g'), '') as renavam,
           nullif(btrim(coalesce(x.tipo, '')), '') as modelo,
           case when x.data ~ '^\d{4}-\d{2}-\d{2}$' then x.data::date else null end as data,
           case when upper(btrim(coalesce(x.posto, ''))) in ('', 'NENHUM RESULTADO', 'NENHUM RESULTADO.', '-', '--', 'N/A')
                then null else btrim(x.posto) end as posto,
           nullif(regexp_replace(coalesce(x.cpf_cnpj, ''), '\D', '', 'g'), '') as cpf_cnpj,
           row_number() over () as ordem
    from jsonb_to_recordset(coalesce(p_linhas, '[]'::jsonb)) as x(
      placa text, nome text, telefone text, celular text, cidade text, uf text, rntrc text,
      renavam text, tipo text, data text, posto text, cpf_cnpj text)
  ),
  validas as (
    select b.*,
           -- a mesma placa duas vezes na planilha: fica a primeira com data (ou a primeira)
           row_number() over (partition by b.placa order by (b.data is null), b.ordem) as rep
    from brutas b
    where b.placa is not null and length(b.placa) = 7
  )
  select v.placa, v.nome, v.telefone, v.cidade, v.uf, v.rntrc, v.renavam, v.modelo, v.data, v.posto, v.cpf_cnpj,
         exists (select 1 from public.unidade_cidades uc
                  where uc.unidade_id = p_unidade
                    and public.normaliza_texto(uc.cidade) = public.normaliza_texto(v.cidade)) as na_cobertura,
         v.rep > 1 as duplicada,
         c.id, c.data_ultima_afericao, c.posto_afericao
  from validas v
  left join public.caminhoneiros c
    on c.unidade_id = p_unidade and public.normaliza_placa(c.placa_veiculo) = v.placa
$$;
revoke all on function public.preparar_base(uuid, jsonb) from public, anon, authenticated;

-- ── analisar_base: a conferência antes de gravar ────────────────────────────
create or replace function public.analisar_base(p_unidade uuid, p_linhas jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'acesso negado: so o admin geral importa base'; end if;
  if not exists (select 1 from public.unidades where id = p_unidade) then raise exception 'unidade nao encontrada'; end if;

  select jsonb_build_object(
    'linhas', jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)),
    'placas', count(*),
    'duplicadas', count(*) filter (where duplicada),
    'novas', count(*) filter (where not duplicada and existente_id is null),
    'existentes', count(*) filter (where not duplicada and existente_id is not null),
    'existentes_com_data_nova', count(*) filter (where not duplicada and existente_id is not null and data is not null
                                                     and (existente_data is null or data > existente_data)),
    'sem_data', count(*) filter (where not duplicada and data is null),
    'com_data', count(*) filter (where not duplicada and data is not null),
    'fora_cobertura', count(*) filter (where not duplicada and not na_cobertura),
    'novas_fora_cobertura', count(*) filter (where not duplicada and not na_cobertura and existente_id is null),
    'cidades_fora', coalesce((select jsonb_agg(jsonb_build_object('cidade', cidade, 'n', n) order by n desc)
                              from (select coalesce(cidade, '(sem cidade)') as cidade, count(*) as n
                                      from public.preparar_base(p_unidade, p_linhas)
                                     where not duplicada and not na_cobertura
                                     group by 1 order by 2 desc limit 15) t), '[]'::jsonb),
    'postos', coalesce((select jsonb_agg(jsonb_build_object('posto', posto, 'n', n, 'nosso', nosso) order by n desc)
                        from (select posto, count(*) as n, public.posto_do_grupo(posto, p_unidade) as nosso
                                from public.preparar_base(p_unidade, p_linhas)
                               where not duplicada and posto is not null
                               group by posto order by 2 desc limit 12) t), '[]'::jsonb),
    'ignoradas', jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)) - count(*)
  ) into v
  from public.preparar_base(p_unidade, p_linhas);
  return v;
end $$;
revoke all on function public.analisar_base(uuid, jsonb) from public, anon;
grant execute on function public.analisar_base(uuid, jsonb) to authenticated, service_role;

-- ── importar_base: grava ────────────────────────────────────────────────────
create or replace function public.importar_base(p_unidade uuid, p_linhas jsonb, p_rotulo text default null,
                                                p_incluir_fora_cobertura boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_criados int := 0; v_atualizados int := 0; v_sem_data int := 0; v_fora int := 0; v_ign int := 0;
  v_id uuid; v_resumo jsonb;
begin
  if not public.is_admin() then raise exception 'acesso negado: so o admin geral importa base'; end if;
  if not exists (select 1 from public.unidades where id = p_unidade) then raise exception 'unidade nao encontrada'; end if;

  drop table if exists _imp;
  create temp table _imp on commit drop as
    select * from public.preparar_base(p_unidade, p_linhas)
     where not duplicada;

  select count(*) filter (where not na_cobertura) into v_fora from _imp;
  if not coalesce(p_incluir_fora_cobertura, false) then
    delete from _imp where not na_cobertura;
  end if;

  -- Existentes: só preenche o que está vazio; data só avança; posto só com data mais nova.
  update public.caminhoneiros c
     set nome = coalesce(c.nome, i.nome),
         telefone = case when coalesce(c.telefone, '') = '' then coalesce(i.telefone, c.telefone) else c.telefone end,
         cidade = coalesce(c.cidade, i.cidade),
         uf = coalesce(c.uf, i.uf),
         rntrc = coalesce(c.rntrc, i.rntrc),
         renavam = coalesce(c.renavam, i.renavam),
         modelo_veiculo = coalesce(c.modelo_veiculo, i.modelo),
         posto_afericao = case when i.posto is not null
                                and (c.data_ultima_afericao is null or i.data > c.data_ultima_afericao)
                               then i.posto else c.posto_afericao end,
         data_ultima_afericao = greatest(c.data_ultima_afericao, i.data),
         tem_tacografo = c.tem_tacografo or i.data is not null,
         updated_at = now()
    from _imp i
   where i.existente_id = c.id
     and (c.nome is null or coalesce(c.telefone,'') = '' or c.cidade is null or c.uf is null
          or c.rntrc is null or c.renavam is null or c.modelo_veiculo is null
          or (i.data is not null and (c.data_ultima_afericao is null or i.data > c.data_ultima_afericao)));
  get diagnostics v_atualizados = row_count;

  insert into public.caminhoneiros
    (nome, telefone, cidade, uf, placa_veiculo, modelo_veiculo, rntrc, renavam,
     data_ultima_afericao, posto_afericao, tem_tacografo, unidade_id, origem, status, observacoes)
  select coalesce(i.nome, i.cpf_cnpj, 'SEM NOME'), coalesce(i.telefone, ''), i.cidade, i.uf, i.placa, i.modelo,
         i.rntrc, i.renavam, i.data, case when i.data is not null then i.posto end,
         i.data is not null, p_unidade, 'outro', 'novo',
         case when i.data is null then 'Sem data de aferição na extração: fora da fila até ser verificado.' end
    from _imp i
   where i.existente_id is null;
  get diagnostics v_criados = row_count;

  select count(*) filter (where data is null and existente_id is null) into v_sem_data from _imp;
  v_ign := jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)) - (select count(*) from _imp)
           - (select count(*) from public.preparar_base(p_unidade, p_linhas) where duplicada);

  v_resumo := jsonb_build_object(
    'linhas', jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)),
    'criados', v_criados, 'atualizados', v_atualizados, 'sem_data', v_sem_data,
    'fora_cobertura', v_fora, 'fora_cobertura_incluidas', coalesce(p_incluir_fora_cobertura, false),
    'ignoradas', greatest(v_ign, 0));

  insert into public.importacoes (unidade_id, importado_por, rotulo, linhas, criados, atualizados, sem_data, fora_cobertura, ignorados, resumo)
  values (p_unidade, auth.uid(), nullif(btrim(coalesce(p_rotulo,'')), ''),
          jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)), v_criados, v_atualizados, v_sem_data, v_fora, greatest(v_ign, 0), v_resumo)
  returning id into v_id;

  return v_resumo || jsonb_build_object('id', v_id);
end $$;
revoke all on function public.importar_base(uuid, jsonb, text, boolean) from public, anon;
grant execute on function public.importar_base(uuid, jsonb, text, boolean) to authenticated, service_role;

-- histórico para a tela
create or replace function public.historico_importacoes(p_unidade uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when not public.is_admin() then null else
    coalesce((select jsonb_agg(jsonb_build_object(
               'id', i.id, 'unidade', u.nome, 'importado_em', i.importado_em,
               'por', (select e.nome from public.equipe e where e.user_id = i.importado_por),
               'rotulo', i.rotulo, 'linhas', i.linhas, 'criados', i.criados, 'atualizados', i.atualizados,
               'sem_data', i.sem_data, 'fora_cobertura', i.fora_cobertura, 'ignorados', i.ignorados)
               order by i.importado_em desc)
              from (select * from public.importacoes x
                     where p_unidade is null or x.unidade_id = p_unidade
                     order by x.importado_em desc limit 20) i
              join public.unidades u on u.id = i.unidade_id), '[]'::jsonb) end
$$;
revoke all on function public.historico_importacoes(uuid) from public, anon;
grant execute on function public.historico_importacoes(uuid) to authenticated, service_role;
