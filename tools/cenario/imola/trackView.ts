// Malha completa de Imola: asfalto, faixas brancas, zebras tricolores italianas, escapes verdes,
// caixas de brita (brita.gdshader), pit lane à direita, terreno LiDAR 1 m, árvores do DSM e heroProps.
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import type { Quality } from '@web/render/quality';
import { plantTrees, TreeSpot } from '@web/render/trees';
import { pbr, phTexture, setHiRes } from '@web/render/textures';
import { buildExtras } from './scenery';
import { buildBarriers, buildBridge, buildGrid, buildPatches, tex } from './trackDetails';
import { buildBanners, buildCornerDetails, buildMarshalPosts, buildPits, buildStands, occupied } from './trackside';
import { buildOsmScenery, OsmData } from './osmScenery';
import { buildHorizon, buildTowers, HAZE } from './surroundings';
import { applyLiveAsphaltUV2 } from '../liveAsphalt';
import { addProp } from '../propsRegistry';
import profile from '../../tracks/imola/visual_profile.json';
import surfaces from '../../tracks/imola/imola-surfaces.json';
import canopy from '../../tracks/imola/imola-canopy.json';
import osm from '../../tracks/imola/imola-osm.json';
import terrain from '../../tracks/imola/imola-terrain.json';
import m4Ref from '../../../data/reference/imola-m4.json';

type Pt = [number, number];

function inWrap(s: number, a: number, b: number): boolean {
  return a <= b ? s >= a && s <= b : s >= a || s <= b;
}

/** Terreno de Imola (parque da Emília-Romanha): verde vivo/oliva sem barro vermelho. */
function terrainMaterial(renderer: THREE.WebGLRenderer): THREE.MeshStandardMaterial {
  const mat = pbr('leafy_grass', renderer, { color: 0xbac796 });
  const dry = phTexture('sparse_grass', 'diff', renderer);
  mat.onBeforeCompile = shader => {
    shader.uniforms.dryMap = { value: dry };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec2 vGround;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvGround = (modelMatrix * vec4(transformed, 1.0)).xz;');
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        uniform sampler2D dryMap;
        varying vec2 vGround;
        float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float vnoise(vec2 p) {
          vec2 i = floor(p), f = fract(p);
          f = f * f * (3.0 - 2.0 * f);
          return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
        }`
      )
      .replace(
        '#include <map_fragment>',
        `vec2 gp = vGround;
        float n = vnoise(gp * 0.014) * 0.6 + vnoise(gp * 0.05) * 0.3 + vnoise(gp * 0.25) * 0.1;
        vec3 green = mix(texture2D(map, vMapUv).rgb, texture2D(map, vMapUv * 0.21 + 0.37).rgb, 0.45);
        vec3 dryC = mix(texture2D(dryMap, vMapUv * 0.8).rgb, texture2D(dryMap, vMapUv * 0.17 + 0.61).rgb, 0.45);
        float lg = dot(green, vec3(0.3, 0.59, 0.11));
        green = mix(vec3(lg), green, 1.18) * vec3(0.86, 0.99, 0.72);
        float ld = dot(dryC, vec3(0.3, 0.59, 0.11));
        vec3 straw = vec3(ld) * vec3(1.12, 1.04, 0.62) * (0.85 + 0.25 * texture2D(map, vMapUv * 0.5).g);
        float dryK = smoothstep(0.52, 0.85, n);
        float tone = 0.84 + 0.32 * vnoise(gp * 0.03 + 7.0);
        float lush = smoothstep(0.50, 0.78, vnoise(gp * 0.08 + 13.0)) * 0.45;
        vec3 grassC = mix(mix(green, straw, dryK * 0.48), green * vec3(0.82, 1.0, 0.84), lush * (1.0 - dryK));
        diffuseColor.rgb *= grassC * tone;`
      );
  };
  return mat;
}

function ribbon(
  track: Track,
  a: (i: number) => number,
  b: (i: number) => number,
  lift: number,
  uScale: number,
  vScale: number,
  include: (i: number) => boolean = () => true
): THREE.BufferGeometry {
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
    for (const [off, u] of [
      [a(i), 0],
      [b(i), 1],
    ] as const) {
      v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, lift);
      pos.push(v.x, v.y, v.z);
      uv.push(uScale ? off / uScale : u, (k * STEP) / vScale);
    }
    if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
    prev = base;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

function weather(g: CanvasRenderingContext2D, w: number, h: number, seed: number, rubber: number) {
  const rand = mulberry32(seed);
  const img = g.getImageData(0, 0, w, h);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (rand() - 0.5) * 30 + (rand() < 0.04 ? -36 : 0);
    img.data[i] += n;
    img.data[i + 1] += n;
    img.data[i + 2] += n;
  }
  g.putImageData(img, 0, 0);
  for (let i = 0; i < 80; i++) {
    g.fillStyle = `rgba(65, 58, 48, ${0.03 + rand() * 0.05})`;
    g.beginPath();
    g.ellipse(rand() * w, rand() * h, 4 + rand() * w * 0.2, 6 + rand() * 28, 0, 0, Math.PI * 2);
    g.fill();
  }
  for (let i = 0; i < rubber; i++) {
    g.fillStyle = `rgba(18, 18, 20, ${0.07 + rand() * 0.18})`;
    g.fillRect(rand() * w, rand() * h, 1 + rand() * w * 0.06, 20 + rand() * h * 0.4);
  }
}

function runoffTexture(renderer: THREE.WebGLRenderer, base: string, band: string): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 512;
  const g = c.getContext('2d')!;
  g.fillStyle = base;
  g.fillRect(0, 0, 256, 512);
  g.fillStyle = band;
  g.fillRect(0, 0, 72, 512);
  weather(g, 256, 512, 11, 24);
  return tex(c, renderer, true);
}

function lineTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 32;
  c.height = 512;
  const g = c.getContext('2d')!;
  g.fillStyle = '#f2f2ee';
  g.fillRect(0, 0, 32, 512);
  weather(g, 32, 512, 13, 2);
  return tex(c, renderer, true);
}

function kerbTexture(colors: string[], renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 512;
  const g = c.getContext('2d')!;
  const h = 512 / colors.length;
  colors.forEach((col, i) => {
    g.fillStyle = col;
    g.fillRect(0, i * h, 64, h);
    g.fillStyle = 'rgba(28, 28, 28, 0.45)';
    g.fillRect(0, i * h, 64, 2);
  });
  weather(g, 64, 512, 19, 14);
  return tex(c, renderer, true);
}

function gravelTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 256;
  const g = c.getContext('2d')!;
  g.fillStyle = '#a89a84';
  g.fillRect(0, 0, 256, 256);
  const rand = mulberry32(83);
  const palette = ['#8f826f', '#b5a790', '#9d8f7b', '#7c7161', '#c2b59f'];
  for (let k = 0; k < 4200; k++) {
    g.fillStyle = palette[Math.floor(rand() * palette.length)];
    const r = 0.7 + rand() * 1.9;
    g.fillRect(rand() * 256, rand() * 256, r, r);
  }
  return tex(c, renderer, true);
}

function buildStartGantry(track: Track, group: THREE.Group) {
  const s0 = track.samples[0];
  const mat = new THREE.MeshStandardMaterial({ color: 0x2b2e33, metalness: 0.5, roughness: 0.5 });
  const g = new THREE.Group();
  const span = s0.wl + s0.wr + 4;
  const h = 6.5;
  for (const x of [-span / 2, span / 2]) {
    const pole = new THREE.Mesh(new THREE.BoxGeometry(0.4, h, 0.4), mat);
    pole.position.set(x, h / 2, 0);
    g.add(pole);
  }
  const beam = new THREE.Mesh(new THREE.BoxGeometry(span, 0.55, 0.5), mat);
  beam.position.set(0, h, 0);
  g.add(beam);
  const lights = new THREE.Mesh(
    new THREE.BoxGeometry(3.2, 0.8, 0.35),
    new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.4 })
  );
  lights.position.set(0, h - 0.7, 0.1);
  g.add(lights);
  for (let k = 0; k < 5; k++) {
    const led = new THREE.Mesh(
      new THREE.CircleGeometry(0.18, 14),
      new THREE.MeshStandardMaterial({ color: 0x2a0000, emissive: 0x330000 })
    );
    led.position.set(-1.2 + k * 0.6, h - 0.7, 0.29);
    g.add(led);
  }
  g.position.copy(s0.p).addScaledVector(s0.r, (s0.wr - s0.wl) / 2);
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s0.r, new THREE.Vector3(0, 1, 0), s0.t.clone().negate()));
  group.add(g);
}

function insidePoly(x: number, z: number, poly: Pt[]): boolean {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i];
    const [xj, zj] = poly[j];
    if (zi > z !== zj > z && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) c = !c;
  }
  return c;
}

/** Malha em grade de 4 m dentro de polígonos do OSM (brita ou asfalto de paddock) seguindo heightAt. */
function polyGroundGrid(
  polys: Pt[][],
  step: number,
  lift: number,
  track: Track,
  heightAt: (x: number, z: number) => number,
  skipInside: boolean
): THREE.BufferGeometry | null {
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const tmp = new THREE.Vector3();

  for (const poly of polys) {
    if (poly.length < 3) continue;
    const xs = poly.map(p => p[0]);
    const zs = poly.map(p => p[1]);
    const x0 = Math.floor(Math.min(...xs) / step) * step;
    const x1 = Math.ceil(Math.max(...xs) / step) * step;
    const z0 = Math.floor(Math.min(...zs) / step) * step;
    const z1 = Math.ceil(Math.max(...zs) / step) * step;
    const nx = Math.round((x1 - x0) / step);
    const nz = Math.round((z1 - z0) / step);
    if (nx < 1 || nz < 1 || nx * nz > 12000) continue;

    for (let j = 0; j < nz; j++) {
      for (let i = 0; i < nx; i++) {
        const x = x0 + (i + 0.5) * step;
        const z = z0 + (j + 0.5) * step;
        if (!insidePoly(x, z, poly)) continue;
        const loc = track.locate(tmp.set(x, heightAt(x, z), z));
        if (skipInside && loc) {
          const edge = loc.d < 0 ? loc.wl + loc.kerbL + loc.runL : loc.wr + loc.kerbR + loc.runR;
          if (Math.abs(loc.d) < edge + 0.4) continue;
        }
        const corners: [number, number][] = [
          [x - step * 0.5, z - step * 0.5],
          [x + step * 0.5, z - step * 0.5],
          [x + step * 0.5, z + step * 0.5],
          [x - step * 0.5, z + step * 0.5],
        ];
        const base = pos.length / 3;
        for (const [cx, cz] of corners) {
          let y = heightAt(cx, cz) + lift;
          const cloc = track.locate(tmp.set(cx, y, cz));
          if (cloc && Math.abs(cloc.d) < 35) y = Math.min(y, cloc.center.y - 0.04);
          pos.push(cx, y, cz);
          uv.push(cx / 4, cz / 4);
        }
        idx.push(base, base + 2, base + 1, base, base + 3, base + 2);
      }
    }
  }
  if (!idx.length) return null;
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/** Pit lane de Imola à direita da reta principal, com mureta dos boxes, faixa branca e acesso OSM. */
function buildPitLane(
  track: Track,
  group: THREE.Group,
  renderer: THREE.WebGLRenderer,
  asphalt: THREE.Material,
  concrete: THREE.Material,
  heightAt: (x: number, z: number) => number
) {
  const S = track.samples;
  const N = S.length;
  const kL = track.length / profile.lapLength;
  const open = profile.pitOpenRange;

  // 1) Faixa contínua da pit lane entre a borda direita da pista e o muro dos boxes
  const apron = ribbon(
    track,
    i => S[i].wr - 0.1,
    i => S[i].wallR + 1.5,
    -0.006,
    4,
    4,
    i => inWrap(S[i].s / kL, open.s0, open.s1)
  );
  const apronMesh = new THREE.Mesh(apron, asphalt);
  apronMesh.receiveShadow = true;
  group.add(apronMesh);

  // 2) Faixa branca limite entre pista e pit entry/lane/exit
  const sep = new THREE.Mesh(
    ribbon(
      track,
      i => S[i].wr + 0.1,
      i => S[i].wr + 0.35,
      0.005,
      0,
      10,
      i => inWrap(S[i].s / kL, open.s0, open.s1)
    ),
    new THREE.MeshStandardMaterial({ map: lineTexture(renderer), roughness: 0.75, polygonOffset: true, polygonOffsetFactor: -3 })
  );
  group.add(sep);

  // 3) Faixa chevron verde-e-branco nas bifurcações de entrada e saída dos boxes
  const cg = document.createElement('canvas');
  cg.width = 64;
  cg.height = 128;
  const gx = cg.getContext('2d')!;
  gx.fillStyle = '#008c45';
  gx.fillRect(0, 0, 64, 128);
  gx.fillStyle = '#f2f2ee';
  gx.fillRect(0, 0, 64, 16);
  gx.fillRect(0, 64, 64, 16);
  const goreMat = new THREE.MeshStandardMaterial({
    map: tex(cg, renderer, true),
    roughness: 0.75,
    polygonOffset: true,
    polygonOffsetFactor: -2,
  });
  const goreMesh = new THREE.Mesh(
    ribbon(
      track,
      i => S[i].wr + 0.45,
      i => S[i].wr + 2.1,
      0.002,
      0,
      4,
      i => {
        const sm = S[i].s / kL;
        return inWrap(sm, 4430, 4560) || inWrap(sm, 165, 505);
      }
    ),
    goreMat
  );
  group.add(goreMesh);

  // 4) Mureta de concreto separando a pista do corredor dos boxes ao longo do pit wall (4560..165)
  const wallParts: THREE.BufferGeometry[] = [];
  const inPitWall = (i: number) => inWrap(S[i].s / kL, 4560, 165);
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  let prev = -1;
  for (let k = 0; k <= N; k++) {
    const i = k % N;
    if (!inPitWall(i)) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const base = pos.length / 3;
    const offIn = s.wr + 1.5;
    const offOut = s.wr + 1.95;
    const corners: [number, number][] = [
      [offIn, -0.1],
      [offIn, 1.05],
      [offOut, 1.05],
      [offOut, -0.1],
    ];
    corners.forEach(([off, yOff], cIdx) => {
      v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, yOff);
      pos.push(v.x, v.y, v.z);
      uv.push((k * STEP) / 4, cIdx === 1 || cIdx === 2 ? 0.5 : 0);
    });
    if (prev >= 0) {
      for (let q = 0; q < 3; q++) {
        idx.push(prev + q, prev + q + 1, base + q, prev + q + 1, base + q + 1, base + q);
      }
    }
    prev = base;
  }
  if (idx.length) {
    const wg = new THREE.BufferGeometry();
    wg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    wg.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    wg.setIndex(idx);
    wg.computeVertexNormals();
    wallParts.push(wg);
  }
  if (wallParts.length) {
    const wallMesh = new THREE.Mesh(mergeGeometries(wallParts)!, concrete);
    wallMesh.castShadow = true;
    wallMesh.receiveShadow = true;
    group.add(wallMesh);
  }

  // 5) Asfalto de acesso do OSM (osm.pitLane) fora da faixa principal e pavimentos do paddock (osm.paved)
  const osmPit = (osm as unknown as OsmData).pitLane ?? [];
  const pitRibbonParts: THREE.BufferGeometry[] = [];
  const tmp = new THREE.Vector3();
  for (const line of osmPit) {
    if (line.length < 2) continue;
    const rPos: number[] = [];
    const rIdx: number[] = [];
    let rPrev = -1;
    line.forEach(([x, z], i) => {
      const a = line[Math.max(0, i - 1)];
      const b = line[Math.min(line.length - 1, i + 1)];
      const dx = b[0] - a[0];
      const dz = b[1] - a[1];
      const l = Math.hypot(dx, dz) || 1;
      const nx = (-dz / l) * 4.0;
      const nz = (dx / l) * 4.0;
      const loc = track.locate(tmp.set(x, heightAt(x, z) + 2, z));
      if (loc && Math.abs(loc.d) < (loc.d < 0 ? loc.wl : loc.wr) + 1.2) {
        rPrev = -1;
        return;
      }
      const y = (loc ? loc.center.y : heightAt(x, z)) + 0.03;
      const base = rPos.length / 3;
      rPos.push(x + nx, y, z + nz, x - nx, y, z - nz);
      if (rPrev >= 0) rIdx.push(rPrev, rPrev + 1, base, rPrev + 1, base + 1, base);
      rPrev = base;
    });
    if (rIdx.length) {
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(rPos, 3));
      g.setIndex(rIdx);
      pitRibbonParts.push(g);
    }
  }
  if (pitRibbonParts.length) {
    const g = mergeGeometries(pitRibbonParts)!;
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color: 0x3f4144, roughness: 0.9, side: THREE.DoubleSide }));
    m.receiveShadow = true;
    group.add(m);
  }

  const pavedPolys = ((osm as unknown as OsmData).paved ?? []).filter(poly => {
    if (poly.length < 3) return false;
    const cx = poly.reduce((s, p) => s + p[0], 0) / poly.length;
    const cz = poly.reduce((s, p) => s + p[1], 0) / poly.length;
    return Math.abs(cx) < 1600 && Math.abs(cz) < 1400;
  });
  const pavedGeo = polyGroundGrid(pavedPolys, 5, 0.08, track, heightAt, true);
  if (pavedGeo) {
    const pMat = new THREE.MeshStandardMaterial({ color: 0x45474a, roughness: 0.92, side: THREE.DoubleSide });
    const pMesh = new THREE.Mesh(pavedGeo, pMat);
    pMesh.receiveShadow = true;
    group.add(pMesh);
  }
}

export function buildTrack(track: Track, scene: THREE.Scene, renderer: THREE.WebGLRenderer, quality: Quality) {
  setHiRes(quality.extreme);
  const S = track.samples;
  const kL = track.length / profile.lapLength;

  // Aplica faixas declarativas de escape verde (wideRunoffs) antes de construir faixas/barreiras
  for (const wr of profile.wideRunoffs) {
    for (let i = 0; i < S.length; i++) {
      const sm = S[i].s / kL;
      if (!inWrap(sm, wr.s0, wr.s1)) continue;
      if (wr.side < 0) {
        S[i].runL = Math.max(S[i].runL, wr.width);
        S[i].wallL = Math.max(S[i].wallL, S[i].wl + S[i].kerbL + S[i].runL);
      } else {
        S[i].runR = Math.max(S[i].runR, wr.width);
        S[i].wallR = Math.max(S[i].wallR, S[i].wr + S[i].kerbR + S[i].runR);
      }
    }
  }

  const group = new THREE.Group();
  const mesh = (g: THREE.BufferGeometry, m: THREE.Material, shadow = true, name = '') => {
    const o = new THREE.Mesh(g, m);
    if (name) o.name = name;
    o.receiveShadow = shadow;
    group.add(o);
    return o;
  };

  // Asfalto de autódromo (mesma base escura/quente com variações espaciais de recapeamento + LiveAsphalt)
  const asphaltNormal = phTexture('asphalt_track', 'nor_gl', renderer);
  const asphaltArm = phTexture('asphalt_track', 'arm', renderer);
  const asphalt = pbr('asphalt_track', renderer, { color: 0xffffff });
  asphalt.onBeforeCompile = shader => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec2 vGround;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvGround = (modelMatrix * vec4(transformed, 1.0)).xz;');
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        varying vec2 vGround;
        float aHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float aNoise(vec2 p) {
          vec2 i = floor(p), f = fract(p);
          f = f * f * (3.0 - 2.0 * f);
          return mix(mix(aHash(i), aHash(i + vec2(1, 0)), f.x), mix(aHash(i + vec2(0, 1)), aHash(i + vec2(1, 1)), f.x), f.y);
        }`
      )
      .replace(
        '#include <map_fragment>',
        `#include <map_fragment>
        diffuseColor.rgb = mix(diffuseColor.rgb, texture2D(map, vMapUv * 0.23 + 0.41).rgb, 0.4);
        diffuseColor.rgb = diffuseColor.rgb * vec3(1.12, 1.05, 0.92) + vec3(0.025, 0.024, 0.022);
        vec2 gp = vGround;
        float big = aNoise(gp / 48.0) * 0.65 + aNoise(gp / 19.0 + 13.0) * 0.35;
        diffuseColor.rgb *= mix(vec3(1.0), vec3(0.72, 0.73, 0.76), smoothstep(0.60, 0.70, big));
        diffuseColor.rgb *= mix(vec3(1.0), vec3(1.14, 1.13, 1.10), smoothstep(0.35, 0.25, big));
        diffuseColor.rgb *= 0.94 + 0.12 * aNoise(gp / 8.0 + 3.0);`
      );
  };
  mesh(applyLiveAsphaltUV2(ribbon(track, i => -S[i].wl, i => S[i].wr, 0, 4, 4), track, m4Ref), asphalt);

  const paintOn = (map: THREE.Texture, offset: number, roughness = 1) =>
    new THREE.MeshStandardMaterial({
      map,
      normalMap: asphaltNormal,
      normalScale: new THREE.Vector2(0.6, 0.6),
      roughnessMap: asphaltArm,
      roughness,
      polygonOffset: true,
      polygonOffsetFactor: offset,
    });

  // Faixas brancas nas bordas
  const white = paintOn(lineTexture(renderer), -2, 0.8);
  mesh(ribbon(track, i => -S[i].wl, i => -S[i].wl + 0.35, 0.004, 0, 10), white);
  mesh(ribbon(track, i => S[i].wr - 0.35, i => S[i].wr, 0.004, 0, 10), white);

  // Zebras tricolores italianas (verde/branco/vermelho/branco)
  const kerbMat = paintOn(kerbTexture(profile.kerbColors, renderer), 0, 0.75);
  mesh(ribbon(track, i => -S[i].wl - S[i].kerbL, i => -S[i].wl, 0.012, 0, 6, i => S[i].kerbL > 0), kerbMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wr + S[i].kerbR, 0.012, 0, 6, i => S[i].kerbR > 0), kerbMat);

  // Tapetes sintéticos verdes nos escapes pavimentados (wideRunoffs)
  const runMat = paintOn(runoffTexture(renderer, '#0d6844', '#0a5436'), -1);
  mesh(ribbon(track, i => -S[i].wl - S[i].kerbL - S[i].runL, i => -S[i].wl - S[i].kerbL, -0.008, 4, 8, i => S[i].runL > 0), runMat);
  mesh(ribbon(track, i => S[i].wr + S[i].kerbR, i => S[i].wr + S[i].kerbR + S[i].runR, -0.008, 4, 8, i => S[i].runR > 0), runMat);

  // Grama das margens + caixas de brita (nome 'brita' para ativar shaders/brita.gdshader)
  const grassMat = terrainMaterial(renderer);
  mesh(ribbon(track, i => -S[i].wallL - 1, i => -S[i].wl, -0.04, 6, 6), grassMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wallR + 1, -0.04, 6, 6), grassMat);

  const britaMat = new THREE.MeshStandardMaterial({
    name: 'brita',
    map: gravelTexture(renderer),
    roughness: 0.96,
    metalness: 0,
    polygonOffset: true,
    polygonOffsetFactor: -1,
    side: THREE.DoubleSide,
  });
  const okSurf = surfaces.sandL.length === S.length && surfaces.sandR.length === S.length;
  if (okSurf) {
    const sandLGeo = ribbon(
      track,
      i => -S[i].wallL - 0.4,
      i => -S[i].wl - S[i].kerbL - S[i].runL,
      -0.003,
      4,
      4,
      i => !inWrap(S[i].s / kL, 4520, 420) && surfaces.sandL[i] > 0.35 && S[i].wallL > S[i].wl + S[i].kerbL + S[i].runL + 0.6
    );
    if (sandLGeo.getAttribute('position').count > 0) mesh(sandLGeo, britaMat, true, 'brita_left');

    const sandRGeo = ribbon(
      track,
      i => S[i].wr + S[i].kerbR + S[i].runR,
      i => S[i].wallR + 0.4,
      -0.003,
      4,
      4,
      i => !inWrap(S[i].s / kL, 4520, 420) && surfaces.sandR[i] > 0.35 && S[i].wallR > S[i].wr + S[i].kerbR + S[i].runR + 0.6
    );
    if (sandRGeo.getAttribute('position').count > 0) mesh(sandRGeo, britaMat, true, 'brita_right');
  }

  const concrete = pbr('concrete_wall_008', renderer, { color: 0xdedbd4, side: THREE.DoubleSide });
  const full = !quality.minimal;

  buildBarriers(track, group, renderer, concrete);
  if (full) buildStands(track, group, renderer, concrete);
  buildPits(track, group, renderer, asphalt);
  if (full) {
    buildBanners(track, group, renderer);
    buildMarshalPosts(track, group);
    buildCornerDetails(track, group);
    buildPatches(track, group, renderer);
  }
  buildGrid(track, group, renderer);

  // Linha de chegada quadriculada
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 8;
  const g2 = c.getContext('2d')!;
  for (let x = 0; x < 16; x++) {
    for (let y = 0; y < 2; y++) {
      g2.fillStyle = (x + y) % 2 ? '#111' : '#f4f4f4';
      g2.fillRect(x * 4, y * 4, 4, 4);
    }
  }
  const chk = new THREE.CanvasTexture(c);
  chk.magFilter = THREE.NearestFilter;
  chk.colorSpace = THREE.SRGBColorSpace;
  const s0 = S[0];
  const line = new THREE.Mesh(
    new THREE.PlaneGeometry(s0.wl + s0.wr, 1.2),
    new THREE.MeshStandardMaterial({ map: chk, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -4 })
  );
  line.position.copy(s0.p).addScaledVector(s0.r, (s0.wr - s0.wl) / 2).addScaledVector(s0.n, 0.006);
  line.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s0.r, s0.t, s0.n));
  line.receiveShadow = true;
  group.add(line);
  buildStartGantry(track, group);

  const heightAt = buildTerrain(track, group, grassMat);

  // Polígonos reais de brita do OSM seguindo heightAt (não flutuam em declives)
  const osmGravel = (osm as unknown as OsmData).gravel ?? [];
  const britaOsmGeo = polyGroundGrid(osmGravel, 4, 0.16, track, heightAt, true);
  if (britaOsmGeo) mesh(britaOsmGeo, britaMat, true, 'brita_osm');

  buildPitLane(track, group, renderer, asphalt, concrete, heightAt);
  buildBridge(track, group, renderer);

  const floorY = group.userData.floorY as number;
  if (full) {
    const ring = buildTowers(track, group, heightAt, floorY);
    buildHorizon(group, ring.center, floorY, HAZE);
    buildCanopyTrees(track, group, heightAt, renderer, quality.extreme);
  }
  buildExtras(track, group, renderer);
  if (full) buildOsmScenery(osm as unknown as OsmData, track, group, heightAt, renderer, quality.extreme);

  registerHeroProps(track, heightAt);
  scene.add(group);
}

function registerHeroProps(track: Track, heightAt: (x: number, z: number) => number) {
  const S = track.samples;
  const N = S.length;
  const kL = track.length / profile.lapLength;
  const pos = new THREE.Vector3();
  for (const hp of profile.heroProps) {
    const i = ((Math.round((hp.s * kL) / STEP) % N) + N) % N;
    const s = S[i];
    const side = hp.side as -1 | 0 | 1;
    if (side === 0) {
      const off = (s.wallR - s.wallL) * 0.5 + hp.d_outside;
      pos.copy(s.p).addScaledVector(s.r, off);
      pos.y = s.p.y;
    } else {
      const wall = side < 0 ? s.wallL : s.wallR;
      pos.copy(s.p).addScaledVector(s.r, side * (wall + hp.d_outside));
      pos.y = heightAt(pos.x, pos.z);
    }
    const rotY = Math.atan2(s.t.x, s.t.z) + (hp.yaw_deg * Math.PI) / 180;
    addProp(`imola/${hp.id}`, pos, rotY, hp.scale, false);
  }
}

function demGrid(S: Track['samples']): (x: number, z: number) => number {
  const T = terrain as { x0: number; z0: number; step: number; nx: number; nz: number; h: number[] };
  const { x0, z0, step, nx, nz } = T;
  const at = (i: number, j: number) => T.h[Math.max(0, Math.min(nz - 1, j)) * nx + Math.max(0, Math.min(nx - 1, i))];
  const sm = new Float32Array(nx * nz);
  for (let j = 0; j < nz; j++) {
    for (let i = 0; i < nx; i++) {
      let a = 0;
      for (let dj = -1; dj <= 1; dj++) {
        for (let di = -1; di <= 1; di++) a += at(i + di, j + dj) * (di || dj ? 1 : 2);
      }
      sm[j * nx + i] = a / 10;
    }
  }
  const raw = (x: number, z: number) => {
    const fx = Math.max(0, Math.min(nx - 1.001, (x - x0) / step));
    const fz = Math.max(0, Math.min(nz - 1.001, (z - z0) / step));
    const i = Math.floor(fx);
    const j = Math.floor(fz);
    const u = fx - i;
    const v = fz - j;
    const g = (a: number, b: number) => sm[b * nx + a];
    return (g(i, j) * (1 - u) + g(i + 1, j) * u) * (1 - v) + (g(i, j + 1) * (1 - u) + g(i + 1, j + 1) * u) * v;
  };
  const diffs = S.filter((_, k) => k % 5 === 0)
    .map(s => raw(s.p.x, s.p.z) - s.p.y)
    .sort((a, b) => a - b);
  const offset = diffs[Math.floor(diffs.length / 2)];
  return (x, z) => raw(x, z) - offset;
}

function buildTerrain(track: Track, group: THREE.Group, grassMat: THREE.MeshStandardMaterial): (x: number, z: number) => number {
  const S = track.samples;
  const box = new THREE.Box3();
  S.forEach(s => box.expandByPoint(s.p));
  box.expandByScalar(700);
  const cell = 12;
  const nx = Math.ceil((box.max.x - box.min.x) / cell);
  const nz = Math.ceil((box.max.z - box.min.z) / cell);
  const coarse = 40;
  const buckets = new Map<string, number[]>();
  S.forEach((s, i) => {
    if (i % 3) return;
    const k = `${Math.floor(s.p.x / coarse)},${Math.floor(s.p.z / coarse)}`;
    if (!buckets.has(k)) buckets.set(k, []);
    buckets.get(k)!.push(i);
  });
  const gridAt = demGrid(S);
  const heightAt = (x: number, z: number) => {
    const cx = Math.floor(x / coarse);
    const cz = Math.floor(z / coarse);
    let best = Infinity;
    let h = 0;
    for (let i = -4; i <= 4; i++) {
      for (let j = -4; j <= 4; j++) {
        for (const k of buckets.get(`${cx + i},${cz + j}`) ?? []) {
          const p = S[k].p;
          const d2 = (p.x - x) ** 2 + (p.z - z) ** 2;
          if (d2 < best) {
            best = d2;
            h = p.y;
          }
        }
      }
    }
    const g = gridAt(x, z);
    if (best === Infinity) return g - 0.45;
    const d = Math.sqrt(best);
    const far = Math.max(0, Math.min(1, (d - 16) / 60));
    return h * (1 - far) + g * far - 0.45 - Math.min(0.8, d * 0.005);
  };

  const geo = new THREE.PlaneGeometry(nx * cell, nz * cell, nx, nz);
  geo.rotateX(-Math.PI / 2);
  geo.translate((box.min.x + box.max.x) / 2, 0, (box.min.z + box.max.z) / 2);
  const pos = geo.attributes.position as THREE.BufferAttribute;
  for (let i = 0; i < pos.count; i++) pos.setY(i, heightAt(pos.getX(i), pos.getZ(i)));
  const uv = geo.attributes.uv as THREE.BufferAttribute;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, pos.getX(i) / 6, pos.getZ(i) / 6);
  geo.computeVertexNormals();
  const terrainMesh = new THREE.Mesh(geo, grassMat);
  terrainMesh.receiveShadow = true;
  group.add(terrainMesh);

  let minY = Infinity;
  for (let i = 0; i < pos.count; i++) minY = Math.min(minY, pos.getY(i));
  const farGeo = new THREE.PlaneGeometry(12000, 12000);
  const farMat = new THREE.MeshStandardMaterial({ color: 0x627c3d, roughness: 0.95, metalness: 0 });
  const far = new THREE.Mesh(farGeo, farMat);
  far.rotation.x = -Math.PI / 2;
  far.position.set((box.min.x + box.max.x) / 2, minY - 2, (box.min.z + box.max.z) / 2);
  group.add(far);
  group.userData.floorY = minY - 2;
  return heightAt;
}

/** Planta as 5.500 árvores reais extraídas do DSM - DTM (imola-canopy.json), evitando pista/prédios/água. */
function buildCanopyTrees(
  track: Track,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  renderer: THREE.WebGLRenderer,
  extreme: boolean
) {
  const rand = mulberry32(47);
  const tmp = new THREE.Vector3();
  const water = ((osm as unknown as OsmData).water ?? []).filter(w => w.length < 80);
  const gravel = (osm as unknown as OsmData).gravel ?? [];
  const data = canopy as number[];
  const spots: TreeSpot[] = [];

  for (let i = 0; i + 2 < data.length; i += 3) {
    const x = data[i];
    const z = data[i + 1];
    const scale = data[i + 2];
    const y = heightAt(x, z);
    const loc = track.locate(tmp.set(x, y, z));
    if (loc && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + 6.5) continue;
    if (occupied(track, x, z, y)) continue;
    if (water.some(w => insidePoly(x, z, w))) continue;
    if (gravel.some(g => insidePoly(x, z, g))) continue;
    spots.push({
      x,
      y: y - 0.3,
      z,
      scale,
      yaw: rand() * Math.PI * 2,
    });
  }
  plantTrees(spots, group, renderer, extreme, rand);
}
