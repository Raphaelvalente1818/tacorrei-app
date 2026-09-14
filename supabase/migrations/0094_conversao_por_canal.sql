-- 0094 — conversão por canal
--
-- 14/09, o Emerson: "em são bernardo temos 207 contatados, mas quando entramos nos
-- leads temos somente 11. porque essa diferença".
-- Os 207 do Dashboard eram `total - novos` = tudo que saiu de "Novo". Dentro deles,
-- 175 são apenas MENSAGEM ENVIADA e só 11 são conversa de verdade. A palavra
-- "Contatados" no cartão dava a entender 207 conversas.
--
-- Pior: a taxa de conversão dividia aferidos por esses 207, misturando mensagem
-- enviada com ligação atendida — dois canais com conversão completamente diferente.
-- Esta função separa os dois, para a pergunta certa: qual canal traz caminhão?
--
-- Definições (e os limites delas):
--   alcancados = leads que receberam aquele canal alguma vez;
--   aferiram   = desses, quantos têm um "Aferido" registrado DEPOIS do primeiro contato.
--   Os dois grupos se sobrepõem (um lead pode ter recebido mensagem e ligação) —
--   por isso `ambos` vem junto: as taxas não somam, e a tela precisa dizer isso.
--   `veio_sozinho` = aferições sem nenhum contato antes; é o denominador que falta
--   para saber o quanto o app realmente move.
--
-- "Ligação atendida" é só quem pegou o telefone: atendeu, agendou, reagendar,
-- recusou ou autorizou WhatsApp. Número inválido e não atendeu não contam como
-- contato — foi tentativa, não conversa.
--
-- Primeira leitura (14/09), e ela contraria o que a gente supunha:
--   São Bernardo  mensagem 1/192 (0,5%) · ligação atendida 0/18 · 6 vieram sozinhos
--   Santo André   mensagem 8/302 (2,6%) · ligação atendida 0/13 · 0 vieram sozinhos
--   TODAS         mensagem 9/494 (1,8%) · ligação atendida 0/31
-- As 9 aferições atribuíveis vieram TODAS de mensagem. Ligação atendida: zero em 31.
-- Amostra pequena e enviesada (as ligações foram para vencidos antigos e clientes de
-- concorrente), mas é o que existe — e desmonta a leitura de que "o canal certo para
-- quem não é cliente é a ligação". Rever antes de mandar a equipe ligar mais.

create or replace function public.conversao_por_canal(p_unidade uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  with alvo as (
    select c.id, c.unidade_id
      from public.caminhoneiros c
     where (p_unidade is null or c.unidade_id = p_unidade)
       and public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao)
  ),
  msg as (
    select l.caminhoneiro_id as id, min(l.created_at) as quando
      from public.ligacoes l join alvo a on a.id = l.caminhoneiro_id
     where l.canal = 'whatsapp'
     group by 1
  ),
  lig as (
    select l.caminhoneiro_id as id, min(l.created_at) as quando
      from public.ligacoes l join alvo a on a.id = l.caminhoneiro_id
     where l.canal in ('ligacao_ativa','ligacao_passiva')
       and l.resultado in ('atendeu','agendou','reagendar','recusou','autorizou_whatsapp')
     group by 1
  ),
  afer as (
    select l.caminhoneiro_id as id, min(l.created_at) as quando
      from public.ligacoes l join alvo a on a.id = l.caminhoneiro_id
     where l.canal = 'presencial' and l.resultado = 'aferido'
     group by 1
  )
  select jsonb_build_object(
    'mensagem', jsonb_build_object(
      'alcancados', (select count(*) from msg),
      'aferiram',   (select count(*) from msg join afer f on f.id = msg.id and f.quando > msg.quando)),
    'ligacao', jsonb_build_object(
      'alcancados', (select count(*) from lig),
      'aferiram',   (select count(*) from lig join afer f on f.id = lig.id and f.quando > lig.quando)),
    'ambos',        (select count(*) from msg join lig on lig.id = msg.id),
    'veio_sozinho', (select count(*) from afer
                      where not exists (select 1 from msg where msg.id = afer.id and msg.quando < afer.quando)
                        and not exists (select 1 from lig where lig.id = afer.id and lig.quando < afer.quando)),
    'aferidos_total', (select count(*) from afer)
  ) into v;

  return v;
end $$;
revoke all on function public.conversao_por_canal(uuid) from public, anon;
grant execute on function public.conversao_por_canal(uuid) to authenticated, service_role;
