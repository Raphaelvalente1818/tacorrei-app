import { useEffect, useState, useCallback } from 'react'
import { useParams, Link } from 'react-router-dom'
import {
  ArrowLeft, Phone, MapPin, Truck, CalendarPlus, FileText, History, Pencil, Check, X,
  MessageCircle, AlertTriangle, Ban, Trash2, CheckCircle2,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/AuthContext'
import type { Agendamento, Caminhoneiro, Ligacao } from '../lib/database.types'
import {
  CANAL_CONTATO_LABEL,
  RESULTADO_LIGACAO_LABEL,
  STATUS_AGENDAMENTO_CLASSES,
  STATUS_AGENDAMENTO_LABEL,
  STATUS_LEAD_CLASSES,
  STATUS_LEAD_LABEL,
} from '../lib/status'
import Badge from '../components/Badge'
import RegistrarLigacaoForm from '../components/RegistrarLigacaoForm'
import AgendarAfericaoModal from '../components/AgendarAfericaoModal'
import RegistrarAfericaoModal from '../components/RegistrarAfericaoModal'

const VALIDADE_ANOS = 2

// Marca e endereço que aparecem nas mensagens de WhatsApp, por unidade.
// A chave é o `unidades.id` do Supabase. Ao abrir uma unidade nova, basta
// adicionar a linha dela aqui; quem não estiver no mapa cai no padrão abaixo.
const UNIDADE_SANTO_ANDRE = '146237d6-5983-4986-b4bd-51f9e1d690c3'
const UNIDADE_SAO_BERNARDO = '265f0c74-123e-4886-9683-b70793c30b61'

type MarcaUnidade = { marca: string; endereco: string }

const MARCA_PADRAO: MarcaUnidade = {
  marca: 'Lacre Tacógrafos',
  endereco: 'Av. dos Estados, 7050, Santo André',
}

const MARCA_POR_UNIDADE: Record<string, MarcaUnidade> = {
  [UNIDADE_SANTO_ANDRE]: MARCA_PADRAO,
  [UNIDADE_SAO_BERNARDO]: {
    marca: 'Tacorrei Tacógrafos',
    endereco: 'Rua dos Feltrins, 1300 bairro Demarchi - São Bernardo',
  },
}

function marcaDoLead(lead: Caminhoneiro): MarcaUnidade {
  return MARCA_POR_UNIDADE[lead.unidade_id] ?? MARCA_PADRAO
}

function formatDateBR(iso: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  if (!y || !m || !d) return iso
  return `${d}/${m}/${y}`
}

// Vencimento = última aferição + 2 anos. Retorna a data e se já está vencido.
function vencimentoLead(iso: string | null): { venc: Date; vencido: boolean } | null {
  if (!iso) return null
  const base = new Date(iso.slice(0, 10) + 'T00:00:00')
  if (isNaN(base.getTime())) return null
  const venc = new Date(base)
  venc.setFullYear(venc.getFullYear() + VALIDADE_ANOS)
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)
  return { venc, vencido: venc.getTime() < hoje.getTime() }
}

function fmtDia(d: Date): string {
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`
}

// Normaliza o telefone para o formato do WhatsApp (DDI 55 + números). null se inválido.
function numeroWhatsapp(tel: string | null): string | null {
  if (!tel) return null
  const d = tel.replace(/\D/g, '')
  if (d.length < 10) return null
  return d.startsWith('55') ? d : '55' + d
}

// Escolhe a mensagem conforme a situação: vencido, a vencer ou sem data de aferição.
function montarMensagem(lead: Caminhoneiro, info: { venc: Date; vencido: boolean } | null): string {
  const placa = lead.placa_veiculo
  const { marca, endereco } = marcaDoLead(lead)

  if (info && info.vencido) {
    const veiculo = placa ? `Veículo com a placa ${placa}` : 'Seu veículo'
    return `⚠️⚠️⚠️
Bom dia!
${veiculo} está com o certificado do Tacógrafo vencido desde ${fmtDia(info.venc)}.
Atualize e evite multas.
${marca}
Ensaio Inmetro
End: ${endereco}
Temos condições especiais para você.`
  }

  if (info && !info.vencido) {
    const inicio = placa ? `Veículo com a placa ${placa}: o` : 'O'
    return `✅ Lembrete importante!
${inicio} certificado do Tacógrafo vence em ${fmtDia(info.venc)}.
Agende com antecedência e evite a correria de última hora e o risco de multa.
${marca} — Ensaio Inmetro
End: ${endereco}
Temos condições especiais para você.`
  }

  // Sem data de aferição registrada — não sabemos o vencimento
  const inicio = placa ? `Para o veículo de placa ${placa}: v` : 'V'
  return `Olá! Aqui é da ${marca} (Ensaio Inmetro).
${inicio}ocê sabe a data da última aferição do tacógrafo? O certificado vale 2 anos, e circular vencido gera multa.
Se quiser, a gente confere e já agenda pra você. Temos condições especiais.
End: ${endereco}`
}

export default function LeadDetail() {
  const { id } = useParams<{ id: string }>()
  const { membro } = useAuth()
  const [lead, setLead] = useState<Caminhoneiro | null>(null)
  const [ligacoes, setLigacoes] = useState<Ligacao[]>([])
  const [agendamentos, setAgendamentos] = useState<Agendamento[]>([])
  const [loading, setLoading] = useState(true)
  const [showAgendar, setShowAgendar] = useState(false)
  const [showAferido, setShowAferido] = useState(false)

  // edição inline
  const [editTelefone, setEditTelefone] = useState(false)
  const [telefoneVal, setTelefoneVal] = useState('')
  const [editAfericao, setEditAfericao] = useState(false)
  const [afericaoVal, setAfericaoVal] = useState('')

  // WhatsApp
  const [showWhats, setShowWhats] = useState(false)
  const [whatsMsg, setWhatsMsg] = useState('')
  const [alerta, setAlerta] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    if (!id) return
    setLoading(true)
    const [leadRes, ligacoesRes, agendamentosRes] = await Promise.all([
      supabase.from('caminhoneiros').select('*').eq('id', id).single(),
      supabase
        .from('ligacoes')
        .select('*')
        .eq('caminhoneiro_id', id)
        .order('created_at', { ascending: false }),
      supabase
        .from('agendamentos')
        .select('*')
        .eq('caminhoneiro_id', id)
        .order('data_hora', { ascending: false }),
    ])
    setLead((leadRes.data as Caminhoneiro) ?? null)
    setLigacoes((ligacoesRes.data as Ligacao[]) ?? [])
    setAgendamentos((agendamentosRes.data as Agendamento[]) ?? [])
    setLoading(false)
  }, [id])

  useEffect(() => {
    carregar()
  }, [carregar])

  async function salvarTelefone() {
    if (!lead) return
    const novo = telefoneVal.trim()
    if (!novo) return
    await supabase.from('caminhoneiros').update({ telefone: novo }).eq('id', lead.id)
    setLead((prev) => (prev ? { ...prev, telefone: novo } : prev))
    setEditTelefone(false)
  }

  async function salvarAfericao() {
    if (!lead) return
    const novo = afericaoVal ? afericaoVal.slice(0, 10) : null
    await supabase.from('caminhoneiros').update({ data_ultima_afericao: novo }).eq('id', lead.id)
    setLead((prev) => (prev ? { ...prev, data_ultima_afericao: novo } : prev))
    setEditAfericao(false)
  }

  // Abre o preview do WhatsApp. A mensagem é escolhida conforme a situação do lead.
  function abrirWhatsapp() {
    if (!lead) return
    setAlerta(null)
    if (lead.tem_tacografo === false) {
      setAlerta(
        'Este veículo é do tipo sem tacógrafo ("NENHUM RESULTADO") — está fora do público-alvo e não deve receber contato de aferição.'
      )
      return
    }
    if (lead.whatsapp_invalido) {
      setAlerta('Este número está marcado como SEM WhatsApp. Se foi engano, clique em "É WhatsApp" para desmarcar.')
      return
    }
    if (!numeroWhatsapp(lead.telefone)) {
      setAlerta('Este lead não tem um número de celular válido para envio de WhatsApp.')
      return
    }
    setWhatsMsg(montarMensagem(lead, vencimentoLead(lead.data_ultima_afericao)))
    setShowWhats(true)
  }

  // Abre o WhatsApp Web com a mensagem e registra o envio.
  async function enviarWhatsapp() {
    if (!lead) return
    const num = numeroWhatsapp(lead.telefone)
    if (!num) return
    // window.open síncrono ao clique (evita bloqueio de popup)
    window.open(`https://wa.me/${num}?text=${encodeURIComponent(whatsMsg)}`, '_blank')

    const agora = new Date().toISOString()
    await supabase.from('ligacoes').insert({
      caminhoneiro_id: lead.id,
      operador_id: membro?.user_id ?? null,
      resultado: 'whatsapp_enviado',
      canal: 'whatsapp',
      notas: whatsMsg,
    })
    const novoStatus =
      lead.status === 'novo' || lead.status === 'sem_resposta' ? 'mensagem_enviada' : lead.status
    await supabase
      .from('caminhoneiros')
      .update({ data_ultimo_whatsapp: agora, status: novoStatus })
      .eq('id', lead.id)

    setShowWhats(false)
    carregar()
  }

  // Recalcula o selo "WhatsApp enviado em" a partir dos envios restantes.
  async function recomputarUltimoWhatsapp(leadId: string) {
    const { data } = await supabase
      .from('ligacoes')
      .select('created_at')
      .eq('caminhoneiro_id', leadId)
      .eq('canal', 'whatsapp')
      .order('created_at', { ascending: false })
      .limit(1)
    const novo = data && data.length ? (data[0] as { created_at: string }).created_at : null
    await supabase.from('caminhoneiros').update({ data_ultimo_whatsapp: novo }).eq('id', leadId)
  }

  // "Não é WhatsApp": marca o número, desfaz o último envio (falso) e destrava o status.
  async function marcarSemWhatsapp() {
    if (!lead) return
    const ultimoWa = ligacoes.find((l) => l.canal === 'whatsapp')
    if (ultimoWa) await supabase.from('ligacoes').delete().eq('id', ultimoWa.id)
    await recomputarUltimoWhatsapp(lead.id)
    const novoStatus = lead.status === 'mensagem_enviada' ? 'novo' : lead.status
    await supabase
      .from('caminhoneiros')
      .update({ whatsapp_invalido: true, status: novoStatus })
      .eq('id', lead.id)
    setAlerta(null)
    carregar()
  }

  async function desmarcarSemWhatsapp() {
    if (!lead) return
    await supabase.from('caminhoneiros').update({ whatsapp_invalido: false }).eq('id', lead.id)
    carregar()
  }

  async function deletarContato(l: Ligacao) {
    if (!lead) return
    if (!window.confirm('Excluir este registro de contato?')) return
    await supabase.from('ligacoes').delete().eq('id', l.id)
    if (l.canal === 'whatsapp') await recomputarUltimoWhatsapp(lead.id)
    carregar()
  }

  if (loading) return <p className="text-sm text-ink-4">Carregando…</p>
  if (!lead) return <p className="text-sm text-ink-4">Lead não encontrado.</p>

  const info = vencimentoLead(lead.data_ultima_afericao)
  const vencido = !!info?.vencido

  return (
    <div>
      <Link to="/leads" className="inline-flex items-center gap-1.5 text-sm text-ink-6 hover:text-ink mb-4">
        <ArrowLeft size={15} /> Voltar para leads
      </Link>

      {alerta && (
        <div className="mb-4 flex items-start gap-2 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-300">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span className="flex-1">{alerta}</span>
          <button onClick={() => setAlerta(null)} className="text-amber-400 hover:text-amber-200">
            <X size={16} />
          </button>
        </div>
      )}

      {lead.tem_tacografo === false && (
        <div className="mb-4 flex items-start gap-2 rounded-xl border border-slate-500/30 bg-slate-500/10 px-4 py-3 text-sm text-slate-300">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" />
          <span>
            Veículo <b>sem tacógrafo</b> (tipo "NENHUM RESULTADO"). Fora do público-alvo — não enviar
            cobrança de aferição.
          </span>
        </div>
      )}

      <div className="card p-6 mb-6">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div className="min-w-0">
            <h1 className="text-xl font-extrabold text-ink mb-1">{lead.nome}</h1>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-ink-6">
              <span className="flex items-center gap-1.5">
                <Phone size={14} />
                {editTelefone ? (
                  <span className="flex items-center gap-1">
                    <input
                      autoFocus
                      value={telefoneVal}
                      onChange={(e) => setTelefoneVal(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') salvarTelefone()
                        if (e.key === 'Escape') setEditTelefone(false)
                      }}
                      className="px-2 py-0.5 border border-line rounded-lg text-sm w-40 focus-ring outline-none"
                    />
                    <button onClick={salvarTelefone} className="text-lucro hover:opacity-70" title="Salvar">
                      <Check size={15} />
                    </button>
                    <button onClick={() => setEditTelefone(false)} className="text-ink-4 hover:text-ink" title="Cancelar">
                      <X size={15} />
                    </button>
                  </span>
                ) : (
                  <span className="flex items-center gap-1">
                    {lead.telefone}
                    <button
                      onClick={() => {
                        setTelefoneVal(lead.telefone)
                        setEditTelefone(true)
                      }}
                      className="text-ink-4 hover:text-brand"
                      title="Editar telefone"
                    >
                      <Pencil size={13} />
                    </button>
                  </span>
                )}
              </span>

              {lead.cidade && (
                <span className="flex items-center gap-1.5">
                  <MapPin size={14} /> {lead.cidade}
                  {lead.uf ? `/${lead.uf}` : ''}
                </span>
              )}
              {lead.placa_veiculo && (
                <span className="flex items-center gap-1.5">
                  <Truck size={14} /> {lead.placa_veiculo}
                </span>
              )}
            </div>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-ink-6 mt-1">
              {lead.rntrc && (
                <span className="flex items-center gap-1.5">
                  <FileText size={14} /> RNTRC: {lead.rntrc}
                </span>
              )}
              {lead.renavam && (
                <span className="flex items-center gap-1.5">
                  <FileText size={14} /> Renavam: {lead.renavam}
                </span>
              )}
              <span className="flex items-center gap-1.5">
                <History size={14} /> Última Aferição:{' '}
                {editAfericao ? (
                  <span className="flex items-center gap-1">
                    <input
                      autoFocus
                      type="date"
                      value={afericaoVal}
                      onChange={(e) => setAfericaoVal(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') salvarAfericao()
                        if (e.key === 'Escape') setEditAfericao(false)
                      }}
                      className="px-2 py-0.5 border border-line rounded-lg text-sm focus-ring outline-none"
                    />
                    <button onClick={salvarAfericao} className="text-lucro hover:opacity-70" title="Salvar">
                      <Check size={15} />
                    </button>
                    <button onClick={() => setEditAfericao(false)} className="text-ink-4 hover:text-ink" title="Cancelar">
                      <X size={15} />
                    </button>
                  </span>
                ) : (
                  <span className="flex items-center gap-1">
                    {formatDateBR(lead.data_ultima_afericao)}
                    {info && (
                      <span
                        className={`ml-1 rounded-full px-2 py-0.5 text-[11px] font-bold ${
                          vencido ? 'bg-rose-500/15 text-rose-300' : 'bg-emerald-500/15 text-emerald-300'
                        }`}
                      >
                        {vencido ? `Vencido em ${fmtDia(info.venc)}` : `Vence em ${fmtDia(info.venc)}`}
                      </span>
                    )}
                    <button
                      onClick={() => {
                        setAfericaoVal(lead.data_ultima_afericao ? lead.data_ultima_afericao.slice(0, 10) : '')
                        setEditAfericao(true)
                      }}
                      className="text-ink-4 hover:text-brand"
                      title="Editar última aferição"
                    >
                      <Pencil size={13} />
                    </button>
                  </span>
                )}
              </span>
            </div>

            {lead.data_ultimo_whatsapp && (
              <div className="mt-2 inline-flex items-center gap-1.5 text-xs font-semibold text-emerald-400">
                <MessageCircle size={14} /> WhatsApp enviado em{' '}
                {new Date(lead.data_ultimo_whatsapp).toLocaleDateString('pt-BR')}
              </div>
            )}
          </div>

          <div className="flex flex-col items-end gap-2">
            <div className="flex items-center gap-2 flex-wrap justify-end">
              <Badge className={STATUS_LEAD_CLASSES[lead.status]}>{STATUS_LEAD_LABEL[lead.status]}</Badge>
              <button
                onClick={abrirWhatsapp}
                className={`flex items-center gap-1.5 text-sm font-bold px-3.5 py-2 rounded-xl transition-colors ${
                  lead.tem_tacografo === false || lead.whatsapp_invalido
                    ? 'border border-line bg-card text-ink-4 hover:bg-white/5'
                    : 'bg-lucro text-white hover:opacity-90'
                }`}
                title={
                  lead.tem_tacografo === false
                    ? 'Veículo sem tacógrafo — fora do público-alvo'
                    : lead.whatsapp_invalido
                      ? 'Número marcado como sem WhatsApp'
                      : 'Enviar WhatsApp (mensagem conforme a situação do lead)'
                }
              >
                <MessageCircle size={16} /> Enviar WhatsApp
              </button>
              {lead.whatsapp_invalido ? (
                <button
                  onClick={desmarcarSemWhatsapp}
                  className="flex items-center gap-1.5 border border-amber-500/30 bg-amber-500/10 text-amber-300 text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-amber-500/20 transition-colors"
                  title="Número marcado como sem WhatsApp. Clique para desmarcar (foi engano)."
                >
                  <Ban size={16} /> Sem WhatsApp
                </button>
              ) : (
                <button
                  onClick={marcarSemWhatsapp}
                  className="flex items-center gap-1.5 border border-line bg-card text-ink-6 text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-white/5 transition-colors"
                  title="Marcar que este número não tem WhatsApp (desfaz o último envio registrado)"
                >
                  <Ban size={16} /> Não é WhatsApp
                </button>
              )}
              <button
                onClick={() => setShowAgendar(true)}
                className="flex items-center gap-1.5 border border-line bg-card text-ink-6 text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-white/5 transition-colors"
              >
                <CalendarPlus size={16} /> Agendar aferição
              </button>
              {/* Fecha o ciclo: grava a data do serviço em `data_ultima_afericao`,
                  o lead sai da fila e volta sozinho daqui a 2 anos. */}
              <button
                onClick={() => setShowAferido(true)}
                className="flex items-center gap-1.5 border border-lucro/40 bg-lucro/10 text-lucro text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-lucro/20 transition-colors"
                title="Registrar que a aferição foi feita"
              >
                <CheckCircle2 size={16} /> Aferido
              </button>
            </div>
          </div>
        </div>
        {lead.observacoes && <p className="text-sm text-ink-6 mt-3 border-t border-line pt-3">{lead.observacoes}</p>}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <div className="card p-5">
            <h2 className="text-sm font-extrabold text-ink mb-3">Registrar contato</h2>
            <RegistrarLigacaoForm
              caminhoneiroId={lead.id}
              operadorId={membro?.user_id}
              onSaved={(novoStatus) => {
                setLead((prev) => (prev ? { ...prev, status: novoStatus } : prev))
                carregar()
              }}
            />
          </div>
        </div>

        <div className="lg:col-span-3 space-y-6">
          <div className="card p-5">
            <h2 className="text-sm font-extrabold text-ink mb-3">Histórico de contatos</h2>
            {ligacoes.length === 0 ? (
              <p className="text-sm text-ink-4">Nenhum contato registrado ainda.</p>
            ) : (
              <ul className="space-y-3">
                {ligacoes.map((l) => (
                  <li key={l.id} className="border-b border-line last:border-0 pb-3 last:pb-0">
                    <div className="flex items-center justify-between mb-1">
                      <span className="flex items-center gap-2">
                        <span className="text-sm font-bold text-ink">{CANAL_CONTATO_LABEL[l.canal]}</span>
                        {l.resultado !== 'whatsapp_enviado' && (
                          <span className="text-xs text-ink-6">· {RESULTADO_LIGACAO_LABEL[l.resultado]}</span>
                        )}
                      </span>
                      <span className="flex items-center gap-2 shrink-0">
                        <span className="text-xs text-ink-4">
                          {new Date(l.created_at).toLocaleString('pt-BR', {
                            dateStyle: 'short',
                            timeStyle: 'short',
                          })}
                        </span>
                        <button
                          onClick={() => deletarContato(l)}
                          className="text-ink-4 hover:text-rose-400"
                          title="Excluir este registro de contato"
                        >
                          <Trash2 size={14} />
                        </button>
                      </span>
                    </div>
                    {l.notas && <p className="text-sm text-ink-6 whitespace-pre-line">{l.notas}</p>}
                  </li>
                ))}
              </ul>
            )}
          </div>

          {agendamentos.length > 0 && (
            <div className="card p-5">
              <h2 className="text-sm font-extrabold text-ink mb-3">Agendamentos</h2>
              <ul className="space-y-2">
                {agendamentos.map((a) => (
                  <li key={a.id} className="flex items-center justify-between text-sm">
                    <div>
                      <div className="font-semibold text-ink">
                        {new Date(a.data_hora).toLocaleString('pt-BR', {
                          dateStyle: 'short',
                          timeStyle: 'short',
                        })}
                      </div>
                      {a.local && <div className="text-ink-4 text-xs">{a.local}</div>}
                    </div>
                    <Badge className={STATUS_AGENDAMENTO_CLASSES[a.status]}>
                      {STATUS_AGENDAMENTO_LABEL[a.status]}
                    </Badge>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </div>

      {showWhats && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
          <div className="card w-full max-w-lg p-6">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
                <MessageCircle size={18} className="text-lucro" /> Enviar WhatsApp
              </h2>
              <button onClick={() => setShowWhats(false)} className="text-ink-4 hover:text-ink">
                <X size={18} />
              </button>
            </div>
            <p className="text-xs text-ink-4 mb-2">
              Confira/edite a mensagem. Ao enviar, o WhatsApp Web abre já com o texto — é só apertar
              enviar lá. O envio fica registrado aqui automaticamente.
            </p>
            <textarea
              value={whatsMsg}
              onChange={(e) => setWhatsMsg(e.target.value)}
              rows={9}
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none resize-none"
            />
            <div className="flex justify-end gap-2 mt-4">
              <button
                onClick={() => setShowWhats(false)}
                className="px-4 py-2 rounded-xl border border-line text-sm font-bold text-ink-6 hover:bg-white/5"
              >
                Cancelar
              </button>
              <button
                onClick={enviarWhatsapp}
                className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-lucro text-white text-sm font-bold hover:opacity-90"
              >
                <MessageCircle size={16} /> Abrir no WhatsApp
              </button>
            </div>
          </div>
        </div>
      )}

      {showAgendar && (
        <AgendarAfericaoModal
          caminhoneiroId={lead.id}
          operadorId={membro?.user_id}
          onClose={() => setShowAgendar(false)}
          onCreated={() => {
            setShowAgendar(false)
            carregar()
          }}
        />
      )}

      {showAferido && (
        <RegistrarAfericaoModal
          caminhoneiroId={lead.id}
          unidadeId={lead.unidade_id}
          operadorId={membro?.user_id}
          onClose={() => setShowAferido(false)}
          onSaved={() => {
            setShowAferido(false)
            carregar()
          }}
        />
      )}
    </div>
  )
}
