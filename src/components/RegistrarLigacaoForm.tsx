import { useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import type { CanalContato, ResultadoLigacao, StatusLead } from '../lib/database.types'
import { CANAL_CONTATO_LABEL } from '../lib/status'
import ConfirmarModal from './ConfirmarModal'

// 0095 — A OPERADORA NÃO PRECISA SABER QUAL BOTÃO APERTAR.
// Ela conta o que aconteceu na ligação e o sistema aplica o efeito: libera a mensagem,
// grava que ele aferiu no concorrente, tira da fila quem roda em outra praça.
// Antes disso, o formulário só inseria em `ligacoes` e mexia no status; autorização e
// "aferiu em outro posto" eram botões separados, e a operadora tinha de saber a regra.
//
// Tudo passa por uma RPC só (`registrar_contato`), que grava o contato E o efeito na
// mesma transação — sem chance de sobrar contato sem efeito, ou o contrário.
//
// O WhatsApp de propósito NÃO é acionado por aqui: o envio tem seis travas (cota do dia,
// intervalo, cooldown por telefone, relação) e foi mensagem fora de trava que derrubou o
// número em 28/08. "Autorizou mensagem" apenas LIBERA o botão; quem envia é ela, na ficha.

type Desfecho = {
  valor: ResultadoLigacao
  label: string
  // o que o sistema faz — aparece na tela ANTES de salvar
  efeito: string
  status: StatusLead
  // desfechos que mexem em mais que o status pedem confirmação
  confirmar?: boolean
  perigo?: boolean
  pedeData?: boolean
}

const DESFECHOS: Desfecho[] = [
  {
    valor: 'atendeu',
    label: 'Atendeu — conversamos',
    efeito: 'Fica como Contatado e continua na fila.',
    status: 'contatado',
  },
  {
    valor: 'nao_atendeu',
    label: 'Não atendeu',
    efeito: 'Fica como Sem resposta e volta na fila para você tentar de novo.',
    status: 'sem_resposta',
  },
  {
    valor: 'numero_invalido',
    label: 'Número inválido',
    efeito:
      'O telefone é marcado como ruim e o caminhão sai da fila — você não vai receber ele de novo amanhã. Volta sozinho se alguém atender ou se o número for trocado.',
    status: 'invalido',
    confirmar: true,
  },
  {
    valor: 'reagendar',
    label: 'Pediu para ligar novamente',
    efeito: 'Fica como Contatado. Anote nas notas o melhor dia e horário.',
    status: 'contatado',
  },
  {
    valor: 'autorizou_whatsapp',
    label: 'Autorizou mensagem',
    efeito:
      'Libera o botão Enviar WhatsApp na ficha. A mensagem não sai agora — quem envia é você, respeitando a cota do dia.',
    status: 'contatado',
  },
  {
    valor: 'agendou',
    label: 'Agendou a aferição',
    efeito: 'Fica como Agendado. Em seguida abre a tela para você marcar o dia e a hora.',
    status: 'agendado',
  },
  {
    valor: 'aferiu_fora',
    label: 'Já aferiu no concorrente',
    efeito:
      'Grava a data que ele informou, marca que foi em outro posto e tira da fila por 2 anos. Se era cliente da casa, entra como perda no histórico.',
    status: 'novo',
    confirmar: true,
    perigo: true,
    pedeData: true,
  },
  {
    valor: 'fora_de_area',
    label: 'Caminhão roda em outra praça',
    efeito:
      'Sai da fila: este caminhão afere onde ele roda, não é nosso alvo. Continua visível para a gestão no filtro "Fora de área", e dá para desfazer.',
    status: 'novo',
    confirmar: true,
  },
  {
    valor: 'recusou',
    label: 'Não quer / recusou',
    efeito: 'Fica como Recusado e sai do caminho por um tempo.',
    status: 'recusado',
  },
]

// Tipos de contato manuais (WhatsApp e aferição são registrados pelos botões da ficha)
const CANAIS: CanalContato[] = ['ligacao_ativa', 'ligacao_passiva']

export default function RegistrarLigacaoForm({
  caminhoneiroId,
  onSaved,
}: {
  caminhoneiroId: string
  // Devolve o status novo e o desfecho — o LeadDetail usa o desfecho para abrir o
  // agendamento quando ela marca "Agendou a aferição".
  onSaved: (novoStatus: StatusLead, resultado: ResultadoLigacao) => void
}) {
  const [canal, setCanal] = useState<CanalContato>('ligacao_ativa')
  const [valor, setValor] = useState<ResultadoLigacao>('atendeu')
  const [notas, setNotas] = useState('')
  const [dataAfericao, setDataAfericao] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmando, setConfirmando] = useState(false)

  const desfecho = DESFECHOS.find((d) => d.valor === valor) ?? DESFECHOS[0]
  const hoje = new Date().toISOString().slice(0, 10)

  async function gravar() {
    setSaving(true)
    setError(null)
    const { error: err } = await supabase.rpc('registrar_contato', {
      p_lead: caminhoneiroId,
      p_canal: canal,
      p_resultado: valor,
      p_notas: notas || null,
      p_data: desfecho.pedeData ? dataAfericao : null,
    })
    setSaving(false)
    setConfirmando(false)
    if (err) {
      setError(err.message)
      return
    }
    setNotas('')
    setDataAfericao('')
    onSaved(desfecho.status, valor)
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (desfecho.pedeData && !dataAfericao) {
      setError('Informe a data em que ele aferiu.')
      return
    }
    if (desfecho.confirmar) {
      setConfirmando(true)
      return
    }
    void gravar()
  }

  return (
    <>
      <form onSubmit={handleSubmit} className="space-y-3">
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
            O que aconteceu
          </label>
          <select
            value={valor}
            onChange={(e) => setValor(e.target.value as ResultadoLigacao)}
            className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card"
          >
            {DESFECHOS.map((d) => (
              <option key={d.valor} value={d.valor}>
                {d.label}
              </option>
            ))}
          </select>
          {/* O efeito fica à vista ANTES de salvar: é assim que ela aprende a regra
              sem decorar manual, e é o que evita o clique errado. */}
          <p className="text-xs text-ink-4 mt-1.5 leading-relaxed">{desfecho.efeito}</p>
        </div>

        {desfecho.pedeData && (
          <div>
            <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
              Quando ele aferiu
            </label>
            <input
              type="date"
              value={dataAfericao}
              max={hoje}
              onChange={(e) => setDataAfericao(e.target.value)}
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card"
            />
          </div>
        )}

        <div>
          <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
            Notas
          </label>
          <textarea
            value={notas}
            onChange={(e) => setNotas(e.target.value)}
            rows={3}
            className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none resize-none"
            placeholder="O que foi conversado, melhor horário para retornar, etc."
          />
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="submit"
          disabled={saving}
          className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d transition-colors disabled:opacity-60"
        >
          {saving ? 'Salvando…' : 'Registrar contato'}
        </button>
      </form>

      {confirmando && (
        <ConfirmarModal
          titulo={desfecho.label}
          texto={desfecho.efeito}
          rotuloConfirmar="Confirmar"
          perigo={desfecho.perigo}
          onConfirmar={() => void gravar()}
          onCancelar={() => setConfirmando(false)}
        />
      )}
    </>
  )
}
