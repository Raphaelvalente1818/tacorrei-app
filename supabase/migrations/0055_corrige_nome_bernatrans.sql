-- [aplicada no banco em 09/09/2026 18:39 — versão 20260909183928]
-- ── 0055 — a segunda empresa é a BERNATRANS, não a BR7 ──────────────────────
-- Correção do Raphael. Mesma raiz de CNPJ (34.051.080), filial diferente:
-- 0001-26 era a matriz, e o contrato é com a filial 0002-07. BR7 Mobilidade é
-- a marca do grupo — fica anotada, porque é por ela que o cliente se apresenta.
--
-- Só o cadastro muda. Os 394 veículos continuam pendurados na mesma empresa
-- (o vínculo é por id, não por CNPJ), então nada precisa ser reimportado.
update public.empresas
   set nome = 'BERNATRANS TRANSPORTES URBANO S/A',
       cnpj = '34.051.080/0002-07',
       observacoes = 'Guia entregue em mãos — sem contato de WhatsApp por decisão do cliente. '
                     || 'Opera sob a marca BR7 Mobilidade.',
       updated_at = now()
 where cnpj = '34.051.080/0001-26';

-- O nome do proprietário nos veículos é o da empresa: acompanha.
update public.caminhoneiros c
   set nome = e.nome, updated_at = now()
  from public.empresas e
 where e.id = c.empresa_id
   and e.cnpj = '34.051.080/0002-07'
   and c.nome <> e.nome;
