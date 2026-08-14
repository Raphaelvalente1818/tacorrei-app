import type { CanalContato, ResultadoLigacao, StatusAgendamento, StatusLead } from './database.types'

export const STATUS_LEAD_LABEL: Record<StatusLead, string> = {
  novo: 'Novo',
  mensagem_enviada: 'Mensagem enviada',
  contatado: 'Contatado',
  sem_resposta: 'Sem resposta',
  agendado: 'Agendado',
  aferido: 'Aferido',
  recusado: 'Recusado',
  invalido: 'Inválido',
}

export const STATUS_LEAD_CLASSES: Record<StatusLead, string> = {
  novo: 'bg-slate-100 text-slate-700 border-slate-200',
  mensagem_enviada: 'bg-teal-50 text-teal-700 border-teal-200',
  contatado: 'bg-blue-50 text-brand-d border-blue-200',
  sem_resposta: 'bg-amber-50 text-amber-700 border-amber-200',
  agendado: 'bg-indigo-50 text-indigo-700 border-indigo-200',
  aferido: 'bg-emerald-50 text-lucro border-emerald-200',
  recusado: 'bg-rose-50 text-rose-700 border-rose-200',
  invalido: 'bg-slate-100 text-slate-500 border-slate-200',
}

export const RESULTADO_LIGACAO_LABEL: Record<ResultadoLigacao, string> = {
  atendeu: 'Atendeu',
  nao_atendeu: 'Não atendeu',
  numero_invalido: 'Número inválido',
  recusou: 'Recusou',
  agendou: 'Agendou aferição',
  reagendar: 'Ligar novamente',
  whatsapp_enviado: 'WhatsApp enviado',
}

export const CANAL_CONTATO_LABEL: Record<CanalContato, string> = {
  ligacao_ativa: 'Ligação feita',
  ligacao_passiva: 'Ligação recebida',
  whatsapp: 'WhatsApp',
}

export const STATUS_AGENDAMENTO_LABEL: Record<StatusAgendamento, string> = {
  agendado: 'Agendado',
  confirmado: 'Confirmado',
  realizado: 'Realizado',
  cancelado: 'Cancelado',
  nao_compareceu: 'Não compareceu',
}

export const STATUS_AGENDAMENTO_CLASSES: Record<StatusAgendamento, string> = {
  agendado: 'bg-indigo-50 text-indigo-700 border-indigo-200',
  confirmado: 'bg-blue-50 text-brand-d border-blue-200',
  realizado: 'bg-emerald-50 text-lucro border-emerald-200',
  cancelado: 'bg-rose-50 text-rose-700 border-rose-200',
  nao_compareceu: 'bg-amber-50 text-amber-700 border-amber-200',
}
