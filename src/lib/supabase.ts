import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types'

// Valores públicos do cliente Supabase (a chave é a "publishable", protegida por RLS —
// é a mesma que já é embarcada no bundle do navegador). O fallback embutido garante que
// o app funcione mesmo se as variáveis de ambiente não forem injetadas no build do deploy.
const url = (import.meta.env.VITE_SUPABASE_URL as string) || 'https://yjseipunenrmgkirafyp.supabase.co'
const key =
  (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string) ||
  'sb_publishable_RA_SyprzO9g7FmewoBFiDQ_NnKmZHdg'

// 15/09 — "JWT expired" na tela da Fernanda, em São Bernardo, no meio de um Salvar lead.
//
// O crachá do login vale 1 hora e o supabase-js renova sozinho — mas só enquanto a aba
// está acordada. Computador que dormiu, tela bloqueada no almoço, aba horas em segundo
// plano: o relógio da renovação não roda, e o PRIMEIRO pedido depois disso sai com o
// crachá vencido. O servidor responde 401 "JWT expired" e a tela mostrava isso cru.
//
// A correção mora aqui, num lugar só, porque tudo que o app fala com o servidor passa
// por este fetch: ao ver um 401 de crachá vencido, renova a sessão UMA vez (mesmo que
// várias chamadas falhem juntas) e repete o pedido com o crachá novo. Se a renovação
// também falhar (dias sem abrir o app — o refresh token também venceu), o supabase-js
// dispara SIGNED_OUT e o AuthContext manda para o login, como sempre fez.
//
// Não mexe em chamadas do próprio /auth/ (senão a renovação tentaria se renovar).
let renovando: Promise<void> | null = null

async function fetchComRenovacao(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const res = await fetch(input, init)
  if (res.status !== 401) return res

  const alvo =
    typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
  if (alvo.includes('/auth/v1/')) return res

  let corpo = ''
  try {
    corpo = await res.clone().text()
  } catch {
    return res
  }
  if (!/jwt expired|token is expired|invalid jwt/i.test(corpo)) return res

  if (!renovando) {
    renovando = supabase.auth
      .refreshSession()
      .then(() => undefined)
      .finally(() => {
        renovando = null
      })
  }
  await renovando

  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  if (!token) return res

  const headers = new Headers(init?.headers)
  headers.set('Authorization', `Bearer ${token}`)
  return fetch(input, { ...init, headers })
}

export const supabase = createClient<Database>(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
  global: {
    fetch: fetchComRenovacao,
  },
})

// REMOVIDO (19/08/2026 — auditoria de segurança): `fetchAllCaminhoneiros()`.
// Era um laço que puxava a base inteira de 1.000 em 1.000 registros. Nenhuma tela
// usava, mas ia no pacote JavaScript entregue ao cliente — ou seja, uma ferramenta
// de extração em massa publicada junto com o produto. Se algum dia for preciso ler
// muitos registros, que seja por RPC no servidor, com teto de página e registro de
// acesso. NÃO reintroduzir leitura em massa no navegador.
