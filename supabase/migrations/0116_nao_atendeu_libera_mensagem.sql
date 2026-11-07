-- 0116 — "NÃO ATENDEU" LIBERA A MENSAGEM DE WHATSAPP (07/11)
--
-- A Fernanda: "quase ninguém atende o celular". O banco confirma: ligação atendida
-- converteu 0 em 31 até setembro; as aferições atribuíveis vieram todas de
-- mensagem. E "não atendeu" foi registrado 16 vezes em dois meses (15 em SBC, 1 em
-- SA) — como não serve para nada, ninguém registra. Enquanto isso, em Santo André
-- "autorizou" virou o botão que se aperta para liberar o WhatsApp (215 em dois
-- meses, 241 de 243 ligações "atendidas"). Uma trava que só o honesto respeita
-- não é trava, é imposto sobre a honestidade.
--
-- Decisão do Emerson: quando a ligação não for atendida, a mensagem fica liberada
-- de qualquer forma, mantendo a cota por dia e o intervalo entre envios.
--
-- Regra: a trava RELAÇÃO do envio passa a aceitar cliente da casa OU autorizou OU
-- uma ligação ativa registrada como "não atendeu" nos últimos
-- `unidades.tentativa_ligacao_dias` (30) dias — para o caminhão, ou, numa frota,
-- para a empresa ou qualquer caminhão dela (o telefone da frota é a mesma pessoa).
-- As outras travas não mudam: contrato, faixa, uma por lead por ciclo, uma por
-- empresa e por telefone em 30 dias, cota do dia, ritmo, "não é mais o dono".
-- A tentativa de ligação continua obrigatória, de propósito: custa dez segundos e
-- deixa verdadeiro o texto da mensagem ("tentei falar com você por telefone").
-- `obter_lead` devolve `tentou_ligar_em` para a ficha mostrar o selo e montar o
-- texto certo. Pontuação não muda: a mensagem continua sendo o contato que atribui.

alter table public.unidades
  add column if not exists tentativa_ligacao_dias integer not null default 30;

-- Quando foi a última ligação não atendida que vale para este caminhão (ou null).
create or replace function public.tentativa_de_ligacao(p_lead uuid)
returns timestamptz
language sql stable security definer
set search_path = public, pg_temp
as $$
  select max(l.created_at)
  from public.caminhoneiros c
  join public.unidades u on u.id = c.unidade_id
  join public.ligacoes l
    on l.canal = 'ligacao_ativa' and l.resultado = 'nao_atendeu'
   and l.created_at > now() - make_interval(days => coalesce(u.tentativa_ligacao_dias, 30))
   and (l.caminhoneiro_id = c.id
        or (c.empresa_id is not null
            and (l.empresa_id = c.empresa_id
                 or l.caminhoneiro_id in (select x.id from public.caminhoneiros x where x.empresa_id = c.empresa_id))))
  where c.id = p_lead
$$;
revoke all on function public.tentativa_de_ligacao(uuid) from public, anon;
grant execute on function public.tentativa_de_ligacao(uuid) to authenticated, service_role;

-- 1) o envio: a trava RELAÇÃO aceita a tentativa de ligação
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.registrar_envio_whatsapp(uuid, text, uuid[])'::regprocedure);
  if position($a$if not exists (select 1 from public.caminhoneiros x where x.empresa_id = v_emp$a$ in v_def) = 0
     or position($a$raise exception 'nenhum caminhao da % aferiu conosco: ligue primeiro e marque "autorizou receber mensagem"', v_emp_nome;$a$ in v_def) = 0
     or position($a$elsif not (public.posto_do_grupo(v_posto, v_unidade) or coalesce(v_autorizou,false)) then$a$ in v_def) = 0
     or position($a$raise exception 'este lead e cliente de concorrente: ligue primeiro e marque "autorizou receber mensagem"';$a$ in v_def) = 0 then
    raise exception '0116: ancoras de registrar_envio_whatsapp nao encontradas';
  end if;
  v_def := replace(v_def,
    $a$if not exists (select 1 from public.caminhoneiros x where x.empresa_id = v_emp$a$,
    $a$if public.tentativa_de_ligacao(p_lead) is null and not exists (select 1 from public.caminhoneiros x where x.empresa_id = v_emp$a$);
  v_def := replace(v_def,
    $a$raise exception 'nenhum caminhao da % aferiu conosco: ligue primeiro e marque "autorizou receber mensagem"', v_emp_nome;$a$,
    $a$raise exception 'nenhum caminhao da % aferiu conosco: ligue primeiro — "autorizou mensagem" ou "nao atendeu" liberam o WhatsApp', v_emp_nome;$a$);
  v_def := replace(v_def,
    $a$elsif not (public.posto_do_grupo(v_posto, v_unidade) or coalesce(v_autorizou,false)) then$a$,
    $a$elsif not (public.posto_do_grupo(v_posto, v_unidade) or coalesce(v_autorizou,false) or public.tentativa_de_ligacao(p_lead) is not null) then$a$);
  v_def := replace(v_def,
    $a$raise exception 'este lead e cliente de concorrente: ligue primeiro e marque "autorizou receber mensagem"';$a$,
    $a$raise exception 'este lead e cliente de concorrente: ligue primeiro — "autorizou mensagem" ou "nao atendeu" liberam o WhatsApp';$a$);
  execute v_def;
end $$;

-- 2) a ficha fica sabendo
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.obter_lead(uuid)'::regprocedure);
  if position($a$'cadastro', public.cadastro_do_lead(c.id),$a$ in v_def) = 0 then
    raise exception '0116: ancora de obter_lead nao encontrada';
  end if;
  v_def := replace(v_def,
    $a$'cadastro', public.cadastro_do_lead(c.id),$a$,
    $a$'cadastro', public.cadastro_do_lead(c.id),
    'tentou_ligar_em', public.tentativa_de_ligacao(c.id),$a$);
  execute v_def;
end $$;
