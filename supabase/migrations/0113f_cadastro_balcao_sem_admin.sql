-- 0113f — "CADASTRO COMPLETO NO BALCÃO" NÃO CONTA LANÇAMENTO DA MATRIZ (07/10)
--
-- Emerson, olhando a Meta de São Bernardo em outubro: "pode limpar esses números
-- do Emerson e Raphael que estão aí?" — Raphael 12 aferições / 0 completos,
-- Emerson 1 / 0. Eram lançamentos feitos de fora do balcão (Raphael registrou em
-- 06/10 as aferições de 1 a 6/10 a partir das ordens de serviço), sem o dono na
-- frente. O cartão mede o BALCÃO — quem está com o cliente e o documento na mão —
-- então aferição registrada por admin geral sai da conta e da lista. Os pontos
-- dessas aferições (Pamela, Fernanda) não mudam: isso aqui é só o cartão.

do $$
declare v_def text; v_oid oid;
begin
  select oid into v_oid from pg_proc where proname = 'montar_meta' and pronamespace = 'public'::regnamespace;
  v_def := pg_get_functiondef(v_oid);

  if position('left join public.equipe q on q.user_id = p2.registrado_por
             where p2.unidade_id = p_unidade and p2.competencia = v_comp' in v_def) = 0
     or position('      from public.pontos p
      where p.unidade_id = p_unidade and p.competencia = v_comp
        and (p_operadora is null or p.registrado_por = p_operadora or p.operadora_id = p_operadora)
    )' in v_def) = 0 then
    raise exception '0113f: ancoras do bloco cadastro nao encontradas';
  end if;

  v_def := replace(v_def,
    'left join public.equipe q on q.user_id = p2.registrado_por
             where p2.unidade_id = p_unidade and p2.competencia = v_comp',
    'left join public.equipe q on q.user_id = p2.registrado_por
             where p2.unidade_id = p_unidade and p2.competencia = v_comp
               and coalesce(q.papel, '''') <> ''admin''');

  v_def := replace(v_def,
    '      from public.pontos p
      where p.unidade_id = p_unidade and p.competencia = v_comp
        and (p_operadora is null or p.registrado_por = p_operadora or p.operadora_id = p_operadora)
    )',
    '      from public.pontos p
      where p.unidade_id = p_unidade and p.competencia = v_comp
        and not exists (select 1 from public.equipe a where a.user_id = p.registrado_por and a.papel = ''admin'')
        and (p_operadora is null or p.registrado_por = p_operadora or p.operadora_id = p_operadora)
    )');

  execute v_def;
end $$;
