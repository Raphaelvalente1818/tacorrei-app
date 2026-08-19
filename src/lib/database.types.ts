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

// 'presencial' = o cliente veio e o serviço foi feito (botão "Aferido" na ficha).
export type CanalContato = 'ligacao_ativa' | 'ligacao_passiva' | 'whatsapp' | 'presencial'

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
  created_at: string
  updated_at: string
}

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
  papel: 'admin' | 'operador'
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
