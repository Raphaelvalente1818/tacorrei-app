import { useState } from 'react'
import { AlertTriangle, X } from 'lucide-react'

// ── Confirmação ──────────────────────────────────────────────────────────────
// Toda deleção e toda correção passam por aqui (pedido do Emerson, 12/09: "sempre
// deixar um popup para confirmar uma deleção"). O texto diz o que vai acontecer e
// o que NÃO volta; quando o banco registra a correção, o motivo é pedido aqui.

export default function ConfirmarModal({
  titulo,
  texto,
  rotuloConfirmar = 'Confirmar',
  perigo = true,
  pedirMotivo = false,
  motivoObrigatorio = false,
  onConfirmar,
  onCancelar,
}: {
  titulo: string
  texto: string
  rotuloConfirmar?: string
  perigo?: boolean
  pedirMotivo?: boolean
  motivoObrigatorio?: boolean
  onConfirmar: (motivo: string) => Promise<void> | void
  onCancelar: () => void
}) {
  const [motivo, setMotivo] = useState('')
  const [rodando, setRodando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  async function confirmar() {
    if (motivoObrigatorio && !motivo.trim()) {
      setErro('Escreva o motivo — ele fica no registro.')
      return
    }
    setRodando(true)
    setErro(null)
    try {
      await onConfirmar(motivo.trim())
    } catch (e) {
      setRodando(false)
      setErro(e instanceof Error ? e.message : String(e))
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50" onClick={onCancelar}>
      <div className="card w-full max-w-md p-5" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-3 mb-2">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <AlertTriangle size={18} className={perigo ? 'text-rose-400' : 'text-amber-300'} /> {titulo}
          </h2>
          <button onClick={onCancelar} className="text-ink-4 hover:text-ink" aria-label="Fechar"><X size={18} /></button>
        </div>
        <p className="text-sm text-ink-6 whitespace-pre-line">{texto}</p>
        {pedirMotivo && (
          <textarea
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            placeholder={motivoObrigatorio ? 'Motivo (obrigatório — fica no registro)' : 'Motivo (opcional — fica no registro)'}
            rows={2}
            className="w-full mt-3 px-3 py-2 border border-line rounded-xl text-sm bg-card focus-ring outline-none"
            autoFocus
          />
        )}
        {erro && <p className="text-sm text-danger mt-2">{erro}</p>}
        <div className="flex items-center justify-end gap-2 mt-4">
          <button onClick={onCancelar} disabled={rodando} className="px-3 py-2 rounded-xl border border-line text-sm text-ink-6 hover:bg-white/5">
            Cancelar
          </button>
          <button
            onClick={confirmar}
            disabled={rodando}
            className={`px-4 py-2 rounded-xl text-sm font-extrabold disabled:opacity-60 ${perigo ? 'bg-rose-500 text-white' : 'bg-brand text-[#04120a]'}`}
          >
            {rodando ? 'Aguarde…' : rotuloConfirmar}
          </button>
        </div>
      </div>
    </div>
  )
}
