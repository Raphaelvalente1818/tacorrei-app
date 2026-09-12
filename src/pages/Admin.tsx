import { useState } from 'react'
import {
  BarChart3, Building2, Users, MapPin, Target, Sun, Briefcase, Shield, MessageCircle, Wallet, SlidersHorizontal, Upload, History, Footprints,
} from 'lucide-react'
import { useAuth } from '../lib/AuthContext'
import MetaDoMes from '../components/MetaDoMes'
import MeuDia from './admin/MeuDia'
import Producao from './admin/Producao'
import Unidades from './admin/Unidades'
import Cobertura from './admin/Cobertura'
import Acessos from './admin/Acessos'
import Mensagens from './admin/Mensagens'
import Premio from './admin/Premio'
import ConfigUnidade from './admin/ConfigUnidade'
import Metodo from './admin/Metodo'
import ImportarBase from './admin/ImportarBase'
import Trilha from './admin/Trilha'

// ── Painel ───────────────────────────────────────────────────────────────────
// Redesenho de 11/09 (PRD R3b): gestão e administração eram uma aba só. Agora:
//   Meu dia        — as quatro perguntas da rotina do gestor. Tela inicial.
//   Gestão         — o operacional de UMA unidade: Meta, Produção, Equipe,
//                    Mensagens, Prêmio. O gestor vê a dele; o admin geral escolhe
//                    pelo "Visualizando" do menu (ou pelo seletor aqui, se em "Todas").
//   Administração  — só admin geral: Unidades (painel + configuração), Cobertura,
//                    Método, Acessos (equipe inteira).
// A matriz de quem faz o quê está no PRD, seção 8; o banco aplica de novo.

type Grupo = 'dia' | 'gestao' | 'admin'
type SubGestao = 'meta' | 'producao' | 'equipe' | 'mensagens' | 'premio' | 'registro'
type SubAdmin = 'unidades' | 'configurar' | 'cobertura' | 'metodo' | 'acessos' | 'importar' | 'trilha'

const tabBase = 'flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-sm font-bold border transition-colors'
const tabOn = 'bg-brand text-[#04120a] border-brand'
const tabOff = 'bg-card text-ink-6 border-line hover:bg-white/5'
const subBase = 'flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold border transition-colors'
const subOn = 'bg-white/10 text-ink border-line'
const subOff = 'text-ink-4 border-transparent hover:text-ink-6'

export default function Admin() {
  const { membro, unidades, unidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  const isGestor = membro?.papel === 'admin_unidade'

  const [grupo, setGrupo] = useState<Grupo>('dia')
  const [subGestao, setSubGestao] = useState<SubGestao>('meta')
  const [subAdmin, setSubAdmin] = useState<SubAdmin>('unidades')
  // Admin geral em "Todas as unidades": as telas de uma unidade só precisam de uma.
  const [unidadeEscolhida, setUnidadeEscolhida] = useState<string | null>(null)

  if (!isAdmin && !isGestor) {
    return (
      <div className="card p-6">
        <p className="text-sm text-ink-6">Acesso restrito aos gestores e administradores.</p>
      </div>
    )
  }

  const unidadeId = isAdmin
    ? (unidadeAtiva ?? unidadeEscolhida ?? unidades[0]?.id ?? null)
    : (membro?.unidade_id ?? null)
  const nomeUnidade = unidades.find((u) => u.id === unidadeId)?.nome ?? null
  const precisaEscolher = isAdmin && !unidadeAtiva && unidades.length > 1

  const grupos: { id: Grupo; label: string; icon: typeof Sun }[] = [
    { id: 'dia', label: 'Meu dia', icon: Sun },
    { id: 'gestao', label: 'Gestão', icon: Briefcase },
    ...(isAdmin ? [{ id: 'admin' as Grupo, label: 'Administração', icon: Shield }] : []),
  ]

  const subsGestao: { id: SubGestao; label: string; icon: typeof Target }[] = [
    { id: 'meta', label: 'Meta', icon: Target },
    { id: 'producao', label: 'Produção', icon: BarChart3 },
    { id: 'equipe', label: 'Equipe', icon: Users },
    { id: 'mensagens', label: 'Mensagens', icon: MessageCircle },
    { id: 'premio', label: 'Prêmio', icon: Wallet },
    { id: 'registro', label: 'Registro', icon: History },
  ]

  const subsAdmin: { id: SubAdmin; label: string; icon: typeof Building2 }[] = [
    { id: 'unidades', label: 'Unidades', icon: Building2 },
    { id: 'configurar', label: 'Configurar unidade', icon: SlidersHorizontal },
    { id: 'cobertura', label: 'Cobertura', icon: MapPin },
    { id: 'metodo', label: 'Método', icon: Target },
    { id: 'acessos', label: 'Acessos', icon: Users },
    { id: 'importar', label: 'Importar base', icon: Upload },
    { id: 'trilha', label: 'Trilha', icon: Footprints },
  ]

  // Telas que são de UMA unidade e por isso mostram de qual.
  const porUnidade =
    grupo === 'dia' ||
    (grupo === 'gestao' && subGestao !== 'producao') ||
    (grupo === 'admin' && (subAdmin === 'configurar' || subAdmin === 'importar'))

  return (
    <div>
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-extrabold text-ink">{isAdmin ? 'Gestão e administração' : 'Gestão da unidade'}</h1>
          <p className="text-sm text-ink-4">
            {grupo === 'dia' && 'A rotina de 10 minutos: quatro perguntas, todo dia, antes de qualquer outra coisa.'}
            {grupo === 'gestao' && 'O operacional da unidade: o que a equipe fez, o que vale ponto, como ela fala com o cliente.'}
            {grupo === 'admin' && 'O que é do Aferi+, não da unidade: unidades, território, método e acessos.'}
          </p>
        </div>
        {porUnidade && (
          precisaEscolher ? (
            <select
              value={unidadeId ?? ''}
              onChange={(e) => setUnidadeEscolhida(e.target.value || null)}
              className="px-3 py-2 border border-line rounded-xl text-sm font-bold bg-card focus-ring outline-none"
            >
              {unidades.map((u) => (
                <option key={u.id} value={u.id}>{u.nome}</option>
              ))}
            </select>
          ) : nomeUnidade ? (
            <span className="text-sm text-ink-6 flex items-center gap-1.5"><Building2 size={14} className="text-brand" /> <b className="text-ink">{nomeUnidade}</b></span>
          ) : null
        )}
      </div>

      <div className="flex flex-wrap gap-2 mb-3">
        {grupos.map((g) => (
          <button key={g.id} onClick={() => setGrupo(g.id)} className={`${tabBase} ${grupo === g.id ? tabOn : tabOff}`}>
            <g.icon size={16} /> {g.label}
          </button>
        ))}
      </div>

      {grupo === 'gestao' && (
        <div className="flex flex-wrap gap-1 mb-5">
          {subsGestao.map((s) => (
            <button key={s.id} onClick={() => setSubGestao(s.id)} className={`${subBase} ${subGestao === s.id ? subOn : subOff}`}>
              <s.icon size={13} /> {s.label}
            </button>
          ))}
        </div>
      )}
      {grupo === 'admin' && isAdmin && (
        <div className="flex flex-wrap gap-1 mb-5">
          {subsAdmin.map((s) => (
            <button key={s.id} onClick={() => setSubAdmin(s.id)} className={`${subBase} ${subAdmin === s.id ? subOn : subOff}`}>
              <s.icon size={13} /> {s.label}
            </button>
          ))}
        </div>
      )}
      {grupo === 'dia' && <div className="mb-2" />}

      {!unidadeId && porUnidade ? (
        <div className="card p-6"><p className="text-sm text-ink-6">Nenhuma unidade disponível.</p></div>
      ) : (
        <>
          {grupo === 'dia' && unidadeId && <MeuDia unidadeId={unidadeId} />}

          {grupo === 'gestao' && subGestao === 'meta' && <MetaDoMes unidadeId={unidadeId} />}
          {grupo === 'gestao' && subGestao === 'producao' && <Producao />}
          {grupo === 'gestao' && subGestao === 'equipe' && <Acessos podeTudo={isAdmin} unidadeFixa={unidadeId} />}
          {grupo === 'gestao' && subGestao === 'mensagens' && unidadeId && <Mensagens unidadeId={unidadeId} />}
          {grupo === 'gestao' && subGestao === 'premio' && unidadeId && <Premio unidadeId={unidadeId} />}
          {grupo === 'gestao' && subGestao === 'registro' && unidadeId && <Trilha modo="gestor" unidadeId={unidadeId} />}

          {grupo === 'admin' && isAdmin && subAdmin === 'unidades' && <Unidades podeEditar />}
          {grupo === 'admin' && isAdmin && subAdmin === 'configurar' && unidadeId && <ConfigUnidade unidadeId={unidadeId} />}
          {grupo === 'admin' && isAdmin && subAdmin === 'cobertura' && <Cobertura />}
          {grupo === 'admin' && isAdmin && subAdmin === 'metodo' && <Metodo />}
          {grupo === 'admin' && isAdmin && subAdmin === 'acessos' && <Acessos podeTudo />}
          {grupo === 'admin' && isAdmin && subAdmin === 'importar' && unidadeId && <ImportarBase unidadeId={unidadeId} nomeUnidade={nomeUnidade} />}
          {grupo === 'admin' && isAdmin && subAdmin === 'trilha' && <Trilha modo="admin" unidadeId={unidadeAtiva ?? null} />}
        </>
      )}
    </div>
  )
}
