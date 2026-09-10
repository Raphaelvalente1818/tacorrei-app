-- [aplicada no banco em 09/09/2026 18:41 — versão 20260909184107]
-- ── 0056 — Auto Viação ABC ──────────────────────────────────────────────────
-- Terceira empresa com contrato. Mesmos padrões das duas anteriores, que o
-- Raphael não repetiu e eu assumi: São Bernardo, com contrato, guia em mãos
-- (contato e telefone vazios). Se algum deles for diferente, é um update de
-- uma linha — nada depende disso ainda porque não há veículo vinculado.
insert into public.empresas (unidade_id, cnpj, nome, contato, telefone, situacao, observacoes)
select u.id, '59.153.569/0005-63', 'AUTO VIAÇÃO ABC', null, null, 'contrato',
       'Guia entregue em mãos — sem contato de WhatsApp por decisão do cliente.'
from public.unidades u
where u.nome = 'Tacorrei São Bernardo'
on conflict do nothing;
