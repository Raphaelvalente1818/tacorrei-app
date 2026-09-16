-- 0101 — "esse caminhão não é mais meu": o cadastro está velho, não o lead.
--
-- Pedido do Emerson em 15/09, depois de ver o dropdown em produção: falta o
-- desfecho para quando a pessoa atende e diz que vendeu o caminhão, mas o
-- Inmetro ainda mostra ela como dona. "As operadoras ficariam com essa
-- classificação aguardando a mudança de proprietário no Inmetro para poder
-- contactar no futuro. O caminhão precisa sair do radar de busca, mas não pode
-- sumir — ele deveria ser buscado pela placa."
--
-- O que este caso NÃO é:
--   • não é "fora de área" — lá o caminhão é real e afere em outra praça, e não
--     é nosso alvo. Aqui o caminhão continua sendo alvo; quem está errado é o
--     contato.
--   • não é "número inválido" — o telefone funciona, quem atendeu é que não é
--     mais o dono.
--   • não é troca de proprietário conhecida — se ele disser quem comprou, a
--     operadora corrige no lápis ao lado do nome (`atualizar_proprietario`) e o
--     lead continua na fila, com o dono certo. Este desfecho é para o caso mais
--     comum: "vendi, não sei para quem".
--
-- Ligar de novo para esse telefone é o caminho da denúncia: a pessoa já disse
-- que não tem nada com isso. Então o lead sai da fila e do envio de WhatsApp,
-- mas continua alcançável pela busca por placa — que nunca respeitou a fila,
-- justamente para o caminhão que chega no balcão.
--
-- E o "aguardando a mudança no Inmetro" vira código, não espera: quando a
-- próxima importação trouxer um DOCUMENTO diferente para aquela placa, o
-- sistema entende que o proprietário mudou de verdade, atualiza o cadastro e
-- devolve o caminhão para a fila sozinho (0101b). Isso só começa a funcionar
-- depois da primeira importação com a coluna CPF/CNPJ (0097) — hoje `documento`
-- é nulo para todo mundo.

alter table public.caminhoneiros
  add column if not exists dono_trocou_em timestamptz,
  add column if not exists dono_trocou_por uuid references public.equipe(user_id) on delete set null;

comment on column public.caminhoneiros.dono_trocou_em is
  'Quando alguem informou que nao e mais o dono do caminhao. Sai da fila e do WhatsApp; volta sozinho quando a importacao trouxer outro documento para a placa.';

create index if not exists caminhoneiros_dono_trocou_idx
  on public.caminhoneiros (unidade_id) where (dono_trocou_em is not null);

-- o desfecho novo
alter table public.ligacoes drop constraint if exists ligacoes_resultado_check;
alter table public.ligacoes add constraint ligacoes_resultado_check
  check (resultado = any (array[
    'atendeu','nao_atendeu','numero_invalido','recusou','agendou','reagendar',
    'whatsapp_enviado','aferido','autorizou_whatsapp','atualizacao',
    'aferiu_fora','fora_de_area','dono_trocou' ]));

-- ------------------------------------------------------- registrar_contato
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_contato';
  if v_def is null then raise exception 'registrar_contato nao encontrada'; end if;

  v_velho := '    when ''fora_de_area''       then ''novo''   -- sai da fila pela marca, não pelo status';
  v_novo  := '    when ''fora_de_area''       then ''novo''   -- sai da fila pela marca, não pelo status
    when ''dono_trocou''        then ''novo''   -- idem: o cadastro é que está velho';
  if position(v_velho in v_def) = 0 then raise exception 'a tabela de status nao foi encontrada'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '  elsif p_resultado = ''fora_de_area'' then
    update public.caminhoneiros
       set fora_de_area_em = now(), fora_de_area_por = auth.uid()
     where id = p_lead;
    v_notas := coalesce(v_notas, ''Afere em outra praça — fora do nosso alvo.'');
  end if;';
  v_novo := '  elsif p_resultado = ''fora_de_area'' then
    update public.caminhoneiros
       set fora_de_area_em = now(), fora_de_area_por = auth.uid()
     where id = p_lead;
    v_notas := coalesce(v_notas, ''Afere em outra praça — fora do nosso alvo.'');

  elsif p_resultado = ''dono_trocou'' then
    update public.caminhoneiros
       set dono_trocou_em = now(), dono_trocou_por = auth.uid()
     where id = p_lead;
    v_notas := coalesce(v_notas,
      ''Informou que nao e mais o dono. Aguardando a troca de proprietario no cadastro.'');
  end if;';
  if position(v_velho in v_def) = 0 then raise exception 'o bloco de efeitos nao foi encontrado'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;

-- ------------------------------------------------------------- fila_leads
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fila_leads';
  if v_def is null then raise exception 'fila_leads nao encontrada'; end if;

  v_velho := '                 when p_filtro in (''sem_telefone'',''fora_de_area'') then c.tem_tacografo = true';
  v_novo  := '                 when p_filtro in (''sem_telefone'',''fora_de_area'',''dono_trocou'') then c.tem_tacografo = true';
  if position(v_velho in v_def) = 0 then raise exception 'a lista de filtros nao foi encontrada'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  -- os baldes continuam disjuntos: "dono trocou" tem precedência sobre os outros
  v_velho := '            or (case
                  when p_filtro = ''fora_de_area'' then c.fora_de_area_em is not null
                  when p_filtro = ''sem_telefone'' then c.fora_de_area_em is null
                       and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                    coalesce(e.fone_cls,0)) = 0
                  else c.fora_de_area_em is null
                       and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                    coalesce(e.fone_cls,0)) > 0
                end))';
  v_novo := '            or (case
                  when p_filtro = ''dono_trocou'' then c.dono_trocou_em is not null
                  when p_filtro = ''fora_de_area'' then c.dono_trocou_em is null
                       and c.fora_de_area_em is not null
                  when p_filtro = ''sem_telefone'' then c.dono_trocou_em is null
                       and c.fora_de_area_em is null
                       and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                    coalesce(e.fone_cls,0)) = 0
                  else c.dono_trocou_em is null and c.fora_de_area_em is null
                       and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                                    coalesce(e.fone_cls,0)) > 0
                end))';
  if position(v_velho in v_def) = 0 then raise exception 'os baldes da fila nao foram encontrados'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;

-- ----------------------------------------------------------- contar_leads
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'contar_leads';
  if v_def is null then raise exception 'contar_leads nao encontrada'; end if;

  v_velho := '           c.fora_de_area_em is not null as fora,';
  v_novo  := '           c.dono_trocou_em is not null as trocou,
           c.fora_de_area_em is not null as fora,';
  if position(v_velho in v_def) = 0 then raise exception 'a coluna fora nao foi encontrada'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '           c.fora_de_area_em is null
             and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                          coalesce(e.fone_cls, 0)) > 0 as trabalhavel';
  v_novo  := '           c.dono_trocou_em is null and c.fora_de_area_em is null
             and greatest(case when c.telefone_invalido_em is null then c.fone_cls else 0 end,
                          coalesce(e.fone_cls, 0)) > 0 as trabalhavel';
  if position(v_velho in v_def) = 0 then raise exception 'a coluna trabalhavel nao foi encontrada'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  v_velho := '    ''sem_telefone'',     count(*) filter (where not fora and not tem_fone),
    ''fora_de_area'',     count(*) filter (where fora)';
  v_novo  := '    ''sem_telefone'',     count(*) filter (where not trocou and not fora and not tem_fone),
    ''fora_de_area'',     count(*) filter (where not trocou and fora),
    ''dono_trocou'',      count(*) filter (where trocou)';
  if position(v_velho in v_def) = 0 then raise exception 'os contadores dos baldes nao foram encontrados'; end if;
  v_def := replace(v_def, v_velho, v_novo);

  execute v_def;
end $$;

-- --------------------------------------------------- meses_de_vencimento
do $$
declare v_def text; v_velho text; v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'meses_de_vencimento';
  if v_def is null then raise exception 'meses_de_vencimento nao encontrada'; end if;

  v_velho := '      and c.fora_de_area_em is null';
  v_novo  := '      and c.fora_de_area_em is null
      and c.dono_trocou_em is null';
  if position(v_velho in v_def) = 0 then raise exception 'o filtro de fora de area nao foi encontrado'; end if;
  execute replace(v_def, v_velho, v_novo);
end $$;

-- ------------------------------------------------ o caminho de volta, à mão
create or replace function public.desmarcar_dono_trocou(p_lead uuid, p_motivo text default null)
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
     set dono_trocou_em = null, dono_trocou_por = null, updated_at = now()
   where id = p_lead;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo)
  values (auth.uid(), v_unidade, 'desmarcar_dono_trocou', 'lead', p_lead,
          nullif(btrim(coalesce(p_motivo,'')),''));

  return (select to_jsonb(c) - 'documento' from public.caminhoneiros c where c.id = p_lead);
end $function$;

revoke all on function public.desmarcar_dono_trocou(uuid, text) from public, anon;
grant execute on function public.desmarcar_dono_trocou(uuid, text) to authenticated, service_role;
