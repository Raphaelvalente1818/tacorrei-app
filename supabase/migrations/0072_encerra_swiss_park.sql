-- [aplicada no banco em 10/09/2026 12:13 — versão 20260910121307]
-- 0072 — Encerra a unidade fictícia Swiss Park
-- Era a unidade de teste de agosto: 167 leads copiados de outras unidades,
-- 23 contatos de teste, ninguém lotado nela, zero operação. Backup antes.
do $$
declare v_u uuid;
begin
  select id into v_u from public.unidades where nome ilike '%swiss%';
  if v_u is null then raise notice 'Swiss Park ja nao existe'; return; end if;

  create table if not exists public._backup_swisspark_0072 as
    select c.*, now() as apagado_em from public.caminhoneiros c where c.unidade_id = v_u;
  create table if not exists public._backup_swisspark_ligacoes_0072 as
    select l.* from public.ligacoes l where l.unidade_id = v_u;

  -- Deletar o pai apaga ligacoes/agendamentos/historico/pontos por cascade.
  delete from public.caminhoneiros where unidade_id = v_u;
  -- O que sobrou pendurado direto na unidade (nada, mas por segurança):
  delete from public.ligacoes where unidade_id = v_u;
  delete from public.agendamentos where unidade_id = v_u;
  delete from public.unidade_cidades where unidade_id = v_u;
  update public.equipe set unidade_id = null where unidade_id = v_u;
  delete from public.unidades where id = v_u;
end $$;
