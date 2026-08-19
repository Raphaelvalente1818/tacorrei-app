import { useCallback, useEffect, useState } from 'react'
import { BarChart3, Building2, Users, Plus, Check, Pencil, Trash2, MapPin } from 'lucide-react'
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
  papel: 'admin' | 'admin_unidade' | 'operador'
  ativo: boolean
  unidade_id: string | null
}

type Aba = 'producao' | 'unidades' | 'cobertura' | 'acessos'

const PAPEL_LABEL: Record<Membro['papel'], string> = {
  admin: 'Admin',
  admin_unidade: 'Admin da unidade',
  operador: 'Operador',
}

const tabBase = 'flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-sm font-bold border transition-colors'
const tabOn = 'bg-brand text-[#04120a] border-brand'
const tabOff = 'bg-card text-ink-6 border-line hover:bg-white/5'

export default function Admin() {
  const { membro } = useAuth()
  const [aba, setAba] = useState<Aba>('producao')

  const isAdmin = membro?.papel === 'admin'
  const isAdminUnidade = membro?.papel === 'admin_unidade'

  if (!isAdmin && !isAdminUnidade) {
    return (
      <div className="card p-6">
        <p className="text-sm text-ink-6">Acesso restrito aos administradores.</p>
      </div>
    )
  }

  // O admin de unidade não cria unidade nem configura território — isso é do
  // Aferi+, não da unidade. Ele fica com Produção (a equipe dele), Unidades
  // (comparação por totais) e Acessos (a equipe dele).
  const abas: { id: Aba; label: string; icon: typeof BarChart3 }[] = [
    { id: 'producao', label: 'Produção', icon: BarChart3 },
    { id: 'unidades', label: 'Unidades', icon: Building2 },
    ...(isAdmin ? [{ id: 'cobertura' as Aba, label: 'Cobertura', icon: MapPin }] : []),
    { id: 'acessos', label: 'Acessos', icon: Users },
  ]

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-xl font-extrabold text-ink">Painel Admin</h1>
        <p className="text-sm text-ink-4">
          {isAdmin
            ? 'Produção das unidades, gestão de unidades e acessos'
            : 'Produção da sua unidade, comparação e acessos da sua equipe'}
        </p>
      </div>

      <div className="flex gap-2 mb-6">
        {abas.map((t) => (
          <button key={t.id} onClick={() => setAba(t.id)} className={`${tabBase} ${aba === t.id ? tabOn : tabOff}`}>
            <t.icon size={16} /> {t.label}
          </button>
        ))}
      </div>

      {aba === 'producao' && <Producao />}
      {aba === 'unidades' && <Unidades podeEditar={isAdmin} />}
      {aba === 'cobertura' && isAdmin && <Cobertura />}
      {aba === 'acessos' && <Acessos podeTudo={isAdmin} />}
    </div>
  )
}

function num(n: number) {
  return n.toLocaleString('pt-BR')
}

function Producao() {
  const { unidades: unidadesCtx, unidadeAtiva } = useAuth()
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

  // Respeita a unidade em foco no menu ("Visualizando"). Sem foco = todas (comparação).
  const focoNome = unidadeAtiva ? unidadesCtx.find((u) => u.id === unidadeAtiva)?.nome ?? null : null
  const unidadesView = unidadeAtiva ? unidades.filter((u) => u.id === unidadeAtiva) : unidades
  const operadoresView = focoNome ? operadores.filter((o) => o.unidade === focoNome) : operadores

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
                {unidadesView.map((u) => (
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
                {unidadesView.length === 0 && (
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
                {operadoresView.map((o, i) => (
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
                {operadoresView.length === 0 && (
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

// Retrato de cada unidade (RPC `unidades_painel`): carteira → fila → abordados → aferidos.
interface UnidadePainel {
  id: string
  nome: string
  janela_dias: number | null
  cidades: string | null
  carteira: number
  fila: number
  abordados: number
  aferidos: number
}

// Percentual da fila já abordada. Abaixo de 1% mostra uma casa decimal, senão
// "5%" e "0%" ficariam indistinguíveis para quem mal começou.
function pctFila(abordados: number, fila: number): string | null {
  if (fila <= 0) return null
  const p = (abordados / fila) * 100
  if (p === 0) return '0%'
  if (p < 1) return `${p.toFixed(1).replace('.', ',')}%`
  return `${Math.round(p)}%`
}

function Unidades({ podeEditar }: { podeEditar: boolean }) {
  const [unidades, setUnidades] = useState<UnidadePainel[]>([])
  const [loading, setLoading] = useState(true)
  const [nova, setNova] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [editId, setEditId] = useState<string | null>(null)
  const [editNome, setEditNome] = useState('')

  const carregar = useCallback(async () => {
    setLoading(true)
    const { data } = await supabase.rpc('unidades_painel')
    setUnidades((data as UnidadePainel[]) ?? [])
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
      {/* Criar unidade é do Aferi+, não do admin de unidade. */}
      {podeEditar && (
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
      )}

      <div className="card overflow-hidden">
        {loading ? (
          <p className="p-6 text-sm text-ink-4">Carregando…</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-3">Unidade</th>
                <th className="px-5 py-3 text-right">Carteira</th>
                <th className="px-5 py-3 text-right">Na fila</th>
                <th className="px-5 py-3 text-right">Abordados</th>
                <th className="px-5 py-3 text-right">Aferidos</th>
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
                      <>
                        {u.nome}
                        <span className="block text-[11px] font-semibold text-ink-4 mt-0.5">
                          {u.cidades ?? 'sem cidades'}
                        </span>
                      </>
                    )}
                  </td>

                  <td className="px-5 py-3 text-right text-ink-4 font-bold tabular-nums">
                    {num(u.carteira)}
                  </td>

                  <td className="px-5 py-3 text-right text-lucro font-extrabold tabular-nums">
                    {num(u.fila)}
                  </td>

                  {/* Abordados: o número manda, o % da fila acompanha, e a barra
                      desenha essa mesma %. Fila zerada → não há o que medir. */}
                  <td className="px-5 py-3 text-right">
                    <div className="flex items-baseline justify-end gap-3">
                      <span className="font-extrabold text-ink tabular-nums">{num(u.abordados)}</span>
                      {pctFila(u.abordados, u.fila) && (
                        <span className="text-xs font-bold text-ink-4">
                          {pctFila(u.abordados, u.fila)}
                        </span>
                      )}
                    </div>
                    {u.fila > 0 && (
                      <div className="h-1.5 rounded-full bg-line overflow-hidden w-28 ml-auto mt-2">
                        {u.abordados > 0 && (
                          <div
                            className="h-full rounded-full bg-brand"
                            style={{ width: `${Math.max((u.abordados / u.fila) * 100, 1.5)}%` }}
                          />
                        )}
                      </div>
                    )}
                  </td>

                  <td className="px-5 py-3 text-right tabular-nums font-extrabold">
                    <span className={u.aferidos > 0 ? 'text-ink' : 'text-ink-4'}>{num(u.aferidos)}</span>
                  </td>

                  <td className="px-5 py-3 text-right">
                    {podeEditar && editId !== u.id && (
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

      <div className="card p-4">
        <p className="text-xs font-bold uppercase tracking-wide text-ink-4 mb-2">O que cada coluna conta</p>
        <dl className="text-sm text-ink-6 space-y-1.5">
          <div className="flex gap-2">
            <dt className="font-bold text-ink shrink-0">Carteira</dt>
            <dd>— total com tacógrafo.</dd>
          </div>
          <div className="flex gap-2">
            <dt className="font-bold text-ink shrink-0">Na fila</dt>
            <dd>— a vencer dentro da janela da unidade, mais os que já venceram. É o trabalho de hoje.</dd>
          </div>
          <div className="flex gap-2">
            <dt className="font-bold text-ink shrink-0">Abordados</dt>
            <dd>— mensagem enviada, e quanto isso representa da fila. Conta o lead uma vez, não o número de mensagens.</dd>
          </div>
          <div className="flex gap-2">
            <dt className="font-bold text-ink shrink-0">Aferidos</dt>
            <dd>— aferidos na unidade.</dd>
          </div>
        </dl>
      </div>
    </div>
  )
}

function Acessos({ podeTudo }: { podeTudo: boolean }) {
  const { membro, unidades: unidadesCtx, unidadeAtiva } = useAuth()
  // Admin de unidade não tem seletor "Visualizando": a unidade dele é a dele.
  const unidadeFoco = podeTudo ? unidadeAtiva : membro?.unidade_id ?? null
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

interface UnidadeJanela {
  id: string
  nome: string
  janela_dias: number | null
}
interface CidadeCobertura {
  id: string
  cidade: string
}

// Atalhos de janela. O banco aceita qualquer número de dias (1 a 3650) ou NULL
// (= base toda); estes são só os valores de uso comum. Se a unidade estiver com
// um número fora desta lista, ele aparece como um chip extra em "Janela atual".
const JANELAS: { label: string; dias: number | null }[] = [
  { label: '30 dias', dias: 30 },
  { label: '45 dias', dias: 45 },
  { label: '60 dias', dias: 60 },
  { label: 'Base toda', dias: null },
]

function Cobertura() {
  const { unidadeAtiva } = useAuth()
  const [unidades, setUnidades] = useState<UnidadeJanela[]>([])
  const [sel, setSel] = useState<string>(unidadeAtiva ?? '')
  const [cidades, setCidades] = useState<CidadeCobertura[]>([])
  const [nova, setNova] = useState('')
  const [loading, setLoading] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)

  const carregarUnidades = useCallback(async () => {
    const { data } = await supabase.from('unidades').select('id, nome, janela_dias').order('nome')
    const list = (data as UnidadeJanela[]) ?? []
    setUnidades(list)
    setSel((s) => s || unidadeAtiva || list[0]?.id || '')
  }, [unidadeAtiva])

  const carregarCidades = useCallback(async (unidadeId: string) => {
    if (!unidadeId) {
      setCidades([])
      return
    }
    const { data } = await supabase
      .from('unidade_cidades')
      .select('id, cidade')
      .eq('unidade_id', unidadeId)
      .order('cidade')
    setCidades((data as CidadeCobertura[]) ?? [])
  }, [])

  useEffect(() => {
    ;(async () => {
      setLoading(true)
      await carregarUnidades()
      setLoading(false)
    })()
  }, [carregarUnidades])

  // Acompanha a unidade em foco no menu ("Visualizando").
  useEffect(() => {
    if (unidadeAtiva) setSel(unidadeAtiva)
  }, [unidadeAtiva])

  useEffect(() => {
    carregarCidades(sel)
  }, [sel, carregarCidades])

  const unidadeSel = unidades.find((u) => u.id === sel) ?? null

  async function setJanela(dias: number | null) {
    if (!sel) return
    await supabase.from('unidades').update({ janela_dias: dias }).eq('id', sel)
    setUnidades((prev) => prev.map((u) => (u.id === sel ? { ...u, janela_dias: dias } : u)))
  }

  async function addCidade() {
    setErro(null)
    const cidade = nova.trim()
    if (!cidade || !sel) return
    setSalvando(true)
    const { error } = await supabase.from('unidade_cidades').insert({ unidade_id: sel, cidade })
    setSalvando(false)
    if (error) {
      setErro(
        error.message.includes('duplicate') || error.message.includes('unidade_cidades_cidade')
          ? `A cidade "${cidade}" já está vinculada a uma unidade.`
          : error.message
      )
      return
    }
    setNova('')
    carregarCidades(sel)
  }

  async function removeCidade(id: string) {
    await supabase.from('unidade_cidades').delete().eq('id', id)
    setCidades((prev) => prev.filter((c) => c.id !== id))
  }

  if (loading) return <p className="text-sm text-ink-4">Carregando…</p>

  return (
    <div className="space-y-4">
      <div className="card p-4 space-y-4">
        <div>
          <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Unidade</label>
          <select
            value={sel}
            onChange={(e) => setSel(e.target.value)}
            className="w-full sm:w-72 px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card"
          >
            {unidades.map((u) => (
              <option key={u.id} value={u.id}>{u.nome}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1.5">
            Janela — o que a unidade recebe
          </label>
          <div className="flex gap-1.5 flex-wrap">
            {JANELAS.map((j) => {
              const on = (unidadeSel?.janela_dias ?? null) === j.dias
              return (
                <button
                  key={j.label}
                  onClick={() => setJanela(j.dias)}
                  className={`px-3.5 py-1.5 rounded-full text-xs font-bold border transition-colors ${
                    on ? 'bg-brand text-[#04120a] border-brand' : 'bg-card text-ink-6 border-line hover:bg-white/5'
                  }`}
                >
                  {j.label}
                </button>
              )
            })}
            {/* Janela definida direto no banco, fora dos atalhos: mostra o valor real
                em vez de deixar todos os chips apagados (o que parecia "nenhuma janela"). */}
            {unidadeSel?.janela_dias != null &&
              !JANELAS.some((j) => j.dias === unidadeSel.janela_dias) && (
                <span className="px-3.5 py-1.5 rounded-full text-xs font-bold border bg-brand text-[#04120a] border-brand">
                  {unidadeSel.janela_dias} dias
                </span>
              )}
          </div>
          <p className="text-xs text-ink-4 mt-2">
            A janela é um <strong>prazo</strong>, não uma fatia da base: a equipe vê quem já está vencido mais quem
            vence dentro desse prazo. Quem vence depois entra na fila sozinho quando a data se aproxima. “Base toda”
            = todos os leads com tacógrafo da unidade, inclusive os que só vencem daqui a muito tempo. Unidades novas
            nascem em 30 dias.
          </p>
        </div>
      </div>

      <div className="card p-4">
        <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Adicionar cidade</label>
        <div className="flex gap-2">
          <input
            value={nova}
            onChange={(e) => setNova(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addCidade()}
            placeholder="Ex.: Santo André"
            className="flex-1 px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
          />
          <button
            onClick={addCidade}
            disabled={salvando}
            className="flex items-center gap-1.5 bg-brand text-[#04120a] text-sm font-bold px-4 py-2 rounded-xl hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            <Plus size={16} /> Adicionar
          </button>
        </div>
        {erro && <p className="text-sm text-danger mt-2">{erro}</p>}
        <p className="text-xs text-ink-4 mt-2">
          Os leads dessas cidades pertencem a esta unidade. Cada cidade só pode estar em uma unidade.
        </p>
      </div>

      <div className="card overflow-hidden">
        <div className="px-5 py-3 border-b border-line text-xs text-ink-4">
          {cidades.length} {cidades.length === 1 ? 'cidade' : 'cidades'} em {unidadeSel?.nome ?? '—'}
        </div>
        {cidades.length === 0 ? (
          <p className="px-5 py-4 text-sm text-ink-4">Nenhuma cidade vinculada ainda.</p>
        ) : (
          <ul className="divide-y divide-line">
            {cidades.map((c) => (
              <li key={c.id} className="flex items-center justify-between px-5 py-3">
                <span className="flex items-center gap-2 text-sm text-ink">
                  <MapPin size={15} className="text-brand" /> {c.cidade}
                </span>
                <button
                  onClick={() => removeCidade(c.id)}
                  className="text-ink-4 hover:text-rose-400"
                  title="Remover cidade"
                >
                  <Trash2 size={15} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
