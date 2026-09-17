-- 0103 — A FROTA QUE AUTORIZOU NÃO É CLIENTE DA CASA (17/09)
--
-- O Emerson abriu a ficha da Trans Serra: selo "Cliente da casa", e na mesma
-- linha "Última aferição: REGIONAL CRONOTACÓGRAFOS" — concorrente. A frota está
-- marcada "A conquistar". As duas coisas não podem ser verdade ao mesmo tempo.
--
-- A causa: `obter_lead` devolve, para a frota, um único booleano `ja_e_cliente`,
-- que na verdade responde "pode receber mensagem?" (algum caminhão aferiu conosco
-- OU alguém da frota autorizou na ligação). O front usava isso como "é cliente".
-- A Trans Serra autorizou ontem; não é cliente. E o tom da conversa muda: com
-- cliente a mensagem é lembrete de fornecedor; com quem só autorizou é a
-- primeira abordagem que ele consentiu.
--
-- A régua não muda em nada: `ja_e_cliente` continua igual (é ele que libera o
-- WhatsApp, e o banco confere de novo em registrar_envio_whatsapp). Entram duas
-- chaves separadas para o front poder dizer a verdade:
--   algum_nosso     → um caminhão da frota fez a última aferição num posto do grupo
--   algum_autorizou → alguém da frota disse "pode mandar" numa ligação
-- Cliente da casa = algum_nosso. Autorizou = algum_autorizou e não algum_nosso.

do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.obter_lead(uuid)'::regprocedure);

  if position('''ja_e_cliente'', exists (' in v_def) = 0 then
    raise exception '0103: ancora ja_e_cliente nao encontrada em obter_lead';
  end if;

  v_def := replace(v_def,
    '''ja_e_cliente'', exists (',
    '''algum_nosso'', exists (
        select 1 from public.caminhoneiros x
        where x.empresa_id = e.id and public.posto_do_grupo(x.posto_afericao, x.unidade_id)),
      ''algum_autorizou'', exists (
        select 1 from public.caminhoneiros x
        where x.empresa_id = e.id and coalesce(x.autorizou_whatsapp,false)),
      ''ja_e_cliente'', exists (');

  execute v_def;
end $$;
