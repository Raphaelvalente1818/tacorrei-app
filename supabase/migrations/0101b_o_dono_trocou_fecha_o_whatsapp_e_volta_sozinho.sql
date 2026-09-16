-- 0101b — a trava do WhatsApp, a volta automática e a conferência.
--
-- 1) TRAVA. Quem já disse "não é mais meu" não pode receber mensagem. Sai da
--    fila mas continua achável pela placa — e é justamente por essa porta que
--    alguém poderia mandar um WhatsApp sem querer para quem já pediu para sair.
--    Vira a sétima trava, no mesmo lugar das outras seis.
--
-- 2) VOLTA SOZINHO. Era isto que o Emerson descreveu: "aguardando a mudança de
--    proprietário no Inmetro". Quando a importação trouxer um DOCUMENTO
--    diferente para aquela placa, o proprietário mudou de verdade — o cadastro
--    é atualizado e o caminhão volta para a fila sem ninguém precisar lembrar.
--    Documento é o sinal certo: nome muda de grafia, telefone muda de dono,
--    CPF/CNPJ não. E como `importar_base` só preenche campo vazio, foi preciso
--    abrir UMA exceção explícita: quando o documento muda, nome e telefone são
--    sobrescritos — senão o lead voltaria para a fila com o contato do antigo
--    dono, que é exatamente a pessoa que pediu para não ser mais incomodada.
--    Fica registrado em `correcoes`. Só começa a valer depois da primeira
--    importação com a coluna CPF/CNPJ (0097): hoje `documento` é nulo.
--
-- 3) CONFERÊNCIA. A fila tem agora QUATRO baldes disjuntos, e a soma continua
--    tendo que bater com a régua. Sem esta checagem, um lead poderia cair em
--    dois baldes (ou em nenhum) e ninguém perceberia.

-- ------------------------------------------------------ 1. a sétima trava
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_envio_whatsapp';
  if v_def is null then raise exception 'registrar_envio_whatsapp nao encontrada'; end if;

  v_velho := '  if v_unidade is null then raise exception ''lead nao encontrado''; end if;';
  v_novo  := '  if v_unidade is null then raise exception ''lead nao encontrado''; end if;
  -- 0101b — quem disse que nao e mais o dono nao recebe mensagem, nem pela busca
  if exists (select 1 from public.caminhoneiros c
              where c.id = p_lead and c.dono_trocou_em is not null) then
    raise exception ''esta pessoa informou que nao e mais dona deste caminhao — aguardando a troca de proprietario no cadastro'';
  end if;';
  if position(v_velho in v_def) = 0 then raise exception 'o ponto da trava nao foi encontrado'; end if;
  execute replace(v_def, v_velho, v_novo);
end $$;

-- --------------------------------------------- 2. a volta pela importação
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'importar_base';
  if v_def is null then raise exception 'importar_base nao encontrada'; end if;

  v_velho := '  update public.caminhoneiros c
     set nome = coalesce(c.nome, i.nome),';
  v_novo  := '  -- 0101b — documento diferente = proprietario mudou de verdade. O caminhao
  -- marcado como "nao e mais o dono" volta para a fila, e o contato do dono
  -- ANTIGO e substituido: ele foi quem pediu para nao ser mais incomodado.
  update public.caminhoneiros c
     set dono_trocou_em = null, dono_trocou_por = null,
         nome = coalesce(i.nome, c.nome),
         telefone = coalesce(i.telefone, c.telefone),
         documento = i.cpf_cnpj,
         telefone_invalido_em = null,
         updated_at = now()
    from _imp i
   where i.existente_id = c.id
     and c.dono_trocou_em is not null
     and c.documento is not null
     and (i.cpf_cnpj ~ ''^[0-9]{11}$'' or i.cpf_cnpj ~ ''^[0-9]{14}$'')
     and i.cpf_cnpj <> c.documento;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo)
  select auth.uid(), c.unidade_id, ''dono_trocou_confirmado'', ''lead'', c.id,
         ''Importacao trouxe outro documento para a placa: proprietario mudou e o caminhao voltou para a fila.''
    from public.caminhoneiros c
    join _imp i on i.existente_id = c.id
   where c.dono_trocou_em is null and c.updated_at >= now() - interval ''1 second''
     and (i.cpf_cnpj ~ ''^[0-9]{11}$'' or i.cpf_cnpj ~ ''^[0-9]{14}$'')
     and i.cpf_cnpj = c.documento;

  update public.caminhoneiros c
     set nome = coalesce(c.nome, i.nome),';
  if position(v_velho in v_def) = 0 then raise exception 'o update da importacao nao foi encontrado'; end if;
  execute replace(v_def, v_velho, v_novo);
end $$;

-- ------------------------------------------------------- 3. a conferência
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'conferencia_contagens';
  if v_def is null then raise exception 'conferencia_contagens nao encontrada'; end if;

  v_velho := '    checagem := ''fila + sem telefone + fora de area = regua na fila'';
    a := (public.contar_leads(u.id)->>''total'')::bigint
       + (public.contar_leads(u.id)->>''sem_telefone'')::bigint
       + (public.contar_leads(u.id)->>''fora_de_area'')::bigint;';
  v_novo  := '    checagem := ''contar_leads.dono_trocou = lista Trocou de dono'';
    a := (public.contar_leads(u.id)->>''dono_trocou'')::bigint;
    b := (public.fila_leads(1, 1, ''dono_trocou'', null, u.id, null)->>''total'')::bigint;
    ok := a = b; return next;

    checagem := ''fila + sem telefone + fora de area + dono trocou = regua na fila'';
    a := (public.contar_leads(u.id)->>''total'')::bigint
       + (public.contar_leads(u.id)->>''sem_telefone'')::bigint
       + (public.contar_leads(u.id)->>''fora_de_area'')::bigint
       + (public.contar_leads(u.id)->>''dono_trocou'')::bigint;';
  if position(v_velho in v_def) = 0 then raise exception 'a checagem da soma nao foi encontrada'; end if;
  execute replace(v_def, v_velho, v_novo);
end $$;

revoke all on function public.conferencia_contagens() from public, anon;
grant execute on function public.conferencia_contagens() to authenticated, service_role;
