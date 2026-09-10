-- [aplicada no banco em 24/08/2026 19:55 — versão 20260824195504]
-- Três travas pedidas em 24/08, todas no servidor (a tela apenas reflete o que o
-- banco já impede — assim a regra não depende de ninguém lembrar dela).
--
-- 1. PISO DE 12 MESES: quem venceu há mais de um ano sai da fila. Um certificado
--    vencido há 5 ou 12 anos quase sempre é caminhão vendido, sucateado ou sem
--    tacógrafo. Mensagem para esse público é a que mais gera denúncia e a que menos
--    converte — e denúncia é o que de fato derruba um número de WhatsApp.
-- 2. UMA MENSAGEM POR LEAD: insistência é a causa raiz de bloqueio. O contador
--    zera quando o lead afere, então a recompra de 2 anos continua funcionando.
-- 3. COTA DE 50/DIA POR UNIDADE: o risco é do NÚMERO de WhatsApp, e cada unidade
--    tem um só. Em São Bernardo as duas operadoras dividem a mesma cota.
alter table public.unidades
  add column if not exists piso_dias integer not null default 365,
  add column if not exists limite_whatsapp_dia integer not null default 50;

alter table public.unidades drop constraint if exists unidades_piso_dias_check;
alter table public.unidades add constraint unidades_piso_dias_check
  check (piso_dias between 30 and 7300);

alter table public.unidades drop constraint if exists unidades_limite_whatsapp_check;
alter table public.unidades add constraint unidades_limite_whatsapp_check
  check (limite_whatsapp_dia between 1 and 1000);

-- espelha janela_do_usuario()
create or replace function public.piso_do_usuario()
returns integer language sql stable security definer set search_path = public, pg_temp
as $$
  select u.piso_dias from public.unidades u
  where u.id = public.unidade_do_usuario()
$$;

-- A JANELA VIRA FAIXA. Antes era só um teto ("vence nos próximos N dias"); agora
-- tem chão também. Continua sendo a regra ÚNICA de visibilidade — usada ao mesmo
-- tempo pela política de RLS e pelas RPCs, para não haver como divergir.
create or replace function public.pode_ler_lead(
  p_unidade_id uuid, p_tem_tacografo boolean, p_data_afericao date
) returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select public.is_equipe_ativa() and (
    public.is_admin()
    or (public.is_admin_unidade() and p_unidade_id = public.unidade_do_usuario())
    or ( p_unidade_id = public.unidade_do_usuario()
      and p_tem_tacografo = true
      and ( public.janela_do_usuario() is null
        or (p_data_afericao is not null
            -- teto: já venceu ou vence dentro da janela
            and (p_data_afericao + interval '2 years')::date
                <= current_date + public.janela_do_usuario()
            -- chão: não venceu há mais tempo que o piso
            and (p_data_afericao + interval '2 years')::date
                >= current_date - coalesce(public.piso_do_usuario(), 365))))
  );
$$;

-- Quanto ainda dá para enviar hoje, na unidade de quem está logado.
create or replace function public.cota_whatsapp_hoje()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $function$
declare v_unidade uuid; v_limite integer; v_usadas integer;
begin
  if not public.is_equipe_ativa() then
    raise exception 'acesso negado';
  end if;

  v_unidade := public.unidade_do_usuario();
  if v_unidade is null then
    return jsonb_build_object('limite', null, 'usadas', 0, 'restantes', null);
  end if;

  select limite_whatsapp_dia into v_limite from public.unidades where id = v_unidade;

  select count(*) into v_usadas
  from public.ligacoes l
  where l.unidade_id = v_unidade
    and l.canal = 'whatsapp'
    and (l.created_at at time zone 'America/Sao_Paulo')::date
        = (now() at time zone 'America/Sao_Paulo')::date;

  return jsonb_build_object(
    'limite', v_limite, 'usadas', v_usadas,
    'restantes', greatest(v_limite - v_usadas, 0));
end $function$;

revoke execute on function public.piso_do_usuario() from public;
grant execute on function public.piso_do_usuario() to authenticated;
revoke execute on function public.cota_whatsapp_hoje() from public;
grant execute on function public.cota_whatsapp_hoje() to authenticated;
