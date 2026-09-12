import { useCallback, useEffect, useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/AuthContext'
import ConfirmarModal from '../../components/ConfirmarModal'

interface Unidade {
  id: string
  nome: string
}
interface Membro {
  user_id: string
  nome: string
  email: string | null
  papel: 'admin' | 'admin_unidade' | 'operador'
  ativo: boolean
  unidade_id: string | null
}

const PAPEL_LABEL: Record<Membro['papel'], string> = {
  admin: 'Admin',
  admin_unidade: 'Admin da unidade',
  operador: 'Operador',
}

// `unidadeFixa`: a tela Gestão → Equipe é de UMA unidade; quando o admin geral
// está em "Todas" e escolheu uma no painel, ela vem por aqui.
export default function Acessos({ podeTudo, unidadeFixa }: { podeTudo: boolean; unidadeFixa?: string | null }) {
  const { membro, unidades: unidadesCtx, unidadeAtiva } = useAuth()
  // Admin de unidade não tem seletor "Visualizando": a unidade dele é a dele.
  const unidadeFoco = unidadeFixa ?? (podeTudo ? unidadeAtiva : membro?.unidade_id ?? null)
  const [membros, setMembros] = useState<Membro[]>([])
  const [unidades, setUnidades] = useState<Unidade[]>([])
  const [loading, setLoading] = useState(true)

  // novo acesso
  const [nome, setNome] = useState('')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [papel, setPapel] = useState<'admin' | 'admin_unidade' | 'operador'>('operador')
  const [unidadeId, setUnidadeId] = useState(unidadeFoco ?? '')
  const [criando, setCriando] = useState(false)
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)

  const carregar = useCallback(async () => {
    setLoading(true)
    const [m, u] = await Promise.all([
      supabase.from('equipe').select('user_id, nome, email, papel, ativo, unidade_id').order('nome'),
      supabase.from('unidades').select('id, nome').order('nome'),
    ])
    setMembros((m.data as Membro[]) ?? [])
    const uni = (u.data as Unidade[]) ?? []
    setUnidades(uni)
    if (!unidadeId && uni.length) setUnidadeId(unidadeFoco ?? uni[0].id)
    setLoading(false)
  }, [unidadeId, unidadeFoco])

  useEffect(() => {
    carregar()
  }, [carregar])

  // Ao trocar a unidade "em foco" no menu, o formulário de novo acesso acompanha.
  useEffect(() => {
    if (unidadeFoco) setUnidadeId(unidadeFoco)
  }, [unidadeFoco])

  async function atualizar(user_id: string, campos: Partial<Membro>) {
    await supabase.from('equipe').update(campos).eq('user_id', user_id)
    setMembros((prev) => prev.map((m) => (m.user_id === user_id ? { ...m, ...campos } : m)))
  }

  // A exclusão passa pelo popup de confirmação (regra da casa: toda deleção confirma).
  const [excluindo, setExcluindo] = useState<Membro | null>(null)
  async function excluir(m: Membro) {
    const { data, error } = await supabase.functions.invoke('admin-excluir-usuario', {
      body: { user_id: m.user_id },
    })
    const erro = error ? error.message : (data as { error?: string })?.error
    if (erro) throw new Error(erro)
    setMembros((prev) => prev.filter((x) => x.user_id !== m.user_id))
    setExcluindo(null)
  }

  async function criarAcesso() {
    setMsg(null)
    if (!nome.trim() || !email.trim() || senha.length < 6) {
      setMsg({ tipo: 'erro', texto: 'Preencha nome, e-mail e uma senha de pelo menos 6 caracteres.' })
      return
    }
    setCriando(true)
    const { data, error } = await supabase.functions.invoke('admin-criar-usuario', {
      body: { nome: nome.trim(), email: email.trim(), senha, papel, unidade_id: unidadeId || null },
    })
    setCriando(false)
    const erro = error ? error.message : (data as { error?: string })?.error
    if (erro) {
      setMsg({ tipo: 'erro', texto: erro })
      return
    }
    setMsg({ tipo: 'ok', texto: `Acesso criado para ${nome.trim()}.` })
    setNome('')
    setEmail('')
    setSenha('')
    setPapel('operador')
    carregar()
  }

  const nomeUnidade = (id: string | null) =>
    (unidadesCtx.find((u) => u.id === id)?.nome ?? unidades.find((u) => u.id === id)?.nome) ?? '—'

  // Filtra pela unidade em foco no menu ("Visualizando"). Sem foco = todas.
  const visiveis = unidadeFoco ? membros.filter((m) => m.unidade_id === unidadeFoco) : membros

  return (
    <div className="space-y-4">
      <div className="card p-4">
        <div className="text-sm font-extrabold text-ink mb-1">Novo acesso</div>
        {unidadeFoco && (
          <p className="text-xs text-lucro mb-2">
            Entra em <b>{nomeUnidade(unidadeFoco)}</b>
            {podeTudo ? ' (unidade em foco no menu).' : ' — sua unidade.'}
          </p>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
          <input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome"
            className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none" />
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="E-mail" type="email"
            className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none" />
          <input value={senha} onChange={(e) => setSenha(e.target.value)} placeholder="Senha (mín. 6)" type="text"
            className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none" />
          {podeTudo ? (
            <div className="grid grid-cols-2 gap-3">
              <select value={unidadeId} onChange={(e) => setUnidadeId(e.target.value)}
                className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card">
                {unidades.map((u) => (
                  <option key={u.id} value={u.id}>{u.nome}</option>
                ))}
              </select>
              <select value={papel} onChange={(e) => setPapel(e.target.value as Membro['papel'])}
                className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card">
                <option value="operador">Operador</option>
                <option value="admin_unidade">Admin da unidade</option>
                <option value="admin">Admin</option>
              </select>
            </div>
          ) : (
            /* Admin de unidade só cria operador, e só na unidade dele. O servidor
               força isso de novo — aqui é só para não oferecer o que será negado. */
            <div className="px-3 py-2 border border-line rounded-xl text-sm text-ink-4 flex items-center">
              Operador em {nomeUnidade(unidadeFoco)}
            </div>
          )}
        </div>
        <div className="flex items-center gap-3 mt-3">
          <button onClick={criarAcesso} disabled={criando}
            className="flex items-center gap-1.5 bg-brand text-[#04120a] text-sm font-bold px-4 py-2 rounded-xl hover:bg-brand-d transition-colors disabled:opacity-60">
            <Plus size={16} /> {criando ? 'Criando…' : 'Criar acesso'}
          </button>
          {msg && <span className={`text-sm ${msg.tipo === 'ok' ? 'text-lucro' : 'text-danger'}`}>{msg.texto}</span>}
        </div>
        <p className="text-xs text-ink-4 mt-2">A funcionária entra com esse e-mail e senha. A senha pode ser trocada por ela depois em “Trocar senha”.</p>
      </div>

      <div className="card overflow-hidden">
        <div className="px-5 py-3 border-b border-line text-xs text-ink-4">
          {visiveis.length} {visiveis.length === 1 ? 'pessoa' : 'pessoas'}
          {unidadeFoco ? ` em ${nomeUnidade(unidadeFoco)}` : ' (equipe inteira)'}
        </div>
        {loading ? (
          <p className="p-6 text-sm text-ink-4">Carregando…</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-3">Nome</th>
                <th className="px-5 py-3">E-mail</th>
                <th className="px-5 py-3">Unidade</th>
                <th className="px-5 py-3">Papel</th>
                <th className="px-5 py-3">Ativo</th>
                <th className="px-5 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {visiveis.map((m) => (
                <tr key={m.user_id} className="border-b border-line last:border-0">
                  <td className="px-5 py-3 font-semibold text-ink">{m.nome}</td>
                  <td className="px-5 py-3 text-ink-6">{m.email ?? '—'}</td>
                  <td className="px-5 py-3">
                    {podeTudo ? (
                      <select
                        value={m.unidade_id ?? ''}
                        onChange={(e) => atualizar(m.user_id, { unidade_id: e.target.value || null })}
                        className="px-2 py-1 border border-line rounded-lg text-sm bg-card outline-none"
                      >
                        <option value="">—</option>
                        {unidades.map((u) => (
                          <option key={u.id} value={u.id}>{u.nome}</option>
                        ))}
                      </select>
                    ) : (
                      <span className="text-ink-6">{nomeUnidade(m.unidade_id)}</span>
                    )}
                  </td>
                  <td className="px-5 py-3">
                    {/* Mover de unidade e promover são do admin pleno. */}
                    {podeTudo ? (
                      <select
                        value={m.papel}
                        onChange={(e) => atualizar(m.user_id, { papel: e.target.value as Membro['papel'] })}
                        className="px-2 py-1 border border-line rounded-lg text-sm bg-card outline-none"
                      >
                        <option value="operador">Operador</option>
                        <option value="admin_unidade">Admin da unidade</option>
                        <option value="admin">Admin</option>
                      </select>
                    ) : (
                      <span className="text-ink-6">{PAPEL_LABEL[m.papel]}</span>
                    )}
                  </td>
                  <td className="px-5 py-3">
                    <button
                      onClick={() => atualizar(m.user_id, { ativo: !m.ativo })}
                      className={`px-2.5 py-1 rounded-full text-xs font-bold border ${
                        m.ativo
                          ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
                          : 'bg-slate-500/15 text-slate-400 border-slate-500/30'
                      }`}
                    >
                      {m.ativo ? 'Ativo' : 'Inativo'}
                    </button>
                  </td>
                  <td className="px-5 py-3 text-right">
                    <button
                      onClick={() => setExcluindo(m)}
                      className="text-ink-4 hover:text-rose-400"
                      title="Excluir acesso definitivamente"
                    >
                      <Trash2 size={15} />
                    </button>
                  </td>
                </tr>
              ))}
              {visiveis.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-5 py-4 text-sm text-ink-4">Nenhum acesso nesta unidade.</td>
                </tr>
              )}
            </tbody>
          </table>
        )}
      </div>
      {excluindo && (
        <ConfirmarModal
          titulo={`Excluir o acesso de ${excluindo.nome}?`}
          texto={'O login é apagado de vez e não volta. O histórico de contatos, agendamentos e pontos fica preservado, sem dono.\n\nSe a ideia é só tirar a pessoa do ar por um tempo, use "Desativar" em vez de excluir.'}
          rotuloConfirmar="Excluir de vez"
          onConfirmar={() => excluir(excluindo)}
          onCancelar={() => setExcluindo(null)}
        />
      )}
      <p className="text-xs text-ink-4">
        <b>Desativar</b> bloqueia o login sem apagar o histórico. <b>Excluir</b> (lixeira) apaga o acesso de vez — o histórico de ligações/agendamentos fica preservado, porém sem dono.
      </p>
    </div>
  )
}
