import { useCallback, useEffect, useState } from 'react'
import { Lock, Plus, Wallet } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/AuthContext'
import { botao, input, real } from './ui'

// ── Prêmio ───────────────────────────────────────────────────────────────────
// Os dois números que a operadora conhece desde o dia 1º: valor do ponto e teto do
// mês, mais a fatia do bolo. Vigência por mês; mudança nunca vale no mês corrente
// (o banco recusa para quem não é admin geral). Sem valor = mês de observação.
// Quem edita: o admin geral; o gestor só se a unidade tiver a marcação liberada.

type Vigencia = {
  id: string
  vigencia: string
  valor_ponto: number | null
  teto_mes: number | null
  pct_bolo: number
  observacao: string | null
  criado_em: string
  criado_por: string | null
}

type Config = { premios: Vigencia[]; pode_editar_premio: boolean; unidade: { nome: string; unidade_edita_premio: boolean } }

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

function rotuloMes(iso: string): string {
  const [a, m] = iso.split('-')
  return `${MESES[Number(m) - 1]}/${a}`
}

function proximoMes(): string {
  const d = new Date()
  d.setMonth(d.getMonth() + 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

export default function Premio({ unidadeId }: { unidadeId: string }) {
  const { membro } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  const [cfg, setCfg] = useState<Config | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  const [vigencia, setVigencia] = useState(proximoMes())
  const [observacaoMes, setObservacaoMes] = useState(false)
  const [valor, setValor] = useState('5')
  const [teto, setTeto] = useState('')
  const [bolo, setBolo] = useState('30')
  const [obs, setObs] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)

  const carregar = useCallback(async () => {
    setErro(null)
    const { data, error } = await supabase.rpc('configuracao_unidade', { p_unidade: unidadeId })
    if (error) {
      setErro(error.message)
      return
    }
    setCfg(data as Config)
  }, [unidadeId])

  useEffect(() => {
    carregar()
  }, [carregar])

  async function salvar() {
    setMsg(null)
    const v = observacaoMes ? null : Number(valor.replace(',', '.'))
    const t = teto.trim() === '' ? null : Number(teto.replace(',', '.'))
    const b = Number(bolo)
    if (!observacaoMes && (isNaN(v as number) || (v as number) <= 0)) return setMsg({ tipo: 'erro', texto: 'Informe o valor do ponto (ou marque "mês de observação").' })
    if (t !== null && (isNaN(t) || t <= 0)) return setMsg({ tipo: 'erro', texto: 'Teto inválido.' })
    if (isNaN(b) || b < 0 || b > 100) return setMsg({ tipo: 'erro', texto: 'O bolo é um percentual entre 0 e 100.' })
    setSalvando(true)
    const { error } = await supabase.rpc('definir_parametros_premio', {
      p_unidade: unidadeId,
      p_vigencia: `${vigencia}-01`,
      p_valor_ponto: v,
      p_teto_mes: t,
      p_pct_bolo: b,
      p_observacao: obs.trim() || null,
    })
    setSalvando(false)
    if (error) {
      setMsg({ tipo: 'erro', texto: error.message })
      return
    }
    setMsg({ tipo: 'ok', texto: `Regra de ${rotuloMes(`${vigencia}-01`)} gravada.` })
    setObs('')
    carregar()
  }

  if (erro) return <p className="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3">{erro}</p>
  if (!cfg) return <p className="text-sm text-ink-4">Carregando…</p>

  const hoje = new Date()
  const compAtual = `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}-01`
  const vigente = cfg.premios.find((p) => p.vigencia <= compAtual) ?? null

  return (
    <div className="space-y-4">
      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
          <Wallet size={16} className="text-brand" /> Regra em vigor neste mês
        </h2>
        {!vigente ? (
          <p className="text-sm text-ink-4">Nenhuma regra cadastrada ainda — o mês conta pontos, mas não paga.</p>
        ) : vigente.valor_ponto === null ? (
          <p className="text-sm text-ink-6">Mês de observação (desde {rotuloMes(vigente.vigencia)}): os pontos contam, o prêmio ainda não.</p>
        ) : (
          <p className="text-sm text-ink-6">
            <b className="text-ink">{real(vigente.valor_ponto)}</b> por ponto
            {vigente.teto_mes !== null && <> · teto <b className="text-ink">{real(vigente.teto_mes)}</b> por mês</>}
            {' '}· <b className="text-ink">{vigente.pct_bolo}%</b> no bolo (desde {rotuloMes(vigente.vigencia)})
          </p>
        )}
      </div>

      <div className="card overflow-hidden">
        <div className="px-5 py-3 border-b border-line text-sm font-extrabold text-ink">Histórico de vigências</div>
        {cfg.premios.length === 0 ? (
          <p className="px-5 py-4 text-sm text-ink-4">Nada cadastrado.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-2">A partir de</th>
                <th className="px-3 py-2 text-right">Valor do ponto</th>
                <th className="px-3 py-2 text-right">Teto</th>
                <th className="px-3 py-2 text-right">Bolo</th>
                <th className="px-3 py-2">Observação</th>
                <th className="px-5 py-2">Quem</th>
              </tr>
            </thead>
            <tbody>
              {cfg.premios.map((p) => (
                <tr key={p.id} className={`border-b border-line last:border-0 ${p.vigencia > compAtual ? 'text-ink-6' : ''}`}>
                  <td className="px-5 py-2.5 font-semibold text-ink">
                    {rotuloMes(p.vigencia)}
                    {p.vigencia > compAtual && <span className="ml-2 text-[10px] text-ink-4 uppercase">futuro</span>}
                    {p === vigente && <span className="ml-2 text-[10px] text-emerald-300 uppercase">em vigor</span>}
                  </td>
                  <td className="px-3 py-2.5 text-right tabular-nums">{p.valor_ponto === null ? <span className="text-ink-4">observação</span> : real(p.valor_ponto)}</td>
                  <td className="px-3 py-2.5 text-right tabular-nums">{p.teto_mes === null ? '—' : real(p.teto_mes)}</td>
                  <td className="px-3 py-2.5 text-right tabular-nums">{p.pct_bolo}%</td>
                  <td className="px-3 py-2.5 text-xs text-ink-4 max-w-72 truncate" title={p.observacao ?? ''}>{p.observacao ?? ''}</td>
                  <td className="px-5 py-2.5 text-xs text-ink-4">{p.criado_por ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {cfg.pode_editar_premio ? (
        <div className="card p-5">
          <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
            <Plus size={16} className="text-brand" /> Nova regra
          </h2>
          <p className="text-xs text-ink-4 mb-3">
            Vale a partir do mês escolhido, até a próxima regra. {isAdmin ? 'Como admin geral você pode gravar qualquer mês; ' : 'Só mês futuro — '}
            uma mudança nunca vale no mês corrente, para a operadora saber o que disputa desde o dia 1º.
          </p>
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
            <div>
              <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">A partir de</label>
              <input type="month" value={vigencia} onChange={(e) => setVigencia(e.target.value)} className={`${input} w-full`} />
            </div>
            <div>
              <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Valor do ponto (R$)</label>
              <input value={valor} disabled={observacaoMes} onChange={(e) => setValor(e.target.value)} inputMode="decimal" className={`${input} w-full disabled:opacity-40`} />
            </div>
            <div>
              <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Teto do mês (R$)</label>
              <input value={teto} disabled={observacaoMes} onChange={(e) => setTeto(e.target.value)} inputMode="decimal" placeholder="sem teto" className={`${input} w-full disabled:opacity-40`} />
            </div>
            <div>
              <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Bolo comum (%)</label>
              <input value={bolo} disabled={observacaoMes} onChange={(e) => setBolo(e.target.value)} inputMode="numeric" className={`${input} w-full disabled:opacity-40`} />
            </div>
          </div>
          <label className="flex items-center gap-2 text-xs text-ink-6 mt-3 cursor-pointer">
            <input type="checkbox" checked={observacaoMes} onChange={(e) => setObservacaoMes(e.target.checked)} />
            Mês de observação: conta os pontos, não paga prêmio.
          </label>
          <input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="Observação (opcional): o porquê desta regra" className={`${input} w-full mt-3`} />
          <div className="flex items-center gap-3 mt-3">
            <button onClick={salvar} disabled={salvando} className={botao}>
              <Plus size={15} /> {salvando ? 'Gravando…' : 'Gravar regra'}
            </button>
            {msg && <span className={`text-sm ${msg.tipo === 'ok' ? 'text-lucro' : 'text-danger'}`}>{msg.texto}</span>}
          </div>
        </div>
      ) : (
        <p className="text-xs text-ink-4 flex items-center gap-2">
          <Lock size={12} /> Valor do ponto, teto e bolo são definidos pelo admin geral do Aferi+. Se a sua unidade precisar mudar, peça a ele.
        </p>
      )}
    </div>
  )
}
