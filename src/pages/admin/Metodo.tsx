import { useCallback, useEffect, useState } from 'react'
import { Save, Target } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { botao, input } from './ui'

// ── Método (só admin geral) ──────────────────────────────────────────────────
// A tabela de pontos e os parâmetros do motor (item 4 da matriz). É uma linha só
// (`parametros_pontos`, id = 1) e vale para todas as unidades — o método é do
// Aferi+, o preço do ponto é da unidade (aba Prêmio). Mudança aqui só pega
// aferições registradas daqui em diante: o ponto é congelado no registro.

type Parametros = {
  conquista_mista: number
  conquista_virgem: number
  conquista_avulso: number
  vencido: number
  renovacao: number
  contrato: number
  bonus_empresa: number
  janela_atribuicao_dias: number
  carencia_vencido_dias: number
  piso_carteira_pct: number
  fator_carteira: number
}

const CAMPOS: { id: keyof Parametros; rotulo: string; ajuda: string; decimal?: boolean }[] = [
  { id: 'conquista_mista', rotulo: 'Conquista · pé na porta', ajuda: 'Caminhão do concorrente em empresa que já afere conosco.' },
  { id: 'conquista_virgem', rotulo: 'Conquista · empresa nova', ajuda: 'Caminhão do concorrente em empresa sem nenhum conosco.' },
  { id: 'conquista_avulso', rotulo: 'Conquista · autônomo', ajuda: 'Caminhão do concorrente, sem empresa.' },
  { id: 'vencido', rotulo: 'Vencido que voltou', ajuda: 'Qualquer posto, vencido há mais que a carência.' },
  { id: 'renovacao', rotulo: 'Renovação', ajuda: 'Já era nosso e voltou.' },
  { id: 'contrato', rotulo: 'Frota com contrato', ajuda: 'Caminhão de empresa com contrato.' },
  { id: 'bonus_empresa', rotulo: 'Bônus empresa conquistada', ajuda: 'Uma vez por empresa, para sempre.' },
  { id: 'janela_atribuicao_dias', rotulo: 'Janela de atribuição (dias)', ajuda: 'Contato até tantos dias antes da aferição leva o ponto.' },
  { id: 'carencia_vencido_dias', rotulo: 'Carência do vencido (dias)', ajuda: 'Antes disso, caminhão vencido do concorrente é conquista.' },
  { id: 'piso_carteira_pct', rotulo: 'Piso da carteira (%)', ajuda: 'Abaixo disso as conquistas do mês entram com o fator, e o bolo não sai.' },
  { id: 'fator_carteira', rotulo: 'Fator da carteira', ajuda: 'Ex.: 0,8.', decimal: true },
]

export default function Metodo() {
  const [p, setP] = useState<Parametros | null>(null)
  const [orig, setOrig] = useState<Parametros | null>(null)
  const [salvando, setSalvando] = useState(false)
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null)

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.from('parametros_pontos').select('*').eq('id', 1).maybeSingle()
    if (error) {
      setMsg({ tipo: 'erro', texto: error.message })
      return
    }
    setP(data as Parametros)
    setOrig(data as Parametros)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  if (!p || !orig) return <p className="text-sm text-ink-4">{msg?.texto ?? 'Carregando…'}</p>

  const mudados = CAMPOS.filter((c) => Number(p[c.id]) !== Number(orig[c.id]))

  async function salvar() {
    if (!p) return
    setSalvando(true)
    setMsg(null)
    const campos: Record<string, number> = {}
    for (const c of mudados) campos[c.id] = Number(p[c.id])
    const { error } = await supabase.from('parametros_pontos').update({ ...campos, atualizado_em: new Date().toISOString() }).eq('id', 1)
    setSalvando(false)
    if (error) {
      setMsg({ tipo: 'erro', texto: error.message })
      return
    }
    setMsg({ tipo: 'ok', texto: 'Salvo. Vale para as aferições registradas daqui em diante.' })
    carregar()
  }

  return (
    <div className="card p-5 space-y-4">
      <div>
        <h2 className="text-sm font-extrabold text-ink flex items-center gap-2">
          <Target size={16} className="text-brand" /> Tabela de pontos e parâmetros do método
        </h2>
        <p className="text-xs text-ink-4 mt-1">
          Uma tabela para todas as unidades. O ponto é congelado no momento do registro — mudar aqui não reescreve o passado.
          Antes de mexer, leia o "Ponto de observação" do método: renovação a 2 foi decisão, não descuido.
        </p>
      </div>
      <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
        {CAMPOS.map((c) => (
          <div key={c.id}>
            <label className="block text-[11px] font-bold uppercase tracking-wide text-ink-4 mb-1">{c.rotulo}</label>
            <input
              type="number"
              step={c.decimal ? '0.05' : '1'}
              value={p[c.id]}
              onChange={(e) => setP((x) => (x ? { ...x, [c.id]: e.target.value === '' ? 0 : Number(e.target.value) } : x))}
              className={`${input} w-full ${Number(p[c.id]) !== Number(orig[c.id]) ? 'border-brand' : ''}`}
            />
            <p className="text-[11px] text-ink-4 mt-0.5">{c.ajuda}</p>
          </div>
        ))}
      </div>
      <div className="flex items-center gap-3">
        <button onClick={salvar} disabled={mudados.length === 0 || salvando} className={botao}>
          <Save size={15} /> {salvando ? 'Salvando…' : mudados.length > 0 ? `Salvar ${mudados.length} ${mudados.length === 1 ? 'alteração' : 'alterações'}` : 'Nada a salvar'}
        </button>
        {msg && <span className={`text-sm ${msg.tipo === 'ok' ? 'text-lucro' : 'text-danger'}`}>{msg.texto}</span>}
      </div>
    </div>
  )
}
