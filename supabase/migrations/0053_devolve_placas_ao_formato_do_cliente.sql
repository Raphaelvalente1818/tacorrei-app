-- [aplicada no banco em 09/09/2026 18:35 — versão 20260909183528]
-- ── 0053 — a placa volta ao formato do cadastro do cliente ──────────────────
--
-- Decisão do Raphael: guardar em Mercosul faz a operadora PERDER A REFERÊNCIA.
-- Ela trabalha olhando a lista da empresa, onde o caminhão é "FFA-5029"; se o
-- app mostra "FFA5A29", ela não reconhece o veículo. A conversão para Mercosul
-- é coisa da consulta ao INMETRO, e ela faz na hora.
--
-- Dá para desfazer sem reenviar planilha porque a conversão é bijetiva e as
-- convertidas ficaram marcadas na observação: 5º caractere volta de letra para
-- dígito (A→0 … J→9). Só mexe nas que têm a marca — as que já nasceram Mercosul
-- não são tocadas.

create or replace function public.desmercosul(p text)
returns text language sql immutable as $$
  select case
    when p ~ '^[A-Z]{3}[0-9][A-J][0-9]{2}$'
    then left(p,4) || translate(substr(p,5,1), 'ABCDEFGHIJ', '0123456789') || right(p,2)
    else p
  end;
$$;

comment on function public.desmercosul(text) is
  'Desfaz a conversão Mercosul: 5º caractere de letra para dígito. Usada na 0053.';

update public.caminhoneiros c
   set placa_veiculo = public.desmercosul(
         upper(regexp_replace(c.placa_veiculo,'[^A-Z0-9]','','g'))),
       -- A observação existia só para registrar a conversão que agora foi
       -- desfeita. Some, e o campo fica livre para a anotação de verdade.
       observacoes = case
         when c.observacoes = 'Cadastro em placa antiga → convertida p/ Mercosul' then null
         else replace(c.observacoes, 'Cadastro em placa antiga → convertida p/ Mercosul; ', '')
       end,
       updated_at = now()
 from public.empresas e
where e.id = c.empresa_id
  and e.cnpj in ('48.424.774/0001-76', '34.051.080/0001-26')
  and c.observacoes like 'Cadastro em placa antiga → convertida p/ Mercosul%';
