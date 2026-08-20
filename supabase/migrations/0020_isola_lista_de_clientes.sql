-- 0020_isola_lista_de_clientes.sql   [APLICADA em 19/08/2026]
-- CRITICA que so aparece no cenario de 800 clientes.
--
-- As politicas de `unidades` e `unidade_cidades` liberavam leitura para QUALQUER
-- membro ativo (`is_equipe_ativa()`). Com 3 unidades e inofensivo. Com 800 clientes
-- independentes, qualquer uma das ~1.600 operadoras poderia listar:
--   * `unidades`        -> a CARTEIRA DE CLIENTES inteira do Aferi+
--   * `unidade_cidades` -> o MAPA DE TERRITORIOS (quem tem qual praca, quais estao livres)
--
-- Um concorrente assinaria UMA unidade e levaria a lista de clientes e a estrategia
-- comercial. Nao vaza lead nenhum -- vaza algo pior.
--
-- Correcao: admin ve tudo; qualquer outro ve apenas a PROPRIA unidade.
-- Testado: a operadora continua vendo os leads dela (915) e passa a enxergar so a
-- propria unidade e os proprios territorios.
-- Nao quebra tela: `AuthContext` so carrega `unidades` para admin; a aba Cobertura
-- e restrita a admin; o placar vai por RPC (DEFINER) e nao depende desta politica.

drop policy if exists "unidades: equipe ativa lê" on public.unidades;
create policy "unidades: equipe ativa lê" on public.unidades
  for select using (public.is_admin() or id = public.unidade_do_usuario());

drop policy if exists "cobertura: equipe le" on public.unidade_cidades;
create policy "cobertura: equipe le" on public.unidade_cidades
  for select using (public.is_admin() or unidade_id = public.unidade_do_usuario());
