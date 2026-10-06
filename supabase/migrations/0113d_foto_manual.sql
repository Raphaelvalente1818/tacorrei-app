-- 0113d — A FOTO É DO GESTOR, NÃO DO RELÓGIO (06/10)
--
-- Decisão do Emerson, no mesmo dia: "deixa que nos próximos meses os admins
-- façam a auditoria deles e apertem o botão para gerar a foto do mês". Então o
-- agendamento do dia 5 sai. A função fotografar_mes_anterior() fica (serve para
-- rodar à mão), mas ninguém a chama sozinha. A foto é o botão "Tirar a foto"
-- na aba Meta, pelo admin geral ou pelo gestor da unidade, depois da auditoria.
--
-- E setembro/2026 — o primeiro mês da aba Resultado, cujo dia 5 passou antes do
-- agendamento existir — é fotografado aqui, a pedido dele, com o que está no
-- banco em 06/10 e sem auditoria respondida (ninguém anulado).

do $$
begin
  perform cron.unschedule('aferimais-foto-do-mes');
exception when others then null;
end $$;

do $$
declare u record; v_r jsonb;
begin
  -- só vale rodando em outubro/2026 e enquanto setembro não tiver foto
  if current_date < date '2026-10-01' or current_date >= date '2026-11-01' then return; end if;
  for u in select id, nome from public.unidades where suspensa_em is null order by nome loop
    if public.competencia_fechada(u.id, date '2026-09-01') then continue; end if;
    v_r := public.fechar_mes_interno(u.id, date '2026-09-01', null, false,
             'Foto de setembro tirada em 06/10, a pedido do Emerson: primeiro mês da aba Resultado, sem auditoria respondida.', null);
    raise notice 'setembro fotografado: % → %', u.nome, v_r;
  end loop;
end $$;
