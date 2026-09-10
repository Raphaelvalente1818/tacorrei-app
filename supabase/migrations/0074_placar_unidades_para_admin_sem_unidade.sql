-- 0074 — Placar entre unidades para o admin geral (que agora não tem unidade)
-- Efeito colateral da 0073: o placar do Dashboard partia da unidade de quem olha
-- para achar o grupo; admin sem unidade recebia lista vazia.
-- (Substituída no mesmo dia pela 0075, que muda a regra: cada unidade vê só a si.)
create or replace function public.placar_unidades()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_inicio timestamptz; v_grupo uuid; v_res jsonb; v_minha uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_minha := public.unidade_do_usuario();
  select u.grupo_id into v_grupo from public.unidades u where u.id = v_minha;
  if v_grupo is null and not public.is_admin() then return '[]'::jsonb; end if;
  v_inicio := date_trunc('month', (now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';
  select coalesce(jsonb_agg(x order by x.total desc, x.unidade), '[]'::jsonb) into v_res
  from (
    select u.nome as unidade, count(l.id) as total, (u.id = v_minha) as sua
    from public.unidades u
    left join public.ligacoes l
      on l.unidade_id = u.id and l.canal = 'whatsapp' and l.created_at >= v_inicio
    where public.is_admin() or u.grupo_id = v_grupo
    group by u.id, u.nome
  ) x;
  return v_res;
end $$;
revoke all on function public.placar_unidades() from public, anon;
grant execute on function public.placar_unidades() to authenticated, service_role;
