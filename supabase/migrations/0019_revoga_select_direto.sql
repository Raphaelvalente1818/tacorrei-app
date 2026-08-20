-- 0019_revoga_select_direto.sql   [APLICADA em 19/08/2026, com o deploy 85636b3 no ar]
--
-- Fecha o achado CRITICO: com SELECT revogado, nao ha como pedir 1.000 registros
-- pela API. Toda leitura passa por listar_leads/obter_lead/contar_leads, que tem
-- teto de 100 e registram em `acessos_lead`.
--
-- O grant de SELECT so na coluna `id` e necessario: o PostgreSQL exige SELECT nas
-- colunas lidas no WHERE de um UPDATE, e a ficha atualiza por id.
--
-- DESFAZER EM EMERGENCIA:
--   grant select on public.caminhoneiros to authenticated;

revoke select on public.caminhoneiros from authenticated;
grant  select (id) on public.caminhoneiros to authenticated;
