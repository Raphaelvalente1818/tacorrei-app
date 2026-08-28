import { useState, type FormEvent } from 'react'
import { X, Building2 } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/AuthContext'

// Cadastro de empresa com contrato. Sem isto, empresa só existiria vindo da
// importação — e caminhão novo chegando não teria onde ser encaixado.
//
// O CNPJ é a chave: é ele que dedupe na importação e evita que "MBK", "MBK LTDA"
// e "MBK Comércio" virem três empresas. Fica opcional no cadastro manual, mas
// preenchê-lo é o que faz a próxima importação reconhecer a empresa em vez de
// duplicá-la.
export type EmpresaEditavel = {
  id?: string
  nome: string
  cnpj: string | null
  contato: string | null
  telefone: string | null
  observacoes?: string | null
  unidade_id?: string
}

const inputCls = 'w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none'
const labelCls = 'block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1'

export default function EmpresaModal({
  empresa,
  onClose,
  onSaved,
}: {
  empresa: EmpresaEditavel | null
  onClose: () => void
  // Devolve o id e o nome da empresa salva, para o chamador emendar direto na
  // segunda fase (colar as placas) sem a pessoa ter que procurar onde clicar.
  onSaved: (salva?: { id: string; nome: string }) => void
}) {
  const { membro, unidades, unidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  const editando = Boolean(empresa?.id)

  const [nome, setNome] = useState(empresa?.nome ?? '')
  const [cnpj, setCnpj] = useState(empresa?.cnpj ?? '')
  const [contato, setContato] = useState(empresa?.contato ?? '')
  const [telefone, setTelefone] = useState(empresa?.telefone ?? '')
  const [observacoes, setObservacoes] = useState(empresa?.observacoes ?? '')
  const [unidadeId, setUnidadeId] = useState(empresa?.unidade_id ?? unidadeAtiva ?? '')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (isAdmin && !unidadeId) {
      setError('Escolha a unidade da empresa.')
      return
    }
    setSaving(true)

    const registro: Record<string, unknown> = {
      nome: nome.trim(),
      cnpj: cnpj.trim() || null,
      contato: contato.trim() || null,
      telefone: telefone.trim() || null,
      observacoes: observacoes.trim() || null,
    }
    if (isAdmin && unidadeId) registro.unidade_id = unidadeId

    const { data, error: err } = editando
      ? await supabase.from('empresas').update(registro).eq('id', empresa!.id!).select('id,nome').single()
      : await supabase.from('empresas').insert(registro).select('id,nome').single()

    setSaving(false)
    if (err) {
      // O índice único de CNPJ por unidade é a rede de segurança contra empresa repetida.
      setError(
        err.message.includes('uq_empresas_cnpj')
          ? 'Já existe uma empresa com este CNPJ nesta unidade.'
          : err.message
      )
      return
    }
    const salva = data as { id: string; nome: string } | null
    onSaved(editando || !salva ? undefined : salva)
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <Building2 size={18} className="text-lucro" />
            {editando ? 'Editar empresa' : 'Nova empresa'}
          </h2>
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
            <label className={labelCls}>Razão social / nome *</label>
            <input required value={nome} onChange={(e) => setNome(e.target.value)} className={inputCls} />
          </div>

          <div>
            <label className={labelCls}>CNPJ</label>
            <input
              value={cnpj}
              onChange={(e) => setCnpj(e.target.value)}
              placeholder="00.000.000/0001-00"
              className={inputCls}
            />
            <p className="text-xs text-ink-4 mt-1">
              É por ele que a próxima importação reconhece a empresa em vez de criar outra.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className={labelCls}>Quem recebe o aviso</label>
              <input value={contato} onChange={(e) => setContato(e.target.value)} className={inputCls} />
            </div>
            <div>
              <label className={labelCls}>WhatsApp do contato</label>
              <input
                value={telefone}
                onChange={(e) => setTelefone(e.target.value)}
                placeholder="(11) 91234-5678"
                className={inputCls}
              />
            </div>
          </div>

          <div>
            <label className={labelCls}>Observações</label>
            <textarea
              value={observacoes}
              onChange={(e) => setObservacoes(e.target.value)}
              rows={2}
              placeholder="Ex.: exige ordem de serviço, atende só de manhã…"
              className={`${inputCls} resize-none`}
            />
          </div>

          {error && <p className="text-sm text-danger">{error}</p>}

          <button
            type="submit"
            disabled={saving}
            className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60 mt-2"
          >
            {saving ? 'Salvando…' : editando ? 'Salvar alterações' : 'Cadastrar empresa'}
          </button>
        </form>
      </div>
    </div>
  )
}
