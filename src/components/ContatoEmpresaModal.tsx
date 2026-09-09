import { useState, type FormEvent } from 'react'
import { Phone, X } from 'lucide-react'
import { supabase } from '../lib/supabase'
import type { CanalContato, ResultadoLigacao } from '../lib/database.types'
import { CANAL_CONTATO_LABEL, RESULTADO_LIGACAO_LABEL } from '../lib/status'

// ── Contato no nível da EMPRESA ──────────────────────────────────────────────
// Numa frota a conversa é com o gestor e vale para a frota inteira: uma
// ligação resolve vinte placas. O registro é UMA linha em `ligacoes` (não uma
// por caminhão, senão a produção do Dashboard inflaria vinte vezes) e desce
// para as placas que ainda estão em aberto, para a frota sair da fila e a
// colega não ligar de novo amanhã para a mesma pessoa.
//
// Não há WhatsApp aqui de propósito: a cota diária, o intervalo entre envios e
// a trava de telefone repetido moram na ficha do lead. Um disparo por empresa
// passaria por fora de tudo isso.

const CANAIS: CanalContato[] = ['ligacao_ativa', 'ligacao_passiva']

const RESULTADOS: ResultadoLigacao[] = [
  'atendeu',
  'nao_atendeu',
  'numero_invalido',
  'recusou',
  'agendou',
  'reagendar',
]

// O que cada resultado faz com as placas em aberto. Precisa estar na tela:
// "Recusou" apaga a frota inteira da fila, e isso não pode ser surpresa.
const EFEITO: Record<string, string> = {
  atendeu: 'ficam como Contatado',
  nao_atendeu: 'ficam como Sem resposta',
  numero_invalido: 'ficam como Inválido',
  recusou: 'ficam como Recusado — a frota sai da fila',
  agendou: 'ficam como Contatado (o agendamento é de cada caminhão)',
  reagendar: 'ficam como Contatado',
}

function telefoneLimpo(tel: string | null): string | null {
  if (!tel) return null
  const d = tel.replace(/\D/g, '')
  return d.length >= 10 ? d : null
}

export default function ContatoEmpresaModal({
  empresa,
  onClose,
  onSaved,
}: {
  empresa: { id: string; nome: string; contato: string | null; telefone: string | null }
  onClose: () => void
  onSaved: () => void
}) {
  const [canal, setCanal] = useState<CanalContato>('ligacao_ativa')
  const [resultado, setResultado] = useState<ResultadoLigacao>('atendeu')
  const [notas, setNotas] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  const fone = telefoneLimpo(empresa.telefone)

  async function salvar(e: FormEvent) {
    e.preventDefault()
    setSalvando(true)
    setErro(null)

    const { data, error } = await supabase.rpc('registrar_ligacao_empresa', {
      p_empresa: empresa.id,
      p_canal: canal,
      p_resultado: resultado,
      p_notas: notas || null,
    })

    setSalvando(false)
    if (error) {
      setErro(error.message)
      return
    }
    const n = (data as { veiculos?: number } | null)?.veiculos ?? 0
    onSaved()
    onClose()
    // O aviso de quantas placas mudaram sobe para a tela de trás pelo recarregamento;
    // aqui só fechamos, para a operadora já cair na próxima empresa da fila.
    void n
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-start justify-between mb-1 gap-3">
          <h2 className="text-base font-extrabold text-ink">{empresa.nome}</h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink shrink-0">
            <X size={18} />
          </button>
        </div>

        <div className="mb-4 text-sm">
          <p className="text-ink-6">{empresa.contato ?? 'sem contato no cadastro'}</p>
          {fone ? (
            <a
              href={`tel:+55${fone}`}
              className="inline-flex items-center gap-1.5 mt-1 font-bold text-brand hover:underline"
            >
              <Phone size={14} /> {empresa.telefone}
            </a>
          ) : (
            <p className="text-xs text-amber-300 mt-1">
              Sem telefone válido no cadastro — corrija no lápis, ao lado do nome.
            </p>
          )}
        </div>

        <form onSubmit={salvar} className="space-y-3">
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
            <p className="text-xs text-ink-4 mt-1">
              As placas ainda em aberto {EFEITO[resultado]}.
            </p>
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
              placeholder="Com quem falou, a objeção, quando retornar."
            />
          </div>

          {erro && <p className="text-sm text-danger">{erro}</p>}

          <button
            type="submit"
            disabled={salvando}
            className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            {salvando ? 'Registrando…' : 'Registrar contato com a empresa'}
          </button>
        </form>
      </div>
    </div>
  )
}
