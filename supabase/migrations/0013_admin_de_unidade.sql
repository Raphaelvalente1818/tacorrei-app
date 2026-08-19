-- 0013_admin_de_unidade.sql
-- PAPEL NOVO: 'admin_unidade' — o dono/gerente de UMA unidade.
--
-- Fica entre o operador e o admin pleno:
--   operador       -> so a fila (com tacografo + janela) da unidade dele
--   admin_unidade  -> a BASE INTEIRA da unidade dele (inclusive sem tacografo e
--                     fora da janela) + gerir os acessos DA PROPRIA unidade
--   admin          -> tudo, todas as unidades (so Raphael e Emerson)
--
-- O admin_unidade NAO cria admin, NAO mexe em quem e de outra unidade, NAO
-- configura cobertura/territorio (isso e do Aferi+, nao da unidade) e NAO
-- enxerga lead nenhum de outra unidade -- so os totais agregados do placar e
-- da aba Unidades, que e o que alimenta a disputa.

alter table public.equipe drop constraint if exists equipe_papel_check;
alter table public.equipe add constraint equipe_papel_check
  check (papel = any (array['admin','admin_unidade','operador']));

create or replace function public.is_admin_unidade()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from equipe e
    where e.user_id = auth.uid() and e.ativo and e.papel = 'admin_unidade'
  );
$$;

create or replace function public.gere_unidade(p_unidade uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or (public.is_admin_unidade() and p_unidade = public.unidade_do_usuario());
$$;

drop policy if exists "caminhoneiros: le unidade" on public.caminhoneiros;
create policy "caminhoneiros: le unidade" on public.caminhoneiros
for select using (
  is_equipe_ativa() and (
    is_admin()
    or (is_admin_unidade() and unidade_id = unidade_do_usuario())
    or (
      unidade_id = unidade_do_usuario()
      and tem_tacografo = true
      and (
        janela_do_usuario() is null
        or (data_ultima_afericao is not null
            and (data_ultima_afericao + interval '2 years')::date
                  <= current_date + janela_do_usuario())
      )
    )
  )
);

drop policy if exists "equipe: admin lê todos" on public.equipe;
create policy "equipe: admin lê todos" on public.equipe
for select using (
  is_admin() or (is_admin_unidade() and unidade_id = unidade_do_usuario())
);

drop policy if exists "equipe: admin insere" on public.equipe;
create policy "equipe: admin insere" on public.equipe
for insert with check (
  is_admin()
  or (is_admin_unidade()
      and unidade_id = unidade_do_usuario()
      and papel = 'operador')
);

drop policy if exists "equipe: admin atualiza" on public.equipe;
create policy "equipe: admin atualiza" on public.equipe
for update using (
  is_admin() or (is_admin_unidade() and unidade_id = unidade_do_usuario())
) with check (
  is_admin()
  or (is_admin_unidade()
      and unidade_id = unidade_do_usuario()
      and papel = 'operador')
);

-- unidades_painel: liberado tambem ao admin_unidade (devolve SO agregados).
-- Corpo identico ao da 0011, mudando apenas a checagem de permissao.
create or replace function public.unidades_painel()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_res jsonb;
begin
  if not (public.is_admin() or public.is_admin_unidade()) then
    raise exception 'acesso negado';
  end if;

  select coalesce(jsonb_agg(x order by x.carteira desc, x.nome), '[]'::jsonb)
    into v_res
  from (
    select
      u.id, u.nome, u.janela_dias,
      (select string_agg(uc.cidade, ' · ' order by uc.cidade)
         from unidade_cidades uc where uc.unidade_id = u.id) as cidades,
      count(c.id) filter (where c.tem_tacografo) as carteira,
      count(c.id) filter (
        where c.tem_tacografo
          and (u.janela_dias is null
               or (c.data_ultima_afericao + interval '2 years')::date
                    <= current_date + u.janela_dias)
      ) as fila,
      count(c.id) filter (
        where c.tem_tacografo and c.data_ultimo_whatsapp is not null
      ) as abordados,
      count(c.id) filter (where c.status = 'aferido') as aferidos
    from unidades u
    left join caminhoneiros c on c.unidade_id = u.id
    group by u.id, u.nome, u.janela_dias
  ) x;

  return v_res;
end;
$$;

grant execute on function public.is_admin_unidade() to authenticated;
grant execute on function public.gere_unidade(uuid) to authenticated;
