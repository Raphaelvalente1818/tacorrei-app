import { useMemo, useState } from 'react'
import { X, Upload, AlertTriangle } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useFiltroUnidade } from '../lib/AuthContext'

// Importação da base de contratos, colada direto do Excel.
//
// Cada unidade cola a SUA base — a unidade não vem na planilha, vem de quem está
// logado. É o que impede uma de escrever na área da outra, e é também por isso
// que não existe coluna UNIDADE no modelo.
//
// Uma passada cria a empresa (pelo CNPJ) e pendura o veículo (pela placa). Placa
// que já existe é vinculada, nunca duplicada: quase toda frota tem carros que já
// estão na base como lead solto, vindos do RNTRC.

type Resultado = {
  empresas_novas: number
  empresas_atualizadas: number
  vinculados: number
  criados: number
  movidos: number
  ignorados: number
}

type Linha = {
  cnpj: string
  empresa: string
  contato: string
  telefone: string
  placa: string
  data: string | null
  modelo: string
  observacoes: string
}

// Cabeçalhos aceitos por campo. Tolerante a acento, caixa e variação de nome —
// cada sistema exporta com um rótulo diferente e ninguém vai renomear coluna.
const SINONIMOS: Record<keyof Linha, string[]> = {
  cnpj: ['CNPJ', 'CPFCNPJ', 'DOCUMENTO'],
  empresa: ['EMPRESA', 'NOME', 'RAZAOSOCIAL', 'RAZAO', 'CLIENTE'],
  contato: ['CONTATO', 'RESPONSAVEL', 'FALARCOM'],
  telefone: ['TELEFONE', 'CELULAR', 'FONE', 'WHATSAPP'],
  placa: ['PLACA', 'PLACA1', 'PLACAVEICULO'],
  data: ['DATAAFERICAO', 'DATA', 'ULTIMAAFERICAO', 'AFERICAO'],
  modelo: ['MODELO', 'TIPO', 'TIPO1', 'VEICULO'],
  observacoes: ['OBSERVACOES', 'OBS', 'OBSERVACAO'],
}

function normalizaCabecalho(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
}

function parseData(bruta: string): string | null {
  const t = bruta.trim()
  const br = t.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)
  if (br) return `${br[3]}-${br[2]}-${br[1]}`
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t
  return null
}

function parsePlanilha(texto: string): { linhas: Linha[]; faltando: string[] } {
  const cruas = texto.split(/\r?\n/).filter((l) => l.trim())
  if (cruas.length < 2) return { linhas: [], faltando: [] }

  // Excel copia com tabulação; CSV brasileiro usa ponto-e-vírgula.
  const sep = cruas[0].includes('\t') ? '\t' : cruas[0].includes(';') ? ';' : ','
  const cabecalho = cruas[0].split(sep).map(normalizaCabecalho)

  const indice = {} as Record<keyof Linha, number>
  ;(Object.keys(SINONIMOS) as Array<keyof Linha>).forEach((campo) => {
    indice[campo] = cabecalho.findIndex((c) => SINONIMOS[campo].includes(c))
  })

  const faltando: string[] = []
  if (indice.empresa < 0 && indice.cnpj < 0) faltando.push('EMPRESA ou CNPJ')
  if (indice.placa < 0) faltando.push('PLACA')
  if (indice.data < 0) faltando.push('DATA_AFERICAO')
  if (indice.telefone < 0) faltando.push('TELEFONE')
  if (faltando.length) return { linhas: [], faltando }

  const pega = (cols: string[], i: number) => (i >= 0 ? (cols[i] ?? '').trim() : '')

  const linhas = cruas.slice(1).map((linha) => {
    const cols = linha.split(sep)
    return {
      cnpj: pega(cols, indice.cnpj),
      empresa: pega(cols, indice.empresa),
      contato: pega(cols, indice.contato),
      telefone: pega(cols, indice.telefone),
      placa: pega(cols, indice.placa),
      data: parseData(pega(cols, indice.data)),
      modelo: pega(cols, indice.modelo),
      observacoes: pega(cols, indice.observacoes),
    }
  })

  return { linhas, faltando: [] }
}

export default function ImportarEmpresasModal({
  onClose,
  onSaved,
}: {
  onClose: () => void
  onSaved: () => void
}) {
  const { membro } = useAuth()
  const filtroUnidade = useFiltroUnidade()
  const isAdmin = membro?.papel === 'admin'
  const [texto, setTexto] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [resultado, setResultado] = useState<Resultado | null>(null)

  const { linhas, faltando } = useMemo(() => parsePlanilha(texto), [texto])
  const semData = useMemo(() => linhas.filter((l) => l.placa && !l.data).length, [linhas])

  async function importar() {
    setError(null)
    if (linhas.length === 0) {
      setError('Cole a planilha inteira, começando pela linha de cabeçalho.')
      return
    }
    setSalvando(true)
    const { data, error: err } = await supabase.rpc('importar_base_empresas', {
      p_linhas: linhas,
      p_unidade: isAdmin ? filtroUnidade : null,
    })
    setSalvando(false)
    if (err) {
      setError(err.message)
      return
    }
    setResultado(data as Resultado)
    onSaved()
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-2xl p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-1">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <Upload size={18} className="text-lucro" />
            Importar base de contratos
          </h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>
        <p className="text-xs text-ink-4 mb-4">
          Abra a planilha, selecione tudo <b>com a linha de cabeçalho</b> e cole aqui. As colunas
          podem estar em qualquer ordem. Os veículos entram na <b>sua unidade</b>.
        </p>

        {resultado ? (
          <div className="space-y-3">
            <div className="rounded-xl border border-line p-4 space-y-1.5 text-sm">
              <p className="text-ink">
                <b className="text-lucro">{resultado.empresas_novas}</b> empresas cadastradas
                {resultado.empresas_atualizadas > 0 && (
                  <span className="text-ink-4"> · {resultado.empresas_atualizadas} atualizadas</span>
                )}
              </p>
              <p className="text-ink">
                <b className="text-lucro">{resultado.vinculados}</b> veículos já existiam e foram
                vinculados
              </p>
              <p className="text-ink">
                <b className="text-lucro">{resultado.criados}</b> veículos criados agora
              </p>
              {resultado.movidos > 0 && (
                <p className="text-amber-300">
                  <b>{resultado.movidos}</b> mudaram de empresa
                </p>
              )}
              {resultado.ignorados > 0 && (
                <p className="text-ink-4">{resultado.ignorados} linhas ignoradas (sem empresa)</p>
              )}
            </div>
            <button
              onClick={onClose}
              className="w-full py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d"
            >
              Fechar
            </button>
          </div>
        ) : (
          <>
            <textarea
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              rows={12}
              placeholder={'CNPJ\tEMPRESA\tCONTATO\tTELEFONE\tPLACA\tDATA_AFERICAO\n12.345.678/0001-90\tTRANSPORTES EXEMPLO\tMarcia\t(11) 91234-5678\tABC1D23\t12/05/2025'}
              className="w-full px-3 py-2 border border-line rounded-xl text-xs focus-ring outline-none resize-none font-mono"
            />

            {faltando.length > 0 && texto.trim() !== '' && (
              <p className="mt-2 text-sm text-amber-300 flex items-start gap-2">
                <AlertTriangle size={15} className="mt-0.5 shrink-0" />
                <span>
                  Faltam colunas obrigatórias: <b>{faltando.join(', ')}</b>. Confira se a primeira
                  linha colada é o cabeçalho.
                </span>
              </p>
            )}

            {linhas.length > 0 && (
              <div className="mt-2 text-xs text-ink-4 space-y-1">
                <p>
                  <b className="text-ink">{linhas.length}</b> linhas lidas.
                </p>
                {semData > 0 && (
                  <p className="text-amber-300">
                    {semData} sem data de aferição — esses veículos entram no cadastro, mas não
                    aparecem em relação mensal nenhuma até a data ser preenchida.
                  </p>
                )}
              </div>
            )}

            {error && <p className="text-sm text-danger mt-2">{error}</p>}

            <button
              onClick={importar}
              disabled={salvando || linhas.length === 0}
              className="w-full mt-3 py-2.5 rounded-xl bg-brand text-white font-bold text-sm hover:bg-brand-d disabled:opacity-60"
            >
              {salvando ? 'Importando…' : `Importar ${linhas.length || ''} linhas`}
            </button>
          </>
        )}
      </div>
    </div>
  )
}
