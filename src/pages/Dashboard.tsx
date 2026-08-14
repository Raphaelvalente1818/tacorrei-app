import { useEffect, useState } from 'react'
import { Bar, BarChart, CartesianGrid, LabelList, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { Users, PhoneCall, CalendarClock, CheckCircle2 } from 'lucide-react'
import { supabase } from '../lib/supabase'
import type { StatusLead } from '../lib/database.types'

const FUNIL_ORDEM: Array<{ status: StatusLead; label: string }> = [
  { status: 'novo', label: 'Novos' },
  { status: 'mensagem_enviada', label: 'Mensagem enviada' },
  { status: 'contatado', label: 'Contatados' },
  { status: 'agendado', label: 'Agendados' },
  { status: 'aferido', label: 'Aferidos' },
]

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

async function contar(status?: StatusLead): Promise<number> {
  // Conta apenas o público-alvo (veículos com tacógrafo); ignora os "sem tacógrafo".
  let query = supabase
    .from('caminhoneiros')
    .select('*', { count: 'exact', head: true })
    .eq('tem_tacografo', true)
  if (status) query = query.eq('status', status)
  const { count } = await query
  return count ?? 0
}

export default function Dashboard() {
  const [loading, setLoading] = useState(true)
  const [total, setTotal] = useState(0)
  const [porStatus, setPorStatus] = useState<Record<string, number>>({})

  useEffect(() => {
    ;(async () => {
      const statuses: StatusLead[] = ['novo', 'mensagem_enviada', 'contatado', 'agendado', 'aferido']
      const [tot, ...counts] = await Promise.all([contar(), ...statuses.map((s) => contar(s))])
      const map: Record<string, number> = {}
      statuses.forEach((s, i) => (map[s] = counts[i]))
      setTotal(tot)
      setPorStatus(map)
      setLoading(false)
    })()
  }, [])

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

      {loading ? (
        <p className="text-sm text-ink-4">Carregando…</p>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <StatTile icon={Users} label="Leads totais" value={total} accent="#2563eb" />
            <StatTile icon={PhoneCall} label="Contatados" value={contatados} accent="#1e40af" />
            <StatTile icon={CalendarClock} label="Agendados" value={agendados} accent="#4f46e5" />
            <StatTile icon={CheckCircle2} label="Aferidos" value={aferidos} accent="#059669" />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-4">Funil de conversão</h2>
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={funil} layout="vertical" margin={{ left: 8, right: 24 }}>
                  <CartesianGrid horizontal={false} stroke="#e2e8f0" />
                  <XAxis type="number" allowDecimals={false} tick={{ fontSize: 12, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
                  <YAxis
                    type="category"
                    dataKey="label"
                    width={90}
                    tick={{ fontSize: 13, fill: '#0f172a', fontWeight: 600 }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <Tooltip
                    cursor={{ fill: '#f1f5f9' }}
                    contentStyle={{ borderRadius: 12, border: '1px solid #e2e8f0', fontSize: 13 }}
                  />
                  <Bar dataKey="total" fill="#2563eb" radius={[0, 4, 4, 0]} barSize={28}>
                    <LabelList dataKey="total" position="right" style={{ fill: '#0f172a', fontWeight: 700, fontSize: 12 }} />
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
