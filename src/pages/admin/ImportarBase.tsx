import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Check, Database, Search, Upload } from 'lucide-react'
import { supabase } from '../../lib/supabase'
import { botao, input, num } from './ui'

// ── Importar base (só admin geral) ───────────────────────────────────────────
// A base é o produto: quem importa é o Aferi+, nunca a unidade (item 8 da matriz).
// Fluxo em três passos, sem surpresa: colar a extração do RNTRC → ver a
// conferência (novas, existentes, sem data, fora da cobertura, duplicadas, postos)
// → confirmar. O banco (`importar_base`, 0087) aplica as regras que não mudam:
// placa existente é atualizada e nunca duplicada; sem data = sem tacógrafo; posto
// só troca com data mais nova; cidade fora da cobertura só entra se marcado.
//
// A extração vem com uma placa por linha (PLACA1/TIPO1/RENAVAM1 + DATA_AFERICAO +
// POSTO_AFERICAO) ou com até 12 placas por linha (PLACA1..PLACA12). No segundo caso
// a data e o posto valem para a PRIMEIRA placa; as outras entram sem data.

type Linha = {
  placa: string
  nome: string
  cpf_cnpj: string
  rntrc: string
  telefone: string
  celular: string
  cidade: string
  uf: string
  tipo: string
  renavam: string
  data: string | null
  posto: string
}

type Analise = {
  linhas: number
  placas: number
  duplicadas: number
  novas: number
  existentes: number
  existentes_com_data_nova: number
  sem_data: number
  com_data: number
  fora_cobertura: number
  novas_fora_cobertura: number
  cidades_fora: { cidade: string; n: number }[]
  postos: { posto: string; n: number; nosso: boolean }[]
  ignoradas: number
}

type Resultado = {
  id: string
  linhas: number
  criados: number
  atualizados: number
  sem_data: number
  fora_cobertura: number
  fora_cobertura_incluidas: boolean
  ignoradas: number
}

type Historico = {
  id: string
  unidade: string
  importado_em: string
  por: string | null
  rotulo: string | null
  linhas: number
  criados: number
  atualizados: number
  sem_data: number
  fora_cobertura: number
  ignorados: number
}

const SINONIMOS: Record<Exclude<keyof Linha, 'placa' | 'tipo' | 'renavam'>, string[]> = {
  nome: ['NOME', 'RAZAOSOCIAL', 'PROPRIETARIO', 'TRANSPORTADOR'],
  cpf_cnpj: ['CPF', 'CNPJ', 'CPFCNPJ', 'DOCUMENTO', 'RENAVAMCPF'],
  rntrc: ['RNTRC'],
  telefone: ['TELEFONE', 'FONE'],
  celular: ['CELULAR', 'WHATSAPP', 'CEL'],
  cidade: ['MUNICIPIO', 'CIDADE'],
  uf: ['UF', 'ESTADO'],
  data: ['DATAAFERICAO', 'DATATACOGRAFO', 'ULTIMAAFERICAO', 'DATAULTIMAAFERICAO', 'AFERICAO'],
  posto: ['POSTOAFERICAO', 'POSTOTACOGRAFO', 'POSTO'],
}

function normalizaCabecalho(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

function parseData(bruta: string): string | null {
  const t = bruta.trim()
  const br = t.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/)
  if (br) return `${br[3]}-${br[2].padStart(2, '0')}-${br[1].padStart(2, '0')}`
  const iso = t.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`
  return null
}

function parsePlanilha(texto: string): { linhas: Linha[]; faltando: string[]; multiplas: number } {
  const cruas = texto.split(/\r?\n/).filter((l) => l.trim())
  if (cruas.length < 2) return { linhas: [], faltando: [], multiplas: 0 }
  const sep = cruas[0].includes('\t') ? '\t' : cruas[0].includes(';') ? ';' : ','
  const cab = cruas[0].split(sep).map(normalizaCabecalho)

  const idx = (nomes: string[]) => cab.findIndex((c) => nomes.includes(c))
  const indice: Record<string, number> = {}
  for (const campo of Object.keys(SINONIMOS) as (keyof typeof SINONIMOS)[]) indice[campo] = idx(SINONIMOS[campo])

  // Placas: PLACA, PLACA1..PLACA12 (com TIPOn / RENAVAMn ao lado).
  const placas: { placa: number; tipo: number; renavam: number }[] = []
  const p0 = idx(['PLACA', 'PLACAVEICULO'])
  if (p0 >= 0) placas.push({ placa: p0, tipo: idx(['TIPO', 'TIPOVEICULO', 'MODELO']), renavam: idx(['RENAVAM']) })
  for (let n = 1; n <= 12; n++) {
    const p = idx([`PLACA${n}`])
    if (p >= 0) placas.push({ placa: p, tipo: idx([`TIPO${n}`]), renavam: idx([`RENAVAM${n}`]) })
  }

  const faltando: string[] = []
  if (placas.length === 0) faltando.push('PLACA (ou PLACA1)')
  if (indice.data < 0) faltando.push('DATA_AFERICAO')
  if (faltando.length) return { linhas: [], faltando, multiplas: 0 }

  const pega = (cols: string[], i: number) => (i >= 0 ? (cols[i] ?? '').trim() : '')
  const linhas: Linha[] = []
  let multiplas = 0
  for (const crua of cruas.slice(1)) {
    const cols = crua.split(sep)
    const base = {
      nome: pega(cols, indice.nome),
      cpf_cnpj: pega(cols, indice.cpf_cnpj),
      rntrc: pega(cols, indice.rntrc),
      telefone: pega(cols, indice.telefone),
      celular: pega(cols, indice.celular),
      cidade: pega(cols, indice.cidade),
      uf: pega(cols, indice.uf),
    }
    const data = parseData(pega(cols, indice.data))
    const posto = pega(cols, indice.posto)
    let k = 0
    for (const pl of placas) {
      const placa = pega(cols, pl.placa)
      if (!placa) continue
      linhas.push({
        ...base,
        placa,
        tipo: pega(cols, pl.tipo),
        renavam: pega(cols, pl.renavam),
        // A data e o posto da linha valem para a primeira placa dela.
        data: k === 0 ? data : null,
        posto: k === 0 ? posto : '',
      })
      k++
    }
    if (k > 1) multiplas++
  }
  return { linhas, faltando: [], multiplas }
}

function fmtDataHora(iso: string): string {
  return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
}

export default function ImportarBase({ unidadeId, nomeUnidade }: { unidadeId: string; nomeUnidade: string | null }) {
  const [texto, setTexto] = useState('')
  const [rotulo, setRotulo] = useState('')
  const [incluirFora, setIncluirFora] = useState(false)
  const [analise, setAnalise] = useState<Analise | null>(null)
  const [analisando, setAnalisando] = useState(false)
  const [importando, setImportando] = useState(false)
  const [confirmando, setConfirmando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [resultado, setResultado] = useState<Resultado | null>(null)
  const [historico, setHistorico] = useState<Historico[]>([])

  const { linhas, faltando, multiplas } = useMemo(() => parsePlanilha(texto), [texto])

  const carregarHistorico = useCallback(async () => {
    const { data } = await supabase.rpc('historico_importacoes', { p_unidade: null })
    setHistorico((data as Historico[]) ?? [])
  }, [])

  useEffect(() => {
    carregarHistorico()
  }, [carregarHistorico])

  // Texto novo ou unidade nova: a conferência anterior não vale mais.
  useEffect(() => {
    setAnalise(null)
    setConfirmando(false)
    setResultado(null)
    setErro(null)
  }, [texto, unidadeId])

  async function analisar() {
    setErro(null)
    setAnalisando(true)
    const { data, error } = await supabase.rpc('analisar_base', { p_unidade: unidadeId, p_linhas: linhas })
    setAnalisando(false)
    if (error) {
      setErro(error.message)
      return
    }
    setAnalise(data as Analise)
  }

  async function importar() {
    setErro(null)
    setImportando(true)
    const { data, error } = await supabase.rpc('importar_base', {
      p_unidade: unidadeId,
      p_linhas: linhas,
      p_rotulo: rotulo.trim() || null,
      p_incluir_fora_cobertura: incluirFora,
    })
    setImportando(false)
    setConfirmando(false)
    if (error) {
      setErro(error.message)
      return
    }
    setResultado(data as Resultado)
    setTexto('')
    setRotulo('')
    setIncluirFora(false)
    carregarHistorico()
  }

  const entrariam = analise ? analise.placas - analise.duplicadas - (incluirFora ? 0 : analise.fora_cobertura) : 0

  return (
    <div className="space-y-4">
      <div className="card p-5">
        <h2 className="text-sm font-extrabold text-ink flex items-center gap-2">
          <Upload size={16} className="text-brand" /> Importar base para <span className="text-brand">{nomeUnidade ?? '—'}</span>
        </h2>
        <p className="text-xs text-ink-4 mt-1 mb-3">
          Abra a extração do RNTRC no Excel, selecione tudo <b>com a linha de cabeçalho</b> e cole aqui. Colunas que o app entende:
          NOME, CPF/CNPJ, RNTRC, TELEFONE, CELULAR, MUNICIPIO, UF, PLACA (ou PLACA1…PLACA12 com TIPO e RENAVAM), DATA_AFERICAO, POSTO_AFERICAO.
          Nada é gravado antes de você ver a conferência e confirmar.
        </p>
        <textarea
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          placeholder={'NOME\tRNTRC\tCPF\tMUNICIPIO\tUF\tTELEFONE\tCELULAR\tPLACA1\tTIPO1\tRENAVAM1\tDATA_AFERICAO\tPOSTO_AFERICAO\n…'}
          rows={8}
          className="w-full px-3 py-2 border border-line rounded-xl text-xs font-mono bg-card focus-ring outline-none"
          spellCheck={false}
        />
        <div className="flex flex-wrap items-center gap-3 mt-3">
          <input value={rotulo} onChange={(e) => setRotulo(e.target.value)} placeholder="Rótulo (ex.: extração SBC set/26)" className={`${input} w-72`} />
          <button onClick={analisar} disabled={linhas.length === 0 || analisando} className={botao}>
            <Search size={15} /> {analisando ? 'Conferindo…' : `Conferir ${num(linhas.length)} placas`}
          </button>
          {texto && faltando.length > 0 && (
            <span className="text-sm text-danger flex items-center gap-1"><AlertTriangle size={14} /> Faltam colunas: {faltando.join(', ')}</span>
          )}
          {multiplas > 0 && (
            <span className="text-xs text-amber-300">{num(multiplas)} linhas com mais de uma placa — a data vale só para a primeira.</span>
          )}
        </div>
        {erro && <p className="text-sm text-danger mt-2">{erro}</p>}
      </div>

      {analise && (
        <div className="card p-5 border-brand/40">
          <h2 className="text-sm font-extrabold text-ink mb-3 flex items-center gap-2">
            <Database size={16} className="text-brand" /> Conferência — nada gravado ainda
          </h2>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
            <Numero rotulo="Placas válidas" valor={analise.placas} ajuda={`${num(analise.ignoradas)} linhas sem placa válida`} />
            <Numero rotulo="Novas" valor={analise.novas} cor="text-emerald-300" />
            <Numero rotulo="Já existem (serão atualizadas)" valor={analise.existentes} ajuda={`${num(analise.existentes_com_data_nova)} com data mais nova que a gravada`} />
            <Numero rotulo="Repetidas na planilha" valor={analise.duplicadas} ajuda="Fica a primeira com data" />
            <Numero rotulo="Com data de aferição" valor={analise.com_data} />
            <Numero rotulo="Sem data (sem tacógrafo)" valor={analise.sem_data} cor={analise.sem_data > 0 ? 'text-amber-300' : undefined} ajuda="Entram, mas fora da fila" />
            <Numero rotulo="Fora da cobertura" valor={analise.fora_cobertura} cor={analise.fora_cobertura > 0 ? 'text-rose-300' : undefined} ajuda={`${num(analise.novas_fora_cobertura)} novas`} />
            <Numero rotulo="Vão entrar" valor={entrariam} cor="text-brand" />
          </div>

          {analise.cidades_fora.length > 0 && (
            <div className="mb-4">
              <p className="text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Cidades fora da cobertura de {nomeUnidade}</p>
              <p className="text-xs text-ink-6">
                {analise.cidades_fora.map((c) => `${c.cidade} (${num(c.n)})`).join(' · ')}
              </p>
              <label className="flex items-center gap-2 text-xs text-ink-6 mt-2 cursor-pointer">
                <input type="checkbox" checked={incluirFora} onChange={(e) => setIncluirFora(e.target.checked)} />
                Importar mesmo assim (as placas ficam nesta unidade). Se a cidade é da unidade, o certo é adicioná-la em Cobertura antes.
              </label>
            </div>
          )}

          {analise.postos.length > 0 && (
            <div className="mb-4">
              <p className="text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Postos mais frequentes na planilha</p>
              <ul className="text-xs text-ink-6 grid md:grid-cols-2 gap-x-6 gap-y-0.5">
                {analise.postos.map((p) => (
                  <li key={p.posto} className="flex justify-between gap-3">
                    <span className="truncate">{p.posto}</span>
                    <span className="shrink-0 tabular-nums">
                      {num(p.n)} {p.nosso && <span className="badge bg-emerald-500/15 text-emerald-300 border-emerald-500/30 ml-1">nosso</span>}
                    </span>
                  </li>
                ))}
              </ul>
              {!analise.postos.some((p) => p.nosso) && (
                <p className="text-xs text-amber-300 mt-1">Nenhum posto da planilha é reconhecido como nosso — confira a palavra-chave do posto em Configurar unidade.</p>
              )}
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3 pt-3 border-t border-line">
            {!confirmando ? (
              <button onClick={() => setConfirmando(true)} disabled={entrariam === 0} className={botao}>
                <Upload size={15} /> Importar {num(entrariam)} placas em {nomeUnidade}
              </button>
            ) : (
              <>
                <button onClick={importar} disabled={importando} className="flex items-center gap-1.5 bg-emerald-500 text-[#04120a] text-sm font-bold px-4 py-2 rounded-xl disabled:opacity-60">
                  <Check size={15} /> {importando ? 'Gravando…' : 'Confirmar: gravar na base'}
                </button>
                <button onClick={() => setConfirmando(false)} disabled={importando} className="px-3 py-2 rounded-xl border border-line text-sm text-ink-6 hover:bg-white/5">Voltar</button>
              </>
            )}
            <span className="text-xs text-ink-4">Placa que já existe é atualizada (data só avança; posto só com data mais nova). Nunca duplica.</span>
          </div>
        </div>
      )}

      {resultado && (
        <div className="card p-5 border-emerald-500/40">
          <h2 className="text-sm font-extrabold text-emerald-300 mb-2 flex items-center gap-2"><Check size={16} /> Importação concluída</h2>
          <p className="text-sm text-ink-6">
            <b className="text-ink">{num(resultado.criados)}</b> placas novas · <b className="text-ink">{num(resultado.atualizados)}</b> atualizadas ·{' '}
            <b className="text-ink">{num(resultado.sem_data)}</b> sem data (fora da fila) ·{' '}
            <b className="text-ink">{num(resultado.fora_cobertura)}</b> fora da cobertura {resultado.fora_cobertura_incluidas ? '(incluídas)' : '(não entraram)'} ·{' '}
            <b className="text-ink">{num(resultado.ignoradas)}</b> ignoradas.
          </p>
          <p className="text-xs text-ink-4 mt-1">A fila da unidade já reflete a carga. A conferência automática roda no dia 1º; se quiser, peça uma rodada agora.</p>
        </div>
      )}

      <div className="card overflow-hidden">
        <div className="px-5 py-3 border-b border-line text-sm font-extrabold text-ink">Importações anteriores</div>
        {historico.length === 0 ? (
          <p className="px-5 py-4 text-sm text-ink-4">Nenhuma importação pela tela ainda (as cargas de agosto e setembro foram por migration).</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-2">Quando</th>
                <th className="px-3 py-2">Unidade</th>
                <th className="px-3 py-2">Quem</th>
                <th className="px-3 py-2">Rótulo</th>
                <th className="px-3 py-2 text-right">Linhas</th>
                <th className="px-3 py-2 text-right">Novas</th>
                <th className="px-3 py-2 text-right">Atualizadas</th>
                <th className="px-3 py-2 text-right">Sem data</th>
                <th className="px-5 py-2 text-right">Fora</th>
              </tr>
            </thead>
            <tbody>
              {historico.map((h) => (
                <tr key={h.id} className="border-b border-line last:border-0">
                  <td className="px-5 py-2 text-ink-6 whitespace-nowrap">{fmtDataHora(h.importado_em)}</td>
                  <td className="px-3 py-2 text-ink">{h.unidade}</td>
                  <td className="px-3 py-2 text-ink-6">{h.por ?? '—'}</td>
                  <td className="px-3 py-2 text-ink-6 max-w-56 truncate">{h.rotulo ?? '—'}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(h.linhas)}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-emerald-300">{num(h.criados)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(h.atualizados)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(h.sem_data)}</td>
                  <td className="px-5 py-2 text-right tabular-nums">{num(h.fora_cobertura)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

function Numero({ rotulo, valor, cor, ajuda }: { rotulo: string; valor: number; cor?: string; ajuda?: string }) {
  return (
    <div className="rounded-xl border border-line bg-card/60 px-3 py-2.5">
      <div className={`text-xl font-extrabold tabular-nums ${cor ?? 'text-ink'}`}>{num(valor)}</div>
      <div className="text-[11px] text-ink-4 leading-tight">{rotulo}</div>
      {ajuda && <div className="text-[10px] text-ink-4/80 leading-tight mt-0.5">{ajuda}</div>}
    </div>
  )
}
