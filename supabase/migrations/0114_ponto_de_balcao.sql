-- 0114 — PONTO DE BALCÃO: 1 PONTO PARA QUEM VEIO SOZINHO COM CADASTRO PERFEITO (28/10)
--
-- Contexto: a Pamela cadastrou 4 caminhões que aferiram no dia 27/10 sem nenhum
-- contato prévio — pela regra 11, "veio sozinho", zero ponto. O Emerson não quis
-- dar essa notícia e propôs 1 ponto para toda aferição sem contato. Com os
-- números na mão (outubro: 87 sozinhos em SBC contra 86 pontos das duas
-- operadoras trabalhando), isso pagaria mais o balcão do que a prospecção.
-- Decisão dele, com a alternativa: **1 ponto para o "veio sozinho" só quando o
-- cadastro sai perfeito do balcão** — CPF ou CNPJ, chassi, placa, RENAVAM de 11,
-- telefone confirmado com o dono E celular (11 dígitos, o que recebe WhatsApp).
-- Paga exatamente o que vale daqui a dois anos (a renovação com o número certo),
-- e dá à operadora um motivo para clicar Aferido e preencher. Vale a partir de
-- hoje, para o que for registrado daqui em diante (o ponto é congelado no registro).
--
-- Regras:
--   * só quando NÃO há contato atribuível nos 45 dias (senão o ponto normal manda);
--   * o ponto vai para quem clicou Aferido (`auth.uid()`), nunca para admin geral;
--   * a classe do caminhão continua a mesma (renovação, conquista…) — é o que a
--     carteira e a Meta usam; `pontos.balcao = true` marca a origem, e os pontos
--     passam a ser `parametros_pontos.balcao` (1), bônus zero;
--   * o fator da carteira (0,8 nas conquistas) não se aplica ao ponto de balcão
--     (floor(0,8) seria zero);
--   * `empresa_conquistada` continua sendo marcada (evita bônus duplo depois),
--     mas o bônus de empresa não vai para o balcão.

alter table public.parametros_pontos add column if not exists balcao integer not null default 1;
alter table public.pontos add column if not exists balcao boolean not null default false;

-- 1) pontuar_afericao: a decisão do balcão entra logo antes do insert
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.pontuar_afericao(uuid, date, uuid, text, date)'::regprocedure);
  if position('v_ini timestamptz; v_fim timestamptz; begin' in v_def) = 0
     or position('insert into public.pontos (ligacao_id,' in v_def) = 0
     or position('registrado_por, origem) values (' in v_def) = 0
     or position('then ''atrasado'' else ''app'' end) on conflict' in v_def) = 0 then
    raise exception '0114: ancoras de pontuar_afericao nao encontradas';
  end if;
  v_def := replace(v_def, 'v_ini timestamptz; v_fim timestamptz; begin',
                          'v_ini timestamptz; v_fim timestamptz; v_balcao boolean := false; begin');
  v_def := replace(v_def, 'insert into public.pontos (ligacao_id,',
    'if v_op is null and auth.uid() is not null '
    || 'and not exists (select 1 from public.equipe a where a.user_id = auth.uid() and a.papel = ''admin'') '
    || 'and cardinality(public.faltas_cadastro(p_lead, false)) = 0 '
    || 'and exists (select 1 from public.caminhoneiros cc where cc.id = p_lead and cc.fone_cls = 11) then '
    || 'v_balcao := true; v_op := auth.uid(); v_contato := null; v_contato_em := null; v_pontos := coalesce(prm.balcao, 1); v_bonus := 0; end if; '
    || 'insert into public.pontos (ligacao_id,');
  v_def := replace(v_def, 'registrado_por, origem) values (', 'registrado_por, origem, balcao) values (');
  v_def := replace(v_def, 'then ''atrasado'' else ''app'' end) on conflict', 'then ''atrasado'' else ''app'' end, v_balcao) on conflict');
  execute v_def;
end $$;

-- 2) o fator da carteira não pega o ponto de balcão (fechamento e resultado)
do $$
declare v_def text; v_nome text;
begin
  foreach v_nome in array array['public.fechar_mes_interno(uuid, date, jsonb, boolean, text, uuid)', 'public.resultado_do_mes(uuid, date)'] loop
    v_def := pg_get_functiondef(v_nome::regprocedure);
    if position('p.classe like ''conquista_%'' and not v_carteira_ok' in v_def) = 0 then
      raise exception '0114: ancora do fator nao encontrada em %', v_nome;
    end if;
    v_def := replace(v_def, 'p.classe like ''conquista_%'' and not v_carteira_ok',
                            'p.classe like ''conquista_%'' and not p.balcao and not v_carteira_ok');
    execute v_def;
  end loop;
end $$;

-- 3) a Meta mostra a origem "balcão" em cada ponto
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef((select oid from pg_proc where proname = 'montar_meta' and pronamespace = 'public'::regnamespace));
  if position('select p.id, p.data_afericao, p.registrado_em, p.classe, p.pontos, p.bonus,' in v_def) = 0 then
    raise exception '0114: ancora do detalhe nao encontrada';
  end if;
  v_def := replace(v_def, 'select p.id, p.data_afericao, p.registrado_em, p.classe, p.pontos, p.bonus,',
                          'select p.id, p.data_afericao, p.registrado_em, p.classe, p.pontos, p.bonus, p.balcao,');
  execute v_def;
end $$;
