-- 0021_placar_so_do_proprio_grupo.sql   [APLICADA em 19/08/2026]
-- O placar e ferramenta INTERNA: existe porque as duas unidades sao do mesmo dono.
-- NAO vai para os clientes da expansao (decisao do Raphael, 19/08/2026).
--
-- O risco era virar armadilha silenciosa: a RPC devolvia o nome de TODAS as
-- unidades para qualquer membro ativo. No dia em que entrasse o cliente numero 3,
-- a operadora dele abriria o Dashboard e veria nome e volume das unidades da casa
-- -- sem ninguem lembrar de desligar nada.
--
-- SOLUCAO: `unidades.grupo_id`. O placar so compara unidades do MESMO grupo de
-- quem esta olhando. Unidade sem grupo (todo cliente novo, por padrao) recebe
-- menos de 2 linhas -- e o componente do Dashboard ja se esconde sozinho nesse
-- caso. O placar desaparece para quem e de fora, sem tela nova e sem depender de
-- alguem lembrar.
--
-- Bonus: o Swiss Park (teste) fica de fora naturalmente (sem grupo), entao o id
-- fixo dele saiu da funcao.

alter table public.unidades add column if not exists grupo_id uuid;

comment on column public.unidades.grupo_id is
  'Unidades do mesmo dono. Usado pelo placar interno: so compara dentro do grupo. NULL = cliente externo (sem placar).';

update public.unidades
   set grupo_id = '11111111-1111-4111-8111-111111111111'::uuid
 where nome in ('Santo André', 'Tacorrei São Bernardo');

create or replace function public.placar_unidades()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_inicio timestamptz; v_grupo uuid; v_res jsonb;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  select u.grupo_id into v_grupo
  from public.unidades u where u.id = public.unidade_do_usuario();

  if v_grupo is null then
    return '[]'::jsonb;          -- cliente externo: sem placar
  end if;

  v_inicio := date_trunc('month', (now() at time zone 'America/Sao_Paulo'))
              at time zone 'America/Sao_Paulo';

  select coalesce(jsonb_agg(x order by x.total desc, x.unidade), '[]'::jsonb) into v_res
  from (
    select u.nome as unidade, count(l.id) as total,
           (u.id = public.unidade_do_usuario()) as sua
    from public.unidades u
    left join public.ligacoes l
      on l.unidade_id = u.id and l.canal = 'whatsapp' and l.created_at >= v_inicio
    where u.grupo_id = v_grupo
    group by u.id, u.nome
  ) x;

  return v_res;
end $$;

revoke execute on function public.placar_unidades() from public, anon;
grant  execute on function public.placar_unidades() to authenticated;
