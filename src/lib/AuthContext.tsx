import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from './supabase'
import type { ConfigMensagem, EquipeMembro, Unidade } from './database.types'

const LS_UNIDADE = 'lacre.unidadeAtiva'

interface AuthState {
  session: Session | null
  user: User | null
  membro: EquipeMembro | null
  loading: boolean
  // Unidades e a unidade "ativa" só fazem sentido para o admin, que fica acima das
  // unidades e escolhe qual quer visualizar. null = "Todas as unidades" (consolidado).
  unidades: Unidade[]
  // Depois de salvar marca/mensagens na aba Unidade, recarrega sem relogar.
  recarregarUnidades: () => Promise<void>
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

  // Todo mundo carrega as unidades que enxerga: o admin, todas (alimenta o seletor
  // "Visualizando"); operadora e gestor, só a própria — a RLS já corta. Junto vêm
  // marca, endereço e os textos das mensagens (0085), que antes eram um mapa fixo
  // no código: unidade nova = cadastro, não deploy.
  const recarregarUnidades = useCallback(async () => {
    if (!membro) {
      setUnidades([])
      return
    }
    const { data } = await supabase
      .from('unidades')
      .select('id, nome, marca, endereco, telefone, msg_credencial, msg_convite_vencido, msg_convite_a_vencer, msg_aviso_contrato')
      .order('nome')
    setUnidades((data as Unidade[]) ?? [])
  }, [membro])

  useEffect(() => {
    recarregarUnidades()
  }, [recarregarUnidades])

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
        recarregarUnidades,
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
  if (membro?.papel === 'admin') return unidadeAtiva
  // Admin de unidade: fixo na unidade dele. A RLS já garante isso no banco;
  // aqui é só para as telas não pedirem dado que viria vazio.
  if (membro?.papel === 'admin_unidade') return membro.unidade_id
  return null
}

// Os textos aprovados em 24/08 (quatro blocos). Ficam aqui como padrão: a unidade
// que não mexeu em nada manda exatamente isto. A porta de saída e a estrutura não
// são configuráveis — é o que protege o número.
export const MENSAGEM_PADRAO: ConfigMensagem = {
  // Marca e endereço não têm padrão de verdade: unidade sem cadastro assina com o
  // próprio nome e a mensagem sai sem a linha do endereço.
  marca: '',
  endereco: '',
  telefone: null,
  credencial: 'Posto de ensaio credenciado pelo Inmetro',
  conviteVencido: 'Venha aferir com a gente e já saia com tudo em dia.',
  conviteAVencer: 'Venha aferir com a gente antes do prazo e já saia com tudo em dia.',
  avisoContrato: 'Atendemos por ordem de chegada e cada veículo já sai com tudo em dia. Se preferirem trazer todos juntos, é só combinar.',
}

export function configMensagemDe(u: Unidade | null | undefined): ConfigMensagem {
  return {
    marca: u?.marca?.trim() || u?.nome || 'nosso posto',
    endereco: u?.endereco?.trim() || '',
    telefone: u?.telefone?.trim() || null,
    credencial: u?.msg_credencial?.trim() || MENSAGEM_PADRAO.credencial,
    conviteVencido: u?.msg_convite_vencido?.trim() || MENSAGEM_PADRAO.conviteVencido,
    conviteAVencer: u?.msg_convite_a_vencer?.trim() || MENSAGEM_PADRAO.conviteAVencer,
    avisoContrato: u?.msg_aviso_contrato?.trim() || MENSAGEM_PADRAO.avisoContrato,
  }
}

// A configuração de mensagem de uma unidade, com os padrões aplicados. Devolve uma
// função porque a ficha do lead só sabe a unidade depois de carregar o lead.
export function useConfigMensagem(): (unidadeId: string | null | undefined) => ConfigMensagem {
  const { unidades } = useAuth()
  return useCallback(
    (unidadeId: string | null | undefined) => configMensagemDe(unidades.find((u) => u.id === unidadeId)),
    [unidades]
  )
}

// Quem enxerga o painel Admin: o pleno e o da unidade (com abas reduzidas).
export function usePodeAdmin(): boolean {
  const { membro } = useAuth()
  return membro?.papel === 'admin' || membro?.papel === 'admin_unidade'
}
