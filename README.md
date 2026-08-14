# App Tacógrafo — Painel de ligações

Painel interno para gerenciar ligações e atrair caminhoneiros para a aferição do tacógrafo.

Stack: React 18 + TypeScript + Vite + Tailwind CSS v4, Supabase (Auth + Postgres + RLS), deploy sugerido na Vercel. Identidade visual reaproveitada do projeto RODE COM LUCRO (cores, tipografia e componentes).

## Rodando localmente

```bash
npm install
cp .env.example .env   # já vem preenchido com o projeto Supabase "tacorrei-app"
npm run dev
```

## Criando seu usuário de acesso

O painel usa Supabase Auth (e-mail/senha). Depois de criar o usuário no Supabase (Authentication → Users → Add user), adicione uma linha na tabela `equipe` ligando o `user_id` ao seu nome e papel:

```sql
insert into equipe (user_id, nome, papel)
values ('<uuid-do-usuario>', 'Seu Nome', 'admin');
```

Sem essa linha o login funciona, mas o RLS bloqueia leitura/escrita de leads, ligações e agendamentos (por segurança).

## Estrutura

- `src/pages/Dashboard.tsx` — funil de conversão e métricas
- `src/pages/Leads.tsx` / `LeadDetail.tsx` — lista de leads, histórico de ligações, registro de contato
- `src/pages/Agenda.tsx` — todos os agendamentos de aferição
- `supabase/migrations/0001_init.sql` — schema (caminhoneiros, ligacoes, agendamentos, equipe) com RLS

## Deploy

Projeto ainda não está conectado a um projeto Vercel. Para publicar:

```bash
vercel link
vercel env add VITE_SUPABASE_URL
vercel env add VITE_SUPABASE_PUBLISHABLE_KEY
vercel deploy --prod
```

## Próximos passos sugeridos

- Cadastro de usuários da equipe direto pelo painel (hoje é manual via SQL)
- Importação em massa de leads (CSV)
- Integração com WhatsApp/discador (como no RODE COM LUCRO)
- Notificação automática de agendamentos próximos
