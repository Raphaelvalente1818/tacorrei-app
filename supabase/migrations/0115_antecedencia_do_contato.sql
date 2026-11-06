-- 0115 — O CONTATO TEM QUE VIR ANTES DE O CAMINHÃO DECIDIR VIR (06/11)
--
-- Análise de outubro: em Santo André, 205 dos 284 pontos com dona nasceram de um
-- contato registrado MENOS DE UMA HORA antes do clique em Aferido — ligação
-- "atendida/autorizou" + mensagem + Aferido, com o caminhão já no balcão. É a
-- carona que o método previa ("impossível provar caso a caso") usada em escala,
-- e a auditoria pela OS não pega (o caminhão aferiu mesmo). Em São Bernardo o
-- padrão não existe (zero casos).
--
-- Decisão do Emerson: "vamos travar para novembro e já corrigir. Nada de alterar o
-- que foi feito — mantemos os dados intactos para a análise futura."
--
-- Regra: um contato só atribui ponto se foi registrado em DIA ANTERIOR ao da
-- aferição (`antecedencia_dias` = 1; comparado em dia de Brasília, para não
-- depender da hora em que a aferição é lançada). Contato no mesmo dia = "veio
-- sozinho" — e aí vale o ponto de balcão (0114) se o cadastro sair perfeito.
-- Vale para aferições com data a partir de `antecedencia_desde` (01/11/2026);
-- outubro e antes não mudam. Os dois parâmetros ficam na tabela do método.
--
-- A auditoria passa a mostrar quantas horas antes do Aferido o contato foi
-- registrado (`contato_horas_antes`), para o gestor enxergar a carona de fronteira
-- que a regra não pega (ex.: "ligação" na véspera para quem já tinha agendado).

alter table public.parametros_pontos
  add column if not exists antecedencia_dias integer not null default 1,
  add column if not exists antecedencia_desde date not null default date '2026-11-01';

-- 1) pontuar_afericao: o contato precisa ser de dia anterior
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.pontuar_afericao(uuid, date, uuid, text, date)'::regprocedure);
  if position('and l.created_at >= v_ini and l.created_at < v_fim order by l.created_at desc limit 1;' in v_def) = 0 then
    raise exception '0115: ancora da atribuicao nao encontrada';
  end if;
  v_def := replace(v_def,
    'and l.created_at >= v_ini and l.created_at < v_fim order by l.created_at desc limit 1;',
    'and l.created_at >= v_ini and l.created_at < v_fim '
    || 'and (p_data < prm.antecedencia_desde or (l.created_at at time zone ''America/Sao_Paulo'')::date <= p_data - coalesce(prm.antecedencia_dias, 0)) '
    || 'order by l.created_at desc limit 1;');
  execute v_def;
end $$;

-- 2) a auditoria mostra o relógio
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef((select oid from pg_proc where proname = 'montar_meta' and pronamespace = 'public'::regnamespace));
  if position('(select e2.nome from public.equipe e2 where e2.user_id = p.registrado_por) as marcado_por,' in v_def) = 0 then
    raise exception '0115: ancora da auditoria nao encontrada';
  end if;
  v_def := replace(v_def,
    '(select e2.nome from public.equipe e2 where e2.user_id = p.registrado_por) as marcado_por,',
    '(select e2.nome from public.equipe e2 where e2.user_id = p.registrado_por) as marcado_por,
             p.contato_em,
             (select round(extract(epoch from (lg.created_at - p.contato_em)) / 3600.0, 1)
                from public.ligacoes lg where lg.id = p.ligacao_id) as contato_horas_antes,');
  execute v_def;
end $$;
