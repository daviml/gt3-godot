/**
 * Perfil lateral declarativo de Interlagos (PLANO-INTERLAGOS-DETALHES.md §3 e Fase 2): o que existe em cada lado
 * da pista, da linha branca para fora, lido de `data/track/visual_profile.json` em vez de `if` por metragem.
 *
 * Esquema (v1; a v2 é igual, só muda a pista):
 *   { versao, pista, passo (m entre amostras), comprimento (m), n (amostras), lados: { esq: Fatia[], dir: Fatia[] } }
 *   v1 (Fase 2): pista antiga do web (4.294 m, 2.147 amostras). v2 (Fase 2B etapa F, hoje): pista nova = a da física
 *   (data/track/track.json, 4.308 m, 2.154 amostras), gerada da v1 por ./migrarPerfil2B.ts pelo mapa de s; nela as
 *   zebras são todas `larg: "fisica"` (a física já tem as zebras decididas na Fase 2) e as barreiras ficam no muro
 *   da física (`dist: "fisica"`; ver o topo do migrarPerfil2B.ts). Editar à mão a partir daqui; não regenerar.
 *   Fatia = { s0, s1, faixas: Faixa[], barreira }  — s0/s1 em metros da pista (s das amostras, inclusive), as
 *   fatias de cada lado cobrem a volta inteira sem buraco nem sobreposição.
 *   Faixas, na ordem da linha branca para fora (a grama é o chão de baixo de tudo, até 1 m depois da barreira):
 *     { tipo: "zebra", larg: "fisica", minimo?: n, listrada?: false, visual?: "normal" | "saida" }
 *         largura da física (Track do web) com mínimo opcional; listrada: false = sem zebra pintada (só a faixa
 *         verde e a salsicha por cima). A largura visual sai de BORDA (trackView.ts). Sem faixa "zebra" = sem zebra.
 *         A largura da física (kerb) também posiciona escape e barreira; para mudar só o desenho (Fase 2, zebras
 *         pelo satélite/vídeo) sem mexer no resto:
 *           - esconder a zebra onde a física tem: listrada: false (a largura da física continua valendo);
 *           - mostrar zebra onde a física não tem (kerb 0): visual: "normal" | "saida" (largura visual fixa de
 *             BORDA.zebra.larg / largSaida, independente do kerb; o kerb, o escape e a barreira não mudam).
 *           Com `visual` onde a física tem zebra, a classe declarada também substitui a que viria do kerb.
 *     { tipo: "pintura", cor: "verde" | "agua", larg: n }    faixa pintada atrás da zebra (cor "agua" = verde-água,
 *         Fase 7: a faixa entre a linha branca e a salsicha nos dois ápices da Ferradura)
 *     { tipo: "salsicha", larg: n }                  salsicha amarela elevada (depois da pintura)
 *     { tipo: "escape", cor: "verde" | "agua" | "vermelho" | "asfalto", larg: Valor, fora?: { cor, larg: Valor },
 *       grama?: Valor }
 *         asfalto pintado de escape. `fora` (Fase 4, saída da Curva do Sol: vermelho com uma faixa verde atrás) = uma
 *         segunda faixa pintada logo depois do escape, de outra cor; não muda o escape nem a barreira (só o desenho).
 *         `grama` (Fase 5, Reta Oposta) = faixa de grama entre a zebra (ou a borda) e o começo do escape, CONTADA
 *         DENTRO de `larg` (o escape pintado vai de grama a larg; o fim do escape e a barreira não mudam).
 *         cor "asfalto" (Fase 5) = asfalto cinza sem tinta: a pista dos boxes depois da junção e a área de escape
 *         ("escape road") antes da Descida do Lago.
 *   barreira = { tipo: "rail" | "wall" | "tecpro" | "tecpro2" | "rolex_pad", dist: Valor, de?: "zebra" | "escape",
 *                banner?: AdScheme, alambrado?: true, topo?: false }
 *     dist = distância lateral da barreira contada da linha branca (borda do asfalto); com `de`, contada da borda
 *     de fora da zebra física ("zebra") ou do fim do escape ("escape").
    topo: false (Fase 6) = barreira azul simples ("tecpro") sem a faixa amarela de patrocinador em cima (a Goodyear do
    Lago no LMU é azul lisa).
    paredao: true (Fase 7) = paredão de concreto alto atrás da barreira, com a faixa grande DHL (Ferradura/Laranjinha;
    antes um trecho fixo em código, buildFerraduraWall em ./trackDetails.ts, que agora desenha onde o perfil pede).
 *   Chave opcional `arvores` (Fase 4, Etapa A das árvores): zonas por s e lado, espaçamento e escala nos setores já
 *   revisados; lida por ./arvoresSetor.ts (não por este módulo).
 *   Valor = número (constante na fatia) | "fisica" (o valor da física do Track nessa amostra) |
 *           número[] (um por amostra de s0 a s1; trechos de transição, valores exatos).
 *
 * Gerado de início por ./extrairPerfil.ts com o comportamento anterior do gerador (migração sem regressão; obsoleto
 * desde a etapa F da Fase 2B, que levou o perfil para a pista nova com ./migrarPerfil2B.ts).
 */
import type { Track } from '@web/track/track';
import perfilJson from '../../../data/track/visual_profile.json';

export type Valor = number | 'fisica' | number[];
export type Faixa =
  | { tipo: 'zebra'; larg: 'fisica'; minimo?: number; listrada?: false; visual?: 'normal' | 'saida' }
  | { tipo: 'pintura'; cor: 'verde' | 'agua'; larg: number }
  | { tipo: 'salsicha'; larg: number }
  | { tipo: 'escape'; cor: CorEscape; larg: Valor; fora?: { cor: CorEscape; larg: Valor }; grama?: Valor };
export type CorEscape = 'verde' | 'agua' | 'vermelho' | 'asfalto';
export type TipoBarreira = 'rail' | 'wall' | 'tecpro' | 'tecpro2' | 'rolex_pad';
export interface Barreira {
  tipo: TipoBarreira;
  dist: Valor;
  de?: 'zebra' | 'escape';
  banner?: string;
  alambrado?: true;
  topo?: false;
  paredao?: true;
}
export interface Fatia {
  s0: number;
  s1: number;
  faixas: Faixa[];
  barreira: Barreira;
}
export interface Perfil {
  versao: number;
  pista: string;
  passo: number;
  comprimento: number;
  n: number;
  lados: { esq: Fatia[]; dir: Fatia[] };
}

/** o que o perfil decide em uma amostra de um lado */
export interface AmostraLado {
  /** largura física da zebra (m), 0 = sem zebra */
  kerb: number;
  /** zebra listrada pintada (false = só pintura/salsicha) */
  listrada: boolean;
  /** classe de largura visual declarada no perfil (null = a que sai da largura da física) */
  zebraVisual: 'normal' | 'saida' | null;
  /** largura da faixa verde atrás da zebra (0 = sem) */
  verde: number;
  /** cor dessa faixa (Faixa pintura.cor; padrão verde) */
  verdeCor: 'verde' | 'agua';
  /** largura da salsicha (0 = sem) */
  salsicha: number;
  /** largura do escape asfaltado (0 = sem) */
  run: number;
  escapeCor: CorEscape;
  /** grama antes do escape pintado, dentro de `run` (Faixa escape.grama; 0 = sem) */
  grama: number;
  /** largura da segunda faixa pintada depois do escape (0 = sem; Faixa escape.fora) */
  run2: number;
  escapeCor2: CorEscape;
  /** deslocamento lateral da barreira a partir do centro (como Sample.wallL/wallR) */
  wall: number;
  tipo: TipoBarreira;
  banner: string | null;
  alambrado: boolean;
  /** faixa de patrocinador em cima da barreira azul simples (Barreira.topo; padrão true) */
  topo: boolean;
  /** paredão de concreto com a faixa DHL atrás da barreira (Barreira.paredao; Fase 7) */
  paredao: boolean;
}

const valor = (v: Valor, k: number, fisica: number) => (v === 'fisica' ? fisica : typeof v === 'number' ? v : v[k]);

/**
 * Avalia o perfil em todas as amostras do lado. `w` = meia-largura do asfalto, `kerb0/run0/wall0` = valores da física
 * (antes de qualquer ajuste visual). Ordem: zebra, escape (que não depende da zebra) e barreira (que pode depender dos dois).
 */
function avaliarLado(fatias: Fatia[], n: number, passo: number, w: number[], kerb0: number[], run0: number[], wall0: number[]): AmostraLado[] {
  const out: AmostraLado[] = new Array(n);
  for (const f of fatias) {
    const i0 = Math.round(f.s0 / passo);
    const i1 = Math.round(f.s1 / passo);
    const zebra = f.faixas.find(x => x.tipo === 'zebra') as Extract<Faixa, { tipo: 'zebra' }> | undefined;
    const pint = f.faixas.find(x => x.tipo === 'pintura') as Extract<Faixa, { tipo: 'pintura' }> | undefined;
    const sal = f.faixas.find(x => x.tipo === 'salsicha') as Extract<Faixa, { tipo: 'salsicha' }> | undefined;
    const esc = f.faixas.find(x => x.tipo === 'escape') as Extract<Faixa, { tipo: 'escape' }> | undefined;
    const b = f.barreira;
    for (let i = i0; i <= i1; i++) {
      const k = i - i0;
      const kerb = zebra ? (zebra.minimo !== undefined ? Math.max(kerb0[i], zebra.minimo) : kerb0[i]) : 0;
      const run = esc ? valor(esc.larg, k, run0[i]) : 0;
      const d = valor(b.dist, k, NaN);
      const wall =
        b.dist === 'fisica' ? wall0[i] : b.de === 'escape' ? w[i] + kerb + run + d : b.de === 'zebra' ? w[i] + kerb + d : w[i] + d;
      out[i] = {
        kerb,
        listrada: zebra?.listrada !== false,
        zebraVisual: zebra?.visual ?? null,
        verde: pint?.larg ?? 0,
        verdeCor: pint?.cor ?? 'verde',
        salsicha: sal?.larg ?? 0,
        run,
        escapeCor: esc?.cor ?? 'verde',
        grama: esc?.grama !== undefined ? Math.min(run, valor(esc.grama, k, 0)) : 0,
        run2: esc?.fora ? valor(esc.fora.larg, k, 0) : 0,
        escapeCor2: esc?.fora?.cor ?? 'verde',
        wall,
        tipo: b.tipo,
        banner: b.banner ?? null,
        alambrado: !!b.alambrado,
        topo: b.topo !== false,
        paredao: !!b.paredao
      };
    }
  }
  return out;
}

/** perfil avaliado por amostra; L = esquerda, R = direita */
export interface PerfilAmostras {
  L: AmostraLado[];
  R: AmostraLado[];
}

/** avalia um perfil (o do arquivo ou outro) nas amostras do track, sem mexer nele; usa os valores atuais da física */
export function avaliarPerfil(track: Track, perfil: Perfil): PerfilAmostras {
  const S = track.samples;
  if (perfil.n !== S.length || perfil.passo * S.length !== track.length)
    throw new Error(`visual_profile.json: ${perfil.n} amostras de ${perfil.passo} m, mas a pista tem ${S.length} (${track.length} m)`);
  for (const lado of [perfil.lados.esq, perfil.lados.dir]) {
    let next = 0;
    for (const f of lado) {
      if (Math.round(f.s0 / perfil.passo) !== next) throw new Error(`visual_profile.json: fatia ${f.s0}..${f.s1} não continua a anterior`);
      next = Math.round(f.s1 / perfil.passo) + 1;
    }
    if (next !== S.length) throw new Error('visual_profile.json: as fatias não cobrem a volta inteira');
  }
  return {
    L: avaliarLado(perfil.lados.esq, S.length, perfil.passo, S.map(s => s.wl), S.map(s => s.kerbL), S.map(s => s.runL), S.map(s => s.wallL)),
    R: avaliarLado(perfil.lados.dir, S.length, perfil.passo, S.map(s => s.wr), S.map(s => s.kerbR), S.map(s => s.runR), S.map(s => s.wallR))
  };
}

const aplicados = new WeakMap<Track, PerfilAmostras>();

/**
 * Lê data/track/visual_profile.json e grava no track as larguras visuais de zebra, escape e a posição das barreiras
 * (kerbL/R, runL/R, wallL/R; a física do jogo não muda, isto é só o cenário). Chamar uma vez, antes de montar o resto.
 */
export function aplicarPerfil(track: Track): PerfilAmostras {
  const p = avaliarPerfil(track, perfilJson as unknown as Perfil);
  track.samples.forEach((s, i) => {
    s.kerbL = p.L[i].kerb;
    s.kerbR = p.R[i].kerb;
    s.runL = p.L[i].run;
    s.runR = p.R[i].run;
    s.wallL = p.L[i].wall;
    s.wallR = p.R[i].wall;
  });
  aplicados.set(track, p);
  return p;
}

/** o perfil já aplicado neste track (aplicarPerfil) */
export function perfilDe(track: Track): PerfilAmostras {
  const p = aplicados.get(track);
  if (!p) throw new Error('perfil lateral ainda não aplicado (aplicarPerfil em buildTrack)');
  return p;
}
