-- 0092 — Ribeirão Pires passa para Santo André
--
-- 13/09, Emerson: "descobri que ribeirão tem nas duas unidades. os últimos de
-- ribeirão são para ficar na unidade de santo andré."
-- Na importação de hoje (0090) eu tinha posto Ribeirão Pires em São Bernardo, por
-- orientação dele na hora ("tem Ribeirão Pires que são de São Bernardo"). Conferido
-- na base: dos 434 caminhões importados, 15 aferiram na Lacre e 4 na Tacorrei — os
-- dois postos realmente atendem a cidade. A decisão dele é Santo André.
--
-- Escopo (escolhido por ele): SÓ a carga de hoje.
--   31 empresas + 434 placas criadas em 13/09  → Santo André
--   109 placas de autônomos de Ribeirão da carga de agosto → ficam em São Bernardo
--
-- A cidade muda de dono junto: `unidade_cidades` tem índice único em lower(cidade),
-- então uma cidade pertence a UMA unidade — e é essa tabela que o gatilho
-- `set_unidade_caminhoneiro` usa para decidir onde cai lead novo. Sem mover a cidade,
-- o próximo lead de Ribeirão voltaria para São Bernardo.
--
-- Ensaio com rollback antes de aplicar: 31 empresas, 434 placas, e NADA pendurado
-- nelas (0 ligações, 0 agendamentos, 0 histórico de posto, 0 pontos) — eram leads
-- criados hoje e ainda não trabalhados. Fila: SBC 4.753 → 4.596, SA 1.979 → 2.136.
-- Conferência depois: 28/28.

do $$
declare
  v_sbc uuid := '265f0c74-123e-4886-9683-b70793c30b61';
  v_sa  uuid := '146237d6-5983-4986-b4bd-51f9e1d690c3';
  v_eu  uuid;
  n_emp int; n_cam int;
begin
  select user_id into v_eu from public.equipe
   where papel = 'admin' and ativo and unidade_id is null order by nome limit 1;

  create temp table alvo_emp on commit drop as
    select id from public.empresas
     where unidade_id = v_sbc and created_at::date = date '2026-09-13';
  create temp table alvo_cam on commit drop as
    select id from public.caminhoneiros
     where unidade_id = v_sbc and created_at::date = date '2026-09-13';

  select count(*) into n_emp from alvo_emp;
  select count(*) into n_cam from alvo_cam;
  if n_emp <> 31 or n_cam <> 434 then
    raise exception 'esperava 31 empresas e 434 placas, achei % e % — nao aplico as cegas', n_emp, n_cam;
  end if;

  update public.empresas       set unidade_id = v_sa where id in (select id from alvo_emp);
  update public.caminhoneiros  set unidade_id = v_sa where id in (select id from alvo_cam);
  update public.ligacoes       set unidade_id = v_sa
   where caminhoneiro_id in (select id from alvo_cam) or empresa_id in (select id from alvo_emp);
  update public.agendamentos   set unidade_id = v_sa where caminhoneiro_id in (select id from alvo_cam);
  update public.historico_posto set unidade_id = v_sa where caminhoneiro_id in (select id from alvo_cam);

  -- a cidade acompanha: é ela que decide onde cai lead novo
  update public.unidade_cidades set unidade_id = v_sa where lower(cidade) = 'ribeirão pires';

  -- a importação original fica como está (ela REALMENTE foi feita para São Bernardo);
  -- o que muda de dono fica registrado como correção, com motivo.
  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, motivo, detalhe)
  values (v_eu, v_sa, 'mudanca_de_unidade', 'importacao',
          'Emerson, 13/09: Ribeirao Pires e atendida pelas duas unidades e os ultimos importados ficam em Santo Andre.',
          jsonb_build_object(
            'de', 'Tacorrei Sao Bernardo', 'para', 'Santo Andre',
            'rotulo_origem', 'Lacre 13/09 · SBC · lote 1',
            'empresas', n_emp, 'placas', n_cam,
            'cidade_movida', 'Ribeirão Pires',
            'ficaram_em_sbc', (select count(*) from public.caminhoneiros
                                where unidade_id = v_sbc and cidade ilike '%ribeir%')));
end $$;
