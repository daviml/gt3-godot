/**
 * Árvores por setor, Etapa A do PLANO-INTERLAGOS-DETALHES.md §5 (Fase 4 em diante): onde e quantas, por dados.
 *
 * Lê `arvores` de data/track/visual_profile.json:
 *   { setores: [{ s0, s1 }],             trechos já revisados (fora deles as árvores ficam como sempre foram)
 *     espacamento: m,                    distância mínima entre troncos dentro dos setores
 *     escala: [min, max], base: k,       tamanho = base × (min..max) (antes 2,0–3,5×; o modelo tem 3–5 m)
 *     zonas: [{ lado: "esq" | "dir", s0, s1, d0, d1, dens, fonte }] }
 *       d0/d1 = metros ALÉM do muro da física; dens = fração que fica (0 = exclusão; 1 = mata como sempre).
 *       Fora das zonas, dentro de um setor: dens 1.
 *     ancora?: { esq?: Ancora, dir?: Ancora }   (Fase 6) muro da física CONGELADO para a âncora do sorteio da mata
 *       (buildScenery: cada tentativa cai a muro + 10..160 m de uma amostra). Onde um setor move o muro da física,
 *       a âncora fica no muro de antes, senão os capões dessas tentativas andam junto com o muro e caem perto de
 *       OUTRO trecho (Fase 6: muro dir do Lago +10–20 m moveu 115 árvores da Reta Oposta). Ancora = { s0, muro: m[] }
 *       (uma por amostra a partir de s0).
 * Tudo decidido pela posição de cada árvore (./sorteio.ts): mexer num setor não muda as árvores dos outros.
 * O espaçamento é um desbaste "de vizinhança": cada árvore tem uma prioridade sorteada pela posição e fica se nenhuma
 * vizinha a menos de `espacamento` (já aprovada pelas zonas) tiver prioridade maior. Não depende da ordem da lista.
 */
import { STEP, type Track } from '@web/track/track';
import perfilJson from '../../../data/track/visual_profile.json';
import { randPosicao } from './sorteio';

interface Zona {
  lado: 'esq' | 'dir';
  s0: number;
  s1: number;
  d0: number;
  d1: number;
  dens: number;
}
interface Ancora {
  s0: number;
  muro: number[];
}
interface ArvoresCfg {
  setores: { s0: number; s1: number }[];
  espacamento: number;
  escala: [number, number];
  base: number;
  zonas: Zona[];
  ancora?: { esq?: Ancora; dir?: Ancora };
}

const CFG = (perfilJson as unknown as { arvores?: ArvoresCfg }).arvores;

export interface Arvore {
  x: number;
  y: number;
  z: number;
  scale: number;
  yaw: number;
}

/**
 * muro usado como âncora do sorteio da mata na amostra i (lado -1 = esq): o congelado em `arvores.ancora` quando a
 * amostra está nele, senão o muro atual
 */
export function muroAncora(track: Track, i: number, side: -1 | 1): number {
  const s = track.samples[i];
  const a = CFG?.ancora?.[side < 0 ? 'esq' : 'dir'];
  if (a) {
    const k = Math.round((s.s - a.s0) / STEP);
    if (k >= 0 && k < a.muro.length) return a.muro[k];
  }
  return side < 0 ? s.wallL : s.wallR;
}

/** aplica as zonas, o espaçamento e a escala nas árvores que caem nos setores revisados; devolve a lista filtrada */
export function arvoresPorSetor<T extends Arvore>(track: Track, spots: T[], rotulo: string): T[] {
  if (!CFG || !CFG.setores.length) return spots;
  // amostra mais próxima em planta (o Track.locate só acha perto da pista e pode escolher outro trecho no miolo)
  const S = track.samples;
  const perto = (x: number, z: number) => {
    let best = Infinity;
    let k = 0;
    for (let i = 0; i < S.length; i++) {
      const d2 = (S[i].p.x - x) ** 2 + (S[i].p.z - z) ** 2;
      if (d2 < best) {
        best = d2;
        k = i;
      }
    }
    const s = S[k];
    const d = (x - s.p.x) * s.r.x + (z - s.p.z) * s.r.z;
    return { s: s.s, d, wallL: s.wallL, wallR: s.wallR };
  };
  const noSetor = (s: number) => CFG.setores.some(z => s >= z.s0 && s <= z.s1);
  const candidatas: { t: T; prio: number }[] = [];
  const fora: T[] = [];
  let excluidas = 0;
  for (const t of spots) {
    const loc = perto(t.x, t.z);
    if (!noSetor(loc.s)) {
      fora.push(t);
      continue;
    }
    const lado = loc.d < 0 ? 'esq' : 'dir';
    const alem = Math.abs(loc.d) - (loc.d < 0 ? loc.wallL : loc.wallR);
    const zona = CFG.zonas.find(z => z.lado === lado && loc.s >= z.s0 && loc.s <= z.s1 && alem >= z.d0 && alem < z.d1);
    const r = randPosicao(t.x, t.z, 0xa7a);
    const dens = zona ? zona.dens : 1;
    if (r() >= dens) {
      excluidas++;
      continue;
    }
    const [e0, e1] = CFG.escala;
    t.scale = CFG.base * (e0 + (e1 - e0) * r());
    candidatas.push({ t, prio: r() });
  }
  // desbaste por vizinhança (grade de `espacamento`)
  const e = CFG.espacamento;
  const grade = new Map<string, { t: T; prio: number }[]>();
  const chave = (x: number, z: number) => `${Math.floor(x / e)},${Math.floor(z / e)}`;
  for (const c of candidatas) {
    const k = chave(c.t.x, c.t.z);
    const l = grade.get(k);
    if (l) l.push(c);
    else grade.set(k, [c]);
  }
  const ficam = new Set<T>();
  for (const c of candidatas) {
    const gx = Math.floor(c.t.x / e);
    const gz = Math.floor(c.t.z / e);
    let ok = true;
    for (let a = -1; a <= 1 && ok; a++)
      for (let b = -1; b <= 1 && ok; b++)
        for (const o of grade.get(`${gx + a},${gz + b}`) ?? [])
          if (o !== c && o.prio > c.prio && (o.t.x - c.t.x) ** 2 + (o.t.z - c.t.z) ** 2 < e * e) ok = false;
    if (ok) ficam.add(c.t);
  }
  console.info(`árvores ${rotulo}: setores revisados ${candidatas.length + excluidas} → ${ficam.size} (zonas tiraram ${excluidas}, espaçamento ${candidatas.length - ficam.size}); fora ${fora.length}`);
  // mesma ordem da lista de entrada
  const foraSet = new Set(fora);
  return spots.filter(t => foraSet.has(t) || ficam.has(t));
}
