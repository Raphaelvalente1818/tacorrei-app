-- 0010_janela_dias_livre.sql
-- A 0008 travou a janela em 30 ou 60 dias. Na pratica o negocio quis 45,
-- entao a regra passa a ser "qualquer numero positivo de dias" (ou NULL = base toda).
-- Teto de 3650 dias (10 anos) so para barrar digitacao absurda; acima disso
-- o efeito ja seria o mesmo de "base toda".
alter table public.unidades drop constraint if exists unidades_janela_dias_check;

alter table public.unidades add constraint unidades_janela_dias_check
  check (janela_dias is null or (janela_dias > 0 and janela_dias <= 3650));

-- Estado aplicado em 19/08/2026: as duas unidades reais em 45 dias.
-- update unidades set janela_dias = 45 where nome in ('Santo André','Tacorrei São Bernardo');
