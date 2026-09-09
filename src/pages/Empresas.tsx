import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Building2, ChevronLeft, ChevronRight, CheckCircle2, MessageCircle, Pencil, Phone, Plus, Truck,
  Upload, X,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useFiltroUnidade } from '../lib/AuthContext'
import EmpresaModal, { type EmpresaEditavel } from '../components/EmpresaModal'
import VeiculosEmpresaModal from '../components/VeiculosEmpresaModal'
import ImportarEmpresasModal from '../components/ImportarEmpresasModal'
import ContatoEmpresaModal from '../components/ContatoEmpresaModal'
import FrotaModal from '../components/FrotaModal'

// ── Empresas (frotas) ────────────────────────────────────────────────────────
// A tela abriga DUAS naturezas, e é `situacao` que as separa:
//
//   contrato  → o oposto do lead. Não se prospecta: já é cliente, já manda os
//               carros. O trabalho é AVISAR quais veículos vencem no mês
//               seguinte. Sem funil, sem taxa de conversão, sem "abordar".
//   prospecto → frota que ainda afere no concorrente. Os caminhões continuam
//               na fila de Leads & Ligações, mas a conversa que resolve é com
//               o gestor da frota — e é aqui que ela é registrada.
//
// Dentro de `prospecto` a `classe` (vinda do banco) diz onde gastar o dia:
//
//   mista     → já temos pelo menos um caminhão desta empresa. É o pé na
//               porta: a operadora liga citando um caminhão que já vem aqui.
//   virgem    → tem posto conhecido, nenhum nosso.
//   sem_dados → nenhum veículo com posto de aferição. Provavelmente não tem
//               tacógrafo; não é fila, é ruído. Fica escondida por padrão.

type ClasseEmpresa = 'contrato' | 'mista' | 'virgem' | 'sem_dados'

type EmpresaPainel = {
  id: string
  nome: string
  cnpj: string | null
  contato: string | null
  telefone: string | null
  unidade_id: string
  situacao: 'contrato' | 'prospecto'
  classe: ClasseEmpresa
  veiculos: number
  nossos: number
  a_conquistar: number
  vencendo: number
  vencidos: number
  janela: number
  risco: number
  avisada_em: string | null
  ultima_abordagem: string | null
}

type Veiculo = { id: string; placa: string | null; modelo: string | null; vence: string }

const UNIDADE_SAO_BERNARDO = '265f0c74-123e-4886-9683-b70793c30b61'

const MARCA_POR_UNIDADE: Record<string, { marca: string; endereco: string }> = {
  [UNIDADE_SAO_BERNARDO]: {
    marca: 'Tacorrei Tacógrafos',
    endereco: 'Rua dos Feltrins, 1300, bairro Demarchi, São Bernardo/SP',
  },
}
const MARCA_PADRAO = {
  marca: 'Lacre Tacógrafos',
  endereco: 'Av. dos Estados, 7050, Santo André/SP',
}

const MESES_PT = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
]

const SELO_CLASSE: Record<ClasseEmpresa, { texto: string; classe: string; ajuda: string } | null> = {
  contrato: null,
  mista: {
    texto: 'Pé na porta',
    classe: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
    ajuda: 'Já temos pelo menos um caminhão desta empresa',
  },
  virgem: {
    texto: 'A conquistar',
    classe: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
    ajuda: 'Nenhum caminhão desta empresa afere conosco',
  },
  sem_dados: {
    texto: 'Sem dados',
    classe: 'bg-slate-500/15 text-slate-400 border-slate-500/30',
    ajuda: 'Nenhum veículo com posto de aferição — provavelmente não tem tacógrafo',
  },
}

function primeiroDoMes(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

function rotuloCompetencia(iso: string): string {
  const [a, m] = iso.split('-')
  return `${MESES_PT[Number(m) - 1]}/${a}`
}

function fmtDia(iso: string): string {
  const [a, m, d] = iso.slice(0, 10).split('-')
  return `${d}/${m}/${a}`
}

// "Em risco" é caminhão nosso prestes a vencer numa empresa que NÃO tem contrato —
// é o que pode vazar para o concorrente. Na frota com contrato o caminhão vencendo
// é o aviso mensal, que já tem coluna própria; contar como risco jogava as 4
// empresas com contrato para o topo da fila e inflava o total do cabeçalho.
function riscoReal(e: EmpresaPainel): number {
  return e.classe === 'contrato' ? 0 : Number(e.risco ?? 0)
}

function diasDesde(iso: string | null): number | null {
  if (!iso) return null
  const ms = Date.now() - new Date(iso).getTime()
  return Math.floor(ms / 86400000)
}

function numeroWhatsapp(tel: string | null): string | null {
  if (!tel) return null
  const d = tel.replace(/\D/g, '')
  if (d.length < 10) return null
  return d.startsWith('55') ? d : '55' + d
}

function saudacao(): string {
  const h = new Date().getHours()
  if (h < 12) return 'Bom dia'
  if (h < 18) return 'Boa tarde'
  return 'Boa noite'
}

// A relação. Mesma estrutura da mensagem individual — quem fala, o fato, o convite —
// só que o fato aqui é uma lista. Sem promessa de horário: é ordem de chegada.
function montarAviso(
  empresa: EmpresaPainel,
  veiculos: Veiculo[],
  competencia: string,
  atendente?: string | null
): string {
  const { marca, endereco } = MARCA_POR_UNIDADE[empresa.unidade_id] ?? MARCA_PADRAO
  const quem = atendente?.trim().split(/\s+/)[0]
  const eu = quem ? `Aqui é ${quem.slice(-1).toLowerCase() === 'a' ? 'a' : 'o'} ${quem}, da ${marca}` : `Aqui é da ${marca}`
  const lista = veiculos
    .map((v) => `• ${v.placa ?? '(sem placa)'} — vence ${fmtDia(v.vence)}`)
    .join('\n')

  return `${saudacao()}! ${eu}
Posto de ensaio credenciado pelo Inmetro

Segue a relação dos veículos da ${empresa.nome} com o certificado do tacógrafo vencendo em ${rotuloCompetencia(competencia)}:

${lista}

Atendemos por ordem de chegada e cada veículo já sai com tudo em dia. Se preferirem trazer todos juntos, é só combinar.

Estou à disposição.
Estamos na ${endereco}`
}

export default function Empresas() {
  const { membro } = useAuth()
  const filtroUnidade = useFiltroUnidade()

  // O padrão é o mês QUE VEM — é o que se avisa. As setas andam no calendário
  // para quem quiser conferir o mês passado ou adiantar o seguinte.
  const [competencia, setCompetencia] = useState(() => {
    const d = new Date()
    d.setMonth(d.getMonth() + 1)
    return primeiroDoMes(d)
  })
  const [empresas, setEmpresas] = useState<EmpresaPainel[]>([])
  // Com 600 empresas, as naturezas numa lista só viram bagunça: quem tem
  // contrato espera aviso mensal, quem é mista espera ligação hoje.
  const [aba, setAba] = useState<'todas' | ClasseEmpresa>('todas')
  const [loading, setLoading] = useState(true)
  const [aberta, setAberta] = useState<EmpresaPainel | null>(null)
  const [veiculos, setVeiculos] = useState<Veiculo[]>([])
  const [mensagem, setMensagem] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [alerta, setAlerta] = useState<string | null>(null)
  // null = fechado · objeto vazio = cadastrando · objeto com id = editando
  const [editando, setEditando] = useState<EmpresaEditavel | null>(null)
  const [gerindoVeiculos, setGerindoVeiculos] = useState<{ id: string; nome: string } | null>(null)
  // Ver a frota é outra coisa que cadastrar placas: consulta, não entrada.
  const [vendoFrota, setVendoFrota] = useState<{ id: string; nome: string } | null>(null)
  const [contatando, setContatando] = useState<EmpresaPainel | null>(null)
  const [importando, setImportando] = useState(false)

  const carregar = useCallback(async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc('empresas_painel', {
      p_unidade: filtroUnidade,
      p_competencia: competencia,
    })
    setLoading(false)
    if (error) return
    setEmpresas((data as EmpresaPainel[]) ?? [])
  }, [filtroUnidade, competencia])

  useEffect(() => {
    carregar()
  }, [carregar])

  function andarMes(passo: number) {
    const [a, m] = competencia.split('-').map(Number)
    const d = new Date(a, m - 1 + passo, 1)
    setCompetencia(primeiroDoMes(d))
  }

  async function abrir(empresa: EmpresaPainel) {
    setAlerta(null)
    const { data, error } = await supabase.rpc('veiculos_da_empresa', {
      p_empresa: empresa.id,
      p_competencia: competencia,
    })
    if (error) {
      setAlerta(error.message)
      return
    }
    const lista = (data as Veiculo[]) ?? []
    setVeiculos(lista)
    setMensagem(montarAviso(empresa, lista, competencia, membro?.nome))
    setAberta(empresa)
  }

  // Grava o aviso ANTES de abrir o WhatsApp: o índice único no banco é o que
  // garante um aviso por empresa por mês. Se gravasse depois, dois cliques
  // seguidos mandariam a relação duas vezes.
  async function enviar() {
    if (!aberta) return
    setSalvando(true)
    const { error } = await supabase.rpc('registrar_aviso_empresa', {
      p_empresa: aberta.id,
      p_competencia: competencia,
      p_mensagem: mensagem,
    })
    setSalvando(false)
    if (error) {
      setAlerta(error.message)
      return
    }
    const num = numeroWhatsapp(aberta.telefone)
    if (num) {
      window.open(`https://wa.me/${num}?text=${encodeURIComponent(mensagem)}`, '_blank')
    } else {
      setAlerta('Aviso registrado, mas esta empresa não tem telefone válido no cadastro — envie por outro canal.')
    }
    setAberta(null)
    carregar()
  }

  // A lista mostrada depende do filtro; os totais falam sempre da lista mostrada,
  // senão o número no topo não bate com as linhas embaixo.
  //
  // A ordem é a fila de trabalho, e muda com a aba:
  //   contrato → por vencimento do mês, que é o que dispara o aviso.
  //   demais   → pela oportunidade da janela de 90 dias (caminhão do concorrente
  //              prestes a vencer) somada ao que está em risco de vazar, e o
  //              desempate é a empresa há mais tempo sem contato.
  // "Sem dados" fica fora de "Todas": são empresas sem nenhum veículo com posto,
  // que quase certamente não têm tacógrafo. Aparecem só na aba delas.
  const visiveis = useMemo(() => {
    const base =
      aba === 'todas'
        ? empresas.filter((e) => e.classe !== 'sem_dados')
        : empresas.filter((e) => e.classe === aba)

    const ordenada = [...base]
    if (aba === 'contrato') {
      ordenada.sort((a, b) => Number(b.vencendo) - Number(a.vencendo) || a.nome.localeCompare(b.nome))
    } else {
      ordenada.sort((a, b) => {
        const pa = Number(a.janela) + riscoReal(a) * 2
        const pb = Number(b.janela) + riscoReal(b) * 2
        if (pa !== pb) return pb - pa
        const da = diasDesde(a.ultima_abordagem)
        const db = diasDesde(b.ultima_abordagem)
        // Nunca abordada vem antes de qualquer uma já abordada.
        if (da === null && db !== null) return -1
        if (db === null && da !== null) return 1
        if (da !== null && db !== null && da !== db) return db - da
        return a.nome.localeCompare(b.nome)
      })
    }
    return ordenada
  }, [empresas, aba])

  const totais = useMemo(
    () => ({
      empresas: visiveis.length,
      veiculos: visiveis.reduce((s, e) => s + Number(e.veiculos ?? 0), 0),
      vencendo: visiveis.reduce((s, e) => s + Number(e.vencendo ?? 0), 0),
      janela: visiveis.reduce((s, e) => s + Number(e.janela ?? 0), 0),
      risco: visiveis.reduce((s, e) => s + riscoReal(e), 0),
      // "A avisar" é só de quem tem contrato. Empresa a conquistar não recebe
      // relação mensal — contá-la aqui faria a operadora procurar um botão que
      // não existe para ela.
      pendentes: visiveis.filter(
        (e) => e.situacao === 'contrato' && Number(e.vencendo ?? 0) > 0 && !e.avisada_em
      ).length,
    }),
    [visiveis]
  )

  const contagem = useMemo(
    () => ({
      todas: empresas.filter((e) => e.classe !== 'sem_dados').length,
      mista: empresas.filter((e) => e.classe === 'mista').length,
      virgem: empresas.filter((e) => e.classe === 'virgem').length,
      contrato: empresas.filter((e) => e.classe === 'contrato').length,
      sem_dados: empresas.filter((e) => e.classe === 'sem_dados').length,
    }),
    [empresas]
  )

  return (
    <div>
      <div className="flex items-center justify-between mb-6 gap-4">
        <div>
          <h1 className="text-xl font-extrabold text-ink">Empresas</h1>
          <p className="text-sm text-ink-4">
            Frotas <b className="text-ink-6">com contrato</b> recebem o aviso mensal. Nas demais, a
            ligação é com o gestor e vale para a frota inteira.
          </p>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <button
            onClick={() => setImportando(true)}
            className="flex items-center gap-1.5 border border-line bg-card text-ink-6 text-sm font-bold px-4 py-2.5 rounded-xl hover:bg-white/5 transition-colors"
            title="Colar a planilha inteira, com empresas e veículos de uma vez"
          >
            <Upload size={16} /> Importar planilha
          </button>
          <button
            onClick={() => setEditando({ nome: '', cnpj: null, contato: null, telefone: null })}
            className="flex items-center gap-1.5 bg-brand text-white text-sm font-bold px-4 py-2.5 rounded-xl hover:bg-brand-d transition-colors"
          >
            <Plus size={16} /> Nova empresa
          </button>
        </div>
      </div>

      <div className="card p-4 mb-6 flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <button
            onClick={() => andarMes(-1)}
            className="p-2 rounded-lg border border-line text-ink-6 hover:bg-white/5"
            aria-label="Mês anterior"
          >
            <ChevronLeft size={16} />
          </button>
          <span className="text-sm font-extrabold text-ink min-w-40 text-center capitalize">
            {rotuloCompetencia(competencia)}
          </span>
          <button
            onClick={() => andarMes(1)}
            className="p-2 rounded-lg border border-line text-ink-6 hover:bg-white/5"
            aria-label="Próximo mês"
          >
            <ChevronRight size={16} />
          </button>
        </div>

        <div className="flex flex-wrap items-center gap-5 text-sm">
          <span className="text-ink-6">
            <b className="text-ink">{totais.empresas}</b> empresas
          </span>
          <span className="text-ink-6">
            <b className="text-ink">{totais.veiculos}</b> veículos
          </span>
          <span className="text-ink-6">
            <b className="text-lucro">{totais.vencendo}</b> vencendo no mês
          </span>
          <span className="text-ink-6" title="Caminhões do concorrente que vencem nos próximos 90 dias">
            <b className="text-amber-400">{totais.janela}</b> na janela
          </span>
          <span className="text-ink-6" title="Caminhões nossos vencendo ou vencidos há pouco — risco de vazar">
            <b className={totais.risco ? 'text-rose-400' : 'text-ink'}>{totais.risco}</b> em risco
          </span>
          <span className="text-ink-6">
            <b className={totais.pendentes ? 'text-amber-400' : 'text-ink'}>{totais.pendentes}</b> a avisar
          </span>
        </div>
      </div>

      {/* O filtro só aparece quando há empresa cadastrada — numa tela vazia ele
          seria botões que não fazem nada. */}
      {empresas.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-4">
          {([
            { v: 'todas' as const, t: 'Todas', n: contagem.todas, ajuda: 'Tudo, menos as sem dados' },
            { v: 'mista' as const, t: 'Pé na porta', n: contagem.mista, ajuda: 'Já temos ao menos um caminhão dessas empresas' },
            { v: 'virgem' as const, t: 'A conquistar', n: contagem.virgem, ajuda: 'Nenhum caminhão conosco ainda' },
            { v: 'contrato' as const, t: 'Com contrato', n: contagem.contrato, ajuda: 'Recebem o aviso mensal' },
            { v: 'sem_dados' as const, t: 'Sem dados', n: contagem.sem_dados, ajuda: 'Nenhum veículo com posto — provavelmente sem tacógrafo' },
          ]).map((f) => (
            <button
              key={f.v}
              onClick={() => setAba(f.v)}
              title={f.ajuda}
              className={`px-3.5 py-1.5 rounded-xl text-sm font-bold border transition-colors ${
                aba === f.v
                  ? 'border-brand bg-brand/15 text-ink'
                  : 'border-line text-ink-6 hover:bg-white/5'
              }`}
            >
              {f.t} <span className="text-ink-4 font-semibold">{f.n}</span>
            </button>
          ))}
        </div>
      )}

      <div className="card overflow-hidden">
        {loading ? (
          <p className="p-6 text-sm text-ink-4">Carregando…</p>
        ) : empresas.length === 0 ? (
          <div className="p-8 text-center">
            <Building2 size={28} className="mx-auto text-ink-4 mb-3" />
            <p className="text-sm font-bold text-ink mb-1">Nenhuma empresa cadastrada ainda</p>
            <p className="text-xs text-ink-4">
              Cadastre uma pelo botão acima, ou importe a base de contratos — cada linha precisa de
              CNPJ, nome, telefone, placa e data da última aferição.
            </p>
          </div>
        ) : visiveis.length === 0 ? (
          <div className="p-8 text-center">
            <Building2 size={28} className="mx-auto text-ink-4 mb-3" />
            <p className="text-sm font-bold text-ink mb-1">Nenhuma empresa nesta lista</p>
            <p className="text-xs text-ink-4">
              A relação de uma empresa se muda no lápis, ao lado do nome.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                  <th className="px-5 py-3">Empresa</th>
                  <th className="px-5 py-3">Contato</th>
                  <th className="px-5 py-3 text-right">Veículos</th>
                  <th className="px-5 py-3 text-right">Vencendo</th>
                  <th className="px-5 py-3 text-right" title="Caminhão do concorrente vencendo em até 90 dias · em risco: caminhão nosso vencendo">
                    Janela 90d
                  </th>
                  <th className="px-5 py-3">Último contato</th>
                  <th className="px-5 py-3">Ação</th>
                </tr>
              </thead>
              <tbody>
                {visiveis.map((e) => {
                  const selo = SELO_CLASSE[e.classe]
                  const dias = diasDesde(e.ultima_abordagem)
                  return (
                    <tr key={e.id} className="border-b border-line last:border-0 hover:bg-white/5">
                      <td className="px-5 py-3">
                        <span className="font-semibold text-ink inline-flex items-center gap-1.5">
                          {e.nome}
                          {/* O selo diz onde gastar o dia: pé na porta antes de virgem. */}
                          {selo && (
                            <span className={`badge ${selo.classe}`} title={selo.ajuda}>
                              {selo.texto}
                            </span>
                          )}
                          <button
                            onClick={() =>
                              setEditando({
                                id: e.id, nome: e.nome, cnpj: e.cnpj,
                                contato: e.contato, telefone: e.telefone,
                                situacao: e.situacao, unidade_id: e.unidade_id,
                              })
                            }
                            className="text-ink-4 hover:text-brand"
                            title="Editar cadastro"
                          >
                            <Pencil size={13} />
                          </button>
                        </span>
                        {e.cnpj && <span className="block text-xs text-ink-4">{e.cnpj}</span>}
                      </td>
                      <td className="px-5 py-3 text-ink-6">
                        {e.contato ?? '—'}
                        {e.telefone && <span className="block text-xs text-ink-4">{e.telefone}</span>}
                      </td>
                      {/* O número abre a FROTA (ver e anotar placa a placa). O "+"
                          ao lado é que abre a colagem — antes o número abria a
                          colagem, o que servia para cadastrar e não para consultar. */}
                      <td className="px-5 py-3 text-right tabular-nums">
                        <span className="inline-flex items-center gap-2 justify-end">
                          <button
                            onClick={() => setVendoFrota({ id: e.id, nome: e.nome })}
                            className="text-ink-6 hover:text-brand hover:underline font-bold"
                            title="Ver a frota, com vencimento e observação de cada placa"
                          >
                            {e.veiculos}
                          </button>
                          <button
                            onClick={() => setGerindoVeiculos({ id: e.id, nome: e.nome })}
                            className="text-ink-4 hover:text-brand"
                            title="Adicionar ou vincular placas nesta empresa"
                          >
                            <Plus size={14} />
                          </button>
                        </span>
                        {Number(e.nossos) > 0 && (
                          <span className="block text-xs text-emerald-400" title="Caminhões que já aferem conosco">
                            {e.nossos} {Number(e.nossos) === 1 ? 'nosso' : 'nossos'}
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums">
                        <span className={Number(e.vencendo) > 0 ? 'font-extrabold text-lucro' : 'text-ink-4'}>
                          {e.vencendo}
                        </span>
                      </td>
                      <td className="px-5 py-3 text-right tabular-nums">
                        <span className={Number(e.janela) > 0 ? 'font-extrabold text-amber-400' : 'text-ink-4'}>
                          {e.janela}
                        </span>
                        {riscoReal(e) > 0 && (
                          <span className="block text-xs text-rose-400" title="Caminhões nossos vencendo — risco de vazar para o concorrente">
                            {e.risco} em risco
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-3 text-xs">
                        {/* Conta ligação e WhatsApp. Antes só olhava WhatsApp, e a
                            empresa para quem ela tinha ligado três vezes aparecia
                            como nunca abordada. */}
                        {dias === null ? (
                          <span className="text-ink-4">nunca</span>
                        ) : (
                          <span className={dias > 60 ? 'text-amber-300' : 'text-ink-6'}>
                            {dias === 0 ? 'hoje' : dias === 1 ? 'ontem' : `há ${dias} dias`}
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-3">
                        {e.classe === 'contrato' ? (
                          e.avisada_em ? (
                            <span className="inline-flex items-center gap-1.5 text-xs font-bold text-emerald-400">
                              <CheckCircle2 size={14} />
                              Avisada em {new Date(e.avisada_em).toLocaleDateString('pt-BR')}
                            </span>
                          ) : Number(e.vencendo) > 0 ? (
                            <button
                              onClick={() => abrir(e)}
                              className="inline-flex items-center gap-1.5 bg-lucro text-white text-xs font-bold px-3 py-1.5 rounded-lg hover:opacity-90"
                            >
                              <MessageCircle size={14} /> Ver relação
                            </button>
                          ) : (
                            <span className="text-xs text-ink-4">nada a avisar</span>
                          )
                        ) : (
                          <button
                            onClick={() => setContatando(e)}
                            className="inline-flex items-center gap-1.5 border border-line text-ink-6 text-xs font-bold px-3 py-1.5 rounded-lg hover:bg-white/5 hover:text-brand"
                            title="Registrar a ligação com o gestor da frota — vale para as placas em aberto"
                          >
                            <Phone size={14} /> Registrar contato
                          </button>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {alerta && (
        <p className="mt-4 text-sm text-amber-300 bg-amber-500/10 border border-amber-500/30 rounded-xl px-4 py-3">
          {alerta}
        </p>
      )}

      {importando && (
        <ImportarEmpresasModal
          onClose={() => setImportando(false)}
          onSaved={carregar}
        />
      )}

      {contatando && (
        <ContatoEmpresaModal
          empresa={contatando}
          onClose={() => setContatando(null)}
          onSaved={carregar}
        />
      )}

      {gerindoVeiculos && (
        <VeiculosEmpresaModal
          empresaId={gerindoVeiculos.id}
          empresaNome={gerindoVeiculos.nome}
          onClose={() => setGerindoVeiculos(null)}
          onSaved={carregar}
        />
      )}

      {vendoFrota && (
        <FrotaModal
          empresaId={vendoFrota.id}
          empresaNome={vendoFrota.nome}
          onClose={() => setVendoFrota(null)}
          // Dar baixa muda "vencendo no mês" e "a avisar" na tela de trás.
          onMudou={carregar}
        />
      )}

      {editando && (
        <EmpresaModal
          empresa={editando.id ? editando : null}
          onClose={() => setEditando(null)}
          onSaved={(salva) => {
            setEditando(null)
            carregar()
            // Cadastrou agora: emenda direto na segunda fase, que é colar as placas.
            if (salva) setGerindoVeiculos(salva)
          }}
        />
      )}

      {aberta && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
          <div className="card w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-1">
              <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
                <Truck size={18} className="text-lucro" />
                {aberta.nome}
              </h2>
              <button onClick={() => setAberta(null)} className="text-ink-4 hover:text-ink">
                <X size={18} />
              </button>
            </div>
            <p className="text-xs text-ink-4 mb-4">
              {veiculos.length} veículo{veiculos.length === 1 ? '' : 's'} vencendo em{' '}
              <span className="capitalize">{rotuloCompetencia(competencia)}</span>. O aviso fica
              registrado e não pode ser repetido neste mês.
            </p>

            <textarea
              value={mensagem}
              onChange={(e) => setMensagem(e.target.value)}
              rows={16}
              className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none resize-none font-mono leading-relaxed"
            />

            <button
              onClick={enviar}
              disabled={salvando}
              className="w-full mt-3 py-2.5 rounded-xl bg-lucro text-white font-bold text-sm hover:opacity-90 disabled:opacity-60"
            >
              {salvando ? 'Registrando…' : 'Registrar aviso e abrir WhatsApp'}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
