import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Building2, ChevronLeft, ChevronRight, CheckCircle2, MessageCircle, Pencil, Plus, Truck, Upload, X,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth, useFiltroUnidade } from '../lib/AuthContext'
import EmpresaModal, { type EmpresaEditavel } from '../components/EmpresaModal'
import VeiculosEmpresaModal from '../components/VeiculosEmpresaModal'
import ImportarEmpresasModal from '../components/ImportarEmpresasModal'

// ── Empresas com contrato ────────────────────────────────────────────────────
// São o oposto do lead. Não se prospecta: já são clientes, já mandam os carros.
// O trabalho aqui é AVISAR quais veículos vencem no mês seguinte, para a empresa
// mandar os certos — e é por isso que esta tela não tem funil, nem taxa de
// conversão, nem botão de "abordar".
//
// A conta que justifica esta tela: São Bernardo tem ~80 empresas, de 10 a 300
// veículos. Com validade de 2 anos, algo como 125 veículos vencem por mês — mais
// do que a operação de prospecção inteira produziu em um mês. E custa 80
// mensagens mensais, não 30 por dia.

type EmpresaPainel = {
  id: string
  nome: string
  cnpj: string | null
  contato: string | null
  telefone: string | null
  unidade_id: string
  veiculos: number
  vencendo: number
  avisada_em: string | null
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
  const [loading, setLoading] = useState(true)
  const [aberta, setAberta] = useState<EmpresaPainel | null>(null)
  const [veiculos, setVeiculos] = useState<Veiculo[]>([])
  const [mensagem, setMensagem] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [alerta, setAlerta] = useState<string | null>(null)
  // null = fechado · objeto vazio = cadastrando · objeto com id = editando
  const [editando, setEditando] = useState<EmpresaEditavel | null>(null)
  const [gerindoVeiculos, setGerindoVeiculos] = useState<{ id: string; nome: string } | null>(null)
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

  const totais = useMemo(
    () => ({
      empresas: empresas.length,
      veiculos: empresas.reduce((s, e) => s + Number(e.veiculos ?? 0), 0),
      vencendo: empresas.reduce((s, e) => s + Number(e.vencendo ?? 0), 0),
      avisadas: empresas.filter((e) => e.avisada_em).length,
      pendentes: empresas.filter((e) => Number(e.vencendo ?? 0) > 0 && !e.avisada_em).length,
    }),
    [empresas]
  )

  return (
    <div>
      <div className="flex items-center justify-between mb-6 gap-4">
        <div>
          <h1 className="text-xl font-extrabold text-ink">Empresas com contrato</h1>
          <p className="text-sm text-ink-4">
            Aviso mensal dos veículos a vencer — estes clientes não são prospectados.
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
          <span className="text-ink-6">
            <b className={totais.pendentes ? 'text-amber-400' : 'text-ink'}>{totais.pendentes}</b> a avisar
          </span>
        </div>
      </div>

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
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-ink-4 text-xs uppercase font-bold border-b border-line">
                <th className="px-5 py-3">Empresa</th>
                <th className="px-5 py-3">Contato</th>
                <th className="px-5 py-3 text-right">Veículos</th>
                <th className="px-5 py-3 text-right">Vencendo</th>
                <th className="px-5 py-3">Aviso do mês</th>
              </tr>
            </thead>
            <tbody>
              {empresas.map((e) => (
                <tr key={e.id} className="border-b border-line last:border-0 hover:bg-white/5">
                  <td className="px-5 py-3">
                    <span className="font-semibold text-ink inline-flex items-center gap-1.5">
                      {e.nome}
                      <button
                        onClick={() =>
                          setEditando({
                            id: e.id, nome: e.nome, cnpj: e.cnpj,
                            contato: e.contato, telefone: e.telefone, unidade_id: e.unidade_id,
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
                  <td className="px-5 py-3 text-right tabular-nums">
                    <button
                      onClick={() => setGerindoVeiculos({ id: e.id, nome: e.nome })}
                      className="text-ink-6 hover:text-brand hover:underline"
                      title="Adicionar ou vincular placas desta empresa"
                    >
                      {e.veiculos}
                    </button>
                  </td>
                  <td className="px-5 py-3 text-right tabular-nums">
                    <span className={Number(e.vencendo) > 0 ? 'font-extrabold text-lucro' : 'text-ink-4'}>
                      {e.vencendo}
                    </span>
                  </td>
                  <td className="px-5 py-3">
                    {e.avisada_em ? (
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
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
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

      {gerindoVeiculos && (
        <VeiculosEmpresaModal
          empresaId={gerindoVeiculos.id}
          empresaNome={gerindoVeiculos.nome}
          onClose={() => setGerindoVeiculos(null)}
          onSaved={carregar}
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
