-- 0117 — O CAMINHÃO QUE AFERIU AQUI NOS ÚLTIMOS 30 DIAS CONTINUA VISÍVEL PARA A UNIDADE (09/11)
--
-- A régua de leitura da operadora (pode_ler_lead) só deixa ver o que está na faixa de
-- trabalho: vence em 45 dias ou venceu há até 12 meses. Quem aferiu hoje vence daqui a
-- 2 anos — e some. Isso quebrava duas coisas do fluxo novo do "Novo lead → aferiu AQUI":
--   1) o `returning id` do insert era recusado pelo RLS (lead sem data está fora da
--      régua): "new row violates row-level security policy" (Fernanda, 09/11);
--   2) depois do Aferido, a ficha para completar o cadastro (o ponto de balcão depende
--      disso) abria como "Lead não encontrado".
-- O item 1 o front resolveu gerando o id antes de inserir. O item 2 é regra: a operadora
-- precisa reabrir o caminhão que acabou de passar pelo balcão — para completar o cadastro,
-- corrigir o telefone, desfazer um Aferido errado. Regra nova: lead da própria unidade com
-- data de aferição nos últimos `afericao_recente_dias` (30) dias é legível pela equipe da
-- unidade, esteja ou não na faixa. Não entra na fila (a fila tem régua própria); aparece
-- pela busca e pelo filtro "Aferido". Admin geral não muda (já vê tudo).

alter table public.unidades
  add column if not exists afericao_recente_dias integer not null default 30;

create or replace function public.pode_ler_lead(p_unidade_id uuid, p_tem_tacografo boolean, p_data_afericao date, p_empresa_id uuid default null)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select public.is_equipe_ativa() and (
    public.is_admin()
    -- 0117 — aferição recente na própria unidade: visível para completar o cadastro
    or (
      p_unidade_id = public.unidade_do_usuario()
      and p_data_afericao is not null
      and p_data_afericao >= current_date - (select coalesce(u.afericao_recente_dias, 30) from public.unidades u where u.id = p_unidade_id)
      and p_data_afericao <= current_date
    )
    or (
      p_unidade_id = public.unidade_do_usuario()
      and p_tem_tacografo = true
      and p_data_afericao is not null
      and case
        -- ---- gestor da unidade ----
        when public.is_admin_unidade() then
          (p_data_afericao + interval '2 years')::date
            >= current_date - coalesce(public.piso_do_usuario(), 365)
          and (p_data_afericao + interval '2 years')::date
            <= current_date + coalesce(public.agrupamento_gestor_do_usuario(), 365)
          and case
            when p_empresa_id is null then
              (p_data_afericao + interval '2 years')::date
                <= current_date + coalesce(public.janela_gestor_do_usuario(), 60)
            else exists (
              select 1
                from public.caminhoneiros f
               where f.empresa_id = p_empresa_id
                 and f.tem_tacografo
                 and f.data_ultima_afericao is not null
                 and (f.data_ultima_afericao + interval '2 years')::date
                     between current_date - coalesce(public.piso_do_usuario(), 365)
                         and current_date + coalesce(public.janela_gestor_do_usuario(), 60))
          end
        -- ---- operadora: exatamente como era antes ----
        else
          public.janela_do_usuario() is null
          or ( (p_data_afericao + interval '2 years')::date
                 <= current_date + public.janela_do_usuario()
           and (p_data_afericao + interval '2 years')::date
                 >= current_date - coalesce(public.piso_do_usuario(), 365) )
      end
    )
  );
$$;
