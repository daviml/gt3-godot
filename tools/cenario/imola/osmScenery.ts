// Arredores reais de Imola (OSM + DSM): casas e prédios em tons da Emília-Romanha com fundações -3,5 m,
// Rio Santerno contínuo seguindo a calha do terreno (riverLine) e matas/fileiras de árvores.
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import { plantTrees, TreeSpot } from '@web/render/trees';
import { TOWER_COLORS, trackDistance } from './surroundings';
import { occupied } from './trackside';

type Pt = [number, number];
export interface OsmData {
  buildings: { pts: Pt[]; h: number; kind: string; a: number }[];
  water: Pt[][];
  forest: Pt[][];
  woods?: Pt[][];
  grass: Pt[][];
  treeRows: Pt[][];
  pitLane: Pt[][];
  kart: Pt[][];
  waterTower: Pt | null;
  corners?: { name: string; pts: Pt[] }[];
  riverLine?: Pt[][];
  paved?: Pt[][];
  gravel?: Pt[][];
}

export function trackSections(_osm: OsmData, track: Track) {
  return track.sections ?? [];
}

const HOUSE_WALLS = ['#c8aa8a', '#b89678', '#cfa984', '#a88b73', '#beae98', '#9e8c7a'];
const HOUSE_ROOFS = ['#8b3d28', '#783322', '#964a30', '#6e3222', '#5c5a58'];
const BIG_WALLS = ['#9a948a', '#85898e', '#a69888', '#8f887d', ...TOWER_COLORS.slice(0, 2).map(() => '#9d9589')];
const BIG_ROOFS = ['#5c6064', '#505458', '#686b6e'];

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
  const rand = mulberry32(2027);
  const tmp = new THREE.Vector3();
  const L = track.length;

  const nearTrack = (x: number, z: number, treeMargin = false) => {
    const loc = track.locate(tmp.set(x, heightAt(x, z), z));
    if (!loc) return false;
    const margin = treeMargin ? 7 : 12;
    return Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + margin || occupied(track, x, z, tmp.y);
  };
  const nearTrees = (x: number, z: number) => nearTrack(x, z, true);

  // Complexo de boxes de Imola fica do lado direito da reta principal (side = +1)
  const pitZone = (x: number, z: number) => {
    const loc = track.locate(tmp.set(x, heightAt(x, z), z));
    return !!loc && loc.d > 0 && loc.d < 95 && (loc.s > L - 400 || loc.s < 220);
  };

  buildBuildings(osm, track, group, heightAt, nearTrack, pitZone, rand);
  buildWater(osm, group, heightAt);
  buildTrees(osm, group, heightAt, nearTrees, renderer, extreme, rand);
}

function makeBuildingTex(kind: 'win' | 'solid' | 'roof'): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512;
  const ctx = c.getContext('2d')!;
  if (kind === 'win') {
    ctx.fillStyle = '#dddad2';
    ctx.fillRect(0, 0, 512, 512);
    for (let row = 0; row < 4; row++) {
      const y0 = row * 128;
      ctx.fillStyle = row % 2 === 0 ? '#d5d1c7' : '#dfdcd2';
      ctx.fillRect(0, y0, 512, 128);
      ctx.fillStyle = '#a8a59c';
      ctx.fillRect(0, y0, 512, 10);
      ctx.fillStyle = '#b9b6ad';
      ctx.fillRect(0, y0 + 118, 512, 10);
      for (let col = 0; col < 4; col++) {
        const x0 = col * 128;
        ctx.fillStyle = '#484d54';
        ctx.fillRect(x0 + 18, y0 + 24, 92, 76);
        const tone = (row * 7 + col * 13) % 5;
        ctx.fillStyle =
          tone === 0 ? '#1f3042' : tone === 1 ? '#263a4e' : tone === 2 ? '#1a2634' : tone === 3 ? '#2c4258' : '#213344';
        ctx.fillRect(x0 + 22, y0 + 28, 84, 68);
        ctx.fillStyle = 'rgba(175,205,230,0.14)';
        ctx.fillRect(x0 + 24, y0 + 30, 80, 18);
        ctx.fillStyle = '#3f444c';
        ctx.fillRect(x0 + 62, y0 + 28, 4, 68);
        ctx.fillStyle = '#8b8f95';
        ctx.fillRect(x0 + 14, y0 + 100, 100, 6);
      }
    }
  } else if (kind === 'solid') {
    ctx.fillStyle = '#dcdcd8';
    ctx.fillRect(0, 0, 512, 512);
    for (let row = 0; row < 4; row++) {
      const y0 = row * 128;
      ctx.fillStyle = row % 2 === 0 ? '#d4d4cf' : '#dfdfda';
      ctx.fillRect(0, y0, 512, 128);
      ctx.fillStyle = '#a6a8ac';
      ctx.fillRect(0, y0, 512, 6);
      for (let col = 0; col < 4; col++) {
        ctx.fillStyle = '#b4b6ba';
        ctx.fillRect(col * 128, y0, 5, 128);
      }
    }
  } else {
    ctx.fillStyle = '#cccccc';
    ctx.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 512; i += 64) {
      ctx.fillStyle = '#b2b2b2';
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

function buildBuildings(
  osm: OsmData,
  track: Track,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  nearTrack: (x: number, z: number) => boolean,
  pitZone: (x: number, z: number) => boolean,
  rand: () => number
) {
  const buckets = {
    win: { pos: [] as number[], col: [] as number[], uv: [] as number[] },
    solid: { pos: [] as number[], col: [] as number[], uv: [] as number[] },
    roof: { pos: [] as number[], col: [] as number[], uv: [] as number[] },
  };
  const c = new THREE.Color();
  const push = (x: number, y: number, z: number, color: THREE.Color, u = 0, v = 0, w = 0) => {
    const b = w < 0 ? buckets.roof : w > 0 ? buckets.win : buckets.solid;
    const scale = w < 0 ? 1 / 16 : 1 / 12;
    b.pos.push(x, y, z);
    b.col.push(color.r, color.g, color.b);
    b.uv.push(u * scale, v * scale);
  };
  const wallC = new THREE.Color();
  const roofC = new THREE.Color();
  const glassC = new THREE.Color('#253e5c');
  let skipped = 0;
  const dist = trackDistance(track);

  for (const b of osm.buildings) {
    if (b.pts.length < 3) continue;
    if (b.pts.some(([x, z]) => nearTrack(x, z))) {
      skipped++;
      continue;
    }
    const cx = b.pts.reduce((s, p) => s + p[0], 0) / b.pts.length;
    const cz = b.pts.reduce((s, p) => s + p[1], 0) / b.pts.length;
    if (dist(cx, cz) > 800 || pitZone(cx, cz)) {
      skipped++;
      continue;
    }
    const xs0 = b.pts.map(p => p[0]);
    const zs0 = b.pts.map(p => p[1]);
    const span0 = Math.max(Math.max(...xs0) - Math.min(...xs0), Math.max(...zs0) - Math.min(...zs0));
    if ((b.kind === 'grandstand' || (b.kind === 'big' && !b.h && span0 > 45)) && dist(cx, cz) < 120) {
      skipped++;
      continue;
    }

    // Fundações profundas (-3,5 m abaixo do ponto mais baixo do terreno sob o prédio) para não flutuar em encostas
    const groundPts = b.pts.map(([x, z]) => heightAt(x, z));
    const minGround = Math.min(...groundPts);
    const maxGround = Math.max(...groundPts);
    const centerGround = heightAt(cx, cz);
    const ground = minGround - 3.5;

    const pit = (b.kind === 'big' || b.kind === 'garage') && pitZone(cx, cz);
    let h = b.h;
    if (!h) h = b.kind === 'house' ? 4.5 + rand() * 3.0 : 6.0 + rand() * 5.0;
    if (dist(cx, cz) < 85) h = Math.min(h, 10.5);
    if (pit) h = Math.max(h, 8.5);
    const top = Math.max(maxGround + 2.5, centerGround + h);

    switch (b.kind) {
      case 'grandstand':
        wallC.set('#6e747c');
        roofC.set('#274f82');
        break;
      case 'roof':
        wallC.set('#7a7874');
        roofC.set('#595c60');
        break;
      case 'house':
        wallC.set(HOUSE_WALLS[Math.floor(rand() * HOUSE_WALLS.length)]);
        roofC.set(HOUSE_ROOFS[Math.floor(rand() * HOUSE_ROOFS.length)]);
        break;
      default:
        wallC.set(BIG_WALLS[Math.floor(rand() * BIG_WALLS.length)]);
        roofC.set(BIG_ROOFS[Math.floor(rand() * BIG_ROOFS.length)]);
    }

    const n = b.pts.length;
    const windows = b.kind === 'house' ? 1 : b.kind === 'grandstand' || b.kind === 'roof' ? 0 : 2;
    let along = rand() * 10;
    for (let i = 0; i < n; i++) {
      const [x1, z1] = b.pts[i];
      const [x2, z2] = b.pts[(i + 1) % n];
      const len = Math.hypot(x2 - x1, z2 - z1);
      const u1 = along;
      const u2 = along + len;
      along = u2;
      const bands: [number, number, THREE.Color][] = pit
        ? [
            [ground, top - h * 0.55, wallC],
            [top - h * 0.55, top - h * 0.2, glassC],
            [top - h * 0.2, top, wallC],
          ]
        : [[ground, top, wallC]];
      for (const [y0, y1, color] of bands) {
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
      roughness: kind === 'roof' ? 0.92 : 0.86,
      side: THREE.DoubleSide,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.receiveShadow = true;
    group.add(mesh);
  }
  console.info(`OSM Imola: ${osm.buildings.length - skipped} prédios (${skipped} descartados por colisão/pista)`);
}

/** Rio Santerno contínuo seguindo a calha do DEM (riverLine) + pequenos lagos/tanques planos em water[]. */
function buildWater(osm: OsmData, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const mat = new THREE.MeshPhysicalMaterial({
    color: 0x264b42,
    roughness: 0.08,
    metalness: 0.05,
    clearcoat: 1,
    clearcoatRoughness: 0.06,
    polygonOffset: true,
    polygonOffsetFactor: -1,
    side: THREE.DoubleSide,
  });

  // 1) Rio Santerno: fita contínua acompanhando a inclinação real da calha escavada no DEM
  const width = 26;
  const riverParts: THREE.BufferGeometry[] = [];
  for (const rawLine of osm.riverLine ?? []) {
    const runs: Pt[][] = [];
    let cur: Pt[] = [];
    for (const [x, z] of rawLine) {
      if (Math.abs(x) < 2100 && Math.abs(z) < 2100) {
        cur.push([x, z]);
      } else if (cur.length) {
        runs.push(cur);
        cur = [];
      }
    }
    if (cur.length) runs.push(cur);

    for (const clipped of runs) {
      if (clipped.length < 2) continue;

      // Reamostra a cada ~10 m para suavizar curvas e seguir o declive do terreno sem atravessar vértices
      const pts: Pt[] = [clipped[0]];
      for (let i = 1; i < clipped.length; i++) {
        const [ax, az] = clipped[i - 1];
        const [bx, bz] = clipped[i];
        const dist = Math.hypot(bx - ax, bz - az);
        const steps = Math.max(1, Math.ceil(dist / 10));
        for (let k = 1; k <= steps; k++) {
          const t = k / steps;
          pts.push([ax + (bx - ax) * t, az + (bz - az) * t]);
        }
      }

      const pos: number[] = [];
      const idx: number[] = [];
      for (let i = 0; i < pts.length; i++) {
        const a = pts[Math.max(0, i - 1)];
        const b = pts[Math.min(pts.length - 1, i + 1)];
        const dx = b[0] - a[0];
        const dz = b[1] - a[1];
        const l = Math.hypot(dx, dz) || 1;
        const nx = (-dz / l) * (width * 0.5);
        const nz = (dx / l) * (width * 0.5);
        const [cx, cz] = pts[i];
        const y = heightAt(cx, cz) + 0.45;
        const base = pos.length / 3;
        pos.push(cx + nx, y, cz + nz, cx - nx, y, cz - nz);
        if (i > 0) idx.push(base - 2, base - 1, base, base - 1, base + 1, base);
      }
      if (idx.length) {
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        g.setIndex(idx);
        riverParts.push(g);
      }
    }
  }
  if (riverParts.length) {
    const geo = mergeGeometries(riverParts)!;
    geo.computeVertexNormals();
    const mesh = new THREE.Mesh(geo, mat);
    mesh.receiveShadow = true;
    group.add(mesh);
  }

  // 2) Pequenos lagos/tanques quase planos em osm.water (ignora water[0] inclinado do Santerno)
  for (const poly of osm.water) {
    if (poly.length < 3 || poly.length > 80) continue;
    const hs = poly.map(([x, z]) => heightAt(x, z));
    const minH = Math.min(...hs);
    const maxH = Math.max(...hs);
    if (maxH - minH > 2.8) continue;
    const sorted = [...hs].sort((a, b) => a - b);
    const level = sorted[Math.floor(sorted.length / 2)] + 0.15;
    const shape = new THREE.Shape(poly.map(([x, z]) => new THREE.Vector2(x, -z)));
    const geo = new THREE.ShapeGeometry(shape);
    geo.rotateX(-Math.PI / 2);
    const m = new THREE.Mesh(geo, mat);
    m.position.y = level;
    m.receiveShadow = true;
    group.add(m);
  }
}

/** Matas do OSM (forest + woods + treeRows) limitadas a 3.500 copas para somar com imola-canopy.json. */
function buildTrees(
  osm: OsmData,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  nearTrack: (x: number, z: number) => boolean,
  renderer: THREE.WebGLRenderer,
  extreme: boolean,
  rand: () => number
) {
  const spots: [number, number][] = [];
  const forestPolys = [...(osm.forest ?? []), ...(osm.woods ?? [])];
  for (const poly of forestPolys) {
    if (poly.length < 3) continue;
    const xs = poly.map(p => p[0]);
    const zs = poly.map(p => p[1]);
    const [x0, x1, z0, z1] = [Math.min(...xs), Math.max(...xs), Math.min(...zs), Math.max(...zs)];
    const tries = Math.min(2500, Math.round(((x1 - x0) * (z1 - z0)) / 90));
    for (let k = 0; k < tries; k++) {
      const x = x0 + rand() * (x1 - x0);
      const z = z0 + rand() * (z1 - z0);
      if (inside(x, z, poly) && !nearTrack(x, z)) spots.push([x, z]);
    }
  }
  for (const line of osm.treeRows ?? []) {
    for (let i = 1; i < line.length; i++) {
      const [ax, az] = line[i - 1];
      const [bx, bz] = line[i];
      const n = Math.ceil(Math.hypot(bx - ax, bz - az) / 8);
      for (let k = 0; k < n; k++) {
        const x = ax + ((bx - ax) * k) / n;
        const z = az + ((bz - az) * k) / n;
        if (!nearTrack(x, z)) spots.push([x, z]);
      }
    }
  }
  const trees: TreeSpot[] = spots.slice(0, 3500).map(([x, z]) => ({
    x,
    y: heightAt(x, z) - 0.35,
    z,
    scale: 1.8 + rand() * 1.1,
    yaw: rand() * Math.PI * 2,
  }));
  if (trees.length) plantTrees(trees, group, renderer, extreme, rand);
}
