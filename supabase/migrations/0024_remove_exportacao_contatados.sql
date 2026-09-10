-- [aplicada no banco em 21/08/2026 14:02 — versão 20260821140218]
-- Revertendo a 0023 a pedido do Raphael (20/08/2026).
--
-- Motivo: a exportacao em planilha e, por natureza, uma porta de saida de dados
-- em massa. Mesmo restrita a admin e registrada no log, ela cria um arquivo que
-- sai do sistema e passa a viver fora de qualquer controle -- num e-mail, num
-- pendrive, num WhatsApp. O log prova QUE saiu; nao impede o que acontece depois.
--
-- Decisao: nao existir a porta e mais seguro que existir com guarda.
-- Se a necessidade voltar, a resposta preferivel e uma TELA de acompanhamento
-- (dados na tela, sem arquivo) em vez de exportacao.

drop function if exists public.exportar_contatados(uuid);

-- volta o log a aceitar so as duas acoes originais (nenhum registro 'exportar' foi gravado)
alter table public.acessos_lead drop constraint if exists acessos_lead_acao_check;
alter table public.acessos_lead add constraint acessos_lead_acao_check
  check (acao in ('listar','abrir'));
