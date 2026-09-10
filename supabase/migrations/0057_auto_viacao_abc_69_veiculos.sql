-- [aplicada no banco em 09/09/2026 18:42 — versão 20260909184230]

-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)
-- ── 0057 — Auto Viação ABC: 69 veículos ─────────────────────────────────────
--
-- A planilha traz 70 linhas, mas a placa DPE-4785 aparece em DOIS ônibus:
-- frota 147 (venc 10/03/2028) e frota 139 (venc 11/03/2028). Dois números
-- internos, dias seguidos — repetição de digitação, não dois veículos com a
-- mesma placa. Entra o 147; o 139 fica de fora até a operadora conferir, e o
-- 147 carrega a anotação para ninguém esquecer.
--
-- A placa é gravada COMO ESTÁ no cadastro do cliente (69 no formato antigo,
-- 1 em Mercosul). Converter faria a operadora perder a referência; a conversão
-- para o INMETRO ela faz na hora da consulta, e a busca do app já aceita os
-- dois formatos.
insert into public.caminhoneiros
  (nome, telefone, cidade, uf, placa_veiculo, origem, status, observacoes,
   data_ultima_afericao, tem_tacografo, whatsapp_invalido, unidade_id,
   posto_afericao, autorizou_whatsapp, empresa_id, numero_empresa)
select 'AUTO VIAÇÃO ABC', '', 'São Bernardo do Campo', 'SP',
       d.placa, 'outro', 'novo', d.obs,
       (d.venc - interval '2 years')::date,
       true, false, e.unidade_id,
       'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.',
       false, e.id, d.numero
from (values
) as d(placa, numero, venc, obs)
cross join public.empresas e
where e.cnpj = '59.153.569/0005-63';
