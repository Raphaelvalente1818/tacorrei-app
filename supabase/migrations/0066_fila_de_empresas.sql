-- 0066 — A aba Empresas vira fila de trabalho
--
-- Até aqui o painel respondia só a pergunta do contrato ("quantos vencem no
-- mês e já avisei?"). Para as ~600 empresas a conquistar ele não dizia nada:
-- nem quantos caminhões já são nossos, nem quantos estão para vencer no
-- concorrente, nem quando falamos com ela pela última vez.
--
-- classe:
--   contrato  — já é cliente, recebe aviso mensal
--   mista     — tem pelo menos um caminhão conosco: o pé na porta
--   virgem    — tem posto conhecido, nenhum nosso
--   sem_dados — nenhum veículo com posto (provavelmente sem tacógrafo)
--
-- ultima_abordagem passa a contar LIGAÇÃO também, e não só WhatsApp. Antes,
-- uma empresa para quem a operadora tinha ligado três vezes continuava
-- aparecendo como nunca abordada — e ela ligava de novo.

create or replace function public.empresas_painel(
  p_unidade uuid default null,
  p_competencia date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v jsonb; v_comp date;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_comp := coalesce(p_competencia, date_trunc('month', current_date + interval '1 month')::date);

  select coalesce(jsonb_agg(to_jsonb(y) order by y.vencendo desc, y.nome), '[]'::jsonb) into v
  from (
    select g.*,
           case when g.situacao = 'contrato' then 'contrato'
                when g.nossos > 0            then 'mista'
                when g.a_conquistar > 0      then 'virgem'
                else 'sem_dados' end as classe
    from (
      select e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao,
             v_comp as competencia,

             count(c.id) filter (where c.tem_tacografo) as veiculos,

             count(c.id) filter (
               where c.tem_tacografo and public.posto_do_grupo(c.posto_afericao)
             ) as nossos,

             count(c.id) filter (
               where c.tem_tacografo and c.posto_afericao is not null
                 and not public.posto_do_grupo(c.posto_afericao)
             ) as a_conquistar,

             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and date_trunc('month', (c.data_ultima_afericao + interval '2 years'))::date = v_comp
             ) as vencendo,

             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and (c.data_ultima_afericao + interval '2 years')::date < current_date
             ) as vencidos,

             -- o gatilho da ligação: caminhão do concorrente que vence agora
             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and c.posto_afericao is not null
                 and not public.posto_do_grupo(c.posto_afericao)
                 and (c.data_ultima_afericao + interval '2 years')::date
                     between current_date and current_date + 90
             ) as janela,

             -- a defesa: caminhão NOSSO vencendo (ou vencido há pouco)
             count(c.id) filter (
               where c.tem_tacografo and c.data_ultima_afericao is not null
                 and public.posto_do_grupo(c.posto_afericao)
                 and (c.data_ultima_afericao + interval '2 years')::date
                     between current_date - 30 and current_date + 90
             ) as risco,

             (select a.enviado_em from public.avisos_empresa a
               where a.empresa_id = e.id and a.competencia = v_comp) as avisada_em,

             greatest(
               max(c.data_ultimo_whatsapp),
               (select max(l.created_at) from public.ligacoes l where l.empresa_id = e.id),
               (select max(l.created_at) from public.ligacoes l
                 join public.caminhoneiros x on x.id = l.caminhoneiro_id
                where x.empresa_id = e.id)
             ) as ultima_abordagem

      from public.empresas e
      left join public.caminhoneiros c on c.empresa_id = e.id
      where e.ativo
        and (public.is_admin() or e.unidade_id = public.unidade_do_usuario())
        and (p_unidade is null or e.unidade_id = p_unidade)
      group by e.id, e.nome, e.cnpj, e.contato, e.telefone, e.unidade_id, e.situacao
    ) g
  ) y;

  return v;
end $$;

revoke all on function public.empresas_painel(uuid, date) from public, anon;
grant execute on function public.empresas_painel(uuid, date) to authenticated, service_role;

-- A listar_leads de 5 argumentos ficou viva quando a de 6 (p_mes) foi criada.
-- É a mesma armadilha do registrar_envio_whatsapp na 0044: o app chama a de 6,
-- mas a velha continua acessível e não conhece empresas.
drop function if exists public.listar_leads(integer, integer, text, text, uuid);
