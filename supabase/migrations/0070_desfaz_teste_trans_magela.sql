-- [aplicada no banco em 09/09/2026 23:54 — versão 20260909235441]
-- 0070 — Desfaz o contato de teste na Trans Magela (09/09, 23:38)
-- Era o teste da fila de empresas. As 19 placas que desceram para 'contatado'
-- nunca tiveram outro contato: voltam para 'novo', que era o estado delas.
update public.caminhoneiros c
   set status = 'novo', updated_at = now()
  from public.empresas e
 where e.id = c.empresa_id and e.nome ilike 'TRANS MAGELA%'
   and c.status = 'contatado'
   and not exists (select 1 from public.ligacoes x where x.caminhoneiro_id = c.id);

delete from public.ligacoes where id = '8a38de04-8a99-4e03-a3cd-2dcf6954bcd1';
