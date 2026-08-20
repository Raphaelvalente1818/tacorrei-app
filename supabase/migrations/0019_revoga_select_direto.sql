-- 0019_revoga_select_direto.sql
-- ⚠️ NAO APLICAR ANTES DE O DEPLOY DA 0018 ESTAR NO AR.
-- Enquanto o app publicado ainda ler a tabela direto, esta migration DERRUBA
-- as telas de Leads, Ficha e Dashboard para todas as operadoras.
--
-- Ordem obrigatoria: (1) git push  ->  (2) conferir Leads/Ficha/Dashboard no ar
-- ->  (3) so entao rodar isto.
--
-- Fecha o achado CRITICO: com SELECT revogado, nao ha como pedir 1.000 registros
-- pela API. Toda leitura passa por listar_leads/obter_lead/contar_leads, que tem
-- teto de 100 e registram em `acessos_lead`.
--
-- O grant de SELECT so na coluna `id` e necessario: o PostgreSQL exige SELECT
-- nas colunas lidas no WHERE de um UPDATE, e a ficha atualiza por id.
-- Testado: UPDATE por id funciona, INSERT funciona, `select nome, telefone` falha.

revoke select on public.caminhoneiros from authenticated;
grant  select (id) on public.caminhoneiros to authenticated;

-- Para desfazer em emergencia:
--   grant select on public.caminhoneiros to authenticated;
