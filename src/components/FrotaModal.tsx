import { useCallback, useEffect, useMemo, useState } from 'react'
import { X, Search, Truck, Check, Pencil, CheckCircle2 } from 'lucide-react'
import { supabase } from '../lib/supabase'

// A frota inteira de uma empresa: consultar, anotar e dar baixa.
//
// É a tela que faltava. Até aqui, clicar no número de veículos abria a colagem
// de placas — bom para cadastrar, inútil para tocar a rotina. E a rotina é
// mensal: abre a frota, olha quem venceu, e à medida que os ônibus passam pela
// oficina vai baixando um a um. Sem isso a data só se corrige na planilha e o
// app envelhece sozinho.
//
// A observação é por VEÍCULO. "Está na oficina", "reboque, não afere",
// "documento com o motorista" — informação que hoje vive no WhatsApp da menina
// e some quando ela sai de férias.

type Veiculo = {
  id: string
  placa: string | null
  numero_empresa: string | null
  modelo: string | null
  observacoes: string | null
  data_ultima_afericao: string | null
  venc: string | null
}

type Filtro = 'todos' | 'vencidos' | 'mes'

function fmt(iso: string | null): string {
  if (!iso) return '—'
  const [a, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${a}`
}

function hojeISO(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

function diasAte(venc: string | null): number | null {
  if (!venc) return null
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)
  return Math.round((new Date(venc + 'T00:00:00').getTime() - hoje.getTime()) / 86400000)
}

// Vencido, vencendo, tranquilo — a cor faz o trabalho que a data sozinha não faz.
function classeVenc(venc: string | null): string {
  const d = diasAte(venc)
  if (d === null) return 'text-ink-4'
  if (d < 0) return 'text-rose-400 font-bold'
  if (d <= 45) return 'text-amber-400 font-bold'
  return 'text-ink-6'
}

export default function FrotaModal({
  empresaId,
  empresaNome,
  onClose,
  onMudou,
}: {
  empresaId: string
  empresaNome: string
  onClose: () => void
  // Dar baixa muda os totais da tela de trás (vencendo no mês, a avisar).
  onMudou?: () => void
}) {
  const [veiculos, setVeiculos] = useState<Veiculo[]>([])
  const [busca, setBusca] = useState('')
  const [buscaDeb, setBuscaDeb] = useState('')
  const [filtro, setFiltro] = useState<Filtro>('todos')
  const [loading, setLoading] = useState(true)
  const [erro, setErro] = useState<string | null>(null)

  const [editandoObs, setEditandoObs] = useState<string | null>(null)
  const [rascunho, setRascunho] = useState('')
  // Qual placa está com o "aferido" aberto, e em que data.
  const [aferindo, setAferindo] = useState<string | null>(null)
  const [dataAfericao, setDataAfericao] = useState(hojeISO())
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    const t = setTimeout(() => setBuscaDeb(busca), 300)
    return () => clearTimeout(t)
  }, [busca])

  const carregar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc('frota_da_empresa', {
      p_empresa: empresaId,
      p_busca: buscaDeb || null,
    })
    setLoading(false)
    if (error) {
      setErro(error.message)
      return
    }
    setVeiculos((data as Veiculo[]) ?? [])
  }, [empresaId, buscaDeb])

  useEffect(() => {
    carregar()
  }, [carregar])

  const mesAtual = hojeISO().slice(0, 7)
  const lista = useMemo(() => {
    if (filtro === 'vencidos') return veiculos.filter((v) => (diasAte(v.venc) ?? 1) < 0)
    if (filtro === 'mes') return veiculos.filter((v) => v.venc?.slice(0, 7) === mesAtual)
    return veiculos
  }, [veiculos, filtro, mesAtual])

  const contagem = useMemo(
    () => ({
      todos: veiculos.length,
      vencidos: veiculos.filter((v) => (diasAte(v.venc) ?? 1) < 0).length,
      mes: veiculos.filter((v) => v.venc?.slice(0, 7) === mesAtual).length,
    }),
    [veiculos, mesAtual]
  )

  async function salvarObs(id: string) {
    setSalvando(true)
    setErro(null)
    const { error } = await supabase.rpc('salvar_obs_veiculo', { p_lead: id, p_obs: rascunho })
    setSalvando(false)
    if (error) {
      setErro(error.message)
      return
    }
    // Atualiza na lista sem recarregar: com 431 veículos, recarregar a cada
    // observação salva faria a tela piscar e perder a rolagem.
    setVeiculos((prev) =>
      prev.map((v) => (v.id === id ? { ...v, observacoes: rascunho.trim() || null } : v))
    )
    setEditandoObs(null)
  }

  // Dar baixa: grava a data da aferição e o vencimento salta 2 anos. A trava de
  // data futura e de data anterior à última aferição está no servidor.
  async function darBaixa(id: string) {
    setSalvando(true)
    setErro(null)
    const { data, error } = await supabase.rpc('registrar_afericao_frota', {
      p_lead: id,
      p_data: dataAfericao,
      p_notas: null,
    })
    setSalvando(false)
    if (error) {
      setErro(error.message)
      return
    }
    const r = data as { data: string; venc: string }
    setVeiculos((prev) =>
      prev.map((v) => (v.id === id ? { ...v, data_ultima_afericao: r.data, venc: r.venc } : v))
    )
    setAferindo(null)
    setDataAfericao(hojeISO())
    onMudou?.()
  }

  const FILTROS: Array<{ v: Filtro; t: string; n: number }> = [
    { v: 'todos', t: 'Todos', n: contagem.todos },
    { v: 'vencidos', t: 'Vencidos', n: contagem.vencidos },
    { v: 'mes', t: 'Vencem este mês', n: contagem.mes },
  ]

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-5xl p-6 max-h-[90vh] flex flex-col">
        <div className="flex items-center justify-between mb-1">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <Truck size={18} className="text-lucro" />
            Frota da {empresaNome}
          </h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>
        <p className="text-xs text-ink-4 mb-4">
          Conforme os veículos forem aferindo, clique em <b className="text-ink-6">Aferido</b> — o
          vencimento salta 2 anos e ele sai da lista de vencidos.
        </p>

        <div className="flex flex-wrap gap-2 mb-3">
          {FILTROS.map((f) => (
            <button
              key={f.v}
              onClick={() => setFiltro(f.v)}
              className={`px-3 py-1.5 rounded-xl text-xs font-bold border transition-colors ${
                filtro === f.v ? 'border-brand bg-brand/15 text-ink' : 'border-line text-ink-6 hover:bg-white/5'
              }`}
            >
              {f.t}{' '}
              <span className={f.v === 'vencidos' && f.n > 0 ? 'text-rose-400' : 'text-ink-4'}>
                {f.n}
              </span>
            </button>
          ))}
        </div>

        <div className="relative mb-3">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink-4" />
          <input
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Buscar por placa, número interno ou observação…"
            className="w-full pl-9 pr-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
          />
        </div>

        {erro && (
          <p className="text-sm text-danger mb-2 bg-danger/10 border border-danger/30 rounded-xl px-3 py-2">
            {erro}
          </p>
        )}

        <div className="flex-1 overflow-y-auto -mx-2 px-2">
          {loading ? (
            <p className="p-6 text-sm text-ink-4">Carregando…</p>
          ) : lista.length === 0 ? (
            <p className="p-6 text-sm text-ink-4 text-center">
              {buscaDeb
                ? 'Nada encontrado para essa busca.'
                : filtro === 'vencidos'
                  ? 'Nenhum veículo vencido. '
                  : 'Nada nesta lista.'}
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-card">
                <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                  <th className="px-2 py-2">Nº</th>
                  <th className="px-2 py-2">Placa</th>
                  <th className="px-2 py-2">Vence</th>
                  <th className="px-2 py-2">Observação</th>
                  <th className="px-2 py-2 text-right">Baixa</th>
                </tr>
              </thead>
              <tbody>
                {lista.map((v) => {
                  const emObs = editandoObs === v.id
                  const emBaixa = aferindo === v.id
                  return (
                    <tr key={v.id} className="border-b border-line last:border-0 align-top">
                      <td className="px-2 py-2 font-mono font-bold text-ink-6 whitespace-nowrap">
                        {v.numero_empresa ?? '—'}
                      </td>
                      <td className="px-2 py-2 font-mono font-bold text-ink whitespace-nowrap">
                        {v.placa ?? '—'}
                      </td>
                      <td className={`px-2 py-2 whitespace-nowrap ${classeVenc(v.venc)}`}>
                        {v.venc ? fmt(v.venc) : 'sem data'}
                      </td>
                      <td className="px-2 py-2 w-2/5">
                        {emObs ? (
                          <div className="flex items-start gap-1.5">
                            <textarea
                              autoFocus
                              value={rascunho}
                              onChange={(ev) => setRascunho(ev.target.value)}
                              onKeyDown={(ev) => {
                                if (ev.key === 'Escape') setEditandoObs(null)
                                if (ev.key === 'Enter' && !ev.shiftKey) {
                                  ev.preventDefault()
                                  salvarObs(v.id)
                                }
                              }}
                              rows={2}
                              placeholder="Ex.: está na oficina · reboque, não afere · documento com o motorista"
                              className="flex-1 px-2 py-1 border border-line rounded-lg text-xs focus-ring outline-none resize-none"
                            />
                            <button
                              onClick={() => salvarObs(v.id)}
                              disabled={salvando}
                              className="text-lucro hover:opacity-70 mt-1 disabled:opacity-40"
                              title="Salvar (Enter)"
                            >
                              <Check size={15} />
                            </button>
                            <button
                              onClick={() => setEditandoObs(null)}
                              className="text-ink-4 hover:text-ink mt-1"
                              title="Cancelar (Esc)"
                            >
                              <X size={15} />
                            </button>
                          </div>
                        ) : (
                          <button
                            onClick={() => {
                              setRascunho(v.observacoes ?? '')
                              setEditandoObs(v.id)
                            }}
                            className="text-left w-full group flex items-start gap-1.5"
                          >
                            <span className={`text-xs ${v.observacoes ? 'text-ink-6' : 'text-ink-4 italic'}`}>
                              {v.observacoes ?? 'sem observação'}
                            </span>
                            <Pencil
                              size={12}
                              className="text-ink-4 opacity-0 group-hover:opacity-100 shrink-0 mt-0.5"
                            />
                          </button>
                        )}
                      </td>
                      <td className="px-2 py-2 text-right whitespace-nowrap">
                        {emBaixa ? (
                          <span className="inline-flex items-center gap-1.5">
                            <input
                              type="date"
                              autoFocus
                              value={dataAfericao}
                              max={hojeISO()}
                              onChange={(ev) => setDataAfericao(ev.target.value)}
                              className="px-2 py-1 border border-line rounded-lg text-xs focus-ring outline-none bg-card"
                            />
                            <button
                              onClick={() => darBaixa(v.id)}
                              disabled={salvando}
                              className="bg-lucro text-white text-xs font-bold px-2.5 py-1.5 rounded-lg hover:opacity-90 disabled:opacity-40"
                            >
                              {salvando ? '…' : 'Confirmar'}
                            </button>
                            <button
                              onClick={() => setAferindo(null)}
                              className="text-ink-4 hover:text-ink"
                              title="Cancelar"
                            >
                              <X size={15} />
                            </button>
                          </span>
                        ) : (
                          <button
                            onClick={() => {
                              setDataAfericao(hojeISO())
                              setAferindo(v.id)
                            }}
                            className="inline-flex items-center gap-1.5 border border-lucro/40 bg-lucro/10 text-lucro text-xs font-bold px-2.5 py-1.5 rounded-lg hover:bg-lucro/20"
                            title="Registrar que este veículo aferiu"
                          >
                            <CheckCircle2 size={13} /> Aferido
                          </button>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  )
}
