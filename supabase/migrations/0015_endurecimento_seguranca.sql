-- 0015_endurecimento_seguranca.sql
-- Endurecimento apontado pelo scan de seguranca de 19/08/2026.
-- (A revogacao efetiva de `public` esta na 0016 — esta aqui sozinha nao bastou.)

revoke execute on function public.set_unidade_caminhoneiro() from anon, authenticated, public;
revoke execute on function public.set_unidade_filho()        from anon, authenticated, public;

alter function public.gere_unidade(uuid) set search_path = public, pg_temp;
