import { useState, type FormEvent } from 'react'
import { X, CheckCircle2, Building2, ClipboardCheck, Phone } from 'lucide-react'
import { supabase } from '../lib/supabase'
import type { CadastroDoLead } from '../lib/database.types'

// Marca que a aferição foi feita. A data vai para `data_ultima_afericao` — o MESMO
// campo que calcula o vencimento —, então o lead sai da fila agora e volta sozinho
// daqui a 2 anos, virando recompra. Também grava no histórico (canal 'presencial')
// para ficar registrado quem marcou e quando.
//
// Com "aferiu em outro posto" ligado, o caminhão sai da fila do mesmo jeito, mas o
// posto vira concorrente, o status volta a Novo e nada conta como aferição nossa
// (nem ponto, nem Produção). Antes disso o único jeito era marcar Aferido com uma
// nota — e o caminhão aparecia como cliente da casa sem ser.
//
// 0112 — O BALCÃO É O ÚNICO LUGAR ONDE O CADASTRO SAI DE GRAÇA. O caminhão está
// aqui, o dono com o documento na mão. Daqui a dois anos, quando a placa voltar
// para a fila, o que vale é ter o CPF (consulta no Inmetro, guia) e um telefone que
// seja DO DONO. Então, em cima da data, o modal mostra o que falta neste cadastro,
// com os campos ali mesmo. Regra combinada com o Emerson: NÃO obriga (campo
// obrigatório com o cliente esperando vira número inventado) e NÃO premia (pagar
// por esforço compra esforço, não resultado). Preenche se der, pula se não der.
// O que foi preenchido fica visível na Meta, por quem marcou — e o gestor cobra.
// O CPF entra por `salvar_dados_gru` (só escrita: a tela nunca o mostra de volta).
export default function RegistrarAfericaoModal({
  caminhoneiroId,
  cadastro,
  telefone,
  onClose,
  onSaved,
}: {
  caminhoneiroId: string
  cadastro?: CadastroDoLead | null
  telefone?: string | null
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

  // O que falta, e os campos para completar. Tudo opcional.
  const faltando = cadastro?.faltando ?? []
  const faltaDoc = faltando.includes('CPF/CNPJ')
  const faltaChassi = faltando.includes('Chassi')
  const faltaAno = false // ano não entra na definição de completo; o GRU pede à parte
  const faltaFone = faltando.includes('Telefone confirmado')
  const [doc, setDoc] = useState('')
  const [chassi, setChassi] = useState('')
  const [foneOk, setFoneOk] = useState(false)
  const [foneNovo, setFoneNovo] = useState('')

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

    // 0112 — primeiro o cadastro (se ela preencheu algo), depois a aferição. Se o
    // cadastro falhar (CPF com dígito a menos, por exemplo), a aferição NÃO é
    // gravada ainda: ela corrige ou apaga o campo e confirma de novo. Melhor do
    // que gravar a aferição e perder o dado que estava na mão.
    if (!outroPosto) {
      if (doc.trim() || chassi.trim()) {
        const { error: e1 } = await supabase.rpc('salvar_dados_gru', {
          p_lead: caminhoneiroId,
          p_documento: doc.trim() || null,
          p_chassi: chassi.trim() || null,
          p_ano_fabricacao: null,
        })
        if (e1) {
          setSaving(false)
          setError(e1.message)
          return
        }
      }
      if (foneOk) {
        const { error: e2 } = await supabase.rpc('confirmar_telefone', {
          p_lead: caminhoneiroId,
          p_telefone: foneNovo.trim() || null,
        })
        if (e2) {
          setSaving(false)
          setError(e2.message)
          return
        }
      }
    }

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

  const temFaltas = !outroPosto && (faltaDoc || faltaChassi || faltaFone || faltaAno)
  const inputCls = 'w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none'

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6 max-h-[92vh] overflow-y-auto">
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
          {/* 0112 — o que falta, em cima, com os campos. Some quando não falta nada
              (ou quando é aferição no concorrente: não há cadastro a aproveitar). */}
          {temFaltas && (
            <div className="rounded-xl border border-sky-500/30 bg-sky-500/10 p-3 space-y-2">
              <div className="flex items-center gap-2 text-sm font-bold text-sky-200">
                <ClipboardCheck size={15} /> Ele está aqui — aproveite para completar o cadastro
              </div>
              <p className="text-[11px] text-ink-4 leading-snug">
                Opcional. Faltam: {faltando.join(', ')}. O que você preencher agora vale daqui a dois anos, quando este
                caminhão voltar para a fila.
              </p>
              {faltaDoc && (
                <div>
                  <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">CPF ou CNPJ do dono (só números)</label>
                  <input value={doc} onChange={(e) => setDoc(e.target.value.replace(/\D/g, '').slice(0, 14))} inputMode="numeric" placeholder="11 ou 14 dígitos" className={inputCls} autoFocus />
                </div>
              )}
              {faltaChassi && (
                <div>
                  <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">Chassi (como está no CRLV)</label>
                  <input value={chassi} onChange={(e) => setChassi(e.target.value.toUpperCase())} placeholder="17 caracteres" className={inputCls} autoFocus={!faltaDoc} />
                </div>
              )}
              {faltaFone && (
                <div className="space-y-1.5">
                  <label className="flex items-start gap-2 text-sm cursor-pointer select-none">
                    <input type="checkbox" checked={foneOk} onChange={(e) => setFoneOk(e.target.checked)} className="mt-0.5" />
                    <span>
                      <span className="font-bold flex items-center gap-1"><Phone size={13} /> Confirmei o telefone com o dono</span>
                      <span className="block text-[11px] text-ink-4">
                        Cadastro: {telefone || 'sem telefone'}. Se ele deu outro número, digite abaixo.
                      </span>
                    </span>
                  </label>
                  {foneOk && (
                    <input value={foneNovo} onChange={(e) => setFoneNovo(e.target.value)} inputMode="tel" placeholder="Outro número? DDD + número (opcional)" className={inputCls} />
                  )}
                </div>
              )}
            </div>
          )}

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
              className={inputCls}
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
              className={`${inputCls} resize-none`}
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
