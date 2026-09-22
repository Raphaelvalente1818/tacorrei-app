import { useEffect, useState } from 'react'
import { Bar, BarChart, CartesianGrid, LabelList, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
// 15/09 - os rotulos dos eixos usam #c3cbd9, o mesmo valor do token `ink-6`. O
// recharts pinta em SVG e nao le classe do Tailwind, entao a cor vive aqui escrita
// a mao. Se o token mudar de novo, estes quatro pontos mudam junto - senao o
// grafico fica o unico lugar do app com o cinza antigo.
import { Users, PhoneCall, CalendarClock, CheckCircle2, Trophy, CalendarRange } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useFiltroUnidade } from '../lib/AuthContext'
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
// 22/09 — TRÊS NÚMEROS DE "MENSAGEM" QUE NÃO BATEM, DE PROPÓSITO. O Emerson viu o
// placar (17), o funil (184) e a conversão por canal (209) e estranhou. São três
// recortes: conversas abertas NESTE MÊS; leads que estão HOJE no estado "Mensagem
// enviada" (saem quando atendem, agendam ou aferem); e todos que JÁ receberam
// mensagem, desde o início. Lição 20: duas contas com o mesmo nome é bug de rótulo.
// Cada número passa a dizer o recorte embaixo, e o placar mostra também os
// caminhões cobertos (`cobertos`, 0104): uma conversa com a frota cobre vários.
type PlacarItem = { unidade: string; total: number; cobertos?: number; sua: boolean }

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
          Conversas de WhatsApp abertas em {mesAtual()}
        </span>
        <span className="text-[11px] text-ink-4 ml-auto" title="Cada clique em Enviar WhatsApp é uma conversa e conta 1 na cota, mesmo cobrindo vários caminhões da frota">
          este mês · uma por envio
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
                <span className="text-lg font-extrabold text-ink tabular-nums">
                  {item.total}
                  {(item.cobertos ?? 0) > item.total && (
                    <span className="text-xs font-semibold text-ink-4 ml-2" title="Caminhões cobertos: a conversa com a frota fala de vários de uma vez">
                      · {item.cobertos} caminhões
                    </span>
                  )}
                </span>
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
  hint,
}: {
  icon: typeof Users
  label: string
  value: number
  accent: string
  // 0094 — linha de baixo que explica do que o número é feito. Existe por causa do
  // cartão "Trabalhados": sem ela, 207 se lê como 207 conversas.
  hint?: string
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
      {hint && <div className="text-xs text-ink-4 mt-1 leading-snug">{hint}</div>}
    </div>
  )
}

// Uma chamada só devolve todas as contagens. Antes eram 6 consultas diretas na
// tabela — o Dashboard era o último lugar que ainda lia `caminhoneiros` sem passar
// pelo servidor. Conta apenas o público-alvo (com tacógrafo).
type Contagens = { total: number } & Partial<Record<StatusLead, number>>

async function buscarContagens(unidadeId: string | null): Promise<Contagens> {
  const { data, error } = await supabase.rpc('contar_leads', { p_unidade: unidadeId })
  if (error || !data) return { total: 0 }
  return data as Contagens
}

// 0094 — conversão separada por canal. Mensagem enviada e ligação atendida têm
// conversões muito diferentes; a média das duas não responde a pergunta "qual canal
// traz caminhão?". Os grupos se sobrepõem (`ambos`), então as taxas não somam.
type Canal = { alcancados: number; aferiram: number }
type Conversao = {
  mensagem: Canal
  ligacao: Canal
  ambos: number
  veio_sozinho: number
  aferidos_total: number
}
const CONVERSAO_VAZIA: Conversao = {
  mensagem: { alcancados: 0, aferiram: 0 },
  ligacao: { alcancados: 0, aferiram: 0 },
  ambos: 0,
  veio_sozinho: 0,
  aferidos_total: 0,
}

async function buscarConversao(unidadeId: string | null): Promise<Conversao> {
  const { data, error } = await supabase.rpc('conversao_por_canal', { p_unidade: unidadeId })
  if (error || !data) return CONVERSAO_VAZIA
  return data as Conversao
}

// 0096b — o panorama do ano. A régua do gestor mostra a ele só as fichas que
// estão em jogo agora (a frota com algo vencendo nos próximos 60 dias). Isso é
// proteção da base, mas cega ele quanto ao tamanho do que tem pela frente — e
// esse tamanho é justamente o que faz valer a pena investir na operação. Aqui
// ele vê a conta do ano inteiro, mês a mês, e nenhum caminhão: sem nome, sem
// placa, sem telefone. Número não se disca.
//
// 0102 — cada mês vem partido em três: cliente da casa (última aferição num posto
// do grupo), concorrente (posto conhecido, não é nosso) e posto desconhecido (a
// base de Santo André tem 167 sem a coluna W; chamar de concorrente seria mentir).
// O mesmo mês com 200 vencimentos é lembrete se são clientes e conquista se são
// do concorrente — o total sozinho não dizia qual esforço o mês pede.
type PanoramaMes = { mes: string; total: number; cliente: number; concorrente: number; desconhecido: number }
type Panorama = { meses: PanoramaMes[]; total: number; cliente: number; concorrente: number; desconhecido: number }
const PANORAMA_VAZIO: Panorama = { meses: [], total: 0, cliente: 0, concorrente: 0, desconhecido: 0 }

async function buscarPanorama(unidadeId: string | null): Promise<Panorama> {
  const { data, error } = await supabase.rpc('panorama_do_ano', { p_unidade: unidadeId })
  if (error || !data) return PANORAMA_VAZIO
  const p = data as Partial<Panorama>
  // Tolerante ao banco antigo (só `total`): as fatias ficam em zero e o gráfico
  // vira uma barra só, em vez de quebrar.
  return {
    meses: (p.meses ?? []).map((m) => ({
      mes: m.mes,
      total: m.total ?? 0,
      cliente: m.cliente ?? 0,
      concorrente: m.concorrente ?? 0,
      desconhecido: m.desconhecido ?? 0,
    })),
    total: p.total ?? 0,
    cliente: p.cliente ?? 0,
    concorrente: p.concorrente ?? 0,
    desconhecido: p.desconhecido ?? 0,
  }
}

// As cores do panorama: verde é a marca (cliente da casa), azul é o de apoio
// (concorrente — o que há para conquistar), cinza é o que ainda não sabemos.
const COR_CLIENTE = '#22c55e'
const COR_CONCORRENTE = '#3f57ff'
const COR_DESCONHECIDO = '#5b6579'

// '2026-10' → 'out/26'
function rotuloMes(mes: string): string {
  const [ano, m] = mes.split('-')
  const nomes = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
  return `${nomes[Number(m) - 1]}/${ano.slice(2)}`
}

// Poucos casos ainda: uma casa decimal abaixo de 10%, nenhuma acima.
function pct(parte: number, todo: number): string {
  if (todo === 0) return '—'
  const t = (parte / todo) * 100
  return `${(t >= 10 ? t.toFixed(0) : t.toFixed(1)).replace('.', ',')}%`
}

export default function Dashboard() {
  const filtroUnidade = useFiltroUnidade()
  const { membro } = useAuth()
  const [loading, setLoading] = useState(true)
  const [total, setTotal] = useState(0)
  const [porStatus, setPorStatus] = useState<Record<string, number>>({})
  const [conv, setConv] = useState<Conversao>(CONVERSAO_VAZIA)
  const [panorama, setPanorama] = useState<Panorama>(PANORAMA_VAZIO)
  const isGestao = membro?.papel === 'admin' || membro?.papel === 'admin_unidade'

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
      const [c, k, p] = await Promise.all([
        buscarContagens(filtroUnidade),
        buscarConversao(filtroUnidade),
        buscarPanorama(filtroUnidade),
      ])
      if (cancelado) return
      const statuses: StatusLead[] = ['novo', 'mensagem_enviada', 'contatado', 'agendado', 'aferido']
      const map: Record<string, number> = {}
      statuses.forEach((s) => (map[s] = Number(c[s] ?? 0)))
      setTotal(Number(c.total ?? 0))
      setPorStatus(map)
      setConv(k)
      setPanorama(p)
      setLoading(false)
    })()
    return () => {
      cancelado = true
    }
  }, [filtroUnidade])

  // "Trabalhados" = tudo que saiu de Novo. NÃO é "conversou": em São Bernardo eram
  // 207, dos quais 175 só receberam uma mensagem e 11 realmente falaram com a gente.
  // O nome antigo do cartão era "Contatados" e induzia ao erro — o Emerson estranhou
  // a diferença para o filtro "Contatado" da fila (11) em 14/09.
  const trabalhados = total - (porStatus['novo'] ?? 0)
  const comMensagem = porStatus['mensagem_enviada'] ?? 0
  const conversaram = porStatus['contatado'] ?? 0
  const agendados = porStatus['agendado'] ?? 0
  const aferidos = porStatus['aferido'] ?? 0
  const funil = FUNIL_ORDEM.map(({ status, label }) => ({ label, total: porStatus[status] ?? 0 }))
  const meses = panorama.meses.map((m) => ({ ...m, label: rotuloMes(m.mes) }))
  // A fatia cinza só entra no desenho onde existe (Santo André); em São Bernardo
  // é zero em todos os meses e não ganha legenda nem barra.
  const temDesconhecido = panorama.desconhecido > 0
  const n = (x: number) => x.toLocaleString('pt-BR')

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
          {/* 22/09 — os quatro blocos são retrato de HOJE, desde o início, dentro da
              régua; só o placar acima fala do mês. O Emerson perguntou "de qual período?"
              — a resposta tem que estar na tela, não na cabeça de quem lê. */}
          <p className="text-[11px] text-ink-4 mb-2">
            Como está <b className="text-ink-6">hoje</b> cada caminhão da base. Vencido há mais de 12 meses fica de fora.
          </p>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <StatTile icon={Users} label="Leads totais" value={total} accent="#3f57ff" />
            <StatTile
              icon={PhoneCall}
              label="Trabalhados"
              value={trabalhados}
              accent="#0ea5e9"
              hint={`${comMensagem.toLocaleString('pt-BR')} só receberam mensagem · ${conversaram.toLocaleString('pt-BR')} conversaram`}
            />
            <StatTile icon={CalendarClock} label="Agendados" value={agendados} accent="#f2a63b" />
            <StatTile icon={CheckCircle2} label="Aferidos" value={aferidos} accent="#22c55e" />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-1">Funil de conversão</h2>
              <p className="text-xs text-ink-4 mb-3">
                Como está <b className="text-ink-6">hoje</b> cada caminhão. Quem recebeu mensagem e depois atendeu,
                agendou ou aferiu já não conta em "Mensagem enviada".
              </p>
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={funil} layout="vertical" margin={{ left: 8, right: 24 }}>
                  <CartesianGrid horizontal={false} stroke="#232c40" />
                  <XAxis type="number" allowDecimals={false} tick={{ fontSize: 12, fill: '#c3cbd9' }} axisLine={false} tickLine={false} />
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

            {/* Conversão por canal (0094). Antes era uma taxa só, dividindo aferidos por
                "contatados" — que misturava mensagem enviada com conversa real. Como os
                dois canais convertem de formas muito diferentes, a média não respondia
                nada. Aqui cada um tem o seu denominador, e a sobreposição fica dita. */}
            <div className="card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-1">Conversão por canal</h2>
              <p className="text-xs text-ink-4 mb-4">
                De quem foi alcançado <b className="text-ink-6">alguma vez</b>, quantos vieram aferir depois. Aqui
                entram também os que já atenderam ou aferiram.
              </p>

              <div className="mb-4">
                <div className="flex items-baseline justify-between mb-1">
                  <span className="text-xs font-bold uppercase tracking-wide text-ink-4">
                    Mensagem de WhatsApp
                  </span>
                  <span className="text-2xl font-extrabold text-lucro">
                    {pct(conv.mensagem.aferiram, conv.mensagem.alcancados)}
                  </span>
                </div>
                <p className="text-xs text-ink-4">
                  {conv.mensagem.aferiram.toLocaleString('pt-BR')} de{' '}
                  {conv.mensagem.alcancados.toLocaleString('pt-BR')} que já receberam mensagem
                </p>
              </div>

              <div className="mb-4">
                <div className="flex items-baseline justify-between mb-1">
                  <span className="text-xs font-bold uppercase tracking-wide text-ink-4">
                    Ligação atendida
                  </span>
                  <span className="text-2xl font-extrabold text-ink">
                    {pct(conv.ligacao.aferiram, conv.ligacao.alcancados)}
                  </span>
                </div>
                <p className="text-xs text-ink-4">
                  {conv.ligacao.aferiram.toLocaleString('pt-BR')} de{' '}
                  {conv.ligacao.alcancados.toLocaleString('pt-BR')} que pegaram o telefone
                </p>
              </div>

              <div className="border-t border-line pt-3 text-xs text-ink-4 leading-relaxed">
                {conv.ambos > 0 && (
                  <>
                    {conv.ambos.toLocaleString('pt-BR')} receberam os dois canais — as taxas não
                    somam.{' '}
                  </>
                )}
                {conv.veio_sozinho > 0 && (
                  <>
                    <span className="text-warn font-semibold">
                      {conv.veio_sozinho.toLocaleString('pt-BR')} vieram sozinhos
                    </span>{' '}
                    (aferiram sem contato antes), de {conv.aferidos_total.toLocaleString('pt-BR')}{' '}
                    aferições registradas.
                  </>
                )}
              </div>
            </div>
          </div>

          {/* Panorama do ano (0096b). O que a unidade tem pela frente, em número.
              A fila entrega só quem está em jogo agora; este quadro conta o resto
              sem mostrar ninguém. */}
          {isGestao && meses.length > 0 && (
            <div className="card p-5 mt-6">
              <div className="flex items-baseline justify-between mb-1 gap-4">
                <h2 className="text-sm font-extrabold text-ink flex items-center gap-2">
                  <CalendarRange size={16} className="text-brand" /> Panorama do ano
                </h2>
                <span className="text-2xl font-extrabold text-ink">
                  {panorama.total.toLocaleString('pt-BR')}
                </span>
              </div>
              <p className="text-xs text-ink-4 mb-3">
                Caminhões que vencem nos próximos doze meses. A fila do dia entrega
                quem já dá para trabalhar; o resto aparece aqui como conta, e chega
                na fila no mês dele.
              </p>
              {/* 0102 — a legenda com os totais do ano. Verde é lembrete (já é
                  cliente), azul é conquista (afere no concorrente). */}
              <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs font-semibold text-ink-6 mb-3">
                <span className="flex items-center gap-1.5">
                  <span className="inline-block w-2.5 h-2.5 rounded-sm" style={{ background: COR_CLIENTE }} />
                  Cliente <span className="text-ink font-extrabold">{n(panorama.cliente)}</span>
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="inline-block w-2.5 h-2.5 rounded-sm" style={{ background: COR_CONCORRENTE }} />
                  Concorrente <span className="text-ink font-extrabold">{n(panorama.concorrente)}</span>
                </span>
                {temDesconhecido && (
                  <span className="flex items-center gap-1.5">
                    <span className="inline-block w-2.5 h-2.5 rounded-sm" style={{ background: COR_DESCONHECIDO }} />
                    Posto desconhecido <span className="text-ink font-extrabold">{n(panorama.desconhecido)}</span>
                  </span>
                )}
              </div>
              <ResponsiveContainer width="100%" height={200}>
                <BarChart data={meses} margin={{ left: 0, right: 8, top: 12 }}>
                  <CartesianGrid vertical={false} stroke="#232c40" />
                  <XAxis
                    dataKey="label"
                    tick={{ fontSize: 11, fill: '#c3cbd9' }}
                    axisLine={false}
                    tickLine={false}
                    interval={0}
                  />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: '#c3cbd9' }} axisLine={false} tickLine={false} width={36} />
                  <Tooltip
                    cursor={{ fill: 'rgba(255,255,255,0.05)' }}
                    contentStyle={{ borderRadius: 12, border: '1px solid #232c40', background: '#141b2a', color: '#f3f6fb', fontSize: 13 }}
                    formatter={(valor, nome) => [n(Number(valor ?? 0)), String(nome ?? '')]}
                  />
                  {/* Empilhadas na ordem: cliente embaixo (a base que já é nossa),
                      concorrente por cima, desconhecido no topo quando existe. O
                      número no alto é o total do mês, sempre no último segmento. */}
                  <Bar dataKey="cliente" name="Cliente" stackId="mes" fill={COR_CLIENTE} />
                  <Bar
                    dataKey="concorrente"
                    name="Concorrente"
                    stackId="mes"
                    fill={COR_CONCORRENTE}
                    radius={temDesconhecido ? undefined : [4, 4, 0, 0]}
                  >
                    {!temDesconhecido && (
                      <LabelList dataKey="total" position="top" style={{ fill: '#c3cbd9', fontWeight: 600, fontSize: 11 }} />
                    )}
                  </Bar>
                  {temDesconhecido && (
                    <Bar dataKey="desconhecido" name="Posto desconhecido" stackId="mes" fill={COR_DESCONHECIDO} radius={[4, 4, 0, 0]}>
                      <LabelList dataKey="total" position="top" style={{ fill: '#c3cbd9', fontWeight: 600, fontSize: 11 }} />
                    </Bar>
                  )}
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </>
      )}
    </div>
  )
}
