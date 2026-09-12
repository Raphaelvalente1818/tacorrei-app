-- 0086 — "Nosso" deixa de ser TACORREI/LACRE escrito no código
--
-- Até aqui `posto_do_grupo(posto)` era `ilike '%TACORREI%' or ilike '%LACRE%'`: o
-- último nome de posto fixo no sistema (item 1 da preparação para venda). Agora:
--   grupos                    — o grupo econômico (Tacorrei e Lacre são um só).
--   unidades.posto_chave      — a palavra que identifica o posto nos cadastros
--                               ('TACORREI', 'LACRE'); nasce da 1ª palavra do posto.
--   posto_do_grupo(posto, unidade) — o posto é de alguma unidade do mesmo grupo
--                               da unidade dada (unidade sem grupo = só ela mesma).
-- As sete funções que usavam a versão antiga passam a chamar a nova com a unidade
-- do caminhão; a fila e a ficha passam a devolver `nosso` pronto, e o front deixa
-- de ter TACORREI/LACRE escrito (Leads.tsx, LeadDetail.tsx). Em montar_meta o
-- "empresa tem nosso" deixa de ser um exists por linha e vira um agregado por
-- empresa (a nova função custa uma leitura de `unidades` por chamada).
--
-- As funções são reescritas a partir da definição atual no banco (replace exato
-- por chamada), para não transcrever 400 linhas à mão. No fim, a migration confere
-- que não sobrou nenhuma chamada de um argumento — se sobrar, ela falha inteira.
-- Portões depois de aplicar: conferencia_contagens() 24/24, testes_pontuacao() 14/14,
-- e "nosso" idêntico ao antigo para todos os caminhões (0 diferenças).

-- ── grupos ──────────────────────────────────────────────────────────────────
create table if not exists public.grupos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  criado_em timestamptz not null default now()
);
alter table public.grupos enable row level security;
drop policy if exists "grupos: equipe le" on public.grupos;
create policy "grupos: equipe le" on public.grupos for select using (public.is_equipe_ativa());
drop policy if exists "grupos: admin gerencia" on public.grupos;
create policy "grupos: admin gerencia" on public.grupos for all using (public.is_admin()) with check (public.is_admin());
revoke all on public.grupos from anon;
grant select on public.grupos to authenticated;
grant insert, update, delete on public.grupos to authenticated;

insert into public.grupos (id, nome)
select distinct u.grupo_id, 'Tacorrei / Lacre'
  from public.unidades u where u.grupo_id is not null
on conflict (id) do nothing;

alter table public.unidades
  drop constraint if exists unidades_grupo_id_fkey,
  add constraint unidades_grupo_id_fkey foreign key (grupo_id) references public.grupos(id);

-- ── posto_chave ─────────────────────────────────────────────────────────────
alter table public.unidades add column if not exists posto_chave text;
update public.unidades
   set posto_chave = upper(split_part(btrim(posto_afericao), ' ', 1))
 where posto_chave is null and posto_afericao is not null;

-- ── posto_do_grupo(posto, unidade) ──────────────────────────────────────────
-- SQL puro, STABLE, sem SET: inlina nos chamadores (lição da 0080). A leitura de
-- `unidades` acontece dentro das funções SECURITY DEFINER que a chamam.
create or replace function public.posto_do_grupo(p_posto text, p_unidade uuid)
returns boolean
language sql
stable
as $$
  select p_posto is not null and exists (
    select 1
      from public.unidades g
      join public.unidades u
        on u.id = g.id or (u.grupo_id is not null and u.grupo_id = g.grupo_id)
     where g.id = p_unidade
       and coalesce(u.posto_chave, upper(split_part(btrim(u.posto_afericao), ' ', 1))) is not null
       and p_posto ilike '%' || coalesce(u.posto_chave, upper(split_part(btrim(u.posto_afericao), ' ', 1))) || '%'
  )
$$;
revoke all on function public.posto_do_grupo(text, uuid) from public, anon;
grant execute on function public.posto_do_grupo(text, uuid) to authenticated, service_role;

-- ── reescreve os chamadores ─────────────────────────────────────────────────
do $$
declare
  r record;
  v_def text; v_novo text;
  -- função → pares (de, para), aplicados em ordem
  v_regras jsonb := '{
    "base_trabalhavel":        [["public.posto_do_grupo(c.posto_afericao)", "public.posto_do_grupo(c.posto_afericao, c.unidade_id)"]],
    "obter_lead":              [["public.posto_do_grupo(x.posto_afericao)", "public.posto_do_grupo(x.posto_afericao, x.unidade_id)"],
                                ["select to_jsonb(c), c.empresa_id, c.unidade_id into v_lead, v_emp, v_unidade",
                                 "select to_jsonb(c) || jsonb_build_object(''nosso'', public.posto_do_grupo(c.posto_afericao, c.unidade_id)), c.empresa_id, c.unidade_id into v_lead, v_emp, v_unidade"]],
    "pontuar_afericao":        [["public.posto_do_grupo(x.posto_afericao)", "public.posto_do_grupo(x.posto_afericao, x.unidade_id)"],
                                ["public.posto_do_grupo(p_posto_ant)", "public.posto_do_grupo(p_posto_ant, v_unidade)"]],
    "registra_troca_de_posto": [["public.posto_do_grupo(old.posto_afericao)", "public.posto_do_grupo(old.posto_afericao, new.unidade_id)"],
                                ["public.posto_do_grupo(new.posto_afericao)", "public.posto_do_grupo(new.posto_afericao, new.unidade_id)"]],
    "registrar_envio_whatsapp":[["public.posto_do_grupo(x.posto_afericao)", "public.posto_do_grupo(x.posto_afericao, x.unidade_id)"],
                                ["public.posto_do_grupo(v_posto)", "public.posto_do_grupo(v_posto, v_unidade)"]],
    "sinais_de_fuga":          [["public.posto_do_grupo(c.posto_afericao)", "public.posto_do_grupo(c.posto_afericao, c.unidade_id)"]],
    "montar_meta":             [["           exists (select 1 from public.caminhoneiros x\n                    where x.empresa_id = b.empresa_id and x.id <> b.id\n                      and public.posto_do_grupo(x.posto_afericao)) as empresa_tem_nosso\n    from public.base_trabalhavel(p_unidade) b\n",
                                 "           (coalesce(en.nossos, 0) - case when b.nosso then 1 else 0 end) > 0 as empresa_tem_nosso\n    from public.base_trabalhavel(p_unidade) b\n    left join (select x.empresa_id, count(*) as nossos from public.caminhoneiros x\n                where x.empresa_id is not null and public.posto_do_grupo(x.posto_afericao, x.unidade_id)\n                group by x.empresa_id) en on en.empresa_id = b.empresa_id\n"],
                                ["public.posto_do_grupo(c.posto_afericao)", "public.posto_do_grupo(c.posto_afericao, c.unidade_id)"]],
    "fila_leads":              [["select c.*, e.nome as empresa_nome, e.situacao as empresa_situacao",
                                 "select c.*, e.nome as empresa_nome, e.situacao as empresa_situacao, public.posto_do_grupo(c.posto_afericao, c.unidade_id) as nosso"]]
  }'::jsonb;
  k text; par jsonb; n_antes int; n_depois int;
begin
  for k in select jsonb_object_keys(v_regras) loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = k;
    if v_def is null then raise exception 'funcao % nao encontrada', k; end if;
    v_novo := v_def;
    for par in select * from jsonb_array_elements(v_regras->k) loop
      n_antes := (length(v_novo) - length(replace(v_novo, par->>0, ''))) / length(par->>0);
      if n_antes = 0 then raise exception 'em %: trecho nao encontrado: %', k, par->>0; end if;
      v_novo := replace(v_novo, par->>0, par->>1);
    end loop;
    execute v_novo;
    raise notice 'reescrita: %', k;
  end loop;

  -- A antiga sai. Se alguma função ainda a chamar, o uso quebraria em produção;
  -- por isso a conferência abaixo.
  drop function public.posto_do_grupo(text);

  select count(*) into n_depois
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc ~ 'posto_do_grupo\(\s*[a-z_.]+\s*\)';
  if n_depois > 0 then
    raise exception 'ainda ha % funcao(oes) chamando posto_do_grupo com um argumento', n_depois;
  end if;
end $$;

-- posto_chave entra na lista do admin geral em configurar_unidade
create or replace function public.configurar_unidade(p_unidade uuid, p_campos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k text;
  v_admin boolean; v_gestor boolean;
  v_geral text[] := array['nome','posto_afericao','posto_chave','marca','endereco','telefone',
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
      if k in ('nome','posto_afericao','posto_chave','marca','endereco','telefone') then
        v_txt := nullif(btrim(p_campos->>k), '');
        if k = 'nome' and v_txt is null then raise exception 'nome obrigatorio'; end if;
        if k = 'posto_chave' then v_txt := upper(v_txt); end if;
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
