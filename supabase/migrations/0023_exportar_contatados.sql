-- [aplicada no banco em 21/08/2026 13:58 — versão 20260821135840]
-- Exportacao de leads contatados, em planilha. SO ADMIN (nem admin_unidade).
--
-- Contexto: esta e a UNICA saida de dados em massa do sistema, e existe de
-- proposito -- o admin e o dono do dado. Por isso ela e registrada em
-- `acessos_lead` com acao 'exportar' e a quantidade de linhas: se um dia houver
-- duvida sobre um vazamento, o log mostra quem exportou, quando e quanto.
--
-- O que conta como CONTATO: ligacao ativa, ligacao passiva ou WhatsApp.
-- O canal 'presencial' (registro do botao Aferido) NAO conta -- ele e o servico,
-- nao uma abordagem. Sem isso, um walk-in que nunca foi abordado apareceria na
-- lista de "contatados" e falsearia a leitura.
--
-- ⚠️ REVERTIDA NA 0024, no mesmo dia. Fica aqui como registro da decisão.

-- o log precisa aceitar a nova acao
alter table public.acessos_lead drop constraint if exists acessos_lead_acao_check;
alter table public.acessos_lead add constraint acessos_lead_acao_check
  check (acao in ('listar','abrir','exportar'));

create or replace function public.exportar_contatados(p_unidade uuid default null)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_res jsonb;
begin
  if not public.is_admin() then
    raise exception 'acesso negado';
  end if;

  select coalesce(jsonb_agg(x order by x.ultimo_contato desc), '[]'::jsonb)
    into v_res
  from (
    select
      u.nome                                   as unidade,
      c.nome                                   as nome,
      c.placa_veiculo                          as placa,
      c.renavam                                as renavam,
      max(l.created_at)                        as ultimo_contato,
      (array_agg(l.canal order by l.created_at desc))[1] as canal_ultimo,
      count(l.id)                              as qtd_contatos,
      (c.status = 'aferido')                   as aferido,
      c.data_ultima_afericao                   as data_afericao
    from public.caminhoneiros c
    join public.ligacoes l
      on l.caminhoneiro_id = c.id
     and l.canal in ('ligacao_ativa','ligacao_passiva','whatsapp')
    join public.unidades u on u.id = c.unidade_id
    where (p_unidade is null or c.unidade_id = p_unidade)
    group by c.id, c.nome, c.placa_veiculo, c.renavam, c.status, c.data_ultima_afericao, u.nome
  ) x;

  perform public.registrar_acesso(
    'exportar',
    jsonb_array_length(v_res),
    jsonb_build_object('tipo', 'contatados', 'unidade', p_unidade)
  );

  return v_res;
end $$;

revoke execute on function public.exportar_contatados(uuid) from public, anon;
grant  execute on function public.exportar_contatados(uuid) to authenticated;
