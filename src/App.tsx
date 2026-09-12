import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './lib/AuthContext'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Leads from './pages/Leads'
import Empresas from './pages/Empresas'
import LeadDetail from './pages/LeadDetail'
import Agenda from './pages/Agenda'
import TrocarSenha from './pages/TrocarSenha'
import RedefinirSenha from './pages/RedefinirSenha'
import Admin from './pages/Admin'
import Placar from './pages/Placar'
import MeuDia from './pages/admin/MeuDia'

// A tela inicial depende do papel: a operadora abre no Meu dia dela (0089) —
// as dicas do que fazer hoje; gestor e admin abrem no Dashboard (o Meu dia deles
// está no painel de Gestão).
function Inicio() {
  const { membro } = useAuth()
  if (membro?.papel === 'operador') {
    return (
      <div>
        <div className="mb-5">
          <h1 className="text-xl font-extrabold text-ink">Meu dia</h1>
          <p className="text-sm text-ink-4">Quatro cartões, todo dia de manhã: onde estão os pontos, quem ligar primeiro, o que ainda falta tocar e quem não pode vencer sem um lembrete nosso.</p>
        </div>
        <MeuDia unidadeId={null} modo="operadora" />
      </div>
    )
  }
  return <Dashboard />
}

function PrivateArea() {
  const { session, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-bg">
        <p className="text-sm text-ink-4">Carregando…</p>
      </div>
    )
  }

  if (!session) return <Login />

  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Inicio />} />
        <Route path="leads" element={<Leads />} />
        <Route path="leads/:id" element={<LeadDetail />} />
        <Route path="empresas" element={<Empresas />} />
        <Route path="agenda" element={<Agenda />} />
        <Route path="admin" element={<Admin />} />
        <Route path="placar" element={<Placar />} />
        <Route path="trocar-senha" element={<TrocarSenha />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          {/* Rota pública: destino do link de "Esqueci minha senha" enviado por e-mail. */}
          <Route path="/redefinir-senha" element={<RedefinirSenha />} />
          <Route path="/*" element={<PrivateArea />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}
