-- [aplicada no banco em 09/09/2026 14:41 — versão 20260909144148]
-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)

-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)
-- ── 0047 — DIASTUR: os 431 veículos ─────────────────────────────────────────
--
-- Planilha "consolidada" enviada pelo Raphael em 09/09, já revisada por eles:
-- 431 linhas, sem placa repetida, sem número interno repetido, os 4 pares
-- duplicados da versão anterior resolvidos. Zero delas existe na base do RNTRC
-- — confirmado por cruzamento — porque frota com contrato não vem do RNTRC.
-- Logo: 431 criações, 0 movimentações, nenhum histórico em risco.
--
-- `data_ultima_afericao` = vencimento − 2 anos. O app guarda a aferição e
-- calcula o vencimento; guardar o vencimento direto quebraria todo o resto.
--
-- `posto_afericao` = Tacorrei porque é cliente com contrato: a última aferição
-- foi conosco. É isso que faz o veículo aparecer como cliente da casa se um dia
-- ele sair da empresa e voltar para a fila.

-- A placa passa a ser única por unidade SEMPRE — antes o índice ignorava
-- veículo de empresa, o que deixava a porta aberta para a mesma placa entrar
-- duas vezes por frotas diferentes.
drop index if exists public.uq_caminhoneiros_placa_unidade;
create unique index uq_caminhoneiros_placa_unidade
  on public.caminhoneiros (unidade_id, upper(regexp_replace(coalesce(placa_veiculo,''),'[^A-Z0-9]','','g')))
  where placa_veiculo is not null;

with alvo as (
  select (select id from public.unidades where nome = 'Tacorrei São Bernardo') as unidade_id,
         (select id from public.empresas where cnpj = '48.424.774/0001-76') as empresa_id
),
dados(placa, numero, venc, obs) as (values
  -- (… linhas de dados omitidas …)
)
insert into public.caminhoneiros
  (nome, telefone, cidade, uf, placa_veiculo, origem, status, observacoes,
   data_ultima_afericao, tem_tacografo, whatsapp_invalido, unidade_id,
   posto_afericao, autorizou_whatsapp, empresa_id, numero_empresa)
select
  'DIASTUR TURISMO LTDA',
  '',                                   -- NOT NULL; o contato é presencial
  'São Bernardo do Campo', 'SP',
  d.placa, 'outro', 'novo',
  case when d.obs = 'M' then 'Cadastro em placa antiga → convertida p/ Mercosul' else d.obs end,
  (d.venc - interval '2 years')::date,  -- o app guarda a AFERIÇÃO, não o vencimento
  true,                                 -- é frota de ônibus: todos têm tacógrafo
  false,
  a.unidade_id,
  'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.',
  false,
  a.empresa_id,
  d.numero
from dados d cross join alvo a
where a.empresa_id is not null and a.unidade_id is not null;
