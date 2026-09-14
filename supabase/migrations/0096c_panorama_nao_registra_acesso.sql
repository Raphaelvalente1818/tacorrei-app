-- 0096c — o panorama do ano não grava registro de acesso.
--
-- Erro pego ao rodar o portão logo depois da 0096b:
--   cannot execute INSERT in a read-only transaction
--   ... registrar_acesso → panorama_do_ano → conferencia_contagens
--
-- A conferência passou a chamar o panorama, e o panorama gravava em
-- acessos_lead. Isso quebrava a conferência em qualquer conexão somente-leitura
-- — que é justamente como ela é rodada para auditar o banco sem tocar nele.
--
-- O registro de acesso existe para saber quem LEU FICHA: quem abriu, quem
-- listou, quem buscou placa. O panorama não devolve ficha nenhuma — nem nome,
-- nem placa, nem telefone, só a contagem por mês. Registrar essa chamada não
-- protege nada e cobra um preço real. Sai.
create or replace function public.panorama_do_ano(p_unidade uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_uni uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_uni := coalesce(p_unidade, public.unidade_do_usuario());
  if not (public.is_admin() or v_uni = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  select jsonb_build_object(
    'meses', coalesce(jsonb_agg(jsonb_build_object('mes', x.mes, 'total', x.total)
                                order by x.mes), '[]'::jsonb),
    'total', coalesce(sum(x.total), 0)
  ) into v
  from (
    select to_char(b.venc, 'YYYY-MM') as mes, count(*) as total
      from public.base_trabalhavel(v_uni) b
     where b.na_fila
       and b.venc >= date_trunc('month', current_date)::date
       and b.venc < (date_trunc('month', current_date) + interval '12 months')::date
     group by 1
  ) x;

  return v;
end $function$;

revoke all on function public.panorama_do_ano(uuid) from public, anon;
grant execute on function public.panorama_do_ano(uuid) to authenticated, service_role;
