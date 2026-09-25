-- 0112 — CADASTRO COMPLETO: VISÍVEL, COBRÁVEL, NÃO PAGO (25/09)
--
-- Ideia do Emerson: quando a operadora clica em Aferido, o caminhão está no
-- balcão e o dono com o documento na mão — é o único momento em que o dado sai
-- de graça. Daqui a dois anos, quando a placa voltar para a fila, o que vale é
-- ter o CPF do dono (consulta no Inmetro por documento, guia) e um telefone que
-- seja DO DONO, não do motorista que o RNTRC registrou.
--
-- A forma foi decidida junto, e é a regra 11 aplicada ao cadastro: "pagar por
-- esforço compra esforço, não resultado". Não se obriga (campo obrigatório com o
-- cliente esperando vira número inventado) e não se premia (ponto por campo
-- produz campo, não dado certo). O cadastro completo fica VISÍVEL — na ficha, no
-- clique Aferido e na Meta, por quem marcou a aferição — e o gestor cobra.
--
-- O que entra:
--   1. `telefone_confirmado_em/por`: o clique "é este mesmo o número do dono?".
--      Muda o telefone por importação → a confirmação cai (gatilho).
--   2. `faltas_cadastro(lead, para_gru)`: UMA definição do que falta. Para a
--      guia (dados_gru) são CPF/CNPJ, chassi, placa, RENAVAM de 11; para o
--      cadastro completo, o mesmo mais o telefone confirmado.
--   3. `cadastro_do_lead(lead)` → {completo, faltando}; `obter_lead` devolve em
--      `cadastro` para a ficha mostrar o selo.
--   4. `confirmar_telefone(lead, telefone?)`: confirma (e troca, se vier outro).
--      Registra em `ligacoes` (sistema/atualizacao), limpa `telefone_invalido_em`.
--   5. `montar_meta` ganha `cadastro`: por quem marcou a aferição no mês,
--      quantas com cadastro completo. Não entra em pontos, prêmio ou fechamento.
--   6. `dados_gru` fecha a exceção do documento: a única função que devolve o CPF
--      para a tela passa a exigir que o lead esteja na régua de quem pediu
--      (`pode_ler_lead`) e registra na trilha (`acessos_lead`, ação 'gru').

-- 1) telefone confirmado no balcão -------------------------------------------
alter table public.caminhoneiros
  add column if not exists telefone_confirmado_em timestamptz,
  add column if not exists telefone_confirmado_por uuid;

comment on column public.caminhoneiros.telefone_confirmado_em is
  'Quando alguém confirmou, com o dono na frente, que este é o telefone dele. Cai se o telefone mudar.';

create or replace function public.trg_telefone_confirmado_cai()
returns trigger language plpgsql as $$
begin
  -- Telefone trocou sem ser pelo próprio confirmar_telefone (que seta os dois
  -- campos na mesma instrução): a confirmação era do número antigo.
  if new.telefone is distinct from old.telefone
     and new.telefone_confirmado_em is not distinct from old.telefone_confirmado_em then
    new.telefone_confirmado_em := null;
    new.telefone_confirmado_por := null;
  end if;
  return new;
end $$;

drop trigger if exists trg_telefone_confirmado_cai on public.caminhoneiros;
create trigger trg_telefone_confirmado_cai
  before update of telefone on public.caminhoneiros
  for each row execute function public.trg_telefone_confirmado_cai();

-- 2) uma definição do que falta -------------------------------------------------
create or replace function public.faltas_cadastro(p_lead uuid, p_para_gru boolean default false)
returns text[]
language sql stable
set search_path to 'public', 'pg_temp'
as $$
  with c as (
    select c.*, coalesce(
             nullif(regexp_replace(coalesce(c.documento, ''), '\D', '', 'g'), ''),
             (select nullif(regexp_replace(coalesce(e.cnpj, ''), '\D', '', 'g'), '')
                from public.empresas e where e.id = c.empresa_id)) as doc
      from public.caminhoneiros c where c.id = p_lead
  )
  select array_remove(array[
    case when coalesce(doc, '') !~ '^([0-9]{11}|[0-9]{14})$' then 'CPF/CNPJ' end,
    case when coalesce(chassi, '') = '' then 'Chassi' end,
    case when coalesce(placa_veiculo, '') = '' then 'Placa' end,
    case when coalesce(renavam, '') !~ '^[0-9]{11}$' then 'RENAVAM (11 dígitos)' end,
    case when not p_para_gru and telefone_confirmado_em is null then 'Telefone confirmado' end
  ], null)
  from c;
$$;
revoke all on function public.faltas_cadastro(uuid, boolean) from public, anon;
grant execute on function public.faltas_cadastro(uuid, boolean) to authenticated, service_role;

create or replace function public.cadastro_do_lead(p_lead uuid)
returns jsonb
language sql stable
set search_path to 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'completo', cardinality(f) = 0,
    'faltando', to_jsonb(f))
  from public.faltas_cadastro(p_lead, false) f;
$$;
revoke all on function public.cadastro_do_lead(uuid) from public, anon;
grant execute on function public.cadastro_do_lead(uuid) to authenticated, service_role;

-- 3) a ficha recebe `cadastro` ---------------------------------------------------
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.obter_lead(uuid)'::regprocedure);
  if position('''afericao_fora'', (' in v_def) = 0 then
    raise exception '0112: ancora afericao_fora nao encontrada em obter_lead';
  end if;
  v_def := replace(v_def, '''afericao_fora'', (',
    '''cadastro'', public.cadastro_do_lead(c.id),
    ''afericao_fora'', (');
  execute v_def;
end $$;

-- 4) confirmar o telefone no balcão ---------------------------------------------
create or replace function public.confirmar_telefone(p_lead uuid, p_telefone text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_unidade uuid; v_tel text; v_novo text; c public.caminhoneiros;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  select x.unidade_id, x.telefone into v_unidade, v_tel from public.caminhoneiros x where x.id = p_lead;
  if v_unidade is null then raise exception 'lead nao encontrado'; end if;
  if not (public.is_admin() or v_unidade = public.unidade_do_usuario()) then
    raise exception 'acesso negado';
  end if;

  v_novo := nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), '');
  if v_novo is not null and v_novo !~ '^[0-9]{10,11}$' then
    raise exception 'telefone precisa ter DDD + numero (10 ou 11 digitos)';
  end if;
  if v_novo is null and coalesce(regexp_replace(v_tel, '\D', '', 'g'), '') !~ '^[0-9]{10,11}$' then
    raise exception 'este lead nao tem telefone valido para confirmar — informe o numero';
  end if;

  update public.caminhoneiros
     set telefone = coalesce(v_novo, telefone),
         telefone_confirmado_em = now(),
         telefone_confirmado_por = auth.uid(),
         telefone_invalido_em = null,
         updated_at = now()
   where id = p_lead
   returning * into c;

  insert into public.ligacoes (caminhoneiro_id, unidade_id, operador_id, canal, resultado, notas)
  values (p_lead, v_unidade, auth.uid(), 'sistema', 'atualizacao',
          case when v_novo is not null and v_novo <> coalesce(regexp_replace(v_tel, '\D', '', 'g'), '')
               then 'Telefone do dono confirmado no balcão (número trocado)'
               else 'Telefone do dono confirmado no balcão' end);

  return (to_jsonb(c) - 'documento') || jsonb_build_object('cadastro', public.cadastro_do_lead(c.id));
end $function$;
revoke all on function public.confirmar_telefone(uuid, text) from public, anon;
grant execute on function public.confirmar_telefone(uuid, text) to authenticated, service_role;

-- 5) Meta: cadastro completo por quem marcou a aferição ---------------------------
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.montar_meta(uuid, date, uuid, boolean)'::regprocedure);
  if position(E'''auditoria'', v_auditoria\n  );' in v_def) = 0 then
    raise exception '0112: ancora do retorno nao encontrada em montar_meta';
  end if;
  v_def := replace(v_def, E'''auditoria'', v_auditoria\n  );',
    '''auditoria'', v_auditoria,
    ''cadastro'', (
      select jsonb_build_object(
        ''afericoes'', count(*),
        ''completos'', count(*) filter (where cardinality(public.faltas_cadastro(p.caminhoneiro_id, false)) = 0),
        ''por_pessoa'', coalesce((
          select jsonb_agg(to_jsonb(r) order by r.afericoes desc, r.nome)
          from (
            select coalesce(q.nome, ''Sem registro'') as nome,
                   count(*) as afericoes,
                   count(*) filter (where cardinality(public.faltas_cadastro(p2.caminhoneiro_id, false)) = 0) as completos
              from public.pontos p2
              left join public.equipe q on q.user_id = p2.registrado_por
             where p2.unidade_id = p_unidade and p2.competencia = v_comp
               and (p_operadora is null or p2.registrado_por = p_operadora or p2.operadora_id = p_operadora)
             group by q.nome
          ) r), ''[]''::jsonb))
      from public.pontos p
      where p.unidade_id = p_unidade and p.competencia = v_comp
        and (p_operadora is null or p.registrado_por = p_operadora or p.operadora_id = p_operadora)
    )
  );');
  execute v_def;
end $$;

-- 6) dados_gru: a exceção do documento fica fechada e com trilha -------------------
alter table public.acessos_lead drop constraint if exists acessos_lead_acao_check;
alter table public.acessos_lead add constraint acessos_lead_acao_check
  check (acao = any (array['listar', 'abrir', 'placa', 'gru']));

do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.dados_gru(uuid, boolean)'::regprocedure);
  if position('if not (public.is_admin() or c.unidade_id = public.unidade_do_usuario()) then raise exception ''acesso negado''; end if;' in v_def) = 0 then
    raise exception '0112: ancora de acesso nao encontrada em dados_gru';
  end if;
  v_def := replace(v_def,
    'if not (public.is_admin() or c.unidade_id = public.unidade_do_usuario()) then raise exception ''acesso negado''; end if;',
    'if not (public.is_admin() or c.unidade_id = public.unidade_do_usuario()) then raise exception ''acesso negado''; end if;
  -- 0112 — o CPF só sai para quem alcança a ficha pela régua, e fica na trilha.
  if not public.pode_ler_lead(c.unidade_id, c.tem_tacografo, c.data_ultima_afericao, c.empresa_id) then
    raise exception ''acesso negado: este caminhao esta fora da sua regua'';
  end if;
  perform public.registrar_acesso(''gru'', 1, jsonb_build_object(''lead'', p_lead, ''registrar'', p_registrar));');
  execute v_def;
end $$;
