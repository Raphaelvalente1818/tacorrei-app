import { useEffect, useState } from 'react'
import { Bar, BarChart, CartesianGrid, LabelList, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { Users, PhoneCall, CalendarClock, CheckCircle2, Trophy } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useFiltroUnidade } from '../lib/AuthContext'
import type { StatusLead } from '../lib/database.types'

const FUNIL_ORDEM: Array<{ status: StatusLead; label: string }> = [
  { status: 'novo', label: 'Novos' },
  { status: 'mensagem_enviada', label: 'Mensagem enviada' },
  { status: 'contatado', label: 'Contatados' },
  { status: 'agendado', label: 'Agendados' },
  { status: 'aferido', label: 'Aferidos' },
]

// ── Placar entre unidades ────────────────────────────────────────────────────
// Mensagens de WhatsApp enviadas no mês corrente, por unidade. Vem da RPC
// `placar_unidades()`, que é SECURITY DEFINER e devolve SÓ os totais agregados —
// por isso a operadora de uma unidade vê o número da outra sem enxergar lead algum.
type PlacarItem = { unidade: string; total: number; sua: boolean }

const MEDALHAS = ['🥇', '🥈', '🥉']

function Placar() {
  const [itens, setItens] = useState<PlacarItem[]>([])

  useEffect(() => {
    let cancelado = false
    supabase.rpc('placar_unidades').then(({ data, error }) => {
      if (cancelado || error) return
      setItens((data as PlacarItem[]) ?? [])
    })
    return () => {
      cancelado = true
    }
  }, [])

  // Enquanto ninguém enviou nada no mês, o placar zerado não motiva — some.
  if (itens.length < 2 || itens.every((i) => i.total === 0)) return null

  const lider = itens[0].total

  return (
    <div className="card p-5 mb-6">
      <div className="flex items-center gap-2 mb-4">
        <Trophy size={16} className="text-lucro" strokeWidth={2.3} />
        <span className="text-xs font-bold uppercase tracking-wide text-ink-4">
          Mensagens enviadas em {mesAtual()}
        </span>
      </div>

      <div className="flex flex-col gap-3">
        {itens.map((item, i) => (
          <div key={item.unidade} className="flex items-center gap-3">
            <span className="w-6 text-center text-base leading-none">
              {MEDALHAS[i] ?? <span className="text-ink-4 text-xs font-bold">{i + 1}º</span>}
            </span>

            <div className="flex-1 min-w-0">
              <div className="flex items-baseline justify-between gap-2 mb-1">
                <span className={`text-sm font-bold truncate ${item.sua ? 'text-lucro' : 'text-ink'}`}>
                  {item.unidade}
                  {item.sua && <span className="badge ml-2 align-middle">VOCÊS</span>}
                </span>
                <span className="text-lg font-extrabold text-ink tabular-nums">{item.total}</span>
              </div>
              {/* Barra = medidor: trilho num tom um passo acima do cartão (visível mesmo
                  vazio) e preenchimento sempre no verde da marca. Antes o preenchimento de
                  quem não era "você" usava um cinza sem croma nenhum — sumia no fundo escuro.
                  Quem está olhando se identifica pelo nome verde + selo VOCÊS, não pela
                  cor da barra; assim a barra encoda só o tamanho, que é o que se compara.
                  Zero não ganha barra nenhuma: o trilho vazio já diz isso, e sem mentir. */}
              <div className="h-2 rounded-full bg-line overflow-hidden">
                {item.total > 0 && (
                  <div
                    className="h-full rounded-full bg-brand"
                    style={{ width: `${Math.max((item.total / lider) * 100, 4)}%` }}
                  />
                )}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function mesAtual(): string {
  const m = new Date().toLocaleDateString('pt-BR', { month: 'long' })
  return m.charAt(0).toUpperCase() + m.slice(1)
}

function StatTile({
  icon: Icon,
  label,
  value,
  accent,
}: {
  icon: typeof Users
  label: string
  value: number
  accent: string
}) {
  return (
    <div className="card p-5">
      <div className="flex items-center gap-2 mb-2">
        <div
          className="w-8 h-8 rounded-lg flex items-center justify-center"
          style={{ background: `${accent}1a`, color: accent }}
        >
          <Icon size={16} strokeWidth={2.3} />
        </div>
        <span className="text-xs font-bold uppercase tracking-wide text-ink-4">{label}</span>
      </div>
      <div className="text-2xl font-extrabold text-ink">{value}</div>
    </div>
  )
}

async function contar(unidadeId: string | null, status?: StatusLead): Promise<number> {
  // Conta apenas o público-alvo (veículos com tacógrafo); ignora os "sem tacógrafo".
  let query = supabase
    .from('caminhoneiros')
    .select('*', { count: 'exact', head: true })
    .eq('tem_tacografo', true)
  if (unidadeId) query = query.eq('unidade_id', unidadeId)
  if (status) query = query.eq('status', status)
  const { count } = await query
  return count ?? 0
}

export default function Dashboard() {
  const filtroUnidade = useFiltroUnidade()
  const [loading, setLoading] = useState(true)
  const [total, setTotal] = useState(0)
  const [porStatus, setPorStatus] = useState<Record<string, number>>({})

  useEffect(() => {
    // Este effect roda mais de uma vez: no primeiro render ainda não sabemos quem
    // está logado, então `filtroUnidade` vem null (= todas as unidades); quando o
    // perfil carrega e é admin, ele vira a unidade escolhida e o effect roda de novo.
    // As duas buscas ficam no ar ao mesmo tempo — e a primeira (sem filtro, que varre
    // a base inteira) costuma demorar MAIS que a segunda. Sem esta guarda, a resposta
    // atrasada chegava por último e sobrescrevia os números certos: era por isso que o
    // admin via o total geral (3.404) mesmo com uma unidade selecionada.
    let cancelado = false
    ;(async () => {
      setLoading(true)
      const statuses: StatusLead[] = ['novo', 'mensagem_enviada', 'contatado', 'agendado', 'aferido']
      const [tot, ...counts] = await Promise.all([
        contar(filtroUnidade),
        ...statuses.map((s) => contar(filtroUnidade, s)),
      ])
      if (cancelado) return
      const map: Record<string, number> = {}
      statuses.forEach((s, i) => (map[s] = counts[i]))
      setTotal(tot)
      setPorStatus(map)
      setLoading(false)
    })()
    return () => {
      cancelado = true
    }
  }, [filtroUnidade])

  const contatados = total - (porStatus['novo'] ?? 0)
  const agendados = porStatus['agendado'] ?? 0
  const aferidos = porStatus['aferido'] ?? 0
  const taxaConversao = total > 0 ? Math.round((aferidos / total) * 100) : 0
  const funil = FUNIL_ORDEM.map(({ status, label }) => ({ label, total: porStatus[status] ?? 0 }))

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-xl font-extrabold text-ink">Dashboard</h1>
        <p className="text-sm text-ink-4">Visão geral do funil de aferição de tacógrafos</p>
      </div>

      <Placar />

      {loading ? (
        <p className="text-sm text-ink-4">Carregando…</p>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <StatTile icon={Users} label="Leads totais" value={total} accent="#3f57ff" />
            <StatTile icon={PhoneCall} label="Contatados" value={contatados} accent="#0ea5e9" />
            <StatTile icon={CalendarClock} label="Agendados" value={agendados} accent="#f2a63b" />
            <StatTile icon={CheckCircle2} label="Aferidos" value={aferidos} accent="#22c55e" />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-4">Funil de conversão</h2>
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={funil} layout="vertical" margin={{ left: 8, right: 24 }}>
                  <CartesianGrid horizontal={false} stroke="#232c40" />
                  <XAxis type="number" allowDecimals={false} tick={{ fontSize: 12, fill: '#93a0b8' }} axisLine={false} tickLine={false} />
                  <YAxis
                    type="category"
                    dataKey="label"
                    width={90}
                    tick={{ fontSize: 13, fill: '#cbd5e1', fontWeight: 600 }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <Tooltip
                    cursor={{ fill: 'rgba(255,255,255,0.05)' }}
                    contentStyle={{ borderRadius: 12, border: '1px solid #232c40', background: '#141b2a', color: '#f3f6fb', fontSize: 13 }}
                  />
                  <Bar dataKey="total" fill="#22c55e" radius={[0, 4, 4, 0]} barSize={28}>
                    <LabelList dataKey="total" position="right" style={{ fill: '#e2e8f0', fontWeight: 700, fontSize: 12 }} />
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="card p-5 flex flex-col justify-center items-center text-center">
              <span className="text-xs font-bold uppercase tracking-wide text-ink-4 mb-2">
                Taxa de conversão
              </span>
              <div className="text-4xl font-extrabold text-lucro mb-1">{taxaConversao}%</div>
              <p className="text-xs text-ink-4">dos leads totais chegaram a ser aferidos</p>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
