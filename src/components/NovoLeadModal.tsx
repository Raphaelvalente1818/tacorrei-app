import { useEffect, useState, type FormEvent } from 'react'
import { X } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/AuthContext'
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
  const { membro, unidades, unidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  const [nome, setNome] = useState('')
  const [telefone, setTelefone] = useState('')
  // Admin escolhe em qual unidade o lead entra (padrão: a unidade ativa no menu).
  const [unidadeId, setUnidadeId] = useState<string>(unidadeAtiva ?? '')
  const [cidade, setCidade] = useState('')
  const [uf, setUf] = useState('')
  const [placa, setPlaca] = useState('')
  const [modelo, setModelo] = useState('')
  const [rntrc, setRntrc] = useState('')
  const [renavam, setRenavam] = useState('')
  const [ultimaAfericao, setUltimaAfericao] = useState('')
  const [origem, setOrigem] = useState<OrigemLead>('outro')
  // Empresa com contrato. Quando o veículo pertence a uma, ele SAI da fila de
  // prospecção e passa a ser avisado pela relação mensal daquela empresa — o
  // motorista que traz o caminhão pode ser qualquer um, então a placa é o vínculo.
  const [empresaId, setEmpresaId] = useState('')
  const [empresas, setEmpresas] = useState<Array<{ id: string; nome: string }>>([])
  const [observacoes, setObservacoes] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelado = false
    const alvo = isAdmin && unidadeId ? unidadeId : unidadeAtiva
    let q = supabase.from('empresas').select('id,nome').eq('ativo', true).order('nome')
    if (alvo) q = q.eq('unidade_id', alvo)
    q.then(({ data, error }) => {
      if (cancelado || error) return
      setEmpresas((data as Array<{ id: string; nome: string }>) ?? [])
    })
    return () => {
      cancelado = true
    }
  }, [isAdmin, unidadeId, unidadeAtiva])

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (isAdmin && !unidadeId) {
      setError('Escolha a unidade em que o lead deve entrar.')
      return
    }
    setSaving(true)
    const registro: Record<string, unknown> = {
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
      empresa_id: empresaId || null,
    }
    // Admin grava a unidade escolhida. Operador não envia: o gatilho preenche com a dele.
    if (isAdmin && unidadeId) registro.unidade_id = unidadeId
    const { error } = await supabase.from('caminhoneiros').insert(registro)
    setSaving(false)
    if (error) {
      setError(error.message)
      return
    }
    onCreated()
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-extrabold text-ink">Novo lead</h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3">
          {isAdmin && (
            <div>
              <label className={labelCls}>Unidade *</label>
              <select
                required
                value={unidadeId}
                onChange={(e) => setUnidadeId(e.target.value)}
                className={`${inputCls} bg-card`}
              >
                <option value="">Selecione a unidade…</option>
                {unidades.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nome}
                  </option>
                ))}
              </select>
            </div>
          )}
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
          {empresas.length > 0 && (
            <div>
              <label className={labelCls}>Empresa (contrato)</label>
              <select
                value={empresaId}
                onChange={(e) => setEmpresaId(e.target.value)}
                className={`${inputCls} bg-card`}
              >
                <option value="">Nenhuma — é autônomo</option>
                {empresas.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.nome}
                  </option>
                ))}
              </select>
              <p className="text-xs text-ink-4 mt-1">
                Escolhendo uma empresa, este veículo sai da fila de prospecção e passa a entrar na
                relação mensal dela.
              </p>
            </div>
          )}
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
