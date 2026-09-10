-- [aplicada no banco em 28/08/2026 17:29 — versão 20260828172901]
-- Coluna W da planilha do RNTRC: onde o veículo fez a ÚLTIMA aferição.
-- É o dado que separa "cliente da casa" de "cliente de concorrente" — distinção que
-- muda o canal de abordagem, não só o texto. Descoberta em 24/08, depois de a conta
-- de WhatsApp de São Bernardo ser restringida: das 20 mensagens daquele dia, 16 foram
-- para clientes de concorrentes, gente sem relação nenhuma com a Tacorrei.
alter table public.caminhoneiros
  add column if not exists posto_afericao text;

-- Postos do grupo. Tacorrei = São Bernardo, Lacre = Santo André.
-- Um cliente da Lacre que mora em São Bernardo continua sendo cliente do GRUPO —
-- por isso a função olha as duas marcas, não a unidade do lead.
create or replace function public.posto_do_grupo(p_posto text)
returns boolean language sql immutable
as $$
  select p_posto is not null
     and (p_posto ilike '%TACORREI%' or p_posto ilike '%LACRE%')
$$;

create index if not exists idx_caminhoneiros_posto on public.caminhoneiros (posto_afericao);

revoke execute on function public.posto_do_grupo(text) from public;
grant execute on function public.posto_do_grupo(text) to authenticated;
