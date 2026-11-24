// Arredores reais de Interlagos a partir do OpenStreetMap (data/tracks/interlagos-osm.json, gerado por
// scripts/build-interlagos-osm.mjs): casas e prédios com o contorno real, arquibancadas, lago, mata,
// fileiras de árvores, pit lane, kartódromo e a caixa d'água da Sabesp.
import * as THREE from 'three';
import { occupied } from './trackside';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import { plantTrees, TreeSpot } from '@web/render/trees';
import { randLocal, randPorArvore, randPosicao } from './sorteio';
import { arvoresPorSetor } from './arvoresSetor';
import { phTexture } from '@web/render/textures';
import { TOWER_COLORS, trackDistance } from '@web/render/surroundings';
// Fase 2B etapa F: OSM da fonte própria (tools/tracks/interlagos/interlagos-osm.json, o mesmo do web + muros/cercas);
// prédios e o resto do OSM são por coordenada de mundo e não mudam. Os metros da pista antiga passam por ./sNovo.ts.
import { L_ANTIGO, s4300, sNovo } from './sNovo';

/** entrada (3840–4050) e saída (300–800) dos boxes, em s real da pista antiga, levadas para a nova */
const PIT_A = [sNovo(3840), sNovo(4050)];
const PIT_B = [sNovo(300), sNovo(800)];

type Pt = [number, number];
export interface OsmData {
  buildings: { pts: Pt[]; h: number; kind: string; a: number }[];
  water: Pt[][];
  forest: Pt[][];
  grass: Pt[][];
  treeRows: Pt[][];
  pitLane: Pt[][];
  kart: Pt[][];
  waterTower: Pt | null;
  corners?: { name: string; pts: Pt[] }[];
}

// grafia oficial onde o OSM difere
const NAME_FIX: Record<string, string> = { Pinherinho: 'Pinheirinho' };

/**
 * Converte os trechos nomeados do OSM em faixas de s ao longo da volta. Só vale o que cai sobre a pista atual
 * (o OSM também tem trechos do traçado antigo); nomes repetidos viram um trecho só.
 */
export function trackSections(osm: OsmData, track: Track) {
  const S = track.samples;
  const L = track.length;
  const found: { name: string; s0: number; s1: number }[] = [];
  for (const c of osm.corners ?? []) {
    const ss: number[] = [];
    for (const [x, z] of c.pts) {
      // amostra de pista mais próxima no plano (sem altura: o ponto do OSM não tem)
      let best = Infinity;
      let bi = 0;
      for (let i = 0; i < S.length; i++) {
        const d2 = (S[i].p.x - x) ** 2 + (S[i].p.z - z) ** 2;
        if (d2 < best) {
          best = d2;
          bi = i;
        }
      }
      const sm = S[bi];
      if (Math.sqrt(best) < Math.max(sm.wl, sm.wr) + 3) ss.push(sm.s);
    }
    if (ss.length < 2) continue;
    ss.sort((a, b) => a - b);
    // trecho que passa pela linha de chegada: começa no maior grupo depois do "salto"
    let s0 = ss[0];
    let s1 = ss[ss.length - 1];
    for (let k = 1; k < ss.length; k++) {
      if (ss[k] - ss[k - 1] > L / 2) {
        s0 = ss[k];
        s1 = ss[k - 1];
      }
    }
    found.push({ name: NAME_FIX[c.name] ?? c.name, s0, s1 });
  }
  // junta trechos com o mesmo nome (o OSM divide alguns em vários pedaços)
  const byName = new Map<string, { name: string; s0: number; s1: number }>();
  for (const f of found) {
    const prev = byName.get(f.name);
    if (!prev || f.s0 < prev.s0) byName.set(f.name, prev ? { ...f, s1: Math.max(prev.s1, f.s1) } : f);
  }
  return [...byName.values()].sort((a, b) => a.s0 - b.s0);
}

/**
 * Cobertura do paddock em "pétalas" (a tenda branca sobre os boxes, nas fotos de 2026): módulos em forma de
 * funil quadrado invertido sobre colunas, em fila ao longo da reta, sobre os prédios dos boxes.
 */
function buildPaddockCanopy(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const S = track.samples;
  const N = S.length;
  // 210 m antes até 150 m depois da linha na pista antiga (s real), levados para a nova
  const pA = sNovo(L_ANTIGO - 210);
  const pB = sNovo(150);
  const inPitStraight = (s: number) => s > pA || s < pB;
  // sobre os prédios dos boxes: além do muro dos boxes (concreto) + pit lane, ~22 m para fora
  const behindPitWall = (i: number) => -(S[i].wallL + 22);
  // não pode cair sobre outro trecho da pista (o miolo do S do Senna fica logo atrás dos boxes)
  const tmp = new THREE.Vector3();
  const overOtherTrack = (p: THREE.Vector3, i: number) => {
    const loc = track.locate(tmp.set(p.x, p.y, p.z));
    if (!loc) return false;
    const di = Math.min(Math.abs(loc.i - i), N - Math.abs(loc.i - i));
    return di > 40 && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + 12;
  };
  // um módulo: funil de 4 lados (pétala) virado para cima, de 9 m de lado
  const profile = [
    new THREE.Vector2(0.35, 0), new THREE.Vector2(0.6, 1.2), new THREE.Vector2(1.3, 2.4),
    new THREE.Vector2(2.9, 3.4), new THREE.Vector2(5.2, 4), new THREE.Vector2(6.3, 4.1)
  ];
  const petal = new THREE.LatheGeometry(profile, 4);
  petal.rotateY(Math.PI / 4);
  petal.computeVertexNormals();
  const column = new THREE.CylinderGeometry(0.28, 0.35, 1, 10);
  column.translate(0, 0.5, 0);
  const white = new THREE.MeshStandardMaterial({ color: 0xf1efe8, roughness: 0.65, side: THREE.DoubleSide });
  const steel = new THREE.MeshStandardMaterial({ color: 0xdedfe0, roughness: 0.4, metalness: 0.3 });
  const spots: { p: THREE.Vector3; yaw: number; ground: number }[] = [];
  for (let i = 0; i < N; i += 5) {
    const s = S[i];
    if (!inPitStraight(s.s)) continue;
    const p = s.p.clone().addScaledVector(s.r, behindPitWall(i));
    if (overOtherTrack(p, i)) continue;
    const ground = heightAt(p.x, p.z);
    spots.push({ p, yaw: Math.atan2(s.t.x, s.t.z), ground });
  }
  const petals = new THREE.InstancedMesh(petal, white, spots.length);
  const cols = new THREE.InstancedMesh(column, steel, spots.length);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const sc = new THREE.Vector3();
  const up = new THREE.Vector3(0, 1, 0);
  spots.forEach(({ p, yaw, ground }, k) => {
    const top = Math.max(ground, p.y) + 13; // acima dos prédios dos boxes
    q.setFromAxisAngle(up, yaw);
    m.compose(new THREE.Vector3(p.x, top - 4, p.z), q, sc.set(1, 1, 1));
    petals.setMatrixAt(k, m);
    m.compose(new THREE.Vector3(p.x, ground, p.z), q, sc.set(1, top - 4 - ground, 1));
    cols.setMatrixAt(k, m);
  });
  petals.castShadow = cols.castShadow = true;
  petals.receiveShadow = true;
  group.add(petals, cols);
}

/** Placas com o nome do trecho: azul-escuras, do lado de fora da curva, viradas para quem chega. */
function buildSectionSigns(track: Track, group: THREE.Group) {
  const S = track.samples;
  const N = S.length;
  const postMat = new THREE.MeshStandardMaterial({ color: 0x6b7075, metalness: 0.5, roughness: 0.5 });
  for (const sec of track.sections) {
    const c = document.createElement('canvas');
    c.width = 512;
    c.height = 128;
    const g = c.getContext('2d')!;
    g.fillStyle = '#0b2e5c';
    g.fillRect(0, 0, 512, 128);
    g.fillStyle = '#e3bd1c';
    g.fillRect(0, 112, 512, 16);
    g.fillStyle = '#ffffff';
    g.font = 'bold 54px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(sec.name.toUpperCase(), 256, 58, 490);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 8;
    const board = new THREE.Mesh(new THREE.PlaneGeometry(4, 1), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.5 }));
    // posição: um pouco antes do início do trecho, do lado de fora da curva que vem
    const i = (Math.round((sec.s0 - 30) / STEP) + N * 10) % N;
    const ahead = S[(i + 25) % N];
    const side = ahead.curv > 0.002 ? -1 : 1; // curva para a direita: placa à esquerda
    const s = S[i];
    const off = side * ((side < 0 ? s.wallL : s.wallR) - 1.2);
    const base = s.p.clone().addScaledVector(s.r, off);
    board.position.copy(base).add(new THREE.Vector3(0, 2.2, 0));
    board.lookAt(base.clone().sub(s.t).setY(board.position.y));
    board.castShadow = true;
    group.add(board);
    // dois postes, nas pontas da placa
    const along = new THREE.Vector3(1, 0, 0).applyQuaternion(board.quaternion);
    for (const dx of [-1.6, 1.6]) {
      const post = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 2.2, 6), postMat);
      post.position.copy(board.position).setY(base.y + 1.1).addScaledVector(along, dx);
      group.add(post);
    }
  }
}

const HOUSE_WALLS = ['#e9dcc6', '#ddd0b8', '#f1e8d8', '#d3c5ab', '#e6d6c4', '#cdd3d6', '#e8e1cf'];
const HOUSE_ROOFS = ['#b4552e', '#a64a2a', '#c1643b', '#9c4628', '#b75a36', '#8f8f8f'];

/** o ponto está dentro do polígono? (par-ímpar) */
function inside(x: number, z: number, poly: Pt[]) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i];
    const [xj, zj] = poly[j];
    if (zi > z !== zj > z && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) c = !c;
  }
  return c;
}

export function buildOsmScenery(
  osm: OsmData,
  track: Track,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  renderer: THREE.WebGLRenderer,
  extreme: boolean
) {
  const rand = mulberry32(2026);
  const tmp = new THREE.Vector3();
  // nada pode encostar na pista: descarta o que fica a menos de 4 m além do muro
  const nearTrack = (x: number, z: number, treeMargin = false) => {
    const loc = track.locate(tmp.set(x, heightAt(x, z), z));
    if (!loc) return false;
    const sm = s4300(loc.s);
    const margin = treeMargin && ((sm >= 340 && sm <= 780) || (sm >= 1850 && sm <= 3400)) ? 38 : 4;
    // arquibancadas, pit lane e garagens (trackside.ts) também ocupam a beira da pista
    return Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + margin || occupied(track, x, z, tmp.y);
  };
  const nearTrees = (x: number, z: number) => nearTrack(x, z, true);
  // complexo dos boxes: perto da reta principal (antes da linha de chegada), do lado de dentro
  // de 520 m antes a 40 m depois da linha na pista antiga (s real), levados para a nova
  const zA = sNovo(L_ANTIGO - 520);
  const zB = sNovo(40);
  const pitZone = (x: number, z: number) => {
    const loc = track.locate(tmp.set(x, heightAt(x, z), z));
    return !!loc && loc.d < 0 && (loc.s > zA || loc.s < zB) && Math.abs(loc.d) < 140;
  };

  buildBuildings(osm, track, group, heightAt, nearTrack, pitZone, renderer, rand);
  buildWater(osm, group, heightAt);
  buildTrees(osm, track, group, heightAt, nearTrees, renderer, extreme, rand);
  // saída e entrada dos boxes reais do OSM (fora do trecho de garagens da reta principal, que já tem buildPits)
  buildRibbons(osm.pitLane, 7.5, group, heightAt, track, true);
  buildRibbons(osm.kart, 7, group, heightAt, track, false);
  if (osm.waterTower) buildWaterTower(osm.waterTower, group, heightAt);
  buildPaddockCanopy(track, group, heightAt);
  track.sections = trackSections(osm, track);
  console.info('trechos:', track.sections.map(x => `${x.name} ${Math.round(x.s0)}–${Math.round(x.s1)}`).join(' | '));
}

/**
 * Fachada procedural: reboco (textura de concreto clareada por cima da cor do prédio), janelas em grade por
 * andar de 3 m com vidro escuro refletindo o céu (tom sorteado por janela), parapeito, e sujeira escorrida
 * perto do chão. Teto (aWin < 0): telha/laje com manchas. Tudo no shader, sem textura de fachada.
 */
function facadeMaterial(renderer: THREE.WebGLRenderer): THREE.MeshStandardMaterial {
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85, side: THREE.DoubleSide });
  const plaster = phTexture('concrete_wall_008', 'diff', renderer);
  mat.onBeforeCompile = shader => {
    shader.uniforms.plaster = { value: plaster };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float aWin;\nvarying float vWin;\nvarying vec2 vFac;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvWin = aWin;\nvFac = uv;');
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        uniform sampler2D plaster;
        varying float vWin;
        varying vec2 vFac;
        float h1(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7); }`
      )
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
        vec3 pl = texture2D(plaster, vFac / 4.0).rgb;
        float glass = 0.0;
        if (vWin < -0.5) {
          // teto: manchas de sujeira em escala de metros
          diffuseColor.rgb *= 0.75 + 0.5 * pl.r;
        } else {
          diffuseColor.rgb *= 0.6 + 0.8 * pl.g;
          if (vWin > 0.5) {
            bool house = vWin < 1.5;
            float bay = house ? 3.6 : 3.0;     // largura de cada vão
            float ww = house ? 1.2 : 1.7;      // largura da janela
            vec2 cell = vec2(floor(vFac.x / bay), floor(vFac.y / 3.0));
            vec2 f = vec2(mod(vFac.x, bay), mod(vFac.y, 3.0));
            float inX = step(abs(f.x - bay * 0.5), ww * 0.5);
            float inY = step(0.95, f.y) * step(f.y, house ? 2.15 : 2.45);
            // algumas posições sem janela (mais nas casas)
            float present = step(house ? 0.35 : 0.08, h1(cell));
            glass = inX * inY * present;
            // parapeito: faixa clara logo abaixo da janela
            float sill = step(abs(f.x - bay * 0.5), ww * 0.5 + 0.1) * step(0.82, f.y) * step(f.y, 0.95) * present;
            diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.75), sill * 0.6);
            vec3 sky = mix(vec3(0.07, 0.09, 0.12), vec3(0.35, 0.42, 0.5), h1(cell + 7.0));
            diffuseColor.rgb = mix(diffuseColor.rgb, sky, glass);
          }
          // sujeira perto do chão
          diffuseColor.rgb *= 0.78 + 0.22 * smoothstep(0.0, 1.6, vFac.y);
        }`
      )
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = mix(roughnessFactor, 0.12, glass);');
  };
  return mat;
}

function makeBuildingTex(kind: 'win' | 'solid' | 'roof'): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512;
  const ctx = c.getContext('2d')!;
  if (kind === 'win') {
    // 4 andares (128px/andar = 3m/andar) x 4 colunas de janelas (128px/col = 3m/col)
    ctx.fillStyle = '#e6e4de';
    ctx.fillRect(0, 0, 512, 512);
    // Reboco / variação sutil por andar
    for (let row = 0; row < 4; row++) {
      const y0 = row * 128;
      ctx.fillStyle = row % 2 === 0 ? '#dcdad2' : '#e8e6e0';
      ctx.fillRect(0, y0, 512, 128);
      // Laje / friso horizontal entre andares
      ctx.fillStyle = '#b9b7ae';
      ctx.fillRect(0, y0, 512, 10);
      ctx.fillStyle = '#c8c6be';
      ctx.fillRect(0, y0 + 118, 512, 10);
      for (let col = 0; col < 4; col++) {
        const x0 = col * 128;
        // Moldura escura da janela
        ctx.fillStyle = '#52575e';
        ctx.fillRect(x0 + 18, y0 + 24, 92, 76);
        // Vidro escuro refletivo com variação por janela
        const tone = ((row * 7 + col * 13) % 5);
        ctx.fillStyle = tone === 0 ? '#233548' : tone === 1 ? '#2b4056' : tone === 2 ? '#1e2c3b' : tone === 3 ? '#324a63' : '#25384c';
        ctx.fillRect(x0 + 22, y0 + 28, 84, 68);
        // Reflexo diagonal sutil no vidro
        ctx.fillStyle = 'rgba(180,210,235,0.16)';
        ctx.fillRect(x0 + 24, y0 + 30, 80, 18);
        // Divisória central da janela
        ctx.fillStyle = '#474c54';
        ctx.fillRect(x0 + 62, y0 + 28, 4, 68);
        // Peitoril
        ctx.fillStyle = '#9ea2a8';
        ctx.fillRect(x0 + 14, y0 + 100, 100, 6);
      }
    }
  } else if (kind === 'solid') {
    // Painéis de concreto / juntas verticais e horizontais (arquibancadas, tanques, faixas de vidro)
    ctx.fillStyle = '#e8e8e6';
    ctx.fillRect(0, 0, 512, 512);
    for (let row = 0; row < 4; row++) {
      const y0 = row * 128;
      ctx.fillStyle = row % 2 === 0 ? '#e0e0dd' : '#eaeae7';
      ctx.fillRect(0, y0, 512, 128);
      ctx.fillStyle = '#b4b6ba';
      ctx.fillRect(0, y0, 512, 6);
      for (let col = 0; col < 4; col++) {
        const x0 = col * 128;
        ctx.fillStyle = '#c4c6ca';
        ctx.fillRect(x0, y0, 5, 128);
      }
    }
  } else {
    // Teto: laje com juntas e manchas sutis
    ctx.fillStyle = '#dedede';
    ctx.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 512; i += 64) {
      ctx.fillStyle = '#c8c8c8';
      ctx.fillRect(i, 0, 3, 512);
      ctx.fillRect(0, i, 512, 3);
    }
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.needsUpdate = true;
  return tex;
}

/** Casas e prédios: paredes + teto plano em 3 malhas texturizadas (janelas, concreto, teto) exportáveis para GLB. */
function buildBuildings(
  osm: OsmData,
  track: Track,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  nearTrack: (x: number, z: number) => boolean,
  pitZone: (x: number, z: number) => boolean,
  _renderer: THREE.WebGLRenderer,
  rand: () => number
) {
  const buckets = {
    win: { pos: [] as number[], col: [] as number[], uv: [] as number[] },
    solid: { pos: [] as number[], col: [] as number[], uv: [] as number[] },
    roof: { pos: [] as number[], col: [] as number[], uv: [] as number[] }
  };
  const c = new THREE.Color();
  /** u = metros ao longo da parede, v = metros acima do chão; w = tipo de janela (<0 teto, 0 sólido, >0 janelas) */
  const push = (x: number, y: number, z: number, color: THREE.Color, u = 0, v = 0, w = 0) => {
    const b = w < 0 ? buckets.roof : w > 0 ? buckets.win : buckets.solid;
    const scale = w < 0 ? 1 / 16 : 1 / 12;
    b.pos.push(x, y, z);
    b.col.push(color.r, color.g, color.b);
    b.uv.push(u * scale, v * scale);
  };
  const wallC = new THREE.Color();
  const roofC = new THREE.Color();
  const glassC = new THREE.Color('#2c4a6e');
  let skipped = 0;
  let tall = 0;
  const dist = trackDistance(track);
  for (const b of osm.buildings) {
    if (b.pts.some(([x, z]) => nearTrack(x, z))) {
      skipped++;
      continue;
    }
    const cx = b.pts.reduce((s, p) => s + p[0], 0) / b.pts.length;
    const cz = b.pts.reduce((s, p) => s + p[1], 0) / b.pts.length;
    const xs0 = b.pts.map(p => p[0]);
    const zs0 = b.pts.map(p => p[1]);
    const span0 = Math.max(Math.max(...xs0) - Math.min(...xs0), Math.max(...zs0) - Math.min(...zs0));
    if ((b.kind === 'grandstand' || (b.kind === 'big' && !b.h && span0 > 45)) && dist(cx, cz) < 120) {
      skipped++;
      continue;
    }
    const ground = heightAt(cx, cz) - 0.3;
    const pit = (b.kind === 'big' || b.kind === 'garage') && pitZone(cx, cz);
    let h = b.h;
    if (!h) h = b.kind === 'house' ? 4.5 + rand() * 3.5 : 8 + rand() * 8;
    if (pit) h = Math.max(h, 9);
    // os bairros em volta são cheios de prédios residenciais de 12–24 andares: os prédios sem altura no OSM,
    // longe da pista e de planta compacta (não galpão) viram torres
    let tower = false;
    if (!b.h && b.kind !== 'house' && b.kind !== 'grandstand' && b.kind !== 'tank' && !pit) {
      const xs = b.pts.map(p => p[0]);
      const zs = b.pts.map(p => p[1]);
      const span = Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...zs) - Math.min(...zs));
      const d = dist(cx, cz);
      if (span > 10 && span < 45 && d > 220 && rand() < Math.min(0.75, (d - 220) / 500)) {
        h = (12 + Math.floor(rand() * 13)) * 2.9 + 2;
        tower = true;
        tall++;
      }
    }
    switch (b.kind) {
      case 'grandstand':
        wallC.set('#9aa1a8');
        roofC.set('#2f6db5'); // cadeiras azuis
        break;
      case 'tank':
        wallC.set('#c9cccf');
        roofC.set('#aab0b5');
        break;
      case 'house':
        wallC.set(HOUSE_WALLS[Math.floor(rand() * HOUSE_WALLS.length)]);
        roofC.set(HOUSE_ROOFS[Math.floor(rand() * HOUSE_ROOFS.length)]);
        break;
      default:
        wallC.set(pit ? '#dfe1e3' : tower ? TOWER_COLORS[Math.floor(rand() * TOWER_COLORS.length)] : rand() < 0.5 ? '#c9c7bf' : TOWER_COLORS[Math.floor(rand() * TOWER_COLORS.length)]);
        roofC.set(pit ? '#b9bcbf' : '#8e9193');
    }
    const top = ground + 0.3 + h;
    const n = b.pts.length;
    const windows = b.kind === 'house' ? 1 : b.kind === 'grandstand' || b.kind === 'tank' ? 0 : 2;
    let along = rand() * 10; // começo da grade de janelas (cada prédio diferente)
    // paredes (prédios dos boxes ganham uma faixa de vidro azul no meio, como a torre e os boxes)
    for (let i = 0; i < n; i++) {
      const [x1, z1] = b.pts[i];
      const [x2, z2] = b.pts[(i + 1) % n];
      const len = Math.hypot(x2 - x1, z2 - z1);
      const u1 = along;
      const u2 = along + len;
      along = u2;
      const bands: [number, number, THREE.Color][] = pit
        ? [[ground, top - h * 0.55, wallC], [top - h * 0.55, top - h * 0.2, glassC], [top - h * 0.2, top, wallC]]
        : [[ground, top, wallC]];
      for (const [y0, y1, color] of bands) {
        // leve escurecimento por orientação da parede (dá volume sem custo)
        const shade = 0.85 + 0.15 * Math.abs(Math.cos(Math.atan2(z2 - z1, x2 - x1)));
        c.copy(color).multiplyScalar(shade);
        const w = color === glassC ? 0 : windows;
        const v0 = y0 - ground;
        const v1 = y1 - ground;
        push(x1, y0, z1, c, u1, v0, w);
        push(x2, y0, z2, c, u2, v0, w);
        push(x2, y1, z2, c, u2, v1, w);
        push(x1, y0, z1, c, u1, v0, w);
        push(x2, y1, z2, c, u2, v1, w);
        push(x1, y1, z1, c, u1, v1, w);
      }
    }
    // teto
    const shape = b.pts.map(([x, z]) => new THREE.Vector2(x, z));
    const tris = THREE.ShapeUtils.triangulateShape(shape, []);
    for (const [a, bb, cc] of tris) {
      for (const k of [a, bb, cc]) push(b.pts[k][0], top, b.pts[k][1], roofC, b.pts[k][0], b.pts[k][1], -1);
    }
  }
  for (const [kind, b] of Object.entries(buckets) as ['win' | 'solid' | 'roof', { pos: number[]; col: number[]; uv: number[] }][]) {
    if (!b.pos.length) continue;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(b.pos, 3));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(b.col, 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(b.uv, 2));
    geo.computeVertexNormals();
    const mat = new THREE.MeshStandardMaterial({
      vertexColors: true,
      map: makeBuildingTex(kind),
      roughness: kind === 'roof' ? 0.92 : 0.84,
      side: THREE.DoubleSide
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.receiveShadow = true;
    group.add(mesh);
  }
  console.info(`OSM: ${osm.buildings.length - skipped} prédios, ${tall} viraram torres (${skipped} descartados por encostar na pista)`);
}

/** Lago: polígono plano na altura da margem, com água que reflete o céu. */
function buildWater(osm: OsmData, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const mat = new THREE.MeshPhysicalMaterial({ color: 0x24443c, roughness: 0.06, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.05 });
  for (const poly of osm.water) {
    // o terreno do jogo é suave e não tem a cava do lago: a água fica logo acima do ponto mais alto da margem
    const level = Math.max(...poly.map(([x, z]) => heightAt(x, z))) + 0.15;
    const shape = new THREE.Shape(poly.map(([x, z]) => new THREE.Vector2(x, -z)));
    const geo = new THREE.ShapeGeometry(shape);
    geo.rotateX(-Math.PI / 2); // (x, -z) no plano XY vira (x, z) no chão
    const m = new THREE.Mesh(geo, mat);
    m.position.y = level;
    m.receiveShadow = true;
    group.add(m);
  }
}

/** Mata (áreas de floresta preenchidas) e fileiras de árvores do OSM. */
function buildTrees(
  osm: OsmData,
  track: Track,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  nearTrack: (x: number, z: number) => boolean,
  renderer: THREE.WebGLRenderer,
  extreme: boolean,
  rand: () => number
) {
  // Fase 4 (item 0): semente por polígono de mata e, para tamanho/giro/espécie/tom, pela posição de cada árvore
  // (./sorteio.ts): o que muda num setor não move as árvores dos outros. O `rand` compartilhado (prédios) não é usado.
  void rand;
  const spots: [number, number][] = [];
  osm.forest.forEach((poly, ip) => {
    const rp = randLocal(2026, ip);
    const xs = poly.map(p => p[0]);
    const zs = poly.map(p => p[1]);
    const [x0, x1, z0, z1] = [Math.min(...xs), Math.max(...xs), Math.min(...zs), Math.max(...zs)];
    // uma árvore a cada ~45 m² (mata fechada como no vídeo de referência)
    const tries = Math.min(9000, Math.round(((x1 - x0) * (z1 - z0)) / 45));
    for (let k = 0; k < tries; k++) {
      const x = x0 + rp() * (x1 - x0);
      const z = z0 + rp() * (z1 - z0);
      if (inside(x, z, poly) && !nearTrack(x, z)) spots.push([x, z]);
    }
  });
  for (const line of osm.treeRows) {
    for (let i = 1; i < line.length; i++) {
      const [ax, az] = line[i - 1];
      const [bx, bz] = line[i];
      const n = Math.ceil(Math.hypot(bx - ax, bz - az) / 7);
      for (let k = 0; k < n; k++) {
        const x = ax + ((bx - ax) * k) / n;
        const z = az + ((bz - az) * k) / n;
        if (!nearTrack(x, z)) spots.push([x, z]);
      }
    }
  }
  if (spots.length > 12000) console.warn(`árvores do OSM: ${spots.length}, só 12.000 entram`);
  const todas: TreeSpot[] = spots.slice(0, 12000).map(([x, z]) => {
    const r = randPosicao(x, z, 0x05e1);
    return { x, y: heightAt(x, z) - 0.2, z, scale: 2.0 + r() * 1.3, yaw: r() * Math.PI * 2 };
  });
  console.info(`árvores do OSM: ${todas.length}`);
  // Etapa A (§5): zonas, espaçamento e escala nos setores já revisados (perfil → arvores)
  const trees = arvoresPorSetor(track, todas, 'OSM');
  plantTrees(trees, group, renderer, extreme, randPorArvore(trees));
}

/** Faixas de asfalto ao longo de linhas do OSM (pit lane na altura da pista, kartódromo no terreno). */
/** atTrackHeight: a faixa fica na altura do trecho de pista ao lado (pit lane); senão, no terreno (kart). */
function buildRibbons(lines: Pt[][], width: number, group: THREE.Group, heightAt: (x: number, z: number) => number, track: Track, atTrackHeight: boolean) {
  const mat = new THREE.MeshStandardMaterial({ color: 0x4a4b4d, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1 });
  const tmp = new THREE.Vector3();
  const parts: THREE.BufferGeometry[] = [];
  for (const line of lines) {
    if (line.length < 2) continue;
    const pos: number[] = [];
    const idx: number[] = [];
    let prev = -1; // vértice do ponto anterior mantido (-1 = faixa interrompida)
    line.forEach(([x, z], i) => {
      const a = line[Math.max(0, i - 1)];
      const b = line[Math.min(line.length - 1, i + 1)];
      const dx = b[0] - a[0];
      const dz = b[1] - a[1];
      const l = Math.hypot(dx, dz) || 1;
      const nx = -dz / l;
      const nz = dx / l;
      const loc = track.locate(tmp.set(x, heightAt(x, z) + 3, z));
      // só interrompe onde o asfalto do pit-lane entraria por cima da pista, da saída ou da entrada dos boxes
      // s real da pista antiga (entrada 3840–4050, saída 300–800) levado para a nova
      const inCustomPit = atTrackHeight && loc && ((loc.s >= PIT_A[0] && loc.s <= PIT_A[1]) || (loc.s >= PIT_B[0] && loc.s <= PIT_B[1]));
      if (loc && (inCustomPit || Math.abs(loc.d) - width / 2 < (loc.d < 0 ? loc.wl : loc.wr) - 0.5)) {
        prev = -1;
        return;
      }
      const y = (atTrackHeight && loc ? loc.center.y : heightAt(x, z)) + 0.05;
      const base = pos.length / 3;
      pos.push(x + (nx * width) / 2, y, z + (nz * width) / 2, x - (nx * width) / 2, y, z - (nz * width) / 2);
      if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
      prev = base;
    });
    if (!idx.length) continue;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    parts.push(g);
  }
  if (!parts.length) return;
  const geo = mergeGeometries(parts)!;
  geo.computeVertexNormals();
  const mesh = new THREE.Mesh(geo, mat);
  mesh.material.side = THREE.DoubleSide;
  mesh.receiveShadow = true;
  group.add(mesh);
}

/** Caixa d'água da Sabesp: coluna alta com o reservatório em forma de cálice em cima. */
function buildWaterTower([x, z]: Pt, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const y = heightAt(x, z) - 0.3;
  const mat = new THREE.MeshStandardMaterial({ color: 0xd8dadb, roughness: 0.7 });
  const g = new THREE.Group();
  const col = new THREE.Mesh(new THREE.CylinderGeometry(1.6, 2, 30, 20), mat);
  col.position.y = 15;
  const cup = new THREE.Mesh(new THREE.CylinderGeometry(7, 2, 5, 28), mat);
  cup.position.y = 32.5;
  const lid = new THREE.Mesh(new THREE.CylinderGeometry(7, 7, 1.6, 28), mat);
  lid.position.y = 35.8;
  const cap = new THREE.Mesh(new THREE.ConeGeometry(4, 1.6, 20), mat);
  cap.position.y = 37.4;
  for (const m of [col, cup, lid, cap]) g.add(m);
  g.position.set(x, y, z);
  group.add(g);
}
