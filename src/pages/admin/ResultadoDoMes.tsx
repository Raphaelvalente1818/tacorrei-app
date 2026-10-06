import { useEffect, useState, type ReactNode } from 'react'
import { Camera, ChevronLeft, ChevronRight, Lock } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/AuthContext'
import { num, real } from './ui'

// ── Resultado do mês ─────────────────────────────────────────────────────────
// 0113 — o quadro que o Emerson montou à mão para os sócios (setembro/2026),
// agora dentro do app, todo mês: por unidade e operadora, aferições, pontos
// brutos, finais (fator da carteira), a parte individual, o bolo (liberado ou
// não), o total; a carteira defendida contra o piso; total da unidade, pago e o
// que fica com a casa; quem veio sozinho; e a observação crítica — quantos
// clientes nossos venceram e não renovaram.
//
// A FOTO É TIRADA PELO GESTOR OU PELO ADMIN GERAL, no botão da aba Meta, depois
// da auditoria (0113d: o Emerson preferiu o botão ao relógio). Enquanto não há
// foto a tela mostra a prévia ao vivo e diz que é prévia; a partir da foto o mês
// não muda mais, e o que for registrado tarde cai no mês corrente (origem
// "atrasado"). Mês de observação é SIMULADO com a próxima regra que paga, e a
// tela diz com qual.
//
// Quem vê: o gestor, a unidade dele; o admin geral, todas as unidades, uma
// embaixo da outra — é o relatório da matriz.

type Operadora = {
  nome: string
  afericoes: number
  brutos: number
  finais: number
  individual: number | null
  bolo: number | null
  bolo_se_liberado: number | null
  total: number | null
  anulada: boolean
}

type Resultado = {
  unidade: string
  competencia: string
  fechado: boolean
  fechado_em: string | null
  fechado_por: string | null
  simulado: boolean
  regra: { valor_ponto: number | null; teto_mes: number | null; pct_bolo: number; vigencia: string | null }
  carteira: {
    pct: number | null
    ok: boolean
    renovaram: number | null
    venciam: number | null
    nao_renovaram: number | null
    piso: number
    fator: number | null
  }
  pontos_brutos: number
  pontos_finais: number
  total_unidade: number | null
  individual: number | null
  bolo: number | null
  bolo_liberado: boolean
  pago: number | null
  fica_com_a_casa: number | null
  operadoras: Operadora[]
  veio_sozinho: { afericoes: number; pontos: number }
  observacao: string | null
}

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']
const MESES_CURTO = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

function rotulo(iso: string): string {
  const [a, m] = iso.split('-')
  return `${MESES[Number(m) - 1]}/${a}`
}
function rotuloCurto(iso: string): string {
  const [a, m] = iso.split('-')
  return `${MESES_CURTO[Number(m) - 1]}/${a}`
}
function primeiroDoMes(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}
// O padrão é o MÊS ANTERIOR: é a foto que acabou de ser tirada (ou está para ser).
function mesAnterior(): string {
  const d = new Date()
  d.setDate(1)
  d.setMonth(d.getMonth() - 1)
  return primeiroDoMes(d)
}
function fmtData(iso: string | null): string {
  if (!iso) return ''
  return new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function ResultadoDoMes({ unidadeId }: { unidadeId: string }) {
  const { membro, unidades } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  const [competencia, setCompetencia] = useState(mesAnterior())
  const [itens, setItens] = useState<Resultado[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  // Admin geral: todas as unidades (o relatório da matriz). Gestor: a dele.
  const alvos = isAdmin && unidades.length > 0 ? unidades.map((u) => u.id) : [unidadeId]

  useEffect(() => {
    let cancelado = false
    setItens(null)
    setErro(null)
    Promise.all(alvos.map((id) => supabase.rpc('resultado_do_mes', { p_unidade: id, p_competencia: competencia })))
      .then((rs) => {
        if (cancelado) return
        const e = rs.find((r) => r.error)
        if (e?.error) {
          setErro(e.error.message)
          return
        }
        setItens(rs.map((r) => r.data as Resultado))
      })
    return () => {
      cancelado = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [competencia, unidadeId, isAdmin, unidades.length])

  function andar(passo: number) {
    const [a, m] = competencia.split('-').map(Number)
    setCompetencia(primeiroDoMes(new Date(a, m - 1 + passo, 1)))
  }

  const hoje = new Date()
  const mesCorrente = primeiroDoMes(hoje) === competencia

  const primeiro = itens?.[0]
  const simulado = itens?.some((i) => i.simulado) ?? false
  const todosFechados = (itens?.length ?? 0) > 0 && itens!.every((i) => i.fechado)

  return (
    <div className="card overflow-hidden">
      {/* Cabeçalho: mês, estado da foto, regra usada */}
      <div className="px-5 pt-5 pb-3 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <Camera size={16} className="text-brand" /> Resultado de {rotulo(competencia)}
          </h2>
          <p className="text-xs text-ink-4 mt-1">
            {todosFechados ? (
              <>
                <Lock size={11} className="inline -mt-0.5 mr-1" />
                Foto tirada em {fmtData(primeiro?.fechado_em ?? null)}
                {primeiro?.fechado_por ? ` por ${primeiro.fechado_por}` : ''} — este mês não muda mais.
                O que for registrado depois pontua no mês corrente.
              </>
            ) : mesCorrente ? (
              <>Mês em andamento — prévia ao vivo. Quando o mês terminar, o gestor audita e tira a foto na aba Meta.</>
            ) : (
              <>Prévia ao vivo — a foto deste mês ainda não foi tirada. O gestor ou o admin geral tira na aba Meta, depois da auditoria; até lá dá para registrar e auditar.</>
            )}
            {' '}A regra do prêmio é de cada unidade — está na coluna "Regra" do segundo quadro.
          </p>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <button onClick={() => andar(-1)} className="p-2 rounded-lg border border-line text-ink-6 hover:bg-white/5" aria-label="Mês anterior">
            <ChevronLeft size={16} />
          </button>
          <span className="text-sm font-extrabold text-ink min-w-32 text-center capitalize">{rotulo(competencia)}</span>
          <button onClick={() => andar(1)} className="p-2 rounded-lg border border-line text-ink-6 hover:bg-white/5" aria-label="Próximo mês">
            <ChevronRight size={16} />
          </button>
        </div>
      </div>

      {erro && <p className="px-5 pb-5 text-sm text-amber-300">{erro}</p>}
      {!erro && !itens && <p className="px-5 pb-5 text-sm text-ink-4">Carregando…</p>}

      {itens && itens.length > 0 && (
        <>
          {/* Quadro 1: por unidade e operadora */}
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-ink-4 text-xs uppercase font-bold border-y border-line">
                  <th className="px-5 py-3">Unidade</th>
                  <th className="px-3 py-3">Operadora</th>
                  <th className="px-3 py-3 text-right">Aferições</th>
                  <th className="px-3 py-3 text-right">Pontos</th>
                  <th className="px-3 py-3 text-right" title="Com o fator da carteira nas conquistas, quando a carteira ficou abaixo do piso">Finais</th>
                  <th className="px-3 py-3 text-right" title="A parte individual, proporcional aos pontos finais">Individual</th>
                  <th className="px-3 py-3 text-right" title="A fatia do bolo da unidade, em partes iguais, se a carteira ficou acima do piso">Bolo</th>
                  <th className="px-5 py-3 text-right">Total</th>
                </tr>
              </thead>
              <tbody>
                {itens.map((u) => (
                  <UnidadeLinhas key={u.unidade} r={u} />
                ))}
              </tbody>
            </table>
          </div>

          {/* Quadro 2: carteira, total, pago, fica com a casa */}
          <div className="overflow-x-auto border-t border-line">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                  <th className="px-5 py-3">Unidade</th>
                  <th className="px-3 py-3">Regra</th>
                  <th className="px-3 py-3">Carteira defendida (piso {primeiro?.carteira.piso ?? 60}%)</th>
                  <th className="px-3 py-3 text-right">Pontos finais</th>
                  <th className="px-3 py-3 text-right">Total da unidade</th>
                  <th className="px-3 py-3 text-right">Pago</th>
                  <th className="px-5 py-3 text-right">Fica com a casa</th>
                </tr>
              </thead>
              <tbody>
                {itens.map((u) => (
                  <tr key={u.unidade} className="border-b border-line last:border-0">
                    <td className="px-5 py-3 font-bold text-ink">{u.unidade}</td>
                    <td className="px-3 py-3">
                      <Regra r={u} />
                    </td>
                    <td className="px-3 py-3">
                      <Carteira c={u.carteira} />
                    </td>
                    <td className="px-3 py-3 text-right tabular-nums">{num(u.pontos_finais)}</td>
                    <td className="px-3 py-3 text-right tabular-nums">{real(u.total_unidade)}</td>
                    <td className="px-3 py-3 text-right tabular-nums font-extrabold text-ink">{real(u.pago)}</td>
                    <td className={`px-5 py-3 text-right tabular-nums ${Number(u.fica_com_a_casa ?? 0) > 0 ? 'text-amber-300' : 'text-ink-4'}`}>
                      {real(u.fica_com_a_casa)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Rodapé: notas e a observação crítica */}
          <div className="px-5 py-4 border-t border-line space-y-3">
            <p className="text-[11px] text-ink-4 leading-relaxed">
              {itens.some((u) => !u.carteira.ok) && (
                <>
                  *Carteira abaixo do piso{itens.filter((u) => !u.carteira.ok).length === itens.length ? ' em todas as unidades' : ` em ${itens.filter((u) => !u.carteira.ok).map((u) => u.unidade).join(' e ')}`}:
                  conquistas entram com fator {primeiro?.carteira.fator ?? 0.8} e o bolo não é liberado
                  {' '}(seria {itens.filter((u) => !u.carteira.ok).map((u) => `${real(u.operadoras[0]?.bolo_se_liberado ?? 0)} por operadora em ${u.unidade}`).join('; ')}).{' '}
                </>
              )}
              Sem contato prévio ("veio sozinho"):{' '}
              {itens.map((u) => `${u.unidade} ${num(u.veio_sozinho.afericoes)} aferições / ${num(u.veio_sozinho.pontos)} pontos`).join(' · ')}.
              {simulado && ` Mês de observação em ${itens.filter((u) => u.simulado).map((u) => u.unidade).join(' e ')}: os valores são simulação com a regra seguinte, não pagamento.`}
            </p>
            <ObservacaoCritica itens={itens} competencia={competencia} />
            {itens.some((u) => u.observacao) && (
              <p className="text-xs text-ink-6">
                {itens.filter((u) => u.observacao).map((u) => `${u.unidade}: ${u.observacao}`).join(' · ')}
              </p>
            )}
          </div>
        </>
      )}
    </div>
  )
}

function UnidadeLinhas({ r }: { r: Resultado }) {
  const ops = r.operadoras
  const linhas = ops.length === 0 ? [null] : ops
  return (
    <>
      {linhas.map((o, i) => (
        <tr key={o?.nome ?? 'vazio'} className={`border-b border-line ${i === 0 ? '' : ''}`}>
          <td className="px-5 py-3 font-bold text-ink align-top">{i === 0 ? r.unidade : ''}</td>
          {o ? (
            <>
              <td className={`px-3 py-3 ${o.anulada ? 'line-through text-rose-300' : 'text-ink'}`}>
                {o.nome}
                {o.anulada && <span className="ml-2 badge bg-rose-500/15 text-rose-300 border-rose-500/30">anulada</span>}
              </td>
              <td className="px-3 py-3 text-right tabular-nums">{num(o.afericoes)}</td>
              <td className="px-3 py-3 text-right tabular-nums">{num(o.brutos)}</td>
              <td className="px-3 py-3 text-right tabular-nums">{num(o.finais)}{o.finais !== o.brutos && '*'}</td>
              <td className="px-3 py-3 text-right tabular-nums">{real(o.individual)}</td>
              <td className={`px-3 py-3 text-right tabular-nums ${r.bolo_liberado ? '' : 'text-rose-300'}`}>{real(o.bolo)}</td>
              <td className="px-5 py-3 text-right tabular-nums font-extrabold text-ink">{real(o.total)}</td>
            </>
          ) : (
            <td colSpan={7} className="px-3 py-3 text-ink-4">Nenhuma aferição pontuada neste mês.</td>
          )}
        </tr>
      ))}
      {/* A linha do bolo da unidade: liberado ou não, e quanto seria */}
      <tr className="border-b border-line bg-white/[0.02]">
        <td className="px-5 py-2" />
        <td className="px-3 py-2 text-xs italic text-ink-4" colSpan={5}>Bolo da unidade</td>
        <td className="px-3 py-2 text-right text-xs tabular-nums">
          {r.bolo === null ? '—' : r.bolo_liberado ? (
            <span className="text-emerald-300">{real(r.bolo)} liberado</span>
          ) : (
            <span className="text-rose-300">
              <span className="line-through text-ink-4">{real(r.bolo)}</span> → {real(0)}
            </span>
          )}
        </td>
        <td className="px-5 py-2 text-right text-xs">
          {r.bolo !== null && !r.bolo_liberado && (
            <span className="badge bg-rose-500/15 text-rose-300 border-rose-500/30">não liberado</span>
          )}
        </td>
      </tr>
    </>
  )
}

// A regra é DA UNIDADE: cada linha mostra a sua (valor, teto, bolo) e se é simulação.
function Regra({ r }: { r: Resultado }) {
  const g = r.regra
  if (g.valor_ponto === null) return <span className="text-ink-4 text-xs">sem regra que pague — só os pontos</span>
  return (
    <div className="text-xs text-ink-6 leading-snug">
      <span className="text-ink font-semibold">{real(g.valor_ponto)}</span>/ponto
      {g.teto_mes !== null && <> · teto <span className="text-ink font-semibold">{real(g.teto_mes)}</span></>}
      {' '}· {100 - g.pct_bolo}% individual · {g.pct_bolo}% bolo
      {r.simulado && (
        <span className="block text-amber-300">simulação com a regra de {g.vigencia ? rotuloCurto(g.vigencia) : '—'}</span>
      )}
    </div>
  )
}

function Carteira({ c }: { c: Resultado['carteira'] }) {
  if (c.pct === null) return <span className="text-ink-4 text-xs">sem cliente nosso vencendo no mês</span>
  const cor = c.ok ? 'bg-emerald-500' : c.pct >= c.piso / 2 ? 'bg-amber-500' : 'bg-rose-500'
  return (
    <div className="flex items-center gap-3 min-w-52">
      <div className="relative h-2 w-28 rounded-full bg-line overflow-hidden shrink-0">
        <div className={`h-full rounded-full ${cor}`} style={{ width: `${Math.max(Math.min(c.pct, 100), 2)}%` }} />
        <div className="absolute top-0 h-full w-px bg-ink-4" style={{ left: `${c.piso}%` }} title={`piso ${c.piso}%`} />
      </div>
      <span className="text-xs tabular-nums text-ink-6">
        <b className={c.ok ? 'text-emerald-300' : 'text-rose-300'}>{c.pct}%</b>
        {c.renovaram !== null && c.venciam !== null && <> — {num(c.renovaram)} renovaram de {num(c.venciam)}</>}
      </span>
    </div>
  )
}

// A observação crítica, escrita a partir dos números: quantos clientes nossos
// venceram e não renovaram. É o que o Emerson pôs em vermelho no quadro dele.
function ObservacaoCritica({ itens, competencia }: { itens: Resultado[]; competencia: string }) {
  const comDado = itens.filter((u) => u.carteira.nao_renovaram !== null && u.carteira.venciam !== null && (u.carteira.venciam ?? 0) > 0)
  if (comDado.length === 0) return null
  const perdidos = comDado.reduce((s, u) => s + (u.carteira.nao_renovaram ?? 0), 0)
  if (perdidos === 0) return null
  const abaixo = comDado.filter((u) => !u.carteira.ok)
  return (
    <div className="rounded-xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-xs text-ink-6 leading-relaxed">
      <b className="text-rose-300">Observação crítica — carteira da casa que não renovou.</b>{' '}
      Em {rotulo(competencia)},{' '}
      {comDado
        .map((u) => (
          <span key={u.unidade}>
            <b className="text-ink">{num(u.carteira.nao_renovaram ?? 0)}</b> clientes nossos de <b className="text-ink">{u.unidade}</b> venceram e
            não renovaram conosco ({num(u.carteira.renovaram ?? 0)} de {num(u.carteira.venciam ?? 0)} renovaram)
          </span>
        ))
        .reduce<ReactNode[]>((acc, el, i) => (i === 0 ? [el] : [...acc, i === comDado.length - 1 ? ' e ' : ', ', el]), [])}
      . São caminhões que já eram da casa, com vencimento conhecido, e que ninguém ligou a tempo
      {abaixo.length > 0 && <> — é por isso que o bolo não saiu em {abaixo.map((u) => u.unidade).join(' e ')}</>}.
      A conquista do mês não compensa o que vazou: o prêmio do mês seguinte depende, antes de tudo, de defender essa carteira.
    </div>
  )
}
