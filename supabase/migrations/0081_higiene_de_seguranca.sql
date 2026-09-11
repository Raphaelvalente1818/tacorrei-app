-- 0081 — Higiene apontada pelo advisor de segurança do Supabase (11/09/2026)
--
-- 1. Dez funções SECURITY DEFINER ainda podiam ser chamadas pelo papel anon (a chave
--    pública do front). Todas, menos piso_do_usuario, recusam sem login ("acesso negado"),
--    então não havia vazamento — mas a regra da casa é: função nova nasce sem EXECUTE para
--    public/anon. Estas escaparam por terem sido criadas antes da regra (0016).
-- 2. As tabelas de backup (_backup_swisspark_0072, _backup_swisspark_ligacoes_0072,
--    _backup_dup_0041) estavam no schema public sem RLS — expostas pela API REST. Ficam
--    com RLS ligado e sem política (só o postgres lê), e sem grant para anon/authenticated.

revoke execute on function public.analisar_veiculos_empresa(uuid, jsonb) from public, anon;
revoke execute on function public.atualizar_proprietario(uuid, text, text) from public, anon;
revoke execute on function public.buscar_por_placa(text) from public, anon;
revoke execute on function public.cota_whatsapp_hoje(uuid) from public, anon;
revoke execute on function public.meses_de_vencimento(uuid) from public, anon;
revoke execute on function public.piso_do_usuario() from public, anon;
revoke execute on function public.registrar_autorizacao(uuid, boolean, text) from public, anon;
revoke execute on function public.registrar_aviso_empresa(uuid, date, text) from public, anon;
revoke execute on function public.veiculos_da_empresa(uuid, date) from public, anon;
revoke execute on function public.vincular_veiculos_empresa(uuid, jsonb) from public, anon;

alter table public._backup_swisspark_0072 enable row level security;
alter table public._backup_swisspark_ligacoes_0072 enable row level security;
revoke all on table public._backup_swisspark_0072 from anon, authenticated;
revoke all on table public._backup_swisspark_ligacoes_0072 from anon, authenticated;
revoke all on table public._backup_dup_0041 from anon, authenticated;
