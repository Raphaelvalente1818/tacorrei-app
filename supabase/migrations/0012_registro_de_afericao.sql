-- 0012_registro_de_afericao.sql
-- Botao "Aferido" na ficha do lead: a funcionaria grava a data em que o servico
-- foi feito. Isso fecha o funil (mensagem -> contato -> agendamento -> AFERICAO),
-- que ate agora terminava vazio, e alimenta o painel de producao enquanto a
-- Agenda de verdade nao existe.
--
-- O evento entra no historico de contatos como canal 'presencial' + resultado
-- 'aferido' -- assim fica registrado QUEM marcou e QUANDO, e a linha do tempo do
-- lead mostra o trajeto inteiro num lugar so.
--
-- Obs.: a data vai para `caminhoneiros.data_ultima_afericao`, o MESMO campo que
-- calcula o vencimento. Ou seja, o lead sai da fila agora e volta sozinho daqui
-- a 2 anos, virando recompra -- sem nenhuma rotina extra.

alter table public.ligacoes drop constraint if exists ligacoes_canal_check;
alter table public.ligacoes add constraint ligacoes_canal_check
  check (canal = any (array['ligacao_ativa','ligacao_passiva','whatsapp','presencial']));

alter table public.ligacoes drop constraint if exists ligacoes_resultado_check;
alter table public.ligacoes add constraint ligacoes_resultado_check
  check (resultado = any (array['atendeu','nao_atendeu','numero_invalido','recusou',
                               'agendou','reagendar','whatsapp_enviado','aferido']));
