import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Plus, Search, ChevronLeft, ChevronRight } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useFiltroUnidade } from '../lib/AuthContext'
import type { Caminhoneiro, StatusLead } from '../lib/database.types'
import { STATUS_LEAD_CLASSES, STATUS_LEAD_LABEL } from '../lib/status'
import Badge from '../components/Badge'
import NovoLeadModal from '../components/NovoLeadModal'

type FiltroLead = StatusLead | 'todos' | 'sem_tacografo'

const FILTROS: Array<{ label: string; value: FiltroLead }> = [
  { label: 'Todos', value: 'todos' },
  { label: 'Novo', value: 'novo' },
  { label: 'Mensagem enviada', value: 'mensagem_enviada' },
  { label: 'Contatado', value: 'contatado' },
  { label: 'Sem resposta', value: 'sem_resposta' },
  { label: 'Agendado', value: 'agendado' },
  { label: 'Aferido', value: 'aferido' },
  { label: 'Recusado', value: 'recusado' },
  { label: 'Sem tacógrafo', value: 'sem_tacografo' },
]

const PAGE_SIZE = 50
const VALIDADE_ANOS = 2

// Vencimento = última aferição + 2 anos. Retorna { texto, classe } ou null (sem data).
function vencimento(iso: string | null): { texto: string; classe: string } | null {
  if (!iso) return null
  const base = new Date(iso.slice(0, 10) + 'T00:00:00')
  if (isNaN(base.getTime())) return null
  const venc = new Date(base)
  venc.setFullYear(venc.getFullYear() + VALIDADE_ANOS)
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)
  const dias = Math.round((venc.getTime() - hoje.getTime()) / 86400000)
  const texto = `${String(venc.getDate()).padStart(2, '0')}/${String(venc.getMonth() + 1).padStart(2, '0')}/${venc.getFullYear()}`
  let classe = 'text-ink-6'
  if (dias < 0) classe = 'text-rose-400 font-bold'
  else if (dias <= 60) classe = 'text-amber-400 font-bold'
  return { texto, classe }
}

export default function Leads() {
  const { membro } = useAuth()
  const filtroUnidade = useFiltroUnidade()
  const isAdmin = membro?.papel === 'admin'
  // A fila "Sem tacógrafo" é só para o admin; a funcionária não vê esse público.
  const filtros = FILTROS.filter((f) => f.value !== 'sem_tacografo' || isAdmin)
  const [leads, setLeads] = useState<Caminhoneiro[]>([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState<FiltroLead>('todos')
  const [busca, setBusca] = useState('')
  const [buscaDebounced, setBuscaDebounced] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [showNovo, setShowNovo] = useState(false)

  // debounce da busca
  useEffect(() => {
    const t = setTimeout(() => setBuscaDebounced(busca), 400)
    return () => clearTimeout(t)
  }, [busca])

  // ao mudar filtro/busca/unidade, volta pra primeira página
  useEffect(() => {
    setPage(0)
  }, [filtro, buscaDebounced, filtroUnidade])

  // `aindaVale` permite descartar uma resposta que chegou atrasada, depois que o
  // filtro/unidade já mudou (senão a lista antiga sobrescreve a nova — ver Dashboard).
  const carregar = useCallback(async (aindaVale: () => boolean = () => true) => {
    setLoading(true)
    const from = page * PAGE_SIZE
    const to = from + PAGE_SIZE - 1
    let query = supabase.from('caminhoneiros').select('*', { count: 'exact' })

    // Admin pode focar numa unidade; a funcionária já é limitada pelo RLS.
    if (filtroUnidade) query = query.eq('unidade_id', filtroUnidade)

    if (filtro === 'sem_tacografo') {
      // fila separada: veículos sem tacógrafo (fora do público-alvo)
      query = query.eq('tem_tacografo', false)
    } else {
      // demais filtros só mostram o público-alvo (com tacógrafo)
      query = query.eq('tem_tacografo', true)
      if (filtro !== 'todos') query = query.eq('status', filtro)
    }

    const q = buscaDebounced.trim().replace(/[,()%]/g, ' ').trim()
    if (q) {
      query = query.or(
        `nome.ilike.%${q}%,telefone.ilike.%${q}%,cidade.ilike.%${q}%,placa_veiculo.ilike.%${q}%`
      )
    }

    // mais perto de vencer primeiro (última aferição mais antiga), sem data por último
    query = query
      .order('data_ultima_afericao', { ascending: true, nullsFirst: false })
      .range(from, to)

    const { data, count } = await query
    if (!aindaVale()) return
    setLeads((data as Caminhoneiro[]) ?? [])
    setTotal(count ?? 0)
    setLoading(false)
  }, [page, filtro, buscaDebounced, filtroUnidade])

  useEffect(() => {
    let cancelado = false
    carregar(() => !cancelado)
    return () => {
      cancelado = true
    }
  }, [carregar])

  const inicio = total === 0 ? 0 : page * PAGE_SIZE + 1
  const fim = Math.min((page + 1) * PAGE_SIZE, total)
  const temAnterior = page > 0
  const temProxima = fim < total

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-extrabold text-ink">Leads & Ligações</h1>
          <p className="text-sm text-ink-4">Caminhoneiros a contatar para aferição do tacógrafo</p>
        </div>
        <button
          onClick={() => setShowNovo(true)}
          className="flex items-center gap-1.5 bg-brand text-white text-sm font-bold px-4 py-2.5 rounded-xl hover:bg-brand-d transition-colors"
        >
          <Plus size={16} /> Novo lead
        </button>
      </div>

      <div className="flex flex-wrap items-center gap-2 mb-4">
        <div className="relative">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-4" />
          <input
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Buscar nome, telefone, cidade, placa…"
            className="pl-8 pr-3 py-2 border border-line rounded-xl text-sm w-72 focus-ring outline-none bg-card"
          />
        </div>
        <div className="flex flex-wrap gap-1.5">
          {filtros.map((f) => (
            <button
              key={f.value}
              onClick={() => setFiltro(f.value)}
              className={`px-3 py-1.5 rounded-full text-xs font-bold border transition-colors ${
                filtro === f.value
                  ? 'bg-brand text-white border-brand'
                  : 'bg-card text-ink-6 border-line hover:bg-white/5'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <p className="p-6 text-sm text-ink-4">Carregando…</p>
        ) : leads.length === 0 ? (
          <p className="p-6 text-sm text-ink-4">Nenhum lead encontrado.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-3">Nome</th>
                <th className="px-5 py-3">Telefone</th>
                <th className="px-5 py-3">Cidade/UF</th>
                <th className="px-5 py-3">Vencimento aferição</th>
                <th className="px-5 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {leads.map((lead) => {
                const venc = vencimento(lead.data_ultima_afericao)
                return (
                  <tr key={lead.id} className="border-b border-line last:border-0 hover:bg-white/5">
                    <td className="px-5 py-3">
                      <Link to={`/leads/${lead.id}`} className="font-semibold text-brand-d hover:underline">
                        {lead.nome}
                      </Link>
                    </td>
                    <td className="px-5 py-3 text-ink-6">{lead.telefone}</td>
                    <td className="px-5 py-3 text-ink-6">
                      {lead.cidade ? `${lead.cidade}${lead.uf ? '/' + lead.uf : ''}` : '—'}
                    </td>
                    <td className="px-5 py-3">
                      {venc ? (
                        <span className={venc.classe}>{venc.texto}</span>
                      ) : (
                        <span className="text-ink-4">sem data</span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      <Badge className={STATUS_LEAD_CLASSES[lead.status]}>
                        {STATUS_LEAD_LABEL[lead.status]}
                      </Badge>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}

        {!loading && total > 0 && (
          <div className="flex items-center justify-between px-5 py-3 border-t border-line text-sm text-ink-6">
            <span>
              Mostrando {inicio}–{fim} de {total} leads
            </span>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={!temAnterior}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg border border-line disabled:opacity-40 hover:bg-white/5"
              >
                <ChevronLeft size={15} /> Anterior
              </button>
              <button
                onClick={() => setPage((p) => p + 1)}
                disabled={!temProxima}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg border border-line disabled:opacity-40 hover:bg-white/5"
              >
                Próxima <ChevronRight size={15} />
              </button>
            </div>
          </div>
        )}
      </div>

      {showNovo && (
        <NovoLeadModal
          onClose={() => setShowNovo(false)}
          onCreated={() => {
            setShowNovo(false)
            carregar()
          }}
        />
      )}
    </div>
  )
}
