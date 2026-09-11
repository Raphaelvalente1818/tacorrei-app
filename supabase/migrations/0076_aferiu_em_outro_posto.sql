-- 0076 — "Aferiu em outro posto": o caminhão sai da fila sem virar cliente da casa
--
-- Contexto (11/09/2026). Em agosto a Ivanessa usou o botão Aferido em quatro placas de
-- Santo André com a nota "aferido em outra empresa" — o jeito certo de tirar da fila um
-- caminhão que renovou no concorrente, mas o único jeito que existia. A 0069 marcou o
-- posto dessas placas como o da unidade, e elas passaram a aparecer como "Cliente da
-- casa". Não geraram ponto (não tinham ligação de origem), então o placar está certo;
-- o posto é que está errado.
--
-- Esta migration (1) cria a operação "aferiu em outro posto", (2) corrige as quatro.
--
-- O que "aferiu em outro posto" faz: data da aferição atualizada (sai da fila e volta
-- em 2 anos), posto = concorrente, status volta a 'novo' (é um ciclo novo, com o
-- concorrente), histórico com resultado 'atualizacao' (não conta como aferição nossa em
-- lugar nenhum). Se o caminhão era nosso, o gatilho trg_troca_de_posto grava o 'fuga'
-- sozinho — a função NÃO insere em historico_posto (a primeira versão inseria e
-- duplicava; corrigido na 0076b, já incorporada aqui).

create or replace function public.registrar_afericao_fora(
  p_lead uuid, p_data date, p_notas text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_unidade uuid; v_lead jsonb;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;

  select c.unidade_id into v_unidade from public.caminhoneiros c where c.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;
  if p_data is null then raise exception 'informe a data'; end if;
  if p_data > current_date then raise exception 'a data da afericao nao pode ser no futuro'; end if;

  update public.caminhoneiros
     set data_ultima_afericao = p_data,
         posto_afericao = 'OUTRO POSTO (concorrente)',
         status = 'novo',
         updated_at = now()
   where id = p_lead;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'sistema', 'atualizacao',
          'Aferiu em outro posto em ' || to_char(p_data, 'DD/MM/YYYY')
          || coalesce('. ' || nullif(btrim(p_notas), ''), ''));

  select to_jsonb(c) into v_lead from public.caminhoneiros c where c.id = p_lead;
  return v_lead;
end $$;

revoke execute on function public.registrar_afericao_fora(uuid, date, text) from public, anon;
grant execute on function public.registrar_afericao_fora(uuid, date, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Correção das quatro placas de Santo André marcadas como Aferido em agosto com a
-- nota "aferido em outra empresa". Placas: ACA4782, DBM7707, MRM2F53, DAJ9H67.
-- ---------------------------------------------------------------------------
with alvo as (
  select c.id from public.caminhoneiros c
   where c.placa_veiculo in ('ACA4782','DBM7707','MRM2F53','DAJ9H67')
     and c.posto_afericao ilike '%LACRE%'
)
update public.caminhoneiros c
   set posto_afericao = 'OUTRO POSTO (concorrente)', status = 'novo', updated_at = now()
  from alvo where c.id = alvo.id;

-- o registro da Ivanessa vira o mesmo tipo de registro que o botão novo grava
update public.ligacoes l
   set canal = 'sistema', resultado = 'atualizacao',
       notas = 'Aferiu em outro posto em ' || to_char(c.data_ultima_afericao, 'DD/MM/YYYY') || '. ' || l.notas
  from public.caminhoneiros c
 where c.id = l.caminhoneiro_id
   and c.placa_veiculo in ('ACA4782','DBM7707','MRM2F53','DAJ9H67')
   and l.resultado = 'aferido' and l.canal = 'presencial';

-- a 0069 registrou "primeira aferição conosco" para elas — não foi; e o update de posto
-- acima faz o gatilho gravar um 'fuga' (LACRE → concorrente) que também é falso
delete from public.historico_posto h
 using public.caminhoneiros c
 where c.id = h.caminhoneiro_id
   and c.placa_veiculo in ('ACA4782','DBM7707','MRM2F53','DAJ9H67')
   and ((h.movimento = 'primeira_afericao' and h.posto_novo ilike '%LACRE%')
     or (h.movimento = 'fuga' and h.posto_anterior ilike '%LACRE%'));
