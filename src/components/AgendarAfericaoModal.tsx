import { useState, type FormEvent } from 'react'
import { X } from 'lucide-react'
import { supabase } from '../lib/supabase'

export default function AgendarAfericaoModal({
  caminhoneiroId,
  operadorId,
  onClose,
  onCreated,
}: {
  caminhoneiroId: string
  operadorId: string | undefined
  onClose: () => void
  onCreated: () => void
}) {
  const [data, setData] = useState('')
  const [hora, setHora] = useState('09:00')
  const [local, setLocal] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError(null)

    const dataHora = new Date(`${data}T${hora}:00`)

    const { error: agendamentoError } = await supabase.from('agendamentos').insert({
      caminhoneiro_id: caminhoneiroId,
      data_hora: dataHora.toISOString(),
      local: local || null,
      created_by: operadorId ?? null,
    })

    if (agendamentoError) {
      setSaving(false)
      setError(agendamentoError.message)
      return
    }

    await supabase.from('caminhoneiros').update({ status: 'agendado' }).eq('id', caminhoneiroId)

    setSaving(false)
    onCreated()
  }

  return (
    <div className="fixed inset-0 bg-ink/40 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-extrabold text-ink">Agendar aferição</h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
                Data *
              </label>
              <input
                type="date"
                required
                value={data}
                onChange={(e) => setData(e.target.value)}
                className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
                Hora *
              </label>
              <input
                type="time"
                required
                value={hora}
                onChange={(e) => setHora(e.target.value)}
                className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
              />
            </div>
          </div>
          <div>
            <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
              Local
            </label>
            <input
              value={local}
              onChange={(e) => setLocal(e.target.value)}
              placeholder="Posto / oficina / endereço"
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
            />
          </div>

          {error && <p className="text-sm text-danger">{error}</p>}

          <button
            type="submit"
            disabled={saving}
            className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            {saving ? 'Salvando…' : 'Confirmar agendamento'}
          </button>
        </form>
      </div>
    </div>
  )
}
