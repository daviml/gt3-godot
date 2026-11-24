// Detalhes da pista no estilo da Interlagos de 2026 (referência: vídeo de volta do Le Mans Ultimate):
// muros com placas por trecho, barreiras azuis acolchoadas, alambrado alto com a ponta virada para a pista,
// outdoors atrás das curvas, passarela sobre a reta, grid de largada pintado e remendos no asfalto.
// As marcas das placas são fictícias.
//
// Fase 2B etapa F: todos os metros abaixo continuam escritos como na pista antiga ("s numa volta de 4.300 m", ou o s
// real antigo onde indicado) e passam por ./sNovo.ts (iNovo4300 / s4300 / sNovo): passarela, pórticos, saída e
// entrada dos boxes, Goodyear do Lago, muro da Ferradura, placas, telão etc. ficam no MESMO lugar físico de antes
// (não foram movidos para as âncoras medidas no satélite: isso é dos setores). A lateral segue a pista nova (bordas
// e muros medidos).
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import { addProp } from '../propsRegistry';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { phTexture } from '@web/render/textures';
import { TINTA } from './tintas';
import { perfilDe, type TipoBarreira } from './perfil';
import { dNovo4300, iNovo4300, L_ANTIGO, s4300, sNovo } from './sNovo';

export type AdScheme = 'verde' | 'vermelho' | 'amarelo' | 'branco' | 'azul' | 'avis';
type Kind = TipoBarreira;

/**
 * Outdoors grandes atrás do muro, no meio de cada trecho [s0, s1] (s numa volta de 4.300 m). `variante` escolhe o
 * texto do conjunto de placas (era o índice do trecho na antiga tabela ZONES; mantido para o resultado não mudar).
 * O tipo de barreira, as placas do muro e o alambrado de cada trecho estão no perfil lateral
 * (data/track/visual_profile.json, ./perfil.ts).
 */
interface Outdoor {
  s0: number;
  s1: number;
  side: -1 | 1;
  ads: AdScheme;
  variante: number;
}
const OUTDOORS: Outdoor[] = [
  { s0: 165, s1: 390, side: 1, ads: 'verde', variante: 0 },
  { s0: 540, s1: 1150, side: 1, ads: 'vermelho', variante: 3 },
  { s0: 1580, s1: 1800, side: -1, ads: 'azul', variante: 7 },
  { s0: 2140, s1: 2335, side: -1, ads: 'branco', variante: 10 },
  { s0: 2310, s1: 2480, side: 1, ads: 'branco', variante: 11 },
  { s0: 2480, s1: 2830, side: -1, ads: 'branco', variante: 12 }
];

const AD_SETS: Record<AdScheme, [string, string, string][]> = {
  verde: [['#006039', '#e8c44a', 'ROLEX'], ['#006039', '#e8c44a', 'ROLEX'], ['#006039', '#ffffff', 'ROLEX'], ['#006039', '#e8c44a', 'ROLEX']],
  vermelho: [['#d0101e', '#ffffff', 'MOTUL'], ['#d0101e', '#ffffff', 'MOTUL'], ['#d0101e', '#ffffff', 'MOTUL'], ['#d0101e', '#ffffff', 'MOTUL']],
  avis: [['#c8102e', '#ffffff', 'AVIS'], ['#c8102e', '#ffffff', 'AVIS'], ['#c8102e', '#ffffff', 'AVIS'], ['#c8102e', '#ffffff', 'AVIS']],
  amarelo: [['#ffcc00', '#d40511', 'DHL'], ['#ffcc00', '#d40511', 'DHL'], ['#ffcc00', '#111111', 'DHL'], ['#ffcc00', '#d40511', 'DHL']],
  branco: [['#f4f4f2', '#006039', 'ROLEX'], ['#f4f4f2', '#d0101e', 'MOTUL'], ['#f4f4f2', '#0f3c96', 'GOODYEAR'], ['#f4f4f2', '#d40511', 'DHL']],
  azul: [['#0f3c96', '#ffd200', 'GOODYEAR'], ['#0f3c96', '#ffd200', 'GOODYEAR'], ['#0f3c96', '#ffd200', 'GOODYEAR'], ['#0f3c96', '#ffffff', 'GOODYEAR']]
};

const TOPPERS: Record<AdScheme, [string, string, string]> = {
  amarelo: ['#ffcc00', '#d40511', 'DHL'],
  azul: ['#0f3c96', '#ffd200', 'GOODYEAR'],
  vermelho: ['#d0101e', '#ffffff', 'MOTUL'],
  avis: ['#c8102e', '#ffffff', 'AVIS'],
  branco: ['#ffffff', '#006039', 'ROLEX'],
  verde: ['#006039', '#e8c44a', 'ROLEX']
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
  return compensaLuz(c);
}

/**
 * Placas e barreiras com marca (MOTUL, DHL, GOODYEAR, ROLEX, AVIS): as cores de marca são as "de catálogo", mas a luz
 * de Interlagos no Godot (sol 3,4 × exposição 1,3 → AgX, ver ./tintas.ts) leva cor clara e saturada ao topo da curva:
 * o vermelho MOTUL saía rosa-salmão (254/109/105) onde o LMU mostra 195/45/72. Mesma causa das tintas do chão, com
 * correção global: a textura inteira é escurecida em luz linear por PLACA_GANHO (o tom de cada cor fica; só sai da
 * região que desbota). Calibrado no MOTUL da Reta Oposta e conferido no GOODYEAR e no DHL (Fase 1, 20/11/2026).
 */
export const PLACA_GANHO = 0.32;

/** Escurece o canvas em luz linear (× k), sem mudar o tom; devolve o mesmo canvas. */
export function compensaLuz(c: HTMLCanvasElement, k = PLACA_GANHO): HTMLCanvasElement {
  const g = c.getContext('2d')!;
  const img = g.getImageData(0, 0, c.width, c.height);
  const lut = new Uint8ClampedArray(256);
  for (let v = 0; v < 256; v++) {
    const x = v / 255;
    const lin = (x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4) * k;
    lut[v] = Math.round(255 * (lin <= 0.0031308 ? lin * 12.92 : 1.055 * lin ** (1 / 2.4) - 0.055));
  }
  for (let i = 0; i < img.data.length; i += 4) {
    img.data[i] = lut[img.data[i]];
    img.data[i + 1] = lut[img.data[i + 1]];
    img.data[i + 2] = lut[img.data[i + 2]];
  }
  g.putImageData(img, 0, 0);
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
  return compensaLuz(c);
}

export function tex(c: HTMLCanvasElement, renderer: THREE.WebGLRenderer, wrap = true): THREE.Texture {
  const t = new THREE.CanvasTexture(c);
  if (wrap) t.wrapS = t.wrapT = THREE.RepeatWrapping;
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
    g.fillStyle = '#ffe000';
    g.font = '900 italic 32px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText('GOODYEAR', x + 64, 50, 120);
  }
  // marcas de pneu de quem encostou
  const rand = mulberry32(5);
  for (let i = 0; i < 14; i++) {
    g.fillStyle = `rgba(15,15,15,${0.1 + rand() * 0.25})`;
    g.fillRect(rand() * 512, 60 + rand() * 30, 20 + rand() * 80, 2 + rand() * 5);
  }
  return tex(compensaLuz(c), renderer);
}

/** Barreira acolchoada verde ROLEX (módulos de 1,5 m com coroa e logo ROLEX dourados). */
function rolexPadTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 96;
  const g = c.getContext('2d')!;
  for (let k = 0; k < 4; k++) {
    const x = k * 128;
    const grad = g.createLinearGradient(0, 0, 0, 96);
    grad.addColorStop(0, '#1ca662');
    grad.addColorStop(0.14, '#0d7a45');
    grad.addColorStop(0.82, '#096337');
    grad.addColorStop(1, '#054424');
    g.fillStyle = grad;
    g.fillRect(x, 0, 128, 96);
    // sombreamento lateral de cada módulo acolchoado
    const side = g.createLinearGradient(x, 0, x + 128, 0);
    side.addColorStop(0, 'rgba(0,0,0,0.42)');
    side.addColorStop(0.08, 'rgba(0,0,0,0)');
    side.addColorStop(0.92, 'rgba(0,0,0,0)');
    side.addColorStop(1, 'rgba(0,0,0,0.42)');
    g.fillStyle = side;
    g.fillRect(x, 0, 128, 96);
    // coroa dourada + texto ROLEX bem nítidos
    const cx = x + 64;
    g.fillStyle = '#ffe45c';
    g.beginPath();
    g.moveTo(cx - 11, 33);
    g.lineTo(cx - 16, 15);
    g.lineTo(cx - 5, 24);
    g.lineTo(cx, 11);
    g.lineTo(cx + 5, 24);
    g.lineTo(cx + 16, 15);
    g.lineTo(cx + 11, 33);
    g.closePath();
    g.fill();
    g.font = '900 28px Georgia, serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText('ROLEX', cx, 62, 116);
  }
  const rand = mulberry32(7);
  for (let i = 0; i < 12; i++) {
    g.fillStyle = `rgba(10,15,10,${0.12 + rand() * 0.22})`;
    g.fillRect(rand() * 512, 76 + rand() * 18, 18 + rand() * 64, 2 + rand() * 4);
  }
  return tex(compensaLuz(c), renderer);
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

/** Tipo de barreira, placas e alambrado de cada lado em cada amostra (do perfil lateral, ./perfil.ts). */
export function barrierLayout(track: Track) {
  const p = perfilDe(track);
  const kind: Record<-1 | 1, Kind[]> = { [-1]: p.L.map(a => a.tipo), [1]: p.R.map(a => a.tipo) };
  const ads: Record<-1 | 1, (AdScheme | null)[]> = { [-1]: p.L.map(a => a.banner as AdScheme | null), [1]: p.R.map(a => a.banner as AdScheme | null) };
  const fence: Record<-1 | 1, boolean[]> = { [-1]: p.L.map(a => a.alambrado), [1]: p.R.map(a => a.alambrado) };
  const topo: Record<-1 | 1, boolean[]> = { [-1]: p.L.map(a => a.topo), [1]: p.R.map(a => a.topo) };
  const outdoors = OUTDOORS.map(o => ({ ...o, i0: iNovo4300(o.s0), i1: iNovo4300(o.s1) }));
  return { kind, ads, fence, topo, outdoors };
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
    // Fase 6: as barreiras azuis (só na Descida do Lago, trechos < 450 m) não são reconhecidas como barreira pelo
    // track_view.gd (material com textura) e sumiam no Mínimo; `ess_` = referência de pilotagem, sempre visível
    if (mat === tecMat || mat === tecTop) m.userData.essential = true;
    group.add(m);
  };

  const railMat = new THREE.MeshStandardMaterial({ color: 0xc2c6ca, metalness: 0.3, roughness: 0.55, side: THREE.DoubleSide });
  const capMat = new THREE.MeshStandardMaterial({ color: 0xbdbcb6, roughness: 0.9, side: THREE.DoubleSide });
  const fenceTex = fenceTexture();
  const fenceMat = new THREE.MeshStandardMaterial({ map: fenceTex, transparent: true, alphaTest: 0.3, side: THREE.DoubleSide, metalness: 0.5, roughness: 0.5 });
  const tecMat = new THREE.MeshStandardMaterial({ map: tecproTexture(renderer), roughness: 0.55, side: THREE.DoubleSide });
  const tecTop = new THREE.MeshStandardMaterial({ color: 0x2457b3, roughness: 0.55, side: THREE.DoubleSide });
  const rolexPadMat = new THREE.MeshStandardMaterial({
    map: rolexPadTexture(renderer),
    emissive: new THREE.Color(0x0a381e),
    emissiveIntensity: 0.35,
    roughness: 0.55,
    side: THREE.DoubleSide
  });
  const rolexTop = new THREE.MeshStandardMaterial({ color: 0x0b6e3e, roughness: 0.55, side: THREE.DoubleSide });
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
  /** esquema da faixa de cima em cada amostra: o do trecho; nas barreiras azuis, a amarela (sem ela onde topo: false) */
  const topperAt = (side: -1 | 1, i: number): AdScheme | null =>
    lay.kind[side][i] === 'wall' ? lay.ads[side][i] ?? 'amarelo' : lay.kind[side][i] === 'tecpro' && lay.topo[side][i] ? 'amarelo' : null;
  const cableMat = new THREE.MeshStandardMaterial({ color: 0x3c4146, metalness: 0.6, roughness: 0.45, side: THREE.DoubleSide });

  for (const side of [-1, 1] as const) {
    const K = lay.kind[side];
    const rail = (i: number) => K[i] === 'rail';
    const wall = (i: number) => K[i] === 'wall';
    const tec = (i: number) => K[i] === 'tecpro';
    const tec2 = (i: number) => K[i] === 'tecpro2';
    const rolexPad = (i: number) => K[i] === 'rolex_pad';
    const fence = (i: number) => lay.fence[side][i];
    strip(side, 0.4, 0, 0.72, 0, rail, railMat, 4);
    strip(side, 0.85, 0, 1.17, 0, rail, railMat, 4);
    // muro: face, tampa de 25 cm e as placas na face que dá para a pista
    strip(side, 0, 0, 1.15, 0, wall, concreteMat, 4);
    strip(side, 1.15, 0, 1.15, -0.25, wall, capMat, 4, false);
    for (const a of Object.keys(AD_SETS) as AdScheme[]) {
      strip(side, 0.18, 0.02, 0.98, 0.02, i => wall(i) && lay.ads[side][i] === a, adMat(a), 16, false);
    }
    // barreira azul simples: 1 m de altura, 60 cm de espessura
    strip(side, 0, 0, 1.0, 0, tec, tecMat, 6);
    strip(side, 1.0, 0, 1.0, -0.6, tec, tecTop, 6, false);
    // barreira azul dupla empilhada (0..1 m e 1..2 m), como na Descida do Lago do LMU
    strip(side, 0, 0, 1.0, 0, tec2, tecMat, 6);
    strip(side, 1.02, 0, 2.02, 0, tec2, tecMat, 6);
    strip(side, 2.02, 0, 2.02, -0.6, tec2, tecTop, 6, false);
    // barreira acolchoada verde ROLEX (1,1 m de altura, 55 cm de espessura) no S do Senna
    strip(side, 0, 0, 1.1, 0, rolexPad, rolexPadMat, 6);
    strip(side, 1.1, 0, 1.1, -0.55, rolexPad, rolexTop, 6, false);
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
      p.set(s.p.x + s.r.x * off, s.p.y, s.p.z + s.r.z * off);
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
      const run = side < 0 ? s.runL : s.runR;
      if (run < 8 || lay.kind[side][i] !== 'rail' || t >= 2000) continue;
      const off = side * ((side < 0 ? s.wallL : s.wallR) - 0.45);
      p.set(s.p.x + s.r.x * off, s.p.y, s.p.z + s.r.z * off);
      m.compose(p, q.setFromAxisAngle(UP, i), sc.set(1, 1, 1));
      tyres.setMatrixAt(t++, m);
    }
  }
  tyres.count = t;
  // sem sombra própria: o InstancedMesh inteiro entraria no mapa de sombra a cada quadro
  group.add(tyres);

  buildBillboards(track, group, renderer, lay.outdoors);
}

/** Outdoors de 14 × 3,5 m atrás do muro, no meio de cada curva com placas, virados para quem chega. */
function buildBillboards(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, outdoors: (Outdoor & { i0: number; i1: number })[]) {
  const S = track.samples;
  const N = S.length;
  const legMat = new THREE.MeshStandardMaterial({ color: 0x5b6066, metalness: 0.5, roughness: 0.5 });
  const backMat = new THREE.MeshStandardMaterial({ color: 0x8a8d90, roughness: 0.8 });
  const tmp = new THREE.Vector3();
  outdoors.forEach(z => {
    const k = z.variante;
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

/** Passarela ROLEX sobre a reta na freada do S do Senna + marcos visuais do LMU (pórtico MOTUL, prédio Senna, telão). */
export function buildBridge(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, heightAt?: (x: number, z: number) => number) {
  const S = track.samples;
  // Fase 4: no lugar medido no satélite (tabuleiro em s 292–297 da pista antiga = 292–297 da nova; o LMU mostra o
  // pilar esquerdo passando em s ≈ 285–290); antes ficava em s 264,6 (iNovo4300(265)), 30 m antes.
  const s = S[Math.round(294.6 / STEP) % S.length];
  const span = s.wallL + s.wallR + 10;
  const h = 6.8;
  const concrete = new THREE.MeshStandardMaterial({ color: 0x9aa0a6, roughness: 0.85 });
  // 6 logos ROLEX sem esticar desenhados direto no canvas (sem depender de KHR_texture_transform no GLB)
  const c = document.createElement('canvas');
  c.width = 2048;
  c.height = 192;
  const cg = c.getContext('2d')!;
  cg.fillStyle = '#0e9654';
  cg.fillRect(0, 0, 2048, 192);
  cg.fillStyle = '#f5d44c';
  cg.textAlign = 'center';
  cg.textBaseline = 'middle';
  cg.font = '900 50px Georgia, serif';
  const count = 6;
  const step = 2048 / count;
  for (let i = 0; i < count; i++) {
    const cx = (i + 0.5) * step;
    cg.beginPath();
    cg.moveTo(cx - 16, 60);
    cg.lineTo(cx - 24, 32);
    cg.lineTo(cx - 8, 46);
    cg.lineTo(cx, 26);
    cg.lineTo(cx + 8, 46);
    cg.lineTo(cx + 24, 32);
    cg.lineTo(cx + 16, 60);
    cg.closePath();
    cg.fill();
    cg.fillText('ROLEX', cx, 122);
  }
  const t = tex(compensaLuz(c), renderer, false);
  const ad = new THREE.MeshStandardMaterial({ map: t, roughness: 0.45 });
  const g = new THREE.Group();
  const deck = new THREE.Mesh(new THREE.BoxGeometry(span, 2.2, 2.4), [concrete, concrete, concrete, concrete, ad, ad]);
  deck.position.set(0, h, 0);
  g.add(deck);
  // viga inferior clara de concreto abaixo da faixa verde ROLEX (como no LMU)
  const sillMat = new THREE.MeshStandardMaterial({ color: 0xd8d6d0, roughness: 0.8 });
  const sill = new THREE.Mesh(new THREE.BoxGeometry(span, 0.38, 2.45), sillMat);
  sill.position.set(0, h - 1.29, 0);
  g.add(sill);
  // pilares finos de concreto atrás dos muros (em vez de torres maciças)
  for (const x of [-span / 2 + 1.0, span / 2 - 1.0]) {
    const pillar = new THREE.Mesh(new THREE.BoxGeometry(0.85, h + 1.1, 1.1), concrete);
    pillar.position.set(x, (h + 1.1) / 2, 0);
    g.add(pillar);
  }
  g.traverse(o => {
    o.castShadow = true;
    o.receiveShadow = true;
  });
  g.position.copy(s.p).addScaledVector(s.r, (s.wallR - s.wallL) / 2);
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
  group.add(g);

  buildMotulGantry(track, group, renderer);
  buildOppositeRunoff(track, group, renderer);
  buildPitExit(track, group);
  buildPitEntry(track, group, renderer);
  // (até a Fase 6 aqui havia buildDescidaLagoGoodyear: barreira dupla desenhada colada na zebra esquerda em s 1394–1582;
  // agora é a barreira "tecpro2" do perfil lateral, no muro da física, de s ~1490 a 1658 — ver setor6_perfil.py)
  buildFerraduraWall(track, group, renderer);
  buildGrassSigns(track, group, renderer);
  buildSennaTents(track, group, heightAt);
  buildSennaBuilding(track, group, renderer, heightAt);
  buildBigScreen(track, group, renderer);
  buildFlagGarland(track, group);
}

/** Pórtico vermelho MOTUL sobre a Reta Oposta (s ≈ 1040 m), igual ao 04_reta_oposta_1 do LMU. */
function buildMotulGantry(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const s = S[iNovo4300(1040) % S.length];
  const span = s.wallL + s.wallR + 4;
  const h = 6.2;
  const steel = new THREE.MeshStandardMaterial({ color: 0x25282c, metalness: 0.5, roughness: 0.5 });
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 128;
  const cg = c.getContext('2d')!;
  cg.fillStyle = '#c8102e';
  cg.fillRect(0, 0, 1024, 128);
  cg.fillStyle = '#ffffff';
  cg.font = '900 italic 66px Arial';
  cg.textAlign = 'center';
  cg.textBaseline = 'middle';
  for (const x of [150, 390, 634, 874]) cg.fillText('MOTUL', x, 66, 200);
  const ad = new THREE.MeshStandardMaterial({ map: tex(compensaLuz(c), renderer, false), roughness: 0.45 });
  const g = new THREE.Group();
  const beam = new THREE.Mesh(new THREE.BoxGeometry(span, 1.5, 0.5), [steel, steel, steel, steel, ad, ad]);
  beam.position.set(0, h, 0);
  g.add(beam);
  const center = s.p.clone().addScaledVector(s.r, (s.wallR - s.wallL) / 2);
  const rotY = Math.atan2(-s.r.z, s.r.x);
  for (const x of [-span / 2 + 0.4, span / 2 - 0.4]) {
    addProp('gantry_tower', center.clone().addScaledVector(s.r, x), rotY, 1, false);
  }
  g.traverse(o => {
    o.castShadow = true;
    o.receiveShadow = true;
  });
  g.position.copy(s.p).addScaledVector(s.r, (s.wallR - s.wallL) / 2);
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
  group.add(g);
}

/**
 * Continuação das faixas vermelha/verde e paredão verde atrás do muro MOTUL na Reta Oposta (s = 780..1150 m).
 * As faixas são tinta sobre asfalto como as outras (textura lisa da cor + relevo do asfalto → "pinta:<nome>" no GLB),
 * com as cores calibradas de ./tintas.ts.
 */
function buildOppositeRunoff(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const asphaltNormal = phTexture('asphalt_track', 'nor_gl', renderer);
  const paint = (cor: string, nome: string) => {
    const c = document.createElement('canvas');
    c.width = c.height = 4;
    const g = c.getContext('2d')!;
    g.fillStyle = cor;
    g.fillRect(0, 0, 4, 4);
    return new THREE.MeshStandardMaterial({ name: nome, map: tex(c, renderer), normalMap: asphaltNormal, normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.9, side: THREE.DoubleSide });
  };
  const S = track.samples;
  const N = S.length;
  const i0 = iNovo4300(780);
  const i1 = iNovo4300(1150);
  const stripOff =(d0: number, d1: number, mat: THREE.Material, y0 = 0.015, y1 = 0.015, iStart = i0, iEnd = i1) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let i = iStart; i <= iEnd; i++) {
      const s = S[i % N];
      const base = pos.length / 3;
      const w0 = s.wr + d0;
      const w1 = y0 === y1 ? Math.min(s.wallR - 0.05, s.wr + d1) : s.wr + d1;
      if (y0 === y1 && w1 <= w0) {
        prev = -1;
        continue;
      }
      for (const [off, y, u] of [[w0, y0, 0], [w1, y1, 1]] as const) {
        v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, y);
        pos.push(v.x, v.y, v.z);
        uv.push(u, (i * STEP) / 8);
      }
      if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
      prev = base;
    }
    if (!idx.length) return;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, mat);
    m.receiveShadow = true;
    group.add(m);
  };
  // Deixa 0..1.5 m de grama junto à linha branca, depois faixa vermelha viva e verde externa até o muro MOTUL
  // nome = qual tinta é (o Godot e tools/ref/regioes_tinta.py acham a malha por ele: "pinta:<nome>")
  stripOff(1.5, 4.5, paint(TINTA.vermelho, 'vermelha_oposta'));
  stripOff(4.5, 7.0, paint(TINTA.verdeAgua, 'verde_oposta'));
  // Paredão/talude verde escuro atrás do muro MOTUL (s = 820..1120 m)
  const wi0 = iNovo4300(820);
  const wi1 = iNovo4300(1120);
  {
    const pos: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let i = wi0; i <= wi1; i++) {
      const s = S[i % N];
      const base = pos.length / 3;
      const d = s.wallR + 0.4;
      for (const h of [1.2, 4.2]) {
        v.copy(s.p).addScaledVector(s.r, d);
        v.y += h;
        pos.push(v.x, v.y, v.z);
      }
      if (prev >= 0) idx.push(prev, base, prev + 1, prev + 1, base, base + 1);
      prev = base;
    }
    if (idx.length) {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const wall = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: 0x1b3b22, roughness: 0.95, side: THREE.DoubleSide }));
      wall.castShadow = true;
      wall.receiveShadow = true;
      group.add(wall);
    }
  }
}

/** Saída dos boxes e barreira divisória até a saída da Curva do Sol (s = 300..795 m, fotos 02 e 03). */
function buildPitExit(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const i0 = iNovo4300(300);
  const i1 = iNovo4300(795);
  const smooth = (a: number, b: number, x: number) => {
    const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
  };
  const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

  const pitRibbon = (getRange: (s: (typeof S)[number], sm: number) => [number, number] | null, yLift: number, mat: THREE.Material) => {
    const pos: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let i = i0; i <= i1; i++) {
      const s = S[i % N];
      const sm = s4300(s.s);
      const range = getRange(s, sm);
      if (!range || range[1] <= range[0]) {
        prev = -1;
        continue;
      }
      const base = pos.length / 3;
      for (const off of range) {
        v.copy(s.p).addScaledVector(s.r, off);
        v.y += yLift;
        pos.push(v.x, v.y, v.z);
      }
      if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
      prev = base;
    }
    if (!idx.length) return;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, mat);
    m.receiveShadow = true;
    group.add(m);
  };

  // Fase 4: o separador (muro da física) passou de borda + 4,4 m para o fim da grama medido no satélite (borda +
  // 6,5–9 m, build_track.py SEPARADOR_F4); a pista dos boxes e o guard-rail andam junto com ele (extra = o que o muro
  // passou de 4,4 m; some na convergência do fim).
  const extra = (s: (typeof S)[number]) => Math.max(0, Math.min(6, s.wallL - s.wl - 4.4));
  const bounds = (s: (typeof S)[number], sm: number): [number, number] => {
    const t = smooth(720, 795, sm);
    const e = extra(s) * (1 - t);
    const dOut = -(s.wl + lerp(9.6, 0.25, smooth(735, 795, sm)) + e);
    const dIn = -(s.wl + lerp(4.8, 0.05, t) + e);
    return [dOut, dIn];
  };
  const asphaltMat = new THREE.MeshStandardMaterial({ color: 0x3e4044, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1, side: THREE.DoubleSide });
  const lineMat = new THREE.MeshStandardMaterial({ color: 0xeeeee8, roughness: 0.8, polygonOffset: true, polygonOffsetFactor: -2, side: THREE.DoubleSide });
  pitRibbon((s, sm) => bounds(s, sm), 0.012, asphaltMat);
  pitRibbon((s, sm) => { const [dOut] = bounds(s, sm); return [dOut, dOut + 0.22]; }, 0.018, lineMat);
  pitRibbon((s, sm) => { const [, dIn] = bounds(s, sm); return [dIn - 0.22, dIn]; }, 0.018, lineMat);

  // Guard-rail metálico duplo separador entre pista e saída dos boxes na Curva do Sol (s = 565..735 m)
  const g0 = iNovo4300(565);
  const g1 = iNovo4300(735);
  const railMat = new THREE.MeshStandardMaterial({ color: 0xc2c6ca, metalness: 0.35, roughness: 0.5, side: THREE.DoubleSide });
  for (const [h0, h1] of [[0.38, 0.68], [0.78, 1.08]] as const) {
    const pos: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let i = g0; i <= g1; i++) {
      const s = S[i % N];
      const base = pos.length / 3;
      const d = -(s.wl + 4.4 + extra(s));
      for (const h of [h0, h1]) {
        v.copy(s.p).addScaledVector(s.r, d);
        v.y += h;
        pos.push(v.x, v.y, v.z);
      }
      if (prev >= 0) idx.push(prev, base, prev + 1, prev + 1, base, base + 1);
      prev = base;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, railMat);
    m.castShadow = true;
    m.receiveShadow = true;
    group.add(m);
  }
  const postMat = new THREE.MeshStandardMaterial({ color: 0x70757c, metalness: 0.5, roughness: 0.5 });
  const postGeo = new THREE.BoxGeometry(0.12, 1.12, 0.12);
  for (let i = g0; i <= g1; i += 2) {
    const s = S[i % N];
    const p = s.p.clone().addScaledVector(s.r, -(s.wl + 4.45 + extra(s)));
    const post = new THREE.Mesh(postGeo, postMat);
    post.position.set(p.x, p.y + 0.56, p.z);
    post.castShadow = true;
    group.add(post);
  }
  // Ponteira laranja/preta no fim do separador (s = 735 m)
  const sEnd = S[g1 % N];
  const tipPos = sEnd.p.clone().addScaledVector(sEnd.r, -(sEnd.wl + 4.4 + extra(sEnd)));
  const tip = new THREE.Group();
  const blackBlk = new THREE.Mesh(new THREE.BoxGeometry(0.65, 1.0, 1.4), new THREE.MeshStandardMaterial({ color: 0x1c1f24, roughness: 0.75 }));
  blackBlk.position.set(0, 0.5, -0.7);
  const orangeBlk = new THREE.Mesh(new THREE.BoxGeometry(0.7, 1.0, 1.1), new THREE.MeshStandardMaterial({ color: 0xff6a00, roughness: 0.6 }));
  orangeBlk.position.set(0, 0.5, 0.55);
  tip.add(blackBlk, orangeBlk);
  tip.position.copy(tipPos);
  tip.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(sEnd.r, new THREE.Vector3(0, 1, 0), sEnd.t.clone()));
  tip.traverse(o => { o.castShadow = true; o.receiveShadow = true; });
  group.add(tip);
}

/** Ilha verde com divisas brancas (>>>) da entrada dos boxes (frame 29 / s = 3885..4038 m). */
function pitChevronTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const W = 256;
  const H = 512;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  g.fillStyle = '#0c8a46';
  g.fillRect(0, 0, W, H);
  // bordas brancas contínuas dos dois lados da ilha
  g.fillStyle = '#f2f2ec';
  g.fillRect(0, 0, 14, H);
  g.fillRect(W - 14, 0, 14, H);
  // duas divisas brancas apontando para a frente (base menor y = -s.t, ponta maior y = +s.t)
  g.strokeStyle = '#f2f2ec';
  g.lineWidth = 30;
  g.lineCap = 'square';
  g.lineJoin = 'miter';
  for (const yBase of [55, 311]) {
    g.beginPath();
    g.moveTo(24, yBase);
    g.lineTo(W / 2, yBase + 125);
    g.lineTo(W - 24, yBase);
    g.stroke();
  }
  return tex(c, renderer);
}

/** Barreira de pneus amarela/preta com setas (<<<O>>>) na ponta do muro dos boxes (s = 4040 m). */
function pitNoseBarrierTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const W = 512;
  const H = 128;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  g.fillStyle = '#181a1e';
  g.fillRect(0, 0, W, H);
  g.fillStyle = '#f2c500';
  g.fillRect(0, 10, W, H - 20);
  g.strokeStyle = '#181a1e';
  g.lineWidth = 14;
  // setas <<< à esquerda e >>> à direita, círculo central
  for (const x of [48, 96, 144]) {
    g.beginPath();
    g.moveTo(x + 28, 28);
    g.lineTo(x, H / 2);
    g.lineTo(x + 28, H - 28);
    g.stroke();
  }
  g.beginPath();
  g.arc(W / 2, H / 2, 26, 0, Math.PI * 2);
  g.stroke();
  for (const x of [368, 416, 464]) {
    g.beginPath();
    g.moveTo(x - 28, 28);
    g.lineTo(x, H / 2);
    g.lineTo(x - 28, H - 28);
    g.stroke();
  }
  return tex(c, renderer);
}

/** Abertura de serviço na subida (s = 3460..3535 m, foto 26) e entrada real dos boxes com ilha verde (s = 3860..4040 m, foto 29). */
function buildPitEntry(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const N = S.length;
  const smooth = (a: number, b: number, x: number) => {
    const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
  };
  const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
  const asphaltMat = new THREE.MeshStandardMaterial({ color: 0x3e4044, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1, side: THREE.DoubleSide });
  const lineMat = new THREE.MeshStandardMaterial({ color: 0xeeeee8, roughness: 0.8, polygonOffset: true, polygonOffsetFactor: -2, side: THREE.DoubleSide });

  const makeBand = (
    fn: (s: (typeof S)[number], sm: number) => [number, number] | null,
    yLift: number,
    mat: THREE.Material,
    sStart: number,
    sEnd: number,
    vScale = 0
  ) => {
    const sA = iNovo4300(sStart);
    const sB = iNovo4300(sEnd);
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let i = sA; i <= sB; i++) {
      const s = S[i % N];
      const sm = s4300(s.s);
      const r = fn(s, sm);
      if (!r || r[1] <= r[0]) {
        prev = -1;
        continue;
      }
      const base = pos.length / 3;
      for (const [off, u] of [[r[0], 0], [r[1], 1]] as const) {
        v.copy(s.p).addScaledVector(s.r, off);
        v.y += yLift;
        pos.push(v.x, v.y, v.z);
        if (vScale) uv.push(u, ((i - sA) * STEP) / vScale);
      }
      if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
      prev = base;
    }
    if (!idx.length) return;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    if (vScale) geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, mat);
    m.receiveShadow = true;
    group.add(m);
  };

  // 1) Abertura de serviço na Subida dos Boxes antes da Curva do Café (s = 3505..3535 m, frame 26)
  makeBand((s, sm) => {
    const w = 3.5 * smooth(3505, 3530, sm);
    return w > 0.1 ? [-(s.wl + w), -(s.wl + 0.04)] : null;
  }, 0.01, asphaltMat, 3505, 3535);
  const orangeMat = new THREE.MeshStandardMaterial({ color: 0xff6a00, roughness: 0.55 });
  const blackMat = new THREE.MeshStandardMaterial({ color: 0x1c1f24, roughness: 0.75 });
  const sAt = S[iNovo4300(3535) % N];
  const atGrp = new THREE.Group();
  const nose = new THREE.Mesh(new THREE.BoxGeometry(1.1, 1.05, 3.6), orangeMat);
  nose.position.set(0, 0.525, 1.8);
  const body = new THREE.Mesh(new THREE.BoxGeometry(1.1, 1.05, 7.5), blackMat);
  body.position.set(0, 0.525, -3.75);
  atGrp.add(nose, body);
  atGrp.position.copy(sAt.p).addScaledVector(sAt.r, -(sAt.wl + 2.2));
  atGrp.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(sAt.r, new THREE.Vector3(0, 1, 0), sAt.t.clone().negate()));
  atGrp.traverse(o => { o.castShadow = true; o.receiveShadow = true; });
  group.add(atGrp);

  // 2) Entrada real dos boxes (s = 3860..4040 m, frame 29): asfalto da faixa, ilha verde com chevrons >>> e barreira no bico
  const entryWidth = (sm: number) => lerp(lerp(0.5, 9.2, smooth(3860, 3915, sm)), 11.5, smooth(4010, 4040, sm));
  makeBand((s, sm) => [-(s.wl + entryWidth(sm)), -(s.wl + 0.04)], 0.01, asphaltMat, 3860, 4040);
  makeBand((s, sm) => {
    const w = entryWidth(sm);
    return [-(s.wl + w), -(s.wl + w - 0.22)];
  }, 0.016, lineMat, 3860, 4040);

  // Ilha verde com chevrons brancos entre a pista (-wl) e a faixa dos boxes (-(wl + 4.5))
  const chevronMat = new THREE.MeshStandardMaterial({
    map: pitChevronTexture(renderer),
    roughness: 0.8,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    side: THREE.DoubleSide
  });
  makeBand((s, sm) => {
    const w = 4.5 * smooth(3885, 3910, sm);
    return w > 0.2 ? [-(s.wl + w), -(s.wl + 0.05)] : null;
  }, 0.015, chevronMat, 3885, 4038, 14);

  // Barreira acolchoada amarela/preta com setas (<<<O>>>) na ponta do muro dos boxes (s = 4040 m)
  const sNose = S[iNovo4300(4040) % N];
  const noseMat = new THREE.MeshStandardMaterial({ map: pitNoseBarrierTexture(renderer), roughness: 0.5 });
  const padDark = new THREE.MeshStandardMaterial({ color: 0x1c1f24, roughness: 0.75 });
  const nosePad = new THREE.Mesh(
    new THREE.BoxGeometry(2.8, 1.08, 3.0),
    [padDark, padDark, padDark, padDark, noseMat, padDark]
  );
  nosePad.position.copy(sNose.p).addScaledVector(sNose.r, -(sNose.wl + 2.2)).setY(sNose.p.y + 0.54);
  nosePad.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(sNose.r, new THREE.Vector3(0, 1, 0), sNose.t.clone().negate()));
  nosePad.castShadow = true;
  nosePad.receiveShadow = true;
  group.add(nosePad);
}

/**
 * Tendas de hospitalidade brancas (cobertura em pirâmide) e contêineres coloridos à esquerda do S do Senna, atrás do
 * guard-rail da saída dos boxes, e apoio atrás da grade direita na entrada do S.
 * Fase 4 (LMU s 380–480): as tendas são todas brancas (antes laranja/vermelho/azul) e há uma fileira de contêineres
 * vermelhos/azuis/brancos/amarelos; nada a menos de 4 m do muro da física. Tudo junto em 3 malhas (corpo, telhado,
 * contêineres) para não somar draw calls.
 */
function buildSennaTents(track: Track, group: THREE.Group, heightAt?: (x: number, z: number) => number) {
  const S = track.samples;
  // s na convenção antiga (4.300 m), d a partir do centro antigo (+ dNovo); |d| mínimo = muro + 4 m + meia tenda
  const tentSpecs = [
    { s: 362, d: -30, w: 8, l: 8 },
    { s: 375, d: -26, w: 7, l: 7 },
    { s: 392, d: -28, w: 10, l: 10 },
    { s: 412, d: -27, w: 7, l: 7 },
    { s: 432, d: -31, w: 12, l: 10 },
    { s: 454, d: -29, w: 9, l: 9 },
    { s: 472, d: -33, w: 10, l: 10 },
    // estruturas de apoio atrás da grade da direita na entrada do S (01)
    { s: 255, d: 28, w: 10, l: 8 },
    { s: 278, d: 30, w: 12, l: 9 }
  ];
  const bodies: THREE.BufferGeometry[] = [];
  const roofs: THREE.BufferGeometry[] = [];
  const m = new THREE.Matrix4();
  const place = (sAntigo4300: number, d: number, half: number): [THREE.Vector3, (typeof S)[number]] => {
    const s = S[iNovo4300(sAntigo4300) % S.length];
    let dd = d + dNovo4300(sAntigo4300);
    const lim = (dd < 0 ? s.wallL : s.wallR) + 4 + half;
    if (Math.abs(dd) < lim) dd = Math.sign(dd) * lim;
    const pos = s.p.clone().addScaledVector(s.r, dd);
    pos.y = (heightAt ? heightAt(pos.x, pos.z) : s.p.y) - 0.3;
    return [pos, s];
  };
  const basis = (s: (typeof S)[number], pos: THREE.Vector3) =>
    m.makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()).setPosition(pos);
  for (const t of tentSpecs) {
    const [pos, s] = place(t.s, t.d, Math.max(t.w, t.l) / 2);
    const body = new THREE.BoxGeometry(t.w, 2.8, t.l).translate(0, 1.4, 0).applyMatrix4(basis(s, pos));
    const roof = new THREE.ConeGeometry(Math.max(t.w, t.l) * 0.74, 1.8, 4).rotateY(Math.PI / 4).translate(0, 3.6, 0).applyMatrix4(basis(s, pos));
    bodies.push(body);
    roofs.push(roof);
  }
  const bodyMat = new THREE.MeshStandardMaterial({ color: 0xd9d9d4, roughness: 0.8 });
  const roofMat = new THREE.MeshStandardMaterial({ color: 0xf2f2ee, roughness: 0.65 });
  // contêineres (6 × 2,4 × 2,6 m) em fileira, cores sortidas como no LMU
  const cores = [0xb3242a, 0x1d4f9c, 0xe8e6df, 0xd9b21c, 0xb3242a, 0x2c7a3c, 0x1d4f9c];
  const cont: THREE.BufferGeometry[] = [];
  const cor = new THREE.Color();
  for (let k = 0; k < 14; k++) {
    const sA = 400 + k * 6.5;
    const [pos, s] = place(sA, -44 - (k % 3 === 0 ? 3 : 0), 3);
    const g = new THREE.BoxGeometry(2.4, 2.6, 6).translate(0, 1.3 + (k % 4 === 1 ? 2.6 : 0), 0).applyMatrix4(basis(s, pos));
    cor.setHex(cores[k % cores.length]);
    const n = g.getAttribute('position').count;
    g.setAttribute('color', new THREE.Float32BufferAttribute(Array.from({ length: n }, () => [cor.r, cor.g, cor.b]).flat(), 3));
    cont.push(g);
  }
  const contMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.7 });
  for (const [geos, mat] of [[bodies, bodyMat], [roofs, roofMat], [cont, contMat]] as const) {
    const mesh = new THREE.Mesh(mergeGeometries(geos as THREE.BufferGeometry[]), mat);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    group.add(mesh);
  }
}

/** Edifício de operações/camarotes atrás dos boxes com mural artístico do Ayrton Senna (s = 4195 m, d = -32 m). */
function buildSennaBuilding(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, heightAt?: (x: number, z: number) => number) {
  const S = track.samples;
  const s = S[iNovo4300(4195) % S.length];
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 512;
  const g = c.getContext('2d')!;
  // Fundo arquitetônico cinza-chumbo (2/3 esquerdos: fachada de 4 andares envidraçados)
  g.fillStyle = '#22262e';
  g.fillRect(0, 0, 1024, 512);
  for (let row = 0; row < 4; row++) {
    const ry = 44 + row * 112;
    // faixa de vidro escuro contínuo
    const gl = g.createLinearGradient(0, ry, 0, ry + 64);
    gl.addColorStop(0, '#101822');
    gl.addColorStop(0.5, '#192638');
    gl.addColorStop(1, '#121a24');
    g.fillStyle = gl;
    g.fillRect(18, ry, 650, 64);
    // brise horizontal metálico
    g.fillStyle = '#3b424d';
    g.fillRect(18, ry - 10, 650, 8);
    g.fillStyle = '#505866';
    g.fillRect(18, ry + 64, 650, 5);
    // montantes verticais metálicos
    g.fillStyle = '#2e343e';
    for (let x = 18; x <= 668; x += 44) g.fillRect(x, ry, 5, 64);
  }
  // Pilares estruturais verticais na fachada
  g.fillStyle = '#323842';
  for (const px of [0, 224, 448, 668]) g.fillRect(px, 0, 14, 512);

  // 1/3 direito (x = 690..1000): painel vertical colorido do mural de Eduardo Kobra
  const mx = 690;
  const mw = 310;
  const my = 20;
  const mh = 472;
  g.save();
  g.beginPath();
  g.rect(mx, my, mw, mh);
  g.clip();
  const palette = ['#f5c400', '#009c3b', '#003893', '#e03c28', '#f59e0b', '#007a3d', '#1d4ed8', '#dc2626'];
  // Raios e triângulos caleidoscópicos irradiando do centro do mural
  const cx = mx + mw * 0.52;
  const cy = my + mh * 0.42;
  for (let a = 0; a < 24; a++) {
    const a0 = (a * Math.PI * 2) / 24;
    const a1 = ((a + 1) * Math.PI * 2) / 24;
    g.fillStyle = palette[(a * 3) % palette.length];
    g.beginPath();
    g.moveTo(cx, cy);
    g.lineTo(cx + Math.cos(a0) * 420, cy + Math.sin(a0) * 420);
    g.lineTo(cx + Math.cos(a1) * 420, cy + Math.sin(a1) * 420);
    g.closePath();
    g.fill();
  }
  // Busto / macacão estilizado nos tons Kobra
  g.fillStyle = '#b91c1c';
  g.beginPath();
  g.moveTo(mx + 10, my + mh);
  g.quadraticCurveTo(cx, my + 275, mx + mw - 10, my + mh);
  g.closePath();
  g.fill();
  // Faixas coloridas diagonais no macacão
  g.fillStyle = '#009c3b';
  g.beginPath();
  g.moveTo(mx + 20, my + mh);
  g.lineTo(cx - 25, my + 315);
  g.lineTo(cx + 25, my + 315);
  g.lineTo(mx + 120, my + mh);
  g.closePath();
  g.fill();

  // Capacete de Ayrton Senna em perfil 3/4 (contorno, cúpula amarela, faixas verde/azul, viseira escura espelhada)
  g.fillStyle = '#11151c';
  g.beginPath();
  g.ellipse(cx + 4, cy + 4, 108, 122, -0.08, 0, Math.PI * 2);
  g.fill();
  const hGrad = g.createLinearGradient(cx - 95, cy - 110, cx + 95, cy + 105);
  hGrad.addColorStop(0, '#ffe442');
  hGrad.addColorStop(0.5, '#f2bd00');
  hGrad.addColorStop(1, '#c48d00');
  g.fillStyle = hGrad;
  g.beginPath();
  g.ellipse(cx, cy, 100, 114, -0.08, 0, Math.PI * 2);
  g.fill();
  // Queixeira angulada 3/4 voltada para a esquerda/frente
  g.fillStyle = '#e3af00';
  g.beginPath();
  g.moveTo(cx - 95, cy + 16);
  g.lineTo(cx - 58, cy + 102);
  g.lineTo(cx + 68, cy + 90);
  g.lineTo(cx + 88, cy + 10);
  g.closePath();
  g.fill();
  // Faixas clássicas verde e azul acompanhando a curvatura 3/4
  g.fillStyle = '#008c38';
  g.beginPath();
  g.moveTo(cx - 88, cy + 32);
  g.quadraticCurveTo(cx - 10, cy + 52, cx + 92, cy + 20);
  g.lineTo(cx + 86, cy + 38);
  g.quadraticCurveTo(cx - 10, cy + 68, cx - 80, cy + 48);
  g.closePath();
  g.fill();
  g.fillStyle = '#002e7a';
  g.beginPath();
  g.moveTo(cx - 78, cy + 52);
  g.quadraticCurveTo(cx - 8, cy + 72, cx + 82, cy + 42);
  g.lineTo(cx + 76, cy + 58);
  g.quadraticCurveTo(cx - 8, cy + 86, cx - 70, cy + 66);
  g.closePath();
  g.fill();
  // Viseira escura espelhada realista (sem olhinhos desenhados)
  const vGrad = g.createLinearGradient(cx - 94, cy - 45, cx + 48, cy + 25);
  vGrad.addColorStop(0, '#070b12');
  vGrad.addColorStop(0.45, '#13253a');
  vGrad.addColorStop(0.75, '#0b1524');
  vGrad.addColorStop(1, '#1d3652');
  g.fillStyle = vGrad;
  g.beginPath();
  g.moveTo(cx - 94, cy - 32);
  g.quadraticCurveTo(cx - 25, cy - 52, cx + 52, cy - 26);
  g.lineTo(cx + 42, cy + 22);
  g.quadraticCurveTo(cx - 25, cy + 40, cx - 88, cy + 16);
  g.closePath();
  g.fill();
  // Reflexo diagonal metálico na viseira
  g.fillStyle = 'rgba(180, 220, 255, 0.28)';
  g.beginPath();
  g.moveTo(cx - 72, cy - 28);
  g.lineTo(cx - 32, cy - 34);
  g.lineTo(cx - 56, cy + 20);
  g.lineTo(cx - 80, cy + 14);
  g.closePath();
  g.fill();
  g.restore();

  const facadeMat = new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.62 });
  const sideMat = new THREE.MeshStandardMaterial({ color: 0x282d36, roughness: 0.82 });
  const roofMat = new THREE.MeshStandardMaterial({ color: 0x1e2228, metalness: 0.35, roughness: 0.65 });
  const pos = s.p.clone().addScaledVector(s.r, -32 + dNovo4300(4195)); // −32 m do centro antigo
  const gy = heightAt ? heightAt(pos.x, pos.z) : s.p.y;
  const H = 20;
  const grp = new THREE.Group();
  // Dimensões 14 (profundidade X) x 20 (altura Y) x 28 (largura Z paralela à pista); face -X ([1]) olha para a Ferradura
  const bldg = new THREE.Mesh(new THREE.BoxGeometry(14, H, 28), [sideMat, facadeMat, roofMat, sideMat, sideMat, sideMat]);
  bldg.position.y = H / 2;
  grp.add(bldg);
  const cornice = new THREE.Mesh(new THREE.BoxGeometry(15.4, 1.2, 29.4), roofMat);
  cornice.position.y = H + 0.6;
  grp.add(cornice);
  grp.position.set(pos.x, gy - 3, pos.z);
  grp.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
  grp.traverse(o => {
    o.castShadow = true;
    o.receiveShadow = true;
  });
  group.add(grp);
}

/** Paredão de concreto atrás da barreira amarela DHL na Ferradura com faixa DHL (s = 2005..2140 m, frame 15). */
function buildFerraduraWall(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const N = S.length;
  const i0 = iNovo4300(2005);
  const i1 = iNovo4300(2140);
  const wallMat = new THREE.MeshStandardMaterial({ color: 0x7b7e82, roughness: 0.9, side: THREE.DoubleSide });
  const bannerMat = new THREE.MeshStandardMaterial({
    map: tex(adCanvas('amarelo', 4, 256, 64), renderer),
    roughness: 0.5,
    side: THREE.DoubleSide
  });

  const makeWallBand = (h0: number, h1: number, offsetExtra: number, mat: THREE.Material, vScale: number) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let i = i0; i <= i1; i++) {
      const s = S[i % N];
      const base = pos.length / 3;
      const d = -(s.wallL + offsetExtra);
      for (const [h, u] of [[h0, 0], [h1, 1]] as const) {
        v.copy(s.p).addScaledVector(s.r, d);
        v.y += h;
        pos.push(v.x, v.y, v.z);
        uv.push(((i - i0) * STEP) / vScale, u);
      }
      if (prev >= 0) idx.push(prev, base, prev + 1, prev + 1, base, base + 1);
      prev = base;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, mat);
    m.castShadow = true;
    m.receiveShadow = true;
    group.add(m);
  };
  makeWallBand(-2.0, 6.2, 1.5, wallMat, 8);
  makeWallBand(2.5, 5.0, 1.38, bannerMat, 18);
}

/** Placas pequenas de patrocinador no gramado e anel de pneus em árvore isolada (frames 13, 19, 25). */
function buildGrassSigns(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const N = S.length;
  const backMat = new THREE.MeshStandardMaterial({ color: 0x26292e, roughness: 0.8 });
  const specs: { s: number; side: -1 | 1; dist: number; ads: AdScheme }[] = [
    { s: 1880, side: -1, dist: 4.2, ads: 'azul' },
    { s: 1880, side: 1, dist: 4.2, ads: 'azul' },
    { s: 2595, side: 1, dist: 5.0, ads: 'azul' },
    { s: 3075, side: -1, dist: 4.5, ads: 'azul' },
    { s: 3425, side: -1, dist: 4.5, ads: 'azul' }
  ];
  const boardGeo = new THREE.BoxGeometry(3.2, 1.25, 0.16);
  const mats = new Map<AdScheme, THREE.Material[]>();
  const boardMat = (a: AdScheme) => {
    if (!mats.has(a)) {
      const c = adCanvas(a, 1, 256, 96);
      const face = new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.55 });
      mats.set(a, [backMat, backMat, backMat, backMat, face, backMat]);
    }
    return mats.get(a)!;
  };
  for (const sp of specs) {
    const s = S[iNovo4300(sp.s) % N];
    const edge = sp.side < 0 ? s.wl : s.wr;
    const pos = s.p.clone().addScaledVector(s.r, sp.side * (edge + sp.dist));
    const m = new THREE.Mesh(boardGeo, boardMat(sp.ads));
    m.position.set(pos.x, s.p.y + 0.58, pos.z);
    m.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
    m.castShadow = true;
    m.receiveShadow = true;
    group.add(m);
  }
  // Anel escuro de pneus na base da árvore no gramado direito após o Pinheirinho (s = 2585 m, frame 19)
  const sTree = S[iNovo4300(2585) % N];
  const pTree = sTree.p.clone().addScaledVector(sTree.r, sTree.wr + 18.0);
  const ring = new THREE.Mesh(
    new THREE.CylinderGeometry(2.6, 2.8, 0.85, 18, 1, true),
    new THREE.MeshStandardMaterial({ color: 0x1b1d20, roughness: 0.9, side: THREE.DoubleSide })
  );
  ring.position.set(pTree.x, sTree.p.y + 0.35, pTree.z);
  ring.castShadow = true;
  ring.receiveShadow = true;
  group.add(ring);
}

/** Telão gigante atrás do guard-rail esquerdo na aproximação dos boxes (s = 3855 m, d = -(wl + 6.5)) + casinha de apoio (frame 28). */
function buildBigScreen(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const s = S[iNovo4300(3855) % S.length];
  const frameMat = new THREE.MeshStandardMaterial({ color: 0x16181c, roughness: 0.7 });
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 144;
  const g = c.getContext('2d')!;
  g.fillStyle = '#5c7ea8';
  g.fillRect(0, 0, 256, 72);
  g.fillStyle = '#3b4046';
  g.fillRect(0, 72, 256, 72);
  g.fillStyle = '#2d6e32';
  g.fillRect(0, 68, 40, 22);
  g.fillRect(216, 68, 40, 22);
  g.fillStyle = '#b0185c';
  g.fillRect(114, 90, 28, 16);
  const screenMat = new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), emissive: 0x22262e, roughness: 0.35 });
  const grp = new THREE.Group();
  // Face +Z ([4]) voltada para quem chega (-s.t), girada levemente para dentro da pista (+0.32 rad)
  const panel = new THREE.Mesh(new THREE.BoxGeometry(9.6, 5.6, 0.9), [frameMat, frameMat, frameMat, frameMat, screenMat, frameMat]);
  panel.position.set(0, 6.2, 0);
  grp.add(panel);
  const base = new THREE.Mesh(new THREE.BoxGeometry(10.0, 3.4, 2.2), frameMat);
  base.position.set(0, 1.7, 0);
  grp.add(base);
  // Casinha branca/azul de apoio fora da pista, logo à frente/esquerda do telão
  const hutWhite = new THREE.MeshStandardMaterial({ color: 0xdfe3e8, roughness: 0.75 });
  const hutBlue = new THREE.MeshStandardMaterial({ color: 0x184896, roughness: 0.6 });
  const hut = new THREE.Mesh(new THREE.BoxGeometry(3.2, 3.0, 3.8), hutWhite);
  hut.position.set(-2.2, 1.5, 4.6);
  const hutRoof = new THREE.Mesh(new THREE.BoxGeometry(3.5, 0.45, 4.1), hutBlue);
  hutRoof.position.set(-2.2, 3.2, 4.6);
  grp.add(hut, hutRoof);

  grp.traverse(o => {
    o.castShadow = true;
    o.receiveShadow = true;
  });
  grp.position.copy(s.p).addScaledVector(s.r, -(s.wl + 8.5));
  grp.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
  grp.rotateY(0.32);
  group.add(grp);
}

/** Varal de bandeiras internacionais sobre o pit lane na reta principal (s = 4215 m, frame 30). */
function buildFlagGarland(track: Track, group: THREE.Group) {
  const S = track.samples;
  const s = S[iNovo4300(4215) % S.length];
  const grp = new THREE.Group();
  const cableMat = new THREE.MeshStandardMaterial({ color: 0x22252a, roughness: 0.6 });
  const span = 16.0;
  const cable = new THREE.Mesh(new THREE.BoxGeometry(span, 0.06, 0.06), cableMat);
  cable.position.set(-span / 2, 7.8, 0);
  grp.add(cable);
  const colors = [0x009c3b, 0xc8102e, 0xf2c500, 0x0f3c96, 0xf2f2ee, 0x111111, 0xd40511, 0x009c3b];
  for (let k = 0; k < 8; k++) {
    const flag = new THREE.Mesh(
      new THREE.BoxGeometry(1.5, 1.05, 0.05),
      new THREE.MeshStandardMaterial({ color: colors[k], roughness: 0.75, side: THREE.DoubleSide })
    );
    flag.position.set(-1.2 - k * 1.9, 7.2, 0);
    grp.add(flag);
  }
  grp.position.copy(s.p).addScaledVector(s.r, -(s.wl + 1.2));
  grp.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
  grp.rotateY(-0.22);
  group.add(grp);
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
  // de 200 a 12 m antes da linha na pista antiga (s real), levado para a nova
  const gA = sNovo(L_ANTIGO - 200);
  const gB = sNovo(L_ANTIGO - 12);
  const c =document.createElement('canvas');
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
  const mesh = overlay(track, 0.005, 16, i => S[i].s > gA && S[i].s < gB, mat);
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
  for (let k = 0; k < 18; k++) {
    // remendos de asfalto mais novo: mais escuros e contrastados, com a junta selada em volta
    const full = rand() < 0.25;
    const x = full ? 0 : Math.floor(rand() * 2) * (W / 2) + (rand() - 0.5) * 12;
    const w = full ? W : W / 2 + rand() * 10;
    const y = rand() * H;
    const h = (4 + rand() * 18) * ppm;
    g.fillStyle = `rgba(10,10,12,${0.12 + rand() * 0.14})`;
    g.fillRect(x, y, w, h);
    g.strokeStyle = 'rgba(6,6,6,0.48)';
    g.lineWidth = 2;
    g.strokeRect(x + 1, y, w - 2, h);
  }
  for (let k = 0; k < 55; k++) {
    // trinca seladas (piche) atravessando parte da pista
    const y = rand() * H;
    const x = rand() * W * 0.7;
    g.strokeStyle = `rgba(5,5,5,${0.48 + rand() * 0.35})`;
    g.lineWidth = 1.6;
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
  const mesh = overlay(track, 0.002, 240, () => true, mat);
  mesh.renderOrder = 1;
  group.add(mesh);
}
