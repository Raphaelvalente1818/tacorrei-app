-- 0095b — a conferência passa a guardar o terceiro balde.
-- Reescreve conferencia_contagens a partir da definição no banco (mesmo método da 0086):
-- substituição exata, e falha se o trecho não existir — nunca "quase aplicou".
-- Depois desta, a conferência tem 15 checagens por unidade (30 no total, era 28).
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'conferencia_contagens';
  if v_def is null then raise exception 'conferencia_contagens nao encontrada'; end if;

  v_velho := '    checagem := ''fila + sem telefone = regua na fila'';
    a := (public.contar_leads(u.id)->>''total'')::bigint
       + (public.contar_leads(u.id)->>''sem_telefone'')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t where t.na_fila;
    ok := a = b; return next;';

  v_novo := '    checagem := ''contar_leads.fora_de_area = lista Fora de area'';
    a := (public.contar_leads(u.id)->>''fora_de_area'')::bigint;
    b := (public.fila_leads(1, 1, ''fora_de_area'', null, u.id, null)->>''total'')::bigint;
    ok := a = b; return next;

    checagem := ''fila + sem telefone + fora de area = regua na fila'';
    a := (public.contar_leads(u.id)->>''total'')::bigint
       + (public.contar_leads(u.id)->>''sem_telefone'')::bigint
       + (public.contar_leads(u.id)->>''fora_de_area'')::bigint;
    select count(*) into b from public.base_trabalhavel(u.id) t where t.na_fila;
    ok := a = b; return next;';

  if position(v_velho in v_def) = 0 then
    raise exception 'o trecho da checagem antiga nao foi encontrado — nao reescrevo as cegas';
  end if;

  execute replace(v_def, v_velho, v_novo);
end $$;

revoke all on function public.conferencia_contagens() from public, anon;
grant execute on function public.conferencia_contagens() to authenticated, service_role;
