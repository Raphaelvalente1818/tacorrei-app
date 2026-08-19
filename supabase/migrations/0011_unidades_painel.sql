-- 0011_unidades_painel.sql
-- Retrato de cada unidade para a aba Admin > Unidades.
-- Colunas: carteira (publico-alvo), fila (o trabalho de hoje), abordados
-- (com o % da fila) e aferidos. So admin.
--
-- "fila" usa a janela da PROPRIA unidade: ja vencidos + os que vencem dentro
-- do prazo dela. Janela NULL (base toda) => a fila e a carteira inteira.
-- "abordados" conta o LEAD uma vez (data_ultimo_whatsapp), nao o numero de
-- mensagens -- por isso difere do placar, que conta cada envio.
create or replace function public.unidades_painel()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res jsonb;
begin
  if not public.is_admin() then
    raise exception 'acesso negado';
  end if;

  select coalesce(jsonb_agg(x order by x.carteira desc, x.nome), '[]'::jsonb)
    into v_res
  from (
    select
      u.id,
      u.nome,
      u.janela_dias,
      (select string_agg(uc.cidade, ' · ' order by uc.cidade)
         from unidade_cidades uc where uc.unidade_id = u.id) as cidades,
      count(c.id) filter (where c.tem_tacografo) as carteira,
      count(c.id) filter (
        where c.tem_tacografo
          and (u.janela_dias is null
               or (c.data_ultima_afericao + interval '2 years')::date
                    <= current_date + u.janela_dias)
      ) as fila,
      count(c.id) filter (
        where c.tem_tacografo and c.data_ultimo_whatsapp is not null
      ) as abordados,
      count(c.id) filter (where c.status = 'aferido') as aferidos
    from unidades u
    left join caminhoneiros c on c.unidade_id = u.id
    group by u.id, u.nome, u.janela_dias
  ) x;

  return v_res;
end;
$$;

revoke all on function public.unidades_painel() from public;
grant execute on function public.unidades_painel() to authenticated;
