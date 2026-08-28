import { useState } from 'react'
import { X, Truck, AlertTriangle, ArrowRight } from 'lucide-react'
import { supabase } from '../lib/supabase'

// Entrada em lote das placas de uma empresa, em DUAS etapas: confere, depois grava.
//
// A conferência existe por um motivo concreto. Boa parte dessas placas já está na
// base — como lead solto vindo do RNTRC, ou pior, já pendurada em OUTRA empresa.
// Criar de novo duplicaria o carro e ele sumiria da relação mensal; mover em
// silêncio tiraria o caminhão da relação da empresa antiga sem ninguém notar.
// Por isso nada é gravado antes de a pessoa ver o que vai acontecer.
type Analise = {
  novas: Array<{ placa: string }>
  leads: Array<{ placa: string; dono: string }>
  mesma_empresa: Array<{ placa: string }>
  outras_empresas: Array<{ placa: string; empresa: string }>
  invalidas: string[]
  repetidas: string[]
}

type Resultado = { vinculados: number; criados: number; movidos: number; ignorados: number }

function parseLinhas(texto: string): Array<{ placa: string; data: string | null }> {
  return texto
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean)
    .map((linha) => {
      const partes = linha.split(/[;,\t]+/).map((p) => p.trim())
      const bruta = partes[1] ?? ''
      let data: string | null = null
      // Aceita 12/05/2026 e 2026-05-12 — planilha brasileira solta os dois.
      const br = bruta.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)
      if (br) data = `${br[3]}-${br[2]}-${br[1]}`
      else if (/^\d{4}-\d{2}-\d{2}$/.test(bruta)) data = bruta
      return { placa: partes[0] ?? '', data }
    })
}

export default function VeiculosEmpresaModal({
  empresaId,
  empresaNome,
  onClose,
  onSaved,
}: {
  empresaId: string
  empresaNome: string
  onClose: () => void
  onSaved: () => void
}) {
  const [texto, setTexto] = useState('')
  const [analise, setAnalise] = useState<Analise | null>(null)
  const [ocupado, setOcupado] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [resultado, setResultado] = useState<Resultado | null>(null)

  const linhas = parseLinhas(texto)

  async function conferir() {
    setError(null)
    if (linhas.length === 0) {
      setError('Cole ao menos uma placa.')
      return
    }
    setOcupado(true)
    const { data, error: err } = await supabase.rpc('analisar_veiculos_empresa', {
      p_empresa: empresaId,
      p_veiculos: linhas,
    })
    setOcupado(false)
    if (err) {
      setError(err.message)
      return
    }
    setAnalise(data as Analise)
  }

  async function confirmar() {
    setOcupado(true)
    const { data, error: err } = await supabase.rpc('vincular_veiculos_empresa', {
      p_empresa: empresaId,
      p_veiculos: linhas,
    })
    setOcupado(false)
    if (err) {
      setError(err.message)
      return
    }
    setResultado(data as Resultado)
    onSaved()
  }

  const temConflito = (analise?.outras_empresas.length ?? 0) > 0

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-1">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <Truck size={18} className="text-lucro" />
            Veículos de {empresaNome}
          </h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>

        {/* ── Etapa 3: o que foi feito ─────────────────────────────────────── */}
        {resultado ? (
          <div className="space-y-3 mt-4">
            <div className="rounded-xl border border-line p-4 space-y-1.5 text-sm">
              <p className="text-ink">
                <b className="text-lucro">{resultado.criados}</b> veículos criados
              </p>
              <p className="text-ink">
                <b className="text-lucro">{resultado.vinculados}</b> já existiam e foram vinculados
              </p>
              {resultado.movidos > 0 && (
                <p className="text-amber-300">
                  <b>{resultado.movidos}</b> mudaram de empresa
                </p>
              )}
            </div>
            <button
              onClick={onClose}
              className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d"
            >
              Fechar
            </button>
          </div>
        ) : analise ? (
          /* ── Etapa 2: confira antes de gravar ───────────────────────────── */
          <div className="space-y-3 mt-4">
            <p className="text-xs text-ink-4">Nada foi gravado ainda. Confira o que vai acontecer:</p>

            <div className="rounded-xl border border-line p-4 space-y-1.5 text-sm">
              <p className="text-ink">
                <b className="text-lucro">{analise.novas.length}</b> placas novas — serão criadas
              </p>
              <p className="text-ink">
                <b className="text-lucro">{analise.leads.length}</b> já existem na base como lead —
                serão <b>movidas</b> para esta empresa, sem duplicar
              </p>
              {analise.mesma_empresa.length > 0 && (
                <p className="text-ink-4">
                  {analise.mesma_empresa.length} já são desta empresa — nada muda
                </p>
              )}
              {analise.repetidas.length > 0 && (
                <p className="text-ink-4">
                  {analise.repetidas.length} repetidas na própria lista — conta uma vez só
                </p>
              )}
              {analise.invalidas.length > 0 && (
                <p className="text-ink-4">
                  {analise.invalidas.length} linhas sem placa válida — ignoradas
                </p>
              )}
            </div>

            {/* O caso que precisa de decisão humana. */}
            {temConflito && (
              <div className="rounded-xl border border-amber-500/40 bg-amber-500/10 p-4">
                <p className="text-sm font-bold text-amber-300 flex items-center gap-2 mb-2">
                  <AlertTriangle size={16} />
                  {analise.outras_empresas.length} placa
                  {analise.outras_empresas.length === 1 ? '' : 's'} já pertence
                  {analise.outras_empresas.length === 1 ? '' : 'm'} a outra empresa
                </p>
                <p className="text-xs text-amber-200/80 mb-3">
                  Confirmando, {analise.outras_empresas.length === 1 ? 'ela sai' : 'elas saem'} da
                  relação mensal da empresa atual e {analise.outras_empresas.length === 1 ? 'passa' : 'passam'}{' '}
                  para a {empresaNome}. Se o caminhão não foi vendido nem transferido, cancele.
                </p>
                <div className="space-y-1 max-h-40 overflow-y-auto">
                  {analise.outras_empresas.map((v) => (
                    <p key={v.placa} className="text-xs text-ink flex items-center gap-1.5">
                      <span className="font-mono font-bold">{v.placa}</span>
                      <span className="text-ink-4">{v.empresa}</span>
                      <ArrowRight size={12} className="text-amber-400" />
                      <span className="text-amber-300">{empresaNome}</span>
                    </p>
                  ))}
                </div>
              </div>
            )}

            {analise.leads.length > 0 && (
              <details className="rounded-xl border border-line p-3">
                <summary className="text-xs font-bold text-ink-6 cursor-pointer">
                  Ver as {analise.leads.length} que já estavam na base
                </summary>
                <div className="mt-2 space-y-1 max-h-40 overflow-y-auto">
                  {analise.leads.map((v) => (
                    <p key={v.placa} className="text-xs text-ink-6">
                      <span className="font-mono font-bold text-ink">{v.placa}</span> — hoje em nome
                      de {v.dono}
                    </p>
                  ))}
                </div>
              </details>
            )}

            {error && <p className="text-sm text-danger">{error}</p>}

            <div className="flex gap-2">
              <button
                onClick={() => setAnalise(null)}
                className="flex-1 py-2.5 rounded-xl border border-line text-ink-6 font-bold text-sm hover:bg-white/5"
              >
                Voltar e corrigir
              </button>
              <button
                onClick={confirmar}
                disabled={ocupado}
                className={`flex-1 py-2.5 rounded-xl font-bold text-sm disabled:opacity-60 ${
                  temConflito
                    ? 'bg-amber-500 text-[#1a1200] hover:opacity-90'
                    : 'bg-brand text-white hover:bg-brand-d'
                }`}
              >
                {ocupado ? 'Gravando…' : temConflito ? 'Confirmar, inclusive as mudanças' : 'Confirmar'}
              </button>
            </div>
          </div>
        ) : (
          /* ── Etapa 1: colar ─────────────────────────────────────────────── */
          <>
            <p className="text-xs text-ink-4 mb-4 mt-1">
              Uma placa por linha. Se souber a data da última aferição, ponha depois de vírgula.
              Placa que já existir na base é <b>movida</b> para a empresa, nunca duplicada — e você
              confere antes.
            </p>
            <textarea
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              rows={12}
              placeholder={'ABC1D23, 12/05/2026\nEFG4H56, 03/09/2025\nIJK7L89'}
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none resize-none font-mono uppercase"
            />
            <p className="text-xs text-ink-4 mt-1.5">
              {linhas.length > 0
                ? `${linhas.length} linha${linhas.length === 1 ? '' : 's'} lida${linhas.length === 1 ? '' : 's'}`
                : 'Cole a lista de placas da empresa'}
            </p>

            {error && <p className="text-sm text-danger mt-2">{error}</p>}

            <button
              onClick={conferir}
              disabled={ocupado || linhas.length === 0}
              className="w-full mt-3 py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d disabled:opacity-60"
            >
              {ocupado ? 'Conferindo…' : 'Conferir antes de gravar'}
            </button>
          </>
        )}
      </div>
    </div>
  )
}
