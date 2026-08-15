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

// Cores dos selos no tema escuro (fundo translúcido + texto claro)
export const STATUS_LEAD_CLASSES: Record<StatusLead, string> = {
  novo: 'bg-slate-500/15 text-slate-300 border-slate-500/30',
  mensagem_enviada: 'bg-teal-500/15 text-teal-300 border-teal-500/30',
  contatado: 'bg-blue-500/15 text-blue-300 border-blue-500/30',
  sem_resposta: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
  agendado: 'bg-indigo-500/15 text-indigo-300 border-indigo-500/30',
  aferido: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
  recusado: 'bg-rose-500/15 text-rose-300 border-rose-500/30',
  invalido: 'bg-slate-500/15 text-slate-400 border-slate-500/30',
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
  agendado: 'bg-indigo-500/15 text-indigo-300 border-indigo-500/30',
  confirmado: 'bg-blue-500/15 text-blue-300 border-blue-500/30',
  realizado: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
  cancelado: 'bg-rose-500/15 text-rose-300 border-rose-500/30',
  nao_compareceu: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
}
