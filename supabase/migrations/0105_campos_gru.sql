-- 0105 — Campos da GRU no caminhoneiros (chassi, ano_fabricacao, endereco, cep, email).
-- Aplicada direto no banco em 23/09/2026 (migration caminhoneiros_campos_gru);
-- reconciliada como arquivo aqui (regra 13). O banco é a fonte da verdade.
alter table public.caminhoneiros
  add column if not exists chassi text,
  add column if not exists ano_fabricacao smallint,
  add column if not exists endereco text,
  add column if not exists cep text,
  add column if not exists email text;

alter table public.caminhoneiros
  add constraint caminhoneiros_chassi_tam check (chassi is null or length(chassi) <= 23),
  add constraint caminhoneiros_ano_fab_valido check (ano_fabricacao is null or ano_fabricacao between 1950 and 2100),
  add constraint caminhoneiros_cep_formato check (cep is null or cep ~ '^[0-9]{8}$');

comment on column public.caminhoneiros.chassi is 'Chassi exatamente como no CRLV (GRU Inmetro, max 23)';
comment on column public.caminhoneiros.ano_fabricacao is 'Ano de fabricacao do CRLV (GRU Inmetro)';
comment on column public.caminhoneiros.endereco is 'Endereco do proprietario (logradouro, numero, complemento, bairro)';
comment on column public.caminhoneiros.cep is 'CEP do proprietario, so digitos (8)';
comment on column public.caminhoneiros.email is 'E-mail do proprietario';
