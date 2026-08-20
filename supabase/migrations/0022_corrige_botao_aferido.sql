-- 0022_corrige_botao_aferido.sql   [APLICADA em 19/08/2026]
--
-- BUG encontrado nos testes com o app em manutencao.
-- SINTOMA: o botao "Aferido" falhava para OPERADORA (admin nao percebia, porque
--          admin ignora a janela).
-- CAUSA:   ao gravar a data de hoje, o vencimento vai para daqui a 2 anos e o lead
--          SAI da janela de 45 dias -- a linha deixa de ser visivel para quem
--          acabou de edita-la. O PostgreSQL recusa:
--          "new row violates row-level security policy".
--          E a armadilha classica de RLS: nao se atualiza uma linha para a
--          invisibilidade. Ironia: o efeito desejado (o lead sair da fila e voltar
--          em 2 anos) era exatamente o que a regra de seguranca impedia.
-- SOLUCAO: a acao vira RPC SECURITY DEFINER, que valida a permissao pela MESMA
--          regra do UPDATE (admin ou a propria unidade) e entao grava. De quebra,
--          atualizar o lead e registrar no historico viraram operacao ATOMICA --
--          antes eram duas chamadas, e a segunda podia falhar sozinha.
--
-- Usada em dois lugares: botao "Aferido" (p_marcar_aferido = true) e a edicao
-- inline da data na ficha (p_marcar_aferido = false), que caía na mesma armadilha.

create or replace function public.registrar_afericao(
  p_lead uuid, p_data date, p_notas text default null, p_marcar_aferido boolean default true
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_unidade uuid; v_lead jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;

  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  if p_data is not null and p_data > current_date then
    raise exception 'a data da afericao nao pode ser no futuro';
  end if;

  update public.caminhoneiros
     set data_ultima_afericao = p_data,
         status = case when p_marcar_aferido then 'aferido' else status end
   where id = p_lead;

  if p_marcar_aferido then
    insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
    values (p_lead, v_unidade, auth.uid(), 'presencial', 'aferido',
            nullif(btrim(coalesce(p_notas, '')), ''));
  end if;

  select to_jsonb(c) into v_lead from public.caminhoneiros c where c.id = p_lead;
  return v_lead;
end $$;

revoke execute on function public.registrar_afericao(uuid, date, text, boolean) from public, anon;
grant  execute on function public.registrar_afericao(uuid, date, text, boolean) to authenticated;
