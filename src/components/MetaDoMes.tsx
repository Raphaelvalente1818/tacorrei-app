import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { ChevronLeft, ChevronRight, ShieldAlert, Target, Trophy } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/AuthContext'

// ── Meta do mês ──────────────────────────────────────────────────────────────
// A composição da meta em detalhe, para o admin da unidade e o admin geral.
// Recompensa por RESULTADO (aferição no nosso posto), nunca por esforço. Cada
// ponto aqui tem origem: a placa, o que o caminhão era antes de vir, quem fez
// o contato que o trouxe e quando. Sem origem, não é ponto — é "veio sozinho".
//
// Fase 1 (três meses): sem meta numérica. A tela mostra o UNIVERSO do mês —
// o que existia para trabalhar — para a meta da fase 2 nascer dele, e não do
// mês anterior.

type Classe =
  | 'conquista_mista'
  | 'conquista_virgem'
  | 'conquista_avulso'
  | 'vencido'
  | 'renovacao'
  | 'contrato'

type Parametros = {
  conquista_mista: number
  conquista_virgem: number
  conquista_avulso: number
  vencido: number
  renovacao: number
  contrato: number
  bonus_empresa: number
  janela_atribuicao_dias: number
  carencia_vencido_dias: number
  piso_carteira_pct: number
  fator_carteira: number
}

type Realizado = {
  operadora_id: string | null
  nome: string
  papel: string
  afericoes: number
  pontos: number
  bonus: number
  total: number
  conquista_mista: number
  conquista_virgem: number
  conquista_avulso: number
  vencido: number
  renovacao: number
  contrato: number
  empresas_conquistadas: number
}

type Detalhe = {
  id: string
  data_afericao: string
  registrado_em: string
  classe: Classe
  pontos: number
  bonus: number
  empresa_conquistada: boolean
  origem: 'app' | 'retroativo'
  posto_anterior: string | null
  venc_anterior: string | null
  placa: string | null
  dono: string | null
  empresa: string | null
  operadora: string | null
  contato_em: string | null
  contato_canal: string | null
  contato_alvo: 'empresa' | 'placa' | null
}

type Auditoria = {
  id: string
  data_afericao: string
  placa: string | null
  dono: string | null
  empresa: string | null
  classe: Classe
  total: number
  operadora: string | null
}

type Meta = {
  competencia: string
  unidade: { id: string; nome: string; posto: string | null }
  parametros: Parametros
  universo: {
    vencem_no_mes: {
      contrato: number
      nossos: number
      concorrente_mista: number
      concorrente_virgem: number
      concorrente_avulso: number
      total: number
    }
    vencidos_recuperaveis: number
    vencidos_frios: number
    empresas_pe_na_porta: number
  }
  realizado: Realizado[]
  detalhe: Detalhe[]
  carteira: {
    renovados: number
    pendentes: number
    pct_defendida: number | null
    piso_pct: number
    fator: number
    mes_fechado: boolean
  }
  risco: {
    nossos_90d: number
    atrasados: number
    empresas: { nome: string; em_risco: number }[]
  }
  auditoria: Auditoria[]
}

const CLASSE_LABEL: Record<Classe, string> = {
  conquista_mista: 'Conquista · pé na porta',
  conquista_virgem: 'Conquista · empresa nova',
  conquista_avulso: 'Conquista · autônomo',
  vencido: 'Vencido que voltou',
  renovacao: 'Renovação',
  contrato: 'Frota com contrato',
}

const CLASSE_COR: Record<Classe, string> = {
  conquista_mista: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
  conquista_virgem: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
  conquista_avulso: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
  vencido: 'bg-rose-500/15 text-rose-300 border-rose-500/30',
  renovacao: 'bg-blue-500/15 text-blue-300 border-blue-500/30',
  contrato: 'bg-slate-500/15 text-slate-300 border-slate-500/30',
}

const MESES_PT = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
]

function primeiroDoMes(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

function rotuloMes(iso: string): string {
  const [a, m] = iso.split('-')
  return `${MESES_PT[Number(m) - 1]} de ${a}`
}

function fmtDia(iso: string | null): string {
  if (!iso) return '—'
  const [a, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${a}`
}

function fmtDataHora(iso: string | null): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
}

function num(n: number | null | undefined): string {
  return Number(n ?? 0).toLocaleString('pt-BR')
}

export default function MetaDoMes() {
  const { membro, unidades, unidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'

  // O admin geral pode estar em "Todas as unidades"; a meta é por unidade,
  // então aqui ele escolhe. O admin de unidade não escolhe nada.
  const [unidadeEscolhida, setUnidadeEscolhida] = useState<string | null>(null)
  const unidadeId = isAdmin
    ? (unidadeAtiva ?? unidadeEscolhida ?? unidades[0]?.id ?? null)
    : (membro?.unidade_id ?? null)

  const [competencia, setCompetencia] = useState(() => primeiroDoMes(new Date()))
  const [meta, setMeta] = useState<Meta | null>(null)
  const [loading, setLoading] = useState(true)
  const [erro, setErro] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    if (!unidadeId) return
    setLoading(true)
    setErro(null)
    const { data, error } = await supabase.rpc('meta_do_mes', {
      p_unidade: unidadeId,
      p_competencia: competencia,
    })
    setLoading(false)
    if (error) {
      setErro(error.message)
      return
    }
    setMeta(data as Meta)
  }, [unidadeId, competencia])

  useEffect(() => {
    carregar()
  }, [carregar])

  function andarMes(passo: number) {
    const [a, m] = competencia.split('-').map(Number)
    setCompetencia(primeiroDoMes(new Date(a, m - 1 + passo, 1)))
  }

  // Só o que tem dona conta como ponto. O que veio sozinho aparece na tabela,
  // riscado, mas não soma para ninguém.
  const totalMes = useMemo(
    () => (meta?.realizado ?? []).filter((r) => r.operadora_id).reduce((s, r) => s + Number(r.total), 0),
    [meta]
  )
  const comAtribuicao = useMemo(
    () => (meta?.realizado ?? []).filter((r) => r.operadora_id),
    [meta]
  )
  const semAtribuicao = useMemo(
    () => (meta?.realizado ?? []).find((r) => !r.operadora_id) ?? null,
    [meta]
  )

  if (!unidadeId) {
    return (
      <div className="card p-6">
        <p className="text-sm text-ink-6">Nenhuma unidade disponível.</p>
      </div>
    )
  }

  const p = meta?.parametros
  const u = meta?.universo
  const c = meta?.carteira
  const abaixoDoPiso = c && c.pct_defendida !== null && c.pct_defendida < c.piso_pct

  return (
    <div className="space-y-6">
      {/* ── Cabeçalho: mês, unidade, fase ─────────────────────────────── */}
      <div className="card p-4 flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <button onClick={() => andarMes(-1)} className="p-2 rounded-lg border border-line text-ink-6 hover:bg-white/5" aria-label="Mês anterior">
            <ChevronLeft size={16} />
          </button>
          <span className="text-sm font-extrabold text-ink min-w-44 text-center capitalize">
            {rotuloMes(competencia)}
          </span>
          <button onClick={() => andarMes(1)} className="p-2 rounded-lg border border-line text-ink-6 hover:bg-white/5" aria-label="Próximo mês">
            <ChevronRight size={16} />
          </button>
        </div>

        <div className="flex flex-wrap items-center gap-4 text-sm">
          {isAdmin && !unidadeAtiva && unidades.length > 1 && (
            <select
              value={unidadeId}
              onChange={(e) => setUnidadeEscolhida(e.target.value)}
              className="px-3 py-2 border border-line rounded-xl text-sm font-bold bg-card focus-ring outline-none"
            >
              {unidades.map((un) => (
                <option key={un.id} value={un.id}>{un.nome}</option>
              ))}
            </select>
          )}
          {meta && (
            <span className="text-ink-6">
              <b className="text-ink">{meta.unidade.nome}</b>
            </span>
          )}
          <span className="badge bg-brand/15 text-brand border-brand/30">Fase 1 · sem meta numérica</span>
        </div>
      </div>

      {erro && (
        <p className="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3">{erro}</p>
      )}

      {loading || !meta || !p || !u || !c ? (
        <div className="card p-6"><p className="text-sm text-ink-4">Carregando…</p></div>
      ) : (
        <>
          {/* ── Placar ─────────────────────────────────────────────────── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <Cartao rotulo="Pontos no mês" valor={num(totalMes)} cor="text-brand" icone={<Trophy size={16} />} />
            <Cartao rotulo="Aferições registradas" valor={num(meta.detalhe.length)} />
            <Cartao
              rotulo="Empresas conquistadas"
              valor={num(meta.detalhe.filter((d) => d.empresa_conquistada).length)}
              cor="text-emerald-400"
            />
            <Cartao
              rotulo="Vieram sozinhos"
              valor={num(semAtribuicao?.afericoes ?? 0)}
              ajuda="Aferições sem contato registrado nos dias anteriores. Não pontuam para ninguém."
            />
          </div>

          {/* ── Como o ponto é contado ─────────────────────────────────── */}
          <div className="card p-5">
            <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
              <Target size={16} className="text-brand" /> Como o ponto é contado
            </h2>
            <p className="text-xs text-ink-4 mb-3">
              Pontua a aferição feita no nosso posto, pelo que o caminhão <b className="text-ink-6">era antes</b> de vir.
              Vai para quem registrou contato no caminhão ou na empresa dele nos{' '}
              <b className="text-ink-6">{p.janela_atribuicao_dias} dias</b> anteriores — o contato mais recente leva.
              Sem contato, ninguém pontua: o caminhão veio sozinho.
            </p>
            <div className="flex flex-wrap gap-2">
              <Regra cor={CLASSE_COR.conquista_mista} texto={`${CLASSE_LABEL.conquista_mista} · ${p.conquista_mista}`} />
              <Regra cor={CLASSE_COR.conquista_virgem} texto={`${CLASSE_LABEL.conquista_virgem} · ${p.conquista_virgem}`} />
              <Regra cor={CLASSE_COR.conquista_avulso} texto={`${CLASSE_LABEL.conquista_avulso} · ${p.conquista_avulso}`} />
              <Regra cor={CLASSE_COR.vencido} texto={`${CLASSE_LABEL.vencido} · ${p.vencido}`} />
              <Regra cor={CLASSE_COR.renovacao} texto={`${CLASSE_LABEL.renovacao} · ${p.renovacao}`} />
              <Regra cor={CLASSE_COR.contrato} texto={`${CLASSE_LABEL.contrato} · ${p.contrato}`} />
              <Regra cor="bg-brand/15 text-brand border-brand/30" texto={`Empresa conquistada · +${p.bonus_empresa}`} />
            </div>
            <p className="text-xs text-ink-4 mt-3">
              "Vencido" é certificado vencido há mais de {p.carencia_vencido_dias} dias, em qualquer posto.
              "Empresa conquistada" é o primeiro caminhão de uma empresa que não tinha nenhum conosco — uma vez por empresa, para sempre.
            </p>
          </div>

          {/* ── Universo do mês ────────────────────────────────────────── */}
          <div className="card p-5">
            <h2 className="text-sm font-extrabold text-ink mb-1">O que existia para trabalhar</h2>
            <p className="text-xs text-ink-4 mb-4">
              Caminhões com certificado vencendo em <span className="capitalize">{rotuloMes(competencia)}</span>, pelo estado atual da base. É daqui que a meta da fase 2 vai nascer.
            </p>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
              <Mini rotulo="Nossos, a renovar" valor={u.vencem_no_mes.nossos} cor="text-blue-300" />
              <Mini rotulo="Frotas com contrato" valor={u.vencem_no_mes.contrato} />
              <Mini rotulo="Concorrente · pé na porta" valor={u.vencem_no_mes.concorrente_mista} cor="text-emerald-300" />
              <Mini rotulo="Concorrente · empresa nova" valor={u.vencem_no_mes.concorrente_virgem} cor="text-amber-300" />
              <Mini rotulo="Concorrente · autônomo" valor={u.vencem_no_mes.concorrente_avulso} cor="text-amber-300" />
              <Mini rotulo="Total no mês" valor={u.vencem_no_mes.total} cor="text-ink" />
            </div>
            <div className="flex flex-wrap gap-5 mt-4 text-xs text-ink-6">
              <span><b className="text-rose-300">{num(u.vencidos_recuperaveis)}</b> vencidos recuperáveis (até 12 meses)</span>
              <span><b className="text-ink-4">{num(u.vencidos_frios)}</b> vencidos frios (mais de 12 meses)</span>
              <span><b className="text-emerald-300">{num(u.empresas_pe_na_porta)}</b> empresas pé na porta com caminhão vencendo em 90 dias</span>
            </div>
          </div>

          {/* ── Realizado por operadora ────────────────────────────────── */}
          <div className="card overflow-hidden">
            <div className="px-5 pt-5 pb-3">
              <h2 className="text-sm font-extrabold text-ink">Realizado por operadora</h2>
            </div>
            {meta.realizado.length === 0 ? (
              <p className="px-5 pb-5 text-sm text-ink-4">Nenhuma aferição registrada neste mês ainda.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-ink-4 text-xs uppercase font-bold border-y border-line">
                      <th className="px-5 py-3">Operadora</th>
                      <th className="px-3 py-3 text-right">Aferições</th>
                      <th className="px-3 py-3 text-right" title="Pé na porta / empresa nova / autônomo">Conquistas</th>
                      <th className="px-3 py-3 text-right">Vencidos</th>
                      <th className="px-3 py-3 text-right">Renov.</th>
                      <th className="px-3 py-3 text-right">Contrato</th>
                      <th className="px-3 py-3 text-right">Empresas</th>
                      <th className="px-3 py-3 text-right">Pontos</th>
                      <th className="px-3 py-3 text-right">Bônus</th>
                      <th className="px-5 py-3 text-right">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[...comAtribuicao, ...(semAtribuicao ? [semAtribuicao] : [])].map((r) => (
                      <tr key={r.operadora_id ?? 'sem'} className={`border-b border-line last:border-0 ${r.operadora_id ? '' : 'text-ink-4'}`}>
                        <td className="px-5 py-3 font-semibold text-ink">
                          {r.nome}
                          {r.papel && r.papel !== 'operador' && (
                            <span className="ml-2 text-xs text-ink-4 font-normal">{r.papel.replace('_', ' ')}</span>
                          )}
                        </td>
                        <td className="px-3 py-3 text-right tabular-nums">{num(r.afericoes)}</td>
                        <td className="px-3 py-3 text-right tabular-nums">
                          <span className="text-emerald-300">{num(r.conquista_mista)}</span>
                          <span className="text-ink-4"> / </span>
                          <span className="text-amber-300">{num(r.conquista_virgem)}</span>
                          <span className="text-ink-4"> / </span>
                          <span className="text-amber-300">{num(r.conquista_avulso)}</span>
                        </td>
                        <td className="px-3 py-3 text-right tabular-nums">{num(r.vencido)}</td>
                        <td className="px-3 py-3 text-right tabular-nums">{num(r.renovacao)}</td>
                        <td className="px-3 py-3 text-right tabular-nums">{num(r.contrato)}</td>
                        <td className="px-3 py-3 text-right tabular-nums text-emerald-300">{num(r.empresas_conquistadas)}</td>
                        <td className="px-3 py-3 text-right tabular-nums">{num(r.pontos)}</td>
                        <td className="px-3 py-3 text-right tabular-nums">{num(r.bonus)}</td>
                        <td className={`px-5 py-3 text-right tabular-nums font-extrabold ${r.operadora_id ? 'text-brand' : ''}`}>
                          {num(r.total)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* ── Carteira defendida + risco ─────────────────────────────── */}
          <div className="grid md:grid-cols-2 gap-4">
            <div className={`card p-5 ${abaixoDoPiso && c.mes_fechado ? 'border-rose-500/40' : ''}`}>
              <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
                <ShieldAlert size={16} className={abaixoDoPiso ? 'text-rose-400' : 'text-brand'} /> Carteira defendida
              </h2>
              <p className="text-xs text-ink-4 mb-3">
                Não adianta caçar caminhão novo deixando vazar o que já é nosso. Abaixo de {c.piso_pct}%, os pontos de conquista do mês entram com fator {String(c.fator).replace('.', ',')}.
              </p>
              <div className="flex items-end gap-6">
                <div>
                  <div className={`text-3xl font-extrabold tabular-nums ${abaixoDoPiso ? 'text-rose-400' : 'text-emerald-400'}`}>
                    {c.pct_defendida === null ? '—' : `${c.pct_defendida}%`}
                  </div>
                  <div className="text-xs text-ink-4">renovaram conosco</div>
                </div>
                <div className="text-xs text-ink-6 space-y-1">
                  <div><b className="text-ink">{num(c.renovados)}</b> renovados no mês</div>
                  <div>
                    <b className="text-ink">{num(c.pendentes)}</b>{' '}
                    {c.mes_fechado ? 'venceram e não voltaram' : 'vencem no mês e ainda não voltaram'}
                  </div>
                </div>
              </div>
            </div>

            <div className="card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-1">O que pode vazar</h2>
              <p className="text-xs text-ink-4 mb-3">
                Caminhões nossos, em empresas sem contrato, vencendo nos próximos 90 dias — a ligação de defesa vale tanto quanto a de conquista.
              </p>
              <div className="flex gap-6 mb-3">
                <div>
                  <div className="text-2xl font-extrabold tabular-nums text-amber-300">{num(meta.risco.nossos_90d)}</div>
                  <div className="text-xs text-ink-4">vencem em 90 dias</div>
                </div>
                <div>
                  <div className="text-2xl font-extrabold tabular-nums text-rose-400">{num(meta.risco.atrasados)}</div>
                  <div className="text-xs text-ink-4">já atrasados (+30 dias)</div>
                </div>
              </div>
              {meta.risco.empresas.length > 0 && (
                <ul className="text-xs text-ink-6 space-y-1">
                  {meta.risco.empresas.slice(0, 6).map((e) => (
                    <li key={e.nome} className="flex justify-between gap-3">
                      <span className="truncate">{e.nome}</span>
                      <b className="text-rose-300 tabular-nums shrink-0">{num(e.em_risco)}</b>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>

          {/* ── Detalhe: a origem de cada ponto ────────────────────────── */}
          <div className="card overflow-hidden">
            <div className="px-5 pt-5 pb-3">
              <h2 className="text-sm font-extrabold text-ink">A origem de cada ponto</h2>
              <p className="text-xs text-ink-4">O que o caminhão era antes de vir, e o contato que o trouxe.</p>
            </div>
            {meta.detalhe.length === 0 ? (
              <p className="px-5 pb-5 text-sm text-ink-4">Nada registrado neste mês.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-ink-4 text-xs uppercase font-bold border-y border-line">
                      <th className="px-5 py-3">Aferição</th>
                      <th className="px-3 py-3">Placa</th>
                      <th className="px-3 py-3">Quem</th>
                      <th className="px-3 py-3">Era</th>
                      <th className="px-3 py-3">Contato que trouxe</th>
                      <th className="px-3 py-3">Operadora</th>
                      <th className="px-5 py-3 text-right">Pontos</th>
                    </tr>
                  </thead>
                  <tbody>
                    {meta.detalhe.map((d) => (
                      <tr key={d.id} className="border-b border-line last:border-0 align-top">
                        <td className="px-5 py-3 text-ink-6 whitespace-nowrap">
                          {fmtDia(d.data_afericao)}
                          {d.origem === 'retroativo' && (
                            <span className="block text-[10px] text-ink-4" title="Pontuado depois, com o estado que o caminhão tinha na base">retroativo</span>
                          )}
                        </td>
                        <td className="px-3 py-3 font-mono font-bold text-ink">{d.placa ?? '—'}</td>
                        <td className="px-3 py-3 text-ink-6 max-w-56">
                          <span className="block truncate">{d.empresa ?? d.dono ?? '—'}</span>
                          {d.empresa && d.dono && <span className="block text-xs text-ink-4 truncate">{d.dono}</span>}
                        </td>
                        <td className="px-3 py-3">
                          <span className={`badge ${CLASSE_COR[d.classe]}`}>{CLASSE_LABEL[d.classe]}</span>
                          {d.empresa_conquistada && (
                            <span className="badge bg-brand/15 text-brand border-brand/30 ml-1">empresa conquistada</span>
                          )}
                          <span className="block text-xs text-ink-4 mt-1">
                            {d.posto_anterior ? d.posto_anterior.slice(0, 28) : 'posto desconhecido'}
                            {d.venc_anterior ? ` · vencia ${fmtDia(d.venc_anterior)}` : ''}
                          </span>
                        </td>
                        <td className="px-3 py-3 text-xs text-ink-6 whitespace-nowrap">
                          {d.contato_em ? (
                            <>
                              {fmtDataHora(d.contato_em)}
                              <span className="block text-ink-4">
                                {d.contato_canal === 'whatsapp' ? 'WhatsApp' : 'ligação'}
                                {d.contato_alvo === 'empresa' ? ' · com a empresa' : ''}
                              </span>
                            </>
                          ) : (
                            <span className="text-ink-4">veio sozinho</span>
                          )}
                        </td>
                        <td className="px-3 py-3 text-ink-6 whitespace-nowrap">{d.operadora ?? '—'}</td>
                        <td className="px-5 py-3 text-right tabular-nums font-extrabold whitespace-nowrap">
                          <span className={d.operadora ? 'text-brand' : 'text-ink-4 line-through'}>
                            {num(d.pontos)}{d.bonus > 0 ? ` +${num(d.bonus)}` : ''}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* ── Auditoria ──────────────────────────────────────────────── */}
          {meta.auditoria.length > 0 && (
            <div className="card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-1">Auditoria do mês</h2>
              <p className="text-xs text-ink-4 mb-3">
                {meta.auditoria.length} aferições sorteadas — sempre as mesmas para este mês. Conferir cada uma contra a ordem de serviço do posto. Um registro falso anula o mês inteiro da operadora.
              </p>
              <ul className="grid md:grid-cols-2 gap-x-6 gap-y-1.5 text-xs">
                {meta.auditoria.map((a, i) => (
                  <li key={a.id} className="flex items-baseline gap-2 text-ink-6">
                    <span className="text-ink-4 tabular-nums w-4 shrink-0">{i + 1}.</span>
                    <span className="font-mono font-bold text-ink">{a.placa ?? '—'}</span>
                    <span className="truncate">{a.empresa ?? a.dono ?? ''}</span>
                    <span className="text-ink-4 shrink-0">{fmtDia(a.data_afericao)}</span>
                    <span className="text-ink-4 shrink-0">{a.operadora ?? 'sem atribuição'}</span>
                    <span className="text-brand tabular-nums shrink-0">{num(a.total)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}
    </div>
  )
}

function Cartao({ rotulo, valor, cor, icone, ajuda }: { rotulo: string; valor: string; cor?: string; icone?: ReactNode; ajuda?: string }) {
  return (
    <div className="card p-4" title={ajuda}>
      <div className="text-[11px] font-bold uppercase tracking-wide text-ink-4 flex items-center gap-1.5">
        {icone}{rotulo}
      </div>
      <div className={`text-2xl font-extrabold tabular-nums mt-1 ${cor ?? 'text-ink'}`}>{valor}</div>
    </div>
  )
}

function Mini({ rotulo, valor, cor }: { rotulo: string; valor: number; cor?: string }) {
  return (
    <div className="rounded-xl border border-line bg-card/60 px-3 py-2.5">
      <div className={`text-xl font-extrabold tabular-nums ${cor ?? 'text-ink-6'}`}>{num(valor)}</div>
      <div className="text-[11px] text-ink-4 leading-tight">{rotulo}</div>
    </div>
  )
}

function Regra({ cor, texto }: { cor: string; texto: string }) {
  return <span className={`badge ${cor}`}>{texto}</span>
}
