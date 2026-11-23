/**
 * Extrator do perfil lateral (PLANO-INTERLAGOS-DETALHES.md Fase 2, "migração sem regressão"): avalia, amostra por
 * amostra, as decisões que o gerador tomava em código até 20/11/2026 (o `for` de ajustes por metragem do
 * trackView.ts, BORDA_TRECHOS, runColor e barrierLayout/ZONES do trackDetails.ts, copiados abaixo sem mudança) e
 * consolida em fatias → data/track/visual_profile.json (esquema em ./perfil.ts).
 *
 * Depois da migração o perfil é a fonte; este arquivo só serve para refazer o perfil v1 (idêntico ao gerador antigo)
 * e como registro de onde cada número veio. Regenerar: (de REPOS/gt3-godot/tools) node cenario.mjs --extrair-perfil
 * A página também confere: avalia o perfil gerado com ./perfil.ts e compara com o código antigo em cada amostra.
 *
 * OBSOLETO desde a Fase 2B etapa F: o perfil passou para a pista nova (./migrarPerfil2B.ts) e o vite.config.ts troca o
 * import do interlagos.json do web abaixo pela fonte nova; o cenario.mjs recusa --extrair-perfil. Fica só como
 * registro de onde vieram os números da v1.
 */
import { STEP, Track, type TrackData } from '@web/track/track';
import interlagos from '../../../../gt3-time-attack/data/tracks/interlagos.json';
import { applyBank, applyKerbs, applyWalls, clampRunoff } from '../../tracks/bank';
import { avaliarPerfil, type Barreira, type Faixa, type Fatia, type Perfil, type TipoBarreira } from './perfil';

// ---------------------------------------------------------------------------------------------------------------
// Código antigo (cópia fiel)
// ---------------------------------------------------------------------------------------------------------------

/** trackView.ts: zebras extras, escapes e muros ajustados quadro a quadro (01..30) contra o LMU */
function legadoBordas(track: Track) {
  const S = track.samples;
  const k43track = track.length / 4300;
  const smooth = (a: number, b: number, x: number) => {
    const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
  };
  const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
  // mínimo de zebra imposto por trecho (o max das regras que valem na amostra)
  const minL: (number | undefined)[] = new Array(S.length);
  const minR: (number | undefined)[] = new Array(S.length);
  const minimo = (arr: (number | undefined)[], i: number, c: number) => (arr[i] = Math.max(arr[i] ?? 0, c));
  for (let i = 0; i < S.length; i++) {
    const sm = S[i].s / k43track;
    const oKL = S[i].kerbL;
    const oKR = S[i].kerbR;
    const oRL = S[i].runL;
    const oRR = S[i].runR;
    const oWL = S[i].wallL;
    const oWR = S[i].wallR;

    // --- Zebras extras onde faltam ---
    if (sm >= 580 && sm <= 785) (S[i].kerbL = Math.max(oKL, 1.2)), minimo(minL, i, 1.2);
    if (sm >= 1385 && sm <= 1580) (S[i].kerbL = Math.max(oKL, 1.2)), minimo(minL, i, 1.2);
    if (sm >= 1580 && sm <= 1760) (S[i].kerbR = Math.max(oKR, 1.2)), minimo(minR, i, 1.2);
    if (sm >= 2510 && sm <= 2610) (S[i].kerbL = Math.max(oKL, 1.6)), minimo(minL, i, 1.6);
    if (sm >= 2900 && sm < 2980) (S[i].kerbR = Math.max(oKR, 1.4)), minimo(minR, i, 1.4);
    if (sm >= 2980 && sm <= 3235) (S[i].kerbR = Math.max(oKR, 1.6)), minimo(minR, i, 1.6);
    if (sm >= 3235 && sm <= 3420) (S[i].kerbR = Math.max(oKR, 2.0)), minimo(minR, i, 2.0);
    if (sm >= 3550 && sm <= 3650) (S[i].kerbL = Math.max(oKL, 1.4)), minimo(minL, i, 1.4);

    // --- Lado Direito (runR e wallR) ---
    let tRR = oRR;
    let tWR = oWR;
    if (sm < 155 || sm >= 3440) {
      if (sm >= 3440 && sm < 3465) {
        const k = smooth(3440, 3465, sm);
        tRR = lerp(oRR, 1.4, k);
        tWR = lerp(oWR, S[i].wr + 1.4, k);
      } else {
        tRR = 1.4;
        tWR = S[i].wr + 1.4;
      }
    } else if (sm >= 155 && sm < 385) {
      if (sm < 255) tRR = lerp(1.2, 4.8, smooth(170, 255, sm));
      else if (sm < 305) tRR = lerp(4.8, 7.2, smooth(255, 305, sm));
      else tRR = 7.2;
      if (sm < 170) tRR = lerp(1.4, tRR, smooth(155, 170, sm));
      const tight = S[i].wr + S[i].kerbR + tRR;
      tWR = sm < 170 ? lerp(S[i].wr + 1.4, tight, smooth(155, 170, sm)) : tight;
    } else if (sm >= 385 && sm < 545) {
      tRR = sm < 530 ? lerp(7.2, 3.5, smooth(385, 530, sm)) : lerp(3.5, 0, smooth(530, 545, sm));
      const extra = lerp(0, 3.0, smooth(375, 415, sm));
      const base = S[i].wr + S[i].kerbR + tRR + extra;
      tWR = sm < 525 ? base : lerp(base, S[i].wr + 6.2, smooth(525, 545, sm));
    } else if (sm >= 545 && sm < 775) {
      tRR = 0;
      tWR = S[i].wr + 6.2;
    } else if (sm >= 775 && sm < 1150) {
      tRR = 0;
      tWR = lerp(S[i].wr + 6.2, S[i].wr + 7.0, smooth(775, 795, sm));
    } else if (sm >= 1150 && sm < 1385) {
      tRR = sm < 1365 ? 0 : lerp(0, 7.5, smooth(1365, 1385, sm));
      tWR = sm < 1365
        ? lerp(S[i].wr + 7.0, S[i].wr + 7.5, smooth(1145, 1165, sm))
        : lerp(S[i].wr + 7.5, S[i].wr + S[i].kerbR + 7.5, smooth(1365, 1385, sm));
    } else if (sm >= 1385 && sm <= 1800) {
      if (sm <= 1660) {
        tRR = 7.5;
        tWR = S[i].wr + S[i].kerbR + 7.5;
      } else if (sm <= 1760) {
        const k = smooth(1660, 1690, sm);
        tRR = lerp(7.5, 5.5, k);
        tWR = lerp(S[i].wr + S[i].kerbR + 7.5, oWR, k);
      } else {
        tRR = lerp(5.5, oRR, smooth(1760, 1800, sm));
        tWR = oWR;
      }
    } else if (sm >= 1970 && sm <= 2245) {
      const inK = smooth(1970, 1990, sm);
      const out = smooth(2180, 2245, sm);
      tRR = lerp(lerp(oRR, 1.0, inK), oRR, out);
      tWR = lerp(lerp(oWR, S[i].wr + 9.0, inK), oWR, out);
    } else if (sm >= 2255 && sm <= 2490) {
      const k = smooth(2255, 2275, sm) * (1 - smooth(2470, 2490, sm));
      tRR = lerp(oRR, 0, k);
      tWR = lerp(oWR, S[i].wr + 5.5, k);
    } else if (sm >= 2495 && sm <= 2625) {
      const k = smooth(2495, 2515, sm) * (1 - smooth(2605, 2625, sm));
      tRR = lerp(oRR, 0, k);
      tWR = lerp(oWR, S[i].wr + 9.0, k);
    } else if (sm >= 2665 && sm <= 2855) {
      const k = smooth(2665, 2685, sm) * (1 - smooth(2835, 2855, sm));
      tRR = lerp(oRR, 0.6, k);
    } else if (sm >= 2890 && sm < 3235) {
      const k = smooth(2890, 2915, sm);
      tRR = lerp(oRR, 8.2, k);
      tWR = lerp(oWR, S[i].wr + S[i].kerbR + 8.2, k);
    } else if (sm >= 3235 && sm < 3440) {
      const out = smooth(3415, 3440, sm);
      const t1 = smooth(3235, 3255, sm);
      const rrMid = lerp(8.2, 0, t1);
      const wrMid = lerp(S[i].wr + S[i].kerbR + 8.2, S[i].wr + S[i].kerbR + 2.8, t1);
      tRR = lerp(rrMid, 1.4, out);
      tWR = lerp(wrMid, S[i].wr + 1.4, out);
    }
    S[i].runR = tRR;
    S[i].wallR = tWR;

    // --- Lado Esquerdo (runL e wallL) ---
    let tRL = oRL;
    let tWL = oWL;
    if (sm < 155 || sm >= 4040) {
      tRL = 1.4;
      tWL = S[i].wl + 1.4;
    } else if (sm >= 155 && sm < 385) {
      tRL = sm < 285
        ? Math.max(oRL, 0.85)
        : sm < 305
          ? Math.max(oRL, lerp(0.85, 2.6, smooth(285, 305, sm)))
          : Math.max(oRL, 2.6);
      if (sm < 170) tRL = lerp(1.4, tRL, smooth(155, 170, sm));
      const tight = S[i].wl + S[i].kerbL + tRL;
      tWL = sm < 170 ? lerp(S[i].wl + 1.4, tight, smooth(155, 170, sm)) : tight;
    } else if (sm >= 385 && sm < 580) {
      tRL = lerp(Math.max(oRL, 2.6), 3.0, smooth(380, 395, sm));
      tWL = S[i].wl + S[i].kerbL + tRL;
    } else if (sm >= 580 && sm < 785) {
      const k = smooth(575, 595, sm);
      tRL = lerp(3.0, 0.5, k);
      tWL = lerp(S[i].wl + S[i].kerbL + 3.0, S[i].wl + 10.5, k);
    } else if (sm >= 785 && sm <= 1375) {
      const inK = smooth(780, 800, sm);
      tRL = sm < 1355 ? lerp(0.5, 0, inK) : lerp(0, 0.4, smooth(1355, 1385, sm));
      tWL = sm < 1355
        ? lerp(S[i].wl + 10.5, S[i].wl + 3.2, inK)
        : lerp(S[i].wl + 3.2, S[i].wl + 6.0, smooth(1355, 1385, sm));
    } else if (sm > 1375 && sm <= 1580) {
      tRL = 0.4;
      tWL = S[i].wl + 6.0;
    } else if (sm > 1580 && sm < 1800) {
      const inK = smooth(1580, 1610, sm);
      const outK = smooth(1775, 1800, sm);
      tRL = lerp(lerp(0.4, 0, inK), 1.8, outK);
      tWL = lerp(lerp(S[i].wl + 6.0, S[i].wl + 3.2, inK), S[i].wl + 6.5, outK);
    } else if (sm >= 1800 && sm < 2010) {
      tRL = sm < 1980 ? 1.8 : lerp(1.8, 2.2, smooth(1980, 2010, sm));
      tWL = sm < 1980 ? S[i].wl + 6.5 : lerp(S[i].wl + 6.5, S[i].wl + 6.8, smooth(1980, 2010, sm));
    } else if (sm >= 2010 && sm < 2130) {
      const k = smooth(2005, 2025, sm);
      tRL = lerp(2.2, 8.5, k);
      tWL = lerp(S[i].wl + 6.8, S[i].wl + S[i].kerbL + 8.5, k);
    } else if (sm >= 2130 && sm <= 2270) {
      const inK = smooth(2125, 2145, sm);
      const out = smooth(2245, 2270, sm);
      tRL = lerp(lerp(8.5, 1.8, inK), oRL, out);
      tWL = lerp(lerp(S[i].wl + S[i].kerbL + 8.5, S[i].wl + 6.5, inK), oWL, out);
    } else if (sm >= 2480 && sm <= 2810) {
      const k = smooth(2480, 2500, sm);
      tRL = lerp(oRL, 0, k);
      tWL = lerp(oWL, S[i].wl + S[i].kerbL + 4.5, k);
    } else if (sm > 2810 && sm < 2900) {
      const k = smooth(2810, 2830, sm) * (1 - smooth(2880, 2900, sm));
      tRL = lerp(0, 4.0, k);
      tWL = lerp(S[i].wl + S[i].kerbL + 4.5, S[i].wl + S[i].kerbL + 6.5, smooth(2810, 2830, sm));
      if (sm >= 2880) tWL = lerp(S[i].wl + S[i].kerbL + 6.5, S[i].wl + 12.0, smooth(2880, 2900, sm));
    } else if (sm >= 2900 && sm <= 3375) {
      const midK = smooth(3205, 3235, sm);
      const out = smooth(3345, 3375, sm);
      tRL = lerp(lerp(0.5, 0, midK), oRL, out);
      tWL = lerp(lerp(S[i].wl + 12.0, S[i].wl + 8.5, midK), oWL, out);
    } else if (sm >= 3500 && sm < 3540) {
      tWL = lerp(oWL, S[i].wl + 3.8, smooth(3500, 3525, sm));
    } else if (sm >= 3540 && sm < 3680) {
      const inK = smooth(3540, 3560, sm);
      const outK = smooth(3665, 3680, sm);
      tRL = lerp(0, 2.0, inK) * (1 - outK);
      tWL = lerp(lerp(S[i].wl + 3.8, S[i].wl + S[i].kerbL + 2.0, inK), S[i].wl + 2.2, outK);
    } else if (sm >= 3680 && sm < 3860) {
      tRL = 0;
      tWL = S[i].wl + 2.2;
    } else if (sm >= 3860 && sm < 4040) {
      tRL = 0;
      const openK = smooth(3860, 3915, sm);
      const joinK = smooth(4015, 4040, sm);
      tWL = lerp(lerp(S[i].wl + 2.2, S[i].wl + 9.4, openK), S[i].wl + 11.7, joinK);
    }
    S[i].runL = tRL;
    S[i].wallL = tWL;
  }
  return { minL, minR };
}

/** trackView.ts (Fase 1): trechos com faixa verde atrás da zebra e/ou salsicha, conferidos no atlas do LMU */
const BORDA_TRECHOS: { lado: -1 | 1; s0: number; s1: number; verde: number; salsicha?: boolean; semZebra?: boolean; nome: string }[] = [
  { lado: -1, s0: 572, s1: 740, verde: 0.2, nome: 'Curva do Sol, zebra interna' },
  { lado: 1, s0: 1988, s1: 2045, verde: 0.65, salsicha: true, semZebra: true, nome: 'Ferradura, ápice da 1ª perna' },
  { lado: -1, s0: 2468, s1: 2505, verde: 1.0, nome: 'Pinheirinho, saída' }
];
const SALSICHA_LARG = 0.4; // BORDA.salsicha.larg

/** trackView.ts: cor do escape pintado */
function legadoCorEscape(track: Track, i: number, side: -1 | 1): 'verde' | 'agua' | 'vermelho' {
  const k43 = track.length / 4300;
  const s = track.samples[i].s / k43;
  if (side > 0 && s > 700 && s < 900) return 'vermelho';
  if ((s > 1950 && s < 2260) || (s > 3100 && s < 3450)) return 'verde';
  return 'verde';
}

type AdScheme = 'verde' | 'vermelho' | 'amarelo' | 'branco' | 'azul' | 'avis';
/** trackDetails.ts: tipo de barreira, placas e alambrado por trecho (o outdoor ficou lá, em OUTDOORS) */
const ZONES: { s0: number; s1: number; side?: -1 | 1; kind: TipoBarreira; ads: AdScheme; fence?: boolean }[] = [
  { s0: 165, s1: 390, side: 1, kind: 'rolex_pad', ads: 'verde', fence: true },
  { s0: 165, s1: 395, side: -1, kind: 'rolex_pad', ads: 'verde', fence: true },
  { s0: 395, s1: 565, side: -1, kind: 'rolex_pad', ads: 'verde', fence: false },
  { s0: 540, s1: 1150, side: 1, kind: 'wall', ads: 'vermelho' },
  { s0: 800, s1: 1180, side: -1, kind: 'rail', ads: 'verde', fence: true },
  { s0: 1150, s1: 1385, side: 1, kind: 'rolex_pad', ads: 'verde', fence: true },
  { s0: 1385, s1: 1660, side: 1, kind: 'tecpro', ads: 'azul' },
  { s0: 1580, s1: 1800, side: -1, kind: 'tecpro', ads: 'azul' },
  { s0: 1800, s1: 2005, side: -1, kind: 'rolex_pad', ads: 'verde', fence: true },
  { s0: 2005, s1: 2140, side: -1, kind: 'wall', ads: 'amarelo', fence: true },
  { s0: 2140, s1: 2335, side: -1, kind: 'wall', ads: 'branco' },
  { s0: 2310, s1: 2480, side: 1, kind: 'wall', ads: 'branco' },
  { s0: 2480, s1: 2830, side: -1, kind: 'wall', ads: 'branco' },
  { s0: 2890, s1: 3235, side: 1, kind: 'wall', ads: 'amarelo', fence: true },
  { s0: 3235, s1: 3420, side: 1, kind: 'wall', ads: 'azul', fence: true },
  { s0: 3420, s1: 4035, side: 1, kind: 'wall', ads: 'avis', fence: true },
  { s0: 3540, s1: 3680, side: -1, kind: 'wall', ads: 'avis', fence: true }
];

function legadoBarreiras(track: Track) {
  const S = track.samples;
  const N = S.length;
  const L = track.length;
  const k = L / 4300;
  const mainRight = (i: number) => S[i].s > L - 520 || S[i].s < 252 * k;
  const mainLeft = (i: number) => S[i].s > L - 251 || S[i].s < 252 * k;
  const kind: Record<-1 | 1, TipoBarreira[]> = { [-1]: new Array(N).fill('rail'), [1]: new Array(N).fill('rail') };
  const ads: Record<-1 | 1, (AdScheme | null)[]> = { [-1]: new Array(N).fill(null), [1]: new Array(N).fill(null) };
  const fence: Record<-1 | 1, boolean[]> = { [-1]: new Array(N).fill(false), [1]: new Array(N).fill(false) };
  for (let i = 0; i < N; i++) {
    if (mainLeft(i)) {
      kind[-1][i] = 'wall';
      ads[-1][i] = 'verde';
      fence[-1][i] = true;
    }
    if (mainRight(i)) {
      kind[1][i] = 'wall';
      ads[1][i] = 'verde';
      fence[1][i] = true;
    }
  }
  for (const z of ZONES) {
    const i0 = Math.round((z.s0 * k) / STEP);
    const i1 = Math.round((z.s1 * k) / STEP);
    let curv = 0;
    for (let i = i0; i < i1; i++) curv += S[i % N].curv;
    const side: -1 | 1 = z.side ?? (curv > 0 ? -1 : 1);
    for (let i = i0; i < i1; i++) {
      const j = i % N;
      kind[side][j] = z.kind;
      ads[side][j] = z.kind === 'wall' ? z.ads : null;
      fence[side][j] = !!z.fence;
    }
  }
  return { kind, ads, fence };
}

// ---------------------------------------------------------------------------------------------------------------
// Consolidação em fatias
// ---------------------------------------------------------------------------------------------------------------

/**
 * constante "bonita" (arredondada a 1e-6) se estiver a ≤ 1e-9 de v; sem trocar o sinal nem cruzar o zero, a não ser
 * com `zero` (distâncias: 1e-16 ou 0 dá na mesma; larguras não, porque "> 0" decide se a faixa existe)
 */
function bonito(v: number, zero = false): number | null {
  const r = Math.round(v * 1e6) / 1e6;
  if (Math.abs(r - v) > 1e-9) return null;
  if (r === v || zero) return r === 0 ? 0 : r;
  if (Math.sign(r) !== Math.sign(v)) return null;
  return r;
}

/**
 * Corta a sequência de amostras de um canal em trechos. Cada amostra tem as representações exatas possíveis
 * (chave → valor); um trecho usa uma chave que vale em todas as suas amostras. Guloso: a chave que vai mais longe;
 * números só valem como constante a partir de MIN amostras; o resto vira lista (valor por amostra).
 */
type Rep = { chave: string; valor: unknown };
interface Trecho {
  i0: number;
  i1: number;
  chave: string;
  valor: unknown;
}
function segmentar(n: number, reps: (i: number) => Rep[], lista: (i: number) => number, MIN = 3): Trecho[] {
  const R = Array.from({ length: n }, (_, i) => reps(i));
  const out: Trecho[] = [];
  const alcance = (i: number, chave: string) => {
    let j = i;
    while (j + 1 < n && R[j + 1].some(r => r.chave === chave)) j++;
    return j;
  };
  let i = 0;
  let lst: number[] | null = null;
  let lst0 = 0;
  const fechaLista = (fim: number) => {
    if (lst) out.push({ i0: lst0, i1: fim, chave: 'lista', valor: lst });
    lst = null;
  };
  while (i < n) {
    let best: Rep | null = null;
    let bestJ = -1;
    for (const r of R[i]) {
      const j = alcance(i, r.chave);
      const numero = r.chave.startsWith('n:') || r.chave.startsWith('d');
      if (numero && j - i + 1 < MIN) continue;
      if (j > bestJ) {
        bestJ = j;
        best = r;
      }
    }
    if (!best) {
      if (!lst) {
        lst = [];
        lst0 = i;
      }
      lst.push(lista(i));
      i++;
      continue;
    }
    fechaLista(i - 1);
    out.push({ i0: i, i1: bestJ, chave: best.chave, valor: best.valor });
    i = bestJ + 1;
  }
  fechaLista(n - 1);
  return out;
}

function extrair(): { perfil: Perfil; conferencia: Record<string, unknown> } {
  const novoTrack = () => {
    const track = new Track(interlagos as unknown as TrackData);
    const trData = interlagos as { maxRunoff?: number; bank?: number[]; kerbLeft?: number[]; kerbRight?: number[]; wallLeft?: number[]; wallRight?: number[] };
    applyKerbs(track, trData.kerbLeft, trData.kerbRight);
    applyWalls(track, trData.wallLeft, trData.wallRight);
    clampRunoff(track, trData.maxRunoff);
    applyBank(track, trData.bank);
    return track;
  };
  const track = novoTrack();
  const S = track.samples;
  const N = S.length;
  const orig = S.map(s => ({ kerbL: s.kerbL, kerbR: s.kerbR, runL: s.runL, runR: s.runR, wallL: s.wallL, wallR: s.wallR }));
  const { minL, minR } = legadoBordas(track);
  const lay = legadoBarreiras(track);

  // trechos especiais (BORDA_TRECHOS), como no trackView.ts
  const trechoL: (typeof BORDA_TRECHOS)[number][] = new Array(N);
  const trechoR: (typeof BORDA_TRECHOS)[number][] = new Array(N);
  for (let i = 0; i < N; i++)
    for (const t of BORDA_TRECHOS) {
      if (S[i].s < t.s0 || S[i].s > t.s1) continue;
      if (t.lado < 0) trechoL[i] = t;
      else trechoR[i] = t;
    }

  const lado = (side: -1 | 1): Fatia[] => {
    const L = side < 0;
    const w = (i: number) => (L ? S[i].wl : S[i].wr);
    const kerb0 = (i: number) => (L ? orig[i].kerbL : orig[i].kerbR);
    const run0 = (i: number) => (L ? orig[i].runL : orig[i].runR);
    const wall0 = (i: number) => (L ? orig[i].wallL : orig[i].wallR);
    const kerb = (i: number) => (L ? S[i].kerbL : S[i].kerbR);
    const run = (i: number) => (L ? S[i].runL : S[i].runR);
    const wall = (i: number) => (L ? S[i].wallL : S[i].wallR);
    const min = L ? minL : minR;
    const trecho = L ? trechoL : trechoR;

    // borda pintada: zebra (física com mínimo), faixa verde, salsicha
    const borda = segmentar(N, i => {
      const t = trecho[i];
      // como no trackView: a zebra listrada some com semZebra; a faixa verde só existe com zebra visível ou semZebra
      const temZebra = kerb(i) > 0;
      const tem = !!t && ((temZebra && !t.semZebra) || !!t.semZebra);
      const faixas: Faixa[] = [];
      if (temZebra) {
        const z: Extract<Faixa, { tipo: 'zebra' }> = { tipo: 'zebra', larg: 'fisica' };
        if (min[i] !== undefined) z.minimo = min[i];
        if (t?.semZebra) z.listrada = false;
        faixas.push(z);
      }
      if (tem) {
        faixas.push({ tipo: 'pintura', cor: 'verde', larg: t.verde });
        if (t.salsicha) faixas.push({ tipo: 'salsicha', larg: SALSICHA_LARG });
      }
      return [{ chave: JSON.stringify(faixas), valor: faixas }];
    }, () => NaN);

    // escape: largura e cor (a cor só importa onde há escape)
    const escape = segmentar(N, i => {
      const r = run(i);
      if (r === 0) return [{ chave: 'nenhum', valor: null }];
      const cor = legadoCorEscape(track, i, side);
      const reps: Rep[] = [];
      if (r === run0(i)) reps.push({ chave: `fisica|${cor}`, valor: { cor, larg: 'fisica' } });
      const b = bonito(r);
      if (b !== null) reps.push({ chave: `n:${b}|${cor}`, valor: { cor, larg: b } });
      return reps;
    }, run);
    // a cor das listas: um trecho de lista não pode trocar de cor no meio
    const escapeCor = (i: number) => legadoCorEscape(track, i, side);

    // barreira: tipo/banner/alambrado e distância
    const barTipo = segmentar(N, i => {
      const tipo = lay.kind[side][i];
      const b: Omit<Barreira, 'dist'> = { tipo };
      const ads = lay.ads[side][i];
      if (ads) b.banner = ads;
      if (lay.fence[side][i]) b.alambrado = true;
      return [{ chave: JSON.stringify(b), valor: b }];
    }, () => NaN);
    const barDist = segmentar(N, i => {
      const reps: Rep[] = [];
      if (wall(i) === wall0(i)) reps.push({ chave: 'fisica', valor: { dist: 'fisica' } });
      const dl = bonito(wall(i) - w(i), true);
      if (dl !== null) reps.push({ chave: `dl:${dl}`, valor: { dist: dl } });
      const dz = bonito(wall(i) - w(i) - kerb(i), true);
      if (dz !== null) reps.push({ chave: `dz:${dz}`, valor: { dist: dz, de: 'zebra' } });
      const de = bonito(wall(i) - w(i) - kerb(i) - run(i), true);
      if (de !== null) reps.push({ chave: `de:${de}`, valor: { dist: de, de: 'escape' } });
      return reps;
    }, i => wall(i) - w(i));

    // cortes de todos os canais juntos (e onde a cor do escape muda dentro de uma lista)
    const cortes = new Set<number>([0]);
    for (const seg of [borda, escape, barTipo, barDist]) for (const t of seg) cortes.add(t.i0);
    for (let i = 1; i < N; i++) if (run(i) > 0 && run(i - 1) > 0 && escapeCor(i) !== escapeCor(i - 1)) cortes.add(i);
    const ini = [...cortes].sort((a, b) => a - b);
    const em = (seg: Trecho[], i: number) => seg.find(t => i >= t.i0 && i <= t.i1)!;
    const fatias: Fatia[] = [];
    ini.forEach((i0, k) => {
      const i1 = (ini[k + 1] ?? N) - 1;
      const sub = (t: Trecho) => (t.chave === 'lista' ? (t.valor as number[]).slice(i0 - t.i0, i1 - t.i0 + 1) : null);
      const b = em(borda, i0);
      const faixas: Faixa[] = [...(b.valor as Faixa[])];
      const e = em(escape, i0);
      if (e.chave === 'lista') faixas.push({ tipo: 'escape', cor: escapeCor(i0), larg: sub(e)! });
      else if (e.chave !== 'nenhum') faixas.push({ tipo: 'escape', ...(e.valor as { cor: 'verde'; larg: number }) });
      const bt = em(barTipo, i0).valor as Omit<Barreira, 'dist'>;
      const bd = em(barDist, i0);
      const dist = bd.chave === 'lista' ? { dist: sub(bd)! } : (bd.valor as { dist: number; de?: 'zebra' | 'escape' });
      const barreira: Barreira = { tipo: bt.tipo, ...dist, ...(bt.banner ? { banner: bt.banner } : {}), ...(bt.alambrado ? { alambrado: true as const } : {}) };
      fatias.push({ s0: S[i0].s, s1: S[i1].s, faixas, barreira });
    });
    return fatias;
  };

  const perfil: Perfil = {
    versao: 1,
    pista: 'interlagos',
    passo: STEP,
    comprimento: track.length,
    n: N,
    lados: { esq: lado(-1), dir: lado(1) }
  };

  // conferência: o perfil avaliado por ./perfil.ts num track novo (física pura) contra o código antigo
  const t2 = novoTrack();
  const p = avaliarPerfil(t2, JSON.parse(JSON.stringify(perfil)) as Perfil);
  const conf: Record<string, { exatas: number; maxDif: number }> = {};
  const conta = (nome: string, a: number, b: number) => {
    const c = (conf[nome] ??= { exatas: 0, maxDif: 0 });
    if (a === b) c.exatas++;
    else c.maxDif = Math.max(c.maxDif, Math.abs(a - b));
  };
  let categorias = 0;
  for (let i = 0; i < N; i++) {
    for (const [side, A] of [[-1, p.L[i]], [1, p.R[i]]] as const) {
      const L = side < 0;
      conta(L ? 'kerbL' : 'kerbR', A.kerb, L ? S[i].kerbL : S[i].kerbR);
      conta(L ? 'runL' : 'runR', A.run, L ? S[i].runL : S[i].runR);
      conta(L ? 'wallL' : 'wallR', A.wall, L ? S[i].wallL : S[i].wallR);
      const t = (L ? trechoL : trechoR)[i];
      const kz = L ? S[i].kerbL : S[i].kerbR;
      const tem = !!t && (kz > 0 || !!t.semZebra);
      const esperado = {
        listrada: kz > 0 ? !t?.semZebra : A.listrada,
        verde: tem ? t.verde : 0,
        salsicha: tem && t.salsicha ? SALSICHA_LARG : 0,
        escapeCor: A.run > 0 ? legadoCorEscape(track, i, side) : A.escapeCor,
        tipo: lay.kind[side][i],
        banner: lay.ads[side][i],
        alambrado: lay.fence[side][i]
      };
      for (const [k, v] of Object.entries(esperado)) if ((A as unknown as Record<string, unknown>)[k] !== v) categorias++;
    }
  }
  return { perfil, conferencia: { amostras: N, valores: conf, categoriasErradas: categorias } };
}

/** JSON legível: cabeçalho indentado, uma fatia por linha */
function formatar(p: Perfil): string {
  const lado = (f: Fatia[]) => '[\n' + f.map(x => '    ' + JSON.stringify(x)).join(',\n') + '\n  ]';
  const { lados, ...cab } = p;
  const head = JSON.stringify(cab, null, 2).slice(0, -2);
  return `${head},\n  "lados": {\n  "esq": ${lado(lados.esq)},\n  "dir": ${lado(lados.dir)}\n  }\n}\n`;
}

(window as any).extrairPerfil = () => {
  const { perfil, conferencia } = extrair();
  return { texto: formatar(perfil), conferencia, fatias: { esq: perfil.lados.esq.length, dir: perfil.lados.dir.length } };
};
