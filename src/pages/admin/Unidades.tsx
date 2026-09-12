import { useCallback, useEffect, useState } from 'react'
import { Plus, Check, Pencil } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { num } from './ui'

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

export default function Unidades({ podeEditar }: { podeEditar: boolean }) {
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
