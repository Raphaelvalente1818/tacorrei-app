-- 0097 — o documento do dono entra na base (CPF do autônomo, CNPJ da frota).
--
-- Por que faltava: as extrações do RNTRC sempre trouxeram a coluna CPF/CNPJ, e
-- o importador usa esse dado para criar a EMPRESA. Para o autônomo não havia
-- onde guardar — `caminhoneiros` não tinha coluna de documento — então a cada
-- carga o dado era lido e descartado. Resultado em 14/09: 2.920 autônomos na
-- régua sem nenhum identificador do dono.
--
-- Por que importa, mesmo sem robô de Inmetro nenhum:
--   1. Hoje não sabemos que cinco placas são do mesmo dono. Era isso que estava
--      por trás dos 41 telefones com três donos diferentes em São Bernardo
--      (0040). Com o documento, autônomo com quatro caminhões vira UMA conversa,
--      como já acontece com frota.
--   2. A consulta ao Inmetro que interessa é por CPF/CNPJ — uma consulta traz a
--      frota inteira do dono, inclusive o que ele aferiu no concorrente. Sem o
--      documento, só sobra placa a placa.
--
-- REGRA DESTA COLUNA: o documento NUNCA vai para a tela. Fica no banco, para o
-- servidor. O papel `authenticated` já só lê a coluna `id` de `caminhoneiros`,
-- então a leitura direta está fechada por construção — mas as funções que
-- devolvem a ficha inteira (`to_jsonb(c)`) precisavam ser costuradas, e são,
-- mais abaixo. Se um dia vazar uma tela, vaza sem CPF.
--
-- Vale a regra 12: este arquivo não carrega os dados, só o registro do que foi
-- feito. Os pares placa+documento foram carregados numa tabela de apoio
-- (`_stage_doc_0097`), aplicados e a tabela apagada na 0097b.

alter table public.caminhoneiros
  add column if not exists documento text;

alter table public.caminhoneiros
  drop constraint if exists caminhoneiros_documento_ck;
alter table public.caminhoneiros
  add constraint caminhoneiros_documento_ck
  check (documento is null or documento ~ '^[0-9]{11}$' or documento ~ '^[0-9]{14}$');

comment on column public.caminhoneiros.documento is
  'CPF (11 digitos) do autonomo ou CNPJ (14) do dono, so digitos. NUNCA vai para a tela: e chave de consulta e de agrupamento por dono, usada pelo servidor.';

-- Dois caminhões do mesmo dono precisam ser encontráveis um pelo outro.
create index if not exists caminhoneiros_documento_idx
  on public.caminhoneiros (unidade_id, documento)
  where documento is not null;

-- Tabela de apoio da carga. Some na 0097b.
create table if not exists public._stage_doc_0097 (
  placa text primary key,
  documento text not null
);
