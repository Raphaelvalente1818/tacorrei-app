-- 0100 — cada contato congela o retrato do caminhão naquele instante.
--
-- Para quê: o Emerson quer ordenar a fila por um score (prazo, frota, relação
-- com a casa, telefone…). A ideia é certa — a lista qualquer sistema de gestão
-- produz; quem decide a ORDEM é o produto. Mas hoje não dá para calibrar peso
-- nenhum: são 9 aferições atribuíveis a um contato e 32 ligações atendidas.
--
-- Decisão de 14/09: esperar 15 a 30 dias para elaborar o score, e COMEÇAR A
-- GRAVAR AGORA. A diferença entre as duas coisas é o que decide se 15/10 será
-- útil — porque o estado do caminhão MUDA depois do contato: a data de aferição
-- avança, o posto troca, o status vira outro. Daqui a um mês é impossível
-- reconstruir "este caminhão vencia em 12 dias quando ela ligou".
--
-- `pontos` já congela o estado anterior, mas só de quem CONVERTEU — nove casos.
-- As ligações que não deram em nada são a maioria e são as mais informativas
-- para um score, e não deixavam rastro nenhum do contexto.
--
-- Nada muda na tela. A operadora não vê diferença.
--
-- O campo `v` diz a versão do retrato: quando esta lista mudar, o número sobe e
-- as leituras antigas continuam interpretáveis.

alter table public.ligacoes
  add column if not exists contexto jsonb;

comment on column public.ligacoes.contexto is
  'Retrato do lead/frota no instante do contato, congelado para calibrar o score depois. Nao e lido por tela nenhuma.';

-- ------------------------------------------------------------ o retrato do lead
create or replace function public.contexto_do_lead(p_lead uuid)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'v', 1,
    -- prazo: o eixo mais forte que a gente tem
    'venc',    (c.data_ultima_afericao + interval '2 years')::date,
    'dias',    (c.data_ultima_afericao + interval '2 years')::date - current_date,
    -- relação com a casa
    'nosso',            public.posto_do_grupo(c.posto_afericao, c.unidade_id),
    'posto_conhecido',  c.posto_afericao is not null,
    'autorizou',        c.autorizou_whatsapp,
    'status',           c.status,
    -- por onde dá para falar
    'fone_cls',      c.fone_cls,
    'tel_queimado',  c.telefone_invalido_em is not null,
    'fone_frota',    e.fone_cls,
    -- tamanho do ganho: uma ligação resolve quantos?
    'tem_empresa',      c.empresa_id is not null,
    'empresa_situacao', e.situacao,
    'frota_total', (select count(*) from public.caminhoneiros f
                     where f.empresa_id = c.empresa_id and f.tem_tacografo
                       and f.data_ultima_afericao is not null),
    'frota_vencendo', (select count(*) from public.caminhoneiros f
                        where f.empresa_id = c.empresa_id and f.tem_tacografo
                          and f.data_ultima_afericao is not null
                          and (f.data_ultima_afericao + interval '2 years')::date
                              <= current_date + coalesce(u.agrupamento_dias, 60)),
    'frota_ja_cliente', (select bool_or(public.posto_do_grupo(f.posto_afericao, f.unidade_id))
                           from public.caminhoneiros f where f.empresa_id = c.empresa_id),
    -- atrito: já incomodei essa pessoa?
    'contatos_antes', (select count(*) from public.ligacoes l
                        where l.caminhoneiro_id = c.id
                          and l.canal in ('ligacao_ativa','ligacao_passiva')),
    'msgs_antes',     (select count(*) from public.ligacoes l
                        where l.caminhoneiro_id = c.id and l.resultado = 'whatsapp_enviado'),
    'dias_ultimo_contato', (select (current_date - max(l.created_at)::date)
                              from public.ligacoes l where l.caminhoneiro_id = c.id),
    -- o que a gente ainda não sabe usar, mas vai querer ter medido
    'cidade', c.cidade,
    'modelo', c.modelo_veiculo,
    'tem_documento', c.documento is not null
  )
  from public.caminhoneiros c
  left join public.empresas e on e.id = c.empresa_id
  left join public.unidades u on u.id = c.unidade_id
  where c.id = p_lead;
$$;

-- ----------------------------------------------------------- o retrato da frota
create or replace function public.contexto_da_empresa(p_empresa uuid)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'v', 1,
    'situacao', e.situacao,
    'veiculos', (select count(*) from public.caminhoneiros f
                  where f.empresa_id = e.id and f.tem_tacografo
                    and f.data_ultima_afericao is not null),
    'vencendo_janela', (select count(*) from public.caminhoneiros f
                         where f.empresa_id = e.id and f.tem_tacografo
                           and f.data_ultima_afericao is not null
                           and (f.data_ultima_afericao + interval '2 years')::date
                               <= current_date + coalesce(u.janela_dias, 45)),
    'vencidos', (select count(*) from public.caminhoneiros f
                  where f.empresa_id = e.id and f.tem_tacografo
                    and f.data_ultima_afericao is not null
                    and (f.data_ultima_afericao + interval '2 years')::date < current_date),
    'ja_e_cliente', (select bool_or(public.posto_do_grupo(f.posto_afericao, f.unidade_id))
                       from public.caminhoneiros f where f.empresa_id = e.id),
    'fone_cls', e.fone_cls,
    'contatos_antes', (select count(*) from public.ligacoes l where l.empresa_id = e.id),
    'dias_ultimo_contato', (select (current_date - max(l.created_at)::date)
                              from public.ligacoes l where l.empresa_id = e.id)
  )
  from public.empresas e
  left join public.unidades u on u.id = e.unidade_id
  where e.id = p_empresa;
$$;

-- Fora da API: ninguém no navegador chama isso.
revoke all on function public.contexto_do_lead(uuid) from public, anon, authenticated;
revoke all on function public.contexto_da_empresa(uuid) from public, anon, authenticated;
grant execute on function public.contexto_do_lead(uuid) to service_role;
grant execute on function public.contexto_da_empresa(uuid) to service_role;

-- --------------------------------------- quem grava contato passa a congelar
do $$
declare v_def text; r record;
begin
  for r in
    select * from (values
      ('registrar_contato',
       'insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), p_canal, p_resultado, v_notas);',
       'insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas, contexto)
  values (p_lead, v_unidade, auth.uid(), p_canal, p_resultado, v_notas,
          public.contexto_do_lead(p_lead));'),

      ('registrar_envio_whatsapp',
       'insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), ''whatsapp'', ''whatsapp_enviado'', p_mensagem);',
       'insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas, contexto)
  values (p_lead, v_unidade, auth.uid(), ''whatsapp'', ''whatsapp_enviado'', p_mensagem,
          public.contexto_do_lead(p_lead));'),

      ('registrar_envio_whatsapp',
       'insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  select x, v_unidade, auth.uid(), ''sistema'', ''whatsapp_enviado'',
         ''Coberto pela mensagem enviada para a frota.''',
       'insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas, contexto)
  select x, v_unidade, auth.uid(), ''sistema'', ''whatsapp_enviado'',
         ''Coberto pela mensagem enviada para a frota.'', public.contexto_do_lead(x)'),

      ('registrar_ligacao_empresa',
       'insert into public.ligacoes
    (empresa_id, caminhoneiro_id, operador_id, resultado, canal, notas, unidade_id)
  values
    (p_empresa, null, auth.uid(), p_resultado, p_canal,
     nullif(btrim(coalesce(p_notas,'''')), ''''), v_unidade)',
       'insert into public.ligacoes
    (empresa_id, caminhoneiro_id, operador_id, resultado, canal, notas, unidade_id, contexto)
  values
    (p_empresa, null, auth.uid(), p_resultado, p_canal,
     nullif(btrim(coalesce(p_notas,'''')), ''''), v_unidade,
     public.contexto_da_empresa(p_empresa))')
    ) as t(fn, alvo, troca)
  loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if v_def is null then raise exception 'funcao % nao encontrada', r.fn; end if;
    if position(r.alvo in v_def) = 0 then
      raise exception 'a gravacao da ligacao nao foi encontrada em % — nao reescrevo as cegas', r.fn;
    end if;
    execute replace(v_def, r.alvo, r.troca);
  end loop;
end $$;
