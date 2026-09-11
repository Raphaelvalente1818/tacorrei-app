-- 0082 — testes_pontuacao(): a rede de proteção da função que vira dinheiro
--
-- Contexto (11/09/2026, item 1 do saneamento em saude-do-codigo.md). pontuar_afericao()
-- decide classe, pontos, bônus e DE QUEM é o ponto. Foi testada à mão no dia em que
-- nasceu (0067) e nunca mais. Esta função monta um cenário completo (empresa, caminhões,
-- contatos) numa transação, chama pontuar_afericao() para cada caso, confere o resultado
-- e DESFAZ TUDO — nada fica no banco. Uma linha por caso, ok = true/false.
--
-- Como roda:   select * from public.testes_pontuacao();
-- Quando roda: antes de qualquer migration que toque em pontos, e junto com a
--              conferencia_contagens() na rodada do dia 1º.
--
-- Mecânica do rollback: o cenário roda dentro de um bloco BEGIN … EXCEPTION; ao final o
-- bloco levanta uma exceção proposital (SQLSTATE 'TP001') carregando os resultados no
-- texto; o bloco externo captura, e o Postgres desfaz tudo que o bloco interno gravou.
-- Só o papel de leitura do Claude e o postgres podem chamar (ela escreve-e-desfaz, e usa
-- ids reais de operadoras como fixture).

create or replace function public.testes_pontuacao()
returns table (caso text, esperado text, obtido text, ok boolean)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_unidade uuid; v_opA uuid; v_opB uuid;
  v_emp uuid; v_emp2 uuid; v_emp_contrato uuid;
  v_hoje date := current_date;
  v_res jsonb := '[]'::jsonb;
  r record; v_lead uuid; v_lig uuid; v_txt text;
  prm record;

  -- helpers em SQL puro dentro do bloco (plpgsql não tem funções locais; usamos labels)
begin
  select * into prm from public.parametros_pontos where id = 1;
  select u.id into v_unidade from public.unidades u where u.nome ilike '%bernardo%' limit 1;
  select e.user_id into v_opA from public.equipe e where e.papel = 'operador' and e.unidade_id = v_unidade and e.ativo order by e.nome limit 1;
  select e.user_id into v_opB from public.equipe e where e.papel = 'operador' and e.unidade_id = v_unidade and e.ativo and e.user_id <> v_opA order by e.nome limit 1;
  if v_unidade is null or v_opA is null or v_opB is null then
    raise exception 'fixture: preciso da unidade SBC e de duas operadoras ativas';
  end if;

  begin
    -- ------------------------------------------------------------------
    -- fixtures
    -- ------------------------------------------------------------------
    insert into public.empresas (unidade_id, nome, situacao, ativo) values (v_unidade, 'ZZ TESTE PROSPECTO', 'prospecto', true) returning id into v_emp;
    insert into public.empresas (unidade_id, nome, situacao, ativo) values (v_unidade, 'ZZ TESTE PROSPECTO 2', 'prospecto', true) returning id into v_emp2;
    insert into public.empresas (unidade_id, nome, situacao, ativo) values (v_unidade, 'ZZ TESTE CONTRATO', 'contrato', true) returning id into v_emp_contrato;

    -- ------------------------------------------------------------------
    -- 1. autônomo do concorrente, em dia, ligação da operadora A há 10 dias
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 1', '11900000001', v_unidade, 'ZZT0A01', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'ligacao_ativa', 'atendeu', (v_hoje - 10)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.classe, p.pontos, p.bonus, p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '1 concorrente autônomo com contato de A',
      'esperado', format('conquista_avulso %s pts, operadora A', prm.conquista_avulso),
      'obtido', format('%s %s pts, %s', r.classe, r.pontos, case when r.operadora_id = v_opA then 'operadora A' else coalesce(r.operadora_id::text,'ninguém') end),
      'ok', r.classe = 'conquista_avulso' and r.pontos = prm.conquista_avulso and r.bonus = 0 and r.operadora_id = v_opA);

    -- ------------------------------------------------------------------
    -- 2. autônomo do concorrente, sem contato → veio sozinho
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 2', '11900000002', v_unidade, 'ZZT0A02', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.classe, p.pontos, p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '2 concorrente autônomo sem contato',
      'esperado', 'conquista_avulso, sem dona (veio sozinho)',
      'obtido', format('%s, %s', r.classe, case when r.operadora_id is null then 'sem dona' else 'com dona' end),
      'ok', r.classe = 'conquista_avulso' and r.operadora_id is null);

    -- ------------------------------------------------------------------
    -- 3. nosso, em dia → renovação
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 3', '11900000003', v_unidade, 'ZZT0A03', true, v_hoje - 700, 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'whatsapp', 'whatsapp_enviado', (v_hoje - 5)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.', v_hoje - 700);
    select p.classe, p.pontos, p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '3 nosso em dia, WhatsApp de A',
      'esperado', format('renovacao %s pts, operadora A', prm.renovacao),
      'obtido', format('%s %s pts, %s', r.classe, r.pontos, case when r.operadora_id = v_opA then 'operadora A' else 'outro' end),
      'ok', r.classe = 'renovacao' and r.pontos = prm.renovacao and r.operadora_id = v_opA);

    -- ------------------------------------------------------------------
    -- 4. nosso, vencido há 100 dias → vencido (vale mais que renovação)
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 4', '11900000004', v_unidade, 'ZZT0A04', true, v_hoje - 730 - 100, 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'ligacao_ativa', 'atendeu', (v_hoje - 2)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.', v_hoje - 730 - 100);
    select p.classe, p.pontos into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '4 nosso vencido há 100 dias',
      'esperado', format('vencido %s pts', prm.vencido), 'obtido', format('%s %s pts', r.classe, r.pontos),
      'ok', r.classe = 'vencido' and r.pontos = prm.vencido);

    -- ------------------------------------------------------------------
    -- 5. concorrente vencido há 30 dias (dentro da carência de 60) → conquista, não "vencido"
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 5', '11900000005', v_unidade, 'ZZT0A05', true, v_hoje - 730 - 30, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 730 - 30);
    select p.classe, p.pontos into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '5 concorrente vencido há 30 dias (carência)',
      'esperado', 'conquista_avulso', 'obtido', r.classe, 'ok', r.classe = 'conquista_avulso');

    -- ------------------------------------------------------------------
    -- 6. frota virgem, contato COM A EMPRESA há 5 dias (operadora B) → virgem + empresa conquistada
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status, empresa_id)
    values ('ZZ Teste 6', '11900000006', v_unidade, 'ZZT0A06', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo', v_emp) returning id into v_lead;
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status, empresa_id)
    values ('ZZ Teste 7', '11900000007', v_unidade, 'ZZT0A07', true, v_hoje - 650, 'OUTRO POSTO (concorrente)', 'novo', v_emp);
    insert into public.ligacoes (empresa_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_emp, v_unidade, v_opB, 'ligacao_ativa', 'atendeu', (v_hoje - 5)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.classe, p.pontos, p.bonus, p.empresa_conquistada, p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '6 frota virgem, contato com a empresa (B)',
      'esperado', format('conquista_virgem %s + bônus %s, empresa conquistada, operadora B', prm.conquista_virgem, prm.bonus_empresa),
      'obtido', format('%s %s + %s, %s, %s', r.classe, r.pontos, r.bonus, case when r.empresa_conquistada then 'conquistada' else 'não' end, case when r.operadora_id = v_opB then 'operadora B' else 'outra' end),
      'ok', r.classe = 'conquista_virgem' and r.pontos = prm.conquista_virgem and r.bonus = prm.bonus_empresa and r.empresa_conquistada and r.operadora_id = v_opB);

    -- ------------------------------------------------------------------
    -- 7. segunda placa da mesma empresa, depois que a primeira virou nossa → mista, sem bônus
    -- ------------------------------------------------------------------
    update public.caminhoneiros set posto_afericao = 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.', data_ultima_afericao = v_hoje where id = v_lead;
    select c.id into v_lead from public.caminhoneiros c where c.placa_veiculo = 'ZZT0A07';
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 650);
    select p.classe, p.pontos, p.bonus, p.empresa_conquistada, p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '7 segunda placa da empresa já conquistada',
      'esperado', format('conquista_mista %s pts, sem bônus, operadora B (contato da empresa vale)', prm.conquista_mista),
      'obtido', format('%s %s pts, bônus %s, %s', r.classe, r.pontos, r.bonus, case when r.operadora_id = v_opB then 'operadora B' else 'outra' end),
      'ok', r.classe = 'conquista_mista' and r.pontos = prm.conquista_mista and r.bonus = 0 and not r.empresa_conquistada and r.operadora_id = v_opB);

    -- ------------------------------------------------------------------
    -- 8. frota com contrato → 1 ponto, sem bônus mesmo sem nossos
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status, empresa_id)
    values ('ZZ Teste 8', '11900000008', v_unidade, 'ZZT0A08', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo', v_emp_contrato) returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.classe, p.pontos, p.bonus, p.empresa_conquistada into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '8 frota com contrato',
      'esperado', format('contrato %s pt, sem bônus', prm.contrato), 'obtido', format('%s %s pt, bônus %s', r.classe, r.pontos, r.bonus),
      'ok', r.classe = 'contrato' and r.pontos = prm.contrato and r.bonus = 0 and not r.empresa_conquistada);

    -- ------------------------------------------------------------------
    -- 9. dois contatos: A há 20 dias, B há 3 dias → o mais recente leva (B)
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 9', '11900000009', v_unidade, 'ZZT0A09', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'ligacao_ativa', 'atendeu', (v_hoje - 20)::timestamp),
           (v_lead, v_unidade, v_opB, 'ligacao_ativa', 'atendeu', (v_hoje - 3)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '9 dois contatos, o mais recente leva',
      'esperado', 'operadora B', 'obtido', case when r.operadora_id = v_opB then 'operadora B' when r.operadora_id = v_opA then 'operadora A' else 'ninguém' end,
      'ok', r.operadora_id = v_opB);

    -- ------------------------------------------------------------------
    -- 10. contato fora da janela (janela + 5 dias antes) → ninguém
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 10', '11900000010', v_unidade, 'ZZT0A10', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'ligacao_ativa', 'atendeu', (v_hoje - prm.janela_atribuicao_dias - 5)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', format('10 contato há %s dias (fora da janela de %s)', prm.janela_atribuicao_dias + 5, prm.janela_atribuicao_dias),
      'esperado', 'ninguém', 'obtido', case when r.operadora_id is null then 'ninguém' else 'alguém' end, 'ok', r.operadora_id is null);

    -- ------------------------------------------------------------------
    -- 11. "aferiu em outro posto" (sistema/atualizacao) não é contato → ninguém
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 11', '11900000011', v_unidade, 'ZZT0A11', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'sistema', 'atualizacao', (v_hoje - 3)::timestamp);
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '11 registro de sistema não é contato',
      'esperado', 'ninguém', 'obtido', case when r.operadora_id is null then 'ninguém' else 'alguém' end, 'ok', r.operadora_id is null);

    -- ------------------------------------------------------------------
    -- 12. contato registrado DEPOIS da aferição não conta
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status)
    values ('ZZ Teste 12', '11900000012', v_unidade, 'ZZT0A12', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo') returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, created_at)
    values (v_lead, v_unidade, v_opA, 'ligacao_ativa', 'atendeu', (v_hoje - 8)::timestamp + interval '10 hours');
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje - 10, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.operadora_id into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '12 aferição há 10 dias, contato há 8 (depois dela)',
      'esperado', 'ninguém', 'obtido', case when r.operadora_id is null then 'ninguém' else 'alguém' end, 'ok', r.operadora_id is null);

    -- ------------------------------------------------------------------
    -- 13. o bônus de empresa conquistada é UM por empresa: outra placa da empresa 2, com a
    --     empresa 2 já conquistada em outra aferição do mesmo cenário
    -- ------------------------------------------------------------------
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status, empresa_id)
    values ('ZZ Teste 13a', '11900000013', v_unidade, 'ZZT0A13', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo', v_emp2) returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    insert into public.caminhoneiros (nome, telefone, unidade_id, placa_veiculo, tem_tacografo, data_ultima_afericao, posto_afericao, status, empresa_id)
    values ('ZZ Teste 13b', '11900000014', v_unidade, 'ZZT0A14', true, v_hoje - 700, 'OUTRO POSTO (concorrente)', 'novo', v_emp2) returning id into v_lead;
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado)
    values (v_lead, v_unidade, v_opA, 'presencial', 'aferido') returning id into v_lig;
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select p.bonus, p.empresa_conquistada into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '13 bônus de empresa é um só por empresa',
      'esperado', 'segunda placa sem bônus', 'obtido', format('bônus %s', r.bonus), 'ok', r.bonus = 0 and not r.empresa_conquistada);

    -- ------------------------------------------------------------------
    -- 14. idempotência: pontuar duas vezes a mesma aferição não duplica
    -- ------------------------------------------------------------------
    perform public.pontuar_afericao(v_lead, v_hoje, v_lig, 'OUTRO POSTO (concorrente)', v_hoje - 700);
    select count(*) as n into r from public.pontos p where p.ligacao_id = v_lig;
    v_res := v_res || jsonb_build_object('caso', '14 pontuar duas vezes a mesma aferição',
      'esperado', '1 registro', 'obtido', format('%s registro(s)', r.n), 'ok', r.n = 1);

    -- desfaz tudo: a exceção proposital carrega o resultado
    raise exception using errcode = 'TP001', message = v_res::text;
  exception
    when sqlstate 'TP001' then
      v_txt := sqlerrm;
  end;

  return query
    select x->>'caso', x->>'esperado', x->>'obtido', (x->>'ok')::boolean
      from jsonb_array_elements(v_txt::jsonb) x;
end $$;

revoke execute on function public.testes_pontuacao() from public, anon, authenticated;
grant execute on function public.testes_pontuacao() to supabase_read_only_user, service_role;
