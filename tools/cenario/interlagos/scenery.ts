// Detalhes de pista: borracha e marcas de pneu no traçado, placas de frenagem e a torre de controle.
// Prédios, arquibancadas, lago e mata reais vêm do OSM (osmScenery.ts).
// Fase 2B etapa F: referência do Porsche reconvertida na pista nova (data/reference/); os metros escritos para a
// pista antiga (janelas de freada/saída, placas, torre) passam por ./sNovo.ts e ficam no mesmo lugar físico.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import porscheRef from '../../../data/reference/interlagos-porsche.json';
import { iNovo, L_ANTIGO, s4300 } from './sNovo';

export function buildExtras(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  buildRubber(track, group);
  buildBrakeBoards(track, group);
  buildTower(track, group, heightAt);
}

/**
 * Onde os carros passam, freiam e saem de curva tracionando: é aí que ficam a borracha e as marcas de pneu.
 * Vem da volta real de referência (Porsche, iRacing), amostrada na mesma malha de 2 m da pista; o traçado
 * "elástico" (track.racingLine) fica longe do real (5 m em média) e só serve de reserva.
 */
function driveZones(track: Track) {
  const S = track.samples;
  const N = S.length;
  const ok = porscheRef.d.length === N;
  const d = ok
    ? Float32Array.from(porscheRef.d, (x, i) => Math.max(-(S[i].wl - 0.9), Math.min(S[i].wr - 0.9, x)))
    : track.racingLine();
  const brake = new Float32Array(N);
  const exit = new Float32Array(N);
  const curv = new Float32Array(N);
  // curvatura do traçado (círculo por três pontos a 8 m), suavizada
  const px = Float32Array.from(S, (s, i) => s.p.x + s.r.x * d[i]);
  const pz = Float32Array.from(S, (s, i) => s.p.z + s.r.z * d[i]);
  const raw = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const a = (i - 4 + N) % N;
    const b = (i + 4) % N;
    const ax = px[i] - px[a], az = pz[i] - pz[a];
    const bx = px[b] - px[i], bz = pz[b] - pz[i];
    const cx = px[b] - px[a], cz = pz[b] - pz[a];
    raw[i] = (2 * Math.abs(ax * bz - az * bx)) / Math.max(1e-6, Math.hypot(ax, az) * Math.hypot(bx, bz) * Math.hypot(cx, cz));
  }
  for (let i = 0; i < N; i++) {
    let a = 0;
    for (let j = -3; j <= 3; j++) a += raw[(i + j + N) % N];
    curv[i] = a / 7;
  }
  if (!ok) return { d, curv, brake, exit };
  const { v, brake: pedal, throttle } = porscheRef;
  // freio: forte onde o pedal está fundo, com as pontas suavizadas (média de 10 m)
  for (let i = 0; i < N; i++) {
    let a = 0;
    for (let j = -2; j <= 2; j++) a += Math.min(1, pedal[(i + j + N) % N] / 0.5);
    brake[i] = a / 5;
  }
  // saída: do ponto mais lento de cada curva lenta (< 45 m/s), até 70 m acelerando
  for (let i = 0; i < N; i++) {
    if (v[i] > 45) continue;
    let min = true;
    for (let j = -10; j <= 10 && min; j++) if (j && v[(i + j + N) % N] < v[i]) min = false;
    if (!min) continue;
    for (let j = i, m = 0; m < 70; j = (j + 1) % N, m += STEP) {
      if (throttle[j] < 0.3 && m > 10) break;
      exit[j] = Math.max(exit[j], 1 - m / 70);
    }
  }
  return { d, curv, brake, exit };
}

/** Malha ao longo do traçado ideal (largura 2·half), com transparência por vértice; só onde alpha(i) > 0. */
function lineRibbon(track: Track, d: Float32Array, half: number, lift: number, vScale: number, alpha: (i: number) => number) {
  const S = track.samples;
  const N = S.length;
  const pos: number[] = [];
  const uv: number[] = [];
  const col: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  let prev = -1;
  for (let k = 0; k <= N; k++) {
    const i = k % N;
    const a = alpha(i);
    // mantém um vértice com alpha 0 na ponta de cada trecho para ele sumir suave
    if (a <= 0 && alpha((i + 1) % N) <= 0 && alpha((i - 1 + N) % N) <= 0) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const base = pos.length / 3;
    for (const [off, u] of [[d[i] - half, 0], [d[i] + half, 1]]) {
      v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, lift);
      pos.push(v.x, v.y, v.z);
      uv.push(u, (k * STEP) / vScale);
      col.push(1, 1, 1, Math.max(0, a));
    }
    if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
    prev = base;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 4));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

function alphaTexture(c: HTMLCanvasElement) {
  const t = new THREE.CanvasTexture(c);
  t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

/** volta de referência das janelas abaixo (m): Interlagos */
const LAP = 4300;
const FREADAS: [number, number][] = [
  [160, 295],   // S do Senna
  [1260, 1410], // Descida do Lago
  [1840, 1985], // Ferradura
  [2360, 2450], // Pinheirinho
  [2560, 2680], // Bico de Pato
  [3060, 3190]  // Junção
];
const SAIDAS: [number, number][] = [
  [600, 780],   // Curva do Sol
  [1450, 1590], // Descida do Lago
  [2020, 2220], // Ferradura / Laranjinha
  [2470, 2560], // Pinheirinho
  [2720, 2860], // Bico de Pato
  [3200, 3360]  // Junção
];

function smoothNoise(n: number, step: number, rand: () => number) {
  const k = Math.ceil(n / step) + 2;
  const knots = Array.from({ length: k }, () => rand());
  return (y: number) => {
    const f = y / step;
    const i = Math.floor(f);
    const t = f - i;
    const u = t * t * (3 - 2 * t);
    return knots[i % k] * (1 - u) + knots[(i + 1) % k] * u;
  };
}

/**
 * Pista "suja" como no LMU (Interlagos):
 *  - trilho de borracha no traçado real: duas faixas estreitas e escuras onde passam as rodas, com riscos finos
 *    ao longo da pista e tom variando devagar;
 *  - riscos longos de freada nas freadas fortes, finos, sobrepostos, de tons variados;
 *  - marcas de saída (aceleração/patinada) em forma de vírgula nas saídas de curva.
 */
function buildRubber(track: Track, group: THREE.Group) {
  const { d, curv, brake } = driveZones(track);
  const S = track.samples;
  const rand = mulberry32(23);
  const inWin = (i: number, wins: [number, number][], ramp: number) => {
    // s da amostra nova na escala das janelas (volta antiga de LAP = 4.300 m), pelo mapa de s
    const s = s4300(S[i].s);
    let w = 0;
    for (const [a, b] of wins) w = Math.max(w, Math.max(0, Math.min(1, (s - a) / ramp, (b - s) / ramp)));
    return w;
  };

  // ---- trilho: 3,2 m (u) × 64 m (v); rodas em u = 0,25 e 0,75 (bitola ~1,6 m)
  {
    const W = 128;
    const H = 2048;
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const g = c.getContext('2d')!;
    const img = g.createImageData(W, H);
    const col = Float32Array.from({ length: W }, () => 0.7 + rand() * 0.6);
    const tone = smoothNoise(H, 96, rand);
    const tone2 = smoothNoise(H, 23, rand);
    for (let y = 0; y < H; y++) {
      const along = 0.75 + 0.35 * tone(y) + 0.15 * tone2(y);
      for (let x = 0; x < W; x++) {
        const u = x / (W - 1);
        const wheel = Math.exp(-(((u - 0.25) / 0.075) ** 2)) + Math.exp(-(((u - 0.75) / 0.075) ** 2));
        const haze = Math.exp(-(((u - 0.5) / 0.32) ** 2)) * 0.22;
        const a = Math.min(1, (wheel * 0.95 + haze) * col[x] * along);
        const k = (y * W + x) * 4;
        img.data[k] = 12;
        img.data[k + 1] = 11;
        img.data[k + 2] = 10;
        img.data[k + 3] = a * 255;
      }
    }
    g.putImageData(img, 0, 0);
    const mat = new THREE.MeshStandardMaterial({
      map: alphaTexture(c), vertexColors: true, transparent: true, roughness: 1, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -1
    });
    const strength = (i: number) => Math.min(1, 0.72 + Math.min(1, curv[i] * 70) * 0.2 + brake[i] * 0.2);
    const band = new THREE.Mesh(lineRibbon(track, d, 1.6, 0.014, 64, strength), mat);
    band.receiveShadow = true;
    band.renderOrder = 2;
    group.add(band);
  }

  // ---- riscos de freada e vírgulas de saída
  const strokes = (W: number, H: number, ppmV: number, pxU: number, n: number, kind: 'freada' | 'saida') => {
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const g = c.getContext('2d')!;
    g.lineCap = 'round';
    for (let k = 0; k < n; k++) {
      const y0 = rand() * H;
      const len = (kind === 'freada' ? 5 + Math.pow(rand(), 0.7) * 40 : 4 + rand() * 18) * ppmV;
      const wheelU = rand() < 0.5 ? 0.25 : 0.75;
      const x0 = kind === 'freada' ? (wheelU + (rand() - 0.5) * 0.18) * W : (0.15 + rand() * 0.8) * W;
      const crooked = rand() < (kind === 'freada' ? 0.3 : 1);
      const drift = (crooked ? (rand() - 0.5) * (kind === 'freada' ? 0.5 : 1.6) : (rand() - 0.5) * 0.08) * pxU;
      const wavy = kind === 'freada' && rand() < 0.12 ? (0.04 + rand() * 0.06) * pxU : 0;
      const lines = 2 + Math.floor(rand() * 3);
      const shade = 4 + Math.floor(rand() * 26);
      const alpha = 0.22 + rand() * 0.5;
      for (let r = 0; r < lines; r++) {
        const ox = (r - (lines - 1) / 2) * (0.05 + rand() * 0.05) * pxU;
        const draw = (yy: number) => {
          const steps = 24;
          for (let j = 0; j < steps; j++) {
            const t0 = j / steps;
            const t1 = (j + 1) / steps;
            const wdt = kind === 'saida' ? (1 - t0) * (5 + rand() * 3) + 1 : 1.5 + rand() * 2.5;
            g.strokeStyle = `rgba(${shade}, ${shade}, ${shade - 2}, ${alpha * (kind === 'saida' ? 1 - t0 * 0.6 : 0.8 + rand() * 0.2)})`;
            g.lineWidth = wdt;
            const xa = x0 + ox + drift * t0 * t0 + Math.sin(t0 * 18) * wavy;
            const xb = x0 + ox + drift * t1 * t1 + Math.sin(t1 * 18) * wavy;
            g.beginPath();
            g.moveTo(xa, yy + len * t0);
            g.lineTo(xb, yy + len * t1);
            g.stroke();
          }
        };
        draw(y0);
        if (y0 + len > H) draw(y0 - H);
      }
    }
    return c;
  };
  {
    const W = 128;
    const H = 4096;
    const c = strokes(W, H, H / 96, W / 3.2, 110, 'freada');
    const mat = new THREE.MeshStandardMaterial({
      map: alphaTexture(c), vertexColors: true, transparent: true, roughness: 1, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -2
    });
    const alpha = (i: number) => Math.min(1, inWin(i, FREADAS, 20) * (0.35 + brake[i] * 0.9));
    const m = new THREE.Mesh(lineRibbon(track, d, 1.6, 0.016, 96, alpha), mat);
    m.receiveShadow = true;
    m.renderOrder = 3;
    group.add(m);
  }
  {
    const W = 256;
    const H = 2048;
    const c = strokes(W, H, H / 48, W / 5, 70, 'saida');
    const mat = new THREE.MeshStandardMaterial({
      map: alphaTexture(c), vertexColors: true, transparent: true, roughness: 1, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -3
    });
    const m = new THREE.Mesh(lineRibbon(track, d, 2.5, 0.03, 48, i => inWin(i, SAIDAS, 15)), mat);
    m.receiveShadow = true;
    m.renderOrder = 4;
    group.add(m);
  }
}

/** Placas de 200/150/100/50 m antes das curvas com frenagem forte, do lado de fora da curva (cor por curva). */
function buildBrakeBoards(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  // cores por curva, como no vídeo de referência: brancas no S do Senna, azuis na Descida do Lago, amarelas
  // no resto
  const STYLES = { branca: ['#f4f4f4', '#111111'], azul: ['#1d4fa3', '#ffffff'], amarela: ['#f2c500', '#111111'] } as const;
  type Style = keyof typeof STYLES;
  const styleAt = (s: number): Style => {
    const m = s4300(s);
    if (m < 500 || m > 4100) return 'branca';
    if (m > 1100 && m < 1600) return 'azul';
    return 'amarela';
  };
  const tex = (label: string, style: Style) => {
    const [bg, fg] = STYLES[style];
    const c = document.createElement('canvas');
    c.width = 128;
    c.height = 96;
    const g = c.getContext('2d')!;
    g.fillStyle = bg;
    g.fillRect(0, 0, 128, 96);
    g.strokeStyle = fg;
    g.lineWidth = 8;
    g.strokeRect(4, 4, 120, 88);
    g.fillStyle = fg;
    g.font = 'bold 56px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(label, 64, 50);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return new THREE.MeshStandardMaterial({ map: t, roughness: 0.6 });
  };
  const mats = new Map<string, THREE.Material[]>();
  const back = new THREE.MeshStandardMaterial({ color: 0x55595e, roughness: 0.7 });
  /** materiais da caixa da placa: número na face +z (virada para quem vem), cinza no resto */
  const boardMats = (dist: number, style: Style) => {
    const key = `${dist}-${style}`;
    if (!mats.has(key)) mats.set(key, [back, back, back, back, tex(String(dist), style), back]);
    return mats.get(key)!;
  };
  const board = new THREE.BoxGeometry(1.6, 1.2, 0.06);
  const postGeo = new THREE.CylinderGeometry(0.05, 0.05, 1.9, 6);
  const postMat = new THREE.MeshStandardMaterial({ color: 0x666666, roughness: 0.6 });
  // freadas fortes (s da entrada da curva em m, numa volta de 4.300 m; lado explícito para bater com o LMU).
  const BRAKES: [number, -1 | 1, number[]][] = [
    [290, 1, [200, 150, 100, 50]], // S do Senna (direita, brancas)
    [1376, 1, [150, 100, 50]], // Descida do Lago (direita, azuis)
    [2012, -1, [100, 50]], // Ferradura (esquerda, amarelas)
    [2650, -1, [100, 50]], // Bico de Pato (esquerda, amarelas)
    [3226, 1, [100, 50]] // Junção (direita, amarelas)
  ];
  for (const [entry, outside, dists] of BRAKES) {
    // amostra da entrada na pista ANTIGA (como o código antigo: entry · 4294/4300) e a placa `dist` m antes dela,
    // levadas para a nova pelo mapa (iNovo): cada placa fica no mesmo lugar físico
    const iA = Math.round((entry * L_ANTIGO) / 4300 / STEP);
    const i = iNovo(iA * STEP) % N;
    for (const dist of dists) {
      const j = iNovo((iA - Math.round(dist / STEP)) * STEP) % N;
      const s = S[j];
      // na grama, 2,5 m depois da borda, mas sempre antes do muro
      const off = outside * Math.min((outside < 0 ? s.wl : s.wr) + 2.5, (outside < 0 ? s.wallL : s.wallR) - 0.5);
      const base = s.p.clone().addScaledVector(s.r, off);
      const post = new THREE.Mesh(postGeo, postMat);
      post.position.copy(base).add(new THREE.Vector3(0, 0.95, 0));
      const m = new THREE.Mesh(board, boardMats(dist, styleAt(S[i].s)));
      m.position.copy(base).add(new THREE.Vector3(0, 1.9, 0));
      // virada para quem vem
      m.lookAt(base.clone().sub(s.t).setY(m.position.y));
      group.add(post, m);
    }
  }
}

/** Torre de controle (branca com janelas azuis em dois níveis e placa INTERLAGOS) perto da linha de chegada. */
function buildTower(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const S = track.samples;
  const N = S.length;
  const plain = new THREE.MeshStandardMaterial({ color: 0xf0f1f2, roughness: 0.6 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x1d3552, roughness: 0.15, metalness: 0.6 });
  const metal = new THREE.MeshStandardMaterial({ color: 0xb0b5ba, roughness: 0.4, metalness: 0.7 });
  const s = S[iNovo(L_ANTIGO - 60) % N]; // 60 m antes da linha na pista antiga
  const base = s.p.clone().addScaledVector(s.r, -(s.wl + 20));
  const y = Math.min(s.p.y, heightAt(base.x, base.z));
  const g = new THREE.Group();
  const add = (geo: THREE.BufferGeometry, mat: THREE.Material | THREE.Material[], py: number) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.y = py;
    m.castShadow = true;
    g.add(m);
  };
  add(new THREE.BoxGeometry(6, 17, 6), plain, 8.5);
  add(new THREE.BoxGeometry(9.6, 0.5, 9.6), plain, 17.25);
  add(new THREE.BoxGeometry(9, 3.2, 9), glass, 19.1);
  add(new THREE.BoxGeometry(10.2, 0.5, 10.2), plain, 20.95);
  add(new THREE.BoxGeometry(8.2, 2.8, 8.2), glass, 22.6);
  add(new THREE.BoxGeometry(9.4, 0.6, 9.4), plain, 24.3);
  add(new THREE.CylinderGeometry(0.12, 0.22, 6, 6), metal, 27.6);
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 96;
  const cg = c.getContext('2d')!;
  cg.fillStyle = '#0f3d24';
  cg.fillRect(0, 0, 512, 96);
  cg.fillStyle = '#f5c400';
  cg.fillRect(0, 82, 512, 14);
  cg.fillStyle = '#ffffff';
  cg.font = '900 italic 58px Arial';
  cg.textAlign = 'center';
  cg.textBaseline = 'middle';
  cg.fillText('INTERLAGOS', 256, 44, 490);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const sign = new THREE.MeshStandardMaterial({ map: t, roughness: 0.5 });
  add(new THREE.BoxGeometry(9.4, 1.8, 0.35), [plain, plain, plain, plain, sign, sign], 25.5);
  g.position.set(base.x, y, base.z);
  g.lookAt(s.p.x, y, s.p.z);
  group.add(g);
}
