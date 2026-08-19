import { NavLink, Outlet } from 'react-router-dom'
import { LayoutDashboard, Phone, CalendarClock, LogOut, KeyRound, Shield, Building2 } from 'lucide-react'
import { useAuth } from '../lib/AuthContext'

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/leads', label: 'Leads & Ligações', icon: Phone, end: false },
  { to: '/agenda', label: 'Agenda de aferições', icon: CalendarClock, end: false },
]

const navBase =
  'flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-sm font-semibold transition-colors'
const navActive = 'bg-gradient-to-br from-brand to-brand-d text-[#04120a] shadow-lg shadow-brand/25'
const navIdle = 'text-ink-6 hover:bg-white/5'

const PAPEL_LABEL: Record<string, string> = {
  admin: 'admin',
  admin_unidade: 'admin da unidade',
  operador: 'operador',
}

export default function Layout() {
  const { membro, user, signOut, unidades, unidadeAtiva, setUnidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'
  // O admin de unidade também entra no painel, mas com abas reduzidas
  // e sem o seletor "Visualizando" — ele só tem uma unidade.
  const vePainelAdmin = isAdmin || membro?.papel === 'admin_unidade'

  return (
    <div className="min-h-screen flex bg-bg">
      <aside className="w-60 shrink-0 border-r border-line bg-panel flex flex-col">
        <div className="px-5 py-5">
          <div className="flex items-center gap-2.5">
            <div className="relative shrink-0">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-brand to-brand-d text-[#04120a] flex items-center justify-center text-lg font-extrabold shadow-lg shadow-brand/30">
                A
              </div>
              <span className="absolute -right-1 -top-1 w-[18px] h-[18px] rounded-md bg-panel text-brand text-xs font-black flex items-center justify-center border-2 border-brand leading-none">
                +
              </span>
            </div>
            <div>
              <div className="text-[15px] font-extrabold text-white leading-none">
                Aferi<span className="text-brand">+</span>
              </div>
              <div className="text-[11px] text-ink-4 mt-0.5">Painel interno</div>
            </div>
          </div>
        </div>

        {isAdmin && (
          <div className="px-3 pb-1">
            <label className="block text-[10px] font-bold uppercase tracking-wide text-ink-4 mb-1.5 px-1">
              Visualizando
            </label>
            <div className="relative">
              <Building2
                size={15}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-brand pointer-events-none"
              />
              <select
                value={unidadeAtiva ?? ''}
                onChange={(e) => setUnidadeAtiva(e.target.value || null)}
                className="w-full pl-9 pr-3 py-2.5 border border-line rounded-xl text-sm font-bold text-ink bg-card focus-ring outline-none appearance-none"
              >
                <option value="">Todas as unidades</option>
                {unidades.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nome}
                  </option>
                ))}
              </select>
            </div>
          </div>
        )}

        <nav className="flex-1 px-3 py-4 space-y-1">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) => `${navBase} ${isActive ? navActive : navIdle}`}
            >
              <item.icon size={17} strokeWidth={2.2} />
              {item.label}
            </NavLink>
          ))}

          {vePainelAdmin && (
            <NavLink to="/admin" className={({ isActive }) => `${navBase} ${isActive ? navActive : navIdle}`}>
              <Shield size={17} strokeWidth={2.2} />
              Admin
            </NavLink>
          )}
        </nav>

        <div className="px-3 py-4 border-t border-line">
          <div className="flex items-center gap-2.5 px-2 py-2 mb-2">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-blue to-blue/70 text-white flex items-center justify-center text-xs font-extrabold shrink-0">
              {(membro?.nome ?? user?.email ?? '?').slice(0, 1).toUpperCase()}
            </div>
            <div className="min-w-0">
              <div className="text-xs font-bold text-ink truncate">{membro?.nome ?? user?.email}</div>
              <div className="text-[11px] text-ink-4">{PAPEL_LABEL[membro?.papel ?? 'operador']}</div>
            </div>
          </div>
          <NavLink to="/trocar-senha" className={({ isActive }) => `w-full ${navBase} ${isActive ? navActive : navIdle}`}>
            <KeyRound size={16} />
            Trocar senha
          </NavLink>
          <button
            onClick={() => signOut()}
            className={`w-full ${navBase} ${navIdle}`}
          >
            <LogOut size={16} />
            Sair
          </button>
        </div>
      </aside>

      <main className="flex-1 min-w-0">
        <div className="max-w-6xl mx-auto px-6 py-8">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
