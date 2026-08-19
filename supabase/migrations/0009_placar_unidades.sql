-- 0009_placar_unidades.sql
-- Placar de mensagens de WhatsApp por unidade (competicao entre unidades).
--
-- Devolve APENAS totais agregados: nome da unidade + contagem. Nenhum lead e exposto,
-- entao pode ser lido por qualquer membro ativo da equipe, inclusive operador de outra
-- unidade -- que continua sem enxergar os leads alheios pela RLS normal.
--
-- Periodo: mes corrente no fuso de Sao Paulo (zera no dia 1o).
-- Metrica: cada envio de WhatsApp registrado em `ligacoes` conta 1.
create or replace function public.placar_unidades()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inicio timestamptz;
  v_res jsonb;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  -- inicio do mes corrente no horario de Brasilia
  v_inicio := date_trunc('month', (now() at time zone 'America/Sao_Paulo'))
              at time zone 'America/Sao_Paulo';

  select coalesce(jsonb_agg(x order by x.total desc, x.unidade), '[]'::jsonb)
    into v_res
  from (
    select
      u.nome                                   as unidade,
      count(l.id)                              as total,
      (u.id = public.unidade_do_usuario())     as sua
    from unidades u
    left join ligacoes l
      on l.unidade_id = u.id
     and l.canal = 'whatsapp'
     and l.created_at >= v_inicio
    -- Swiss Park e unidade de TESTE: fica fora do placar.
    -- Quando ela for apagada, esta linha pode sair.
    where u.id <> '066cbbd9-1af3-46f1-95d0-ae5f3f988fc0'::uuid
    group by u.id, u.nome
  ) x;

  return v_res;
end;
$$;

revoke all on function public.placar_unidades() from public;
grant execute on function public.placar_unidades() to authenticated;
