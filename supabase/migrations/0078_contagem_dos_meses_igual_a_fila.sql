-- 0078 — A contagem por mês de vencimento passa a contar o mesmo que a fila lista
--
-- Contexto (11/09/2026). O botão "Vencidos" dizia 67 e a lista trazia centenas. A função
-- meses_de_vencimento contava só autônomos (empresa_id is null); a fila (listar_leads) lista
-- autônomos E veículos de empresa prospecto — só some da fila quem está sob contrato.
-- Agora as duas usam o mesmo recorte. (A tela passa a mostrar o total no botão e "sem
-- contato" na dica, em vez do contrário.)

create or replace function public.meses_de_vencimento(p_unidade uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select coalesce(jsonb_agg(x order by x.mes), '[]'::jsonb) into v
  from (
    select to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') as mes,
           count(*) as total, count(*) filter (where c.status = 'novo') as novos
    from public.caminhoneiros c
    left join public.empresas e on e.id = c.empresa_id
    where c.tem_tacografo and c.data_ultima_afericao is not null
      -- mesmo recorte da fila: some só quem está sob contrato
      and (c.empresa_id is null or e.situacao = 'prospecto')
      and public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      and public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao)
      and (p_unidade is null or c.unidade_id = p_unidade)
    group by 1) x;
  return v;
end $$;
