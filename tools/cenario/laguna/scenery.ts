// Cópia adaptada para Laguna Seca (tools/cenario/vite.config.ts troca o módulo do web por este só com
// TRACK=laguna-seca): borracha pela volta real do iRacing em Laguna (M4) e placas de freada 3/2/1 achadas na
// própria telemetria (onde o piloto freia forte), brancas com número preto como no LMU.
// Detalhes de pista: borracha e marcas de pneu no traçado, placas de frenagem e a torre de controle.
// Prédios, arquibancadas, lago e mata reais vêm do OSM (osmScenery.ts).
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import porscheRef from '../../../data/reference/laguna-seca-m4.json';

/** volta de referência das tabelas (m): Laguna Seca */
const LAP = 3598;

export function buildExtras(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  buildRubber(track, group);
  buildBrakeBoards(track, group);
  buildTower(track, group, heightAt);
  buildFlag(track, group, heightAt);
  buildSausage(track, group);
}

/**
 * Bandeira grande no alto do Corkscrew (LMU), no morro por dentro da T8: mastro de 20 m e bandeira listrada
 * vermelha e branca com o cantão azul (desenho genérico).
 */
function buildFlag(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const S = track.samples;
  const s = S[Math.round((2420 * track.length) / LAP / STEP) % S.length];
  const rh = new THREE.Vector3(s.r.x, 0, s.r.z).normalize();
  const base = s.p.clone().addScaledVector(rh, -(s.wallL + 9));
  const y = heightAt(base.x, base.z);
  const c = document.createElement('canvas');
  c.width = 380;
  c.height = 200;
  const g = c.getContext('2d')!;
  for (let k = 0; k < 13; k++) {
    g.fillStyle = k % 2 ? '#ffffff' : '#b22234';
    g.fillRect(0, (k * 200) / 13, 380, 200 / 13 + 1);
  }
  g.fillStyle = '#3c3b6e';
  g.fillRect(0, 0, 152, 108);
  g.fillStyle = '#ffffff';
  for (let r = 0; r < 9; r++) for (let k = 0; k < (r % 2 ? 5 : 6); k++) {
    g.beginPath();
    g.arc(13 + k * 25 + (r % 2 ? 12 : 0), 8 + r * 11.5, 3, 0, Math.PI * 2);
    g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.18, 20, 8), new THREE.MeshStandardMaterial({ color: 0xd8d8d8, metalness: 0.6, roughness: 0.4 }));
  pole.position.set(base.x, y + 10, base.z);
  const flag = new THREE.Mesh(new THREE.PlaneGeometry(7.6, 4), new THREE.MeshStandardMaterial({ map: t, side: THREE.DoubleSide, roughness: 0.8 }));
  // tremulando para o lado da pista que vem (vento do mar, de oeste)
  flag.position.set(base.x - 3.9, y + 17.9, base.z);
  flag.rotation.y = 0.35;
  for (const m of [pole, flag]) {
    m.castShadow = true;
    m.userData.essential = true;
    group.add(m);
  }
}

/** "Salsicha" amarela por dentro do ápice da T8 (Corkscrew), logo depois da zebra (LMU): só visual. */
function buildSausage(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 64;
  const g = c.getContext('2d')!;
  g.fillStyle = '#f2c500';
  g.fillRect(0, 0, 64, 64);
  g.fillStyle = '#1b1b1b';
  for (let k = -64; k < 64; k += 22) {
    g.beginPath();
    g.moveTo(k, 64);
    g.lineTo(k + 10, 64);
    g.lineTo(k + 74, 0);
    g.lineTo(k + 64, 0);
    g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const mat = new THREE.MeshStandardMaterial({ map: t, roughness: 0.6 });
  // ápice da T8 (curva para a esquerda): por dentro = esquerda
  const i0 = Math.round((2446 * track.length) / LAP / STEP) % N;
  for (let k = 0; k < 2; k++) {
    const s = S[(i0 + k) % N];
    const off = -(s.wl + s.kerbL + 0.7);
    const geo = new THREE.CylinderGeometry(0.3, 0.3, 1.9, 10, 1, false, 0, Math.PI);
    const m = new THREE.Mesh(geo, mat);
    m.position.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, -0.02);
    // deitada ao longo da pista, com a parte curva para cima
    const ax = new THREE.Matrix4().makeBasis(s.r, s.t, new THREE.Vector3().crossVectors(s.r, s.t).negate());
    m.quaternion.setFromRotationMatrix(ax);
    m.rotateY(Math.PI / 2);
    m.castShadow = true;
    m.userData.essential = true;
    group.add(m);
  }
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

/** volta de referência das janelas abaixo (m): Laguna Seca */
const FREADAS: [number, number][] = [[250, 450], [1300, 1480], [2300, 2450], [2840, 2965], [3120, 3255]]; // T2, T5, T8, T10, T11
const SAIDAS: [number, number][] = [[490, 620], [760, 880], [1050, 1160], [1500, 1620], [2470, 2540], [3262, 3380]]; // Andretti, T3, T4, T5, T8A, T11

/** ruído 1D suave (valores sorteados a cada `step` linhas, interpolados) para variar o tom ao longo da pista */
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
 * Pista "suja" como no LMU (Laguna):
 *  - trilho de borracha no traçado real: duas faixas estreitas e escuras onde passam as rodas, com riscos finos
 *    ao longo da pista e tom variando devagar (nada de blocos: era o que fazia listras atravessadas);
 *  - riscos longos de freada antes da T2, T5, T8, T10 e T11, finos, sobrepostos, de tons variados, alguns tortos
 *    ou travados (ondulados);
 *  - marcas de saída (aceleração/patinada) em forma de vírgula nas saídas da Andretti, T3, T4, T5, T8A e T11,
 *    numa faixa larga que passa por cima da zebra e da faixa verde.
 * Três malhas que dão a volta (baratas, valem também no Mínimo).
 */
function buildRubber(track: Track, group: THREE.Group) {
  const { d, curv, brake } = driveZones(track);
  const S = track.samples;
  const N = S.length;
  const rand = mulberry32(23);
  const kL = track.length / LAP;
  const inWin = (i: number, wins: [number, number][], ramp: number) => {
    const s = S[i].s / kL;
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
    const col = Float32Array.from({ length: W }, () => 0.7 + rand() * 0.6); // riscos ao longo da pista
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
    // alturas maiores que no web: o Godot não tem o polygonOffset do three.js e, rente ao chão, o trilho a 3 mm
    // "brigava" com o asfalto (listras claras atravessadas)
    const band = new THREE.Mesh(lineRibbon(track, d, 1.6, 0.014, 64, strength), mat);
    band.receiveShadow = true;
    band.renderOrder = 2;
    group.add(band);
  }

  // ---- riscos de freada: 3,2 m × 96 m de textura, ~110 riscos (2 a 4 linhas finas cada)
  const strokes = (W: number, H: number, ppmV: number, pxU: number, n: number, kind: 'freada' | 'saida') => {
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const g = c.getContext('2d')!;
    g.lineCap = 'round';
    for (let k = 0; k < n; k++) {
      const y0 = rand() * H;
      const len = (kind === 'freada' ? 5 + Math.pow(rand(), 0.7) * 40 : 4 + rand() * 18) * ppmV;
      // perto das rodas (u 0,25 / 0,75) ou soltos (saídas: espalhados até a zebra)
      const wheelU = rand() < 0.5 ? 0.25 : 0.75;
      const x0 = kind === 'freada' ? (wheelU + (rand() - 0.5) * 0.18) * W : (0.15 + rand() * 0.8) * W;
      const crooked = rand() < (kind === 'freada' ? 0.3 : 1);
      const drift = (crooked ? (rand() - 0.5) * (kind === 'freada' ? 0.5 : 1.6) : (rand() - 0.5) * 0.08) * pxU;
      const wavy = kind === 'freada' && rand() < 0.12 ? (0.04 + rand() * 0.06) * pxU : 0; // roda travada
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
            // vírgula: começa grossa e afina; freada: largura quase constante
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
        if (y0 + len > H) draw(y0 - H); // continua do outro lado da emenda
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

  // ---- vírgulas de saída: faixa de 5 m centrada no traçado, acima da zebra (0,012) e da faixa verde
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
  void N;
}

/** Placas de 200/150/100/50 m antes das curvas com frenagem forte, do lado de fora da curva (cor por curva). */
function buildBrakeBoards(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const STYLES = { branca: ['#f4f4f4', '#111111'] } as const;
  type Style = keyof typeof STYLES;
  const styleAt = (_s: number): Style => 'branca';
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
  // Freadas fortes da volta real (T2, T5, T8, T10, T11): onde o pedal do iRacing passa de 30% dentro de cada janela.
  // A placa é ancorada na ENTRADA da curva (primeira amostra depois do início da freada em que a curvatura passa
  // de 1/120 m no mesmo sentido da curva onde fica a velocidade mínima; senão a T7 "roubava" a do Corkscrew) e
  // fica a 150/100/50 m antes dela (placas 3/2/1), do lado de fora da curva que vem. Placa que cairia dentro de uma
  // curva anterior (raio < 120 m) não é posta.
  const BRAKES: [number, number[], -1 | 1][] = [];
  const v = porscheRef.v as number[];
  const pedal = porscheRef.brake as number[];
  const cs = (i: number) => {
    let a = 0;
    for (let k = -3; k <= 3; k++) a += S[(i + k + N) % N].curv;
    return a / 7;
  };
  const kB = track.length / LAP;
  const JANELAS: [number, number][] = [[250, 450], [1300, 1480], [2300, 2450], [2840, 2965], [3120, 3255]];
  if (v.length === N) {
    for (const [a, b] of JANELAS) {
      let i0 = -1;
      for (let i = Math.round((a * kB) / STEP); i < Math.round((b * kB) / STEP); i++) {
        if (pedal[i % N] >= 0.3 && pedal[(i - 1 + N) % N] < 0.3) { i0 = i % N; break; }
      }
      if (i0 < 0) continue;
      let jmin = i0;
      for (let k = 0; k < 120; k++) if (v[(i0 + k) % N] < v[jmin]) jmin = (i0 + k) % N;
      const dir = Math.sign(cs(jmin)) || 1;
      let e = i0;
      for (let k = -10; k < 150; k++) {
        const j = (i0 + k + N) % N;
        if (Math.abs(cs(j)) > 1 / 120 && Math.sign(cs(j)) === dir) { e = j; break; }
      }
      // fora da curva que vem: curva para a direita (curv > 0) → placas à esquerda
      BRAKES.push([(e * STEP) / kB, [3, 2, 1], dir > 0 ? -1 : 1]);
      console.info('placas de freada: pedal>30% s=' + Math.round((i0 * STEP) / kB) + ', entrada s=' + Math.round((e * STEP) / kB));
    }
  }
  const DIST: Record<number, number> = { 3: 150, 2: 100, 1: 50 };
  for (const [entry, dists, outside] of BRAKES) {
    const i = Math.round((entry * track.length) / LAP / STEP) % N;
    for (const dist of dists) {
      const j = (i - Math.round(DIST[dist] / STEP) + N) % N;
      if (Math.abs(cs(j)) > 1 / 120) continue; // dentro de uma curva anterior: sem placa
      const s = S[j];
      // na brita/grama, 2,5 m depois da borda (e da zebra), mas sempre antes do muro
      const edge = (outside < 0 ? s.wl + s.kerbL : s.wr + s.kerbR) + 2.5;
      const off = outside * Math.min(edge, (outside < 0 ? s.wallL : s.wallR) - 0.5);
      const base = s.p.clone().addScaledVector(s.r, off);
      const post = new THREE.Mesh(postGeo, postMat);
      post.position.copy(base).add(new THREE.Vector3(0, 0.95, 0));
      const m = new THREE.Mesh(board, boardMats(dist, styleAt(S[i].s)));
      m.position.copy(base).add(new THREE.Vector3(0, 1.9, 0));
      // virada para quem vem
      m.lookAt(base.clone().sub(s.t).setY(m.position.y));
      for (const o of [post, m]) o.userData.essential = true;
      group.add(post, m);
      console.info('  placa ' + dist + ' em s=' + Math.round((j * STEP) / kB) + (outside < 0 ? ' (esquerda)' : ' (direita)'));
    }
  }
}

/**
 * Torre de controle de Laguna perto da linha de chegada, atrás dos boxes: esguia, branca, cabine envidraçada
 * escura em dois andares e uma placa "LAGUNA SECA" no topo, virada para a reta.
 */
function buildTower(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const S = track.samples;
  const N = S.length;
  const plain = new THREE.MeshStandardMaterial({ color: 0xeeeeec, roughness: 0.6 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x1c2733, roughness: 0.12, metalness: 0.65 });
  const s = S[N - Math.round(40 / STEP)];
  const rh = new THREE.Vector3(s.r.x, 0, s.r.z).normalize();
  const base = s.p.clone().addScaledVector(rh, -(s.wallL + 34));
  const y = Math.min(s.p.y, heightAt(base.x, base.z));
  const g = new THREE.Group();
  const add = (geo: THREE.BufferGeometry, mat: THREE.Material | THREE.Material[], py: number) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.y = py;
    m.castShadow = true;
    m.userData.essential = true;
    g.add(m);
  };
  add(new THREE.BoxGeometry(5, 20, 5), plain, 10);
  add(new THREE.BoxGeometry(10, 3.2, 10), glass, 21.8);
  add(new THREE.BoxGeometry(10.6, 0.5, 10.6), plain, 23.6);
  add(new THREE.BoxGeometry(9, 3, 9), glass, 25.4);
  add(new THREE.BoxGeometry(9.6, 0.6, 9.6), plain, 27.2);
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 96;
  const cg = c.getContext('2d')!;
  cg.fillStyle = '#14306b';
  cg.fillRect(0, 0, 512, 96);
  cg.fillStyle = '#ffffff';
  cg.font = '900 italic 58px Arial';
  cg.textAlign = 'center';
  cg.textBaseline = 'middle';
  cg.fillText('LAGUNA SECA', 256, 50, 490);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const sign = new THREE.MeshStandardMaterial({ map: t, roughness: 0.5 });
  add(new THREE.BoxGeometry(9.6, 1.8, 0.3), [plain, plain, plain, plain, sign, sign], 28.6);
  g.position.set(base.x, y, base.z);
  // placa virada para a reta
  g.lookAt(s.p.x, y, s.p.z);
  group.add(g);
}
