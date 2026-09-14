-- 0100b — o retrato tem que ser de ANTES do efeito.
--
-- Defeito pego no ensaio da 0100, antes de qualquer dado real ser gravado: em
-- `registrar_contato`, a linha de `ligacoes` é inserida no FIM, depois de o lead
-- já ter sido alterado. O retrato saía com o efeito dentro dele.
--
-- No teste apareceu como `status: sem_resposta` — o status DEPOIS do "não
-- atendeu", não o de antes. E isso estragaria justamente os desfechos mais
-- importantes: "já aferiu no concorrente" grava data e posto novos antes do
-- insert, então o `venc` congelado seria o de 2028, e não o vencimento que fez
-- a operadora ligar. "Número inválido" queimaria o telefone antes de o retrato
-- registrar que ele estava bom. O campo que mais interessa para o score seria o
-- primeiro a mentir.
--
-- Agora o retrato é tirado logo depois da checagem de acesso, guardado numa
-- variável, e só então os efeitos acontecem.
--
-- `registrar_ligacao_empresa` e `registrar_envio_whatsapp` já inserem a linha
-- antes de mexer nos caminhões — foram conferidos e estão certos.
--
-- Conferido depois de aplicar, com "já aferiu no concorrente" (o pior caso):
--   vencimento real antes da ligação .. 2026-09-27
--   vencimento no retrato ............. 2026-09-27  ✓
--   status no retrato ................. novo        ✓
--   vencimento do lead depois ......... 2028-08-15
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_contato';
  if v_def is null then raise exception 'registrar_contato nao encontrada'; end if;

  -- 1. variável para o retrato
  v_velho := 'declare v_unidade uuid; v_status text; v_notas text;';
  v_novo  := 'declare v_unidade uuid; v_status text; v_notas text; v_ctx jsonb;';
  if position(v_velho in v_def) = 0 then raise exception 'declare nao encontrado'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  -- 2. tira o retrato antes de tudo que muda o lead
  v_velho := '  v_notas := nullif(btrim(coalesce(p_notas,'''')), '''');';
  v_novo  := '  -- 0100b — o retrato é de ANTES do efeito: daqui para baixo o lead muda.
  v_ctx := public.contexto_do_lead(p_lead);

  v_notas := nullif(btrim(coalesce(p_notas,'''')), '''');';
  if position(v_velho in v_def) = 0 then raise exception 'o ponto de tirar o retrato nao foi encontrado'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  -- 3. o insert usa o retrato guardado, não um novo
  v_velho := 'public.contexto_do_lead(p_lead));';
  v_novo  := 'v_ctx);';
  if position(v_velho in v_def) = 0 then raise exception 'a chamada no insert nao foi encontrada'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;
