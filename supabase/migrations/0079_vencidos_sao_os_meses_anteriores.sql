-- 0079 — "Vencidos" na fila = venceu em mês anterior ao atual (mesmo corte do botão)
--
-- O botão "Vencidos" soma os meses anteriores ao atual; o mês corrente tem botão próprio
-- (set/26). A lista, porém, filtrava "venc < hoje" — os 44 que venceram entre 1 e 10/09
-- apareciam nos dois lugares, e o botão dava 550 com a lista em 594. Agora: Vencidos =
-- venceu antes do dia 1º deste mês; o botão do mês = tudo que vence (ou venceu) neste mês.

create or replace function public.listar_leads(
  p_pagina integer default 1, p_tamanho integer default 100, p_filtro text default 'todos',
  p_busca text default null, p_unidade uuid default null, p_mes text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_tam integer; v_ini integer; v_busca text; v_mes text; v_total bigint; v_linhas jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  if p_tamanho is not null and p_tamanho > 100 then
    raise exception 'tamanho de pagina acima do permitido (maximo 100)';
  end if;

  v_tam := least(greatest(coalesce(p_tamanho,100),1),100);
  v_ini := greatest(coalesce(p_pagina,1)-1,0) * v_tam;
  v_busca := nullif(btrim(coalesce(p_busca,'')),'');
  v_mes := nullif(btrim(coalesce(p_mes,'')),'');

  with visiveis as (
    select c.*, e.nome as empresa_nome, e.situacao as empresa_situacao
    from public.caminhoneiros c
    left join public.empresas e on e.id = c.empresa_id
    where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      -- some da fila só quem está sob contrato; prospecto continua aparecendo
      and (c.empresa_id is null or e.situacao = 'prospecto')
      and (p_unidade is null or c.unidade_id = p_unidade)
      and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
      -- piso da unidade, igual para admin e operadora; a busca passa por cima
      and (v_busca is not null or c.tem_tacografo = false
           or public.lead_trabalhavel(c.unidade_id, c.data_ultima_afericao))
      and (v_mes is null
           or (v_mes = 'vencidos'
               and (c.data_ultima_afericao + interval '2 years')::date < date_trunc('month', current_date)::date)
           or to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') = v_mes)
      and (v_busca is null
           or c.nome ilike '%'||v_busca||'%' or c.telefone ilike '%'||v_busca||'%'
           or c.cidade ilike '%'||v_busca||'%' or c.placa_veiculo ilike '%'||v_busca||'%'
           or e.nome ilike '%'||v_busca||'%')
  )
  select (select count(*) from visiveis),
         coalesce((select jsonb_agg(to_jsonb(p) order by p.data_ultima_afericao asc nulls last, p.id)
                   from (select * from visiveis order by data_ultima_afericao asc nulls last, id
                         offset v_ini limit v_tam) p), '[]'::jsonb)
  into v_total, v_linhas;

  perform public.registrar_acesso('listar', jsonb_array_length(v_linhas),
    jsonb_build_object('filtro',p_filtro,'busca',v_busca,'mes',v_mes,
                       'pagina',coalesce(p_pagina,1),'unidade',p_unidade));

  return jsonb_build_object('total', v_total, 'leads', v_linhas);
end $$;
