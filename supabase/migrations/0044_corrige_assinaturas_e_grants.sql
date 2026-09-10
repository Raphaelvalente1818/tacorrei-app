-- [aplicada no banco em 08/09/2026 18:00 — versão 20260908180002]
-- ── 0044 — fecha duas frestas abertas pela 0043 ─────────────────────────────
--
-- 1) `create or replace` com assinatura nova NÃO substitui: cria uma segunda
--    função. A antiga de 2 argumentos continuava viva com o corpo velho — e é
--    exatamente ela que o app chamava. Sem isto, a trava por empresa não valeria
--    de nada: o botão continuaria caindo na versão sem trava.
--
-- 2) Função nova nasce com EXECUTE para PUBLIC. A migration 0016 revogou isso
--    de propósito. Repor o padrão: só `authenticated` e `service_role`.

drop function if exists public.registrar_envio_whatsapp(uuid, text);

revoke execute on function public.registrar_envio_whatsapp(uuid, text, uuid[]) from public, anon;
revoke execute on function public.normaliza_fone(text) from public, anon;
revoke execute on function public.listar_leads(integer,integer,text,text,uuid,text) from public, anon;
revoke execute on function public.empresas_painel(uuid, date) from public, anon;
revoke execute on function public.obter_lead(uuid) from public, anon;

grant execute on function public.registrar_envio_whatsapp(uuid, text, uuid[]) to authenticated, service_role;
grant execute on function public.normaliza_fone(text) to authenticated, service_role;
