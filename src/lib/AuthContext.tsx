import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from './supabase'
import type { EquipeMembro, Unidade } from './database.types'

const LS_UNIDADE = 'lacre.unidadeAtiva'

interface AuthState {
  session: Session | null
  user: User | null
  membro: EquipeMembro | null
  loading: boolean
  // Unidades e a unidade "ativa" só fazem sentido para o admin, que fica acima das
  // unidades e escolhe qual quer visualizar. null = "Todas as unidades" (consolidado).
  unidades: Unidade[]
  unidadeAtiva: string | null
  setUnidadeAtiva: (id: string | null) => void
  signInWithPassword: (email: string, password: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthState | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [membro, setMembro] = useState<EquipeMembro | null>(null)
  const [loading, setLoading] = useState(true)
  const [unidades, setUnidades] = useState<Unidade[]>([])
  const [unidadeAtiva, setUnidadeAtivaState] = useState<string | null>(() => {
    try {
      return localStorage.getItem(LS_UNIDADE) || null
    } catch {
      return null
    }
  })

  function setUnidadeAtiva(id: string | null) {
    setUnidadeAtivaState(id)
    try {
      if (id) localStorage.setItem(LS_UNIDADE, id)
      else localStorage.removeItem(LS_UNIDADE)
    } catch {
      // ignora ambientes sem localStorage
    }
  }

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession)
    })

    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session?.user) {
      setMembro(null)
      return
    }
    supabase
      .from('equipe')
      .select('*')
      .eq('user_id', session.user.id)
      .maybeSingle()
      .then(({ data }) => setMembro(data as EquipeMembro | null))
  }, [session?.user])

  // Admin carrega a lista de unidades para alimentar o seletor.
  useEffect(() => {
    if (membro?.papel !== 'admin') {
      setUnidades([])
      return
    }
    supabase
      .from('unidades')
      .select('id, nome')
      .order('nome')
      .then(({ data }) => setUnidades((data as Unidade[]) ?? []))
  }, [membro?.papel])

  async function signInWithPassword(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error?.message ?? null }
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  return (
    <AuthContext.Provider
      value={{
        session,
        user: session?.user ?? null,
        membro,
        loading,
        unidades,
        unidadeAtiva,
        setUnidadeAtiva,
        signInWithPassword,
        signOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth deve ser usado dentro de <AuthProvider>')
  return ctx
}

// Helper: unidade pela qual o admin deve filtrar as telas operacionais.
// Para operador, retorna null (o RLS já limita à unidade dele).
export function useFiltroUnidade(): string | null {
  const { membro, unidadeAtiva } = useAuth()
  return membro?.papel === 'admin' ? unidadeAtiva : null
}
