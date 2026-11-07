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

// 07/11 — ONDE FOI A ÚLTIMA AFERIÇÃO.
// O campo "Última aferição" era uma data solta. A operadora, com o caminhão no balcão,
// preenchia a data de hoje e salvava — e para o sistema isso era só um dado de cadastro:
// sem posto, sem histórico de Aferido, sem ponto, fora da carteira. O cruzamento com o
// OS Gold de outubro mostrou 224 caminhões assim (94% do balcão registrado, 59% pelo
// caminho errado). O texto de 28/10 não mudou nada; a tela convidava ao erro.
// Agora a pergunta é "onde foi": aferiu AQUI → o lead nasce e o Aferido é registrado
// na mesma hora (posto, histórico, ponto de balcão se o cadastro ficar perfeito);
// aferiu em OUTRO posto → a data entra com posto de concorrente; não sei → sem data.
type OndeAferiu = 'nao_sei' | 'aqui' | 'outro'

function hojeISO(): string {
  const d = new Date()
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

export default function NovoLeadModal({
  onClose,
  onCreated,
}: {
  onClose: () => void
  // `aferiuAqui` avisa a lista que o Aferido já foi registrado: ela leva a operadora
  // para a ficha, para completar o cadastro (é o que vale o ponto de balcão).
  onCreated: (id?: string, aferiuAqui?: boolean) => void
}) {
  const { membro, unidades, unidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  const [ondeAferiu, setOndeAferiu] = useState<OndeAferiu>('nao_sei')
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
    if (ondeAferiu !== 'nao_sei' && !ultimaAfericao) {
      setError('Informe a data da aferição.')
      return
    }
    if (ondeAferiu !== 'nao_sei' && ultimaAfericao > hojeISO()) {
      setError('A data da aferição não pode ser no futuro.')
      return
    }
    if (ondeAferiu === 'aqui' && !placa.trim()) {
      setError('Para registrar o Aferido, informe a placa.')
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
      // Aferiu AQUI: a data NÃO vai no cadastro — quem grava é o Aferido, logo
      // abaixo, junto com o posto, o histórico e o ponto. Em outro posto: data e
      // posto de concorrente, o mesmo que "Já aferiu no concorrente" na ficha.
      data_ultima_afericao: ondeAferiu === 'outro' ? ultimaAfericao : null,
      posto_afericao: ondeAferiu === 'outro' ? 'OUTRO POSTO (concorrente)' : null,
      observacoes: observacoes || null,
      origem,
      empresa_id: empresaId || null,
    }
    // Admin grava a unidade escolhida. Operador não envia: o gatilho preenche com a dele.
    if (isAdmin && unidadeId) registro.unidade_id = unidadeId
    const { data: criado, error } = await supabase
      .from('caminhoneiros')
      .insert(registro)
      .select('id')
      .single()
    if (error) {
      setSaving(false)
      setError(error.message)
      return
    }
    const novoId = (criado as { id: string } | null)?.id
    if (ondeAferiu === 'aqui' && novoId) {
      const { error: errAf } = await supabase.rpc('registrar_afericao', {
        p_lead: novoId,
        p_data: ultimaAfericao,
        p_notas: 'Registrado no cadastro do lead (aferiu aqui).',
        p_marcar_aferido: true,
      })
      setSaving(false)
      if (errAf) {
        // O lead existe; só o Aferido falhou. Avisar e mandar para a ficha, onde o
        // botão Aferido resolve — sem deixar o caminhão pela metade.
        setError(`O lead foi criado, mas o Aferido não: ${errAf.message}. Abra a ficha e clique em Aferido.`)
        return
      }
      onCreated(novoId, true)
      return
    }
    setSaving(false)
    onCreated(novoId, false)
  }

  const nomeUnidade =
    unidades.find((u) => u.id === (isAdmin && unidadeId ? unidadeId : unidadeAtiva))?.marca ||
    unidades.find((u) => u.id === (isAdmin && unidadeId ? unidadeId : unidadeAtiva))?.nome ||
    'nossa unidade'

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
          {/* Onde foi a última aferição — ver o comentário no topo do arquivo. */}
          <div className="rounded-xl border border-line p-3 space-y-2">
            <label className={labelCls}>Última aferição do tacógrafo</label>
            {(
              [
                { v: 'nao_sei', t: 'Não sei / nunca aferiu', d: 'O caminhão entra sem data. Quando aferir, use o botão Aferido na ficha.' },
                { v: 'aqui', t: `Aferiu AQUI, na ${nomeUnidade}`, d: 'O lead é criado e o Aferido já fica registrado — posto, histórico e ponto. Em seguida você vai para a ficha completar o cadastro (CPF/CNPJ, chassi, RENAVAM e celular confirmado valem 1 ponto de balcão).' },
                { v: 'outro', t: 'Aferiu em OUTRO posto', d: 'Entra como cliente de concorrente, com a data informada, e aparece na fila quando estiver vencendo.' },
              ] as Array<{ v: OndeAferiu; t: string; d: string }>
            ).map((o) => (
              <label key={o.v} className="flex items-start gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="onde_aferiu"
                  checked={ondeAferiu === o.v}
                  onChange={() => {
                    setOndeAferiu(o.v)
                    if (o.v === 'aqui' && !ultimaAfericao) setUltimaAfericao(hojeISO())
                  }}
                  className="mt-1"
                />
                <span className="text-sm">
                  <span className="font-bold text-ink">{o.t}</span>
                  {ondeAferiu === o.v && <span className="block text-xs text-ink-4 mt-0.5">{o.d}</span>}
                </span>
              </label>
            ))}
            {ondeAferiu !== 'nao_sei' && (
              <div>
                <label className={labelCls}>{ondeAferiu === 'aqui' ? 'Data em que aferiu aqui' : 'Data da aferição no outro posto'}</label>
                <input
                  type="date"
                  value={ultimaAfericao}
                  max={hojeISO()}
                  onChange={(e) => setUltimaAfericao(e.target.value)}
                  className={inputCls}
                />
              </div>
            )}
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
            {saving ? 'Salvando…' : ondeAferiu === 'aqui' ? 'Salvar lead e registrar Aferido' : 'Salvar lead'}
          </button>
        </form>
      </div>
    </div>
  )
}
