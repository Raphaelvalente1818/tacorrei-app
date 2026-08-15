import { useState, type FormEvent } from 'react'
import { useAuth } from '../lib/AuthContext'
import { supabase } from '../lib/supabase'

export default function Login() {
  const { signInWithPassword } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [info, setInfo] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [enviandoReset, setEnviandoReset] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setInfo(null)
    setLoading(true)
    const { error } = await signInWithPassword(email, password)
    setLoading(false)
    if (error) setError('E-mail ou senha inválidos.')
  }

  async function esqueciSenha() {
    setError(null)
    setInfo(null)
    if (!email) {
      setError('Digite seu e-mail no campo acima para receber o link de redefinição.')
      return
    }
    setEnviandoReset(true)
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/redefinir-senha`,
    })
    setEnviandoReset(false)
    if (error) {
      setError('Não foi possível enviar o e-mail agora. Tente novamente em instantes.')
    } else {
      setInfo('Enviamos um link de redefinição para o seu e-mail. Confira a caixa de entrada e o spam.')
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-bg px-4">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-6">
          <div className="relative mb-3">
            <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-brand to-brand-d text-[#04120a] flex items-center justify-center text-4xl font-extrabold shadow-xl shadow-brand/30">
              A
            </div>
            <span className="absolute -right-1.5 -top-1.5 w-7 h-7 rounded-lg bg-bg text-brand text-lg font-black flex items-center justify-center border-2 border-brand leading-none">
              +
            </span>
          </div>
          <h1 className="text-lg font-extrabold text-ink">
            Aferi<span className="text-lucro">+</span>
          </h1>
          <p className="text-sm text-ink-4">Painel de ligações e aferições</p>
        </div>

        <form onSubmit={handleSubmit} className="card p-6 space-y-4">
          <div>
            <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
              E-mail
            </label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full px-3 py-2.5 border border-line rounded-xl text-sm focus-ring outline-none"
              placeholder="voce@empresa.com"
            />
          </div>
          <div>
            <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
              Senha
            </label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2.5 border border-line rounded-xl text-sm focus-ring outline-none"
              placeholder="••••••••"
            />
          </div>

          {error && <p className="text-sm text-danger">{error}</p>}
          {info && <p className="text-sm text-lucro">{info}</p>}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            {loading ? 'Entrando…' : 'Entrar'}
          </button>

          <button
            type="button"
            onClick={esqueciSenha}
            disabled={enviandoReset}
            className="w-full text-center text-sm font-semibold text-brand-d hover:underline disabled:opacity-60"
          >
            {enviandoReset ? 'Enviando…' : 'Esqueci minha senha'}
          </button>
        </form>

        <p className="text-xs text-ink-4 text-center mt-4">
          Acesso restrito à equipe. Fale com o admin para criar sua conta.
        </p>
      </div>
    </div>
  )
}
