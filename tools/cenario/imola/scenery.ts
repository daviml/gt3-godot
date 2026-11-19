// Detalhes de pista de Imola: borracha e marcas no traçado real (M4), placas de frenagem (ess_)
// dentro das janelas de visual_profile.json e salsichas amarelas nas chicanes.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import m4Ref from '../../../data/reference/imola-m4.json';
import profile from '../../tracks/imola/visual_profile.json';
import { tex } from './trackDetails';

const LAP = profile.lapLength;

export function buildExtras(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  buildRubber(track, group, renderer);
  buildBrakeBoards(track, group, renderer);
  buildSausages(track, group, renderer);
}

function buildSausages(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const N = S.length;
  const kL = track.length / LAP;

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
  const t = tex(c, renderer, true);
  const mat = new THREE.MeshStandardMaterial({ map: t, roughness: 0.6 });

  for (const sg of profile.sausages) {
    const i0 = Math.round((sg.s0 * kL) / STEP);
    const i1 = Math.round((sg.s1 * kL) / STEP);
    const side = sg.side as -1 | 1;
    const len = Math.max(2.0, (i1 - i0) * STEP);
    const iMid = Math.round((i0 + i1) / 2) % N;
    const s = S[iMid];
    const edge = side < 0 ? s.wl + Math.max(0.9, s.kerbL * 0.5) : s.wr + Math.max(0.9, s.kerbR * 0.5);
    const off = side * (edge + sg.offset);
    const geo = new THREE.CylinderGeometry(0.24, 0.24, Math.min(8.0, len * 0.45), 10, 1, false, 0, Math.PI);
    const m = new THREE.Mesh(geo, mat);
    m.position.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, -0.05);
    const ax = new THREE.Matrix4().makeBasis(s.n, s.t, new THREE.Vector3().crossVectors(s.n, s.t).normalize());
    m.quaternion.setFromRotationMatrix(ax);
    m.castShadow = true;
    m.userData.essential = true;
    group.add(m);
  }
}

function driveZones(track: Track) {
  const S = track.samples;
  const N = S.length;
  const ok = m4Ref.d.length === N;
  const d = ok
    ? Float32Array.from(m4Ref.d, (x, i) => Math.max(-(S[i].wl - 0.9), Math.min(S[i].wr - 0.9, x)))
    : track.racingLine();
  const brake = new Float32Array(N);
  const curv = new Float32Array(N);
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
  if (!ok) return { d, curv, brake };
  const pedal = m4Ref.brake;
  for (let i = 0; i < N; i++) {
    let a = 0;
    for (let j = -2; j <= 2; j++) a += Math.min(1, pedal[(i + j + N) % N] / 0.5);
    brake[i] = a / 5;
  }
  return { d, curv, brake };
}

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
    if (a <= 0 && alpha((i + 1) % N) <= 0 && alpha((i - 1 + N) % N) <= 0) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const base = pos.length / 3;
    for (const [off, u] of [[d[i] - half, 0], [d[i] + half, 1]] as const) {
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

function buildRubber(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const { d, curv, brake } = driveZones(track);
  const S = track.samples;
  const rand = mulberry32(23);
  const kL = track.length / LAP;
  const wins = profile.brakingWindows.map(w => [w.s0, w.s1] as [number, number]);
  const inWin = (i: number, ramp: number) => {
    const s = S[i].s / kL;
    let w = 0;
    for (const [a, b] of wins) w = Math.max(w, Math.max(0, Math.min(1, (s - a) / ramp, (b - s) / ramp)));
    return w;
  };

  // Trilho de borracha no traçado real
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
        const a = Math.min(1, (wheel * 0.9 + haze) * col[x] * along);
        const k = (y * W + x) * 4;
        img.data[k] = 12;
        img.data[k + 1] = 11;
        img.data[k + 2] = 10;
        img.data[k + 3] = a * 245;
      }
    }
    g.putImageData(img, 0, 0);
    const mat = new THREE.MeshStandardMaterial({
      map: tex(c, renderer, true),
      vertexColors: true,
      transparent: true,
      roughness: 1,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -1,
    });
    const strength = (i: number) => Math.min(1, 0.70 + Math.min(1, curv[i] * 70) * 0.2 + brake[i] * 0.2);
    const band = new THREE.Mesh(lineRibbon(track, d, 1.6, 0.014, 64, strength), mat);
    band.receiveShadow = true;
    band.renderOrder = 2;
    group.add(band);
  }

  // Riscos de freada nas zonas da telemetria
  {
    const W = 128;
    const H = 4096;
    const ppmV = H / 96;
    const pxU = W / 3.2;
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const g = c.getContext('2d')!;
    g.lineCap = 'round';
    for (let k = 0; k < 110; k++) {
      const y0 = rand() * H;
      const len = (6 + Math.pow(rand(), 0.7) * 38) * ppmV;
      const wheelU = rand() < 0.5 ? 0.25 : 0.75;
      const x0 = (wheelU + (rand() - 0.5) * 0.18) * W;
      const drift = (rand() - 0.5) * 0.35 * pxU;
      const lines = 2 + Math.floor(rand() * 3);
      const shade = 6 + Math.floor(rand() * 24);
      const alpha = 0.20 + rand() * 0.45;
      for (let r = 0; r < lines; r++) {
        const ox = (r - (lines - 1) / 2) * 0.06 * pxU;
        const draw = (yy: number) => {
          g.strokeStyle = `rgba(${shade}, ${shade}, ${shade - 2}, ${alpha})`;
          g.lineWidth = 1.6 + rand() * 2.2;
          g.beginPath();
          g.moveTo(x0 + ox, yy);
          g.lineTo(x0 + ox + drift, yy + len);
          g.stroke();
        };
        draw(y0);
        if (y0 + len > H) draw(y0 - H);
      }
    }
    const mat = new THREE.MeshStandardMaterial({
      map: tex(c, renderer, true),
      vertexColors: true,
      transparent: true,
      roughness: 1,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
    });
    const alpha = (i: number) => Math.min(1, inWin(i, 20) * (0.35 + brake[i] * 0.85));
    const m = new THREE.Mesh(lineRibbon(track, d, 1.6, 0.017, 96, alpha), mat);
    m.receiveShadow = true;
    m.renderOrder = 3;
    group.add(m);
  }
}

function buildBrakeBoards(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const N = S.length;
  const boardTex = (label: string) => {
    const c = document.createElement('canvas');
    c.width = 160;
    c.height = 96;
    const g = c.getContext('2d')!;
    g.fillStyle = '#f4f4f4';
    g.fillRect(0, 0, 160, 96);
    g.strokeStyle = '#111111';
    g.lineWidth = 8;
    g.strokeRect(4, 4, 152, 88);
    g.fillStyle = '#111111';
    g.font = 'bold 54px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(label, 80, 50);
    return new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.6 });
  };
  const back = new THREE.MeshStandardMaterial({ color: 0x55595e, roughness: 0.7 });
  const mats = new Map<number, THREE.Material[]>();
  const boardMats = (dist: number) => {
    if (!mats.has(dist)) mats.set(dist, [back, back, back, back, boardTex(String(dist)), back]);
    return mats.get(dist)!;
  };
  const boardGeo = new THREE.BoxGeometry(1.75, 1.15, 0.06);
  const postGeo = new THREE.CylinderGeometry(0.05, 0.05, 2.0, 6);
  const postMat = new THREE.MeshStandardMaterial({ color: 0x666666, roughness: 0.6 });

  const v = m4Ref.v as number[];
  const pedal = m4Ref.brake as number[];
  const cs = (i: number) => {
    let a = 0;
    for (let k = -3; k <= 3; k++) a += S[(i + k + N) % N].curv;
    return a / 7;
  };
  const kB = track.length / LAP;
  for (const w of profile.brakingWindows) {
    if (v.length !== N) break;
    let i0 = -1;
    for (let i = Math.round((w.s0 * kB) / STEP); i < Math.round((w.s1 * kB) / STEP); i++) {
      if (pedal[i % N] >= 0.3 && pedal[(i - 1 + N) % N] < 0.3) {
        i0 = i % N;
        break;
      }
    }
    if (i0 < 0) continue;
    let jmin = i0;
    for (let k = 0; k < 140; k++) if (v[(i0 + k) % N] < v[jmin]) jmin = (i0 + k) % N;
    const dir = Math.sign(cs(jmin)) || -1;
    let e = i0;
    for (let k = -10; k < 160; k++) {
      const j = (i0 + k + N) % N;
      if (Math.abs(cs(j)) > 1 / 140 && Math.sign(cs(j)) === dir) {
        e = j;
        break;
      }
    }
    const outside: -1 | 1 = dir > 0 ? -1 : 1;
    for (const dist of w.labels) {
      const j = (e - Math.round(dist / STEP) + N) % N;
      if (Math.abs(cs(j)) > 1 / 120) continue;
      const s = S[j];
      const edge = (outside < 0 ? s.wl + s.kerbL : s.wr + s.kerbR) + 2.2;
      const off = outside * Math.min(edge, (outside < 0 ? s.wallL : s.wallR) - 0.45);
      const base = s.p.clone().addScaledVector(s.r, off);
      const post = new THREE.Mesh(postGeo, postMat);
      post.position.copy(base).add(new THREE.Vector3(0, 1.0, 0));
      const m = new THREE.Mesh(boardGeo, boardMats(dist));
      m.position.copy(base).add(new THREE.Vector3(0, 1.95, 0));
      m.lookAt(base.clone().sub(s.t).setY(m.position.y));
      post.userData.essential = true;
      m.userData.essential = true;
      group.add(post, m);
    }
  }
}
