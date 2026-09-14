-- 0098 — foto de um lead antes de virar cobaia de teste.
--
-- O Emerson vai testar o fluxo novo de "Registrar contato" numa placa real, em
-- produção, e pediu para dar para apagar depois. Reconstruir de memória é como
-- se perde dado: `registrar_contato` mexe em status, pode queimar o telefone,
-- marcar fora de área, liberar WhatsApp, gravar data e posto de aferição — e o
-- gatilho de troca de posto ainda escreve em `historico_posto` sozinho.
--
-- Então, antes do teste, a linha inteira é guardada como jsonb, junto com os
-- ids do que já existia pendurado nela. Desfazer vira diferença exata: apaga o
-- que apareceu depois da foto e devolve a linha ao que era, sem chute.
--
-- Estado no momento da foto: status 'novo', 0 ligações, 0 agendamentos,
-- 0 pontos, 0 linhas de histórico. Lead limpo.
--
-- Esta tabela é temporária por natureza: some quando o teste for desfeito (0099b).
create table if not exists public._snap_teste_0098 (
  lead_id uuid primary key,
  tirada_em timestamptz not null default now(),
  linha jsonb not null,
  ligacoes uuid[] not null,
  agendamentos uuid[] not null,
  pontos uuid[] not null,
  historico uuid[] not null
);

insert into public._snap_teste_0098 (lead_id, linha, ligacoes, agendamentos, pontos, historico)
select c.id,
       to_jsonb(c),
       coalesce((select array_agg(l.id) from public.ligacoes l where l.caminhoneiro_id = c.id), '{}'),
       coalesce((select array_agg(a.id) from public.agendamentos a where a.caminhoneiro_id = c.id), '{}'),
       coalesce((select array_agg(p.id) from public.pontos p where p.caminhoneiro_id = c.id), '{}'),
       coalesce((select array_agg(h.id) from public.historico_posto h where h.caminhoneiro_id = c.id), '{}')
  from public.caminhoneiros c
 where c.id = '818aa4f3-39e7-4065-b2a2-9525a055f1ad'
on conflict (lead_id) do nothing;

do $$
declare n int;
begin
  select count(*) into n from public._snap_teste_0098;
  if n <> 1 then raise exception 'a foto nao foi tirada (linhas: %)', n; end if;
end $$;

revoke all on public._snap_teste_0098 from public, anon, authenticated;
