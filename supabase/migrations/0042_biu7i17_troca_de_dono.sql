-- [aplicada no banco em 08/09/2026 17:34 — versão 20260908173451]
-- ── 0042 — BIU7I17 mudou de dono ────────────────────────────────────────────
-- A linha antiga trazia ROTA MOURA com telefone de DDD 81 (Pernambuco); a
-- importação de agosto trouxe RODOVEL, sem telefone. Decisão do Raphael: o
-- caminhão trocou de dono e o telefone do dono novo ainda não existe. Fica o
-- nome certo e o telefone em branco — melhor vazio, que a moça preenche quando
-- souber, do que um número que leva a mensagem para o dono anterior, em outro
-- estado.
--
-- Vazio é '' e não NULL porque a coluna é NOT NULL; é a mesma convenção dos
-- outros ~1.000 leads sem telefone. A normalização devolve nulo de qualquer
-- forma, então o lead não recebe WhatsApp — que é o comportamento desejado.
update public.caminhoneiros c
set nome = b.nome,
    telefone = '',
    telefone_e164 = null,
    observacoes = nullif(trim(concat_ws(' · ',
      nullif(trim(coalesce(c.observacoes,'')), ''),
      'Trocou de dono; telefone do novo proprietário a levantar.')), ''),
    updated_at = now()
from public._backup_dup_0041 b
where upper(regexp_replace(coalesce(c.placa_veiculo,''),'[^A-Z0-9]','','g')) = 'BIU7I17'
  and upper(regexp_replace(coalesce(b.placa_veiculo,''),'[^A-Z0-9]','','g')) = 'BIU7I17'
  and b.nome ilike 'RODOVEL%';
