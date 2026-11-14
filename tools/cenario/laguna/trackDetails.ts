// Cópia adaptada para Laguna Seca (tools/cenario/vite.config.ts troca o módulo do web por este só com
// TRACK=laguna-seca). Trechos em metros numa volta de LAP m; muro de concreto com alambrado como padrão (LMU),
// placas fictícias com nomes da região, pilhas de pneu por fora das curvas fechadas e as passarelas reais.
// Detalhes da pista no estilo da Interlagos de 2026 (referência: vídeo de volta do Le Mans Ultimate):
// muros com placas por trecho, barreiras azuis acolchoadas, alambrado alto com a ponta virada para a pista,
// outdoors atrás das curvas, passarela sobre a reta, grid de largada pintado e remendos no asfalto.
// As marcas das placas são fictícias.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';

/** volta de referência das tabelas (m): Laguna Seca */
const LAP = 3598;

export type AdScheme = 'verde' | 'vermelho' | 'amarelo' | 'branco' | 'azul';
type Kind = 'rail' | 'wall' | 'tecpro' | 'none';

interface Zone {
  s0: number;
  s1: number;
  /** lado da barreira (+1 = direita de quem corre); sem lado = o de fora da curva */
  side?: -1 | 1;
  kind: 'wall' | 'tecpro';
  ads: AdScheme;
  fence?: boolean;
  /** outdoor grande atrás do muro */
  billboard?: boolean;
}

/**
 * Trechos (s em metros a partir da linha de chegada, Interlagos tem 4.300 m) e o tipo de barreira do lado de
 * fora, como no vídeo de referência: placas verdes no S do Senna, vermelhas na Curva do Sol, verde com
 * alambrado na Reta Oposta, barreira azul na Descida do Lago e na Ferradura, amarelas no Laranjinha, brancas
 * no Pinheirinho e no Bico de Pato, amarelo/azul no Mergulho, vermelhas da Junção até o fim da subida.
 */
const ZONES: Zone[] = [
  { s0: 380, s1: 600, kind: 'wall', ads: 'vermelho', billboard: true }, // Andretti Hairpin (fora = direita)
  { s0: 700, s1: 830, kind: 'wall', ads: 'azul', billboard: true }, // T3
  { s0: 1420, s1: 1600, kind: 'wall', ads: 'branco', billboard: true }, // T5
  { s0: 1850, s1: 1990, kind: 'wall', ads: 'verde' }, // T6
  { s0: 2380, s1: 2470, side: -1, kind: 'wall', ads: 'branco', billboard: true }, // freada do Corkscrew
  { s0: 2620, s1: 2780, kind: 'wall', ads: 'amarelo', billboard: true }, // Rainey Curve
  { s0: 2940, s1: 3060, kind: 'wall', ads: 'azul', billboard: true }, // T10
  { s0: 3220, s1: 3320, kind: 'wall', ads: 'vermelho', billboard: true } // T11
];

const AD_SETS: Record<AdScheme, [string, string, string][]> = {
  verde: [['#0c5a36', '#ffffff', 'LAGUNA SECA'], ['#0c5a36', '#d9c47c', 'MONTEREY'], ['#0c5a36', '#ffffff', 'SALINAS VALLEY'], ['#0c5a36', '#ffffff', 'GT3 TIME ATTACK']],
  vermelho: [['#c8102e', '#ffffff', 'TURBO 16V'], ['#c8102e', '#ffffff', 'PACIFIC OIL'], ['#111111', '#ffffff', 'TURBO 16V'], ['#c8102e', '#ffffff', 'COAST TIRES']],
  amarelo: [['#f2c500', '#c8102e', 'GOLDEN STATE'], ['#f2c500', '#111111', 'CARGO WEST'], ['#f2c500', '#c8102e', 'GOLDEN STATE'], ['#f2c500', '#111111', 'CARGO WEST']],
  branco: [['#f4f4f2', '#1d4fa3', 'RACE CONTROL'], ['#f4f4f2', '#e2231a', 'MONTEREY BAY'], ['#f4f4f2', '#1d4fa3', 'RACE CONTROL'], ['#f4f4f2', '#ef7d00', 'CARMEL']],
  azul: [['#0f2f6e', '#ffffff', 'BLUE COAST'], ['#1a2e6e', '#f2c500', 'BIG SUR'], ['#0f2f6e', '#ffffff', 'BLUE COAST'], ['#1a2e6e', '#ffffff', 'BIG SUR']]
};

/**
 * Faixa contínua de patrocinador no topo dos muros e barreiras (como a DHL amarela e a Goodyear azul do LMU):
 * cor saturada, um logo fictício repetido a cada 8 m, sem junta. Uma marca por esquema de cor do trecho.
 */
const TOPPERS: Record<AdScheme, [string, string, string]> = {
  amarelo: ['#ffcc00', '#d40511', 'GOLDEN STATE'],
  azul: ['#0f3c96', '#ffffff', 'BLUE COAST'],
  vermelho: ['#d0101e', '#ffffff', 'TURBO 16V'],
  branco: ['#ffffff', '#1d4fa3', 'RACE CONTROL'],
  verde: ['#0c7a3e', '#ffffff', 'LAGUNA SECA']
};
function topperCanvas(scheme: AdScheme): HTMLCanvasElement {
  const [bg, fg, text] = TOPPERS[scheme];
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 64;
  const g = c.getContext('2d')!;
  g.fillStyle = bg;
  g.fillRect(0, 0, 1024, 64);
  g.fillStyle = fg;
  g.font = '900 italic 44px Arial';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  // dois logos por tile (a cada 4 m) e um filete fino em cima e embaixo
  g.fillText(text, 256, 34, 440);
  g.fillText(text, 768, 34, 440);
  g.fillRect(0, 0, 1024, 3);
  g.fillRect(0, 61, 1024, 3);
  return c;
}

/** Placas lado a lado (cada uma com fundo, texto e uma faixa de destaque embaixo). */
export function adCanvas(scheme: AdScheme, panels: number, pw: number, ph: number): HTMLCanvasElement {
  const set = AD_SETS[scheme];
  const c = document.createElement('canvas');
  c.width = pw * panels;
  c.height = ph;
  const g = c.getContext('2d')!;
  for (let k = 0; k < panels; k++) {
    const [bg, fg, text] = set[k % set.length];
    const x = k * pw;
    g.fillStyle = bg;
    g.fillRect(x, 0, pw, ph);
    g.fillStyle = fg;
    g.globalAlpha = 0.85;
    g.fillRect(x, ph * 0.86, pw, ph * 0.06);
    g.globalAlpha = 1;
    g.font = `900 italic ${Math.round(ph * 0.48)}px Arial`;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(text, x + pw / 2, ph * 0.46, pw * 0.9);
    // junta entre placas
    g.fillStyle = 'rgba(0,0,0,0.35)';
    g.fillRect(x, 0, 2, ph);
  }
  return c;
}

export function tex(c: HTMLCanvasElement, renderer: THREE.WebGLRenderer, wrap = true): THREE.Texture {
  const t = new THREE.CanvasTexture(c);
  if (wrap) t.wrapS = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy();
  return t;
}

/** Barreira acolchoada azul (módulos de 1,5 m com a borda de cima arredondada e o nome da pista). */
function tecproTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 96;
  const g = c.getContext('2d')!;
  for (let k = 0; k < 4; k++) {
    const x = k * 128;
    const grad = g.createLinearGradient(0, 0, 0, 96);
    grad.addColorStop(0, '#5d86d1');
    grad.addColorStop(0.12, '#2457b3');
    grad.addColorStop(0.8, '#1d4a99');
    grad.addColorStop(1, '#122f63');
    g.fillStyle = grad;
    g.fillRect(x, 0, 128, 96);
    // laterais arredondadas do módulo
    const side = g.createLinearGradient(x, 0, x + 128, 0);
    side.addColorStop(0, 'rgba(0,0,0,0.45)');
    side.addColorStop(0.08, 'rgba(0,0,0,0)');
    side.addColorStop(0.92, 'rgba(0,0,0,0)');
    side.addColorStop(1, 'rgba(0,0,0,0.45)');
    g.fillStyle = side;
    g.fillRect(x, 0, 128, 96);
    g.fillStyle = k % 2 ? '#ffffff' : '#f2c500';
    g.font = '900 italic 26px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(k % 2 ? 'INTERLAGOS' : 'PNEUS VILA', x + 64, 50, 116);
  }
  // marcas de pneu de quem encostou
  const rand = mulberry32(5);
  for (let i = 0; i < 14; i++) {
    g.fillStyle = `rgba(15,15,15,${0.1 + rand() * 0.25})`;
    g.fillRect(rand() * 512, 60 + rand() * 30, 20 + rand() * 80, 2 + rand() * 5);
  }
  return tex(c, renderer);
}

function fenceTexture(): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  g.strokeStyle = 'rgba(200, 205, 210, 0.85)';
  g.lineWidth = 2;
  g.beginPath();
  g.moveTo(0, 0);
  g.lineTo(64, 64);
  g.moveTo(64, 0);
  g.lineTo(0, 64);
  g.stroke();
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

function tyreStackTexture(): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 128;
  c.height = 96;
  const g = c.getContext('2d')!;
  for (let k = 0; k < 3; k++) {
    const y = k * 32;
    const grad = g.createLinearGradient(0, y, 0, y + 32);
    grad.addColorStop(0, '#0c0c0c');
    grad.addColorStop(0.25, '#2a2a2a');
    grad.addColorStop(0.5, '#323232');
    grad.addColorStop(0.75, '#262626');
    grad.addColorStop(1, '#0a0a0a');
    g.fillStyle = grad;
    g.fillRect(0, y, 128, 32);
    g.fillStyle = 'rgba(0,0,0,0.35)';
    for (let x = 0; x < 128; x += 6) g.fillRect(x, y + 8, 2, 16); // sulcos
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = THREE.RepeatWrapping;
  t.repeat.set(3, 1);
  return t;
}

/** Tipo de barreira, placas e alambrado de cada lado em cada amostra. */
export function barrierLayout(track: Track) {
  const S = track.samples;
  const N = S.length;
  const L = track.length;
  const k = L / LAP;
  const mainStraight = (i: number) => S[i].s > L - 270 || S[i].s < 150 * k;
  // Laguna (LMU): muro de concreto com alambrado na volta toda
  const kind: Record<-1 | 1, Kind[]> = { [-1]: new Array(N).fill('wall'), [1]: new Array(N).fill('wall') };
  const ads: Record<-1 | 1, (AdScheme | null)[]> = { [-1]: new Array(N).fill(null), [1]: new Array(N).fill(null) };
  const fence: Record<-1 | 1, boolean[]> = { [-1]: new Array(N).fill(true), [1]: new Array(N).fill(true) };
  for (let i = 0; i < N; i++) {
    if (!mainStraight(i)) continue;
    for (const side of [-1, 1] as const) {
      kind[side][i] = 'wall';
      ads[side][i] = side < 0 ? 'branco' : 'verde'; // muro dos boxes / muro da arquibancada
      fence[side][i] = true;
    }
  }
  // Laguna: à esquerda, da entrada dos boxes até a saída na Andretti, a pit lane (OSM) passa por dentro do muro da
  // física; o muro/alambrado genérico ali cortaria a pit lane: sem barreira (o muro dos boxes vem do OSM)
  for (let i = 0; i < N; i++) {
    const sm = S[i].s / k;
    if (sm > 3190 || sm < 570) {
      kind[-1][i] = 'none';
      ads[-1][i] = null;
      fence[-1][i] = false;
    }
  }
  const zones = ZONES.map(z => {
    const i0 = Math.round((z.s0 * k) / STEP);
    const i1 = Math.round((z.s1 * k) / STEP);
    let curv = 0;
    for (let i = i0; i < i1; i++) curv += S[i % N].curv;
    const side: -1 | 1 = z.side ?? (curv > 0 ? -1 : 1); // curva à direita: fora é a esquerda
    for (let i = i0; i < i1; i++) {
      const j = i % N;
      kind[side][j] = z.kind;
      ads[side][j] = z.kind === 'wall' ? z.ads : null;
      fence[side][j] = !!z.fence;
    }
    return { ...z, side, i0, i1 };
  });
  return { kind, ads, fence, zones };
}

/**
 * Barreiras: muro de concreto com placas (e alambrado) onde o trecho pede, barreira azul acolchoada nas
 * curvas de fora da Descida do Lago e da Ferradura, guard-rail duplo no resto; pilhas de pneu onde o escape
 * é largo e o lado é de guard-rail.
 */
export function buildBarriers(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, concreteMat: THREE.Material) {
  const S = track.samples;
  const N = S.length;
  const lay = barrierLayout(track);

  /**
   * faixa ao longo do muro de (h0, recuo0) a (h1, recuo1), onde include(i); recuo > 0 = para dentro da pista.
   * Com h0 = h1 vira uma faixa horizontal (tampa); com recuos diferentes, inclinada (ponta do alambrado).
   */
  const strip = (side: -1 | 1, h0: number, in0: number, h1: number, in1: number, include: (i: number) => boolean, mat: THREE.Material, vScale: number, shadow = true) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let k = 0; k <= N; k++) {
      const i = k % N;
      if (!include(i)) {
        prev = -1;
        continue;
      }
      const s = S[i];
      const wall = side < 0 ? s.wallL : s.wallR;
      const base = pos.length / 3;
      for (const [h, inset, u] of [[h0, in0, 0], [h1, in1, 1]]) {
        v.copy(s.p).addScaledVector(s.r, side * (wall - inset));
        v.y += h;
        pos.push(v.x, v.y, v.z);
        // do lado direito a face fica virada ao contrário: inverte o sentido da textura para o texto não espelhar
        uv.push((side < 0 ? 1 : -1) * ((k * STEP) / vScale), u);
      }
      if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
      prev = base;
    }
    if (!idx.length) return;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, mat);
    m.castShadow = shadow;
    m.receiveShadow = true;
    group.add(m);
  };

  const railMat = new THREE.MeshStandardMaterial({ color: 0xc2c6ca, metalness: 0.3, roughness: 0.55, side: THREE.DoubleSide });
  const capMat = new THREE.MeshStandardMaterial({ color: 0xbdbcb6, roughness: 0.9, side: THREE.DoubleSide });
  const fenceTex = fenceTexture();
  const fenceMat = new THREE.MeshStandardMaterial({ map: fenceTex, transparent: true, alphaTest: 0.3, side: THREE.DoubleSide, metalness: 0.5, roughness: 0.5 });
  const tecMat = new THREE.MeshStandardMaterial({ map: tecproTexture(renderer), roughness: 0.55, side: THREE.DoubleSide });
  const tecTop = new THREE.MeshStandardMaterial({ color: 0x2457b3, roughness: 0.55, side: THREE.DoubleSide });
  const adMats = new Map<AdScheme, THREE.Material>();
  const adMat = (a: AdScheme) => {
    if (!adMats.has(a))
      adMats.set(a, new THREE.MeshStandardMaterial({ map: tex(adCanvas(a, 4, 256, 64), renderer), roughness: 0.55, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -1 }));
    return adMats.get(a)!;
  };

  const topMats = new Map<AdScheme, THREE.Material>();
  const topMat = (a: AdScheme) => {
    if (!topMats.has(a)) topMats.set(a, new THREE.MeshStandardMaterial({ map: tex(topperCanvas(a), renderer), roughness: 0.45, side: THREE.DoubleSide }));
    return topMats.get(a)!;
  };
  /** esquema da faixa de cima em cada amostra: o do trecho; nas barreiras azuis, a amarela */
  const topperAt = (side: -1 | 1, i: number): AdScheme | null =>
    lay.kind[side][i] === 'wall' ? lay.ads[side][i] ?? 'amarelo' : lay.kind[side][i] === 'tecpro' ? 'amarelo' : null;
  const cableMat = new THREE.MeshStandardMaterial({ color: 0x3c4146, metalness: 0.6, roughness: 0.45, side: THREE.DoubleSide });

  for (const side of [-1, 1] as const) {
    const K = lay.kind[side];
    const rail = (i: number) => K[i] === 'rail';
    const wall = (i: number) => K[i] === 'wall';
    const tec = (i: number) => K[i] === 'tecpro';
    const fence = (i: number) => lay.fence[side][i];
    strip(side, 0.4, 0, 0.72, 0, rail, railMat, 4);
    strip(side, 0.85, 0, 1.17, 0, rail, railMat, 4);
    // muro: face, tampa de 25 cm e as placas na face que dá para a pista
    strip(side, 0, 0, 1.15, 0, wall, concreteMat, 4);
    strip(side, 1.15, 0, 1.15, -0.25, wall, capMat, 4, false);
    for (const a of Object.keys(AD_SETS) as AdScheme[]) {
      strip(side, 0.18, 0.02, 0.98, 0.02, i => wall(i) && lay.ads[side][i] === a, adMat(a), 48, false);
    }
    // barreira azul: 1 m de altura, 60 cm de espessura
    strip(side, 0, 0, 1.0, 0, tec, tecMat, 6);
    strip(side, 1.0, 0, 1.0, -0.6, tec, tecTop, 6, false);
    // faixa de patrocinador em cima do muro (45 cm) e da barreira azul
    for (const a of Object.keys(TOPPERS) as AdScheme[]) {
      strip(side, 1.17, -0.12, 1.62, -0.12, i => wall(i) && !fence(i) && topperAt(side, i) === a, topMat(a), 8, false);
      strip(side, 1.0, -0.3, 1.45, -0.3, i => tec(i) && topperAt(side, i) === a, topMat(a), 8, false);
    }
    // alambrado: vertical até 4,2 m e a ponta inclinada para a pista
    strip(side, 1.15, 0, 4.2, 0, fence, fenceMat, 0.6, false);
    strip(side, 4.2, 0, 5.0, 0.7, fence, fenceMat, 0.6, false);
    // cabos de aço do alambrado (bem visíveis no LMU): três horizontais e um no alto da ponta
    for (const h of [1.9, 3.0, 4.15]) strip(side, h, -0.03, h + 0.035, -0.03, fence, cableMat, 4, false);
    strip(side, 4.95, 0.66, 4.99, 0.68, fence, cableMat, 4, false);
  }

  // postes: guard-rail a cada 4 m; alambrado a cada 8 m com o braço inclinado em cima
  const postGeo = new THREE.BoxGeometry(0.1, 1, 0.1);
  postGeo.translate(0, 0.5, 0);
  const postMat = new THREE.MeshStandardMaterial({ color: 0x80858a, metalness: 0.6, roughness: 0.5 });
  const posts = new THREE.InstancedMesh(postGeo, postMat, N * 2);
  const fencePostMat = new THREE.MeshStandardMaterial({ color: 0x4a4f55, metalness: 0.6, roughness: 0.45 });
  const fencePosts = new THREE.InstancedMesh(postGeo, fencePostMat, N);
  const arms = new THREE.InstancedMesh(postGeo, fencePostMat, N);
  let fp = 0;
  const m = new THREE.Matrix4();
  const sc = new THREE.Vector3();
  const q = new THREE.Quaternion();
  const q0 = new THREE.Quaternion();
  const p = new THREE.Vector3();
  let n = 0;
  let a = 0;
  for (let i = 0; i < N; i += 2) {
    const s = S[i];
    for (const side of [-1, 1] as const) {
      const tall = lay.fence[side][i];
      const rail = lay.kind[side][i] === 'rail';
      if (tall ? i % 4 : !rail) continue;
      const off = side * ((side < 0 ? s.wallL : s.wallR) + 0.08);
      p.set(s.p.x + s.r.x * off, s.p.y + s.r.y * off, s.p.z + s.r.z * off);
      if (tall) {
        m.compose(p, q0, sc.set(1.7, 4.3, 1.7));
        fencePosts.setMatrixAt(fp++, m);
      } else {
        m.compose(p, q0, sc.set(1, 1.2, 1));
        posts.setMatrixAt(n++, m);
      }
      if (tall) {
        // braço de 1,05 m saindo do topo, inclinado ~40° para dentro da pista (girar em torno de t leva o
        // topo para +r; para dentro é -lado·r)
        p.y += 4.25;
        q.setFromAxisAngle(s.t, -side * 0.7);
        m.compose(p, q, sc.set(1.5, 1.05, 1.5));
        arms.setMatrixAt(a++, m);
      }
    }
  }
  posts.count = n;
  fencePosts.count = fp;
  arms.count = a;
  group.add(posts, fencePosts, arms);

  // pilhas de pneu (3 de altura) no guard-rail onde o escape é largo: as zonas de freada forte
  const tyreGeo = new THREE.CylinderGeometry(0.39, 0.39, 0.72, 10);
  tyreGeo.translate(0, 0.36, 0);
  const tyreMat = new THREE.MeshStandardMaterial({ map: tyreStackTexture(), roughness: 0.95 });
  const tyres = new THREE.InstancedMesh(tyreGeo, tyreMat, 2000);
  const UP = new THREE.Vector3(0, 1, 0);
  let t = 0;
  for (let i = 0; i < N && t < 2000; i++) {
    const s = S[i];
    for (const side of [-1, 1] as const) {
      // Laguna: barreira de pneus na frente do muro, por fora das curvas fechadas (raio < 80 m)
      const c = S[i].curv;
      if (Math.abs(c) < 1 / 80 || side !== (c > 0 ? -1 : 1) || t >= 1998 || lay.kind[side][i] === 'none') continue;
      const off = side * ((side < 0 ? s.wallL : s.wallR) - 0.45);
      for (const along of [-0.5, 0.5]) {
        p.set(s.p.x + s.r.x * off + s.t.x * along, s.p.y + s.r.y * off, s.p.z + s.r.z * off + s.t.z * along);
        m.compose(p, q.setFromAxisAngle(UP, i + along), sc.set(1, 1, 1));
        tyres.setMatrixAt(t++, m);
      }
    }
  }
  tyres.count = t;
  // sem sombra própria: o InstancedMesh inteiro entraria no mapa de sombra a cada quadro
  group.add(tyres);

  buildBillboards(track, group, renderer, lay.zones);
}

/** Outdoors de 14 × 3,5 m atrás do muro, no meio de cada curva com placas, virados para quem chega. */
function buildBillboards(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, zones: (Zone & { side: -1 | 1; i0: number; i1: number })[]) {
  const S = track.samples;
  const N = S.length;
  const legMat = new THREE.MeshStandardMaterial({ color: 0x5b6066, metalness: 0.5, roughness: 0.5 });
  const backMat = new THREE.MeshStandardMaterial({ color: 0x8a8d90, roughness: 0.8 });
  const tmp = new THREE.Vector3();
  zones.forEach((z, k) => {
    if (!z.billboard) return;
    const i = Math.round((z.i0 + z.i1) / 2) % N;
    const s = S[i];
    const wall = z.side < 0 ? s.wallL : s.wallR;
    const base = s.p.clone().addScaledVector(s.r, z.side * (wall + 7));
    // não pode cair sobre outro trecho da pista
    const loc = track.locate(tmp.copy(base));
    if (loc && Math.abs(loc.i - i) > 20 && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + 4) return;
    const set = AD_SETS[z.ads];
    const c = adCanvas(z.ads, 1, 512, 128);
    // um texto diferente por outdoor
    if (set.length > 1) {
      const [bg, fg, text] = set[k % set.length];
      const g = c.getContext('2d')!;
      g.fillStyle = bg;
      g.fillRect(0, 0, 512, 128);
      g.fillStyle = fg;
      g.fillRect(0, 110, 512, 8);
      g.font = '900 italic 62px Arial';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(text, 256, 58, 470);
    }
    const face = new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.5 });
    const board = new THREE.Group();
    const panel = new THREE.Mesh(new THREE.BoxGeometry(14, 3.5, 0.2), [backMat, backMat, backMat, backMat, face, backMat]);
    panel.position.y = 4.6;
    board.add(panel);
    for (const x of [-4.5, 4.5]) {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.3, 3, 0.3), legMat);
      leg.position.set(x, 1.5, -0.3);
      board.add(leg);
    }
    board.traverse(o => (o.castShadow = true));
    board.position.copy(base).setY(s.p.y - 0.3);
    // virado para quem vem: entre o "para trás" da pista e o "para dentro"
    const look = s.t.clone().multiplyScalar(-1).addScaledVector(s.r, -z.side * 0.8).setY(0).normalize();
    board.lookAt(board.position.clone().add(look));
    group.add(board);
  });
}

/**
 * Pontes reais de Laguna, nas posições das estruturas vistas no satélite (as sombras caem ~10 m ao norte) e no
 * visual do LMU, com nomes genéricos (nenhuma marca real):
 *   s ≈ 912   arco treliçado escuro com faixa vermelha (reta entre a T3 e a T4)
 *   s ≈ 1376  passarela treliçada (antes da T5)
 *   s ≈ 1824  viaduto de estrada, largo, de concreto (antes da T6)
 *   s ≈ 2602  passarela treliçada com a placa branca "LAGUNA SECA" (chegada da Rainey)
 *   s ≈ −8    passarela logo antes da linha de chegada
 * Todas "essenciais" (aparecem também no Mínimo): são referência de pilotagem.
 */
type BridgeKind = 'arch' | 'truss' | 'road';
const BRIDGES: [number, BridgeKind, string, string][] = [
  [912, 'arch', 'LAGUNA SECA', 'MONTEREY'],
  [1376, 'truss', 'MONTEREY COUNTY', ''],
  [1824, 'road', '', ''],
  [2602, 'truss', 'LAGUNA SECA', 'RACEWAY'],
  [LAP - 8, 'truss', 'LAGUNA SECA', '']
];

export function buildBridge(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const mats = {
    steel: new THREE.MeshStandardMaterial({ color: 0x3b3f45, metalness: 0.5, roughness: 0.5 }),
    light: new THREE.MeshStandardMaterial({ color: 0xa9adb1, metalness: 0.45, roughness: 0.5 }),
    concrete: new THREE.MeshStandardMaterial({ color: 0xc9c6bd, roughness: 0.9 })
  };
  for (const [at, kind, t1, t2] of BRIDGES) buildOneBridge(track, group, renderer, at, kind, t1, t2, mats);
}

/** placa com uma ou duas linhas de texto */
export function signMaterial(renderer: THREE.WebGLRenderer, t1: string, t2: string, bg: string, fg: string, accent: string) {
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 192;
  const g = c.getContext('2d')!;
  g.fillStyle = bg;
  g.fillRect(0, 0, 1024, 192);
  g.fillStyle = accent;
  g.fillRect(0, 172, 1024, 20);
  g.fillStyle = fg;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.font = '900 italic ' + (t2 ? 78 : 104) + 'px Arial';
  g.fillText(t1, 512, t2 ? 66 : 92, 980);
  if (t2) {
    g.font = '700 54px Arial';
    g.fillText(t2, 512, 138, 900);
  }
  return new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.5 });
}

function buildOneBridge(
  track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, at: number, kind: BridgeKind, t1: string, t2: string,
  mats: { steel: THREE.Material; light: THREE.Material; concrete: THREE.Material }
) {
  const S = track.samples;
  const N = S.length;
  const s = S[((Math.round((at * track.length) / LAP / STEP) % N) + N) % N];
  const span = s.wallL + s.wallR + 6;
  const g = new THREE.Group();
  const _a = new THREE.Vector3();
  const _m = new THREE.Vector3();
  /** viga de seção t × t entre dois pontos (coordenadas da ponte: x atravessa, y sobe, z ao longo da pista) */
  const beam = (a: THREE.Vector3, b: THREE.Vector3, t: number, mat: THREE.Material) => {
    const len = a.distanceTo(b);
    const m = new THREE.Mesh(new THREE.BoxGeometry(t, len, t), mat);
    m.position.copy(_m.addVectors(a, b).multiplyScalar(0.5));
    m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), _a.subVectors(b, a).normalize());
    g.add(m);
  };
  const box = (w: number, h: number, d: number, x: number, y: number, z: number, mat: THREE.Material | THREE.Material[]) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    m.position.set(x, y, z);
    g.add(m);
    return m;
  };
  const V = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);
  const half = span / 2;

  if (kind === 'arch') {
    // arco de treliça: dois arcos (externo e interno) em cada face, ligados em ziguezague; faixa vermelha no meio
    const H = 16;
    const SEG = 18;
    for (const z of [-1.4, 1.4]) {
      const outer: THREE.Vector3[] = [];
      const inner: THREE.Vector3[] = [];
      for (let k = 0; k <= SEG; k++) {
        const th = (Math.PI * k) / SEG;
        outer.push(V(half * Math.cos(th), H * Math.sin(th), z));
        inner.push(V((half - 1.6) * Math.cos(th), (H - 1.5) * Math.sin(th), z));
      }
      for (let k = 0; k < SEG; k++) {
        beam(outer[k], outer[k + 1], 0.45, mats.steel);
        beam(inner[k], inner[k + 1], 0.35, mats.steel);
        beam(k % 2 ? outer[k] : inner[k], k % 2 ? inner[k + 1] : outer[k + 1], 0.18, mats.steel);
      }
    }
    for (let k = 1; k < SEG; k += 3) {
      const th = (Math.PI * k) / SEG;
      beam(V(half * Math.cos(th), H * Math.sin(th), -1.4), V(half * Math.cos(th), H * Math.sin(th), 1.4), 0.2, mats.steel);
    }
    const sign = signMaterial(renderer, t1, t2, '#c8102e', '#ffffff', '#1b1b1b');
    box(span * 0.5, 2.6, 0.35, 0, H * 0.6, 0, [mats.steel, mats.steel, mats.steel, mats.steel, sign, sign]);
    for (const x of [-half * 0.25, half * 0.25]) beam(V(x, H * 0.6 + 1.3, 0), V(x * 1.2, H * 0.92, 0), 0.08, mats.steel);
    for (const x of [-half, half]) box(2.4, 1.2, 4, x, 0.6, 0, mats.concrete);
  } else if (kind === 'truss') {
    // passarela: tabuleiro, duas faces de treliça (banzos, montantes e diagonais), torres de escada nas pontas
    const h = 7.2;
    const hh = 2.3;
    box(span, 0.5, 2.8, 0, h, 0, mats.light);
    const n = Math.max(4, Math.round(span / 3));
    for (const z of [-1.35, 1.35]) {
      beam(V(-half, h + 0.25, z), V(half, h + 0.25, z), 0.25, mats.light);
      beam(V(-half, h + hh, z), V(half, h + hh, z), 0.25, mats.light);
      for (let k = 0; k <= n; k++) {
        const x = -half + (span * k) / n;
        beam(V(x, h + 0.25, z), V(x, h + hh, z), 0.14, mats.light);
        if (k < n) {
          const x2 = -half + (span * (k + 1)) / n;
          beam(k % 2 ? V(x, h + 0.25, z) : V(x, h + hh, z), k % 2 ? V(x2, h + hh, z) : V(x2, h + 0.25, z), 0.1, mats.light);
        }
      }
    }
    for (let k = 0; k <= n; k += 2) {
      const x = -half + (span * k) / n;
      beam(V(x, h + hh, -1.35), V(x, h + hh, 1.35), 0.12, mats.light);
    }
    if (t1) {
      const sign = signMaterial(renderer, t1, t2, '#f4f4f2', '#14306b', '#c8102e');
      const w = Math.min(16, span * 0.45);
      box(w, w * 0.19, 0.25, 0, h + hh + 0.4 + w * 0.095, 0, [mats.light, mats.light, mats.light, mats.light, sign, sign]);
    }
    for (const x of [-half - 1.6, half + 1.6]) box(3.2, h + 2.6, 3.6, x, (h + 2.6) / 2, 0, mats.concrete);
  } else {
    // viaduto de estrada: tabuleiro largo de concreto com guarda-corpo e pilares nas pontas
    const h = 7.6;
    box(span, 1.4, 10, 0, h, 0, mats.concrete);
    for (const z of [-4.8, 4.8]) box(span, 1.0, 0.3, 0, h + 1.2, z, mats.concrete);
    for (const x of [-half - 0.8, half + 0.8]) box(1.6, h, 9, x, h / 2, 0, mats.concrete);
  }
  g.traverse(o => {
    o.castShadow = true;
    o.receiveShadow = true;
    o.userData.essential = true;
  });
  g.position.copy(s.p).addScaledVector(new THREE.Vector3(s.r.x, 0, s.r.z).normalize(), (s.wallR - s.wallL) / 2);
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(new THREE.Vector3(s.r.x, 0, s.r.z).normalize(), new THREE.Vector3(0, 1, 0), new THREE.Vector3(-s.t.x, 0, -s.t.z).normalize()) /* em pé, mesmo com camber */);
  group.add(g);
}

/** Faixa com textura ao longo da pista (u atravessa de -wl a wr, v em metros/vScale), onde include(i). */
function overlay(track: Track, lift: number, vScale: number, include: (i: number) => boolean, mat: THREE.Material, widen = 0) {
  const S = track.samples;
  const N = S.length;
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  let prev = -1;
  for (let k = 0; k <= N; k++) {
    const i = k % N;
    if (!include(i)) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const base = pos.length / 3;
    for (const [off, u] of [[-s.wl - widen, 0], [s.wr + widen, 1]]) {
      v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, lift);
      pos.push(v.x, v.y, v.z);
      uv.push(u, (k * STEP) / vScale);
    }
    if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
    prev = base;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  const mesh = new THREE.Mesh(g, mat);
  mesh.receiveShadow = true;
  return mesh;
}

/** Grid de largada: 24 posições em ziguezague (a cada 8 m) atrás da linha de chegada. */
export function buildGrid(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const L = track.length;
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512; // 16 m de pista: duas posições
  const g = c.getContext('2d')!;
  g.fillStyle = 'rgba(236,236,230,0.92)';
  const ppm = 512 / 16;
  for (const [x0, x1, y] of [[0.1, 0.44, 2], [0.56, 0.9, 10]]) {
    const top = 512 - y * ppm; // a textura sobe com a pista (flipY)
    g.fillRect(x0 * 512, top, (x1 - x0) * 512, 0.25 * ppm); // linha da frente
    g.fillRect(x0 * 512, top, 0.18 * ppm, 1.6 * ppm); // pernas para trás
    g.fillRect(x1 * 512 - 0.18 * ppm, top, 0.18 * ppm, 1.6 * ppm);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const mat = new THREE.MeshStandardMaterial({ map: t, transparent: true, depthWrite: false, roughness: 0.8, polygonOffset: true, polygonOffsetFactor: -3 });
  const S = track.samples;
  const mesh = overlay(track, 0.005, 16, i => S[i].s > L - 200 && S[i].s < L - 12, mat);
  mesh.renderOrder = 3;
  group.add(mesh);
}

/**
 * Remendos de asfalto: retângulos de asfalto mais novo (um pouco mais escuro) com a junta selada em volta, e trincas transversais finas. Uma textura de 240 m repetida na volta inteira.
 */
export function buildPatches(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const W = 128;
  const H = 2048;
  const ppm = H / 240;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const rand = mulberry32(42);
  for (let k = 0; k < 12; k++) {
    // remendos de asfalto mais novo: só um pouco mais escuros, com a junta selada em volta
    const full = false; // Laguna: nada de faixa atravessando a pista inteira (parecia tracejado repetido)
    const x = full ? 0 : Math.floor(rand() * 2) * (W / 2) + (rand() - 0.5) * 12;
    const w = full ? W : W / 2 + rand() * 10;
    const y = rand() * H;
    const h = (4 + rand() * 18) * ppm;
    g.fillStyle = `rgba(10,10,12,${0.05 + rand() * 0.06})`;
    g.fillRect(x, y, w, h);
    g.strokeStyle = 'rgba(8,8,8,0.3)';
    g.lineWidth = 1.5;
    g.strokeRect(x + 1, y, w - 2, h);
  }
  for (let k = 0; k < 0; k++) {
    // Laguna: sem as trincas transversais; trinca seladas (piche) atravessando parte da pista
    const y = rand() * H;
    const x = rand() * W * 0.6;
    g.strokeStyle = `rgba(5,5,5,${0.3 + rand() * 0.3})`;
    g.lineWidth = 1;
    g.beginPath();
    g.moveTo(x, y);
    let cx = x;
    let cy = y;
    for (let j = 0; j < 6; j++) {
      cx += 4 + rand() * 10;
      cy += (rand() - 0.5) * 5;
      g.lineTo(cx, cy);
    }
    g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const mat = new THREE.MeshStandardMaterial({ map: t, transparent: true, depthWrite: false, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1 });
  const mesh = overlay(track, 0.006, 240, () => true, mat); // 6 mm: sem briga de profundidade no Godot
  mesh.renderOrder = 1;
  group.add(mesh);
  buildWear(track, group, renderer);
}

/**
 * Laguna (LMU): asfalto com bem mais variação de tom que o shader sozinho dá. Uma textura de 320 m que cobre a
 * largura toda (u 0 = borda esquerda, 1 = direita), por cima do asfalto e por baixo da borracha:
 *  - desgaste claro e esbranquiçado fora do traçado, mais forte perto das bordas (agregado exposto);
 *  - emendas longitudinais da pavimentação (faixa de piche escuro com uma borda clara), com interrupções;
 *  - remendos claros e escuros de tamanhos variados e manchas de óleo pequenas.
 */
function buildWear(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const W = 256;
  const H = 4096;
  const ppm = H / 320;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const rand = mulberry32(777);
  // desgaste claro: muitas manchas grandes e suaves, mais perto das bordas
  for (let k = 0; k < 200; k++) {
    const edge = rand() < 0.65;
    const u = edge ? (rand() < 0.5 ? rand() * 0.22 : 1 - rand() * 0.22) : rand();
    const x = u * W;
    const y = rand() * H;
    const rx = (0.05 + rand() * 0.12) * W;
    const ry = (2 + rand() * 14) * ppm;
    const gr = g.createRadialGradient(x, y, 0, x, y, 1);
    const a = (edge ? 0.05 : 0.025) + rand() * 0.04;
    gr.addColorStop(0, `rgba(205, 203, 196, ${a})`);
    gr.addColorStop(1, 'rgba(205, 203, 196, 0)');
    g.save();
    g.translate(x, y);
    g.scale(rx, ry);
    g.translate(-x, -y);
    g.fillStyle = gr;
    g.beginPath();
    g.arc(x, y, 1, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }
  // emendas longitudinais (duas faixas de pavimentação), com trechos interrompidos e leve sinuosidade
  for (const u0 of [0.36, 0.68]) {
    let y = 0;
    while (y < H) {
      const len = (8 + rand() * 40) * ppm;
      const off = (rand() - 0.5) * 0.02 * W;
      g.fillStyle = `rgba(14, 14, 15, ${0.22 + rand() * 0.2})`;
      g.fillRect(u0 * W + off, y, 1.6 + rand() * 1.4, len);
      g.fillStyle = `rgba(210, 208, 200, ${0.08 + rand() * 0.1})`;
      g.fillRect(u0 * W + off + 2.5, y, 3 + rand() * 4, len);
      y += len + (rand() < 0.3 ? (2 + rand() * 10) * ppm : 0);
    }
  }
  // remendos retangulares claros (asfalto velho) e escuros (novo), juntas seladas em volta
  for (let k = 0; k < 34; k++) {
    const light = rand() < 0.45;
    const x = rand() * W * 0.75;
    const w = (0.12 + rand() * 0.3) * W;
    const y = rand() * H;
    const h = (2 + rand() * 16) * ppm;
    g.fillStyle = light ? `rgba(196, 194, 188, ${0.05 + rand() * 0.07})` : `rgba(8, 8, 9, ${0.08 + rand() * 0.1})`;
    g.fillRect(x, y, w, h);
    g.strokeStyle = 'rgba(6, 6, 6, 0.35)';
    g.lineWidth = 1.5;
    g.strokeRect(x + 1, y, w - 2, h);
  }
  // manchas de óleo e pontos escuros
  for (let k = 0; k < 160; k++) {
    g.fillStyle = `rgba(10, 10, 12, ${0.08 + rand() * 0.18})`;
    g.beginPath();
    g.ellipse(rand() * W, rand() * H, 1 + rand() * 6, (0.3 + rand()) * ppm, 0, 0, Math.PI * 2);
    g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const mat = new THREE.MeshStandardMaterial({ map: t, transparent: true, depthWrite: false, roughness: 0.95, polygonOffset: true, polygonOffsetFactor: -1 });
  const mesh = overlay(track, 0.008, 320, () => true, mat);
  mesh.renderOrder = 1;
  group.add(mesh);
}
