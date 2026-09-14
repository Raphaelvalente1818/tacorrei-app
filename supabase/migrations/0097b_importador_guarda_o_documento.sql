-- 0097b — o importador passa a guardar o documento, e a ficha nunca o devolve.
--
-- Mudança de caminho, e vale registrar por quê. A primeira ideia era eu carregar
-- os 4.456 pares placa+documento que estão nas planilhas já enviadas, como foi
-- feito na 0090 e na 0093. Isso obrigaria os CPFs a passarem pela conversa, e
-- resolveria só uma vez: a próxima extração voltaria a descartar o dado.
--
-- Mas o caminho já existe e é melhor: a tela Administração → Importar base já
-- reconhece as colunas CPF / CNPJ / CPFCNPJ / DOCUMENTO (ImportarBase.tsx) e
-- `preparar_base` já devolve `cpf_cnpj` desde a 0087. O que faltava era uma
-- linha: `importar_base` usava esse valor apenas como nome de reserva e jogava
-- fora. Agora ele grava.
--
-- Efeito: o Emerson cola a base na tela e os documentos entram sozinhos —
-- nenhum dado de cliente passa por aqui, a carga fica registrada em
-- `importacoes` como qualquer outra, e toda importação futura já nasce certa.
--
-- Regras da gravação:
--   - só preenche quando está vazio (`coalesce(c.documento, …)`); documento que
--     já existe na base não é sobrescrito por planilha;
--   - só aceita 11 ou 14 dígitos. Sem essa guarda, um CPF truncado na extração
--     derrubaria a importação inteira na constraint — uma linha ruim não pode
--     custar a carga;
--   - a linha entra no UPDATE quando o único que falta é o documento.

do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'importar_base';
  if v_def is null then raise exception 'importar_base nao encontrada'; end if;

  -- 1. o UPDATE grava o documento
  v_velho := '         renavam = coalesce(c.renavam, i.renavam),';
  v_novo  := '         renavam = coalesce(c.renavam, i.renavam),
         documento = coalesce(c.documento,
                              case when i.cpf_cnpj ~ ''^[0-9]{11}$'' or i.cpf_cnpj ~ ''^[0-9]{14}$''
                                   then i.cpf_cnpj end),';
  if position(v_velho in v_def) = 0 then raise exception 'lista do update nao encontrada'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  -- 2. faltar só o documento já é motivo para atualizar a linha
  v_velho := '     and (c.nome is null or coalesce(c.telefone,'''') = '''' or c.cidade is null or c.uf is null';
  v_novo  := '     and ((c.documento is null and i.cpf_cnpj is not null)
          or c.nome is null or coalesce(c.telefone,'''') = '''' or c.cidade is null or c.uf is null';
  if position(v_velho in v_def) = 0 then raise exception 'where do update nao encontrado'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  -- 3. o INSERT também
  v_velho := '     data_ultima_afericao, posto_afericao, tem_tacografo, unidade_id, origem, status, observacoes)';
  v_novo  := '     data_ultima_afericao, posto_afericao, tem_tacografo, unidade_id, origem, status, observacoes, documento)';
  if position(v_velho in v_def) = 0 then raise exception 'colunas do insert nao encontradas'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '         case when i.data is null then ''Sem data de aferição na extração: fora da fila até ser verificado.'' end
    from _imp i';
  v_novo  := '         case when i.data is null then ''Sem data de aferição na extração: fora da fila até ser verificado.'' end,
         case when i.cpf_cnpj ~ ''^[0-9]{11}$'' or i.cpf_cnpj ~ ''^[0-9]{14}$'' then i.cpf_cnpj end
    from _imp i';
  if position(v_velho in v_def) = 0 then raise exception 'select do insert nao encontrado'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;

-- O documento não pode escapar pela ficha. A leitura direta da tabela já está
-- fechada (o papel logado só lê a coluna `id` de `caminhoneiros`), mas três
-- funções devolvem a linha inteira em jsonb e levariam a coluna nova junto.
do $$
declare v_def text; v_velho text; v_novo text; r record;
begin
  for r in
    select * from (values
      ('fila_leads',
       'jsonb_agg(to_jsonb(p) order by p.fone desc',
       'jsonb_agg((to_jsonb(p) - ''documento'') order by p.fone desc'),
      ('obter_lead',
       'select to_jsonb(c) || jsonb_build_object(''nosso''',
       'select (to_jsonb(c) - ''documento'') || jsonb_build_object(''nosso'''),
      ('buscar_por_placa',
       'select to_jsonb(c) || jsonb_build_object(',
       'select (to_jsonb(c) - ''documento'') || jsonb_build_object(')
    ) as t(fn, alvo, troca)
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if v_def is null then raise exception 'funcao % nao encontrada', r.fn; end if;
    if position(r.alvo in v_def) = 0 then
      raise exception 'o trecho que devolve a ficha nao foi encontrado em %', r.fn;
    end if;
    execute replace(v_def, r.alvo, r.troca);
  end loop;
end $$;

-- A tabela de apoio da 0097 não vai ser usada: a carga passa pela tela.
drop table if exists public._stage_doc_0097;
