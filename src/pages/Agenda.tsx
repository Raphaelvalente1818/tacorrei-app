import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { STATUS_AGENDAMENTO_CLASSES, STATUS_AGENDAMENTO_LABEL } from '../lib/status'
import type { StatusAgendamento } from '../lib/database.types'

interface AgendamentoComLead {
  id: string
  data_hora: string
  local: string | null
  status: StatusAgendamento
  caminhoneiro_id: string
  caminhoneiros: { nome: string; telefone: string } | null
}

const STATUS_OPCOES: StatusAgendamento[] = ['agendado', 'confirmado', 'realizado', 'cancelado', 'nao_compareceu']

export default function Agenda() {
  const [itens, setItens] = useState<AgendamentoComLead[]>([])
  const [loading, setLoading] = useState(true)

  async function carregar() {
    setLoading(true)
    const { data } = await supabase
      .from('agendamentos')
      .select('id, data_hora, local, status, caminhoneiro_id, caminhoneiros ( nome, telefone )')
      .order('data_hora', { ascending: true })
    setItens((data as unknown as AgendamentoComLead[]) ?? [])
    setLoading(false)
  }

  useEffect(() => {
    carregar()
  }, [])

  async function atualizarStatus(id: string, status: StatusAgendamento) {
    await supabase.from('agendamentos').update({ status }).eq('id', id)
    carregar()
  }

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-xl font-extrabold text-ink">Agenda de aferições</h1>
        <p className="text-sm text-ink-4">Todos os agendamentos, do mais próximo ao mais distante</p>
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <p className="p-6 text-sm text-ink-4">Carregando…</p>
        ) : itens.length === 0 ? (
          <p className="p-6 text-sm text-ink-4">Nenhum agendamento ainda.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-3">Data/hora</th>
                <th className="px-5 py-3">Caminhoneiro</th>
                <th className="px-5 py-3">Local</th>
                <th className="px-5 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {itens.map((a) => (
                <tr key={a.id} className="border-b border-line last:border-0 hover:bg-slate-50">
                  <td className="px-5 py-3 font-semibold text-ink">
                    {new Date(a.data_hora).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
                  </td>
                  <td className="px-5 py-3">
                    <Link to={`/leads/${a.caminhoneiro_id}`} className="text-brand-d font-semibold hover:underline">
                      {a.caminhoneiros?.nome ?? '—'}
                    </Link>
                  </td>
                  <td className="px-5 py-3 text-ink-6">{a.local ?? '—'}</td>
                  <td className="px-5 py-3">
                    <select
                      value={a.status}
                      onChange={(e) => atualizarStatus(a.id, e.target.value as StatusAgendamento)}
                      className={`border rounded-full px-2.5 py-1 text-xs font-bold outline-none ${STATUS_AGENDAMENTO_CLASSES[a.status]}`}
                    >
                      {STATUS_OPCOES.map((s) => (
                        <option key={s} value={s}>
                          {STATUS_AGENDAMENTO_LABEL[s]}
                        </option>
                      ))}
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
