-- Número sem WhatsApp (marcado pela equipe ao descobrir que o número não tem WhatsApp)
-- e permissão para excluir registros de contato (desfazer envios falsos / correções).
-- Já aplicado em 14/08/2026.

alter table public.caminhoneiros
  add column if not exists whatsapp_invalido boolean not null default false;

drop policy if exists "ligacoes: equipe ativa exclui" on public.ligacoes;
create policy "ligacoes: equipe ativa exclui"
  on public.ligacoes
  for delete
  using (is_equipe_ativa());
