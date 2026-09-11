import { useState, type FormEvent } from 'react'
import { X, CheckCircle2, Building2 } from 'lucide-react'
import { supabase } from '../lib/supabase'

// Marca que a aferição foi feita. A data vai para `data_ultima_afericao` — o MESMO
// campo que calcula o vencimento —, então o lead sai da fila agora e volta sozinho
// daqui a 2 anos, virando recompra. Também grava no histórico (canal 'presencial')
// para ficar registrado quem marcou e quando.
//
// Com "aferiu em outro posto" ligado, o caminhão sai da fila do mesmo jeito, mas o
// posto vira concorrente, o status volta a Novo e nada conta como aferição nossa
// (nem ponto, nem Produção). Antes disso o único jeito era marcar Aferido com uma
// nota — e o caminhão aparecia como cliente da casa sem ser.
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
  const [outroPosto, setOutroPosto] = useState(false)
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
    const { error: rpcError } = outroPosto
      ? await supabase.rpc('registrar_afericao_fora', {
          p_lead: caminhoneiroId,
          p_data: data,
          p_notas: notas.trim() || null,
        })
      : await supabase.rpc('registrar_afericao', {
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
          {outroPosto
            ? 'O caminhão sai da fila por 2 anos como cliente do concorrente. Não conta como aferição nossa nem gera ponto.'
            : 'O certificado passa a valer por 2 anos a partir desta data, e o lead volta para a fila quando estiver perto de vencer.'}
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

          <label
            className={`flex items-start gap-2 p-3 rounded-xl border text-sm cursor-pointer select-none ${
              outroPosto ? 'border-warn bg-warn/10' : 'border-line'
            }`}
          >
            <input
              type="checkbox"
              checked={outroPosto}
              onChange={(e) => setOutroPosto(e.target.checked)}
              className="mt-0.5"
            />
            <span>
              <span className="font-bold flex items-center gap-1">
                <Building2 size={14} /> Aferiu em outro posto
              </span>
              <span className="block text-xs text-ink-4">
                O motorista disse que já renovou no concorrente. Tira da fila sem marcar como cliente nosso.
              </span>
            </span>
          </label>

          {error && <p className="text-sm text-danger">{error}</p>}

          <button
            type="submit"
            disabled={saving}
            className={`w-full py-2.5 rounded-xl font-bold text-sm transition-colors disabled:opacity-60 ${
              outroPosto
                ? 'bg-warn text-[#04120a] hover:bg-warn/90'
                : 'bg-brand text-[#04120a] hover:bg-brand-d'
            }`}
          >
            {saving ? 'Salvando…' : outroPosto ? 'Registrar aferição no concorrente' : 'Confirmar aferição'}
          </button>
        </form>
      </div>
    </div>
  )
}
