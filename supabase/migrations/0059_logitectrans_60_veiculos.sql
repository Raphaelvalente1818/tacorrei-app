-- [aplicada no banco em 09/09/2026 18:45 — versão 20260909184518]

-- ⚠️ DADOS DE CLIENTE OMITIDOS DE PROPÓSITO. As linhas de placas/números internos
-- foram retiradas deste arquivo: frota de cliente não vai para o git. O comando
-- está aqui pela estrutura e pela decisão; os dados vivem só no banco.
-- (por isso este arquivo NÃO pode ser reaplicado como está)
-- ── 0059 — Logitectrans: 60 veículos ────────────────────────────────────────
--
-- A planilha traz 61. A de nº 203 / DPE-5375 / venc 04/09/2027 é EXATAMENTE a
-- mesma linha que veio na planilha da Auto Viação ABC — mesmo número, placa e
-- data. E a própria planilha da Logitectrans anota "Frota não consta na aba
-- FROTAS", isto é, o 203 não está na lista de frota dela. Fica na ABC, onde já
-- está, e marcada lá para conferência. Se for da Logitectrans, é um update.
--
-- Placa gravada COMO ESTÁ no cadastro do cliente (60 antigas, 1 Mercosul).
insert into public.caminhoneiros
  (nome, telefone, cidade, uf, placa_veiculo, origem, status, observacoes,
   data_ultima_afericao, tem_tacografo, whatsapp_invalido, unidade_id,
   posto_afericao, autorizou_whatsapp, empresa_id, numero_empresa)
select 'LOGITECTRANS GERENCIAMENTO DE PROJETOS DE TRANSPORTES LTDA', '',
       'São Bernardo do Campo', 'SP',
       d.placa, 'outro', 'novo', d.obs,
       (d.venc - interval '2 years')::date,
       true, false, e.unidade_id,
       'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.',
       false, e.id, d.numero
from (values
) as d(placa, numero, venc, obs)
cross join public.empresas e
where e.cnpj = '11.076.765/0001-21';

-- A ABC fica com o aviso do 203, porque a dúvida é de lá também.
update public.caminhoneiros c
   set observacoes = 'CONFERIR: este ônibus também aparece na planilha da Logitectrans (mesmo nº, placa e data). Confirmar de qual empresa é.',
       updated_at = now()
  from public.empresas e
 where e.id = c.empresa_id and e.cnpj = '59.153.569/0005-63'
   and c.numero_empresa = '203';
