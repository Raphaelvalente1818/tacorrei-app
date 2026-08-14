import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider, useAuth } from './lib/AuthContext'
import Layout from './components/Layout'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Leads from './pages/Leads'
import LeadDetail from './pages/LeadDetail'
import Agenda from './pages/Agenda'
import TrocarSenha from './pages/TrocarSenha'
import RedefinirSenha from './pages/RedefinirSenha'

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
        <Route index element={<Dashboard />} />
        <Route path="leads" element={<Leads />} />
        <Route path="leads/:id" element={<LeadDetail />} />
        <Route path="agenda" element={<Agenda />} />
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
