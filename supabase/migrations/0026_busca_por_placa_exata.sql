-- [aplicada no banco em 24/08/2026 15:03 — versão 20260824150352]
-- A operadora só enxerga a janela (45 dias). Em São Bernardo isso deixa 1.500 leads
-- da carteira invisíveis para ela. Agora que toda aferição de autônomo deve ser
-- registrada, o caminhão que aparece na porta fora da janela não podia ser achado —
-- e o "Novo lead" criaria uma placa duplicada, com a linha antiga guardando a data
-- velha e voltando para a fila depois.
--
-- Esta busca alcança a unidade INTEIRA, mas só por PLACA EXATA: é preciso já saber a
-- placa, volta no máximo 1 linha, e cada consulta fica registrada em `acessos_lead`
-- com a ação própria 'placa'. Não serve para enumerar base — serve para achar UM
-- caminhão que está fisicamente na oficina.
alter table public.acessos_lead drop constraint if exists acessos_lead_acao_check;
alter table public.acessos_lead add constraint acessos_lead_acao_check
  check (acao = any (array['listar','abrir','placa']));

-- Normaliza: maiúsculas, sem hífen/espaço/ponto. 'abc-1d23' e 'ABC1D23' são a mesma.
create or replace function public.normaliza_placa(p text)
returns text language sql immutable
as $$ select nullif(upper(regexp_replace(coalesce(p,''), '[^A-Za-z0-9]', '', 'g')), '') $$;

create or replace function public.buscar_por_placa(p_placa text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_placa text;
  v_lead  jsonb;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  v_placa := public.normaliza_placa(p_placa);

  -- Exige a placa inteira. Prefixo não busca: 3 caracteres devolveriam meia base.
  if v_placa is null or length(v_placa) < 7 then
    raise exception 'informe a placa completa (7 caracteres)';
  end if;

  select to_jsonb(c) into v_lead
  from public.caminhoneiros c
  where public.normaliza_placa(c.placa_veiculo) = v_placa
    and (public.is_admin() or c.unidade_id = public.unidade_do_usuario())
  order by c.data_ultima_afericao desc nulls last
  limit 1;

  perform public.registrar_acesso('placa', case when v_lead is null then 0 else 1 end,
    jsonb_build_object('placa', v_placa, 'achou', v_lead is not null));

  return v_lead;
end $function$;

revoke execute on function public.buscar_por_placa(text) from public;
grant execute on function public.buscar_por_placa(text) to authenticated;
revoke execute on function public.normaliza_placa(text) from public;
grant execute on function public.normaliza_placa(text) to authenticated;
