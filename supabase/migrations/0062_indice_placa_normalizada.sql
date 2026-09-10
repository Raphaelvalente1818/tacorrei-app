-- [aplicada no banco em 09/09/2026 21:04 — versão 20260909210417]
-- Índice de apoio: com 17.973 veículos, cruzar placa normalizada sem índice
-- estoura o tempo limite. O índice único existente é por (unidade, placa) e
-- não serve para o cruzamento ENTRE unidades.
create index if not exists idx_cam_placa_norm
  on public.caminhoneiros (upper(regexp_replace(coalesce(placa_veiculo,''),'[^A-Z0-9]','','g')));
