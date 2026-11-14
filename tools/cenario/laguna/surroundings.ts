// Cópia adaptada para Laguna Seca (tools/cenario/vite.config.ts troca o módulo do web por este só com
// TRACK=laguna-seca): sem anel de prédios (vale aberto em Monterey) e horizonte de morros secos da Califórnia
// (Santa Lucia ao sul, Gabilan a leste), em camadas cada vez mais azuladas, com carvalhos escuros nos mais perto.
// Arredores distantes de Interlagos (etapa 5 do PLANO-visual): o anel de prédios residenciais altos dos bairros
// em volta (Interlagos, Cidade Dutra, Socorro), que é o que dá a cara de São Paulo, e o contorno de cidade e
// morros no horizonte, azulado pela distância. Tudo procedural e em poucas chamadas de desenho.
import * as THREE from 'three';
import type { Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';

/** névoa da distância (mesma cor da neblina da cena) */
export const HAZE = new THREE.Color(0xaabdd2);

/** cores de reboco dos prédios residenciais (bege, creme, salmão, branco, cinza-azulado, terracota) */
export const TOWER_COLORS = ['#e8dcc4', '#f1e9d6', '#e3c9a8', '#d9b8a0', '#f4f2ec', '#c9d0d6', '#e6d3b0', '#cfa58a', '#dcdcd4', '#bfc8cf', '#efe0c0'];

/**
 * Fachada de prédio residencial no shader, em coordenadas de mundo: andares de 2,9 m com janelas, faixa de
 * varanda (laje saliente clara e guarda-corpo de vidro escuro) em parte dos prédios, coluna de caixa de escada
 * sem janela, e telhado de laje cinza com caixa d'água. A cor do reboco vem de instanceColor.
 */
function towerMaterial(): THREE.MeshStandardMaterial {
  const mat = new THREE.MeshStandardMaterial({ roughness: 0.85 });
  mat.onBeforeCompile = shader => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vW;\nvarying vec3 vN;\nvarying float vSeed;\nvarying float vH;')
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        vec4 wp = modelMatrix * instanceMatrix * vec4(transformed, 1.0);
        vW = wp.xyz;
        vN = normalize(mat3(instanceMatrix) * normal);
        vec3 o = (instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        vSeed = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453);
        vH = (transformed.y) * length(instanceMatrix[1].xyz);`
      );
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        varying vec3 vW;
        varying vec3 vN;
        varying float vSeed;
        varying float vH;
        float tH(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7); }`
      )
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
        float glass = 0.0;
        if (abs(vN.y) > 0.5) {
          diffuseColor.rgb = vec3(0.52, 0.52, 0.5) * (0.85 + 0.3 * tH(floor(vW.xz / 3.0)));
        } else {
          float u = abs(vN.x) > abs(vN.z) ? vW.z : vW.x;
          float floorH = 2.9;
          vec2 cell = vec2(floor(u / 3.2), floor(vH / floorH));
          vec2 f = vec2(mod(u, 3.2), mod(vH, floorH));
          bool balcony = vSeed > 0.45;
          float ground = step(vH, 3.5);
          // coluna da escada (sem janela) a cada ~6 vãos
          float stair = step(mod(cell.x + floor(vSeed * 7.0), 6.0), 0.5);
          float inX = step(abs(f.x - 1.6), balcony ? 1.35 : 0.75);
          float inY = step(0.8, f.y) * step(f.y, balcony ? 2.55 : 2.2);
          float lit = step(0.06, tH(cell + vSeed * 13.0));
          glass = inX * inY * lit * (1.0 - stair) * (1.0 - ground);
          vec3 sky = mix(vec3(0.08, 0.1, 0.13), vec3(0.32, 0.38, 0.46), tH(cell + 3.0));
          diffuseColor.rgb = mix(diffuseColor.rgb, sky, glass);
          if (balcony) {
            // laje da varanda (faixa clara) e guarda-corpo (faixa escura translúcida) em cada andar
            float slab = step(f.y, 0.22) * (1.0 - ground);
            float rail = step(0.22, f.y) * step(f.y, 1.05) * (1.0 - stair) * (1.0 - ground);
            diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.93, 0.92, 0.89), slab * 0.8);
            diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * 0.55, rail * 0.6);
          }
          // térreo mais escuro (portaria, garagem) e sujeira escorrida embaixo
          diffuseColor.rgb *= 1.0 - ground * 0.35;
          diffuseColor.rgb *= 0.82 + 0.18 * smoothstep(0.0, 12.0, vH);
          // lado na sombra um pouco mais frio
          diffuseColor.rgb *= 0.9 + 0.1 * abs(vN.x);
        }`
      )
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = mix(roughnessFactor, 0.15, glass);');
  };
  return mat;
}

/** distância horizontal (m) do ponto ao traçado (amostra a cada 8 m) */
export function trackDistance(track: Track) {
  const S = track.samples.filter((_, i) => i % 4 === 0);
  return (x: number, z: number) => {
    let best = Infinity;
    for (const s of S) {
      const d2 = (s.p.x - x) ** 2 + (s.p.z - z) ** 2;
      if (d2 < best) best = d2;
    }
    return Math.sqrt(best);
  };
}

/**
 * Anel de prédios altos (15–25 andares) entre ~350 m e ~2,8 km da pista, em grupos (condomínios de 2–6 torres)
 * mais densos a norte e a leste (bairros mais verticais). Uma chamada de desenho para todos.
 */
export function buildTowers(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number, floorY: number) {
  const rand = mulberry32(1554);
  const dist = trackDistance(track);
  const box = new THREE.Box3();
  track.samples.forEach(s => box.expandByPoint(s.p));
  const center = box.getCenter(new THREE.Vector3());
  const radius = Math.max(box.max.x - box.min.x, box.max.z - box.min.z) / 2;
  // Laguna: nenhum prédio alto em volta (o anel fica vazio; arredores.mjs grava torres.json = [])
  if (center) return { center, radius };
  const geo = new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0);
  const MAX = 1400;
  const mesh = new THREE.InstancedMesh(geo, towerMaterial(), MAX);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const up = new THREE.Vector3(0, 1, 0);
  const color = new THREE.Color();
  let n = 0;
  for (let tries = 0; tries < 6000 && n < MAX; tries++) {
    const ang = rand() * Math.PI * 2;
    // mais prédios a norte (-z) e a leste (+x)
    const bias = 0.6 + 0.4 * Math.max(0, -Math.sin(ang)) + 0.3 * Math.max(0, Math.cos(ang));
    if (rand() > bias) continue;
    const r = radius + 250 + Math.pow(rand(), 0.8) * 2300;
    const cx = center.x + Math.cos(ang) * r;
    const cz = center.z + Math.sin(ang) * r;
    const d = dist(cx, cz);
    if (d < 320) continue;
    // condomínio: 2 a 6 torres iguais lado a lado
    const k = 2 + Math.floor(rand() * 5);
    const floors = 12 + Math.floor(rand() * 14) + (d > 1200 ? Math.floor(rand() * 6) : 0);
    const h = floors * 2.9 + 2;
    const w = 14 + rand() * 10;
    const dpt = 12 + rand() * 8;
    const yaw = ang + (rand() < 0.5 ? 0 : Math.PI / 2) + (rand() - 0.5) * 0.3;
    q.setFromAxisAngle(up, yaw);
    color.set(TOWER_COLORS[Math.floor(rand() * TOWER_COLORS.length)]);
    const gap = w + 10 + rand() * 12;
    for (let t = 0; t < k && n < MAX; t++) {
      const off = (t - (k - 1) / 2) * gap;
      const x = cx + Math.cos(yaw) * off;
      const z = cz - Math.sin(yaw) * off;
      if (dist(x, z) < 300) continue;
      const ground = heightAt(x, z);
      const base = Math.min(ground, floorY) - 6;
      const top = ground + h * (0.9 + rand() * 0.2);
      m.compose(new THREE.Vector3(x, base, z), q, new THREE.Vector3(w, top - base, dpt));
      mesh.setMatrixAt(n, m);
      mesh.setColorAt(n, color);
      n++;
    }
  }
  mesh.count = n;
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  mesh.computeBoundingSphere();
  mesh.receiveShadow = false;
  group.add(mesh);
  console.info(`horizonte: ${n} prédios altos`);
  return { center, radius };
}

/**
 * Contorno do horizonte: faixa cilíndrica bem longe com morros (Serra do Mar a sul, Cantareira a norte) e a
 * cidade em camadas, cada camada mais clara e azulada (névoa da distância). Sem neblina própria: as cores já
 * vêm "enevoadas" e o topo é transparente, deixando o céu do HDRI aparecer.
 */
export function buildHorizon(group: THREE.Group, center: THREE.Vector3, floorY: number, haze: THREE.Color) {
  const W = 4096;
  const H = 256;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const rand = mulberry32(99);
  const base = H - 4;
  /** cor da camada misturada com a névoa (k = 0 perto, 1 longe) */
  const tint = (hex: string, k: number) => '#' + new THREE.Color(hex).lerp(haze, k).getHexString();
  // morros: soma de senos; mais altos ao sul (Santa Lucia, meio da textura) e a leste
  const ridge = (amp: number, seed: number, col: string, lift: number) => {
    const ys: number[] = [];
    g.fillStyle = col;
    g.beginPath();
    g.moveTo(0, base);
    for (let x = 0; x <= W; x += 8) {
      const u = (x / W) * Math.PI * 2;
      const south = 0.5 + 0.5 * Math.cos(u - Math.PI * 0.5 - seed * 0.2);
      const east = 0.5 + 0.5 * Math.cos(u - seed);
      const y = amp * (0.3 + 0.45 * south + 0.25 * east) *
        (0.62 + 0.2 * Math.sin(u * 4 + seed) + 0.12 * Math.sin(u * 9 + seed * 2) + 0.06 * Math.sin(u * 23 + seed * 3));
      ys.push(base - lift - y);
      g.lineTo(x, base - lift - y);
    }
    g.lineTo(W, base);
    g.closePath();
    g.fill();
    return ys;
  };
  ridge(150, 0.4, tint('#a3b2c0', 0.45), 50); // serras distantes, azuladas
  ridge(105, 1.9, tint('#b9a878', 0.35), 46); // morros intermediários, oliva enevoado
  const near = ridge(62, 3.3, tint('#dcb879', 0.18), 42); // morros perto: palha dourada
  // carvalhos nos morros perto: manchas escuras pequenas, mais nas encostas
  g.fillStyle = tint('#6b6a40', 0.25);
  for (let k = 0; k < 900; k++) {
    const x = rand() * W;
    const top = near[Math.min(near.length - 1, Math.floor(x / 8))];
    const y = top + 3 + rand() * (base - 42 - top);
    if (y > base - 44) continue;
    g.beginPath();
    g.ellipse(x, y, 2 + rand() * 4, 1.5 + rand() * 2, 0, 0, Math.PI * 2);
    g.fill();
  }
  // base contínua (o chão distante encobre)
  g.fillStyle = tint('#d2b077', 0.18);
  g.fillRect(0, base - 44, W, 50);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = THREE.RepeatWrapping;
  tex.anisotropy = 4;
  const R = 3900;
  const height = 420;
  const geo = new THREE.CylinderGeometry(R, R, height, 128, 1, true);
  const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, side: THREE.BackSide, fog: false, depthWrite: false, alphaTest: 0.02 });
  const ring = new THREE.Mesh(geo, mat);
  ring.position.set(center.x, floorY - 40 + height / 2, center.z);
  ring.renderOrder = -2;
  ring.frustumCulled = false;
  group.add(ring);
}
