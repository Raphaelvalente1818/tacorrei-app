import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/AuthContext'
import { num } from './ui'

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

export default function Producao() {
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
