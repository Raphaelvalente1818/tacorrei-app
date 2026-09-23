-- 0105b — Importador: RENAVAM sempre com 11 digitos (o Excel come os zeros a esquerda)
-- e leitura dos campos da GRU (chassi, ano, endereco, cep, email) na tela Importar base.
-- Aplicada em 23/09/2026 (migration importacao_renavam_11_e_campos_gru); reconciliada (regra 13).
drop function if exists public.preparar_base(uuid, jsonb);

create function public.preparar_base(p_unidade uuid, p_linhas jsonb)
 returns table(placa text, nome text, telefone text, cidade text, uf text, rntrc text, renavam text, modelo text, data date, posto text, cpf_cnpj text, na_cobertura boolean, duplicada boolean, existente_id uuid, existente_data date, existente_posto text, chassi text, ano_fabricacao smallint, endereco text, cep text, email text)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with brutas as (
    select public.normaliza_placa(x.placa) as placa,
           nullif(btrim(coalesce(x.nome, '')), '') as nome,
           nullif(btrim(coalesce(nullif(nullif(btrim(coalesce(x.celular,'')), ''), '0'), nullif(btrim(coalesce(x.telefone,'')), '0'), '')), '') as telefone,
           nullif(btrim(coalesce(x.cidade, '')), '') as cidade,
           nullif(upper(btrim(coalesce(x.uf, ''))), '') as uf,
           nullif(regexp_replace(coalesce(x.rntrc, ''), '\D', '', 'g'), '') as rntrc,
           -- RENAVAM sempre com 11 digitos (Excel remove os zeros a esquerda)
           case when regexp_replace(coalesce(x.renavam, ''), '\D', '', 'g') ~ '^[0-9]{1,11}$'
                then lpad(regexp_replace(x.renavam, '\D', '', 'g'), 11, '0')
                else nullif(regexp_replace(coalesce(x.renavam, ''), '\D', '', 'g'), '') end as renavam,
           nullif(btrim(coalesce(x.tipo, '')), '') as modelo,
           case when x.data ~ '^\d{4}-\d{2}-\d{2}$' then x.data::date else null end as data,
           case when upper(btrim(coalesce(x.posto, ''))) in ('', 'NENHUM RESULTADO', 'NENHUM RESULTADO.', '-', '--', 'N/A')
                then null else btrim(x.posto) end as posto,
           nullif(regexp_replace(coalesce(x.cpf_cnpj, ''), '\D', '', 'g'), '') as cpf_cnpj,
           nullif(upper(regexp_replace(coalesce(x.chassi, ''), '\s', '', 'g')), '') as chassi,
           case when btrim(coalesce(x.ano_fabricacao, '')) ~ '^(19[5-9][0-9]|20[0-9]{2})$' then btrim(x.ano_fabricacao)::smallint end as ano_fabricacao,
           nullif(btrim(coalesce(x.endereco, '')), '') as endereco,
           case when regexp_replace(coalesce(x.cep, ''), '\D', '', 'g') ~ '^[0-9]{7,8}$'
                then lpad(regexp_replace(x.cep, '\D', '', 'g'), 8, '0') end as cep,
           case when btrim(coalesce(x.email, '')) like '%@%' then lower(btrim(x.email)) end as email,
           row_number() over () as ordem
    from jsonb_to_recordset(coalesce(p_linhas, '[]'::jsonb)) as x(
      placa text, nome text, telefone text, celular text, cidade text, uf text, rntrc text,
      renavam text, tipo text, data text, posto text, cpf_cnpj text,
      chassi text, ano_fabricacao text, endereco text, cep text, email text)
  ),
  validas as (
    select b.*,
           row_number() over (partition by b.placa order by (b.data is null), b.ordem) as rep
    from brutas b
    where b.placa is not null and length(b.placa) = 7
  )
  select v.placa, v.nome, v.telefone, v.cidade, v.uf, v.rntrc, v.renavam, v.modelo, v.data, v.posto, v.cpf_cnpj,
         exists (select 1 from public.unidade_cidades uc
                  where uc.unidade_id = p_unidade
                    and public.normaliza_texto(uc.cidade) = public.normaliza_texto(v.cidade)) as na_cobertura,
         v.rep > 1 as duplicada,
         c.id, c.data_ultima_afericao, c.posto_afericao,
         v.chassi, v.ano_fabricacao, v.endereco, v.cep, v.email
  from validas v
  left join public.caminhoneiros c
    on c.unidade_id = p_unidade and public.normaliza_placa(c.placa_veiculo) = v.placa
$function$;

revoke all on function public.preparar_base(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.preparar_base(uuid, jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.importar_base(p_unidade uuid, p_linhas jsonb, p_rotulo text DEFAULT NULL::text, p_incluir_fora_cobertura boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_criados int := 0; v_atualizados int := 0; v_sem_data int := 0; v_fora int := 0; v_ign int := 0;
  v_id uuid; v_resumo jsonb;
begin
  if not public.is_admin() then raise exception 'acesso negado: so o admin geral importa base'; end if;
  if not exists (select 1 from public.unidades where id = p_unidade) then raise exception 'unidade nao encontrada'; end if;

  drop table if exists _imp;
  create temp table _imp on commit drop as
    select * from public.preparar_base(p_unidade, p_linhas)
     where not duplicada;

  select count(*) filter (where not na_cobertura) into v_fora from _imp;
  if not coalesce(p_incluir_fora_cobertura, false) then
    delete from _imp where not na_cobertura;
  end if;

  update public.caminhoneiros c
     set dono_trocou_em = null, dono_trocou_por = null,
         nome = coalesce(i.nome, c.nome),
         telefone = coalesce(i.telefone, c.telefone),
         documento = i.cpf_cnpj,
         telefone_invalido_em = null,
         updated_at = now()
    from _imp i
   where i.existente_id = c.id
     and c.dono_trocou_em is not null
     and c.documento is not null
     and (i.cpf_cnpj ~ '^[0-9]{11}$' or i.cpf_cnpj ~ '^[0-9]{14}$')
     and i.cpf_cnpj <> c.documento;

  insert into public.correcoes (quem, unidade_id, acao, alvo_tipo, alvo_id, motivo)
  select auth.uid(), c.unidade_id, 'dono_trocou_confirmado', 'lead', c.id,
         'Importacao trouxe outro documento para a placa: proprietario mudou e o caminhao voltou para a fila.'
    from public.caminhoneiros c
    join _imp i on i.existente_id = c.id
   where c.dono_trocou_em is null and c.updated_at >= now() - interval '1 second'
     and (i.cpf_cnpj ~ '^[0-9]{11}$' or i.cpf_cnpj ~ '^[0-9]{14}$')
     and i.cpf_cnpj = c.documento;

  update public.caminhoneiros c
     set nome = coalesce(c.nome, i.nome),
         telefone = case when coalesce(c.telefone, '') = '' then coalesce(i.telefone, c.telefone) else c.telefone end,
         cidade = coalesce(c.cidade, i.cidade),
         uf = coalesce(c.uf, i.uf),
         rntrc = coalesce(c.rntrc, i.rntrc),
         renavam = coalesce(c.renavam, i.renavam),
         documento = coalesce(c.documento,
                              case when i.cpf_cnpj ~ '^[0-9]{11}$' or i.cpf_cnpj ~ '^[0-9]{14}$'
                                   then i.cpf_cnpj end),
         modelo_veiculo = coalesce(c.modelo_veiculo, i.modelo),
         chassi = coalesce(c.chassi, i.chassi),
         ano_fabricacao = coalesce(c.ano_fabricacao, i.ano_fabricacao),
         endereco = coalesce(c.endereco, i.endereco),
         cep = coalesce(c.cep, i.cep),
         email = coalesce(c.email, i.email),
         posto_afericao = case when i.posto is not null
                                and (c.data_ultima_afericao is null or i.data > c.data_ultima_afericao)
                               then i.posto else c.posto_afericao end,
         data_ultima_afericao = greatest(c.data_ultima_afericao, i.data),
         tem_tacografo = c.tem_tacografo or i.data is not null,
         updated_at = now()
    from _imp i
   where i.existente_id = c.id
     and ((c.documento is null and i.cpf_cnpj is not null)
          or c.nome is null or coalesce(c.telefone,'') = '' or c.cidade is null or c.uf is null
          or c.rntrc is null or c.renavam is null or c.modelo_veiculo is null
          or (c.chassi is null and i.chassi is not null)
          or (c.ano_fabricacao is null and i.ano_fabricacao is not null)
          or (c.endereco is null and i.endereco is not null)
          or (c.cep is null and i.cep is not null)
          or (c.email is null and i.email is not null)
          or (i.data is not null and (c.data_ultima_afericao is null or i.data > c.data_ultima_afericao)));
  get diagnostics v_atualizados = row_count;

  insert into public.caminhoneiros
    (nome, telefone, cidade, uf, placa_veiculo, modelo_veiculo, rntrc, renavam,
     data_ultima_afericao, posto_afericao, tem_tacografo, unidade_id, origem, status, observacoes, documento,
     chassi, ano_fabricacao, endereco, cep, email)
  select coalesce(i.nome, i.cpf_cnpj, 'SEM NOME'), coalesce(i.telefone, ''), i.cidade, i.uf, i.placa, i.modelo,
         i.rntrc, i.renavam, i.data, case when i.data is not null then i.posto end,
         i.data is not null, p_unidade, 'outro', 'novo',
         case when i.data is null then 'Sem data de aferição na extração: fora da fila até ser verificado.' end,
         case when i.cpf_cnpj ~ '^[0-9]{11}$' or i.cpf_cnpj ~ '^[0-9]{14}$' then i.cpf_cnpj end,
         i.chassi, i.ano_fabricacao, i.endereco, i.cep, i.email
    from _imp i
   where i.existente_id is null;
  get diagnostics v_criados = row_count;

  select count(*) filter (where data is null and existente_id is null) into v_sem_data from _imp;
  v_ign := jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)) - (select count(*) from _imp)
           - (select count(*) from public.preparar_base(p_unidade, p_linhas) where duplicada);

  v_resumo := jsonb_build_object(
    'linhas', jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)),
    'criados', v_criados, 'atualizados', v_atualizados, 'sem_data', v_sem_data,
    'fora_cobertura', v_fora, 'fora_cobertura_incluidas', coalesce(p_incluir_fora_cobertura, false),
    'ignoradas', greatest(v_ign, 0));

  insert into public.importacoes (unidade_id, importado_por, rotulo, linhas, criados, atualizados, sem_data, fora_cobertura, ignorados, resumo)
  values (p_unidade, auth.uid(), nullif(btrim(coalesce(p_rotulo,'')), ''),
          jsonb_array_length(coalesce(p_linhas, '[]'::jsonb)), v_criados, v_atualizados, v_sem_data, v_fora, greatest(v_ign, 0), v_resumo)
  returning id into v_id;

  return v_resumo || jsonb_build_object('id', v_id);
end $function$;
