-- Veículos "NENHUM RESULTADO" na planilha original = tipo Fiorino/sem tacógrafo → fora do
-- público-alvo (não devem receber contato de aferição). Já aplicado em 14/08/2026.
-- Na importação esses viraram data_ultima_afericao NULL; o único NULL que NÃO é "NENHUM
-- RESULTADO" é a placa FQJ3B04 (estava em branco), mantida como tem_tacografo = true.

alter table public.caminhoneiros
  add column if not exists tem_tacografo boolean not null default true;

update public.caminhoneiros
  set tem_tacografo = false
  where data_ultima_afericao is null
    and placa_veiculo is distinct from 'FQJ3B04';
