-- 0099b — devolve a ESU6G39 ao estado da foto (0098) e apaga a foto.
--
-- Diferença exata contra a foto, não reconstrução de memória: apaga o que
-- apareceu depois dela e repõe a linha como estava. O gatilho de troca de posto
-- fica calado (`aferimais.sem_historico`) — repor o cadastro não é movimento de
-- cliente; se ele disparasse, a volta ao estado original geraria um evento falso
-- de conquista.
--
-- No fim, compara a linha inteira com a foto e FALHA se sobrar qualquer
-- diferença. Restauração que não se prova não é restauração.
--
-- `updated_at` fica FORA da comparação: existe um gatilho que o reescreve com
-- now() a cada update, então ele não volta — e não deve voltar mesmo. A linha
-- foi realmente mexida hoje, e fingir o contrário seria apagar o rastro do
-- próprio teste. A primeira versão desta migration falhou exatamente aqui, e a
-- falha provou que o resto voltou idêntico.
do $$
declare
  v_lead uuid := '818aa4f3-39e7-4065-b2a2-9525a055f1ad';
  v_snap record;
  n_lig int; n_ag int; n_pt int; n_hi int;
  v_agora jsonb; v_antes jsonb; v_dif text;
begin
  select * into v_snap from public._snap_teste_0098 where lead_id = v_lead;
  if v_snap is null then raise exception 'a foto nao existe — nao restauro as cegas'; end if;

  perform set_config('aferimais.sem_historico', '1', true);

  delete from public.pontos p
   where p.caminhoneiro_id = v_lead and not (p.id = any(v_snap.pontos));
  get diagnostics n_pt = row_count;

  delete from public.agendamentos a
   where a.caminhoneiro_id = v_lead and not (a.id = any(v_snap.agendamentos));
  get diagnostics n_ag = row_count;

  delete from public.historico_posto h
   where h.caminhoneiro_id = v_lead and not (h.id = any(v_snap.historico));
  get diagnostics n_hi = row_count;

  delete from public.ligacoes l
   where l.caminhoneiro_id = v_lead and not (l.id = any(v_snap.ligacoes));
  get diagnostics n_lig = row_count;

  update public.caminhoneiros c set
    nome                 = v_snap.linha->>'nome',
    telefone             = v_snap.linha->>'telefone',
    status               = v_snap.linha->>'status',
    observacoes          = v_snap.linha->>'observacoes',
    data_ultima_afericao = (v_snap.linha->>'data_ultima_afericao')::date,
    posto_afericao       = v_snap.linha->>'posto_afericao',
    tem_tacografo        = (v_snap.linha->>'tem_tacografo')::boolean,
    whatsapp_invalido    = (v_snap.linha->>'whatsapp_invalido')::boolean,
    autorizou_whatsapp   = (v_snap.linha->>'autorizou_whatsapp')::boolean,
    autorizado_em        = (v_snap.linha->>'autorizado_em')::timestamptz,
    autorizado_por       = (v_snap.linha->>'autorizado_por')::uuid,
    telefone_invalido_em = (v_snap.linha->>'telefone_invalido_em')::timestamptz,
    fora_de_area_em      = (v_snap.linha->>'fora_de_area_em')::timestamptz,
    fora_de_area_por     = (v_snap.linha->>'fora_de_area_por')::uuid,
    data_ultimo_whatsapp = (v_snap.linha->>'data_ultimo_whatsapp')::timestamptz,
    documento            = v_snap.linha->>'documento'
  where c.id = v_lead;

  select to_jsonb(c) into v_agora from public.caminhoneiros c where c.id = v_lead;
  v_antes := v_snap.linha;

  select string_agg(k || ': era ' || coalesce(v_antes->>k,'null')
                      || ', ficou ' || coalesce(v_agora->>k,'null'), ' | ')
    into v_dif
    from jsonb_object_keys(v_antes) k
   where k <> 'updated_at'
     and coalesce(v_antes->>k, '(nulo)') is distinct from coalesce(v_agora->>k, '(nulo)');

  if v_dif is not null then
    raise exception 'a linha nao voltou igual — %', v_dif;
  end if;

  if (select count(*) from public.ligacoes where caminhoneiro_id = v_lead)
     <> cardinality(v_snap.ligacoes) then
    raise exception 'o numero de ligacoes nao bate com a foto';
  end if;

  raise notice 'restaurado: % ligacoes, % agendamentos, % pontos, % historico apagados',
    n_lig, n_ag, n_pt, n_hi;
end $$;

drop table if exists public._snap_teste_0098;
