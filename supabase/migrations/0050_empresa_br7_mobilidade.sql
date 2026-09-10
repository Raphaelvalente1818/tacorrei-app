-- [aplicada no banco em 09/09/2026 18:28 — versão 20260909182843]
-- ── 0050 — BR7 Mobilidade ───────────────────────────────────────────────────
-- Segunda empresa com contrato de São Bernardo. Como na DIASTUR, contato e
-- telefone ficam VAZIOS: a guia é entregue em mãos. A tela vai avisar que não
-- há número para o aviso mensal — é o comportamento certo, não cadastro pela
-- metade.
--
-- Só a empresa. Os veículos entram quando a planilha chegar.
insert into public.empresas (unidade_id, cnpj, nome, contato, telefone, situacao, observacoes)
select u.id, '34.051.080/0001-26', 'BR7 MOBILIDADE', null, null, 'contrato',
       'Guia entregue em mãos — sem contato de WhatsApp por decisão do cliente.'
from public.unidades u
where u.nome = 'Tacorrei São Bernardo'
on conflict do nothing;
