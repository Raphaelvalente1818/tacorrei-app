-- [aplicada no banco em 28/08/2026 19:42 — versão 20260828194216]
-- p_mes aceita 'vencidos' além de 'YYYY-MM'. Sem isso, um admin — que enxerga a
-- base inteira — precisaria de uma chip por mês desde 2011 para chegar nos
-- vencidos. Agregado, é uma chip só, que é como a operadora pensa: "os atrasados".
create or replace function public.listar_leads(
  p_pagina integer default 1, p_tamanho integer default 100,
  p_filtro text default 'todos', p_busca text default null,
  p_unidade uuid default null, p_mes text default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
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
    select c.* from public.caminhoneiros c
    where public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      and c.empresa_id is null
      and (p_unidade is null or c.unidade_id = p_unidade)
      and (case when p_filtro = 'sem_tacografo' then c.tem_tacografo = false
                else c.tem_tacografo = true and (p_filtro = 'todos' or c.status = p_filtro) end)
      and (v_mes is null
           or (v_mes = 'vencidos'
               and (c.data_ultima_afericao + interval '2 years')::date < current_date)
           or to_char((c.data_ultima_afericao + interval '2 years')::date,'YYYY-MM') = v_mes)
      and (v_busca is null
           or c.nome ilike '%'||v_busca||'%' or c.telefone ilike '%'||v_busca||'%'
           or c.cidade ilike '%'||v_busca||'%' or c.placa_veiculo ilike '%'||v_busca||'%')
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
end $function$;
