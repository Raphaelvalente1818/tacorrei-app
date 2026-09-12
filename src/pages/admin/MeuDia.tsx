import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { ClipboardCheck, DoorOpen, ListChecks, ShieldCheck, Trophy } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { num } from './ui'

// ── Meu dia ──────────────────────────────────────────────────────────────────
// A rotina de 10 minutos do manual do gestor, em tela. Quatro perguntas, nada mais:
//   1. Quantos pontos cada operadora fez até ontem?
//   2. Quais empresas "pé na porta" estão sem contato há mais de 7 dias?
//   3. Quantos "Novo" ainda restam na fila do mês?
//   4. O que foi marcado como aferido ontem — confere com as ordens de serviço?
// A quarta é a única que o app não responde sozinho: ele mostra o que foi marcado,
// o gestor bate com o caderno da oficina. É a auditoria diária, barata.
//
// Modo 'operadora' (0089): a mesma tela, em primeira pessoa — é a tela inicial dela.
// Troca dois cartões: o 1 mostra só os pontos dela e o total da unidade (nada de placar
// entre colegas: o método não quer uma torcendo contra a outra), e o 4 vira a defesa da
// carteira — nossos que vencem em 30 dias e ninguém ligou. Os cartões 2 e 3 são iguais.

type MeuDia = {
  hoje: string
  competencia: string
  pontos?: { nome: string; operadora_id: string; pontos: number; ontem: number; afericoes: number }[]
  eu?: { pontos: number; ontem: number; afericoes: number; empresas: number; unidade: number }
  pe_na_porta: { id: string; nome: string; janela: number; ultima_abordagem: string | null }[]
  pe_na_porta_total: number
  fila: { novos: number; total: number }
  aferidos_ontem?: { placa: string | null; dono: string | null; empresa: string | null; operadora: string | null; marcado_por: string | null; total: number }[]
  defesa?: { total: number; sem_contato: number; lista: { id: string; placa: string | null; dono: string | null; empresa: string | null; venc: string }[] }
}

function fmtDia(iso: string): string {
  const [a, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${a}`
}

function diasAtras(iso: string | null): string {
  if (!iso) return 'nunca'
  const d = Math.floor((Date.now() - new Date(iso).getTime()) / 86400000)
  return d === 0 ? 'hoje' : d === 1 ? 'ontem' : `há ${d} dias`
}

export default function MeuDia({ unidadeId, modo = 'gestor' }: { unidadeId: string | null; modo?: 'gestor' | 'operadora' }) {
  const [dia, setDia] = useState<MeuDia | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const operadora = modo === 'operadora'

  const carregar = useCallback(async () => {
    setErro(null)
    const { data, error } = operadora
      ? await supabase.rpc('meu_dia_operadora')
      : await supabase.rpc('meu_dia', { p_unidade: unidadeId })
    if (error) {
      setErro(error.message)
      return
    }
    setDia(data as MeuDia)
  }, [unidadeId, operadora])

  useEffect(() => {
    carregar()
  }, [carregar])

  if (erro) return <p className="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3">{erro}</p>
  if (!dia) return <p className="text-sm text-ink-4">Carregando…</p>

  const pontos = dia.pontos ?? []
  const totalPontos = pontos.reduce((s, p) => s + p.pontos, 0)

  return (
    <div className="grid md:grid-cols-2 gap-4">
      {/* 1. Pontos — o gestor vê a equipe; a operadora vê só a si e o total da unidade */}
      {operadora && dia.eu ? (
        <div className="card p-5">
          <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
            <Trophy size={16} className="text-brand" /> 1. Meus pontos no mês
          </h2>
          <p className="text-xs text-ink-4 mb-3">Só aferição no nosso posto pontua — pelo que o caminhão era antes de vir. A origem de cada ponto está no Meu placar.</p>
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-xl border border-line bg-card/60 px-3 py-2.5">
              <div className="text-2xl font-extrabold tabular-nums text-brand">{num(dia.eu.pontos)}</div>
              <div className="text-[11px] text-ink-4">meus pontos {dia.eu.ontem > 0 ? <span className="text-emerald-300">· +{num(dia.eu.ontem)} ontem</span> : ''}</div>
            </div>
            <div className="rounded-xl border border-line bg-card/60 px-3 py-2.5">
              <div className="text-2xl font-extrabold tabular-nums text-ink">{num(dia.eu.afericoes)}</div>
              <div className="text-[11px] text-ink-4">minhas aferições {dia.eu.empresas > 0 ? `· ${num(dia.eu.empresas)} empresa${dia.eu.empresas > 1 ? 's' : ''} conquistada${dia.eu.empresas > 1 ? 's' : ''}` : ''}</div>
            </div>
            <div className="rounded-xl border border-line bg-card/60 px-3 py-2.5 col-span-2">
              <div className="text-xl font-extrabold tabular-nums text-ink-6">{num(dia.eu.unidade)}</div>
              <div className="text-[11px] text-ink-4">pontos da unidade no mês — o bolo comum é sobre isso</div>
            </div>
          </div>
          <p className="text-xs text-ink-4 mt-3">
            <Link to="/placar" className="text-brand font-bold hover:underline">Abrir o Meu placar →</Link>
          </p>
        </div>
      ) : (
      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
          <Trophy size={16} className="text-brand" /> 1. Pontos no mês, por operadora
        </h2>
        <p className="text-xs text-ink-4 mb-3">Só aferição no nosso posto pontua. Quem está parada há dias precisa de conversa, não de cobrança.</p>
        {pontos.length === 0 ? (
          <p className="text-sm text-ink-4">Nenhuma operadora ativa nesta unidade.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="py-2">Operadora</th>
                <th className="py-2 text-right">Pontos</th>
                <th className="py-2 text-right">Ontem</th>
                <th className="py-2 text-right">Aferições</th>
              </tr>
            </thead>
            <tbody>
              {pontos.map((p) => (
                <tr key={p.operadora_id} className="border-b border-line last:border-0">
                  <td className="py-2 font-semibold text-ink">{p.nome}</td>
                  <td className="py-2 text-right tabular-nums font-extrabold text-brand">{num(p.pontos)}</td>
                  <td className={`py-2 text-right tabular-nums ${p.ontem > 0 ? 'text-emerald-300' : 'text-ink-4'}`}>{p.ontem > 0 ? `+${num(p.ontem)}` : '0'}</td>
                  <td className="py-2 text-right tabular-nums text-ink-6">{num(p.afericoes)}</td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="text-xs text-ink-4">
                <td className="pt-2">Unidade</td>
                <td className="pt-2 text-right tabular-nums font-bold text-ink">{num(totalPontos)}</td>
                <td colSpan={2}></td>
              </tr>
            </tfoot>
          </table>
        )}
      </div>
      )}

      {/* 2. Pé na porta */}
      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
          <DoorOpen size={16} className="text-emerald-400" /> 2. Pé na porta sem contato há mais de 7 dias
        </h2>
        <p className="text-xs text-ink-4 mb-3">
          {operadora
            ? 'Empresas que já aferem conosco e têm caminhão do concorrente vencendo em 90 dias. Comece o dia por aqui: é a ligação mais barata que existe — "já cuidamos do X de vocês".'
            : 'Empresas que já aferem conosco e têm caminhão do concorrente vencendo em 90 dias. É a ligação mais barata que existe.'}
        </p>
        {dia.pe_na_porta.length === 0 ? (
          (dia.pe_na_porta_total ?? 0) === 0 ? (
            <p className="text-sm text-ink-6">Nenhuma empresa pé na porta com caminhão vencendo em 90 dias nesta unidade.</p>
          ) : (
            <p className="text-sm text-emerald-300">Todas as {num(dia.pe_na_porta_total)} pé na porta com caminhão vencendo foram abordadas nos últimos 7 dias.</p>
          )
        ) : (
          <>
            <ul className="text-sm space-y-1.5">
              {dia.pe_na_porta.slice(0, 8).map((e) => (
                <li key={e.id} className="flex items-center justify-between gap-3">
                  <span className="truncate text-ink">{e.nome}</span>
                  <span className="text-xs text-ink-4 shrink-0">
                    <b className="text-amber-300 tabular-nums">{num(e.janela)}</b> em 90d · {diasAtras(e.ultima_abordagem)}
                  </span>
                </li>
              ))}
            </ul>
            <p className="text-xs text-ink-4 mt-3">
              {dia.pe_na_porta.length > 8 ? `E mais ${dia.pe_na_porta.length - 8}. ` : ''}
              <Link to="/empresas" className="text-brand font-bold hover:underline">Abrir a fila de empresas →</Link>
            </p>
          </>
        )}
      </div>

      {/* 3. Novos na fila */}
      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
          <ListChecks size={16} className="text-blue-300" /> 3. "Novo" que ainda restam na fila do mês
        </h2>
        <p className="text-xs text-ink-4 mb-3">{operadora ? 'Caminhões que vencem neste mês (ou já venceram) e ninguém tocou ainda. É o seu estoque da semana.' : 'Caminhões que vencem neste mês (ou já venceram) e ninguém tocou. No fim do mês, isto tem de estar perto de zero.'}</p>
        <div className="flex items-end gap-4">
          <div>
            <div className={`text-3xl font-extrabold tabular-nums ${dia.fila.novos > 0 ? 'text-amber-300' : 'text-emerald-400'}`}>{num(dia.fila.novos)}</div>
            <div className="text-xs text-ink-4">sem nenhum contato</div>
          </div>
          <div className="text-xs text-ink-6 pb-1">
            de <b className="text-ink">{num(dia.fila.total)}</b> na fila do mês
            {dia.fila.total > 0 && <> · <b className="text-ink">{Math.round(100 * (dia.fila.total - dia.fila.novos) / dia.fila.total)}%</b> já tocados</>}
          </div>
        </div>
        <p className="text-xs text-ink-4 mt-3">
          <Link to="/leads" className="text-brand font-bold hover:underline">Abrir a fila →</Link>
        </p>
      </div>

      {/* 4. Gestor: aferidos de ontem × OS. Operadora: a defesa da carteira. */}
      {operadora && dia.defesa ? (
        <div className="card p-5">
          <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
            <ShieldCheck size={16} className="text-blue-300" /> 4. Nossos que vencem em 30 dias e ninguém ligou
          </h2>
          <p className="text-xs text-ink-4 mb-3">
            Cliente da casa não dá ponto de conquista, mas é quem paga a conta — e se ele vencer sem um lembrete nosso, o concorrente liga primeiro. A renovação pontua, e a carteira defendida abaixo de 60% tira o bolo de todo mundo.
          </p>
          {dia.defesa.total === 0 ? (
            <p className="text-sm text-ink-6">Nenhum cliente nosso vence nos próximos 30 dias.</p>
          ) : dia.defesa.sem_contato === 0 ? (
            <p className="text-sm text-emerald-300">Todos os {num(dia.defesa.total)} clientes nossos que vencem em 30 dias já receberam contato.</p>
          ) : (
            <>
              <div className="flex items-end gap-3 mb-2">
                <div className="text-3xl font-extrabold tabular-nums text-amber-300">{num(dia.defesa.sem_contato)}</div>
                <div className="text-xs text-ink-6 pb-1">de <b className="text-ink">{num(dia.defesa.total)}</b> ainda sem lembrete</div>
              </div>
              <ul className="text-sm space-y-1.5">
                {dia.defesa.lista.slice(0, 8).map((d) => (
                  <li key={d.id} className="flex items-center justify-between gap-3">
                    <Link to={`/leads/${d.id}`} className="truncate hover:underline">
                      <span className="font-mono font-bold text-ink">{d.placa ?? '—'}</span>
                      <span className="text-ink-6"> · {d.empresa ?? d.dono ?? ''}</span>
                    </Link>
                    <span className="text-xs text-ink-4 shrink-0">vence {fmtDia(d.venc)}</span>
                  </li>
                ))}
              </ul>
              {dia.defesa.lista.length > 8 && <p className="text-xs text-ink-4 mt-2">E mais {num(dia.defesa.lista.length - 8)} — estão na fila, ordenados por vencimento.</p>}
            </>
          )}
        </div>
      ) : (
      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink mb-1 flex items-center gap-2">
          <ClipboardCheck size={16} className="text-amber-300" /> 4. Marcados como aferidos ontem
        </h2>
        <p className="text-xs text-ink-4 mb-3">
          Bata esta lista com as ordens de serviço de ontem. Caminhão que passou pelo posto e não está aqui: alguém esqueceu de marcar. Está aqui e não passou: conversa séria.
        </p>
        {(dia.aferidos_ontem ?? []).length === 0 ? (
          <p className="text-sm text-ink-6">Nenhum aferido marcado ontem. Se houve caminhão no posto, falta registro.</p>
        ) : (
          <ul className="text-sm space-y-1.5">
            {(dia.aferidos_ontem ?? []).map((a, i) => (
              <li key={i} className="flex items-center justify-between gap-3">
                <span className="truncate">
                  <span className="font-mono font-bold text-ink">{a.placa ?? '—'}</span>
                  <span className="text-ink-6"> · {a.empresa ?? a.dono ?? ''}</span>
                </span>
                <span className="text-xs text-ink-4 shrink-0">
                  {a.operadora ?? 'veio sozinho'}{a.marcado_por && a.marcado_por !== a.operadora ? ` · marcou: ${a.marcado_por}` : ''}
                  {' '}· <b className="text-brand tabular-nums">{num(a.total)}</b>
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
      )}
    </div>
  )
}
