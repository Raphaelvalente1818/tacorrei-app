-- [aplicada no banco em 09/09/2026 14:35 — versão 20260909143529]
-- ── 0046 — fora a planilha de 04/09 ────────────────────────────────────────
-- O Raphael vai mandar a base da DIASTUR já revisada por eles. A de 04/09
-- ficou desatualizada (apontava 102 vencidos, número que eles já corrigiram),
-- e manter as duas convida ao erro de importar a errada.
--
-- A empresa e o campo `numero_empresa` da migration 0045 continuam de pé:
-- nenhum veículo foi vinculado, então não há o que reverter.
drop table if exists public._import_diastur;
