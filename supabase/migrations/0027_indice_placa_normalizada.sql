-- [aplicada no banco em 24/08/2026 15:04 — versão 20260824150400]
create index if not exists idx_caminhoneiros_placa_norm
  on public.caminhoneiros (public.normaliza_placa(placa_veiculo));
