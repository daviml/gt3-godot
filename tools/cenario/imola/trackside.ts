// Arquibancadas (construídas e naturais), torcida, boxes à direita da reta principal, postos de fiscal,
// torres de TV e cones de Imola — lidos de visual_profile.json, com fundações -3,5 m e costas escuras.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import { AdScheme, adCanvas, tex } from './trackDetails';
import profile from '../../tracks/imola/visual_profile.json';

const LAP = profile.lapLength;

function overOther(track: Track, p: THREE.Vector3, i: number, margin: number): boolean {
  const N = track.samples.length;
  const loc = track.locate(p);
  if (!loc) return false;
  const di = Math.min(Math.abs(loc.i - i), N - Math.abs(loc.i - i));
  return di > 40 && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + margin;
}

function crowdTexture(renderer: THREE.WebGLRenderer, seatColor: string): THREE.Texture {
  const W = 512;
  const ppm = W / 8;
  const c = document.createElement('canvas');
  c.width = c.height = W;
  const g = c.getContext('2d')!;
  const rowH = 0.8 * ppm;
  for (let r = 0; r < 10; r++) {
    const y = r * rowH;
    g.fillStyle = '#5e6266';
    g.fillRect(0, y, W, rowH);
    g.fillStyle = seatColor;
    g.fillRect(0, y + rowH * 0.15, W, rowH * 0.55);
    g.fillStyle = 'rgba(0,0,0,0.22)';
    for (let x = 0; x < W; x += 0.5 * ppm) g.fillRect(x + 2, y + rowH * 0.15, 0.42 * ppm, rowH * 0.18);
    g.fillStyle = 'rgba(0,0,0,0.38)';
    g.fillRect(0, y + rowH * 0.92, W, rowH * 0.08);
  }
  return tex(c, renderer, true);
}

/** Fachada traseira arquitetônica escura (concreto cinza-escuro + juntas + vidros fumê) para não estourar ao sol. */
function darkBackTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 256;
  const g = c.getContext('2d')!;
  g.fillStyle = '#3b4047';
  g.fillRect(0, 0, 512, 256);
  g.fillStyle = '#252a30';
  g.fillRect(0, 88, 512, 42);
  g.fillRect(0, 165, 512, 36);
  g.fillStyle = '#4e545c';
  for (let x = 0; x < 512; x += 64) g.fillRect(x, 0, 6, 256);
  return tex(c, renderer, true);
}

const CROWD_COLS = 8;
const CROWD_ROWS = 4;

function crowdAtlas(renderer: THREE.WebGLRenderer): THREE.Texture {
  const cw = 64;
  const ch = 128;
  const c = document.createElement('canvas');
  c.width = cw * CROWD_COLS;
  c.height = ch * CROWD_ROWS;
  const g = c.getContext('2d')!;
  const rand = mulberry32(177);
  const shirts = ['#cd212a', '#cd212a', '#ffffff', '#ffffff', '#008c45', '#1d4fa3', '#222222', '#f2c500', '#ff7a1a', '#7fc3e8', '#e8e2d0', '#333333'];
  const skins = ['#f1c9a5', '#d9a77e', '#b07a52', '#7a4e32', '#5a3a26'];
  const hairs = ['#1d1510', '#3b2a1c', '#6b4a2b', '#c9a35b', '#2a2a2a'];
  for (let k = 0; k < CROWD_COLS * CROWD_ROWS; k++) {
    const cx = (k % CROWD_COLS) * cw;
    const cy = (CROWD_ROWS - 1 - Math.floor(k / CROWD_COLS)) * ch;
    const shirt = shirts[Math.floor(rand() * shirts.length)];
    const skin = skins[Math.floor(rand() * skins.length)];
    const standing = rand() < 0.35;
    const armsUp = rand() < 0.2;
    const w = 26 + rand() * 10;
    const x0 = cx + (cw - w) / 2;
    const shoulder = cy + (standing ? 34 : 58);
    if (standing) {
      g.fillStyle = rand() < 0.6 ? '#2b3a55' : '#3a3530';
      g.fillRect(x0 + 3, shoulder + 40, w - 6, ch - (shoulder - cy) - 40);
    }
    g.fillStyle = shirt;
    g.beginPath();
    g.roundRect(x0, shoulder, w, ch - (shoulder - cy), [8, 8, 0, 0]);
    g.fill();
    g.fillStyle = armsUp ? skin : shirt;
    if (armsUp) {
      g.fillRect(x0 - 5, shoulder - 30, 6, 36);
      g.fillRect(x0 + w - 1, shoulder - 30, 6, 36);
    } else {
      g.fillRect(x0 - 4, shoulder + 4, 6, 30);
      g.fillRect(x0 + w - 2, shoulder + 4, 6, 30);
    }
    const hr = 9 + rand() * 2;
    const hx = cx + cw / 2;
    const hy = shoulder - hr - 2;
    g.fillStyle = skin;
    g.fillRect(hx - 4, shoulder - 5, 8, 6);
    g.beginPath();
    g.arc(hx, hy, hr, 0, Math.PI * 2);
    g.fill();
    if (rand() < 0.3) {
      g.fillStyle = shirts[Math.floor(rand() * shirts.length)];
      g.fillRect(hx - hr, hy - hr, hr * 2, hr * 0.8);
      g.fillRect(hx - hr, hy - hr * 0.35, hr * 2.5, 3);
    } else {
      g.fillStyle = hairs[Math.floor(rand() * hairs.length)];
      g.beginPath();
      g.arc(hx, hy - 2, hr, Math.PI, Math.PI * 2);
      g.fill();
    }
    // Bandeira tricolor italiana em alguns torcedores
    if (armsUp && rand() < 0.45) {
      g.fillStyle = '#008c45';
      g.fillRect(cx + 4, shoulder - 54, (cw - 8) / 3, 24);
      g.fillStyle = '#f4f5f0';
      g.fillRect(cx + 4 + (cw - 8) / 3, shoulder - 54, (cw - 8) / 3, 24);
      g.fillStyle = '#cd212a';
      g.fillRect(cx + 4 + (2 * (cw - 8)) / 3, shoulder - 54, (cw - 8) / 3, 24);
    }
  }
  return tex(c, renderer, false);
}

interface Fan {
  p: THREE.Vector3;
  face: THREE.Vector3;
  cell: number;
}

function buildCrowd(fans: Fan[], group: THREE.Group, renderer: THREE.WebGLRenderer) {
  if (!fans.length) return;
  const geo = new THREE.PlaneGeometry(0.5, 1).translate(0, 0.5, 0);
  const cells = new Float32Array(fans.length);
  const mat = new THREE.MeshStandardMaterial({
    map: crowdAtlas(renderer),
    alphaTest: 0.5,
    side: THREE.DoubleSide,
    roughness: 0.9,
  });
  mat.onBeforeCompile = shader => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float aCell;')
      .replace(
        '#include <uv_vertex>',
        `#include <uv_vertex>
        vMapUv = (vMapUv + vec2(mod(aCell, ${CROWD_COLS}.0), floor(aCell / ${CROWD_COLS}.0))) / vec2(${CROWD_COLS}.0, ${CROWD_ROWS}.0);`
      );
  };
  const mesh = new THREE.InstancedMesh(geo, mat, fans.length);
  const m = new THREE.Matrix4();
  const x = new THREE.Vector3();
  const up = new THREE.Vector3(0, 1, 0);
  const sc = new THREE.Vector3();
  const q = new THREE.Quaternion();
  fans.forEach((f, i) => {
    x.crossVectors(up, f.face).normalize();
    q.setFromRotationMatrix(m.makeBasis(x, up, f.face));
    const k = 0.92 + ((i * 7919) % 17) / 100;
    m.compose(f.p, q, sc.set(k, k, k));
    mesh.setMatrixAt(i, m);
    cells[i] = f.cell;
  });
  geo.setAttribute('aCell', new THREE.InstancedBufferAttribute(cells, 1));
  mesh.computeBoundingSphere();
  group.add(mesh);
  console.info(`torcida: ${fans.length} pessoas`);
}

interface StandMats {
  concrete: THREE.Material;
  back: THREE.Material;
  roof: THREE.Material;
  steel: THREE.Material;
  slope: THREE.Material;
}

function buildStand(
  track: Track,
  group: THREE.Group,
  renderer: THREE.WebGLRenderer,
  mats: StandMats,
  st: (typeof profile.stands)[number],
  fans: Fan[],
  rand: () => number
) {
  const S = track.samples;
  const N = S.length;
  const k = track.length / LAP;
  const i0 = Math.round((st.s0 * k) / STEP);
  const i1 = Math.round((st.s1 * k) / STEP);
  const side = st.side as -1 | 1;
  const depth = st.depth;
  const natural = !!(st as { naturalSlope?: boolean }).naturalSlope;
  const at = (j: number) => S[((j % N) + N) % N];
  const rise = depth * (natural ? 0.36 : 0.55);
  const front = natural ? 0.6 : 2.6;
  const d0 = natural ? 2.5 : 3.5;
  const d1 = d0 + depth;
  const tmp = new THREE.Vector3();
  const ok: boolean[] = [];
  for (let j = i0; j <= i1; j++) {
    const s = at(j);
    const i = ((j % N) + N) % N;
    const wall = side < 0 ? s.wallL : s.wallR;
    ok.push(
      !overOther(track, tmp.copy(s.p).addScaledVector(s.r, side * (wall + d1)), i, 6) &&
        !overOther(track, tmp.copy(s.p).addScaledVector(s.r, side * (wall + d0)), i, 6)
    );
  }
  const band = (a: [number, number], b: [number, number], mat: THREE.Material, vLen: number, shadow: boolean) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let j = i0; j <= i1; j++) {
      if (!ok[j - i0]) {
        prev = -1;
        continue;
      }
      const s = at(j);
      const wall = side < 0 ? s.wallL : s.wallR;
      const base = pos.length / 3;
      for (const [[d, h], u] of [[a, 0], [b, 1]] as const) {
        v.copy(s.p).addScaledVector(s.r, side * (wall + d));
        v.y += h;
        pos.push(v.x, v.y, v.z);
        uv.push(((j - i0) * STEP) / 8, (u * vLen) / 8);
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
    m.castShadow = shadow;
    m.receiveShadow = true;
    group.add(m);
  };

  if (natural) {
    band([d0, -1.5], [d1, front + rise], mats.slope, Math.hypot(depth, rise), false);
  } else {
    const seatMat = new THREE.MeshStandardMaterial({
      map: crowdTexture(renderer, st.seatColor),
      roughness: 0.9,
      side: THREE.DoubleSide,
    });
    band([d0, front], [d1, front + rise], seatMat, Math.hypot(depth, rise), false);
    band([d0, -3.5], [d0, front], mats.concrete, front + 3.5, false);
    band([d1, -3.5], [d1, front + rise + 1.2], mats.back, front + rise + 4.7, true);
  }

  const rows = Math.floor(depth / 0.85);
  const face = new THREE.Vector3();
  for (let j = i0; j < i1; j++) {
    if (!ok[j - i0] || !ok[j + 1 - i0]) continue;
    const s = at(j);
    const wall = side < 0 ? s.wallL : s.wallR;
    face.copy(s.r).multiplyScalar(-side).setY(0).normalize();
    for (let r = 0; r < rows; r++) {
      const d = d0 + (r + 0.55) * (depth / rows);
      const h = front + (rise * (d - d0)) / depth - 0.35;
      for (let u = rand() * 0.3; u < STEP; u += 0.55 + rand() * 0.16) {
        if (rand() < (natural ? 0.38 : 0.25)) continue;
        const p = s.p.clone().addScaledVector(s.r, side * (wall + d)).addScaledVector(s.t, u);
        p.y += h;
        fans.push({ p, face: face.clone(), cell: Math.floor(rand() * CROWD_COLS * CROWD_ROWS) });
      }
    }
  }

  if (!st.roof || natural) return;
  const top = front + rise + 4.6;
  const front0 = d0 + depth * 0.28;
  band([d1 + 0.5, top], [front0, top - 0.9], mats.roof, depth, true);
  const beam = new THREE.BoxGeometry(0.22, 1, 0.22).translate(0, 0.5, 0);
  const steel = mats.steel;
  const up = new THREE.Vector3(0, 1, 0);
  const a3 = new THREE.Vector3();
  const b3 = new THREE.Vector3();
  const bar = (a: THREE.Vector3, b: THREE.Vector3, thick = 1) => {
    const len = a.distanceTo(b);
    const m = new THREE.Mesh(beam, steel);
    m.position.copy(a);
    m.quaternion.setFromUnitVectors(up, b3.copy(b).sub(a).normalize());
    m.scale.set(thick, len, thick);
    m.castShadow = true;
    group.add(m);
  };
  const point = (s: (typeof S)[number], d: number, h: number, out: THREE.Vector3) => {
    const wall = side < 0 ? s.wallL : s.wallR;
    return out.copy(s.p).addScaledVector(s.r, side * (wall + d)).setY(s.p.y + h);
  };
  for (let j = i0; j <= i1; j += 8) {
    if (!ok[j - i0]) continue;
    const s = at(j);
    const base = point(s, d1 + 0.3, -3.5, new THREE.Vector3());
    const colTop = point(s, d1 + 0.3, top + 0.1, new THREE.Vector3());
    bar(base, colTop, 2.2);
    const tip = point(s, front0 + 0.2, top - 0.95, new THREE.Vector3());
    bar(colTop, tip, 1.2);
    bar(point(s, d1 + 0.3, top - 3.2, a3), tip, 0.8);
  }
}

const PIT = profile.pit;

function inRange(track: Track, s: number, a: number, b: number) {
  const L = track.length;
  const k = L / LAP;
  const x = (((s - a * k) % L) + L) % L;
  return x <= (b - a) * k;
}

export function occupied(track: Track, x: number, z: number, y: number): boolean {
  const loc = track.locate(new THREE.Vector3(x, y, z));
  if (!loc) return false;
  const pitSide = PIT.side as -1 | 1;
  if (loc.d * pitSide > 0 && inRange(track, loc.s, PIT.s0 - 30, PIT.s1 + 30) && Math.abs(loc.d) < (pitSide < 0 ? loc.wallL : loc.wallR) + PIT.garageFrom + PIT.garageDepth + 8) {
    return true;
  }
  return profile.stands.some(st => {
    const off = st.side * loc.d;
    const wall = st.side < 0 ? loc.wallL : loc.wallR;
    return off > 0 && inRange(track, loc.s, st.s0 - 10, st.s1 + 10) && off < wall + 3 + st.depth + 5;
  });
}

export function buildStands(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, concrete: THREE.Material) {
  const mats: StandMats = {
    concrete,
    back: new THREE.MeshStandardMaterial({ map: darkBackTexture(renderer), roughness: 0.8, side: THREE.DoubleSide }),
    roof: new THREE.MeshStandardMaterial({ color: 0x3b4048, roughness: 0.55, metalness: 0.3, side: THREE.DoubleSide }),
    steel: new THREE.MeshStandardMaterial({ color: 0x9aa0a8, roughness: 0.4, metalness: 0.6, side: THREE.DoubleSide }),
    slope: new THREE.MeshStandardMaterial({ name: 'grama', color: 0x5c7c3d, roughness: 0.99, side: THREE.DoubleSide }),
  };
  const fans: Fan[] = [];
  const rand = mulberry32(31);
  for (const st of profile.stands) buildStand(track, group, renderer, mats, st, fans, rand);
  buildCrowd(fans, group, renderer);
}

function wallBand(
  track: Track,
  group: THREE.Group,
  s0: number,
  s1: number,
  side: -1 | 1,
  a: [number, number],
  b: [number, number],
  mat: THREE.Material,
  uTile: number,
  shadow = false
) {
  const S = track.samples;
  const N = S.length;
  const k = track.length / LAP;
  const i0 = Math.round((s0 * k) / STEP);
  const i1 = Math.round((s1 * k) / STEP);
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  for (let j = i0; j <= i1; j++) {
    const s = S[((j % N) + N) % N];
    const wall = side < 0 ? s.wallL : s.wallR;
    for (const [[d, h], u] of [[a, 0], [b, 1]] as const) {
      v.copy(s.p).addScaledVector(s.r, side * (wall + d));
      v.y += h;
      pos.push(v.x, v.y, v.z);
      uv.push(((side < 0 ? 1 : -1) * (j - i0) * STEP) / uTile, u);
    }
    if (j > i0) {
      const base = (j - i0) * 2;
      idx.push(base - 2, base - 1, base, base - 1, base + 1, base);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const m = new THREE.Mesh(geo, mat);
  m.castShadow = shadow;
  m.receiveShadow = true;
  group.add(m);
  return m;
}

function garageTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const W = 1024;
  const H = 384;
  const ppm = W / 24;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const hpm = H / PIT.garageH;
  const y = (h: number) => H - h * hpm;
  g.fillStyle = '#474c54';
  g.fillRect(0, 0, W, H);
  const teams = ['#cd212a', '#1d4fa3', '#f2c500', '#008c45'];
  for (let k = 0; k < 4; k++) {
    const x0 = k * 6 * ppm;
    const gx = x0 + 0.6 * ppm;
    const gw = 4.8 * ppm;
    const grad = g.createLinearGradient(0, y(3.8), 0, y(0));
    grad.addColorStop(0, '#14161a');
    grad.addColorStop(1, '#292c32');
    g.fillStyle = grad;
    g.fillRect(gx, y(3.8), gw, 3.8 * hpm);
    g.fillStyle = teams[k];
    g.globalAlpha = 0.55;
    g.fillRect(gx + gw * 0.12, y(3.2), gw * 0.76, 1.6 * hpm);
    g.globalAlpha = 1;
    g.fillStyle = 'rgba(255,255,240,0.8)';
    for (let l = 0; l < 3; l++) g.fillRect(gx + gw * (0.2 + l * 0.27), y(3.6), gw * 0.12, 0.08 * hpm);
    g.fillStyle = teams[k];
    g.fillRect(gx, y(4.4), gw, 0.45 * hpm);
    g.fillStyle = '#ffffff';
    g.font = 'bold ' + Math.round(0.36 * hpm) + 'px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText('BOX ' + (k + 1), gx + gw / 2, y(4.18));
  }
  // Andar de cima: varandas com faixa verde do autódromo (f_006, f_101)
  const gy0 = y(7.6);
  const gy1 = y(5.0);
  const glass = g.createLinearGradient(0, gy0, 0, gy1);
  glass.addColorStop(0, '#2a4668');
  glass.addColorStop(1, '#16253b');
  g.fillStyle = glass;
  g.fillRect(0, gy0, W, gy1 - gy0);
  g.fillStyle = '#0b5d34';
  g.fillRect(0, y(5.5), W, 0.75 * hpm);
  g.fillStyle = '#9aa0a8';
  for (let x = 0; x < W; x += 1.5 * ppm) g.fillRect(x, gy0, 3, gy1 - gy0);
  g.fillStyle = '#383d44';
  g.fillRect(0, 0, W, y(7.8));
  return tex(c, renderer, true);
}

/** Prédio dos boxes de Imola à direita da reta principal, com fundações -3,5 m e fachada traseira escura. */
export function buildPits(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, _asphalt: THREE.Material) {
  const side = PIT.side as -1 | 1;
  const d0 = PIT.garageFrom;
  const d1 = d0 + PIT.garageDepth;
  const h = PIT.garageH;
  const facade = new THREE.MeshStandardMaterial({ map: garageTexture(renderer), roughness: 0.5, side: THREE.DoubleSide });
  const backMat = new THREE.MeshStandardMaterial({ map: darkBackTexture(renderer), roughness: 0.75, side: THREE.DoubleSide });
  const roof = new THREE.MeshStandardMaterial({ color: 0x52565c, roughness: 0.8, side: THREE.DoubleSide });
  const apron = new THREE.MeshStandardMaterial({ color: 0x45484c, roughness: 0.9, side: THREE.DoubleSide });

  wallBand(track, group, PIT.s0, PIT.s1, side, [d0, -3.5], [d0, h], facade, 24, true);
  wallBand(track, group, PIT.s0, PIT.s1, side, [d0, h], [d1, h], roof, 8);
  wallBand(track, group, PIT.s0, PIT.s1, side, [d1, -3.5], [d1, h], backMat, 12, true);
  wallBand(track, group, PIT.s0, PIT.s1, side, [0.5, 0.01], [d0, 0.01], apron, 8);

  const S = track.samples;
  const N = S.length;
  const k = track.length / LAP;
  for (const sEnd of [PIT.s0, PIT.s1]) {
    const s = S[Math.round((sEnd * k) / STEP) % N];
    const p0 = s.p.clone().addScaledVector(s.r, side * (s.wallR + d0));
    const p1 = s.p.clone().addScaledVector(s.r, side * (s.wallR + d1));
    const geo = new THREE.BufferGeometry();
    geo.setAttribute(
      'position',
      new THREE.Float32BufferAttribute(
        [
          p0.x, p0.y - 3.5, p0.z, p1.x, p1.y - 3.5, p1.z, p1.x, p1.y + h, p1.z,
          p0.x, p0.y - 3.5, p0.z, p1.x, p1.y + h, p1.z, p0.x, p0.y + h, p0.z,
        ],
        3
      )
    );
    geo.computeVertexNormals();
    group.add(new THREE.Mesh(geo, backMat));
  }
}

export function buildBanners(_track: Track, _group: THREE.Group, _renderer: THREE.WebGLRenderer) {
  // Pórticos de Imola declarados em visual_profile.json -> bridges
}

export function buildMarshalPosts(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const L = track.length;
  const white = new THREE.MeshStandardMaterial({ color: 0xd8dad6, roughness: 0.7 });
  const roofMat = new THREE.MeshStandardMaterial({ color: 0xe8701a, roughness: 0.6 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x2c4a6e, roughness: 0.15, metalness: 0.5 });
  const flagMat = new THREE.MeshStandardMaterial({ color: 0xf2d000, roughness: 0.8, side: THREE.DoubleSide });
  const poleMat = new THREE.MeshStandardMaterial({ color: 0xaaaaaa, metalness: 0.6, roughness: 0.4 });
  const tmp = new THREE.Vector3();
  const every = Math.round(350 / STEP);
  for (let i = Math.round(450 / STEP); i < N; i += every) {
    const s = S[i];
    if (s.s > L - 400 || s.s < 250) continue;
    let curv = 0;
    for (let k = -20; k <= 20; k++) curv += S[(i + k + N) % N].curv;
    const side: -1 | 1 = curv > 0 ? -1 : 1;
    const wall = side < 0 ? s.wallL : s.wallR;
    const base = s.p.clone().addScaledVector(s.r, side * (wall + 3.2));
    if (overOther(track, tmp.copy(base), i, 4)) continue;
    const g = new THREE.Group();
    const hut = new THREE.Mesh(new THREE.BoxGeometry(2.2, 3.0, 2.2), white);
    hut.position.y = 1.0;
    const win = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.8, 2.24), glass);
    win.position.y = 1.8;
    const roof = new THREE.Mesh(new THREE.BoxGeometry(2.8, 0.2, 2.8), roofMat);
    roof.position.y = 2.6;
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 2.2, 6), poleMat);
    pole.position.set(1.3, 3.6, 0);
    const flag = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.6), flagMat);
    flag.position.set(1.75, 4.35, 0);
    g.add(hut, win, roof, pole, flag);
    g.traverse(o => (o.castShadow = true));
    g.position.copy(base).setY(s.p.y - 0.5);
    g.lookAt(s.p.x, g.position.y, s.p.z);
    group.add(g);
  }
}

export function buildCornerDetails(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const L = track.length;
  const rand = mulberry32(404);
  const tmp = new THREE.Vector3();
  const corners: number[] = [];
  const avgCurv = (i: number) => {
    let c = 0;
    for (let k = -7; k <= 7; k++) c += S[(i + k + N) % N].curv;
    return c / 15;
  };
  for (let i = 0; i < N; i++) {
    const c = Math.abs(avgCurv(i));
    if (c < 0.012 || S[i].s > L - 350 || S[i].s < 200) continue;
    if (corners.length && i - corners[corners.length - 1] < 90 / STEP) {
      if (c > Math.abs(avgCurv(corners[corners.length - 1]))) corners[corners.length - 1] = i;
      continue;
    }
    corners.push(i);
  }

  // Torres de câmera de TV
  const scaff = new THREE.MeshStandardMaterial({ color: 0x9ea3a8, metalness: 0.6, roughness: 0.4 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x1c1e21, roughness: 0.5, metalness: 0.3 });
  const umb = new THREE.MeshStandardMaterial({ color: 0xcd212a, roughness: 0.7, side: THREE.DoubleSide });
  const deck = new THREE.MeshStandardMaterial({ color: 0x6b6f73, roughness: 0.8 });
  for (const i of corners) {
    const ahead = S[(i - Math.round(40 / STEP) + N) % N];
    const sgn = avgCurv(i) > 0 ? -1 : 1;
    const wall = sgn < 0 ? ahead.wallL : ahead.wallR;
    const base = ahead.p.clone().addScaledVector(ahead.r, sgn * (wall + 5));
    if (overOther(track, tmp.copy(base), (i - Math.round(40 / STEP) + N) % N, 4) || occupied(track, base.x, base.z, base.y)) continue;
    const g = new THREE.Group();
    for (const [x, z] of [[-0.8, -0.8], [0.8, -0.8], [-0.8, 0.8], [0.8, 0.8]]) {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 5.2, 6), scaff);
      leg.position.set(x, 2.1, z);
      g.add(leg);
    }
    const plat = new THREE.Mesh(new THREE.BoxGeometry(2, 0.1, 2), deck);
    plat.position.y = 4.6;
    const cam = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.4, 0.75), dark);
    cam.position.set(0, 5.5, 0.1);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 2.2, 6), scaff);
    pole.position.set(-0.7, 5.7, -0.6);
    const top = new THREE.Mesh(new THREE.ConeGeometry(1.1, 0.4, 10, 1, true), umb);
    top.position.set(-0.7, 6.9, -0.6);
    g.add(plat, cam, pole, top);
    g.position.copy(base).setY(ahead.p.y - 0.5);
    const apex = S[i].p;
    g.lookAt(apex.x, g.position.y, apex.z);
    group.add(g);
  }

  // Cones laranja nos escapes largos
  const coneGeo = new THREE.ConeGeometry(0.17, 0.5, 12).translate(0, 0.25, 0);
  const cones = new THREE.InstancedMesh(coneGeo, new THREE.MeshStandardMaterial({ color: 0xff6a10, roughness: 0.6 }), 400);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(1, 1, 1);
  let nc = 0;
  for (const i of corners) {
    const sgn = avgCurv(i) > 0 ? -1 : 1;
    for (let k = Math.round(-60 / STEP); k <= Math.round(-20 / STEP); k += 5) {
      const s = S[(i + k + N) % N];
      const run = sgn < 0 ? s.runL : s.runR;
      const edge = sgn < 0 ? s.wl : s.wr;
      if (run < 3 || nc >= cones.count) continue;
      const p = s.p.clone().addScaledVector(s.r, sgn * (edge + run * 0.5));
      m.compose(p, q.identity(), sc);
      cones.setMatrixAt(nc++, m);
    }
  }
  cones.count = nc;
  group.add(cones);
  void rand;
}
