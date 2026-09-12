import { useCallback, useEffect, useState } from 'react'
import { Building2, Save, SlidersHorizontal } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/AuthContext'
import { botao, chip, chipOff, chipOn, input } from './ui'

// ── Configuração da unidade (só admin geral) ─────────────────────────────────
// Itens 3, 5, 6 e 9 da matriz: nome, posto, marca, endereço, telefone; janela e
// piso da fila; cota e intervalo do WhatsApp; e a marcação que libera ao gestor
// mexer no prêmio. Tudo passa por `configurar_unidade`, que aplica a matriz de
// novo no banco — a tela só não oferece o que seria negado.

type UnidadeCfg = {
  id: string
  nome: string
  posto_afericao: string | null
  marca: string | null
  endereco: string | null
  telefone: string | null
  janela_dias: number | null
  piso_dias: number
  limite_whatsapp_dia: number
  intervalo_whatsapp_min: number
  cooldown_telefone_dias: number
  agrupamento_dias: number
  unidade_edita_premio: boolean
}

const JANELAS: { label: string; dias: number | null }[] = [
  { label: '30 dias', dias: 30 },
  { label: '45 dias', dias: 45 },
  { label: '60 dias', dias: 60 },
  { label: 'Base toda', dias: null },
]

const PISOS: { label: string; dias: number }[] = [
  { label: '6 meses', dias: 180 },
  { label: '12 meses', dias: 365 },
  { label: '24 meses', dias: 730 },
]

export default function ConfigUnidade({ unidadeId }: { unidadeId: string }) {
  const { recarregarUnidades } = useAuth()
  const [u, setU] = useState<UnidadeCfg | null>(null)
  const [orig, setOrig] = useState<UnidadeCfg | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)

  const carregar = useCallback(async () => {
    setErro(null)
    const { data, error } = await supabase.rpc('configuracao_unidade', { p_unidade: unidadeId })
    if (error) {
      setErro(error.message)
      return
    }
    const un = (data as { unidade: UnidadeCfg }).unidade
    setU(un)
    setOrig(un)
    setMsg(null)
  }, [unidadeId])

  useEffect(() => {
    carregar()
  }, [carregar])

  if (erro) return <p className="text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3">{erro}</p>
  if (!u || !orig) return <p className="text-sm text-ink-4">Carregando…</p>

  const campos: (keyof UnidadeCfg)[] = [
    'nome', 'posto_afericao', 'marca', 'endereco', 'telefone', 'janela_dias', 'piso_dias',
    'limite_whatsapp_dia', 'intervalo_whatsapp_min', 'cooldown_telefone_dias', 'agrupamento_dias', 'unidade_edita_premio',
  ]
  const mudados = campos.filter((k) => u[k] !== orig[k])

  function set<K extends keyof UnidadeCfg>(k: K, v: UnidadeCfg[K]) {
    setU((x) => (x ? { ...x, [k]: v } : x))
  }

  async function salvar() {
    if (!u) return
    setSalvando(true)
    setMsg(null)
    const p_campos: Record<string, unknown> = {}
    for (const k of mudados) p_campos[k] = u[k]
    const { data, error } = await supabase.rpc('configurar_unidade', { p_unidade: unidadeId, p_campos })
    setSalvando(false)
    if (error) {
      setMsg({ tipo: 'erro', texto: error.message })
      return
    }
    setU(data as UnidadeCfg)
    setOrig(data as UnidadeCfg)
    await recarregarUnidades()
    setMsg({ tipo: 'ok', texto: 'Salvo. Vale para todas as telas, sem deploy.' })
  }

  const numInput = (k: 'limite_whatsapp_dia' | 'intervalo_whatsapp_min' | 'cooldown_telefone_dias' | 'agrupamento_dias', rotulo: string, ajuda: string) => (
    <div>
      <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">{rotulo}</label>
      <input
        type="number"
        value={u[k]}
        onChange={(e) => set(k, Number(e.target.value))}
        className={`${input} w-full`}
      />
      <p className="text-[11px] text-ink-4 mt-0.5">{ajuda}</p>
    </div>
  )

  return (
    <div className="space-y-4">
      <div className="card p-5 space-y-4">
        <h2 className="text-sm font-extrabold text-ink flex items-center gap-2">
          <Building2 size={16} className="text-brand" /> Identidade — {orig.nome}
        </h2>
        <div className="grid sm:grid-cols-2 gap-3">
          <div>
            <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Nome da unidade (interno)</label>
            <input value={u.nome} onChange={(e) => set('nome', e.target.value)} className={`${input} w-full`} />
          </div>
          <div>
            <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Nome do posto (como está no Inmetro)</label>
            <input value={u.posto_afericao ?? ''} onChange={(e) => set('posto_afericao', e.target.value)} placeholder="Ex.: TACORREI TACÓGRAFOS COMÉRCIO E SERVIÇOS LTDA-ME." className={`${input} w-full`} />
            <p className="text-[11px] text-ink-4 mt-0.5">É o que o botão "Aferido" grava no caminhão e o que define "nosso" nos painéis.</p>
          </div>
          <div>
            <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Marca (como assina a mensagem)</label>
            <input value={u.marca ?? ''} onChange={(e) => set('marca', e.target.value)} placeholder="Ex.: Tacorrei Tacógrafos" className={`${input} w-full`} />
          </div>
          <div>
            <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Telefone do posto</label>
            <input value={u.telefone ?? ''} onChange={(e) => set('telefone', e.target.value)} placeholder="(11) 0000-0000" className={`${input} w-full`} />
          </div>
          <div className="sm:col-span-2">
            <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Endereço (última linha da mensagem)</label>
            <input value={u.endereco ?? ''} onChange={(e) => set('endereco', e.target.value)} placeholder="Rua, número, bairro, cidade/UF" className={`${input} w-full`} />
          </div>
        </div>
      </div>

      <div className="card p-5 space-y-4">
        <h2 className="text-sm font-extrabold text-ink flex items-center gap-2">
          <SlidersHorizontal size={16} className="text-brand" /> Fila e WhatsApp
        </h2>
        <div>
          <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1.5">Janela — quanto antes do vencimento o caminhão entra na fila</label>
          <div className="flex gap-1.5 flex-wrap">
            {JANELAS.map((j) => (
              <button key={j.label} type="button" onClick={() => set('janela_dias', j.dias)} className={`${chip} ${u.janela_dias === j.dias ? chipOn : chipOff}`}>{j.label}</button>
            ))}
            {u.janela_dias != null && !JANELAS.some((j) => j.dias === u.janela_dias) && (
              <span className={`${chip} ${chipOn}`}>{u.janela_dias} dias</span>
            )}
          </div>
          <p className="text-[11px] text-ink-4 mt-1">A janela é um prazo, não uma fatia da base: quem vence depois entra sozinho quando a data chega.</p>
        </div>
        <div>
          <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1.5">Piso — até quanto tempo de vencido ainda se trabalha</label>
          <div className="flex gap-1.5 flex-wrap">
            {PISOS.map((p) => (
              <button key={p.label} type="button" onClick={() => set('piso_dias', p.dias)} className={`${chip} ${u.piso_dias === p.dias ? chipOn : chipOff}`}>{p.label}</button>
            ))}
            {!PISOS.some((p) => p.dias === u.piso_dias) && <span className={`${chip} ${chipOn}`}>{u.piso_dias} dias</span>}
          </div>
          <p className="text-[11px] text-ink-4 mt-1">Igual para admin e operadora, em todas as telas. Vencido há mais que isso fica no banco, alcançável pela busca de placa.</p>
        </div>
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
          {numInput('limite_whatsapp_dia', 'Cota de WhatsApp por dia', 'Mensagens novas por dia na unidade.')}
          {numInput('intervalo_whatsapp_min', 'Intervalo entre mensagens (min)', 'Espera mínima entre dois envios.')}
          {numInput('cooldown_telefone_dias', 'Mesmo telefone (dias)', 'Um número não recebe outra mensagem antes disso.')}
          {numInput('agrupamento_dias', 'Agrupamento da frota (dias)', 'Irmãos que vencem dentro deste prazo entram pré-marcados na mesma mensagem.')}
        </div>
      </div>

      <div className="card p-5">
        <label className="flex items-start gap-3 cursor-pointer">
          <input type="checkbox" checked={u.unidade_edita_premio} onChange={(e) => set('unidade_edita_premio', e.target.checked)} className="mt-1" />
          <span>
            <span className="text-sm font-bold text-ink">O gestor desta unidade pode definir valor do ponto, teto e bolo</span>
            <span className="block text-xs text-ink-4 mt-0.5">
              Desligado por padrão (decisão de 11/09): nas unidades do grupo, quem define é o admin geral. Ligar para unidade de fora que compre o app e pague o prêmio do próprio bolso.
              Mesmo ligado, o gestor só grava para mês futuro.
            </span>
          </span>
        </label>
      </div>

      <div className="flex items-center gap-3">
        <button onClick={salvar} disabled={mudados.length === 0 || salvando} className={botao}>
          <Save size={15} /> {salvando ? 'Salvando…' : mudados.length > 0 ? `Salvar ${mudados.length} ${mudados.length === 1 ? 'alteração' : 'alterações'}` : 'Nada a salvar'}
        </button>
        {msg && <span className={`text-sm ${msg.tipo === 'ok' ? 'text-lucro' : 'text-danger'}`}>{msg.texto}</span>}
      </div>
    </div>
  )
}
