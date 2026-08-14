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

// Busca todos os caminhoneiros paginando em blocos de 1000 (limite do PostgREST).
// Mantido para eventual exportação em CSV — as telas usam paginação/contagem no servidor.
export async function fetchAllCaminhoneiros() {
  const BLOCO = 1000
  let inicio = 0
  const todos: unknown[] = []
  for (;;) {
    const { data, error } = await supabase
      .from('caminhoneiros')
      .select('*')
      .order('created_at', { ascending: false })
      .range(inicio, inicio + BLOCO - 1)
    if (error) throw error
    const lote = data ?? []
    todos.push(...lote)
    if (lote.length < BLOCO) break
    inicio += BLOCO
  }
  return todos
}
