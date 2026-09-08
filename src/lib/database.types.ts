// Tipos manuais alinhados à migration 0001_init.sql
// (podem ser substituídos depois por `supabase gen types typescript`)

export type StatusLead =
  | 'novo'
  | 'mensagem_enviada'
  | 'contatado'
  | 'sem_resposta'
  | 'agendado'
  | 'aferido'
  | 'recusado'
  | 'invalido'

export type OrigemLead = 'indicacao' | 'campanha' | 'cold_call' | 'site' | 'whatsapp' | 'outro'

export type ResultadoLigacao =
  | 'atendeu'
  | 'nao_atendeu'
  | 'numero_invalido'
  | 'recusou'
  | 'agendou'
  | 'reagendar'
  | 'whatsapp_enviado'
  | 'aferido'
  // Colhido na ligação: "pode me mandar no WhatsApp?". É o consentimento que
  // libera a mensagem para quem é cliente de concorrente.
  | 'autorizou_whatsapp'
  // Anotação do próprio app (troca de proprietário), não uma ação da operadora.
  | 'atualizacao'

// 'presencial' = o cliente veio e o serviço foi feito (botão "Aferido" na ficha).
// 'sistema' = o app registrou sozinho.
export type CanalContato =
  | 'ligacao_ativa' | 'ligacao_passiva' | 'whatsapp' | 'presencial' | 'sistema'

export type StatusAgendamento = 'agendado' | 'confirmado' | 'realizado' | 'cancelado' | 'nao_compareceu'

export interface Caminhoneiro {
  id: string
  nome: string
  telefone: string
  telefone_e164: string | null
  cidade: string | null
  uf: string | null
  placa_veiculo: string | null
  modelo_veiculo: string | null
  origem: OrigemLead
  status: StatusLead
  observacoes: string | null
  responsavel_id: string | null
  rntrc: string | null
  renavam: string | null
  data_ultima_afericao: string | null
  data_ultimo_whatsapp: string | null
  tem_tacografo: boolean
  whatsapp_invalido: boolean
  unidade_id: string
  // Onde o veículo fez a ÚLTIMA aferição (coluna W da base do RNTRC).
  // Separa cliente da casa de cliente de concorrente — e isso decide o canal.
  posto_afericao: string | null
  // "Pode me mandar no WhatsApp?" dito na ligação. Sem isso, cliente de
  // concorrente não recebe mensagem.
  autorizou_whatsapp: boolean
  autorizado_em: string | null
  autorizado_por: string | null
  // Frota a que o caminhão pertence. Null = autônomo, um dono um caminhão.
  empresa_id: string | null
  created_at: string
  updated_at: string
}

// 'contrato'  → fora da fila; o caminho é a relação mensal na aba Empresas.
// 'prospecto' → frota que ainda afere no concorrente (ou em ninguém). Continua
//               na fila e é trabalhada — mas como UMA abordagem, não N.
export type SituacaoEmpresa = 'contrato' | 'prospecto'

export interface Empresa {
  id: string
  unidade_id: string
  cnpj: string | null
  nome: string
  contato: string | null
  telefone: string | null
  situacao: SituacaoEmpresa
  ativo: boolean
  observacoes: string | null
  created_at: string
  updated_at: string
}

// Um caminhão da frota, como vem dentro de `obter_lead`.
export interface VeiculoDaFrota {
  id: string
  placa: string | null
  venc: string | null
  // Dias até vencer. Negativo = já venceu. É o que decide quem entra na mesma
  // conversa e quem fica para uma abordagem futura.
  dias: number | null
  este: boolean
}

// A frota vista de dentro da ficha de um caminhão dela.
export interface EmpresaDoLead {
  id: string
  nome: string
  cnpj: string | null
  contato: string | null
  telefone: string | null
  situacao: SituacaoEmpresa
  agrupamento_dias: number
  // "Herda o melhor": se UM caminhão da frota já aferiu conosco, a pessoa que
  // atende o telefone nos conhece. O opt-in é dela, não da placa.
  ja_e_cliente: boolean
  veiculos: VeiculoDaFrota[]
}

// O que `obter_lead` devolve: o caminhão e, quando ele é de frota, a frota junto.
export type LeadComEmpresa = Caminhoneiro & { empresa?: EmpresaDoLead | null }

export interface Ligacao {
  id: string
  caminhoneiro_id: string
  operador_id: string | null
  resultado: ResultadoLigacao
  canal: CanalContato
  duracao_segundos: number | null
  notas: string | null
  proxima_acao_em: string | null
  created_at: string
}

export interface Agendamento {
  id: string
  caminhoneiro_id: string
  ligacao_id: string | null
  data_hora: string
  local: string | null
  status: StatusAgendamento
  observacoes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

export interface EquipeMembro {
  user_id: string
  nome: string
  // 'admin' = Raphael/Emerson (tudo, todas as unidades)
  // 'admin_unidade' = dono/gerente de UMA unidade
  // 'operador' = a fila do dia
  papel: 'admin' | 'admin_unidade' | 'operador'
  ativo: boolean
  unidade_id: string | null
  email: string | null
  created_at: string
}

export interface Unidade {
  id: string
  nome: string
}

// Placeholder mínimo para satisfazer o generic do supabase-js.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Database = any
