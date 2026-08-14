import { useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { KeyRound, ArrowLeft, CheckCircle2 } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/AuthContext'

export default function TrocarSenha() {
  const { user } = useAuth()
  const [senha, setSenha] = useState('')
  const [confirma, setConfirma] = useState('')
  const [erro, setErro] = useState<string | null>(null)
  const [ok, setOk] = useState(false)
  const [loading, setLoading] = useState(false)

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
      setErro('Não foi possível alterar a senha. Tente novamente.')
      return
    }
    setSenha('')
    setConfirma('')
    setOk(true)
  }

  return (
    <div className="max-w-md">
      <Link to="/" className="inline-flex items-center gap-1.5 text-sm text-ink-6 hover:text-brand-d mb-4">
        <ArrowLeft size={15} /> Voltar
      </Link>

      <div className="flex items-center gap-2 mb-1">
        <KeyRound size={20} className="text-brand" />
        <h1 className="text-xl font-extrabold text-ink">Trocar senha</h1>
      </div>
      <p className="text-sm text-ink-4 mb-6">
        Defina uma nova senha para a conta {user?.email ? <strong>{user.email}</strong> : 'da sua equipe'}.
      </p>

      {ok ? (
        <div className="card p-6">
          <div className="flex items-center gap-2 text-lucro font-bold mb-1">
            <CheckCircle2 size={20} /> Senha alterada!
          </div>
          <p className="text-sm text-ink-6">Sua nova senha já está valendo. Use-a no próximo login.</p>
          <Link
            to="/"
            className="inline-block mt-4 py-2.5 px-4 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors"
          >
            Voltar ao painel
          </Link>
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
  )
}
