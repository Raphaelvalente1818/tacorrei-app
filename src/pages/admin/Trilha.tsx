import { useCallback, useEffect, useState } from 'react'
import { Footprints, History } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { chip, chipOff, chipOn, num } from './ui'

// ── Trilha de acessos e registro de correções ────────────────────────────────
// Item 20 da matriz (admin geral): quem listou, buscou e abriu o quê — a mesma
// `acessos_lead` que existe desde a 0017, agora com tela. E o registro de
// correções (`correcoes`, 0088): suspensões, contatos de empresa apagados,
// aferições desfeitas, mudanças de situação de empresa — quem, quando, por quê.
// O gestor vê só as correções da unidade dele (modo 'gestor').

type Resumo = {
  dia: string
  nome: string
  papel: string | null
  unidade: string | null
  listagens: number
  leads_listados: number
  buscas_placa: number
  fichas_abertas: number
  primeiro: string
  ultimo: string
}
type Ultimo = { criado_em: string; nome: string; acao: string; quantidade: number; detalhe: Record<string, unknown> | null }
type Correcao = {
  quando: string
  quem: string
  acao: string
  alvo_tipo: string | null
  alvo_id: string | null
  motivo: string | null
  detalhe: Record<string, unknown> | null
  unidade?: string | null
}

const ACAO_LABEL: Record<string, string> = {
  suspender_unidade: 'Suspendeu a unidade',
  reativar_unidade: 'Reativou a unidade',
  apagar_contato_empresa: 'Apagou contato com empresa',
  desfazer_afericao: 'Desfez uma aferição',
  situacao_empresa: 'Mudou situação de empresa',
}

function fmt(iso: string): string {
  return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
}
function fmtDia(iso: string): string {
  const [a, m, d] = iso.split('-')
  return `${d}/${m}/${a}`
}

function descreve(c: Correcao): string {
  const d = c.detalhe ?? {}
  switch (c.acao) {
    case 'situacao_empresa':
      return `${String(d.empresa ?? '')}: ${String(d.de ?? '—')} → ${String(d.para ?? '—')}`
    case 'desfazer_afericao': {
      const volta = (d.volta_para ?? {}) as Record<string, unknown>
      return `${String(d.placa ?? '')}: voltou para ${volta.data ? fmtDia(String(volta.data)) : 'sem data'}${volta.posto ? ` · ${String(volta.posto).slice(0, 24)}` : ''}`
    }
    case 'apagar_contato_empresa': {
      const l = d as { canal?: string; resultado?: string; notas?: string }
      return `${l.canal ?? ''} · ${l.resultado ?? ''}${l.notas ? ` — ${String(l.notas).slice(0, 60)}` : ''}`
    }
    default:
      return String(d.nome ?? '')
  }
}

export default function Trilha({ modo, unidadeId }: { modo: 'admin' | 'gestor'; unidadeId: string | null }) {
  const [dias, setDias] = useState(7)
  const [resumo, setResumo] = useState<Resumo[]>([])
  const [ultimos, setUltimos] = useState<Ultimo[]>([])
  const [correcoes, setCorrecoes] = useState<Correcao[]>([])
  const [erro, setErro] = useState<string | null>(null)
  const [verUltimos, setVerUltimos] = useState(false)

  const carregar = useCallback(async () => {
    setErro(null)
    if (modo === 'admin') {
      const { data, error } = await supabase.rpc('trilha_acessos', { p_dias: dias, p_unidade: unidadeId })
      if (error) return setErro(error.message)
      const t = data as { resumo: Resumo[]; ultimos: Ultimo[]; correcoes: Correcao[] }
      setResumo(t.resumo)
      setUltimos(t.ultimos)
      setCorrecoes(t.correcoes)
    } else {
      if (!unidadeId) return
      const { data, error } = await supabase.rpc('correcoes_da_unidade', { p_unidade: unidadeId, p_limite: 100 })
      if (error) return setErro(error.message)
      setCorrecoes((data as Correcao[]) ?? [])
    }
  }, [modo, dias, unidadeId])

  useEffect(() => {
    carregar()
  }, [carregar])

  return (
    <div className="space-y-4">
      {erro && <p className="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3">{erro}</p>}

      {modo === 'admin' && (
        <div className="card overflow-hidden">
          <div className="px-5 py-3 border-b border-line flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-extrabold text-ink flex items-center gap-2"><Footprints size={16} className="text-brand" /> Quem acessou o quê, por dia</h2>
            <div className="flex gap-1.5">
              {[1, 7, 30].map((d) => (
                <button key={d} onClick={() => setDias(d)} className={`${chip} ${dias === d ? chipOn : chipOff}`}>{d === 1 ? 'Hoje' : `${d} dias`}</button>
              ))}
            </div>
          </div>
          {resumo.length === 0 ? (
            <p className="px-5 py-4 text-sm text-ink-4">Nenhum acesso no período.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                    <th className="px-5 py-2">Dia</th>
                    <th className="px-3 py-2">Quem</th>
                    <th className="px-3 py-2">Unidade</th>
                    <th className="px-3 py-2 text-right" title="Vezes que a fila foi carregada">Listagens</th>
                    <th className="px-3 py-2 text-right" title="Soma dos leads devolvidos nas listagens">Leads vistos</th>
                    <th className="px-3 py-2 text-right">Buscas por placa</th>
                    <th className="px-3 py-2 text-right">Fichas abertas</th>
                    <th className="px-5 py-2">Horário</th>
                  </tr>
                </thead>
                <tbody>
                  {resumo.map((r, i) => (
                    <tr key={i} className={`border-b border-line last:border-0 ${r.leads_listados > 3000 ? 'text-amber-300' : ''}`} title={r.leads_listados > 3000 ? 'Volume alto de listagem no dia — vale olhar' : ''}>
                      <td className="px-5 py-2 whitespace-nowrap text-ink-6">{fmtDia(r.dia)}</td>
                      <td className="px-3 py-2 font-semibold text-ink">{r.nome} <span className="text-[10px] text-ink-4 font-normal">{r.papel ?? ''}</span></td>
                      <td className="px-3 py-2 text-ink-6">{r.unidade ?? '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{num(r.listagens)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{num(r.leads_listados)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{num(r.buscas_placa)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{num(r.fichas_abertas)}</td>
                      <td className="px-5 py-2 text-xs text-ink-4 whitespace-nowrap">
                        {new Date(r.primeiro).toLocaleTimeString('pt-BR', { timeStyle: 'short' })}–{new Date(r.ultimo).toLocaleTimeString('pt-BR', { timeStyle: 'short' })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="px-5 py-3 border-t border-line">
            <button onClick={() => setVerUltimos((v) => !v)} className="text-xs text-brand font-bold hover:underline">
              {verUltimos ? 'Esconder os últimos 100 acessos' : 'Ver os últimos 100 acessos, um a um'}
            </button>
            {verUltimos && (
              <ul className="mt-2 text-xs text-ink-6 space-y-0.5 max-h-72 overflow-y-auto">
                {ultimos.map((u, i) => (
                  <li key={i} className="flex gap-3">
                    <span className="text-ink-4 whitespace-nowrap">{fmt(u.criado_em)}</span>
                    <span className="font-semibold text-ink">{u.nome}</span>
                    <span>{u.acao}{u.quantidade ? ` (${num(u.quantidade)})` : ''}</span>
                    <span className="text-ink-4 truncate">{u.detalhe ? JSON.stringify(u.detalhe) : ''}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}

      <div className="card overflow-hidden">
        <div className="px-5 py-3 border-b border-line">
          <h2 className="text-sm font-extrabold text-ink flex items-center gap-2"><History size={16} className="text-amber-300" /> Correções registradas</h2>
          <p className="text-xs text-ink-4">Tudo que desfez ou apagou algo passa por aqui: quem, quando, o quê e por quê.</p>
        </div>
        {correcoes.length === 0 ? (
          <p className="px-5 py-4 text-sm text-ink-4">Nenhuma correção registrada{modo === 'gestor' ? ' nesta unidade' : ''}.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-2">Quando</th>
                <th className="px-3 py-2">Quem</th>
                {modo === 'admin' && <th className="px-3 py-2">Unidade</th>}
                <th className="px-3 py-2">O quê</th>
                <th className="px-3 py-2">Detalhe</th>
                <th className="px-5 py-2">Motivo</th>
              </tr>
            </thead>
            <tbody>
              {correcoes.map((c, i) => (
                <tr key={i} className="border-b border-line last:border-0 align-top">
                  <td className="px-5 py-2 whitespace-nowrap text-ink-6">{fmt(c.quando)}</td>
                  <td className="px-3 py-2 font-semibold text-ink">{c.quem}</td>
                  {modo === 'admin' && <td className="px-3 py-2 text-ink-6">{c.unidade ?? '—'}</td>}
                  <td className="px-3 py-2 text-ink">{ACAO_LABEL[c.acao] ?? c.acao}</td>
                  <td className="px-3 py-2 text-xs text-ink-6 max-w-72 truncate" title={descreve(c)}>{descreve(c)}</td>
                  <td className="px-5 py-2 text-xs text-ink-4 max-w-56 truncate" title={c.motivo ?? ''}>{c.motivo ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
