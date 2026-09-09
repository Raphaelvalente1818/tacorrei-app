-- 0069 — Pontos retroativos das aferições registradas em setembro
--
-- O motor nasceu em 09/09. As 7 aferições registradas desde 01/09 são pontuadas
-- com o estado que o caminhão tinha ANTES (que ainda está lá, porque o botão
-- Aferido da ficha não trocava o posto). O vencimento anterior é desconhecido
-- (foi sobrescrito), então nenhuma delas pode cair em 'vencido'. Marcadas como
-- 'retroativo' para o relatório não confundir com registro ao vivo.
--
-- Resultado: Santo André 3 conquistas atribuídas à Ivanessa (contatos de
-- 26–27/08); São Bernardo 4 aferições de agosto sem contato prévio — vieram
-- sozinhas, não pontuam para ninguém.
do $$
declare r record;
begin
  for r in
    select l.id as ligacao, c.id as lead, c.data_ultima_afericao as data, c.posto_afericao as posto
      from public.ligacoes l
      join public.caminhoneiros c on c.id = l.caminhoneiro_id
     where l.canal = 'presencial' and l.resultado = 'aferido'
       and l.created_at >= '2026-09-01'
       and c.data_ultima_afericao is not null
       and not exists (select 1 from public.pontos p where p.ligacao_id = l.id)
  loop
    perform public.pontuar_afericao(r.lead, r.data, r.ligacao, r.posto, null);
  end loop;
end $$;

update public.pontos set origem = 'retroativo', registrado_por = null
 where registrado_em >= now() - interval '5 minutes' and origem = 'app';

-- E agora sim: quem aferiu conosco passa a constar como nosso. O trigger
-- registra a troca em historico_posto.
update public.caminhoneiros c
   set posto_afericao = u.posto_afericao, updated_at = now()
  from public.unidades u
 where u.id = c.unidade_id and u.posto_afericao is not null
   and not public.posto_do_grupo(c.posto_afericao)
   and exists (select 1 from public.ligacoes l
                where l.caminhoneiro_id = c.id and l.canal = 'presencial' and l.resultado = 'aferido'
                  and l.created_at >= '2026-08-01');
