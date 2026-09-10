-- [aplicada no banco em 09/09/2026 18:32 — versão 20260909183200]

-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)
-- ── 0052 — BR7 Mobilidade: os 394 veículos ──────────────────────────────────
--
-- Cruzamento feito antes: nenhuma das 394 placas existe na base, nem no formato
-- Mercosul nem no antigo. São 394 criações, 0 movimentações — como na DIASTUR,
-- e pelo mesmo motivo: frota com contrato não vem do RNTRC.
--
-- Lê da área de trabalho `_import_br7`, que já passou pela conferência.
insert into public.caminhoneiros
  (nome, telefone, cidade, uf, placa_veiculo, origem, status, observacoes,
   data_ultima_afericao, tem_tacografo, whatsapp_invalido, unidade_id,
   posto_afericao, autorizou_whatsapp, empresa_id, numero_empresa)
select
  'BR7 MOBILIDADE',
  '',                                    -- NOT NULL; o contato é presencial
  'São Bernardo do Campo', 'SP',
  i.placa, 'outro', 'novo',
  case when i.original <> i.placa
       then 'Cadastro em placa antiga → convertida p/ Mercosul' end,
  (i.vencimento - interval '2 years')::date,   -- o app guarda a AFERIÇÃO
  true,                                  -- frota de ônibus: todos têm tacógrafo
  false,
  e.unidade_id,
  'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.',
  false,
  e.id,
  i.numero_empresa
from public._import_br7 i
cross join public.empresas e
where e.cnpj = '34.051.080/0001-26';

drop table if exists public._import_br7;
