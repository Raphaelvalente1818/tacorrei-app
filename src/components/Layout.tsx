import { NavLink, Outlet } from 'react-router-dom'
import { LayoutDashboard, Phone, CalendarClock, LogOut, KeyRound, Shield, Building2 } from 'lucide-react'
import { useAuth } from '../lib/AuthContext'

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/leads', label: 'Leads & Ligações', icon: Phone, end: false },
  { to: '/agenda', label: 'Agenda de aferições', icon: CalendarClock, end: false },
]

export default function Layout() {
  const { membro, user, signOut, unidades, unidadeAtiva, setUnidadeAtiva } = useAuth()
  const isAdmin = membro?.papel === 'admin'

  return (
    <div className="min-h-screen flex bg-bg">
      <aside className="w-60 shrink-0 border-r border-line bg-card flex flex-col">
        <div className="px-5 py-5 border-b border-line">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-brand text-white flex items-center justify-center font-extrabold">
              T
            </div>
            <div>
              <div className="text-sm font-extrabold text-ink leading-tight">Lacre Tacógrafos</div>
              <div className="text-[11px] text-ink-4">Painel interno</div>
            </div>
          </div>
        </div>

        {isAdmin && (
          <div className="px-3 pt-4">
            <label className="block text-[10px] font-bold uppercase tracking-wide text-ink-4 mb-1 px-1">
              Unidade
            </label>
            <div className="relative">
              <Building2
                size={15}
                className="absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-4 pointer-events-none"
              />
              <select
                value={unidadeAtiva ?? ''}
                onChange={(e) => setUnidadeAtiva(e.target.value || null)}
                className="w-full pl-8 pr-3 py-2 border border-line rounded-xl text-sm font-semibold text-ink bg-card focus-ring outline-none appearance-none"
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
              className={({ isActive }) =>
                `flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                  isActive
                    ? 'bg-blue-50 text-brand-d'
                    : 'text-ink-6 hover:bg-slate-50'
                }`
              }
            >
              <item.icon size={17} strokeWidth={2.2} />
              {item.label}
            </NavLink>
          ))}

          {isAdmin && (
            <NavLink
              to="/admin"
              className={({ isActive }) =>
                `flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                  isActive
                    ? 'bg-blue-50 text-brand-d'
                    : 'text-ink-6 hover:bg-slate-50'
                }`
              }
            >
              <Shield size={17} strokeWidth={2.2} />
              Admin
            </NavLink>
          )}
        </nav>

        <div className="px-3 py-4 border-t border-line">
          <div className="px-3 py-2 mb-2">
            <div className="text-xs font-bold text-ink truncate">
              {membro?.nome ?? user?.email}
            </div>
            <div className="text-[11px] text-ink-4">{membro?.papel ?? 'operador'}</div>
          </div>
          <NavLink
            to="/trocar-senha"
            className={({ isActive }) =>
              `w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-sm font-semibold transition-colors ${
                isActive ? 'bg-blue-50 text-brand-d' : 'text-ink-6 hover:bg-slate-50'
              }`
            }
          >
            <KeyRound size={16} />
            Trocar senha
          </NavLink>
          <button
            onClick={() => signOut()}
            className="w-full flex items-center gap-2.5 px-3 py-2 rounded-xl text-sm font-semibold text-ink-6 hover:bg-slate-50 transition-colors"
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
