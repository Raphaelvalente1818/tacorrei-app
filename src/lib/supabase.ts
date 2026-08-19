import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types'

// Valores públicos do cliente Supabase (a chave é a "publishable", protegida por RLS —
// é a mesma que já é embarcada no bundle do navegador). O fallback embutido garante que
// o app funcione mesmo se as variáveis de ambiente não forem injetadas no build do deploy.
const url = (import.meta.env.VITE_SUPABASE_URL as string) || 'https://yjseipunenrmgkirafyp.supabase.co'
const key =
  (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string) ||
  'sb_publishable_RA_SyprzO9g7FmewoBFiDQ_NnKmZHdg'

export const supabase = createClient<Database>(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
})

// REMOVIDO (19/08/2026 — auditoria de segurança): `fetchAllCaminhoneiros()`.
// Era um laço que puxava a base inteira de 1.000 em 1.000 registros. Nenhuma tela
// usava, mas ia no pacote JavaScript entregue ao cliente — ou seja, uma ferramenta
// de extração em massa publicada junto com o produto. Se algum dia for preciso ler
// muitos registros, que seja por RPC no servidor, com teto de página e registro de
// acesso. NÃO reintroduzir leitura em massa no navegador.
