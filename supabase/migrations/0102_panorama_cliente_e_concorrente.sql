-- 0102 — O PANORAMA DO ANO SEPARA CLIENTE DE CONCORRENTE (16/09)
--
-- O Emerson olhou o gráfico e perguntou: "não pode vir o total dividido por
-- Cliente e Concorrente?". Pode, e é a pergunta certa: o mesmo mês com 200
-- vencimentos é um mês bem diferente se 150 são clientes da casa (basta lembrar
-- que está vencendo) ou se 150 são do concorrente (é conquista, não lembrete).
-- O número sozinho não diz qual esforço o mês pede.
--
-- Três fatias, não duas. `base_trabalhavel` já sabe quem é `nosso` (última
-- aferição num posto do grupo) e quem tem `posto_conhecido`. Só que Santo André
-- tem 167 caminhões sem posto na base (a coluna W nunca veio para eles). Chamar
-- esses de "concorrente" seria mentir no gráfico — eles são "não sabemos". Então
-- cada mês devolve cliente + concorrente + desconhecido, e o front só desenha a
-- terceira fatia quando ela existe (em São Bernardo é zero).
--
-- A chave `total` continua por mês e no todo: o front antigo, se ainda estiver
-- em cache, segue funcionando. Continua sem nome, sem placa, sem telefone.
--
-- Medido em 16/09 (janela de 12 meses, só na_fila):
--   São Bernardo  cliente 489 · concorrente 1.632 · desconhecido 0   = 2.121
--   Santo André   cliente 208 · concorrente   637 · desconhecido 167 = 1.012

create or replace function public.panorama_do_ano(p_unidade uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v jsonb; v_uni uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  v_uni := coalesce(p_unidade, public.unidade_do_usuario());
  if not (public.is_admin() or v_uni = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  select jsonb_build_object(
    'meses', coalesce(jsonb_agg(jsonb_build_object(
                'mes', x.mes,
                'total', x.total,
                'cliente', x.cliente,
                'concorrente', x.concorrente,
                'desconhecido', x.desconhecido)
              order by x.mes), '[]'::jsonb),
    'total',        coalesce(sum(x.total), 0),
    'cliente',      coalesce(sum(x.cliente), 0),
    'concorrente',  coalesce(sum(x.concorrente), 0),
    'desconhecido', coalesce(sum(x.desconhecido), 0)
  ) into v
  from (
    select to_char(b.venc, 'YYYY-MM') as mes,
           count(*) as total,
           count(*) filter (where b.nosso) as cliente,
           count(*) filter (where b.posto_conhecido and not b.nosso) as concorrente,
           count(*) filter (where not b.posto_conhecido) as desconhecido
      from public.base_trabalhavel(v_uni) b
     where b.na_fila
       and b.venc >= date_trunc('month', current_date)::date
       and b.venc < (date_trunc('month', current_date) + interval '12 months')::date
     group by 1
  ) x;

  return v;
end $function$;
