import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Plus, Search, ChevronLeft, ChevronRight, CheckCircle2, Truck, MessageCircle } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useFiltroUnidade } from '../lib/AuthContext'
import type { Caminhoneiro, StatusLead } from '../lib/database.types'
import { STATUS_LEAD_CLASSES, STATUS_LEAD_LABEL } from '../lib/status'
import Badge from '../components/Badge'
import NovoLeadModal from '../components/NovoLeadModal'
import RegistrarAfericaoModal from '../components/RegistrarAfericaoModal'

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

const PAGE_SIZE = 100

// Um quadradinho por página. Com 100 por página a operadora tem ~6 a 10 páginas,
// e todas cabem na tela — é o caso normal. Acima de 12 (só acontece no admin
// olhando a base inteira) volta a resumir com '…', senão viraria uma fileira de
// 100 quadradinhos.
const MAX_QUADRADINHOS = 12

function paginasVisiveis(atual: number, total: number): (number | '…')[] {
  if (total <= MAX_QUADRADINHOS) return Array.from({ length: total }, (_, i) => i + 1)

  const paginas = new Set<number>([1, total, atual, atual - 1, atual + 1])
  // perto das pontas, estica para o outro lado para manter sempre 7 posições
  if (atual <= 3) [2, 3, 4].forEach((p) => paginas.add(p))
  if (atual >= total - 2) [total - 3, total - 2, total - 1].forEach((p) => paginas.add(p))

  const ordenadas = [...paginas].filter((p) => p >= 1 && p <= total).sort((a, b) => a - b)

  const saida: (number | '…')[] = []
  ordenadas.forEach((p, i) => {
    if (i > 0 && p - ordenadas[i - 1] > 1) saida.push('…')
    saida.push(p)
  })
  return saida
}
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

// Guarda qual lead a operadora abriu por último. Ao voltar da ficha, a lista
// rola até ele e o destaca — assim ela retoma a sequência de onde parou em vez
// de cair no topo da página 1. Fica em sessionStorage (morre ao fechar a aba).
const LS_ULTIMO_LEAD = 'lacre.ultimoLead'

// A lista mostra só a janela (45 dias). Em São Bernardo isso deixa 1.500 leads da
// carteira fora do alcance da operadora — e quando um desses caminhões aparece na
// porta para aferir, ela busca a placa, não acha, e o "Novo lead" criaria uma
// duplicata: a linha antiga guardaria a data velha e voltaria para a fila depois.
// Por isso, quando a busca não devolve nada E o que foi digitado é uma placa
// inteira, o app faz uma segunda consulta que alcança a unidade toda — uma placa
// por vez, no máximo um resultado, registrada no log. É preciso já saber a placa;
// não dá para varrer base com isso.
function normalizaPlaca(s: string): string {
  return s.toUpperCase().replace(/[^A-Z0-9]/g, '')
}
const PLACA_COMPLETA = /^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$/

export default function Leads() {
  const { membro } = useAuth()
  const filtroUnidade = useFiltroUnidade()
  const isAdmin = membro?.papel === 'admin'
  // A fila "Sem tacógrafo" é só para o admin; a funcionária não vê esse público.
  const filtros = FILTROS.filter((f) => f.value !== 'sem_tacografo' || isAdmin)
  const [leads, setLeads] = useState<Caminhoneiro[]>([])
  const [loading, setLoading] = useState(true)
  // Filtro, busca e página moram na URL: voltar da ficha (ou dar refresh, ou usar
  // o botão do navegador) devolve a lista exatamente como estava.
  const [params, setParams] = useSearchParams()
  const [filtro, setFiltro] = useState<FiltroLead>((params.get('f') as FiltroLead) || 'todos')
  const [busca, setBusca] = useState(params.get('q') ?? '')
  const [buscaDebounced, setBuscaDebounced] = useState(params.get('q') ?? '')
  const [page, setPage] = useState(Math.max(0, Number(params.get('p') ?? 1) - 1))
  const [total, setTotal] = useState(0)
  const [showNovo, setShowNovo] = useState(false)
  const [irPara, setIrPara] = useState('')
  // Achado da busca por placa exata (fora da janela) — ver comentário em normalizaPlaca.
  const [foraDaJanela, setForaDaJanela] = useState<Caminhoneiro | null>(null)
  const [placaAferir, setPlacaAferir] = useState<string | null>(null)
  const [placaAferida, setPlacaAferida] = useState(false)
  // Cota de WhatsApp do dia — a operadora precisa ver quanto sobrou ANTES de
  // começar a rodada, não descobrir no meio que a trava fechou.
  const [cota, setCota] = useState<{ limite: number; usadas: number; restantes: number } | null>(null)

  useEffect(() => {
    let cancelado = false
    supabase.rpc('cota_whatsapp_hoje', { p_unidade: filtroUnidade }).then(({ data, error }) => {
      if (cancelado || error || !data) return
      const c = data as { limite: number | null; usadas: number; restantes: number | null }
      if (c.limite == null || c.restantes == null) return
      setCota({ limite: c.limite, usadas: c.usadas, restantes: c.restantes })
    })
    return () => {
      cancelado = true
    }
  }, [filtroUnidade, leads])

  // debounce da busca
  useEffect(() => {
    const t = setTimeout(() => setBuscaDebounced(busca), 400)
    return () => clearTimeout(t)
  }, [busca])

  // ao mudar filtro/busca/unidade, volta pra primeira página
  const primeiraCarga = useRef(true)
  useEffect(() => {
    if (primeiraCarga.current) {
      // não zera a página na montagem, senão perderíamos a página vinda da URL
      primeiraCarga.current = false
      return
    }
    setPage(0)
  }, [filtro, buscaDebounced, filtroUnidade])

  // espelha o estado da lista na URL
  useEffect(() => {
    const novo = new URLSearchParams()
    if (page > 0) novo.set('p', String(page + 1))
    if (filtro !== 'todos') novo.set('f', filtro)
    if (buscaDebounced) novo.set('q', buscaDebounced)
    setParams(novo, { replace: true })
  }, [page, filtro, buscaDebounced, setParams])

  // `aindaVale` permite descartar uma resposta que chegou atrasada, depois que o
  // filtro/unidade já mudou (senão a lista antiga sobrescreve a nova — ver Dashboard).
  const carregar = useCallback(async (aindaVale: () => boolean = () => true) => {
    setLoading(true)
    // A lista NÃO consulta a tabela direto. Vai pela RPC `listar_leads`, que impõe
    // teto de 100 por página e registra o acesso em `acessos_lead`. Era por aqui
    // que dava para puxar 1.000 registros de uma vez sem deixar rastro.
    const { data, error } = await supabase.rpc('listar_leads', {
      p_pagina: page + 1,
      p_tamanho: PAGE_SIZE,
      p_filtro: filtro,
      p_busca: buscaDebounced.trim() || null,
      p_unidade: filtroUnidade,
    })

    if (!aindaVale()) return
    if (error) {
      setLeads([])
      setTotal(0)
      setLoading(false)
      return
    }
    const res = data as { total: number; leads: Caminhoneiro[] } | null
    setLeads(res?.leads ?? [])
    setTotal(Number(res?.total ?? 0))
    setLoading(false)
  }, [page, filtro, buscaDebounced, filtroUnidade])

  useEffect(() => {
    let cancelado = false
    carregar(() => !cancelado)
    return () => {
      cancelado = true
    }
  }, [carregar])

  // Depois que a lista pinta, rola até o lead aberto por último e o destaca.
  const [destacado, setDestacado] = useState<string | null>(null)
  useEffect(() => {
    if (loading || leads.length === 0) return
    let id: string | null = null
    try {
      id = sessionStorage.getItem(LS_ULTIMO_LEAD)
    } catch {
      return
    }
    if (!id || !leads.some((l) => l.id === id)) return
    try {
      sessionStorage.removeItem(LS_ULTIMO_LEAD)
    } catch {
      // ignora
    }
    setDestacado(id)
    // espera o navegador pintar a linha antes de rolar
    requestAnimationFrame(() => {
      document.getElementById(`lead-${id}`)?.scrollIntoView({ block: 'center', behavior: 'smooth' })
    })
    const t = setTimeout(() => setDestacado(null), 2500)
    return () => clearTimeout(t)
  }, [loading, leads])

  // Segunda tentativa: a lista não achou nada e o que foi digitado é uma placa
  // completa. Só então vale a pena alcançar a base inteira da unidade.
  useEffect(() => {
    setForaDaJanela(null)
    setPlacaAferida(false)
    if (loading) return
    const placa = normalizaPlaca(buscaDebounced.trim())
    if (total > 0 || !PLACA_COMPLETA.test(placa)) return

    let cancelado = false
    supabase.rpc('buscar_por_placa', { p_placa: placa }).then(({ data, error }) => {
      if (cancelado || error || !data) return
      setForaDaJanela(data as Caminhoneiro)
    })
    return () => {
      cancelado = true
    }
  }, [loading, total, buscaDebounced])

  const inicio = total === 0 ? 0 : page * PAGE_SIZE + 1
  const fim = Math.min((page + 1) * PAGE_SIZE, total)
  const temAnterior = page > 0
  const temProxima = fim < total
  const totalPaginas = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const paginas = paginasVisiveis(page + 1, totalPaginas)

  // "Ir para a página": aceita Enter ou o botão. Fora do intervalo, corrige para
  // a página mais próxima em vez de recusar — digitar 50 numa lista de 19 vai
  // para a 19, que é o que a pessoa queria dizer.
  function irParaPagina() {
    const n = parseInt(irPara, 10)
    if (!Number.isFinite(n)) return
    setPage(Math.min(Math.max(n, 1), totalPaginas) - 1)
    setIrPara('')
  }

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
        {cota && (
          <div
            className={`flex items-center gap-2 px-3 py-2 rounded-xl border text-xs font-bold ${
              cota.restantes === 0
                ? 'border-rose-500/40 text-rose-400 bg-rose-500/10'
                : cota.restantes <= 10
                  ? 'border-amber-500/40 text-amber-400 bg-amber-500/10'
                  : 'border-line text-ink-6'
            }`}
            title="Limite diário de mensagens da unidade. Protege o número de WhatsApp contra bloqueio."
          >
            <MessageCircle size={14} />
            {cota.restantes === 0
              ? `Cota de hoje encerrada (${cota.limite})`
              : `${cota.restantes} de ${cota.limite} mensagens hoje`}
          </div>
        )}
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

      {/* Caminhão que está na base da unidade mas fora da janela — normalmente o
          walk-in que apareceu para aferir antes da hora. Some do caminho assim que
          a busca muda. Registrar por aqui evita a duplicata do "Novo lead". */}
      {foraDaJanela && (
        <div className="card p-5 mb-4 border-brand/40">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 rounded-lg bg-brand/15 text-brand flex items-center justify-center shrink-0">
              <Truck size={16} strokeWidth={2.3} />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
                Fora da fila, mas está na sua base
              </p>
              <p className="text-sm font-bold text-ink">{foraDaJanela.nome}</p>
              <p className="text-sm text-ink-6">
                {foraDaJanela.placa_veiculo}
                {foraDaJanela.cidade ? ` · ${foraDaJanela.cidade}` : ''}
                {(() => {
                  const v = vencimento(foraDaJanela.data_ultima_afericao)
                  return v ? ` · vence ${v.texto}` : ''
                })()}
              </p>
              <p className="text-xs text-ink-4 mt-1">
                Não aparece na lista porque o vencimento ainda está longe. Se ele veio aferir agora,
                registre por aqui — não crie um lead novo, senão a placa fica duplicada.
              </p>
            </div>
            {placaAferida ? (
              <span className="flex items-center gap-1.5 text-sm font-bold text-lucro shrink-0">
                <CheckCircle2 size={16} /> Registrado
              </span>
            ) : (
              <button
                onClick={() => setPlacaAferir(foraDaJanela.id)}
                className="flex items-center gap-1.5 bg-brand text-[#04120a] text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-brand-d transition-colors shrink-0"
              >
                <CheckCircle2 size={16} /> Aferido
              </button>
            )}
          </div>
        </div>
      )}

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
                  <tr
                  key={lead.id}
                  id={`lead-${lead.id}`}
                  className={`border-b border-line last:border-0 transition-colors ${
                    destacado === lead.id ? 'bg-brand/15' : 'hover:bg-white/5'
                  }`}
                >
                    <td className="px-5 py-3">
                      <Link
                        to={`/leads/${lead.id}`}
                        onClick={() => {
                          try {
                            sessionStorage.setItem(LS_ULTIMO_LEAD, lead.id)
                          } catch {
                            // ignora ambientes sem sessionStorage
                          }
                        }}
                        className="font-semibold text-brand-d hover:underline"
                      >
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
          <div className="px-5 py-3 border-t border-line text-sm text-ink-6 space-y-3">
            <div className="flex items-center justify-between gap-3">
              <span>
                Mostrando {inicio}–{fim} de {total} leads
              </span>
              {totalPaginas > MAX_QUADRADINHOS && (
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-ink-4">Ir para</span>
                  <input
                    value={irPara}
                    onChange={(e) => setIrPara(e.target.value.replace(/\D/g, ''))}
                    onKeyDown={(e) => e.key === 'Enter' && irParaPagina()}
                    inputMode="numeric"
                    placeholder={String(totalPaginas)}
                    aria-label={`Ir para a página (1 a ${totalPaginas})`}
                    className="w-14 px-2 py-1.5 border border-line rounded-lg text-sm text-center tabular-nums focus-ring outline-none bg-card"
                  />
                  <button
                    onClick={irParaPagina}
                    disabled={!irPara}
                    className="px-2.5 py-1.5 rounded-lg border border-line text-sm font-bold disabled:opacity-40 hover:bg-white/5"
                  >
                    Ir
                  </button>
                  <span className="text-xs text-ink-4">de {totalPaginas}</span>
                </div>
              )}
            </div>

            <div className="flex flex-wrap items-center justify-center gap-1.5">
              <button
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={!temAnterior}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg border border-line disabled:opacity-40 hover:bg-white/5"
                aria-label="Página anterior"
              >
                <ChevronLeft size={15} /> Anterior
              </button>

              {/* Números para pular direto. Com 19 páginas, "Próxima" 12 vezes
                  para chegar no meio é o que as operadoras reclamaram. */}
              {paginas.map((p, i) =>
                p === '…' ? (
                  <span key={`gap-${i}`} className="px-1.5 text-ink-4 select-none">
                    …
                  </span>
                ) : (
                  <button
                    key={p}
                    onClick={() => setPage(p - 1)}
                    aria-current={p === page + 1 ? 'page' : undefined}
                    className={`w-9 h-9 flex items-center justify-center rounded-lg border text-sm font-bold tabular-nums transition-colors ${
                      p === page + 1
                        ? 'bg-brand text-[#04120a] border-brand'
                        : 'border-line text-ink-6 hover:bg-white/5'
                    }`}
                  >
                    {p}
                  </button>
                )
              )}

              <button
                onClick={() => setPage((p) => p + 1)}
                disabled={!temProxima}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg border border-line disabled:opacity-40 hover:bg-white/5"
                aria-label="Próxima página"
              >
                Próxima <ChevronRight size={15} />
              </button>
            </div>
          </div>
        )}
      </div>

      {placaAferir && (
        <RegistrarAfericaoModal
          caminhoneiroId={placaAferir}
          onClose={() => setPlacaAferir(null)}
          onSaved={() => {
            setPlacaAferir(null)
            setPlacaAferida(true)
          }}
        />
      )}

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
