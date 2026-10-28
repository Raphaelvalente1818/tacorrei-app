import { useEffect } from 'react'

// 28/10 — a Fernanda registrou uma conquista numa aba e o "Meu dia" da outra
// aba continuou com 51 pontos: a tela só carregava ao abrir. Os números que
// mudam com o trabalho dela (pontos, fila, carteira) têm que acompanhar a volta
// para a aba. Dispara quando a janela recebe foco ou a aba volta a ficar visível,
// com uma folga mínima para não bater no banco a cada clique.
export function useRecarregarAoVoltar(carregar: () => void, minimoMs = 15_000) {
  useEffect(() => {
    let ultimo = Date.now()
    const talvez = () => {
      if (document.visibilityState !== 'visible') return
      if (Date.now() - ultimo < minimoMs) return
      ultimo = Date.now()
      carregar()
    }
    window.addEventListener('focus', talvez)
    document.addEventListener('visibilitychange', talvez)
    return () => {
      window.removeEventListener('focus', talvez)
      document.removeEventListener('visibilitychange', talvez)
    }
  }, [carregar, minimoMs])
}
