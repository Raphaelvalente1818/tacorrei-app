import { Trophy } from 'lucide-react'
import MetaDoMes from '../components/MetaDoMes'

// "Meu placar": a operadora vê a mesma composição do mês que o admin vê na
// aba Meta — só os pontos dela, o total da unidade ao lado, sem auditoria.
// É a mesma tela e o mesmo número: ninguém discute placar no fim do mês.
export default function Placar() {
  return (
    <div>
      <div className="mb-6">
        <h1 className="text-xl font-extrabold text-ink flex items-center gap-2">
          <Trophy size={20} className="text-brand" /> Meu placar
        </h1>
        <p className="text-sm text-ink-4">
          Ponto é aferição feita no nosso posto, de caminhão que você contatou nos 45 dias anteriores.
          Ligação e mensagem não pontuam — o que pontua é o caminhão chegar.
        </p>
      </div>
      <MetaDoMes modo="operadora" />
    </div>
  )
}
