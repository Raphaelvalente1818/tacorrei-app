import { useCallback, useEffect, useState } from 'react'
import { BarChart3, Building2, Users, Plus, Check, Pencil, Trash2 } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/AuthContext'

type Periodo = { label: string; dias: number | null }
const PERIODOS: Periodo[] = [
  { label: 'Últimos 7 dias', dias: 7 },
  { label: 'Últimos 30 dias', dias: 30 },
  { label: 'Tudo', dias: null },
]

interface ProdUnidade {
  id: string
  nome: string
  leads: number
  aferidos: number
  agendados_total: number
  contatos: number
  whatsapp: number
  agendados: number
}
interface ProdOperador {
  operador: string
  papel: string
  unidade: string | null
  contatos: number
  whatsapp: number
  agendados: number
}
interface Unidade {
  id: string
  nome: string
}
interface Membro {
  user_id: string
  nome: string
  email: string | null
  papel: 'admin' | 'operador'
  ativo: boolean
  unidade_id: string | null
}

type Aba = 'producao' | 'unidades' | 'acessos'

const tabBase = 'flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-sm font-bold border transition-colors'
const tabOn = 'bg-brand text-[#04120a] border-brand'
const tabOff = 'bg-card text-ink-6 border-line hover:bg-white/5'

export default function Admin() {
  const { membro } = useAuth()
  const [aba, setAba] = useState<Aba>('producao')

  if (membro?.papel !== 'admin') {
    return (
      <div className="card p-6">
        <p className="text-sm text-ink-6">Acesso restrito aos administradores.</p>
      </div>
    )
  }

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-xl font-extrabold text-ink">Painel Admin</h1>
        <p className="text-sm text-ink-4">Produção das unidades, gestão de unidades e acessos</p>
      </div>

      <div className="flex gap-2 mb-6">
        {([
          { id: 'producao', label: 'Produção', icon: BarChart3 },
          { id: 'unidades', label: 'Unidades', icon: Building2 },
          { id: 'acessos', label: 'Acessos', icon: Users },
        ] as const).map((t) => (
          <button key={t.id} onClick={() => setAba(t.id)} className={`${tabBase} ${aba === t.id ? tabOn : tabOff}`}>
            <t.icon size={16} /> {t.label}
          </button>
        ))}
      </div>

      {aba === 'producao' && <Producao />}
      {aba === 'unidades' && <Unidades />}
      {aba === 'acessos' && <Acessos />}
    </div>
  )
}

function num(n: number) {
  return n.toLocaleString('pt-BR')
}

function Producao() {
  const [dias, setDias] = useState<number | null>(30)
  const [unidades, setUnidades] = useState<ProdUnidade[]>([])
  const [operadores, setOperadores] = useState<ProdOperador[]>([])
  const [loading, setLoading] = useState(true)

  const carregar = useCallback(async () => {
    setLoading(true)
    const [u, o] = await Promise.all([
      supabase.rpc('producao_unidades', { p_dias: dias }),
      supabase.rpc('producao_operadores', { p_dias: dias }),
    ])
    setUnidades((u.data as ProdUnidade[]) ?? [])
    setOperadores((o.data as ProdOperador[]) ?? [])
    setLoading(false)
  }, [dias])

  useEffect(() => {
    carregar()
  }, [carregar])

  return (
    <div className="space-y-6">
      <div className="flex gap-1.5">
        {PERIODOS.map((p) => (
          <button
            key={p.label}
            onClick={() => setDias(p.dias)}
            className={`px-3 py-1.5 rounded-full text-xs font-bold border transition-colors ${
              dias === p.dias ? 'bg-brand text-[#04120a] border-brand' : 'bg-card text-ink-6 border-line hover:bg-white/5'
            }`}
          >
            {p.label}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="text-sm text-ink-4">Carregando…</p>
      ) : (
        <>
          <div className="card overflow-hidden">
            <div className="px-5 py-3 border-b border-line text-sm font-extrabold text-ink">Produção por unidade</div>
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                  <th className="px-5 py-3">Unidade</th>
                  <th className="px-5 py-3 text-right">Leads</th>
                  <th className="px-5 py-3 text-right">Contatos</th>
                  <th className="px-5 py-3 text-right">WhatsApp</th>
                  <th className="px-5 py-3 text-right">Agendados</th>
                  <th className="px-5 py-3 text-right">Aferidos</th>
                  <th className="px-5 py-3 text-right">Conversão</th>
                </tr>
              </thead>
              <tbody>
                {unidades.map((u) => (
                  <tr key={u.id} className="border-b border-line last:border-0">
                    <td className="px-5 py-3 font-semibold text-ink">{u.nome}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(u.leads)}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(u.contatos)}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(u.whatsapp)}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(u.agendados)}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(u.aferidos)}</td>
                    <td className="px-5 py-3 text-right font-bold text-lucro">
                      {u.leads > 0 ? Math.round((u.aferidos / u.leads) * 100) : 0}%
                    </td>
                  </tr>
                ))}
                {unidades.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-5 py-4 text-sm text-ink-4">
                      Nenhuma unidade.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="card overflow-hidden">
            <div className="px-5 py-3 border-b border-line text-sm font-extrabold text-ink">Produção por funcionária</div>
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                  <th className="px-5 py-3">Funcionária</th>
                  <th className="px-5 py-3">Unidade</th>
                  <th className="px-5 py-3 text-right">Contatos</th>
                  <th className="px-5 py-3 text-right">WhatsApp</th>
                  <th className="px-5 py-3 text-right">Agendados</th>
                </tr>
              </thead>
              <tbody>
                {operadores.map((o, i) => (
                  <tr key={i} className="border-b border-line last:border-0">
                    <td className="px-5 py-3 font-semibold text-ink">
                      {o.operador}
                      {o.papel === 'admin' && <span className="ml-1 text-[10px] text-ink-4">(admin)</span>}
                    </td>
                    <td className="px-5 py-3 text-ink-6">{o.unidade ?? '—'}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(o.contatos)}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(o.whatsapp)}</td>
                    <td className="px-5 py-3 text-right text-ink-6">{num(o.agendados)}</td>
                  </tr>
                ))}
                {operadores.length === 0 && (
                  <tr>
                    <td colSpan={5} className="px-5 py-4 text-sm text-ink-4">
                      Ninguém na equipe ainda.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}

function Unidades() {
  const [unidades, setUnidades] = useState<ProdUnidade[]>([])
  const [loading, setLoading] = useState(true)
  const [nova, setNova] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [editId, setEditId] = useState<string | null>(null)
  const [editNome, setEditNome] = useState('')

  const carregar = useCallback(async () => {
    setLoading(true)
    const { data } = await supabase.rpc('producao_unidades', { p_dias: null })
    setUnidades((data as ProdUnidade[]) ?? [])
    setLoading(false)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  async function criar() {
    setErro(null)
    const nome = nova.trim()
    if (!nome) return
    setSalvando(true)
    const { error } = await supabase.from('unidades').insert({ nome })
    setSalvando(false)
    if (error) {
      setErro(error.message.includes('duplicate') ? 'Já existe uma unidade com esse nome.' : error.message)
      return
    }
    setNova('')
    carregar()
  }

  async function salvarNome(id: string) {
    const nome = editNome.trim()
    if (!nome) return
    await supabase.from('unidades').update({ nome }).eq('id', id)
    setEditId(null)
    carregar()
  }

  return (
    <div className="space-y-4">
      <div className="card p-4">
        <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Nova unidade</label>
        <div className="flex gap-2">
          <input
            value={nova}
            onChange={(e) => setNova(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && criar()}
            placeholder="Ex.: São Bernardo"
            className="flex-1 px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
          />
          <button
            onClick={criar}
            disabled={salvando}
            className="flex items-center gap-1.5 bg-brand text-[#04120a] text-sm font-bold px-4 py-2 rounded-xl hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            <Plus size={16} /> Criar
          </button>
        </div>
        {erro && <p className="text-sm text-danger mt-2">{erro}</p>}
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <p className="p-6 text-sm text-ink-4">Carregando…</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-3">Unidade</th>
                <th className="px-5 py-3 text-right">Leads (com tacógrafo)</th>
                <th className="px-5 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {unidades.map((u) => (
                <tr key={u.id} className="border-b border-line last:border-0">
                  <td className="px-5 py-3 font-semibold text-ink">
                    {editId === u.id ? (
                      <span className="flex items-center gap-1">
                        <input
                          autoFocus
                          value={editNome}
                          onChange={(e) => setEditNome(e.target.value)}
                          onKeyDown={(e) => e.key === 'Enter' && salvarNome(u.id)}
                          className="px-2 py-0.5 border border-line rounded-lg text-sm focus-ring outline-none"
                        />
                        <button onClick={() => salvarNome(u.id)} className="text-lucro hover:opacity-70">
                          <Check size={15} />
                        </button>
                      </span>
                    ) : (
                      u.nome
                    )}
                  </td>
                  <td className="px-5 py-3 text-right text-ink-6">{num(u.leads)}</td>
                  <td className="px-5 py-3 text-right">
                    {editId !== u.id && (
                      <button
                        onClick={() => {
                          setEditId(u.id)
                          setEditNome(u.nome)
                        }}
                        className="text-ink-4 hover:text-brand"
                        title="Renomear"
                      >
                        <Pencil size={14} />
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

function Acessos() {
  const { unidades: unidadesCtx, unidadeAtiva } = useAuth()
  const [membros, setMembros] = useState<Membro[]>([])
  const [unidades, setUnidades] = useState<Unidade[]>([])
  const [loading, setLoading] = useState(true)

  // novo acesso
  const [nome, setNome] = useState('')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [papel, setPapel] = useState<'admin' | 'operador'>('operador')
  const [unidadeId, setUnidadeId] = useState(unidadeAtiva ?? '')
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
    if (!unidadeId && uni.length) setUnidadeId(unidadeAtiva ?? uni[0].id)
    setLoading(false)
  }, [unidadeId, unidadeAtiva])

  useEffect(() => {
    carregar()
  }, [carregar])

  // Ao trocar a unidade "em foco" no menu, o formulário de novo acesso acompanha.
  useEffect(() => {
    if (unidadeAtiva) setUnidadeId(unidadeAtiva)
  }, [unidadeAtiva])

  async function atualizar(user_id: string, campos: Partial<Membro>) {
    await supabase.from('equipe').update(campos).eq('user_id', user_id)
    setMembros((prev) => prev.map((m) => (m.user_id === user_id ? { ...m, ...campos } : m)))
  }

  async function excluir(m: Membro) {
    if (
      !window.confirm(
        `Excluir definitivamente o acesso de ${m.nome}? O login será apagado. O histórico de ligações/agendamentos é mantido (fica sem dono).`
      )
    )
      return
    const { data, error } = await supabase.functions.invoke('admin-excluir-usuario', {
      body: { user_id: m.user_id },
    })
    const erro = error ? error.message : (data as { error?: string })?.error
    if (erro) {
      setMsg({ tipo: 'erro', texto: erro })
      return
    }
    setMembros((prev) => prev.filter((x) => x.user_id !== m.user_id))
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
  const visiveis = unidadeAtiva ? membros.filter((m) => m.unidade_id === unidadeAtiva) : membros

  return (
    <div className="space-y-4">
      <div className="card p-4">
        <div className="text-sm font-extrabold text-ink mb-1">Novo acesso</div>
        {unidadeAtiva && (
          <p className="text-xs text-lucro mb-2">
            Entra em <b>{nomeUnidade(unidadeAtiva)}</b> (unidade em foco no menu).
          </p>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
          <input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome"
            className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none" />
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="E-mail" type="email"
            className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none" />
          <input value={senha} onChange={(e) => setSenha(e.target.value)} placeholder="Senha (mín. 6)" type="text"
            className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none" />
          <div className="grid grid-cols-2 gap-3">
            <select value={unidadeId} onChange={(e) => setUnidadeId(e.target.value)}
              className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card">
              {unidades.map((u) => (
                <option key={u.id} value={u.id}>{u.nome}</option>
              ))}
            </select>
            <select value={papel} onChange={(e) => setPapel(e.target.value as 'admin' | 'operador')}
              className="px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card">
              <option value="operador">Operador</option>
              <option value="admin">Admin</option>
            </select>
          </div>
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
          {unidadeAtiva ? ` em ${nomeUnidade(unidadeAtiva)}` : ' (equipe inteira)'}
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
                  </td>
                  <td className="px-5 py-3">
                    <select
                      value={m.papel}
                      onChange={(e) => atualizar(m.user_id, { papel: e.target.value as 'admin' | 'operador' })}
                      className="px-2 py-1 border border-line rounded-lg text-sm bg-card outline-none"
                    >
                      <option value="operador">Operador</option>
                      <option value="admin">Admin</option>
                    </select>
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
                      onClick={() => excluir(m)}
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
      <p className="text-xs text-ink-4">
        <b>Desativar</b> bloqueia o login sem apagar o histórico. <b>Excluir</b> (lixeira) apaga o acesso de vez — o histórico de ligações/agendamentos fica preservado, porém sem dono.
      </p>
    </div>
  )
}
