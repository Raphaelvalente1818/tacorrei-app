-- [aplicada no banco em 09/09/2026 18:31 — versão 20260909183126]

-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)
-- ── 0051 — BR7: área de trabalho ────────────────────────────────────────────
-- Ainda NÃO vincula veículo nenhum. É só a lista, para o cruzamento com a base
-- acontecer antes de gravar. Diferente da DIASTUR, esta frota pode ter placas
-- que já existem como lead vindo do RNTRC — e nesse caso o registro é MOVIDO,
-- nunca duplicado, para não perder ligação nem mensagem já enviada.
--
-- Placas antigas convertidas para Mercosul (187 das 394); `original` guarda o
-- que veio na planilha, porque a base pode ter a placa no formato velho.
drop table if exists public._import_br7;
create table public._import_br7 (
  placa text primary key,
  original text not null,
  numero_empresa text not null,
  vencimento date
);
alter table public._import_br7 enable row level security;

insert into public._import_br7 (placa, original, numero_empresa, vencimento) values
  -- (… linhas de dados omitidas …)
;
