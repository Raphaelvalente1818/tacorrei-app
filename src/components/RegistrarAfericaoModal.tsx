import { useState, type FormEvent } from 'react'
import { X, CheckCircle2 } from 'lucide-react'
import { supabase } from '../lib/supabase'

// Marca que a aferição foi feita. A data vai para `data_ultima_afericao` — o MESMO
// campo que calcula o vencimento —, então o lead sai da fila agora e volta sozinho
// daqui a 2 anos, virando recompra. Também grava no histórico (canal 'presencial')
// para ficar registrado quem marcou e quando.
export default function RegistrarAfericaoModal({
  caminhoneiroId,
  onClose,
  onSaved,
}: {
  caminhoneiroId: string
  onClose: () => void
  onSaved: () => void
}) {
  // Já vem preenchido com hoje, que é o caso normal — mas fica editável para
  // quando a funcionária registrar um serviço de ontem ou da semana passada.
  const [data, setData] = useState(() => {
    const d = new Date()
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
    return d.toISOString().slice(0, 10)
  })
  const [notas, setNotas] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const hoje = (() => {
    const d = new Date()
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
    return d.toISOString().slice(0, 10)
  })()

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    if (data > hoje) {
      setError('A data da aferição não pode ser no futuro.')
      return
    }
    setSaving(true)
    setError(null)

    // Vai por RPC, e não por update direto, por um motivo concreto: ao gravar a data
    // de hoje o vencimento pula para daqui a 2 anos e o lead SAI da janela da
    // operadora. O Postgres então recusa o update — não se atualiza uma linha para
    // a invisibilidade. A RPC valida a permissão pela mesma regra e grava.
    // De quebra, lead + histórico viram uma operação atômica.
    const { error: rpcError } = await supabase.rpc('registrar_afericao', {
      p_lead: caminhoneiroId,
      p_data: data,
      p_notas: notas.trim() || null,
      p_marcar_aferido: true,
    })

    if (rpcError) {
      setSaving(false)
      setError(rpcError.message)
      return
    }

    setSaving(false)
    onSaved()
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6">
        <div className="flex items-center justify-between mb-1">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <CheckCircle2 size={18} className="text-lucro" />
            Registrar aferição
          </h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>
        <p className="text-xs text-ink-4 mb-4">
          O certificado passa a valer por 2 anos a partir desta data, e o lead volta para a fila quando estiver
          perto de vencer.
        </p>

        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
              Data da aferição *
            </label>
            <input
              type="date"
              required
              max={hoje}
              value={data}
              onChange={(e) => setData(e.target.value)}
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
            />
          </div>

          <div>
            <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
              Observações
            </label>
            <textarea
              value={notas}
              onChange={(e) => setNotas(e.target.value)}
              rows={2}
              placeholder="Opcional — nº do certificado, quem atendeu, etc."
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none resize-none"
            />
          </div>

          {error && <p className="text-sm text-danger">{error}</p>}

          <button
            type="submit"
            disabled={saving}
            className="w-full py-2.5 rounded-xl bg-brand text-[#04120a] font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            {saving ? 'Salvando…' : 'Confirmar aferição'}
          </button>
        </form>
      </div>
    </div>
  )
}
