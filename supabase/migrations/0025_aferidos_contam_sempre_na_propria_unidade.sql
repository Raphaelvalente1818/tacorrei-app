-- [aplicada no banco em 24/08/2026 14:54 — versão 20260824145401]
-- Problema: ao marcar "Aferido", a data da aferição vira hoje e o vencimento pula
-- para daqui a 2 anos. O lead sai da janela e, para a OPERADORA que fez o trabalho,
-- ele simplesmente some das contagens: o painel dela mostrava 0 aferidos.
-- Quem fez o serviço não via o próprio resultado.
--
-- Correção: no CONTADOR (que devolve só números agregados, nunca dados de lead),
-- os aferidos da PRÓPRIA unidade contam sempre, dentro ou fora da janela.
-- A regra de visibilidade dos leads em si (listar_leads / obter_lead) não muda.
create or replace function public.contar_leads(p_unidade uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  select jsonb_build_object(
    'total',            count(*),
    'novo',             count(*) filter (where status = 'novo'),
    'mensagem_enviada', count(*) filter (where status = 'mensagem_enviada'),
    'contatado',        count(*) filter (where status = 'contatado'),
    'agendado',         count(*) filter (where status = 'agendado'),
    'aferido',          count(*) filter (where status = 'aferido')
  ) into v
  from public.caminhoneiros c
  where c.tem_tacografo = true
    and (
      public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
      or (c.status = 'aferido' and c.unidade_id = public.unidade_do_usuario())
    )
    and (p_unidade is null or c.unidade_id = p_unidade);

  return v;
end $function$;

revoke execute on function public.contar_leads(uuid) from public;
grant execute on function public.contar_leads(uuid) to authenticated;
