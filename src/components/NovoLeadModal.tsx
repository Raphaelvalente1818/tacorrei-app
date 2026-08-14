import { useState, type FormEvent } from 'react'
import { X } from 'lucide-react'
import { supabase } from '../lib/supabase'
import type { OrigemLead } from '../lib/database.types'

const ORIGENS: Array<{ value: OrigemLead; label: string }> = [
  { value: 'indicacao', label: 'Indicação' },
  { value: 'campanha', label: 'Campanha' },
  { value: 'cold_call', label: 'Cold call' },
  { value: 'site', label: 'Site' },
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'outro', label: 'Outro' },
]

const inputCls = 'w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none'
const labelCls = 'block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1'

export default function NovoLeadModal({
  onClose,
  onCreated,
}: {
  onClose: () => void
  onCreated: () => void
}) {
  const [nome, setNome] = useState('')
  const [telefone, setTelefone] = useState('')
  const [cidade, setCidade] = useState('')
  const [uf, setUf] = useState('')
  const [placa, setPlaca] = useState('')
  const [modelo, setModelo] = useState('')
  const [rntrc, setRntrc] = useState('')
  const [renavam, setRenavam] = useState('')
  const [ultimaAfericao, setUltimaAfericao] = useState('')
  const [origem, setOrigem] = useState<OrigemLead>('outro')
  const [observacoes, setObservacoes] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError(null)
    const { error } = await supabase.from('caminhoneiros').insert({
      nome,
      telefone,
      cidade: cidade || null,
      uf: uf ? uf.toUpperCase() : null,
      placa_veiculo: placa || null,
      modelo_veiculo: modelo || null,
      rntrc: rntrc || null,
      renavam: renavam || null,
      data_ultima_afericao: ultimaAfericao || null,
      observacoes: observacoes || null,
      origem,
    })
    setSaving(false)
    if (error) {
      setError(error.message)
      return
    }
    onCreated()
  }

  return (
    <div className="fixed inset-0 bg-ink/40 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-extrabold text-ink">Novo lead</h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3">
          <div>
            <label className={labelCls}>Nome *</label>
            <input required value={nome} onChange={(e) => setNome(e.target.value)} className={inputCls} />
          </div>
          <div>
            <label className={labelCls}>Telefone *</label>
            <input
              required
              value={telefone}
              onChange={(e) => setTelefone(e.target.value)}
              placeholder="(11) 91234-5678"
              className={inputCls}
            />
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="col-span-2">
              <label className={labelCls}>Cidade</label>
              <input value={cidade} onChange={(e) => setCidade(e.target.value)} className={inputCls} />
            </div>
            <div>
              <label className={labelCls}>UF</label>
              <input
                value={uf}
                maxLength={2}
                onChange={(e) => setUf(e.target.value)}
                className={`${inputCls} uppercase`}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className={labelCls}>Placa do veículo</label>
              <input
                value={placa}
                onChange={(e) => setPlaca(e.target.value)}
                className={`${inputCls} uppercase`}
              />
            </div>
            <div>
              <label className={labelCls}>Modelo do veículo</label>
              <input value={modelo} onChange={(e) => setModelo(e.target.value)} className={inputCls} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className={labelCls}>RNTRC</label>
              <input value={rntrc} onChange={(e) => setRntrc(e.target.value)} className={inputCls} />
            </div>
            <div>
              <label className={labelCls}>Renavam</label>
              <input value={renavam} onChange={(e) => setRenavam(e.target.value)} className={inputCls} />
            </div>
          </div>
          <div>
            <label className={labelCls}>Última aferição</label>
            <input
              type="date"
              value={ultimaAfericao}
              onChange={(e) => setUltimaAfericao(e.target.value)}
              className={inputCls}
            />
          </div>
          <div>
            <label className={labelCls}>Origem</label>
            <select
              value={origem}
              onChange={(e) => setOrigem(e.target.value as OrigemLead)}
              className={`${inputCls} bg-card`}
            >
              {ORIGENS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelCls}>Observações</label>
            <textarea
              value={observacoes}
              onChange={(e) => setObservacoes(e.target.value)}
              rows={2}
              className={`${inputCls} resize-none`}
            />
          </div>

          {error && <p className="text-sm text-danger">{error}</p>}

          <button
            type="submit"
            disabled={saving}
            className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60 mt-2"
          >
            {saving ? 'Salvando…' : 'Salvar lead'}
          </button>
        </form>
      </div>
    </div>
  )
}
