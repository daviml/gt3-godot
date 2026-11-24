// Mais detalhes da beira da pista vistos no vídeo de referência (Le Mans Ultimate): arquibancadas com
// torcida, pórticos de patrocinador sobre a pista e postos de fiscal.
// Fase 2B etapa F: os metros continuam escritos para a pista antiga (s numa volta de 4.300 m, ou o s real antigo onde
// indicado) e passam por ./sNovo.ts: arquibancada, boxes, pórtico, postos e resgate ficam no mesmo lugar físico.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import { AdScheme, adCanvas, tex } from '@web/render/trackDetails';
import { addProp } from '../propsRegistry';
import { iNovo, iNovo4300, L_ANTIGO, s4300, sNovo, sNovo4300 } from './sNovo';
import { ajusteLateral } from './ajusteLateral';
import { randLocal } from './sorteio';

/** Ponto p cai sobre (ou perto de) outro trecho da pista, longe da amostra i? */
function overOther(track: Track, p: THREE.Vector3, i: number, margin: number): boolean {
  const N = track.samples.length;
  const loc = track.locate(p);
  if (!loc) return false;
  const di = Math.min(Math.abs(loc.i - i), N - Math.abs(loc.i - i));
  return di > 40 && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + margin;
}

/**
 * Degraus da arquibancada vistos de cima: fileiras de cadeiras azuis (0,8 m) sobre concreto. As pessoas são
 * cartões em pé sobre cada fileira (crowdAtlas). Tile de 8 × 8 m.
 */
function crowdTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const W = 512;
  const ppm = W / 8;
  const c = document.createElement('canvas');
  c.width = c.height = W;
  const g = c.getContext('2d')!;
  const rowH = 0.8 * ppm;
  for (let r = 0; r < 10; r++) {
    const y = r * rowH;
    g.fillStyle = '#8f9295';
    g.fillRect(0, y, W, rowH);
    g.fillStyle = '#1f4f9c';
    g.fillRect(0, y + rowH * 0.15, W, rowH * 0.55);
    // encosto de cada cadeira
    g.fillStyle = '#173d7a';
    for (let x = 0; x < W; x += 0.5 * ppm) g.fillRect(x + 2, y + rowH * 0.15, 0.42 * ppm, rowH * 0.18);
    g.fillStyle = 'rgba(0,0,0,0.35)';
    g.fillRect(0, y + rowH * 0.92, W, rowH * 0.08);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

/** atlas de pessoas: 8 × 4 figuras de 64 × 128 px (0,5 × 1 m), sentadas ou em pé, braços para cima, boné, bandeira */
const CROWD_COLS = 8;
const CROWD_ROWS = 4;
function crowdAtlas(renderer: THREE.WebGLRenderer): THREE.Texture {
  const cw = 64;
  const ch = 128;
  const c = document.createElement('canvas');
  c.width = cw * CROWD_COLS;
  c.height = ch * CROWD_ROWS;
  const g = c.getContext('2d')!;
  const rand = mulberry32(77);
  const shirts = ['#f2c500', '#f2c500', '#1f8a3e', '#1f8a3e', '#ffffff', '#ffffff', '#d4202a', '#1d4fa3', '#222222', '#ff7a1a', '#8e44ad', '#7fc3e8', '#e8e2d0', '#c0392b'];
  const skins = ['#f1c9a5', '#d9a77e', '#b07a52', '#7a4e32', '#5a3a26'];
  const hairs = ['#1d1510', '#3b2a1c', '#6b4a2b', '#c9a35b', '#2a2a2a'];
  for (let k = 0; k < CROWD_COLS * CROWD_ROWS; k++) {
    const cx = (k % CROWD_COLS) * cw;
    // a linha do atlas conta de baixo para cima (v do Three), o canvas de cima para baixo
    const cy = (CROWD_ROWS - 1 - Math.floor(k / CROWD_COLS)) * ch;
    const shirt = shirts[Math.floor(rand() * shirts.length)];
    const skin = skins[Math.floor(rand() * skins.length)];
    const standing = rand() < 0.35;
    const armsUp = rand() < 0.2;
    const w = 26 + rand() * 10;
    const x0 = cx + (cw - w) / 2;
    const shoulder = cy + (standing ? 34 : 58);
    // calça (só em pé aparece acima do encosto da frente)
    if (standing) {
      g.fillStyle = rand() < 0.6 ? '#2b3a55' : '#3a3530';
      g.fillRect(x0 + 3, shoulder + 40, w - 6, ch - (shoulder - cy) - 40);
    }
    // tronco
    g.fillStyle = shirt;
    g.beginPath();
    g.roundRect(x0, shoulder, w, ch - (shoulder - cy), [8, 8, 0, 0]);
    g.fill();
    // braços
    g.fillStyle = armsUp ? skin : shirt;
    if (armsUp) {
      g.fillRect(x0 - 5, shoulder - 30, 6, 36);
      g.fillRect(x0 + w - 1, shoulder - 30, 6, 36);
    } else {
      g.fillRect(x0 - 4, shoulder + 4, 6, 30);
      g.fillRect(x0 + w - 2, shoulder + 4, 6, 30);
    }
    // cabeça e cabelo / boné
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
    // bandeira do Brasil de vez em quando (verde e amarela, simplificada)
    if (armsUp && rand() < 0.5) {
      g.fillStyle = '#1f8a3e';
      g.fillRect(cx + 2, shoulder - 54, cw - 4, 26);
      g.fillStyle = '#f2c500';
      g.beginPath();
      g.moveTo(cx + cw / 2, shoulder - 52);
      g.lineTo(cx + cw - 6, shoulder - 41);
      g.lineTo(cx + cw / 2, shoulder - 30);
      g.lineTo(cx + 6, shoulder - 41);
      g.fill();
    }
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

/** pessoa da torcida: posição do pé do cartão, direção para a pista e figura do atlas */
interface Fan {
  p: THREE.Vector3;
  face: THREE.Vector3;
  cell: number;
}

/** Torcida: um cartão (2 triângulos) por pessoa, virado para a pista, todos numa chamada de desenho. */
function buildCrowd(fans: Fan[], group: THREE.Group, renderer: THREE.WebGLRenderer) {
  if (!fans.length) return;
  const geo = new THREE.PlaneGeometry(0.5, 1).translate(0, 0.5, 0);
  const cells = new Float32Array(fans.length);
  const mat = new THREE.MeshStandardMaterial({ map: crowdAtlas(renderer), alphaTest: 0.5, side: THREE.DoubleSide, roughness: 0.9 });
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
  crowd: THREE.Material;
  concrete: THREE.Material;
  roof: THREE.Material;
  steel: THREE.Material;
}

/**
 * Arquibancada ao longo da pista, atrás do muro: degraus com torcida subindo para longe da pista, frente e
 * fundo de concreto e, se `roof`, cobertura em balanço sobre pilares. Some onde encostaria em outro trecho.
 * s0/s1 em metros numa volta de 4.300 m (s1 pode passar da linha de chegada).
 */
function buildStand(track: Track, group: THREE.Group, mats: StandMats, s0: number, s1: number, side: -1 | 1, depth: number, roof: boolean, fans: Fan[], rand: () => number, semTeto?: [number, number]) {
  const S = track.samples;
  const N = S.length;
  const i0 = iNovo4300(s0);
  const i1 = iNovo4300(s1);
  const at = (j: number) => S[((j % N) + N) % N];
  const rise = depth * 0.55;
  const front = 2.6; // primeira fileira acima do muro
  const d0 = 3;
  const d1 = 3 + depth;
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
  // Fase 3: trecho sem cobertura (s novo; LMU s 3910–4210: arquibancada a céu aberto, árvores atrás; coberta de ~4240 em diante)
  const comTeto = (j: number) => {
    if (!semTeto) return true;
    const sj = at(j).s;
    return !(semTeto[0] <= semTeto[1] ? sj >= semTeto[0] && sj <= semTeto[1] : sj >= semTeto[0] || sj <= semTeto[1]);
  };
  /** faixa entre os pontos a e b = (distância além do muro, altura), ao longo do trecho */
  const band = (a: [number, number], b: [number, number], mat: THREE.Material, vLen: number, shadow: boolean, incl: (j: number) => boolean = () => true) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let j = i0; j <= i1; j++) {
      if (!ok[j - i0] || !incl(j)) {
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
  const backCanvas = document.createElement('canvas');
  backCanvas.width = 512;
  backCanvas.height = 256;
  const bctx = backCanvas.getContext('2d')!;
  bctx.fillStyle = '#24282e';
  bctx.fillRect(0, 0, 512, 256);
  // Recessos escuros horizontais (andares/vãos de circulação)
  for (let row = 0; row < 3; row++) {
    const ry = 22 + row * 78;
    bctx.fillStyle = '#111418';
    bctx.fillRect(0, ry, 512, 42);
    bctx.fillStyle = '#1a1e24';
    bctx.fillRect(0, ry + 34, 512, 8);
    // Guarda-corpo metálico
    bctx.fillStyle = '#4a5059';
    bctx.fillRect(0, ry + 26, 512, 3);
  }
  // Pilares verticais e vigas de concreto
  for (let col = 0; col < 4; col++) {
    const cx = col * 128;
    bctx.fillStyle = '#383d45';
    bctx.fillRect(cx, 0, 18, 256);
    bctx.fillStyle = '#1b1e23';
    bctx.fillRect(cx + 18, 0, 5, 256);
  }
  for (let row = 0; row < 4; row++) {
    const by = row * 78;
    bctx.fillStyle = '#3c4149';
    bctx.fillRect(0, by, 512, 16);
  }
  const backTex = new THREE.CanvasTexture(backCanvas);
  backTex.wrapS = THREE.RepeatWrapping;
  backTex.wrapT = THREE.RepeatWrapping;
  backTex.colorSpace = THREE.SRGBColorSpace;
  backTex.needsUpdate = true;
  const backMat = new THREE.MeshStandardMaterial({ map: backTex, roughness: 0.9, side: THREE.DoubleSide });
  band([d0, front], [d1, front + rise], mats.crowd, Math.hypot(depth, rise), false);
  band([d0, -10], [d0, front], mats.concrete, front + 10, false); // frente assentada no barranco
  band([d1, -10], [d1, front + rise + 0.8], backMat, front + rise + 10, true);

  // torcida: uma pessoa a cada ~0,55 m em cada fileira de 0,8 m, com lugares vazios
  const rows = Math.floor(depth / 0.8);
  const face = new THREE.Vector3();
  for (let j = i0; j < i1; j++) {
    if (!ok[j - i0] || !ok[j + 1 - i0]) continue;
    const s = at(j);
    const wall = side < 0 ? s.wallL : s.wallR;
    face.copy(s.r).multiplyScalar(-side).setY(0).normalize();
    for (let r = 0; r < rows; r++) {
      const d = d0 + (r + 0.55) * (depth / rows);
      const h = front + (rise * (d - d0)) / depth - 0.35;
      for (let u = rand() * 0.3; u < STEP; u += 0.5 + rand() * 0.12) {
        if (rand() < 0.22) continue;
        const p = s.p.clone().addScaledVector(s.r, side * (wall + d)).addScaledVector(s.t, u);
        p.y += h;
        fans.push({ p, face: face.clone(), cell: Math.floor(rand() * CROWD_COLS * CROWD_ROWS) });
      }
    }
  }
  if (!roof) return;
  // cobertura fina em balanço, presa em pilares atrás com vigas de treliça aparentes por baixo
  const top = front + rise + 4.6;
  // cobre só as fileiras de trás e o meio: a frente fica a céu aberto (antes era uma laje até a pista)
  const front0 = d0 + depth * 0.3;
  band([d1 + 0.5, top], [front0, top - 0.9], mats.roof, depth, true, comTeto);
  const beam = new THREE.BoxGeometry(0.22, 1, 0.22);
  beam.translate(0, 0.5, 0);
  const steel = mats.steel;
  const up = new THREE.Vector3(0, 1, 0);
  const a3 = new THREE.Vector3();
  const b3 = new THREE.Vector3();
  /** viga de a até b */
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
    if (!ok[j - i0] || !comTeto(j)) continue;
    const s = at(j);
    const base = point(s, d1 + 0.3, -10, new THREE.Vector3());
    const colTop = point(s, d1 + 0.3, top + 0.1, new THREE.Vector3());
    bar(base, colTop, 2.2); // pilar
    // viga de cima (sob a cobertura) até a ponta, e o tirante diagonal do meio do pilar até a ponta
    const tip = point(s, front0 + 0.2, top - 0.95, new THREE.Vector3());
    bar(colTop, tip, 1.2);
    bar(point(s, d1 + 0.3, top - 3.2, a3), tip, 0.8);
    // montantes da treliça entre a viga e o tirante
    for (const f of [0.3, 0.55, 0.8]) {
      const onTop = new THREE.Vector3().lerpVectors(colTop, tip, f);
      const onTie = new THREE.Vector3().lerpVectors(point(s, d1 + 0.3, top - 3.2, a3), tip, f);
      bar(onTie, onTop, 0.5);
    }
  }
  // terça longitudinal na ponta da cobertura (liga as treliças)
  band([front0 + 0.1, top - 1.25], [front0 + 0.1, top - 0.95], mats.steel, 0.3, false, comTeto);
}

/** Arquibancadas (s0, s1 em m numa volta de 4.300 m; lado; profundidade; cobertura). */
const STANDS: { s0: number; s1: number; side: -1 | 1; depth: number; roof: boolean; semTeto?: [number, number] }[] = [
  // reta principal e topo da Subida dos Boxes, lado de fora. Fase 3: sem cobertura em s novo 3900–4240 (LMU chase
  // s 3910–4210: arquibancada aberta com as árvores logo atrás; coberta de ~4240 até o S). Antes de 3900 (setor 10)
  // continua coberta.
  { s0: 3780, s1: 4300 + 230, side: 1, depth: 22, roof: true, semTeto: [3900, 4240] }
];
/**
 * Reta dos boxes: pit lane e garagens atrás do muro da esquerda (s em m numa volta de 4.300 m). Fase 3: começa no bico
 * do muro dos boxes (s novo ~4106; antes s antigo-4300 4040 = novo ~4049, quando o muro dos boxes começava ali) e vai até
 * perto do fim do setor 3 (s novo ~228, para a margem de 20 m do `occupied` não passar de 248; antes ~60): o LMU (chase s 80–230) mostra a pista dos boxes e os prédios/tendas do
 * paddock atrás do muro até a entrada do S, onde tínhamos árvores.
 */
const PIT = { s0: s4300(4106), s1: 4300 + s4300(228), lane: 11, garageFrom: 12.5, garageDepth: 14.5, garageH: 7.2 };

/**
 * s (m) da pista nova está no trecho [a, b] (em metros de uma volta de 4.300 m da pista antiga; b pode passar da
 * linha)? As pontas vão para a pista nova pelo mapa de s (sNovo4300).
 */
function inRange(track: Track, s: number, a: number, b: number) {
  const L = track.length;
  const a1 = sNovo4300(a);
  const x = (((s - a1) % L) + L) % L;
  return x <= sNovo4300(b) - a1;
}

/**
 * O ponto (x, z) cai numa área ocupada por arquibancada, pit lane ou garagens? Árvores e prédios do OSM
 * não podem nascer aí (antes cresciam árvores no meio da torcida).
 */
export function occupied(track: Track, x: number, z: number, y: number): boolean {
  const loc = track.locate(new THREE.Vector3(x, y, z));
  if (!loc) return false;
  if (loc.d < 0 && inRange(track, loc.s, 920, 1400) && -loc.d < 70) return true; // Reta Oposta esquerda aberta como no LMU
  if (loc.d < 0 && inRange(track, loc.s, 340, 780) && -loc.d < 42) return true; // saída do S e Curva do Sol
  if (inRange(track, loc.s, 1850, 2250) && Math.abs(loc.d) < 42) return true; // Ferradura e Laranjinha
  if (inRange(track, loc.s, 2480, 2850) && Math.abs(loc.d) < 42) return true; // Pinheirinho e Bico de Pato
  if (loc.d < 0 && inRange(track, loc.s, 2980, 3380) && -loc.d < 48) return true; // Mergulho e Junção esquerda
  if (loc.d < 0 && inRange(track, loc.s, PIT.s0 - 20, PIT.s1 + 20) && -loc.d < loc.wallL + PIT.garageFrom + PIT.garageDepth + 4) return true;
  return STANDS.some(st => {
    const off = st.side * loc.d;
    const wall = st.side < 0 ? loc.wallL : loc.wallR;
    return off > 0 && inRange(track, loc.s, st.s0 - 10, st.s1 + 10) && off < wall + 3 + st.depth + 12;
  });
}

/** Arquibancadas com torcida: reta principal (coberta, atravessando a linha) e Junção/Subida dos Boxes. */
export function buildStands(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, concrete: THREE.Material) {
  const mats: StandMats = {
    crowd: new THREE.MeshStandardMaterial({ map: crowdTexture(renderer), roughness: 0.9, side: THREE.DoubleSide }),
    concrete,
    roof: new THREE.MeshStandardMaterial({ color: 0xb4b8bc, roughness: 0.55, metalness: 0.3, side: THREE.DoubleSide }),
    steel: new THREE.MeshStandardMaterial({ color: 0xb9bec4, roughness: 0.4, metalness: 0.6, side: THREE.DoubleSide })
  };
  const fans: Fan[] = [];
  const rand = mulberry32(31);
  for (const st of STANDS) buildStand(track, group, mats, st.s0, st.s1, st.side, st.depth, st.roof, fans, rand, st.semTeto);
  buildCrowd(fans, group, renderer);
}

/**
 * Faixa ao longo da pista, do lado `side`, entre os pontos a e b = (distância além do muro, altura acima da
 * pista), no trecho [s0, s1]. u = metros ao longo / uTile; v vai de 0 a 1 entre a e b.
 */
function wallBand(track: Track, group: THREE.Group, s0: number, s1: number, side: -1 | 1, a: [number, number], b: [number, number], mat: THREE.Material, uTile: number, shadow = false) {
  const S = track.samples;
  const N = S.length;
  const i0 = iNovo4300(s0);
  const i1 = iNovo4300(s1);
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  for (let j = i0; j <= i1; j++) {
    const s = S[((j % N) + N) % N];
    const wall = side < 0 ? s.wallL : s.wallR;
    for (const [[d, h], u] of [[a, 0], [b, 1]] as const) {
      v.copy(s.p).addScaledVector(s.r, side * (wall + d));
      v.y += h + ajusteLateral(track, ((j % N) + N) % N, side * (wall + d)); // Fase 3 (0 fora do setor 3)
      pos.push(v.x, v.y, v.z);
      uv.push(((j - i0) * STEP) / uTile, u);
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

/** Faixas pintadas da pit lane: linha contínua junto ao muro e tracejada entre a faixa rápida e a de trabalho. */
function pitLaneTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 256; // 8 m ao longo
  c.height = 256; // largura da pit lane
  const g = c.getContext('2d')!;
  const ppm = 256 / PIT.lane;
  g.fillStyle = 'rgba(235,235,228,0.9)';
  // v = 0 (junto ao muro) fica embaixo no canvas
  g.fillRect(0, 256 - 0.6 * ppm, 256, 0.15 * ppm);
  for (let x = 0; x < 256; x += 64) g.fillRect(x, 256 - 4.5 * ppm, 32, 0.15 * ppm);
  // marcas de pneu das paradas
  const rand = mulberry32(9);
  for (let i = 0; i < 20; i++) {
    g.fillStyle = 'rgba(15,15,15,' + (0.06 + rand() * 0.1) + ')';
    g.fillRect(rand() * 256, 256 - (5 + rand() * 5) * ppm, 20 + rand() * 60, 2 + rand() * 4);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

/**
 * Fachada das garagens (4 boxes de 6 m por textura): portão aberto com o fundo na cor da equipe, pilares
 * brancos, e em cima a faixa de vidro do andar das salas, com a platibanda branca.
 */
function garageTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const W = 1024;
  const H = 384;
  const ppm = W / 24; // 24 m ao longo
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const hpm = H / PIT.garageH;
  const y = (h: number) => H - h * hpm; // altura (m) → pixel
  g.fillStyle = '#e9eaeb';
  g.fillRect(0, 0, W, H);
  const teams = ['#c8102e', '#1d4fa3', '#f2c500', '#1f8a3e'];
  for (let k = 0; k < 4; k++) {
    const x0 = k * 6 * ppm;
    // portão: 4,8 × 3,8 m, interior escuro com a parede do fundo na cor da equipe
    const gx = x0 + 0.6 * ppm;
    const gw = 4.8 * ppm;
    const grad = g.createLinearGradient(0, y(3.8), 0, y(0));
    grad.addColorStop(0, '#15171a');
    grad.addColorStop(1, '#2b2e33');
    g.fillStyle = grad;
    g.fillRect(gx, y(3.8), gw, 3.8 * hpm);
    g.fillStyle = teams[k];
    g.globalAlpha = 0.55;
    g.fillRect(gx + gw * 0.12, y(3.2), gw * 0.76, 1.6 * hpm);
    g.globalAlpha = 1;
    // luzes do teto da garagem
    g.fillStyle = 'rgba(255,255,240,0.8)';
    for (let l = 0; l < 3; l++) g.fillRect(gx + gw * (0.2 + l * 0.27), y(3.6), gw * 0.12, 0.08 * hpm);
    // placa com o número do box
    g.fillStyle = teams[k];
    g.fillRect(gx, y(4.4), gw, 0.45 * hpm);
    g.fillStyle = '#ffffff';
    g.font = 'bold ' + Math.round(0.36 * hpm) + 'px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText('BOX ' + (k + 1), gx + gw / 2, y(4.18));
  }
  // andar de cima: vidro com montantes
  const gy0 = y(7.6);
  const gy1 = y(5.0);
  const glass = g.createLinearGradient(0, gy0, 0, gy1);
  glass.addColorStop(0, '#3d5f86');
  glass.addColorStop(1, '#1d3150');
  g.fillStyle = glass;
  g.fillRect(0, gy0, W, gy1 - gy0);
  g.fillStyle = '#c9ccd0';
  for (let x = 0; x < W; x += 1.5 * ppm) g.fillRect(x, gy0, 3, gy1 - gy0);
  // platibanda branca
  g.fillStyle = '#f4f4f2';
  g.fillRect(0, 0, W, y(7.8));
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

function paddockBackTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const W = 1024;
  const H = 512;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  // concreto cinza-escuro de base
  g.fillStyle = '#2d323a';
  g.fillRect(0, 0, W, H);
  // platibanda superior escura
  g.fillStyle = '#1f2329';
  g.fillRect(0, 0, W, 38);
  // 3 andares de faixas de vidro fumê com divisórias metálicas
  for (let row = 0; row < 3; row++) {
    const ry = 56 + row * 124;
    const gl = g.createLinearGradient(0, ry, 0, ry + 72);
    gl.addColorStop(0, '#121b26');
    gl.addColorStop(0.5, '#182432');
    gl.addColorStop(1, '#101822');
    g.fillStyle = gl;
    g.fillRect(0, ry, W, 72);
    g.fillStyle = '#474f5c';
    g.fillRect(0, ry - 8, W, 8);
    g.fillRect(0, ry + 72, W, 6);
    g.fillStyle = '#363c46';
    for (let x = 0; x < W; x += 64) g.fillRect(x, ry, 6, 72);
  }
  // pilares estruturais a cada 6 m (256 px em tile de 24 m)
  for (let x = 0; x < W; x += 256) {
    g.fillStyle = '#3b414b';
    g.fillRect(x, 0, 22, H);
    g.fillStyle = '#1b1f25';
    g.fillRect(x + 22, 0, 6, H);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

/** Pit lane asfaltada atrás do muro dos boxes e o prédio das garagens atrás dela. */
export function buildPits(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, asphalt: THREE.Material) {
  const lane = wallBand(track, group, PIT.s0, PIT.s1, -1, [0.3, 0.01], [PIT.lane + 0.3, 0.01], asphalt, 4);
  // UV do asfalto em metros/4 também na largura
  const uv = lane.geometry.attributes.uv as THREE.BufferAttribute;
  for (let i = 0; i < uv.count; i++) uv.setY(i, (uv.getY(i) * PIT.lane) / 4);
  const lines = new THREE.MeshStandardMaterial({ map: pitLaneTexture(renderer), transparent: true, depthWrite: false, roughness: 0.85, polygonOffset: true, polygonOffsetFactor: -2 });
  wallBand(track, group, PIT.s0, PIT.s1, -1, [0.3, 0.02], [PIT.lane + 0.3, 0.02], lines, 8).renderOrder = 2;
  const d0 = PIT.garageFrom;
  const d1 = d0 + PIT.garageDepth;
  const h = PIT.garageH;
  const facade = new THREE.MeshStandardMaterial({ map: garageTexture(renderer), roughness: 0.5, side: THREE.DoubleSide });
  const paddockBackMat = new THREE.MeshStandardMaterial({ map: paddockBackTexture(renderer), roughness: 0.72, side: THREE.DoubleSide });
  const plain = new THREE.MeshStandardMaterial({ color: 0xe1e2e3, roughness: 0.7, side: THREE.DoubleSide });
  const roof = new THREE.MeshStandardMaterial({ color: 0x262a30, roughness: 0.85, side: THREE.DoubleSide });
  const gStart = PIT.s0 + 30;
  wallBand(track, group, gStart, PIT.s1, -1, [d0, -0.5], [d0, h], facade, 24, true);
  wallBand(track, group, gStart, PIT.s1, -1, [d0, h], [d1, h], roof, 8);
  wallBand(track, group, gStart, PIT.s1, -1, [d1, -10], [d1, h], paddockBackMat, 24, true);
  // área de trabalho em concreto entre a pit lane e as garagens
  wallBand(track, group, PIT.s0, PIT.s1, -1, [PIT.lane + 0.3, 0.01], [d0, 0.01], plain, 8);
  // fechamento das pontas do prédio com UVs corretas (sem esticar 1 pixel)
  const S = track.samples;
  const N = S.length;
  for (const sEnd of [gStart, PIT.s1]) {
    const s = S[iNovo4300(sEnd) % N];
    const p0 = s.p.clone().addScaledVector(s.r, -(s.wallL + d0));
    const p1 = s.p.clone().addScaledVector(s.r, -(s.wallL + d1));
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute([
      p0.x, p0.y - 0.5, p0.z, p1.x, p1.y - 10, p1.z, p1.x, p1.y + h, p1.z,
      p0.x, p0.y - 0.5, p0.z, p1.x, p1.y + h, p1.z, p0.x, p0.y + h, p0.z
    ], 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute([
      0, 0, 0.6, -1.2, 0.6, 1,
      0, 0, 0.6, 1, 0, 1
    ], 2));
    geo.computeVertexNormals();
    group.add(new THREE.Mesh(geo, paddockBackMat));
  }
}

/** Pórtico de patrocinador sobre a pista: dois postes, faixa de placas dos dois lados e treliça em cima. */
function buildBanner(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, sAt: number, ads: AdScheme) {
  const S = track.samples;
  const s = S[iNovo4300(sAt) % S.length];
  const span = s.wl + s.wr + 6;
  const h = 6.2;
  const steel = new THREE.MeshStandardMaterial({ color: 0x9da2a7, metalness: 0.6, roughness: 0.45 });
  const t = tex(adCanvas(ads, 4, 256, 64), renderer);
  t.repeat.set(span / 24, 1);
  const face = new THREE.MeshStandardMaterial({ map: t, roughness: 0.5 });
  const g = new THREE.Group();
  for (const x of [-span / 2, span / 2]) {
    const pole = new THREE.Mesh(new THREE.BoxGeometry(0.5, h + 1.6, 0.5), steel);
    pole.position.set(x, (h + 1.6) / 2, 0);
    g.add(pole);
  }
  const panel = new THREE.Mesh(new THREE.BoxGeometry(span, 1.6, 0.4), [steel, steel, steel, steel, face, face]);
  panel.position.set(0, h + 0.8, 0);
  const truss = new THREE.Mesh(new THREE.BoxGeometry(span, 0.25, 0.6), steel);
  truss.position.set(0, h + 1.75, 0);
  g.add(panel, truss);
  g.traverse(o => (o.castShadow = true));
  g.position.copy(s.p).addScaledVector(s.r, (s.wr - s.wl) / 2);
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s.r, new THREE.Vector3(0, 1, 0), s.t.clone().negate()));
  group.add(g);
}

/**
 * Pórticos de patrocinador além dos fixos (passarela, MOTUL). Até a Fase 5 havia um pórtico vermelho no começo da Reta
 * Oposta (s ≈ 866, buildBanner(…, 860, 'vermelho')): o LMU não tem (chase s 820–870: só o pórtico MOTUL ao longe) e o
 * satélite só mostra um pórtico no setor, o MOTUL em s ~1000 (trackDetails.ts). Ficou sem nenhum.
 */
export function buildBanners(_track: Track, _group: THREE.Group, _renderer: THREE.WebGLRenderer) {
  void buildBanner;
}

/**
 * Postos de fiscal: casinha branca com janela, teto laranja e bandeira amarela, atrás do muro do lado de fora
 * da curva, a cada ~330 m (fora da reta dos boxes e onde cairia em outro trecho da pista).
 */
export function buildMarshalPosts(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const L = track.length;
  const white = new THREE.MeshStandardMaterial({ color: 0xf2f2ef, roughness: 0.7 });
  const roofMat = new THREE.MeshStandardMaterial({ color: 0xe8701a, roughness: 0.6 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x2c4a6e, roughness: 0.15, metalness: 0.5 });
  const flagMat = new THREE.MeshStandardMaterial({ color: 0xf2d000, roughness: 0.8, side: THREE.DoubleSide });
  const poleMat = new THREE.MeshStandardMaterial({ color: 0xaaaaaa, metalness: 0.6, roughness: 0.4 });
  const gateMat = new THREE.MeshStandardMaterial({ color: 0xe8701a, roughness: 0.6 });
  const gateMesh = new THREE.MeshStandardMaterial({ color: 0xd8dadc, roughness: 0.5, metalness: 0.4, transparent: true, opacity: 0.55, side: THREE.DoubleSide });
  const tmp = new THREE.Vector3();
  // a cada 330 m da pista antiga a partir de 400 m (fora dos últimos 560 m), cada posto levado pelo mapa de s
  const every = Math.round(330 / STEP);
  const NA = Math.round(L_ANTIGO / STEP);
  for (let iA = Math.round(400 / STEP); iA < NA; iA += every) {
    if (iA * STEP > L_ANTIGO - 560) continue;
    const i = iNovo(iA * STEP) % N;
    const s = S[i];
    let curv = 0;
    for (let k = -20; k <= 20; k++) curv += S[(i + k + N) % N].curv;
    const side: -1 | 1 = curv > 0 ? -1 : 1; // curva à direita: fora é a esquerda
    const wall = side < 0 ? s.wallL : s.wallR;
    const base = s.p.clone().addScaledVector(s.r, side * (wall + 3));
    if (overOther(track, tmp.copy(base), i, 3)) continue;
    const rotY = Math.atan2(s.p.x - base.x, s.p.z - base.z);
    addProp('marshal_post', new THREE.Vector3(base.x, s.p.y - 0.2, base.z), rotY, 1, false);
    // portão dos fiscais no muro, ao lado da casinha: folha de grade com moldura laranja, um pouco acima do muro
    const gate = new THREE.Group();
    for (const [w, h, x, y] of [[3, 0.12, 0, 2.04], [3, 0.12, 0, 0.06], [0.12, 2.1, -1.44, 1.05], [0.12, 2.1, 1.44, 1.05], [0.08, 2.0, 0, 1.05]]) {
      const bar = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.08), gateMat);
      bar.position.set(x, y, 0);
      gate.add(bar);
    }
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(2.8, 1.9), gateMesh);
    mesh.position.set(0, 1.05, 0);
    gate.add(mesh);
    const at = S[(i + 3) % N];
    const gw = side < 0 ? at.wallL : at.wallR;
    gate.position.copy(at.p).addScaledVector(at.r, side * (gw + 0.25)).setY(at.p.y - 0.1);
    gate.lookAt(at.p.x, gate.position.y, at.p.z);
    group.add(gate);
  }
  // ambulâncias e guindastes de resgate em pontos estratégicos fora do muro
  for (const [sM, side, id] of [
    [220, -1, 'ambulance'],
    [1920, -1, 'crane'],
    [3090, 1, 'ambulance'],
    // (Fase 5: o guindaste em s 1340 da volta de 4.300 m, à direita da Reta Oposta, saiu: o LMU não tem, s 1290–1360)
  ] as [number, -1 | 1, string][]) {
    const idx = iNovo4300(sM) % N;
    const s = S[idx];
    const wall = side < 0 ? s.wallL : s.wallR;
    const p = s.p.clone().addScaledVector(s.r, side * (wall + 5.5));
    if (overOther(track, tmp.copy(p), idx, 4)) continue;
    const rotY = Math.atan2(s.p.x - p.x, s.p.z - p.z) + (id === 'ambulance' ? Math.PI * 0.45 : 0.3);
    addProp(id, new THREE.Vector3(p.x, s.p.y - 0.15, p.z), rotY, 1, false);
  }
}

/**
 * Detalhes de curva vistos no LMU: torres de câmera de TV (andaime com plataforma, câmera e guarda-sol) do lado
 * de fora das curvas de freada forte, cones laranja na entrada dos escapes largos e marcas de pneu escuras no
 * escape (carros que passaram reto).
 */
export function buildCornerDetails(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const L = track.length;
  const tmp = new THREE.Vector3();
  // curvas: picos de curvatura (média de 30 m), longe da reta dos boxes
  const corners: number[] = [];
  const avgCurv = (i: number) => {
    let c = 0;
    for (let k = -7; k <= 7; k++) c += S[(i + k + N) % N].curv;
    return c / 15;
  };
  // longe da reta dos boxes: de 150 m a 500 m antes da linha na pista antiga (s real), levados para a nova
  const sIni = sNovo(150);
  const sFim = sNovo(L_ANTIGO - 500);
  for (let i = 0; i < N; i++) {
    const c = Math.abs(avgCurv(i));
    if (c < 0.012 || S[i].s > sFim || S[i].s < sIni) continue;
    if (corners.length && i - corners[corners.length - 1] < 90 / STEP) {
      if (c > Math.abs(avgCurv(corners[corners.length - 1]))) corners[corners.length - 1] = i;
      continue;
    }
    corners.push(i);
  }

  // torre de TV: andaime de 4,5 m, plataforma, câmera com lente e guarda-sol
  const scaff = new THREE.MeshStandardMaterial({ color: 0x9ea3a8, metalness: 0.6, roughness: 0.4 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x1c1e21, roughness: 0.5, metalness: 0.3 });
  const umb = new THREE.MeshStandardMaterial({ color: 0x1d4fa3, roughness: 0.7, side: THREE.DoubleSide });
  const deck = new THREE.MeshStandardMaterial({ color: 0x6b6f73, roughness: 0.8 });
  for (const i of corners) {
    const ahead = S[(i - Math.round(40 / STEP) + N) % N];
    const sgn = avgCurv(i) > 0 ? -1 : 1; // lado de fora
    const wall = sgn < 0 ? ahead.wallL : ahead.wallR;
    const base = ahead.p.clone().addScaledVector(ahead.r, sgn * (wall + 5));
    if (overOther(track, tmp.copy(base), (i - Math.round(40 / STEP) + N) % N, 4) || occupied(track, base.x, base.z, base.y)) continue;
    const g = new THREE.Group();
    for (const [x, z] of [[-0.8, -0.8], [0.8, -0.8], [-0.8, 0.8], [0.8, 0.8]]) {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 4.5, 6), scaff);
      leg.position.set(x, 2.25, z);
      g.add(leg);
    }
    for (const y of [1.5, 3.0]) {
      const ring = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.05, 1.7), scaff);
      ring.position.y = y;
      g.add(ring);
    }
    const plat = new THREE.Mesh(new THREE.BoxGeometry(2, 0.1, 2), deck);
    plat.position.y = 4.5;
    const cam = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.4, 0.75), dark);
    cam.position.set(0, 5.4, 0.1);
    const lens = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.13, 0.5, 10), dark);
    lens.rotation.x = Math.PI / 2;
    lens.position.set(0, 5.45, 0.7);
    const tripod = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.12, 0.85, 6), dark);
    tripod.position.set(0, 4.97, 0.1);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 2.2, 6), scaff);
    pole.position.set(-0.7, 5.6, -0.6);
    const top = new THREE.Mesh(new THREE.ConeGeometry(1.1, 0.4, 10, 1, true), umb);
    top.position.set(-0.7, 6.8, -0.6);
    g.add(plat, cam, lens, tripod, pole, top);
    g.position.copy(base).setY(ahead.p.y - 0.2);
    // câmera olhando para o ápice da curva
    const apex = S[i].p;
    g.lookAt(apex.x, g.position.y, apex.z);
    group.add(g);
  }

  // cones na borda dos escapes largos e marcas de pneu no escape
  const coneGeo = new THREE.ConeGeometry(0.17, 0.5, 12);
  coneGeo.translate(0, 0.25, 0);
  const cones = new THREE.InstancedMesh(coneGeo, new THREE.MeshStandardMaterial({ color: 0xff6a10, roughness: 0.6 }), 600);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const sc = new THREE.Vector3(1, 1, 1);
  let nc = 0;
  const marks = document.createElement('canvas');
  marks.width = 64;
  marks.height = 256;
  const mg = marks.getContext('2d')!;
  for (const x of [14, 46]) {
    const grad = mg.createLinearGradient(0, 0, 0, 256);
    grad.addColorStop(0, 'rgba(20,18,16,0)');
    grad.addColorStop(0.15, 'rgba(20,18,16,0.75)');
    grad.addColorStop(0.8, 'rgba(20,18,16,0.6)');
    grad.addColorStop(1, 'rgba(20,18,16,0)');
    mg.fillStyle = grad;
    mg.fillRect(x - 5, 0, 10, 256);
  }
  const markTex = new THREE.CanvasTexture(marks);
  const markMat = new THREE.MeshBasicMaterial({ map: markTex, transparent: true, depthWrite: false, opacity: 0.8, polygonOffset: true, polygonOffsetFactor: -3 });
  const markGeo = new THREE.PlaneGeometry(1.9, 1).rotateX(-Math.PI / 2);
  const markMesh = new THREE.InstancedMesh(markGeo, markMat, 200);
  let nm = 0;
  const UP = new THREE.Vector3(0, 1, 0);
  for (const i of corners) {
    const sgn = avgCurv(i) > 0 ? -1 : 1;
    // entrada da curva (onde quem freia tarde sai reto): 60 a 20 m antes do ápice
    for (let k = Math.round(-60 / STEP); k <= Math.round(-20 / STEP); k += 5) {
      const s = S[(i + k + N) % N];
      const run = sgn < 0 ? s.runL : s.runR;
      const edge = sgn < 0 ? s.wl : s.wr;
      if (run < 6 || nc >= cones.count) continue;
      const p = s.p.clone().addScaledVector(s.r, sgn * (edge + run * 0.5));
      m.compose(p, q.identity(), sc);
      cones.setMatrixAt(nc++, m);
    }
    // marcas: 2–4 riscos saindo da pista em ângulo para o escape
    const s = S[(i - Math.round(30 / STEP) + N) % N];
    const run = sgn < 0 ? s.runL : s.runR;
    const edge = sgn < 0 ? s.wl : s.wr;
    if (run < 6) continue;
    // Fase 6: sorteio por curva (./sorteio.ts), não mais um mulberry32(404) global para todas: com o global, mudar o
    // escape de uma curva (Descida do Lago) movia as marcas de todas as curvas seguintes (mudança única: as marcas de
    // pneu de todas as curvas trocaram de lugar uma vez)
    const rand = randLocal(404, i);
    const n = 2 + Math.floor(rand() * 3);
    for (let t = 0; t < n && nm < markMesh.count; t++) {
      const len = 10 + rand() * 18;
      const dir = s.t.clone().addScaledVector(s.r, sgn * (0.15 + rand() * 0.2)).setY(0).normalize();
      const start = s.p.clone().addScaledVector(s.r, sgn * (edge - 1 + rand() * 2)).addScaledVector(s.t, (rand() - 0.5) * 14);
      const mid = start.clone().addScaledVector(dir, len / 2);
      mid.y = Math.max(s.p.y, mid.y) + 0.03;
      q.setFromAxisAngle(UP, Math.atan2(dir.x, dir.z));
      m.compose(mid, q, new THREE.Vector3(1, 1, len));
      markMesh.setMatrixAt(nm++, m);
    }
  }
  cones.count = nc;
  markMesh.count = nm;
  markMesh.receiveShadow = false;
  group.add(cones, markMesh);
}
