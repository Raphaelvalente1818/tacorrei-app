import { useEffect, useState, type ReactNode } from 'react'
import { X, FileText, Copy, Check, MessageCircle, Bookmark } from 'lucide-react'
import { supabase } from '../lib/supabase'

// "Emitir GRU" — a guia é emitida no portal do Inmetro, que tem CAPTCHA e é POST
// (não dá para pré-preencher pela URL). O Aferi+ reúne os dados que a operadora hoje
// cata de duas páginas, diz o que falta, deixa completar o que só está no CRLV
// (CPF/CNPJ, chassi, ano) e abre o portal com os dados na área de transferência.
// Lá, o favorito "Preencher GRU (Aferi+)" (abaixo) lê esse bloco e preenche os campos
// sozinho. A pessoa marca o "não sou robô" e clica em Buscar — isso é sempre ela;
// o favorito NÃO submete o formulário nem toca no CAPTCHA. Toda a lógica de dados
// vem de dados_gru()/salvar_dados_gru(): o documento nunca trafega pelo obter_lead.
// Ao abrir o portal, dados_gru(lead, true) registra "GRU solicitada" no histórico.

type Resumo = {
  documento: string | null
  placa: string | null
  renavam: string | null
  chassi: string | null
  ano_fabricacao: number | null
}
type DadosGru = {
  pronto: boolean
  faltando: string[]
  url: string
  resumo: Resumo
  campos: Record<string, string>
}

// O favorito ("bookmarklet"). Lê o bloco "Rótulo: valor" da área de transferência
// (ou pede para colar), preenche os campos do formulário pelos nomes reais (CakePHP,
// data[Model][campo]) e dispara input/change para o site reagir. Fixa Brasil /
// emplacado no Brasil e deduz CPF×CNPJ pelo tamanho do documento. Rola até o
// "não sou robô" e para ali. String.raw preserva as barras dos regex.
const BOOKMARKLET =
  'javascript:' +
  String.raw`(async()=>{ const map={'cpf/cnpj':'data[CrVeiculoProprietario][nr_identificacao]','placa':'data[CrVeiculo][ds_placa]','renavam':'data[CrVeiculo][ds_renavam]','chassi':'data[CrVeiculo][ds_chassi]','ano':'data[CrVeiculo][dt_ano]'}; let txt=''; try{txt=await navigator.clipboard.readText()}catch(e){} if(!txt||!/placa/i.test(txt)){txt=prompt('Cole aqui o bloco copiado do Aferi+ (Ctrl+V):','')||''} if(!txt)return; const vals={}; txt.split(/\r?\n/).forEach(l=>{const m=l.match(/^\s*([^:]+):\s*(.*?)\s*$/);if(m)vals[m[1].trim().toLowerCase()]=m[2]}); const set=(name,val)=>{const el=document.querySelector('[name="'+name+'"]');if(!el||val==null||val==='')return false;el.value=val;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return true}; set('data[CrVeiculoProprietario][pai_id]','2'); set('data[CrVeiculo][pai_id]','2'); set('data[CrVeiculo][vet_id]','1'); const doc=(vals['cpf/cnpj']||'').replace(/\D/g,''); if(doc.length===11)set('data[CrVeiculoProprietario][tp_pessoa]','1');else if(doc.length===14)set('data[CrVeiculoProprietario][tp_pessoa]','2'); let n=0; if(set(map['cpf/cnpj'],doc))n++; for(const k of ['placa','renavam','chassi','ano']){if(set(map[k],(vals[k]||'').trim()))n++} const cap=document.querySelector('.g-recaptcha,iframe[src*="recaptcha"]'); if(cap)cap.scrollIntoView({behavior:'smooth',block:'center'}); alert('Aferi+: '+n+' campo(s) preenchido(s). Agora marque "Não sou um robô" e clique em Buscar.');})();`

function tipoDocumento(doc: string): string {
  const d = doc.replace(/\D/g, '')
  if (d.length === 11) return 'CPF'
  if (d.length === 14) return 'CNPJ'
  return '—'
}

const boxCls = 'flex items-center justify-between px-3 py-2 border border-line rounded-xl text-sm'

export default function EmitirGruModal({
  leadId,
  placa,
  telefone,
  onClose,
  onSaved,
}: {
  leadId: string
  placa: string | null
  telefone: string | null
  onClose: () => void
  onSaved: () => void
}) {
  const [dados, setDados] = useState<DadosGru | null>(null)
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [salvando, setSalvando] = useState(false)
  const [copiado, setCopiado] = useState<string | null>(null)

  // Só estes três entram no salvar_dados_gru (o resto vem da base).
  const [doc, setDoc] = useState('')
  const [chassi, setChassi] = useState('')
  const [ano, setAno] = useState('')

  function aplicar(d: DadosGru) {
    setDados(d)
    setDoc(d.resumo.documento ?? '')
    setChassi(d.resumo.chassi ?? '')
    setAno(d.resumo.ano_fabricacao ? String(d.resumo.ano_fabricacao) : '')
  }

  async function carregar(registrar: boolean) {
    const { data, error } = await supabase.rpc('dados_gru', { p_lead: leadId, p_registrar: registrar })
    if (error) {
      setErro(error.message)
      return
    }
    aplicar(data as DadosGru)
  }

  useEffect(() => {
    ;(async () => {
      setCarregando(true)
      await carregar(false)
      setCarregando(false)
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [leadId])

  async function salvar() {
    setSalvando(true)
    setErro(null)
    const { data, error } = await supabase.rpc('salvar_dados_gru', {
      p_lead: leadId,
      p_documento: doc.trim() || null,
      p_chassi: chassi.trim() || null,
      p_ano_fabricacao: ano.trim() ? Number(ano.trim()) : null,
    })
    setSalvando(false)
    if (error) {
      setErro(error.message)
      return
    }
    aplicar(data as DadosGru)
    onSaved()
  }

  async function copiar(texto: string, rotulo: string) {
    try {
      await navigator.clipboard.writeText(texto)
      setCopiado(rotulo)
      setTimeout(() => setCopiado((c) => (c === rotulo ? null : c)), 1800)
    } catch {
      setErro('Não consegui copiar automaticamente — selecione e copie à mão.')
    }
  }

  // O bloco copiado é o que o favorito lê: uma linha "Rótulo: valor" por campo.
  function blocoParaColar(d: DadosGru): string {
    const r = d.resumo
    return [
      `CPF/CNPJ: ${r.documento ?? ''}`,
      `Placa: ${d.campos['data[CrVeiculo][ds_placa]'] ?? r.placa ?? ''}`,
      `RENAVAM: ${r.renavam ?? ''}`,
      `Chassi: ${r.chassi ?? ''}`,
      `Ano: ${r.ano_fabricacao ?? ''}`,
    ].join('\n')
  }

  async function abrirInmetro() {
    if (!dados) return
    await copiar(blocoParaColar(dados), 'tudo')
    window.open(dados.url, '_blank', 'noopener')
    await carregar(true) // registra "GRU solicitada" no histórico
    onSaved()
  }

  function pedirFotoCrlv() {
    const fone = (telefone ?? '').replace(/\D/g, '')
    const texto = encodeURIComponent(
      'Olá! Para emitir a guia (GRU) da aferição, você pode me enviar uma foto do CRLV (documento do veículo)? Obrigado!',
    )
    const url = fone ? `https://wa.me/55${fone}?text=${texto}` : `https://wa.me/?text=${texto}`
    window.open(url, '_blank', 'noopener')
  }

  const r = dados?.resumo
  const falta = (nome: string) => (dados?.faltando ?? []).some((f) => f.toLowerCase().startsWith(nome.toLowerCase()))
  const renavamOk = !!r && /^[0-9]{11}$/.test(r.renavam ?? '')

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="card w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-1">
          <h2 className="text-base font-extrabold text-ink flex items-center gap-2">
            <FileText size={18} className="text-brand" /> Emitir GRU{placa ? ` — ${placa}` : ''}
          </h2>
          <button onClick={onClose} className="text-ink-4 hover:text-ink">
            <X size={18} />
          </button>
        </div>
        <p className="text-xs text-ink-4 mb-4">
          A guia é emitida no site do Inmetro (com “não sou robô”). O Aferi+ junta os dados, abre o portal e o
          favorito preenche os campos — você confere, marca o “não sou robô” e emite.
        </p>

        {carregando ? (
          <p className="text-sm text-ink-4">Carregando…</p>
        ) : !dados ? (
          <p className="text-sm text-danger">{erro ?? 'Não foi possível carregar os dados.'}</p>
        ) : (
          <>
            {!dados.pronto && (
              <div className="mb-3 rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
                Faltam {dados.faltando.length}: {dados.faltando.join(', ')}. Complete abaixo (está no CRLV) e salve.
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Tipo de documento</label>
                <div className={boxCls}>
                  <span>{tipoDocumento(doc)}</span>
                  <span className="text-ink-4 text-xs">automático</span>
                </div>
              </div>

              <EditCampo label="CPF / CNPJ do proprietário" hint="Igual ao CRLV" faltando={falta('CPF')}>
                <input
                  value={doc}
                  onChange={(e) => setDoc(e.target.value)}
                  placeholder="só números"
                  className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
                />
              </EditCampo>

              <div>
                <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">Placa</label>
                <div className={boxCls}>
                  <span>{r?.placa ?? '—'}</span>
                  {r?.placa && (
                    <BotaoCopiar
                      ok={copiado === 'placa'}
                      onClick={() => copiar(dados.campos['data[CrVeiculo][ds_placa]'] ?? r.placa ?? '', 'placa')}
                    />
                  )}
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">RENAVAM (11 dígitos)</label>
                <div className={`${boxCls} ${renavamOk ? '' : 'text-danger border-danger/40'}`}>
                  <span>{r?.renavam || '—'}</span>
                  {renavamOk && <BotaoCopiar ok={copiado === 'renavam'} onClick={() => copiar(r?.renavam ?? '', 'renavam')} />}
                </div>
                {!renavamOk && <p className="text-xs text-ink-4 mt-1">Vem da base/importação — corrija por lá se estiver errado.</p>}
              </div>

              <EditCampo label="Chassi (até 23)" hint="Igual ao CRLV" faltando={falta('Chassi')}>
                <input
                  value={chassi}
                  onChange={(e) => setChassi(e.target.value.toUpperCase())}
                  placeholder="—"
                  className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
                />
              </EditCampo>

              <EditCampo label="Ano de fabricação" hint="opcional" faltando={false}>
                <input
                  value={ano}
                  onChange={(e) => setAno(e.target.value.replace(/\D/g, '').slice(0, 4))}
                  placeholder="opcional"
                  inputMode="numeric"
                  className="w-full px-3 py-2 border border-line rounded-xl text-sm focus-ring outline-none"
                />
              </EditCampo>
            </div>

            <div className="flex flex-wrap gap-2 mt-4">
              <button
                onClick={pedirFotoCrlv}
                className="flex items-center gap-1.5 border border-line bg-card text-ink-6 text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-white/5 transition-colors"
              >
                <MessageCircle size={16} /> Pedir foto do CRLV
              </button>
              <button
                onClick={salvar}
                disabled={salvando}
                className="flex items-center gap-1.5 border border-line bg-card text-ink text-sm font-bold px-3.5 py-2 rounded-xl hover:bg-white/5 transition-colors disabled:opacity-60"
              >
                {salvando ? 'Salvando…' : 'Salvar'}
              </button>
            </div>

            {erro && <p className="text-sm text-danger mt-2">{erro}</p>}

            {dados.pronto && (
              <div className="mt-5 border-t border-line pt-4">
                <ol className="space-y-2 text-sm text-ink-6 mb-3">
                  <li>
                    <b className="text-ink">1.</b> Clique em <b>Copiar dados e abrir Inmetro</b> — o portal abre numa nova aba.
                  </li>
                  <li>
                    <b className="text-ink">2.</b> No portal, clique no favorito <b>Preencher GRU (Aferi+)</b> — os campos se preenchem sozinhos.
                  </li>
                  <li>
                    <b className="text-ink">3.</b> Confira, marque <b>“Não sou um robô”</b> e clique em <b>Buscar</b>. Isso é sempre você.
                  </li>
                </ol>
                <button
                  onClick={abrirInmetro}
                  className="w-full py-2.5 rounded-xl font-bold text-sm bg-brand text-[#04120a] hover:bg-brand-d transition-colors"
                >
                  {copiado === 'tudo' ? 'Copiado! Abrindo Inmetro…' : 'Copiar dados e abrir Inmetro'}
                </button>
                <p className="text-xs text-ink-4 mt-2">
                  Ao abrir, fica registrado no histórico: “GRU solicitada”. Sem o favorito, cada campo acima tem um botão de copiar.
                </p>

                <details className="mt-3 rounded-xl border border-line px-3 py-2 text-sm">
                  <summary className="cursor-pointer font-bold text-ink-6 flex items-center gap-1.5">
                    <Bookmark size={15} /> Instalar o favorito “Preencher GRU (Aferi+)” — uma vez só
                  </summary>
                  <ol className="mt-2 space-y-1.5 text-xs text-ink-6">
                    <li><b className="text-ink">1.</b> Clique em <b>Copiar código do favorito</b> (abaixo).</li>
                    <li><b className="text-ink">2.</b> No Chrome, mostre a barra de favoritos (<b>Ctrl+Shift+B</b>), clique com o botão direito nela → <b>Adicionar página…</b></li>
                    <li><b className="text-ink">3.</b> Nome: <b>Preencher GRU (Aferi+)</b>. No campo URL, apague o que tiver e <b>cole</b> (Ctrl+V). Salvar.</li>
                    <li><b className="text-ink">4.</b> Na 1ª vez, o Chrome pergunta se o site pode ler a área de transferência — <b>Permitir</b>.</li>
                  </ol>
                  <button
                    onClick={() => copiar(BOOKMARKLET, 'fav')}
                    className="mt-2 flex items-center gap-1.5 border border-line bg-card text-ink-6 text-xs font-bold px-3 py-1.5 rounded-xl hover:bg-white/5 transition-colors"
                  >
                    {copiado === 'fav' ? <Check size={14} className="text-brand" /> : <Copy size={14} />}
                    {copiado === 'fav' ? 'Código copiado' : 'Copiar código do favorito'}
                  </button>
                </details>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

function EditCampo({
  label,
  hint,
  faltando,
  children,
}: {
  label: string
  hint?: string
  faltando: boolean
  children: ReactNode
}) {
  return (
    <div>
      <label className="block text-xs font-bold uppercase tracking-wide text-ink-4 mb-1">
        {label} {faltando && <span className="text-danger">• falta</span>}
      </label>
      {children}
      {hint && <p className="text-xs text-ink-4 mt-1">{hint}</p>}
    </div>
  )
}

function BotaoCopiar({ ok, onClick }: { ok: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} className="text-ink-4 hover:text-brand" title="Copiar">
      {ok ? <Check size={15} className="text-brand" /> : <Copy size={15} />}
    </button>
  )
}
