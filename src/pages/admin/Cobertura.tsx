import { useCallback, useEffect, useState } from 'react'
import { Plus, Trash2, MapPin } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/AuthContext'
import ConfirmarModal from '../../components/ConfirmarModal'

interface UnidadeJanela {
  id: string
  nome: string
}
interface CidadeCobertura {
  id: string
  cidade: string
}

export default function Cobertura() {
  const { unidadeAtiva } = useAuth()
  const [unidades, setUnidades] = useState<UnidadeJanela[]>([])
  const [sel, setSel] = useState<string>(unidadeAtiva ?? '')
  const [cidades, setCidades] = useState<CidadeCobertura[]>([])
  const [nova, setNova] = useState('')
  const [loading, setLoading] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)

  const carregarUnidades = useCallback(async () => {
    const { data } = await supabase.from('unidades').select('id, nome').order('nome')
    const list = (data as UnidadeJanela[]) ?? []
    setUnidades(list)
    setSel((s) => s || unidadeAtiva || list[0]?.id || '')
  }, [unidadeAtiva])

  const carregarCidades = useCallback(async (unidadeId: string) => {
    if (!unidadeId) {
      setCidades([])
      return
    }
    const { data } = await supabase
      .from('unidade_cidades')
      .select('id, cidade')
      .eq('unidade_id', unidadeId)
      .order('cidade')
    setCidades((data as CidadeCobertura[]) ?? [])
  }, [])

  useEffect(() => {
    ;(async () => {
      setLoading(true)
      await carregarUnidades()
      setLoading(false)
    })()
  }, [carregarUnidades])

  // Acompanha a unidade em foco no menu ("Visualizando").
  useEffect(() => {
    if (unidadeAtiva) setSel(unidadeAtiva)
  }, [unidadeAtiva])

  useEffect(() => {
    carregarCidades(sel)
  }, [sel, carregarCidades])

  const unidadeSel = unidades.find((u) => u.id === sel) ?? null

  async function addCidade() {
    setErro(null)
    const cidade = nova.trim()
    if (!cidade || !sel) return
    setSalvando(true)
    const { error } = await supabase.from('unidade_cidades').insert({ unidade_id: sel, cidade })
    setSalvando(false)
    if (error) {
      setErro(
        error.message.includes('duplicate') || error.message.includes('unidade_cidades_cidade')
          ? `A cidade "${cidade}" já está vinculada a uma unidade.`
          : error.message
      )
      return
    }
    setNova('')
    carregarCidades(sel)
  }

  const [removendo, setRemovendo] = useState<CidadeCobertura | null>(null)
  async function removeCidade(id: string) {
    const { error } = await supabase.from('unidade_cidades').delete().eq('id', id)
    if (error) throw new Error(error.message)
    setCidades((prev) => prev.filter((c) => c.id !== id))
    setRemovendo(null)
  }

  if (loading) return <p className="text-sm text-ink-4">Carregando…</p>

  return (
    <div className="space-y-4">
      <div className="card p-4 space-y-3">
        <div>
          <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Unidade</label>
          <select
            value={sel}
            onChange={(e) => setSel(e.target.value)}
            className="w-full sm:w-72 px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card"
          >
            {unidades.map((u) => (
              <option key={u.id} value={u.id}>{u.nome}</option>
            ))}
          </select>
        </div>

        <p className="text-xs text-ink-4">Janela, piso e cota ficam em Unidades → Configurar. Aqui é só o território: as cidades que a unidade compra.</p>
      </div>

      <div className="card p-4">
        <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Adicionar cidade</label>
        <div className="flex gap-2">
          <input
            value={nova}
            onChange={(e) => setNova(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addCidade()}
            placeholder="Ex.: Santo André"
            className="flex-1 px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
          />
          <button
            onClick={addCidade}
            disabled={salvando}
            className="flex items-center gap-1.5 bg-brand text-[#04120a] text-sm font-bold px-4 py-2 rounded-xl hover:bg-brand-d transition-colors disabled:opacity-60"
          >
            <Plus size={16} /> Adicionar
          </button>
        </div>
        {erro && <p className="text-sm text-danger mt-2">{erro}</p>}
        <p className="text-xs text-ink-4 mt-2">
          Os leads dessas cidades pertencem a esta unidade. Cada cidade só pode estar em uma unidade.
        </p>
      </div>

      <div className="card overflow-hidden">
        <div className="px-5 py-3 border-b border-line text-xs text-ink-4">
          {cidades.length} {cidades.length === 1 ? 'cidade' : 'cidades'} em {unidadeSel?.nome ?? '—'}
        </div>
        {cidades.length === 0 ? (
          <p className="px-5 py-4 text-sm text-ink-4">Nenhuma cidade vinculada ainda.</p>
        ) : (
          <ul className="divide-y divide-line">
            {cidades.map((c) => (
              <li key={c.id} className="flex items-center justify-between px-5 py-3">
                <span className="flex items-center gap-2 text-sm text-ink">
                  <MapPin size={15} className="text-brand" /> {c.cidade}
                </span>
                <button
                  onClick={() => setRemovendo(c)}
                  className="text-ink-4 hover:text-rose-400"
                  title="Remover cidade"
                >
                  <Trash2 size={15} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      {removendo && (
        <ConfirmarModal
          titulo={`Tirar ${removendo.cidade} da cobertura de ${unidadeSel?.nome ?? 'unidade'}?`}
          texto="Os leads dessa cidade que já estão na base continuam onde estão; a cidade só deixa de ser da unidade para as próximas importações. Dá para adicionar de novo depois."
          rotuloConfirmar="Tirar da cobertura"
          onConfirmar={() => removeCidade(removendo.id)}
          onCancelar={() => setRemovendo(null)}
        />
      )}
    </div>
  )
}
