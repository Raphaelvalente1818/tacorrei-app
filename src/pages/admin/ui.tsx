// Miúdos compartilhados pelas telas do painel.
export function num(n: number | null | undefined): string {
  return Number(n ?? 0).toLocaleString('pt-BR')
}

export function real(n: number | null | undefined): string {
  if (n === null || n === undefined) return '—'
  return Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

export const chipOn = 'bg-brand text-[#04120a] border-brand'
export const chipOff = 'bg-card text-ink-6 border-line hover:bg-white/5'
export const chip = 'px-3 py-1.5 rounded-full text-xs font-bold border transition-colors'
export const input = 'px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none bg-card'
export const botao = 'flex items-center gap-1.5 bg-brand text-[#04120a] text-sm font-bold px-4 py-2 rounded-xl hover:bg-brand-d transition-colors disabled:opacity-60'
