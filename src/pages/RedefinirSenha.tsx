import { useEffect, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { KeyRound, CheckCircle2 } from 'lucide-react'
import { supabase } from '../lib/supabase'

// Página pública onde o usuário cai ao clicar no link de "Esqueci minha senha" do e-mail.
// O supabase-js detecta o token de recuperação na URL e cria uma sessão temporária
// (evento PASSWORD_RECOVERY); então liberamos o formulário de nova senha.
export default function RedefinirSenha() {
  const navigate = useNavigate()
  const [pronto, setPronto] = useState(false)
  const [senha, setSenha] = useState('')
  const [confirma, setConfirma] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [ok, setOk] = useState(false)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) setPronto(true)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY' || session) setPronto(true)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setErro(null)
    if (senha.length < 6) {
      setErro('A senha precisa ter pelo menos 6 caracteres.')
      return
    }
    if (senha !== confirma) {
      setErro('As senhas não conferem.')
      return
    }
    setLoading(true)
    const { error } = await supabase.auth.updateUser({ password: senha })
    setLoading(false)
    if (error) {
      setErro('Não foi possível alterar a senha. O link pode ter expirado — peça um novo na tela de login.')
      return
    }
    setOk(true)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-bg px-4">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-6">
          <div className="w-14 h-14 rounded-2xl bg-brand text-white flex items-center justify-center mb-3">
            <KeyRound size={26} />
          </div>
          <h1 className="text-lg font-extrabold text-ink">Redefinir senha</h1>
          <p className="text-sm text-ink-4">Lacre Tacógrafos</p>
        </div>

        {ok ? (
          <div className="card p-6 text-center">
            <div className="flex items-center justify-center gap-2 text-lucro font-bold mb-1">
              <CheckCircle2 size={20} /> Senha redefinida!
            </div>
            <p className="text-sm text-ink-6 mb-4">Já pode entrar com a nova senha.</p>
            <button
              onClick={() => navigate('/')}
              className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors"
            >
              Ir para o painel
            </button>
          </div>
        ) : !pronto ? (
          <div className="card p-6 text-center">
            <p className="text-sm text-ink-6 mb-2">Validando o link de redefinição…</p>
            <p className="text-xs text-ink-4">
              Se esta tela não liberar, o link pode ter expirado. Volte ao login e peça um novo em
              “Esqueci minha senha”.
            </p>
            <button
              onClick={() => navigate('/')}
              className="mt-4 text-sm font-semibold text-brand-d hover:underline"
            >
              Voltar ao login
            </button>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="card p-6 space-y-4">
            <div>
              <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
                Nova senha
              </label>
              <input
                type="password"
                required
                value={senha}
                onChange={(e) => setSenha(e.target.value)}
                className="w-full px-3 py-2.5 border border-line rounded-xl text-sm focus-ring outline-none"
                placeholder="Pelo menos 6 caracteres"
              />
            </div>
            <div>
              <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
                Confirmar nova senha
              </label>
              <input
                type="password"
                required
                value={confirma}
                onChange={(e) => setConfirma(e.target.value)}
                className="w-full px-3 py-2.5 border border-line rounded-xl text-sm focus-ring outline-none"
                placeholder="Digite de novo"
              />
            </div>

            {erro && <p className="text-sm text-danger">{erro}</p>}

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
            >
              {loading ? 'Salvando…' : 'Salvar nova senha'}
            </button>
          </form>
        )}
      </div>
    </div>
  )
}
