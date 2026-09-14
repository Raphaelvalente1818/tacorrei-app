-- 0093 — Recaptura do posto de aferição: Santo André e Mauá
--
-- ATENÇÃO: como na 0090, as placas dos clientes NÃO estão neste arquivo (regra 12).
-- A carga foi feita a partir de uma tabela de apoio (`_stage_posto_sa` + `_stage_postos`)
-- montada com as duas extrações do Inmetro que o Emerson mandou em 14/09 e apagada
-- logo depois pela 0093b. O que está aqui é a lógica e o registro do que foi feito.
--
-- Os dois arquivos se completam (zero placas em comum):
--   "base maua santo andre.xlsx"             → Mauá,        1.103 placas, 375 com posto
--   "base santo andre Completa e ajustada"   → Santo André, 2.046 placas, 571 com posto
-- Juntas: 946 placas com posto. Casaram 100% com a base da unidade, zero desconhecidas.
--
-- Trava pedida pelo Emerson: "não trazer o posto daqueles que foram registrados que
-- vieram na nossa unidade". Implementada em DUAS camadas, porque uma só não bastava:
--   (a) tem aferição marcada no app (presencial/aferido) ......... 8 placas
--   (b) o app tem registro MAIS NOVO que o arquivo ............... 4 placas
-- Em todas as 12 o arquivo estava desatualizado. Duas (LYA7J30 e MCK7B01) são conquistas
-- de agosto/setembro que o arquivo ainda mostra no concorrente — sem a trava, elas
-- voltariam para 2024 e sumiriam do placar da Ivanessa. As outras 4 são os "aferiu em
-- outro posto" registrados pela operadora: o arquivo traz o nome real do concorrente,
-- mas com data de 2024, mais velha que o registro dela. Registro mais novo ganha.
--
-- O que entrou:
--   909 placas → só o nome do posto (a data já estava no cadastro e batia exatamente)
--    25 placas → posto + data; estavam como "sem tacógrafo" e têm. Entram na fila.
--
-- Resultado em Santo André:
--   posto conhecido na base ......... 1.442 → 2.376
--   "nossos" na régua ...................288 → 453
--   posto desconhecido na régua .........952 → 358
--   fila .............................2.136 → 2.151
--
-- NÃO gera histórico de posto: preencher o nome do posto para uma data que já estava no
-- cadastro é correção de cadastro, não movimento de cliente — geraria 934 eventos falsos
-- de conquista/fuga e estragaria o painel de sinais de fuga. Nenhuma linha do arquivo
-- trouxe data mais nova que a nossa, então nada de verdade deixou de ser registrado.
-- O silêncio usa a mesma chave da 0088: `aferimais.sem_historico`.
--
-- Conferência depois: 0 falhas, 0 protegidas alteradas, 0 linhas novas em historico_posto,
-- conferencia_contagens 28/28, testes_pontuacao 14/14.
--
-- Achado de brinde: o arquivo de Santo André traz uma coluna `Situacao` (ativa/inativa/
-- retirada). As 241 marcadas "inativa" estão TODAS vencidas pela nossa conta de 2 anos —
-- 100% de acerto. É a primeira validação externa da régua de validade.

do $$
declare
  v_sa uuid := '146237d6-5983-4986-b4bd-51f9e1d690c3';
  v_eu uuid; n_posto int; n_data int; n_nossas int;
  v_obs text := 'Sem consulta ao INMETRO: pode ter tacógrafo. Fora da fila até ser verificado.';
begin
  select user_id into v_eu from public.equipe
   where papel='admin' and ativo and unidade_id is null order by nome limit 1;

  -- o gatilho de histórico fica calado: isto é correção de cadastro
  perform set_config('aferimais.sem_historico', '1', true);

  -- 1. quem já tinha a data: só o nome do posto
  update public.caminhoneiros c
     set posto_afericao = s.posto
    from public._stage_posto_sa s
   where s.lead_id = c.id and s.acao = 'preencher_posto' and s.data_hoje is not null;
  get diagnostics n_posto = row_count;

  -- 2. quem estava sem data: ganha data e passa a ter tacógrafo (entra na fila)
  update public.caminhoneiros c
     set posto_afericao = s.posto,
         data_ultima_afericao = s.dt,
         tem_tacografo = true,
         observacoes = nullif(btrim(replace(coalesce(c.observacoes,''), v_obs, '')), '')
    from public._stage_posto_sa s
   where s.lead_id = c.id and s.acao = 'preencher_posto' and s.data_hoje is null;
  get diagnostics n_data = row_count;

  select count(*) into n_nossas from public._stage_posto_sa s
   where s.acao='preencher_posto' and (s.posto ilike '%LACRE%' or s.posto ilike '%TACORREI%');

  if n_posto + n_data <> 934 then
    raise exception 'esperava 934 atualizacoes, fiz % + % — nao gravo as cegas', n_posto, n_data;
  end if;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, motivo, detalhe)
  values (v_eu, v_sa, 'recaptura_posto', 'base',
          'Emerson, 14/09: recaptura do posto no Inmetro para Santo Andre e Maua, preservando o que foi registrado no app.',
          jsonb_build_object(
            'arquivos', 'base maua santo andre.xlsx + base santo andre Completa e ajustada.xlsx',
            'placas_no_arquivo', 946,
            'so_posto', n_posto, 'posto_e_data', n_data,
            'viram_nossas', n_nossas,
            'protegidas_afericao_no_app', (select count(*) from public._stage_posto_sa where acao='protegido_afericao_no_app'),
            'protegidas_app_mais_novo', (select count(*) from public._stage_posto_sa where acao='protegido_app_mais_novo'),
            'historico_suprimido', true));
end $$;

-- 0093b (aplicada em seguida): as tabelas de apoio saem, porque continham placas de cliente.
-- drop table if exists public._stage_posto_sa;
-- drop table if exists public._stage_postos;
