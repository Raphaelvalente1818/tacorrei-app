-- [aplicada no banco em 09/09/2026 18:43 — versão 20260909184351]
-- ── 0058 — Logitectrans ─────────────────────────────────────────────────────
-- Quarta empresa com contrato. Mesmos padrões das anteriores: São Bernardo,
-- com contrato, guia em mãos (contato e telefone vazios).
insert into public.empresas (unidade_id, cnpj, nome, contato, telefone, situacao, observacoes)
select u.id, '11.076.765/0001-21',
       'LOGITECTRANS GERENCIAMENTO DE PROJETOS DE TRANSPORTES LTDA',
       null, null, 'contrato',
       'Guia entregue em mãos — sem contato de WhatsApp por decisão do cliente.'
from public.unidades u
where u.nome = 'Tacorrei São Bernardo'
on conflict do nothing;
