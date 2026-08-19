-- 0014_producao_por_papel.sql
-- Producao individual: o admin_unidade so pode ver a equipe DELE.
-- Antes o filtro era `where is_admin()` -- fora isso, devolvia todo mundo.
create or replace function public.producao_operadores(p_dias integer default null)
returns jsonb
language sql stable security definer set search_path to 'public','pg_temp'
as $function$
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
    where e.ativo
      and (
        public.is_admin()
        or (public.is_admin_unidade() and e.unidade_id = public.unidade_do_usuario())
      )
    order by un.nome nulls last, e.nome
  ) t;
$function$;
