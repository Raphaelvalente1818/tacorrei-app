// Edge Function: exclui definitivamente um acesso (login + linha na equipe).
// Só admin pode chamar. O histórico (ligacoes/agendamentos) tem ON DELETE SET NULL,
// então é preservado — fica apenas sem dono.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const authHeader = req.headers.get('Authorization') ?? ''

    // Valida que o chamador é admin (usa o JWT dele).
    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } })
    const { data: isAdmin, error: adminErr } = await caller.rpc('is_admin')
    if (adminErr || !isAdmin) {
      return json({ error: 'Acesso restrito a administradores.' }, 403)
    }

    const { user_id } = await req.json()
    if (!user_id) return json({ error: 'user_id é obrigatório.' }, 400)

    const admin = createClient(url, service)

    // 1) Remove a pessoa da equipe (histórico aponta com ON DELETE SET NULL).
    const { error: delEquipe } = await admin.from('equipe').delete().eq('user_id', user_id)
    if (delEquipe) return json({ error: delEquipe.message }, 400)

    // 2) Apaga o login (auth).
    const { error: delUser } = await admin.auth.admin.deleteUser(user_id)
    if (delUser) return json({ error: delUser.message }, 400)

    return json({ ok: true })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
