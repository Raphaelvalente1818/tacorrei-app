import { useEffect, useMemo, useState } from 'react'
import { MessageCircle, RotateCcw, Save } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { MENSAGEM_PADRAO, configMensagemDe, useAuth } from '../../lib/AuthContext'
import type { Unidade } from '../../lib/database.types'
import { botao } from './ui'

// ── Mensagens ────────────────────────────────────────────────────────────────
// A mensagem tem quatro blocos fixos: quem fala · o fato · o convite · a porta de
// saída. O gestor mexe só no que é da unidade dele — a linha do credenciamento, os
// dois convites e o texto do aviso das frotas com contrato. Saudação, nome, o fato
// (placa e data) e a porta de saída são do app, e não se editam: foi a porta de
// saída que parou de derrubar o número em 28/08.

type Campo = 'msg_credencial' | 'msg_convite_vencido' | 'msg_convite_a_vencer' | 'msg_aviso_contrato'

const CAMPOS: { id: Campo; rotulo: string; ajuda: string; padrao: string }[] = [
  {
    id: 'msg_credencial',
    rotulo: 'Linha de credenciamento (bloco 1 — quem fala)',
    ajuda: 'Vem logo abaixo de "Aqui é a Fulana, da Marca". Uma linha, sem emoji.',
    padrao: MENSAGEM_PADRAO.credencial,
  },
  {
    id: 'msg_convite_vencido',
    rotulo: 'Convite para caminhão vencido (bloco 3)',
    ajuda: 'Uma frase. Sem prometer horário — a oficina atende por ordem de chegada.',
    padrao: MENSAGEM_PADRAO.conviteVencido,
  },
  {
    id: 'msg_convite_a_vencer',
    rotulo: 'Convite para caminhão a vencer (bloco 3)',
    ajuda: 'Mesma regra: uma frase, sem horário.',
    padrao: MENSAGEM_PADRAO.conviteAVencer,
  },
  {
    id: 'msg_aviso_contrato',
    rotulo: 'Aviso mensal das frotas com contrato (depois da relação de placas)',
    ajuda: 'O que vem depois da lista de veículos vencendo no mês.',
    padrao: MENSAGEM_PADRAO.avisoContrato,
  },
]

const LIMITE = 240

export default function Mensagens({ unidadeId }: { unidadeId: string }) {
  const { unidades, recarregarUnidades, membro } = useAuth()
  const unidade = unidades.find((u) => u.id === unidadeId) ?? null
  const [valores, setValores] = useState<Record<Campo, string>>({
    msg_credencial: '', msg_convite_vencido: '', msg_convite_a_vencer: '', msg_aviso_contrato: '',
  })
  const [salvando, setSalvando] = useState(false)
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)

  useEffect(() => {
    setValores({
      msg_credencial: unidade?.msg_credencial ?? '',
      msg_convite_vencido: unidade?.msg_convite_vencido ?? '',
      msg_convite_a_vencer: unidade?.msg_convite_a_vencer ?? '',
      msg_aviso_contrato: unidade?.msg_aviso_contrato ?? '',
    })
    setMsg(null)
  }, [unidade])

  const alterado = CAMPOS.some((c) => (valores[c.id] ?? '') !== (unidade?.[c.id] ?? ''))

  // A prévia usa o que está sendo digitado, com os padrões aplicados por cima.
  const cfg = useMemo(() => configMensagemDe({ ...(unidade ?? { id: unidadeId, nome: 'Unidade' }), ...valores } as Unidade), [unidade, unidadeId, valores])
  const quem = membro?.nome?.trim().split(/\s+/)[0] ?? 'Fulana'
  const artigo = quem.slice(-1).toLowerCase() === 'a' ? 'a' : 'o'
  const onde = cfg.endereco ? `\n\nEstamos na ${cfg.endereco}` : ''
  const previa = `Bom dia, José!
Aqui é ${artigo} ${quem}, da ${cfg.marca}
${cfg.credencial}

Verificamos aqui que o certificado do tacógrafo da placa ABC1D23 consta vencido desde 05/09/2026.

${cfg.conviteVencido}

Se esse veículo não for mais seu, me avisa que eu retiro do cadastro.
Estou à sua disposição para qualquer dúvida.${onde}`

  async function salvar() {
    setSalvando(true)
    setMsg(null)
    const { error } = await supabase.rpc('configurar_unidade', { p_unidade: unidadeId, p_campos: valores })
    setSalvando(false)
    if (error) {
      setMsg({ tipo: 'erro', texto: error.message })
      return
    }
    await recarregarUnidades()
    setMsg({ tipo: 'ok', texto: 'Salvo. As próximas mensagens já saem com este texto.' })
  }

  return (
    <div className="grid lg:grid-cols-2 gap-4">
      <div className="card p-5 space-y-4">
        <div>
          <h2 className="text-sm font-extrabold text-ink flex items-center gap-2">
            <MessageCircle size={16} className="text-brand" /> Textos da unidade
          </h2>
          <p className="text-xs text-ink-4 mt-1">
            Vazio = o texto padrão do Aferi+. A estrutura de quatro blocos e a porta de saída não mudam — é o que protege o número.
            {' '}Marca e endereço ({cfg.marca}{cfg.endereco ? `, ${cfg.endereco}` : ', sem endereço'}) são cadastro do admin geral.
          </p>
        </div>

        {CAMPOS.map((c) => (
          <div key={c.id}>
            <div className="flex items-center justify-between mb-1">
              <label className="text-xs font-bold uppercase tracking-wide text-ink-4">{c.rotulo}</label>
              {valores[c.id] && (
                <button type="button" onClick={() => setValores((v) => ({ ...v, [c.id]: '' }))} className="text-[11px] text-ink-4 hover:text-brand flex items-center gap-1">
                  <RotateCcw size={11} /> padrão
                </button>
              )}
            </div>
            <textarea
              value={valores[c.id]}
              onChange={(e) => setValores((v) => ({ ...v, [c.id]: e.target.value.slice(0, LIMITE) }))}
              placeholder={c.padrao}
              rows={2}
              className="w-full px-3 py-2 border border-line rounded-xl text-sm bg-card focus-ring outline-none"
            />
            <div className="flex justify-between text-[11px] text-ink-4 mt-0.5">
              <span>{c.ajuda}</span>
              <span className="tabular-nums">{valores[c.id].length}/{LIMITE}</span>
            </div>
          </div>
        ))}

        <div className="flex items-center gap-3">
          <button onClick={salvar} disabled={!alterado || salvando} className={botao}>
            <Save size={15} /> {salvando ? 'Salvando…' : 'Salvar textos'}
          </button>
          {msg && <span className={`text-sm ${msg.tipo === 'ok' ? 'text-lucro' : 'text-danger'}`}>{msg.texto}</span>}
        </div>
      </div>

      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink mb-1">Prévia — caminhão vencido, autônomo</h2>
        <p className="text-xs text-ink-4 mb-3">Como a operadora vai ver antes de enviar. Nome, placa e data são exemplo.</p>
        <pre className="whitespace-pre-wrap text-sm text-ink-6 bg-card2 border border-line rounded-xl p-4 font-sans leading-relaxed">{previa}</pre>
        <p className="text-[11px] text-ink-4 mt-3">
          Em frota, o app troca a porta de saída para "Se algum desses veículos não for mais de vocês…" e acrescenta a lista de placas. Cliente da casa recebe "Sua última aferição foi conosco". Nada disso se configura.
        </p>
      </div>
    </div>
  )
}
