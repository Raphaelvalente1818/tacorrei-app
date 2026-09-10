-- [aplicada no banco em 08/09/2026 17:32 — versão 20260908173217]
-- ── 0041 — funde as 14 placas duplicadas de São Bernardo ────────────────────
--
-- Não eram duplicatas de cadastro. São o MESMO caminhão em dois momentos:
--   • linha de 18–19/08 → o lead vindo do RNTRC (tem RNTRC, telefone formatado,
--     histórico de ligação e mensagem, aferição antiga);
--   • linha de 27–28/08 → o registro de que ele AFERIU na Tacorrei em agosto
--     (sem RNTRC, telefone cru, aferição de agosto/2026).
--
-- Apagar qualquer uma das duas perde metade da história. Pior: em 5 casos a
-- linha nova é uma CONVERSÃO — o caminhão recebeu mensagem e voltou —, e como
-- ela caiu numa linha separada, a conversão nunca chegou ao painel.
--
-- A linha antiga sobrevive (é ela que tem o histórico) e recebe da nova o que
-- só a nova sabe: a aferição de agosto e o posto.

-- 1) Rede de segurança — as 28 linhas ficam guardadas -----------------------
drop table if exists public._backup_dup_0041;
create table public._backup_dup_0041 as
with d as (
  select unidade_id, upper(regexp_replace(coalesce(placa_veiculo,''),'[^A-Z0-9]','','g')) p
  from public.caminhoneiros
  where empresa_id is null and placa_veiculo is not null
  group by 1,2 having count(*) > 1
)
select c.*, now() as salvo_em
from public.caminhoneiros c
join d on d.unidade_id = c.unidade_id
      and d.p = upper(regexp_replace(coalesce(c.placa_veiculo,''),'[^A-Z0-9]','','g'))
where c.empresa_id is null;

alter table public._backup_dup_0041 enable row level security;
comment on table public._backup_dup_0041 is
  'Cópia das 28 linhas antes da fusão da migration 0041. Sem policy: só service_role lê.';

-- 2) Os pares, com quem fica e quem sai -------------------------------------
create temporary table pares on commit drop as
with d as (
  select unidade_id, upper(regexp_replace(coalesce(placa_veiculo,''),'[^A-Z0-9]','','g')) p
  from public.caminhoneiros
  where empresa_id is null and placa_veiculo is not null
  group by 1,2 having count(*) > 1
),
linhas as (
  select c.*, upper(regexp_replace(coalesce(c.placa_veiculo,''),'[^A-Z0-9]','','g')) as pl
  from public.caminhoneiros c
  join d on d.unidade_id = c.unidade_id
        and d.p = upper(regexp_replace(coalesce(c.placa_veiculo,''),'[^A-Z0-9]','','g'))
  where c.empresa_id is null
),
ord as (
  select *, row_number() over (partition by unidade_id, pl order by created_at) as rn,
            count(*)  over (partition by unidade_id, pl) as n
  from linhas
)
select a.pl as placa, a.unidade_id,
       a.id as id_fica, b.id as id_sai,
       a.data_ultima_afericao as af_a, b.data_ultima_afericao as af_b,
       a.posto_afericao as posto_a, b.posto_afericao as posto_b,
       a.telefone as fone_a, b.telefone as fone_b,
       a.nome as nome_a, b.nome as nome_b,
       a.renavam as renavam_a, b.renavam as renavam_b,
       a.observacoes as obs_a, b.observacoes as obs_b,
       a.data_ultimo_whatsapp as msg_em
from ord a
join ord b on b.unidade_id = a.unidade_id and b.pl = a.pl and b.rn = 2
where a.rn = 1 and a.n = 2;

-- 3) A fusão ----------------------------------------------------------------
-- Aferição e posto vêm da linha com a data MAIS RECENTE; empatou, vem da nova,
-- porque a nova é o registro do serviço prestado, não a foto do RNTRC.
--
-- Nome só muda nos 3 casos que eu conferi um a um, em que o caminhão trocou de
-- dono (mesmo RENAVAM, titular diferente). Nos demais fica o nome antigo — a
-- linha nova traz erro de digitação em pelo menos um caso ("CLEBER FRNANDO").
--
-- Telefone da linha nova só entra quando o antigo não presta. É por isso que o
-- telefone "11" é descartado: são dois caracteres, o DDD sozinho, sem número.
update public.caminhoneiros c
set data_ultima_afericao = greatest(p.af_a, p.af_b),
    posto_afericao = case when coalesce(p.af_b, '1900-01-01') >= coalesce(p.af_a, '1900-01-01')
                          then p.posto_b else p.posto_a end,
    nome     = case when p.placa in ('DVT7360','FZR4C14','DXV5C61') then p.nome_b else p.nome_a end,
    telefone = case
                 when p.placa in ('DVT7360','FZR4C14','DXV5C61') then p.fone_b
                 when public.normaliza_fone(p.fone_a) is null
                  and public.normaliza_fone(p.fone_b) is not null then p.fone_b
                 else p.fone_a
               end,
    renavam  = case when length(coalesce(p.renavam_b,'')) > length(coalesce(p.renavam_a,''))
                    then p.renavam_b else p.renavam_a end,
    observacoes = nullif(concat_ws(' · ', nullif(trim(coalesce(p.obs_a,'')),''),
                                          nullif(trim(coalesce(p.obs_b,'')),'')), ''),
    updated_at = now()
from pares p
where c.id = p.id_fica;

-- 4) As conversões ----------------------------------------------------------
-- Recebeu mensagem, e DEPOIS aferiu na Tacorrei. O painel conta aferido por
-- `status`, então sem isto a conversão não existe para o sistema.
update public.caminhoneiros c
set status = 'aferido', updated_at = now()
from pares p
where c.id = p.id_fica
  and p.msg_em is not null
  and p.af_b > (p.msg_em at time zone 'America/Sao_Paulo')::date - 1
  and public.posto_do_grupo(p.posto_b);

insert into public.ligacoes (caminhoneiro_id, unidade_id, canal, resultado, notas, created_at)
select p.id_fica, p.unidade_id, 'sistema', 'aferido',
       'Aferição de ' || to_char(p.af_b,'DD/MM/YYYY') ||
       ' reconciliada pela migration 0041 (estava numa linha separada).',
       p.af_b::timestamptz
from pares p
where p.msg_em is not null
  and p.af_b > (p.msg_em at time zone 'America/Sao_Paulo')::date - 1
  and public.posto_do_grupo(p.posto_b);

-- 5) Fora a linha repetida ---------------------------------------------------
delete from public.ligacoes l using pares p where l.caminhoneiro_id = p.id_sai;
delete from public.caminhoneiros c using pares p where c.id = p.id_sai;

-- 6) Trava para não voltar a acontecer --------------------------------------
-- Se a mesma placa for cadastrada de novo na mesma unidade, o banco recusa.
create unique index if not exists uq_caminhoneiros_placa_unidade
  on public.caminhoneiros (unidade_id, upper(regexp_replace(coalesce(placa_veiculo,''),'[^A-Z0-9]','','g')))
  where placa_veiculo is not null and empresa_id is null;
