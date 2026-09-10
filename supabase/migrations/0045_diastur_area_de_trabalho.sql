-- [aplicada no banco em 09/09/2026 14:32 — versão 20260909143246]

-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)
-- ── 0045 — DIASTUR: área de trabalho, empresa e campos novos ────────────────
--
-- NADA de veículo é vinculado aqui. Esta migration só prepara: cria a empresa,
-- os campos que faltavam, e uma tabela de trabalho com as 435 placas para a
-- conferência acontecer ANTES de mexer em lead nenhum.
--
-- Origem dos dados: planilha real da DIASTUR analisada em 04/09. As abas 2026,
-- 2027 e 2028 são a mesma lista repartida à mão — aqui viram uma coisa só.
-- As placas antigas já vêm convertidas para Mercosul (5º caractere: dígito
-- vira letra, 0→A … 9→J); a coluna `original` guarda como estava na planilha.

-- 1) Campos que a operação de frota exige ------------------------------------
-- O número interno é como a DIASTUR chama o caminhão dela. É por ele que a
-- relação mensal faz sentido para o cliente — placa ele não decora, número sim.
alter table public.caminhoneiros
  add column if not exists numero_empresa text;

comment on column public.caminhoneiros.numero_empresa is
  'Número interno do veículo na frota do cliente. Aparece na relação mensal.';

-- 2) A empresa ---------------------------------------------------------------
-- Contato e telefone ficam VAZIOS de propósito: na DIASTUR a guia é entregue
-- em mãos. A tela vai avisar que não há número para o aviso mensal — é o
-- comportamento certo, não um cadastro pela metade.
insert into public.empresas (unidade_id, cnpj, nome, contato, telefone, situacao, observacoes)
select u.id, '48.424.774/0001-76', 'DIASTUR TURISMO LTDA', null, null, 'contrato',
       'Guia entregue em mãos — sem contato de WhatsApp por decisão do cliente.'
from public.unidades u
where u.nome = 'Tacorrei São Bernardo'
on conflict do nothing;

-- 3) A área de trabalho ------------------------------------------------------
drop table if exists public._import_diastur;
create table public._import_diastur (
  placa text primary key,
  original text not null,
  numero_empresa text not null,
  vencimento date
);
alter table public._import_diastur enable row level security;

insert into public._import_diastur (placa, original, numero_empresa, vencimento) values
  -- (… linhas de dados omitidas …)
;
