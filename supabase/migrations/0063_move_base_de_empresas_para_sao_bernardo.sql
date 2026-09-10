-- [aplicada no banco em 09/09/2026 21:04 — versão 20260909210451]
-- ── 0063 — as 635 empresas voltam para São Bernardo ─────────────────────────
--
-- O que aconteceu: a tela envia a unidade só quando o admin escolheu uma no
-- filtro. Com "Todas as unidades" ela manda null, e a função caía no fallback
-- `unidade_do_usuario()`. O Emerson é admin lotado em Santo André — então
-- 6.128 caminhões de São Bernardo e Diadema entraram em Santo André, sem aviso.
--
-- 24 dessas placas JÁ EXISTIAM em São Bernardo como lead solto. Essas não são
-- movidas: o lead antigo é que recebe o vínculo com a empresa, porque é ele que
-- carrega o histórico. A linha nova é apagada. Nenhuma das 24 tinha mensagem
-- enviada, então nada de conversa se perde.

-- 1) Guarda quem é quem antes de mexer
create temporary table _mover on commit drop as
with sa as (select id from unidades where nome='Santo André'),
     sb as (select id from unidades where nome='Tacorrei São Bernardo')
select c.id as novo_id,
       upper(regexp_replace(coalesce(c.placa_veiculo,''),'[^A-Z0-9]','','g')) as pl,
       c.empresa_id, c.data_ultima_afericao, c.posto_afericao, c.numero_empresa,
       c.observacoes, c.tem_tacografo, c.nome, c.modelo_veiculo,
       (select a.id from caminhoneiros a, sb
         where a.unidade_id = sb.id
           and upper(regexp_replace(coalesce(a.placa_veiculo,''),'[^A-Z0-9]','','g'))
             = upper(regexp_replace(coalesce(c.placa_veiculo,''),'[^A-Z0-9]','','g'))
         limit 1) as antigo_id
from caminhoneiros c join empresas e on e.id = c.empresa_id, sa
where e.situacao = 'prospecto' and c.unidade_id = sa.id;

-- 2) As 24 que colidem: o lead ANTIGO herda a empresa e o que a base nova sabe
update public.caminhoneiros a
   set empresa_id = m.empresa_id,
       numero_empresa = coalesce(a.numero_empresa, m.numero_empresa),
       modelo_veiculo = coalesce(a.modelo_veiculo, m.modelo_veiculo),
       observacoes = coalesce(a.observacoes, m.observacoes),
       -- posto e data só avançam se a base nova for mais recente. É essa
       -- passagem que o gatilho de fuga lê.
       data_ultima_afericao = case
         when m.data_ultima_afericao is not null
          and (a.data_ultima_afericao is null or m.data_ultima_afericao > a.data_ultima_afericao)
         then m.data_ultima_afericao else a.data_ultima_afericao end,
       posto_afericao = case
         when m.posto_afericao is not null
          and (a.data_ultima_afericao is null or m.data_ultima_afericao > a.data_ultima_afericao)
         then m.posto_afericao else a.posto_afericao end,
       tem_tacografo = a.tem_tacografo or m.tem_tacografo,
       updated_at = now()
  from _mover m
 where a.id = m.antigo_id and m.antigo_id is not null;

delete from public.caminhoneiros c
 using _mover m
 where c.id = m.novo_id and m.antigo_id is not null;

-- 3) O resto muda de unidade, junto com as empresas
update public.empresas
   set unidade_id = (select id from unidades where nome='Tacorrei São Bernardo'),
       updated_at = now()
 where situacao = 'prospecto'
   and unidade_id = (select id from unidades where nome='Santo André');

update public.caminhoneiros c
   set unidade_id = e.unidade_id, updated_at = now()
  from public.empresas e
 where e.id = c.empresa_id and c.unidade_id <> e.unidade_id;
