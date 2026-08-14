-- Campos de documento e vencimento da aferição do tacógrafo.
-- Já aplicado no projeto Supabase em 12/08/2026 (migration add_rntrc_renavam_data_ultima_afericao).

alter table public.caminhoneiros
  add column if not exists rntrc text,
  add column if not exists renavam text,
  add column if not exists data_ultima_afericao date;

-- Ordenação da lista de leads usa data_ultima_afericao (mais antiga = mais perto de vencer).
create index if not exists caminhoneiros_data_ultima_afericao_idx
  on public.caminhoneiros (data_ultima_afericao);
