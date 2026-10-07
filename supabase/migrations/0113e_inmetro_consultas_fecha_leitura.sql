-- 0113e — INMETRO_CONSULTAS: FECHA A LEITURA (06/10)
--
-- Achado da análise de segurança pedida pelo Emerson: a tabela
-- `inmetro_consultas` (criada em 05/10 fora das migrations, pelo coletor de
-- consultas ao portal do Inmetro) estava SEM RLS e com todos os privilégios para
-- `anon`. Qualquer pessoa com a chave pública do app — que vai no JavaScript, por
-- design — podia ler, alterar e apagar as 1.835 linhas (placa, chassi, RENAVAM,
-- posto, data da aferição) sem login, em uma requisição.
--
-- O coletor grava direto na tabela pelo navegador (POST, sem sessão), então a
-- ESCRITA continua aberta para não quebrá-lo; a LEITURA e a EXCLUSÃO ficam só
-- para o admin geral logado. Se um dia o coletor fizer login, o certo é fechar
-- também a escrita (trocar `with check (true)` por `public.is_admin()`).
--
-- Testado como anon depois da migration: "permission denied for table".

alter table public.inmetro_consultas enable row level security;

revoke all on public.inmetro_consultas from public, anon, authenticated;
grant insert, update on public.inmetro_consultas to anon, authenticated;
grant select, delete on public.inmetro_consultas to authenticated;
grant all on public.inmetro_consultas to service_role;

create policy "inmetro: coletor insere"   on public.inmetro_consultas for insert to anon, authenticated with check (true);
create policy "inmetro: coletor atualiza" on public.inmetro_consultas for update to anon, authenticated using (true) with check (true);
create policy "inmetro: admin le"         on public.inmetro_consultas for select to authenticated using (public.is_admin());
create policy "inmetro: admin apaga"      on public.inmetro_consultas for delete to authenticated using (public.is_admin());

-- o coletor precisa da sequência para inserir
grant usage, select on sequence public.inmetro_consultas_id_seq to anon, authenticated;

-- duas funções de gatilho que ainda respondiam a anon na API (superfície, não vazamento)
revoke execute on function public.marca_telefone_invalido() from public, anon, authenticated;
revoke execute on function public.registra_situacao_empresa() from public, anon, authenticated;
