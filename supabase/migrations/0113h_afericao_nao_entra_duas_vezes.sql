-- 0113h — A MESMA AFERIÇÃO NÃO ENTRA DUAS VEZES (28/10)
--
-- Achado ao investigar "registrei a conquista e nada mudou" (Fernanda, SBC): o
-- Meu dia estava parado numa aba antiga (resolvido no front), mas a varredura
-- mostrou outra coisa — 35 caminhões com o Aferido registrado 2 a 9 vezes para a
-- MESMA data desde setembro (GDU3F58 nove vezes em 55 minutos; MEZ3D84 sete vezes
-- em dois dias). Cada clique criava uma ligação 'aferido' e um ponto: a primeira
-- com a classe certa, as seguintes como "renovação" (o posto já era o nosso).
-- Em outubro: 62 linhas a mais, 112 pontos a mais (87 em SA, 25 em SBC), a maior
-- parte "veio sozinho" (não paga), mas 26 atribuídos a operadora.
--
-- Agora `registrar_afericao` e `registrar_afericao_frota` recusam quando já existe
-- aferição registrada para o mesmo caminhão com data a até 30 dias da informada
-- (o certificado vale 2 anos; duas aferições em um mês não existem). A recusa diz
-- a data e quem registrou. Quem precisar corrigir usa "Desfazer aferição" (0088).
-- As linhas duplicadas já gravadas NÃO são apagadas aqui — decisão do Emerson.

do $$
declare v_def text;
begin
  -- 1) ficha: registrar_afericao(uuid, date, text, boolean)
  v_def := pg_get_functiondef('public.registrar_afericao(uuid, date, text, boolean)'::regprocedure);
  if position('  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  if p_marcar_aferido then' in v_def) = 0 then
    raise exception '0113h: ancora de registrar_afericao nao encontrada';
  end if;
  v_def := replace(v_def,
'  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  if p_marcar_aferido then',
'  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  -- 0113h: a mesma aferição não entra duas vezes
  if p_marcar_aferido and p_data is not null then
    declare v_dup record;
    begin
      select p.data_afericao, e.nome, l.created_at into v_dup
        from public.ligacoes l
        join public.pontos p on p.ligacao_id = l.id
        left join public.equipe e on e.user_id = l.operador_id
       where l.caminhoneiro_id = p_lead and l.resultado = ''aferido''
         and abs(p.data_afericao - p_data) <= 30
       order by l.created_at desc limit 1;
      if found then
        raise exception ''esta aferição já está registrada: % por % (em %). Não registre de novo — se estiver errada, use "Desfazer aferição".'',
          to_char(v_dup.data_afericao, ''DD/MM/YYYY''), coalesce(v_dup.nome, ''alguém da equipe''),
          to_char(v_dup.created_at at time zone ''America/Sao_Paulo'', ''DD/MM HH24:MI'');
      end if;
    end;
  end if;

  if p_marcar_aferido then');
  execute v_def;

  -- 2) frota: registrar_afericao_frota(uuid, date, text)
  v_def := pg_get_functiondef('public.registrar_afericao_frota(uuid, date, text)'::regprocedure);
  if position('  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  update public.caminhoneiros' in v_def) = 0 then
    raise exception '0113h: ancora de registrar_afericao_frota nao encontrada';
  end if;
  v_def := replace(v_def,
'  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  update public.caminhoneiros',
'  select u.posto_afericao into v_posto_unidade from public.unidades u where u.id = v_unidade;

  -- 0113h: a mesma aferição não entra duas vezes
  declare v_dup record;
  begin
    select p.data_afericao, e.nome, l.created_at into v_dup
      from public.ligacoes l
      join public.pontos p on p.ligacao_id = l.id
      left join public.equipe e on e.user_id = l.operador_id
     where l.caminhoneiro_id = p_lead and l.resultado = ''aferido''
       and abs(p.data_afericao - v_data) <= 30
     order by l.created_at desc limit 1;
    if found then
      raise exception ''a placa % já tem aferição registrada: % por % (em %). Não registre de novo — se estiver errada, use "Desfazer aferição".'',
        v_placa, to_char(v_dup.data_afericao, ''DD/MM/YYYY''), coalesce(v_dup.nome, ''alguém da equipe''),
        to_char(v_dup.created_at at time zone ''America/Sao_Paulo'', ''DD/MM HH24:MI'');
    end if;
  end;

  update public.caminhoneiros');
  execute v_def;
end $$;
