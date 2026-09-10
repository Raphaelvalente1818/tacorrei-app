-- 0073 — Admin geral não pertence a unidade nenhuma
--
-- Emerson e Raphael estavam lotados em Santo André com papel 'admin'. Toda
-- permissão já tem `is_admin() or …`, então a lotação era cosmética — até o dia
-- em que não foi: a importação de 6.128 veículos caiu em Santo André porque um
-- fallback usou `unidade_do_usuario()` (0063/0064). O mesmo fallback ainda
-- existia no gatilho de inserção de lead. Admin geral fica SEM unidade, e onde
-- o sistema precisava de uma, agora pede em vez de adivinhar.

update public.equipe set unidade_id = null where papel = 'admin';

-- O gatilho: cidade mapeada define a unidade; sem cidade mapeada, operador e
-- admin de unidade caem na própria unidade (correto para eles); admin geral
-- precisa dizer qual — nunca mais um lead entra na unidade errada por acidente.
create or replace function public.set_unidade_caminhoneiro()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.unidade_id is null then
    if new.cidade is not null then
      select uc.unidade_id into new.unidade_id
      from public.unidade_cidades uc
      where lower(uc.cidade) = lower(new.cidade)
      limit 1;
    end if;
    if new.unidade_id is null then
      new.unidade_id := public.unidade_do_usuario();
    end if;
    if new.unidade_id is null then
      raise exception 'informe a unidade do lead: a cidade "%" nao esta na cobertura de nenhuma unidade',
        coalesce(new.cidade, '(vazia)');
    end if;
  end if;
  return new;
end $$;
