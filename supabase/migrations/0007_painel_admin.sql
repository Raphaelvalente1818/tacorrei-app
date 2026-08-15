-- Painel Admin: produção por unidade/funcionária + gestão de acessos. Aplicada em 15/08/2026.
-- Depende de 0005 (unidades, unidade_id, is_admin(), unidade_do_usuario()).

-- 1) Coluna de e-mail na equipe (para exibir/gerenciar acessos sem cruzar com auth.users no cliente).
alter table public.equipe add column if not exists email text;

update public.equipe e
set email = u.email
from auth.users u
where u.id = e.user_id and e.email is null;

-- 2) Admin pode inserir/atualizar a equipe (criar e mover acessos, trocar papel, ativar/desativar).
drop policy if exists "equipe: admin insere" on public.equipe;
create policy "equipe: admin insere" on public.equipe
  for insert with check (is_admin());

drop policy if exists "equipe: admin atualiza" on public.equipe;
create policy "equipe: admin atualiza" on public.equipe
  for update using (is_admin()) with check (is_admin());

-- 3) Produção por unidade (jsonb). Gated por is_admin().
create or replace function public.producao_unidades(p_dias integer default null)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  from (
    select
      u.id, u.nome,
      (select count(*) from public.caminhoneiros c where c.unidade_id = u.id and c.tem_tacografo) as leads,
      (select count(*) from public.caminhoneiros c where c.unidade_id = u.id and c.tem_tacografo and c.status = 'aferido') as aferidos,
      (select count(*) from public.caminhoneiros c where c.unidade_id = u.id and c.tem_tacografo and c.status = 'agendado') as agendados_total,
      (select count(*) from public.ligacoes l where l.unidade_id = u.id
         and (p_dias is null or l.created_at >= now() - (p_dias || ' days')::interval)) as contatos,
      (select count(*) from public.ligacoes l where l.unidade_id = u.id and l.canal = 'whatsapp'
         and (p_dias is null or l.created_at >= now() - (p_dias || ' days')::interval)) as whatsapp,
      (select count(*) from public.agendamentos a where a.unidade_id = u.id
         and (p_dias is null or a.created_at >= now() - (p_dias || ' days')::interval)) as agendados
    from public.unidades u
    where is_admin()
    order by u.nome
  ) t;
$$;

-- 4) Produção por funcionária (jsonb). Gated por is_admin().
create or replace function public.producao_operadores(p_dias integer default null)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  from (
    select
      e.nome as operador, e.papel, un.nome as unidade,
      (select count(*) from public.ligacoes l where l.operador_id = e.user_id
         and (p_dias is null or l.created_at >= now() - (p_dias || ' days')::interval)) as contatos,
      (select count(*) from public.ligacoes l where l.operador_id = e.user_id and l.canal = 'whatsapp'
         and (p_dias is null or l.created_at >= now() - (p_dias || ' days')::interval)) as whatsapp,
      (select count(*) from public.agendamentos a where a.created_by = e.user_id
         and (p_dias is null or a.created_at >= now() - (p_dias || ' days')::interval)) as agendados
    from public.equipe e
    left join public.unidades un on un.id = e.unidade_id
    where is_admin() and e.ativo
    order by un.nome nulls last, e.nome
  ) t;
$$;
