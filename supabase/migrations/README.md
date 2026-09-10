# Migrations — como ler esta pasta

O banco de verdade é o Supabase (`yjseipunenrmgkirafyp`). Toda migration é aplicada lá
primeiro, pelo Claude via `apply_migration`, e o arquivo aqui é o **registro** do que foi
aplicado — com o comentário que explica a decisão, que é a parte que mais vale.

## Numeração

- **0001–0022**: escritas à mão em agosto; a numeração é a original.
- **0023–0064**: reconstituídas em 10/09/2026 a partir do histórico do próprio Supabase
  (`supabase_migrations.schema_migrations`). Cada arquivo traz no topo a data/hora em que
  foi aplicado e a versão de 14 dígitos que o Supabase usa.
- As migrations de 24/08 e 28/08 foram aplicadas **sem número**; ganharam 0025–0039 na
  ordem cronológica. Como eram 17 para 15 vagas, as duas últimas de 28/08 ficaram como
  **0039a** e **0039b** — mesma convenção que o banco já usa para a **0065b**.
- **0065b** não tem arquivo: era só a correção do corpo da função da 0065, e a 0065 daqui
  já está corrigida.
- **0070** e **0072** são só de dados (desfazer um teste, encerrar a unidade fictícia).

## ⚠️ Arquivos com dados de cliente omitidos

`0045`, `0047`, `0051`, `0052`, `0057`, `0059` carregaram as frotas com contrato (DIASTUR,
BERNATRANS, Auto Viação ABC, Logitectrans — 954 veículos). **As linhas de placas foram
retiradas destes arquivos**: frota de cliente não vai para o git. O comando fica pela
estrutura (a coluna `numero_empresa`, o índice único de placa) e pelo comentário que
registra a decisão. Esses seis arquivos **não podem ser reaplicados como estão**.

Pelo mesmo motivo, nunca exportar dados do banco para dentro deste repositório.

## Regras que valem para toda migration nova

1. **Ao mudar a assinatura de uma função, `drop function` da antiga.** `create or replace`
   com assinatura nova cria uma SEGUNDA função (aconteceu na 0044 e de novo na 0066).
2. **Função nova nasce com EXECUTE para PUBLIC.** Repor `revoke … from public, anon` e
   `grant … to authenticated, service_role`.
3. **Conferir as check constraints das tabelas que a função escreve** — a 0065 chamou
   `registrar_acesso('contato_empresa')` e `acessos_lead` só aceita `listar|abrir|placa`.
4. **Testar escrita sem sujar a base**: bloco `do $$ … raise exception 'ROLLBACK PROPOSITAL' $$`
   dentro da migration — o insert roda e a transação volta.
5. **Validade do certificado = 2 anos**, em toda conta de vencimento.
