import { useEffect, useState, useCallback } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import {
  ArrowLeft, Phone, MapPin, Truck, CalendarPlus, FileText, History, Pencil, Check, X,
  MessageCircle, AlertTriangle, Ban, Trash2, CheckCircle2, Building2, Undo2,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useConfigMensagem } from '../lib/AuthContext'
import type {
  Agendamento, ConfigMensagem, Ligacao, LeadComEmpresa, VeiculoDaFrota,
} from '../lib/database.types'
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
import ConfirmarModal from '../components/ConfirmarModal'

const VALIDADE_ANOS = 2

// Marca, endereço e os textos variáveis da mensagem vêm do cadastro da unidade
// (aba Unidade → Mensagens; 0085). `useConfigMensagem()` aplica os padrões.

// Cliente da casa = a última aferição foi num posto do grupo (`nosso`, calculado
// no banco por posto_do_grupo). Para ele a mensagem é lembrete de fornecedor. Para quem aferiu em concorrente é
// abordagem fria — e foi ela que restringiu o número da Tacorrei em 28/08.
//
// Numa FROTA a conta é outra: basta UM caminhão ter aferido conosco. Quem atende
// o telefone é a mesma pessoa para os sete caminhões — ela esteve na oficina,
// deu o número, sabe quem somos. O opt-in é da pessoa, não da placa. Falar do
// segundo caminhão dela não é abordagem fria, é crescer uma conta que já é nossa.
function ehClienteDaCasa(lead: LeadComEmpresa): boolean {
  if (lead.empresa) return lead.empresa.ja_e_cliente
  return lead.nosso ?? false
}

// Quem pode receber mensagem: cliente da casa, ou quem autorizou na ligação.
function podeReceberMensagem(lead: LeadComEmpresa): boolean {
  return ehClienteDaCasa(lead) || lead.autorizou_whatsapp
}

// O telefone do lead vem do RNTRC, e lá está o número de QUEM DIRIGE aquele
// caminhão — que muda a cada viagem. Numa frota, quem decide mandar o caminhão
// para a aferição é o contato da empresa. Medi na base: as frotas têm telefone
// diferente em cada veículo, então usar o do lead seria falar com o motorista
// da vez em vez de com quem resolve.
function telefoneDestino(lead: LeadComEmpresa): string {
  const daEmpresa = lead.empresa?.telefone?.trim()
  return daEmpresa ? daEmpresa : lead.telefone
}

// A quem a saudação se dirige: o contato da frota, ou o próprio dono.
function nomeDestino(lead: LeadComEmpresa): string | null {
  return lead.empresa?.contato?.trim() || lead.nome
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

// ── Mensagem de WhatsApp ─────────────────────────────────────────────────────
// Texto aprovado pelo Raphael em 24/08, depois de várias rodadas. A versão anterior
// abria com ⚠️⚠️⚠️, ameaçava multa antes de dizer quem estava falando e não deixava
// saída para quem não é mais dono do veículo — o desenho exato de uma mensagem que a
// pessoa denuncia. E denúncia, não volume, é o que derruba um número de WhatsApp.
//
// A estrutura tem quatro blocos, nesta ordem, e cada um faz um trabalho:
//   1. Quem está falando  → desarma o "que número é esse?"
//   2. O fato, sem drama  → informa, não ameaça
//   3. O convite          → curto, sem promessa de horário
//   4. A porta de saída   → quem não é mais dono responde em vez de denunciar
//      (é a linha mais barata do texto e a que mais protege o número)
//
// A oficina NÃO trabalha com hora marcada. Nenhum texto promete horário.

// "JOSE TADEU DIAS" → "José"... na medida do possível. Cadastro de empresa não tem
// primeiro nome: nesses casos a saudação sai sem nome, que é melhor que "Olá, Grupo".
const MARCAS_DE_EMPRESA = /\b(LTDA|ME|EPP|EIRELI|MEI|S\/A|SA|TRANSPORTES?|TRANSP|COMERCIO|COM|IND|INDUSTRIA|SERVICOS?|LOGISTICA|GRUPO|CIA)\b/i

function primeiroNome(nome: string | null): string | null {
  if (!nome) return null
  if (MARCAS_DE_EMPRESA.test(nome)) return null
  const bruto = nome.trim().split(/\s+/)[0]
  if (!bruto || bruto.length < 3) return null
  return bruto.charAt(0).toUpperCase() + bruto.slice(1).toLowerCase()
}

// "Aqui é a Ivanessa" / "Aqui é o Cicero". O artigo vem do nome: em português,
// nome terminado em 'a' é quase sempre feminino. Acerta as sete pessoas da equipe
// hoje; se um dia entrar um "Nicola" ou uma "Isabel", vira campo no cadastro.
function assinatura(atendente: string | null | undefined, marca: string): string {
  const quem = primeiroNome(atendente ?? null)
  if (!quem) return `Aqui é da ${marca}`
  const artigo = quem.slice(-1).toLowerCase() === 'a' ? 'a' : 'o'
  return `Aqui é ${artigo} ${quem}, da ${marca}`
}

// "Bom dia" fixo às 15h entrega o robô.
function saudacao(): string {
  const h = new Date().getHours()
  if (h < 12) return 'Bom dia'
  if (h < 18) return 'Boa tarde'
  return 'Boa noite'
}

// Os caminhões que entram na mesma conversa, escritos como lista. Só aparece
// quando ela marcou algum irmão — frota de um caminhão só não ganha bloco extra.
function blocoDaFrota(irmaos: VeiculoDaFrota[]): string {
  if (irmaos.length === 0) return ''
  const linhas = irmaos
    .map((v) => `• ${v.placa ?? 'sem placa'} — ${(v.dias ?? 0) < 0 ? 'vencido desde' : 'vence em'} ${formatDateBR(v.venc)}`)
    .join('\n')
  const plural = irmaos.length > 1
  return `

E já aproveitando, ${plural ? 'estes também estão para vencer' : 'este também está para vencer'}:
${linhas}

Se preferir, dá para trazer ${plural ? 'todos de uma vez' : 'os dois juntos'} — eu deixo as guias prontas e vocês resolvem numa viagem só.`
}

function montarMensagem(
  lead: LeadComEmpresa,
  info: { venc: Date; vencido: boolean } | null,
  cfg: ConfigMensagem,
  atendente?: string | null,
  irmaos: VeiculoDaFrota[] = []
): string {
  const { marca, endereco } = cfg
  const frota = lead.empresa
  const nome = primeiroNome(nomeDestino(lead))
  const abre = nome ? `${saudacao()}, ${nome}!` : `${saudacao()}!`

  // Cabeçalho: saudação, quem assina e o credenciamento — nesta ordem, sempre.
  const cabecalho = `${abre}
${assinatura(atendente, marca)}
${cfg.credencial}`

  // "da placa ABC1D23" ou "do seu veículo" — evita concordância remendada no texto.
  const doVeiculo = lead.placa_veiculo ? `da placa ${lead.placa_veiculo}` : 'do seu veículo'
  const oVeiculo = lead.placa_veiculo ? `a placa ${lead.placa_veiculo}` : 'o seu veículo'

  const extras = blocoDaFrota(irmaos)

  // A porta de saída muda de número quando a conversa cobre vários caminhões.
  const saida = frota
    ? `Se algum desses veículos não for mais de vocês, me avisa que eu retiro do cadastro.`
    : `Se esse veículo não for mais seu, me avisa que eu retiro do cadastro.`

  // Unidade sem endereço cadastrado: a mensagem sai sem a última linha.
  const onde = endereco ? `\n\nEstamos na ${endereco}` : ''
  const rodape = `${saida}
Estou à sua disposição para qualquer dúvida.${onde}`

  // Para quem já aferiu conosco, dizer isso muda a natureza da mensagem: deixa de
  // ser alguém desconhecido que sabe a placa dele e passa a ser o fornecedor dele.
  const daCasa = ehClienteDaCasa(lead)
  const relacao = daCasa
    ? frota
      ? ` Vocês já aferem com a gente aqui na ${marca}.`
      : ` Sua última aferição foi conosco, aqui na ${marca}.`
    : ''
  // Depois da ligação em que ele autorizou, a mensagem tem de lembrar a conversa —
  // senão chega como se fosse o primeiro contato.
  const posLigacao = !daCasa && lead.autorizou_whatsapp
    ? ' Conforme conversamos agora há pouco por telefone, segue por escrito.'
    : ''

  if (info && info.vencido) {
    const meses = Math.floor((Date.now() - info.venc.getTime()) / (30 * 86400000))

    // Vencido há muito tempo: quase sempre caminhão vendido ou sem tacógrafo.
    // Aqui não se AFIRMA nada — pergunta-se. Afirmar para quem não tem mais o
    // veículo é o caminho mais curto para a denúncia. Com o piso de 12 meses este
    // caso não chega à operadora; fica valendo para o admin e caso o piso mude.
    if (meses > 36) {
      return `${cabecalho}

Verificamos aqui que ${oVeiculo} aparece sem aferição de tacógrafo há bastante tempo. Esse veículo ainda é seu e ainda usa tacógrafo?

Se ainda usa, eu te explico como funciona.

${rodape}`
    }

    // Com o bloco da frota o convite já vem lá dentro ("trazer todos de uma
    // vez"); repetir "venha aferir" aqui soaria insistente.
    const convite = extras ? '' : `${cfg.conviteVencido}\n\n`
    return `${cabecalho}

Verificamos aqui que o certificado do tacógrafo ${doVeiculo} consta vencido desde ${fmtDia(info.venc)}.${relacao}${posLigacao}${extras}

${convite}${rodape}`
  }

  if (info && !info.vencido) {
    const convite = extras ? '' : `${cfg.conviteAVencer}\n\n`
    return `${cabecalho}

Verificamos aqui que o certificado do tacógrafo ${doVeiculo} vence em ${fmtDia(info.venc)}.${relacao}${posLigacao}${extras}

${convite}${rodape}`
  }

  // Sem data de aferição = sem tacógrafo. Esses leads não aparecem para a operadora;
  // este texto só existe para o caso raro de um cadastro criado à mão.
  return `${cabecalho}

Você sabe a data da última aferição do tacógrafo ${doVeiculo}? O certificado vale 2 anos.

Se quiser, eu confiro para você e a gente já deixa tudo em dia.

${rodape}`
}

export default function LeadDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { membro } = useAuth()
  const configMensagem = useConfigMensagem()
  const [lead, setLead] = useState<LeadComEmpresa | null>(null)
  const [ligacoes, setLigacoes] = useState<Ligacao[]>([])
  const [agendamentos, setAgendamentos] = useState<Agendamento[]>([])
  const [loading, setLoading] = useState(true)
  const [showAgendar, setShowAgendar] = useState(false)
  const [showAferido, setShowAferido] = useState(false)

  // edição inline
  const [editTelefone, setEditTelefone] = useState(false)
  const [telefoneVal, setTelefoneVal] = useState('')
  const [editAfericao, setEditAfericao] = useState(false)
  // O veículo é o que persiste; o dono muda. Quando o cara responde "não é mais
  // meu", a operadora corrige aqui mesmo — e a troca vai para o histórico.
  const [editDono, setEditDono] = useState(false)
  const [donoVal, setDonoVal] = useState('')
  const [afericaoVal, setAfericaoVal] = useState('')

  // WhatsApp
  const [showWhats, setShowWhats] = useState(false)
  const [whatsMsg, setWhatsMsg] = useState('')
  const [alerta, setAlerta] = useState<string | null>(null)
  // Numa frota, a conversa é uma só e cobre vários caminhões. Aqui ficam os
  // irmãos que ela marcou — eles entram no texto e são registrados junto, para
  // não voltarem à fila e gerarem uma segunda mensagem para a mesma pessoa.
  const [incluidos, setIncluidos] = useState<string[]>([])
  // Se ela mexeu no texto, o app para de reescrever por cima.
  const [msgEditada, setMsgEditada] = useState(false)

  const carregar = useCallback(async () => {
    if (!id) return
    setLoading(true)
    const [leadRes, ligacoesRes, agendamentosRes] = await Promise.all([
      // Pela RPC, para registrar quem abriu qual ficha (a RLS continua valendo).
      supabase.rpc('obter_lead', { p_id: id }),
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
    const leadCarregado = (leadRes.data as LeadComEmpresa | null) ?? null
    setLead(leadCarregado)
    setAgendamentos((agendamentosRes.data as Agendamento[]) ?? [])

    // Numa frota, a conversa que conta pode ter sido com o gestor, registrada na
    // empresa e não nesta placa. Sem trazê-la para cá, a operadora abre a ficha,
    // não vê nada e liga de novo para quem a colega falou ontem.
    const doCaminhao = (ligacoesRes.data as Ligacao[]) ?? []
    const empresaId = leadCarregado?.empresa?.id
    if (empresaId) {
      const { data: daEmpresa } = await supabase
        .from('ligacoes')
        .select('*')
        .eq('empresa_id', empresaId)
        .order('created_at', { ascending: false })
      const todas = [...doCaminhao, ...((daEmpresa as Ligacao[]) ?? [])]
      todas.sort((a, b) => b.created_at.localeCompare(a.created_at))
      setLigacoes(todas)
    } else {
      setLigacoes(doCaminhao)
    }
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

  async function salvarProprietario() {
    if (!lead) return
    const novo = donoVal.trim()
    if (!novo || novo === lead.nome) {
      setEditDono(false)
      return
    }
    const { error } = await supabase.rpc('atualizar_proprietario', {
      p_lead: lead.id,
      p_nome: novo,
      p_telefone: null,
    })
    if (error) {
      setAlerta(error.message)
      return
    }
    setEditDono(false)
    carregar()
  }

  // "Pode me mandar no WhatsApp?" — dito na ligação. É o que libera a mensagem
  // para quem é cliente de concorrente. Ligação atendida não basta; a permissão
  // precisa ser explícita, e fica gravada com data e autor.
  async function marcarAutorizacao(autorizou: boolean) {
    if (!lead) return
    const { error } = await supabase.rpc('registrar_autorizacao', {
      p_lead: lead.id,
      p_autorizou: autorizou,
      p_notas: null,
    })
    if (error) {
      setAlerta(error.message)
      return
    }
    carregar()
  }

  async function salvarAfericao() {
    if (!lead) return
    const novo = afericaoVal ? afericaoVal.slice(0, 10) : null
    // Mesma armadilha do botão Aferido: uma data recente tira o lead da janela e o
    // update direto seria recusado. `p_marcar_aferido: false` só corrige a data.
    await supabase.rpc('registrar_afericao', {
      p_lead: lead.id,
      p_data: novo,
      p_notas: null,
      p_marcar_aferido: false,
    })
    setLead((prev) => (prev ? { ...prev, data_ultima_afericao: novo } : prev))
    setEditAfericao(false)
  }

  // Os outros caminhões da frota (o atual fica de fora — ele é o assunto).
  const irmaosDaFrota = useCallback(
    (l: LeadComEmpresa): VeiculoDaFrota[] => (l.empresa?.veiculos ?? []).filter((v) => !v.este),
    []
  )

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
    // Empresa com contrato não recebe mensagem avulsa: ela já é nossa, e o
    // combinado é a relação mensal com todos os vencimentos de uma vez.
    if (lead.empresa?.situacao === 'contrato') {
      setAlerta(
        `Este caminhão é da ${lead.empresa.nome}, que tem contrato. O caminho é a relação mensal na aba Empresas, não mensagem avulsa.`
      )
      return
    }
    if (!numeroWhatsapp(telefoneDestino(lead))) {
      setAlerta(
        lead.empresa
          ? `A ${lead.empresa.nome} está sem telefone de contato no cadastro, e o número do caminhão também não serve. Preencha o contato da empresa na aba Empresas.`
          : 'Este lead não tem um número de celular válido para envio de WhatsApp.'
      )
      return
    }
    if (!podeReceberMensagem(lead)) {
      setAlerta(
        lead.empresa
          ? `Nenhum caminhão da ${lead.empresa.nome} aferiu conosco ainda — é frota do concorrente. Ligue para o contato e, se ele autorizar, marque "Autorizou receber mensagem".`
          : 'Este caminhão fez a última aferição em outro posto — não temos relação com ele. Ligue primeiro e, se ele autorizar, marque "Autorizou receber mensagem" que o WhatsApp libera.'
      )
      return
    }
    if (lead.data_ultimo_whatsapp) {
      setAlerta('Este lead já recebeu uma mensagem. A regra é uma por cliente — insistir é o que mais gera bloqueio. Ele volta a ser abordável depois da próxima aferição.')
      return
    }

    // Pré-marca os irmãos que vencem dentro da janela de agrupamento. Os que
    // vencem depois ficam desmarcados: citar caminhão que só vence daqui a oito
    // meses transforma um lembrete útil em mala direta.
    const irmaos = irmaosDaFrota(lead)
    const janela = lead.empresa?.agrupamento_dias ?? 60
    const pre = irmaos.filter((v) => v.dias !== null && v.dias <= janela).map((v) => v.id)
    setIncluidos(pre)
    setMsgEditada(false)
    setWhatsMsg(
      montarMensagem(
        lead,
        vencimentoLead(lead.data_ultima_afericao),
        configMensagem(lead.unidade_id),
        membro?.nome,
        irmaos.filter((v) => pre.includes(v.id))
      )
    )
    setShowWhats(true)
  }

  // Marcar ou desmarcar um caminhão reescreve o texto — a não ser que ela já
  // tenha editado à mão, caso em que sobrescrever seria apagar o trabalho dela.
  useEffect(() => {
    if (!showWhats || !lead || msgEditada) return
    const irmaos = irmaosDaFrota(lead).filter((v) => incluidos.includes(v.id))
    setWhatsMsg(montarMensagem(lead, vencimentoLead(lead.data_ultima_afericao), configMensagem(lead.unidade_id), membro?.nome, irmaos))
  }, [incluidos, showWhats, lead, msgEditada, membro?.nome, irmaosDaFrota, configMensagem])

  // Abre o WhatsApp Web com a mensagem e registra o envio.
  //
  // O registro vem PRIMEIRO e vai por RPC, não por INSERT direto. É lá que moram as
  // três travas — uma mensagem por lead, cota diária da unidade e faixa de vencimento.
  // Se a RPC recusar, o WhatsApp nem abre: adiantaria pouco impedir o registro depois
  // que a mensagem já saiu. Custo: o `window.open` deixa de ser síncrono ao clique e
  // alguns navegadores bloqueiam o popup — por isso, se ele não abrir, mostramos o
  // link para a operadora clicar.
  async function enviarWhatsapp() {
    if (!lead) return
    const num = numeroWhatsapp(telefoneDestino(lead))
    if (!num) return

    const { data, error } = await supabase.rpc('registrar_envio_whatsapp', {
      p_lead: lead.id,
      p_mensagem: whatsMsg,
      // Os irmãos cobertos por esta conversa. O banco registra cada um e tira
      // todos da fila juntos — senão a mesma pessoa receberia outra mensagem
      // semana que vem, sobre um caminhão que ela já viu neste texto.
      p_leads: incluidos.length > 0 ? incluidos : null,
    })

    if (error) {
      setShowWhats(false)
      setAlerta(error.message)
      return
    }

    const janela = window.open(`https://wa.me/${num}?text=${encodeURIComponent(whatsMsg)}`, '_blank')
    if (!janela) {
      setAlerta('O navegador bloqueou a abertura do WhatsApp. O envio já foi registrado — abra a conversa manualmente.')
    }

    const cota = data as { restantes: number; limite: number; extras: number } | null
    if (cota && cota.extras > 0) {
      setAlerta(
        `Registrado. Além deste, mais ${cota.extras} caminhão(ões) da frota saíram da fila — estão cobertos por esta conversa.`
      )
    } else if (cota && cota.restantes <= 5) {
      setAlerta(
        cota.restantes === 0
          ? `Cota do dia encerrada (${cota.limite} mensagens). Voltam amanhã.`
          : `Atenção: restam ${cota.restantes} mensagens na cota de hoje.`
      )
    }

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

  // ── Correções (com confirmação sempre; com registro quando é do gestor) ────
  // Três ações diferentes no mesmo histórico:
  //   • contato da placa → a operadora apaga o próprio (sem registro);
  //   • contato COM A EMPRESA → só gestor/admin, via apagar_contato_empresa (fica em `correcoes`);
  //   • "Aferido" → só gestor/admin, via desfazer_afericao: volta data, posto e status,
  //     apaga o ponto e a linha do histórico de posto (fica em `correcoes`).
  const podeCorrigir = membro?.papel === 'admin' || membro?.papel === 'admin_unidade'
  const [confirmacao, setConfirmacao] = useState<{ tipo: 'contato' | 'empresa' | 'aferido'; ligacao: Ligacao } | null>(null)

  async function deletarContato(l: Ligacao) {
    if (!lead) return
    const { error } = await supabase.from('ligacoes').delete().eq('id', l.id)
    if (error) throw new Error(error.message)
    if (l.canal === 'whatsapp') await recomputarUltimoWhatsapp(lead.id)
    setConfirmacao(null)
    carregar()
  }

  async function apagarContatoEmpresa(l: Ligacao, motivo: string) {
    const { error } = await supabase.rpc('apagar_contato_empresa', { p_ligacao: l.id, p_motivo: motivo || null })
    if (error) throw new Error(error.message)
    setConfirmacao(null)
    carregar()
  }

  async function desfazerAfericao(motivo: string) {
    if (!lead) return
    const { error } = await supabase.rpc('desfazer_afericao', { p_lead: lead.id, p_motivo: motivo || null })
    if (error) throw new Error(error.message)
    setConfirmacao(null)
    carregar()
  }

  if (loading) return <p className="text-sm text-ink-4">Carregando…</p>
  if (!lead) return <p className="text-sm text-ink-4">Lead não encontrado.</p>

  const info = vencimentoLead(lead.data_ultima_afericao)
  const vencido = !!info?.vencido

  return (
    <div>
      {/* -1 volta para a lista COM os filtros/página que estavam na URL. Se a pessoa
          abriu a ficha direto pelo link (sem passar pela lista), cai em /leads. */}
      <Link
        to="/leads"
        onClick={(e) => {
          if (window.history.length > 1) {
            e.preventDefault()
            navigate(-1)
          }
        }}
        className="inline-flex items-center gap-1.5 text-sm text-ink-6 hover:text-ink mb-4"
      >
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
            {editDono ? (
              <div className="flex items-center gap-1 mb-1">
                <input
                  autoFocus
                  value={donoVal}
                  onChange={(e) => setDonoVal(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') salvarProprietario()
                    if (e.key === 'Escape') setEditDono(false)
                  }}
                  className="px-2 py-1 border border-line rounded-lg text-lg font-bold w-full max-w-md focus-ring outline-none"
                />
                <button onClick={salvarProprietario} className="text-lucro hover:opacity-70" title="Salvar">
                  <Check size={18} />
                </button>
                <button onClick={() => setEditDono(false)} className="text-ink-4 hover:text-ink" title="Cancelar">
                  <X size={18} />
                </button>
              </div>
            ) : (
              <h1 className="text-xl font-extrabold text-ink mb-1 flex items-center gap-2">
                {lead.nome}
                <button
                  onClick={() => {
                    setDonoVal(lead.nome)
                    setEditDono(true)
                  }}
                  className="text-ink-4 hover:text-brand"
                  title="Trocar proprietário (o caminhão foi vendido)"
                >
                  <Pencil size={14} />
                </button>
              </h1>
            )}

            {/* Relação com a casa. É o que decide o canal: cliente recebe mensagem,
                cliente de concorrente se liga primeiro. */}
            <div className="flex flex-wrap items-center gap-2 mb-2">
              {ehClienteDaCasa(lead) ? (
                <span className="badge bg-emerald-500/15 text-emerald-300 border-emerald-500/30">
                  Cliente da casa
                </span>
              ) : lead.autorizou_whatsapp ? (
                /* O "desfazer" fica FORA do selo, como palavra. Dentro dele o × ficava
                   apertado e quebrava linha — e um jeito de voltar precisa ser óbvio:
                   marcar sem querer libera mensagem para quem nunca autorizou, que é
                   exatamente o que derrubou o número em 28/08. */
                <span className="inline-flex items-center gap-2">
                  <span className="badge bg-teal-500/15 text-teal-300 border-teal-500/30">
                    Autorizou receber mensagem
                  </span>
                  <button
                    onClick={() => marcarAutorizacao(false)}
                    className="text-xs font-bold text-ink-4 hover:text-rose-300 underline underline-offset-2"
                    title="Volta a bloquear o envio de mensagem para este lead"
                  >
                    desfazer
                  </button>
                </span>
              ) : lead.posto_afericao ? (
                <span className="badge bg-slate-500/15 text-slate-400 border-slate-500/30">
                  Cliente de concorrente
                </span>
              ) : null}
              {lead.posto_afericao && (
                <span className="text-xs text-ink-4">
                  Última aferição: {lead.posto_afericao}
                </span>
              )}
            </div>

            {/* Frota. Sem isto a operadora não teria como saber que existe irmão
                vencendo, e a trava "uma abordagem por empresa" pareceria capricho
                do sistema em vez de proteção do número. */}
            {lead.empresa && (
              <div
                className={`rounded-xl border p-3 mb-3 ${
                  lead.empresa.situacao === 'contrato'
                    ? 'border-sky-500/30 bg-sky-500/10'
                    : 'border-line bg-white/5'
                }`}
              >
                <p className="text-sm font-bold text-ink flex items-center gap-2">
                  <Building2 size={15} className="text-lucro" />
                  {lead.empresa.nome}
                  <span
                    className={`badge ${
                      lead.empresa.situacao === 'contrato'
                        ? 'bg-sky-500/15 text-sky-300 border-sky-500/30'
                        : 'bg-amber-500/15 text-amber-300 border-amber-500/30'
                    }`}
                  >
                    {lead.empresa.situacao === 'contrato' ? 'Com contrato' : 'A conquistar'}
                  </span>
                </p>
                <p className="text-xs text-ink-4 mt-1">
                  {lead.empresa.veiculos.length} caminhã
                  {lead.empresa.veiculos.length === 1 ? 'o' : 'es'} na frota
                  {lead.empresa.contato && ` · falar com ${lead.empresa.contato}`}
                  {lead.empresa.telefone && ` · ${lead.empresa.telefone}`}
                </p>
                {lead.empresa.situacao === 'contrato' ? (
                  <p className="text-xs text-sky-200/80 mt-1.5">
                    Tem contrato: o caminho é a relação mensal na aba Empresas, não mensagem avulsa.
                  </p>
                ) : (
                  <p className="text-xs text-ink-4 mt-1.5">
                    A mensagem vai para o contato da empresa e cobre os caminhões que vencem junto —
                    uma conversa, não uma por placa.
                  </p>
                )}
              </div>
            )}

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
              {/* Cliente de concorrente que ainda não autorizou: o botão de mensagem
                  sai de cena e entra o de autorização. A operadora liga, e só marca
                  aqui se ele disser que pode mandar. Foi a mensagem sem relação que
                  derrubou o número em 28/08 — 16 das 20 daquele dia. */}
              {!podeReceberMensagem(lead) && (
                <button
                  onClick={() => marcarAutorizacao(true)}
                  className="flex items-center gap-1.5 border border-teal-500/30 bg-teal-500/10 text-teal-300 text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-teal-500/20 transition-colors"
                  title="Marque depois de ligar, se ele disser que pode mandar mensagem"
                >
                  <Phone size={16} /> Liguei — autorizou mensagem
                </button>
              )}
              <button
                onClick={abrirWhatsapp}
                className={`flex items-center gap-1.5 text-sm font-bold px-3.5 py-2 rounded-xl transition-colors ${
                  lead.tem_tacografo === false || lead.whatsapp_invalido || !podeReceberMensagem(lead)
                    ? 'border border-line bg-card text-ink-4 hover:bg-white/5'
                    : 'bg-lucro text-white hover:opacity-90'
                }`}
                title={
                  lead.tem_tacografo === false
                    ? 'Veículo sem tacógrafo — fora do público-alvo'
                    : lead.whatsapp_invalido
                      ? 'Número marcado como sem WhatsApp'
                      : !podeReceberMensagem(lead)
                        ? 'Cliente de concorrente: ligue primeiro e marque a autorização'
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
                        {l.empresa_id && (
                          <span
                            className="badge bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
                            title="Contato com o gestor da frota — vale para todos os caminhões desta empresa"
                          >
                            com a empresa
                          </span>
                        )}
                      </span>
                      <span className="flex items-center gap-2 shrink-0">
                        <span className="text-xs text-ink-4">
                          {new Date(l.created_at).toLocaleString('pt-BR', {
                            dateStyle: 'short',
                            timeStyle: 'short',
                          })}
                        </span>
                        {/* O que cada lixeira faz depende do que é a linha — ver "Correções". */}
                        {l.resultado === 'aferido' ? (
                          podeCorrigir && (
                            <button
                              onClick={() => setConfirmacao({ tipo: 'aferido', ligacao: l })}
                              className="text-ink-4 hover:text-rose-400"
                              title="Desfazer esta aferição (volta data, posto e ponto)"
                            >
                              <Undo2 size={14} />
                            </button>
                          )
                        ) : l.empresa_id ? (
                          podeCorrigir && (
                            <button
                              onClick={() => setConfirmacao({ tipo: 'empresa', ligacao: l })}
                              className="text-ink-4 hover:text-rose-400"
                              title="Apagar este contato com a empresa (fica registrado)"
                            >
                              <Trash2 size={14} />
                            </button>
                          )
                        ) : (
                          <button
                            onClick={() => setConfirmacao({ tipo: 'contato', ligacao: l })}
                            className="text-ink-4 hover:text-rose-400"
                            title="Excluir este registro de contato"
                          >
                            <Trash2 size={14} />
                          </button>
                        )}
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

            {lead.empresa && (
              <p className="text-xs text-ink-6 mb-3 rounded-lg border border-line px-3 py-2">
                Vai para <b className="text-ink">{lead.empresa.contato ?? 'o contato'}</b>
                {lead.empresa.telefone && <> · {lead.empresa.telefone}</>} — contato da{' '}
                {lead.empresa.nome}, não o telefone do caminhão.
              </p>
            )}

            {/* Os caminhões que entram nesta conversa. Marcados = citados no texto
                E registrados como abordados, para não gerarem uma segunda mensagem
                para a mesma pessoa daqui a duas semanas. */}
            {lead.empresa && irmaosDaFrota(lead).length > 0 && (
              <div className="rounded-xl border border-line p-3 mb-3">
                <p className="text-xs font-bold text-ink-6 mb-2">
                  Outros caminhões da {lead.empresa.nome} — marque os que entram nesta conversa
                </p>
                <div className="space-y-1.5 max-h-44 overflow-y-auto">
                  {irmaosDaFrota(lead).map((v) => {
                    const dias = v.dias ?? 0
                    const dentro = dias <= (lead.empresa?.agrupamento_dias ?? 60)
                    return (
                      <label key={v.id} className="flex items-center gap-2 text-xs cursor-pointer">
                        <input
                          type="checkbox"
                          checked={incluidos.includes(v.id)}
                          onChange={(e) => {
                            setMsgEditada(false)
                            setIncluidos((prev) =>
                              e.target.checked ? [...prev, v.id] : prev.filter((x) => x !== v.id)
                            )
                          }}
                          className="accent-lucro"
                        />
                        <span className="font-mono font-bold text-ink">{v.placa ?? 'sem placa'}</span>
                        <span className={dias < 0 ? 'text-rose-300' : dentro ? 'text-ink-6' : 'text-ink-4'}>
                          {dias < 0
                            ? `vencido desde ${formatDateBR(v.venc)}`
                            : `vence em ${formatDateBR(v.venc)}`}
                        </span>
                        {!dentro && <span className="text-ink-4">· ainda longe</span>}
                      </label>
                    )
                  })}
                </div>
                <p className="text-xs text-ink-4 mt-2">
                  Quem ficar de fora não é citado e continua na fila para uma abordagem própria.
                </p>
              </div>
            )}

            <textarea
              value={whatsMsg}
              onChange={(e) => {
                setWhatsMsg(e.target.value)
                setMsgEditada(true)
              }}
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
          onClose={() => setShowAferido(false)}
          onSaved={() => {
            setShowAferido(false)
            carregar()
          }}
        />
      )}
      {confirmacao?.tipo === 'contato' && (
        <ConfirmarModal
          titulo="Excluir este registro de contato?"
          texto="O registro some do histórico deste caminhão e não volta. Se foi um WhatsApp, o caminhão volta a poder receber mensagem."
          rotuloConfirmar="Excluir"
          onConfirmar={() => deletarContato(confirmacao.ligacao)}
          onCancelar={() => setConfirmacao(null)}
        />
      )}
      {confirmacao?.tipo === 'empresa' && (
        <ConfirmarModal
          titulo="Apagar este contato com a empresa?"
          texto="Ele vale para todos os caminhões da frota — some do histórico de todos. Se esse contato já trouxe uma aferição pontuada, o banco recusa. Fica registrado quem apagou e por quê."
          rotuloConfirmar="Apagar e registrar"
          pedirMotivo
          motivoObrigatorio
          onConfirmar={(motivo) => apagarContatoEmpresa(confirmacao.ligacao, motivo)}
          onCancelar={() => setConfirmacao(null)}
        />
      )}
      {confirmacao?.tipo === 'aferido' && (
        <ConfirmarModal
          titulo="Desfazer esta aferição?"
          texto={'O caminhão volta ao que era antes: data, posto e situação anteriores. O ponto que ela gerou é removido e o caminhão volta para a fila. Mês já fechado só o admin geral desfaz.\n\nFica registrado quem desfez e por quê.'}
          rotuloConfirmar="Desfazer e registrar"
          pedirMotivo
          motivoObrigatorio
          onConfirmar={(motivo) => desfazerAfericao(motivo)}
          onCancelar={() => setConfirmacao(null)}
        />
      )}
    </div>
  )
}
