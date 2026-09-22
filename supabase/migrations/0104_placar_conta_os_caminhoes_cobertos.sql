-- 0104 — O PLACAR DIZ QUANTOS CAMINHÕES AS CONVERSAS COBRIRAM (22/09)
--
-- O Emerson viu três números de "mensagem" no Dashboard que não batem: o placar
-- (17), o funil (184) e a conversão por canal (209). Não é erro de conta — são
-- três recortes com a mesma palavra em cima: conversas abertas NESTE MÊS; leads
-- que estão HOJE no estado "mensagem enviada"; e todos que JÁ receberam alguma
-- mensagem. A lição 20 de novo: duas contas com o mesmo nome é bug de rótulo.
--
-- O front ganha o recorte escrito embaixo de cada número. Aqui, o placar passa
-- a devolver também `cobertos`: uma conversa com a frota cobre vários caminhões
-- (os irmãos entram em `ligacoes` como canal 'sistema'), e "17 conversas · 41
-- caminhões" conta a história inteira. `total` continua igual (é o que a cota
-- conta e o que a barra mede); `cobertos` é informação a mais, ainda agregada —
-- nenhum lead, nenhum nome.

create or replace function public.placar_unidades()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_inicio timestamptz; v_res jsonb; v_minha uuid;
begin
  if not public.is_equipe_ativa() then raise exception 'acesso negado'; end if;
  v_minha := public.unidade_do_usuario();
  if v_minha is null and not public.is_admin() then return '[]'::jsonb; end if;

  v_inicio := date_trunc('month', (now() at time zone 'America/Sao_Paulo')) at time zone 'America/Sao_Paulo';

  select coalesce(jsonb_agg(x order by x.total desc, x.unidade), '[]'::jsonb) into v_res
  from (
    select u.nome as unidade,
           count(l.id) filter (where l.canal = 'whatsapp') as total,
           count(l.id) as cobertos,
           (u.id = v_minha) as sua
    from public.unidades u
    left join public.ligacoes l
      on l.unidade_id = u.id
     and l.resultado = 'whatsapp_enviado'
     and l.canal in ('whatsapp', 'sistema')
     and l.created_at >= v_inicio
    where public.is_admin() or u.id = v_minha
    group by u.id, u.nome
  ) x;
  return v_res;
end $function$;
