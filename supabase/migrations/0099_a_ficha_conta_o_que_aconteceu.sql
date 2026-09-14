-- 0099 — a ficha conta o que aconteceu, e o documento para de vazar.
--
-- Três coisas, uma origem: o Emerson testou "Já aferiu no concorrente" na ficha
-- e a tela não mudou nada de visível. Ao mapear o resto, apareceram dois
-- desfechos mudos e um vazamento que a 0097b não tinha coberto.
--
-- 1) VAZAMENTO. A 0097b tapou `documento` em obter_lead, fila_leads e
--    buscar_por_placa. Faltaram SEIS funções que também devolvem a linha
--    inteira para o navegador depois de escrever: atualizar_proprietario,
--    desmarcar_fora_de_area, registrar_afericao, registrar_afericao_fora,
--    registrar_autorizacao e registrar_contato. Eu tinha olhado só quem LÊ;
--    quem ESCREVE também devolve. Agora todas removem a chave.
--
-- 2) UM SINAL SÓ PARA "AFERIU FORA". Havia dois caminhos com resultados
--    diferentes gravados: o desfecho da ligação (`aferiu_fora`, 0095) e o
--    checkbox do modal do gestor (`registrar_afericao_fora`), que gravava
--    'atualizacao' — o mesmo código usado para troca de proprietário. Para a
--    tela saber que houve aferição no concorrente sem adivinhar por texto de
--    nota, os dois passam a gravar `aferiu_fora`. As linhas antigas são
--    convertidas (elas são reconhecíveis pela nota que a própria função
--    escreveu) e a conversão fica registrada em `correcoes`.
--
-- 3) obter_lead passa a devolver `afericao_fora`: a data, quando foi registrado
--    e se ELE ERA NOSSO e foi embora. Essa última parte decide a cor do selo na
--    ficha — vermelho quando perdemos um cliente, âmbar quando ele sempre foi do
--    concorrente. São fatos diferentes e a operadora reage diferente a cada um.
--
-- 4) `desmarcar_telefone_invalido`: marcar um número como ruim tira o caminhão
--    da fila. Sem um caminho de volta, marcar por engano some com o lead em
--    silêncio. Mesmo padrão do desmarcar_fora_de_area, com motivo e registro.

-- ---------------------------------------------------------------- 1. o sinal
do $$
declare v_def text; v_velho text; v_novo text; n int;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'public' and p.proname = 'registrar_afericao_fora';
  if v_def is null then raise exception 'registrar_afericao_fora nao encontrada'; end if;

  v_velho := '''sistema'', ''atualizacao'',';
  v_novo  := '''sistema'', ''aferiu_fora'',';
  if position(v_velho in v_def) = 0 then
    raise exception 'a gravacao da ligacao nao foi encontrada em registrar_afericao_fora';
  end if;
  execute replace(v_def, v_velho, v_novo);

  -- as linhas antigas do mesmo evento, escritas pela propria funcao
  update public.ligacoes
     set resultado = 'aferiu_fora'
   where resultado = 'atualizacao'
     and canal = 'sistema'
     and notas like 'Aferiu em outro posto em %';
  get diagnostics n = row_count;

  if n > 0 then
    insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo)
    select null, l.unidade_id, 'unifica_resultado_aferiu_fora', 'ligacao', l.id,
           'Migration 0099: o mesmo evento era gravado com dois codigos diferentes.'
      from public.ligacoes l
     where l.resultado = 'aferiu_fora' and l.canal = 'sistema'
       and l.notas like 'Aferiu em outro posto em %';
  end if;

  raise notice 'linhas convertidas: %', n;
end $$;

-- ------------------------------------------------- 2. o documento para de vazar
do $$
declare v_def text; r record;
begin
  for r in
    select unnest(array['atualizar_proprietario','desmarcar_fora_de_area','registrar_afericao',
                        'registrar_afericao_fora','registrar_autorizacao','registrar_contato']) as fn
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if v_def is null then raise exception 'funcao % nao encontrada', r.fn; end if;
    if position('to_jsonb(c)' in v_def) = 0 then
      raise exception '% nao devolve to_jsonb(c) — confira antes de eu reescrever', r.fn;
    end if;
    execute replace(v_def, 'to_jsonb(c)', '(to_jsonb(c) - ''documento'')');
  end loop;
end $$;

-- --------------------------------------------- 3. obter_lead conta a aferição fora
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'obter_lead';
  if v_def is null then raise exception 'obter_lead nao encontrada'; end if;

  v_velho := 'jsonb_build_object(''nosso'', public.posto_do_grupo(c.posto_afericao, c.unidade_id))';
  v_novo  := 'jsonb_build_object(''nosso'', public.posto_do_grupo(c.posto_afericao, c.unidade_id),
    ''afericao_fora'', (
      select jsonb_build_object(
               ''data'', c.data_ultima_afericao,
               ''registrado_em'', l.created_at,
               ''era_nosso'', exists (select 1 from public.historico_posto h
                                      where h.caminhoneiro_id = c.id and h.movimento = ''fuga''))
        from public.ligacoes l
       where l.caminhoneiro_id = c.id and l.resultado = ''aferiu_fora''
       order by l.created_at desc limit 1))';

  if position(v_velho in v_def) = 0 then
    raise exception 'o trecho do nosso nao foi encontrado em obter_lead';
  end if;
  execute replace(v_def, v_velho, v_novo);
end $$;

-- ------------------------------------- 4. caminho de volta do telefone inválido
create or replace function public.desmarcar_telefone_invalido(p_lead uuid, p_motivo text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_unidade uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  update public.caminhoneiros
     set telefone_invalido_em = null, updated_at = now()
   where id = p_lead;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo)
  values (auth.uid(), v_unidade, 'desmarcar_telefone_invalido', 'lead', p_lead,
          nullif(btrim(coalesce(p_motivo,'')),''));

  return (select to_jsonb(c) - 'documento' from public.caminhoneiros c where c.id = p_lead);
end $function$;

revoke all on function public.desmarcar_telefone_invalido(uuid, text) from public, anon;
grant execute on function public.desmarcar_telefone_invalido(uuid, text) to authenticated, service_role;
