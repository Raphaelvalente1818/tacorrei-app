import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import type { CanalContato, ResultadoLigacao, StatusLead } from '../lib/database.types'
import { CANAL_CONTATO_LABEL, RESULTADO_LIGACAO_LABEL } from '../lib/status'

// Resultados oferecidos NESTE formulário. Ficam de fora os que têm botão próprio
// na ficha: 'whatsapp_enviado' (botão Enviar WhatsApp) e 'aferido' (botão Aferido,
// que também grava a data do serviço — registrar por aqui não faria isso).
const RESULTADOS: ResultadoLigacao[] = [
  'atendeu',
  'nao_atendeu',
  'numero_invalido',
  'recusou',
  'agendou',
  'reagendar',
]

// Tipos de contato manuais (WhatsApp e aferição são registrados pelos botões da ficha)
const CANAIS: CanalContato[] = ['ligacao_ativa', 'ligacao_passiva']

// Precisa cobrir TODOS os resultados, inclusive os que não aparecem no formulário —
// é um Record completo, e o build quebra se faltar algum.
const STATUS_POR_RESULTADO: Record<ResultadoLigacao, StatusLead> = {
  atendeu: 'contatado',
  nao_atendeu: 'sem_resposta',
  numero_invalido: 'invalido',
  recusou: 'recusado',
  agendou: 'agendado',
  reagendar: 'contatado',
  whatsapp_enviado: 'mensagem_enviada',
  aferido: 'aferido',
}

export default function RegistrarLigacaoForm({
  caminhoneiroId,
  operadorId,
  onSaved,
}: {
  caminhoneiroId: string
  operadorId: string | undefined
  onSaved: (novoStatus: StatusLead, resultado: ResultadoLigacao) => void
}) {
  const [canal, setCanal] = useState<CanalContato>('ligacao_ativa')
  const [resultado, setResultado] = useState<ResultadoLigacao>('atendeu')
  const [notas, setNotas] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError(null)

    const { error: ligacaoError } = await supabase.from('ligacoes').insert({
      caminhoneiro_id: caminhoneiroId,
      operador_id: operadorId ?? null,
      resultado,
      canal,
      notas: notas || null,
    })

    if (ligacaoError) {
      setSaving(false)
      setError(ligacaoError.message)
      return
    }

    const novoStatus = STATUS_POR_RESULTADO[resultado]
    const { error: statusError } = await supabase
      .from('caminhoneiros')
      .update({ status: novoStatus })
      .eq('id', caminhoneiroId)

    setSaving(false)
    if (statusError) {
      setError(statusError.message)
      return
    }

    setNotas('')
    onSaved(novoStatus, resultado)
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <div>
        <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
          Tipo de contato
        </label>
        <select
          value={canal}
          onChange={(e) => setCanal(e.target.value as CanalContato)}
          className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card"
        >
          {CANAIS.map((c) => (
            <option key={c} value={c}>
              {CANAL_CONTATO_LABEL[c]}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
          Resultado
        </label>
        <select
          value={resultado}
          onChange={(e) => setResultado(e.target.value as ResultadoLigacao)}
          className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card"
        >
          {RESULTADOS.map((r) => (
            <option key={r} value={r}>
              {RESULTADO_LIGACAO_LABEL[r]}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
          Notas
        </label>
        <textarea
          value={notas}
          onChange={(e) => setNotas(e.target.value)}
          rows={3}
          className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none resize-none"
          placeholder="O que foi conversado, melhor horário para retornar, etc."
        />
      </div>
      {error && <p className="text-sm text-danger">{error}</p>}
      <button
        type="submit"
        disabled={saving}
        className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
      >
        {saving ? 'Salvando…' : 'Registrar contato'}
      </button>
    </form>
  )
}
