-- 0089 — "Meu dia" da operadora
--
-- Emerson, 12/09: "a operadora é quem precisa ficar atenta e receber as dicas do que fazer".
-- A tela inicial da operadora deixa de ser o Dashboard e vira o Meu dia dela — a mesma
-- ideia da tela do gestor, em primeira pessoa e sem nada que a faça torcer contra a colega:
--   1. Meus pontos no mês (e ontem), minhas aferições, o total da unidade.
--   2. Pé na porta sem contato há mais de 7 dias — a lista de quem ligar hoje.
--   3. "Novo" que ainda restam na fila do mês — o estoque da semana.
--   4. Nossos que vencem nos próximos 30 dias e ninguém tocou — a defesa da carteira
--      (o cliente cativo, que não dá ponto de conquista mas é a alma do negócio).
-- Só a própria operadora (ou quem tem unidade) chama; devolve o que a unidade dela tem.

create or replace function public.meu_dia_operadora()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid; v_uid uuid := auth.uid();
  v_comp date := date_trunc('month', current_date)::date;
  v_fim  date := (date_trunc('month', current_date) + interval '1 month')::date;
  v_eu jsonb; v_pe jsonb; v_pe_total integer; v_novos jsonb; v_defesa jsonb; v_painel jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_unidade := public.unidade_do_usuario();
  if v_unidade is null then raise exception 'usuario sem unidade'; end if;

  -- 1. eu, no mês
  select jsonb_build_object(
           'pontos', coalesce(sum(p.pontos + p.bonus) filter (where p.operadora_id = v_uid), 0),
           'ontem', coalesce(sum(p.pontos + p.bonus) filter (where p.operadora_id = v_uid and p.data_afericao = current_date - 1), 0),
           'afericoes', count(*) filter (where p.operadora_id = v_uid),
           'empresas', count(*) filter (where p.operadora_id = v_uid and p.empresa_conquistada),
           'unidade', coalesce(sum(p.pontos + p.bonus) filter (where p.operadora_id is not null), 0))
    into v_eu
  from public.pontos p
  where p.unidade_id = v_unidade and p.competencia = v_comp;

  -- 2. pé na porta sem contato há mais de 7 dias (mesma conta do gestor)
  v_painel := public.empresas_painel(v_unidade, null);
  select count(*) into v_pe_total
  from jsonb_array_elements(v_painel) x
  where x->>'classe' = 'mista' and (x->>'janela')::int > 0;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x->>'id', 'nome', x->>'nome', 'janela', (x->>'janela')::int,
           'ultima_abordagem', x->>'ultima_abordagem')
           order by (x->>'janela')::int desc, x->>'nome'), '[]'::jsonb) into v_pe
  from jsonb_array_elements(v_painel) x
  where x->>'classe' = 'mista'
    and (x->>'janela')::int > 0
    and (x->>'ultima_abordagem' is null or (x->>'ultima_abordagem')::timestamptz < now() - interval '7 days');

  -- 3. "Novo" na fila do mês
  select jsonb_build_object('novos', count(*) filter (where b.status = 'novo'), 'total', count(*)) into v_novos
  from public.base_trabalhavel(v_unidade) b
  where b.na_fila and b.venc < v_fim;

  -- 4. defesa: nossos (fora de contrato) vencendo em 30 dias, sem contato registrado
  --    desde a última aferição — ninguém lembrou o cliente da casa.
  select jsonb_build_object(
           'total', count(*),
           'sem_contato', count(*) filter (where not tocado),
           'lista', coalesce(jsonb_agg(jsonb_build_object('id', id, 'placa', placa, 'dono', dono, 'empresa', empresa, 'venc', venc)
                                       order by venc) filter (where not tocado), '[]'::jsonb))
    into v_defesa
  from (
    select b.id, c.placa_veiculo as placa, c.nome as dono, b.empresa_nome as empresa, b.venc,
           exists (select 1 from public.ligacoes l
                    where (l.caminhoneiro_id = b.id or (b.empresa_id is not null and l.empresa_id = b.empresa_id))
                      and l.canal in ('ligacao_ativa','ligacao_passiva','whatsapp')
                      and l.created_at > coalesce(b.data_ultima_afericao, date '2000-01-01')) as tocado
      from public.base_trabalhavel(v_unidade) b
      join public.caminhoneiros c on c.id = b.id
     where b.nosso and b.na_fila
       and b.venc between current_date and current_date + 30
     order by b.venc
     limit 200
  ) d;

  return jsonb_build_object(
    'hoje', current_date, 'competencia', v_comp,
    'eu', v_eu, 'pe_na_porta', v_pe, 'pe_na_porta_total', v_pe_total,
    'fila', v_novos, 'defesa', v_defesa
  );
end $$;
revoke all on function public.meu_dia_operadora() from public, anon;
grant execute on function public.meu_dia_operadora() to authenticated, service_role;
