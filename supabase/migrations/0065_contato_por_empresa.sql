-- 0065 — Contato no nível da empresa
--
-- Até aqui toda ligação tinha que ser pendurada numa placa. Numa frota a
-- conversa é com o gestor, não com o caminhão: uma ligação resolve vinte
-- placas. Sem isso, a operadora tem que escolher uma placa qualquer para
-- registrar — e a regra de atribuição de pontos (aferição precedida de
-- contato nos 45 dias) não tem como enxergar a frota inteira.
--
-- A ligação de empresa é UMA linha, não vinte. Se fosse uma por placa, os
-- números de produção do Dashboard inflariam 20× e ninguém confiaria mais
-- neles.
--
-- Nota: o banco também tem uma 0065b, que só corrigiu o corpo da função —
-- ela chamava registrar_acesso('contato_empresa'), e acessos_lead só aceita
-- 'listar' | 'abrir' | 'placa'. Este arquivo já está com a versão corrigida.

alter table public.ligacoes
  add column if not exists empresa_id uuid references public.empresas(id) on delete cascade;

alter table public.ligacoes alter column caminhoneiro_id drop not null;

alter table public.ligacoes drop constraint if exists ligacoes_alvo_ck;
alter table public.ligacoes add constraint ligacoes_alvo_ck
  check (caminhoneiro_id is not null or empresa_id is not null);

create index if not exists idx_ligacoes_empresa
  on public.ligacoes (empresa_id, created_at desc) where empresa_id is not null;

-- Registra o contato na empresa e faz ele DESCER para as placas que ainda
-- estão em aberto — é isso que tira a frota da fila de leads e evita que a
-- colega ligue de novo amanhã para o mesmo gestor.
--
-- 'agendou' é a exceção: agendamento é de caminhão, não de frota. Nesse caso
-- as outras placas ficam só como 'contatado'.
create or replace function public.registrar_ligacao_empresa(
  p_empresa   uuid,
  p_canal     text,
  p_resultado text,
  p_notas     text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_unidade uuid; v_status text; v_n integer; v_id uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select e.unidade_id into v_unidade
    from public.empresas e
   where e.id = p_empresa
     and e.ativo
     and (public.is_admin() or e.unidade_id = public.unidade_do_usuario());
  if v_unidade is null then
    raise exception 'empresa nao encontrada nesta unidade';
  end if;

  if p_canal not in ('ligacao_ativa','ligacao_passiva','presencial') then
    raise exception 'canal invalido: %', p_canal;
  end if;

  v_status := case p_resultado
    when 'atendeu'         then 'contatado'
    when 'nao_atendeu'     then 'sem_resposta'
    when 'numero_invalido' then 'invalido'
    when 'recusou'         then 'recusado'
    when 'agendou'         then 'contatado'
    when 'reagendar'       then 'contatado'
  end;
  if v_status is null then
    raise exception 'resultado invalido: %', p_resultado;
  end if;

  insert into public.ligacoes
    (empresa_id, caminhoneiro_id, operador_id, resultado, canal, notas, unidade_id)
  values
    (p_empresa, null, auth.uid(), p_resultado, p_canal,
     nullif(btrim(coalesce(p_notas,'')), ''), v_unidade)
  returning id into v_id;

  -- Só as placas em aberto. Quem já aferiu, já recusou ou já está agendado
  -- não é mexido por uma ligação de frota.
  update public.caminhoneiros c
     set status = v_status, updated_at = now()
   where c.empresa_id = p_empresa
     and c.status in ('novo','sem_resposta','contatado','mensagem_enviada');
  get diagnostics v_n = row_count;

  return jsonb_build_object('ligacao', v_id, 'veiculos', v_n, 'status', v_status);
end $$;

-- Função nova nasce com EXECUTE para PUBLIC (foi o que a 0016 revogou).
-- Todo arquivo novo precisa repetir isto.
revoke all on function public.registrar_ligacao_empresa(uuid, text, text, text) from public, anon;
grant execute on function public.registrar_ligacao_empresa(uuid, text, text, text)
  to authenticated, service_role;
