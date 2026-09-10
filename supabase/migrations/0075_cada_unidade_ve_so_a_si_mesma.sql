-- 0075 — Cada unidade enxerga só a si mesma
--
-- Em agosto o placar entre unidades e a aba Unidades foram feitos para
-- Tacorrei e Lacre se compararem e correrem atrás. Agora o Aferi+ vai ser
-- vendido para unidades de fora do grupo, e nenhuma unidade pode ver número
-- da outra — nem agregado. A comparação entre unidades passa a ser privilégio
-- do admin geral (o dono do produto).
--
-- Preparação para venda — o que AINDA está fixo no código (10/09):
--   1. posto_do_grupo() tem TACORREI/LACRE escritos a mão → ler de unidades.posto_afericao
--   2. marca/endereço das mensagens no frontend → colunas em unidades
--   3. parametros_pontos é global → por grupo
--   4. falta papel "admin de grupo" (dono de um cliente com 2+ unidades)

-- 1) Placar do Dashboard: operador e admin de unidade veem só a própria unidade.
create or replace function public.placar_unidades()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_inicio timestamptz; v_res jsonb; v_minha uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_minha := public.unidade_do_usuario();
  if v_minha is null and not public.is_admin() then return '[]'::jsonb; end if;

  v_inicio := date_trunc('month', (now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';

  select coalesce(jsonb_agg(x order by x.total desc, x.unidade), '[]'::jsonb) into v_res
  from (
    select u.nome as unidade, count(l.id) as total, (u.id = v_minha) as sua
    from public.unidades u
    left join public.ligacoes l
      on l.unidade_id = u.id and l.canal = 'whatsapp' and l.created_at >= v_inicio
    where public.is_admin() or u.id = v_minha
    group by u.id, u.nome
  ) x;
  return v_res;
end $$;

revoke all on function public.placar_unidades() from public, anon;
grant execute on function public.placar_unidades() to authenticated, service_role;

-- 2) Aba Unidades do Admin: admin de unidade vê só a dele.
create or replace function public.unidades_painel()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_res jsonb;
begin
  if not (public.is_admin() or public.is_admin_unidade()) then
    raise exception 'acesso negado';
  end if;

  select coalesce(jsonb_agg(x order by x.carteira desc, x.nome), '[]'::jsonb) into v_res
  from (
    select
      u.id, u.nome, u.janela_dias,
      (select string_agg(uc.cidade, ' · ' order by uc.cidade)
         from public.unidade_cidades uc where uc.unidade_id = u.id) as cidades,
      count(c.id) filter (where c.tem_tacografo) as carteira,
      count(c.id) filter (
        where c.tem_tacografo
          and (u.janela_dias is null
               or (c.data_ultima_afericao + interval '2 years')::date <= current_date + u.janela_dias)
      ) as fila,
      count(c.id) filter (where c.tem_tacografo and c.data_ultimo_whatsapp is not null) as abordados,
      count(c.id) filter (where c.status = 'aferido') as aferidos
    from public.unidades u
    left join public.caminhoneiros c on c.unidade_id = u.id
    where public.is_admin() or u.id = public.unidade_do_usuario()
    group by u.id, u.nome, u.janela_dias
  ) x;
  return v_res;
end $$;

revoke all on function public.unidades_painel() from public, anon;
grant execute on function public.unidades_painel() to authenticated, service_role;
