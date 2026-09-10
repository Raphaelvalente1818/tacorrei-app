-- [aplicada no banco em 09/09/2026 14:47 — versão 20260909144715]
-- ── 0049 — marcar aferido direto na lista da frota ──────────────────────────
--
-- A rotina mensal da menina é: abre a frota, vê quem venceu, e à medida que os
-- ônibus passam ela vai baixando. Sem isso a data só se corrige na planilha e
-- o app envelhece sozinho.
--
-- ⚠️ NÃO mexe em `status`. Veículo de frota não está no funil de prospecção, e
-- marcar 'aferido' aqui inflaria os "aferidos" do Dashboard sem um "contatado"
-- do outro lado — a taxa de conversão deixaria de medir o que mede. A aferição
-- fica registrada em `ligacoes`, que é onde ela pertence.
create or replace function public.registrar_afericao_frota(
  p_lead uuid, p_data date default null, p_notas text default null)
returns jsonb language plpgsql security definer
set search_path to 'public','pg_temp' as $function$
declare v_unidade uuid; v_emp uuid; v_data date; v_anterior date; v_placa text;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id, c.empresa_id, c.data_ultima_afericao, c.placa_veiculo
    into v_unidade, v_emp, v_anterior, v_placa
  from public.caminhoneiros c where c.id = p_lead;

  if v_unidade is null then raise exception 'veiculo nao encontrado'; end if;
  if v_emp is null then
    raise exception 'este veiculo nao e de frota: use o botao Aferido na ficha do lead';
  end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_data := coalesce(p_data, (now() at time zone 'America/Sao_Paulo')::date);

  -- Data futura quase sempre é dedo errado no ano. Já aconteceu na base (uma
  -- aferição registrada em 31/08 quando ainda era agosto).
  if v_data > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'data no futuro (%): confira o ano', to_char(v_data,'DD/MM/YYYY');
  end if;
  if v_anterior is not null and v_data < v_anterior then
    raise exception 'a aferição anterior é de % — uma nova não pode ser anterior a ela',
      to_char(v_anterior,'DD/MM/YYYY');
  end if;

  update public.caminhoneiros
     set data_ultima_afericao = v_data,
         posto_afericao = 'TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME.',
         updated_at = now()
   where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'presencial', 'aferido',
          coalesce(p_notas, 'Aferição registrada na lista da frota.'));

  return jsonb_build_object(
    'data', v_data,
    'venc', (v_data + interval '2 years')::date,
    'anterior', v_anterior,
    'placa', v_placa);
end $function$;

revoke execute on function public.registrar_afericao_frota(uuid, date, text) from public, anon;
grant execute on function public.registrar_afericao_frota(uuid, date, text) to authenticated, service_role;
