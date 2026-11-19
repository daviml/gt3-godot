// Arredores distantes de Imola: sem torres residenciais altas (parque + cidade baixa + Apeninos da
// Emília-Romanha) e horizonte cilíndrico com colinas verdes/oliva ao sul/oeste e casario baixo ao norte.
import * as THREE from 'three';
import type { Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';

export const HAZE = new THREE.Color(0xb6cbe0);
export const TOWER_COLORS = ['#e8dcc4', '#f1e9d6', '#e3c9a8', '#d9b8a0', '#f4f2ec', '#c9d0d6'];

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

export function buildTowers(track: Track, _group: THREE.Group, _heightAt: (x: number, z: number) => number, _floorY: number) {
  const box = new THREE.Box3();
  track.samples.forEach(s => box.expandByPoint(s.p));
  const center = box.getCenter(new THREE.Vector3());
  const radius = Math.max(box.max.x - box.min.x, box.max.z - box.min.z) / 2;
  // Imola: sem anel de arranha-céus (horizonte de parque, cidade baixa e colinas dos Apeninos)
  return { center, radius };
}

export function buildHorizon(group: THREE.Group, center: THREE.Vector3, floorY: number, haze: THREE.Color) {
  const W = 4096;
  const H = 256;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const rand = mulberry32(199);
  const base = H - 4;
  const tint = (hex: string, k: number) => '#' + new THREE.Color(hex).lerp(haze, k).getHexString();

  // Apeninos mais altos ao sul/oeste, vale plano do Pó ao norte/leste
  const ridge = (amp: number, seed: number, col: string, lift: number, southWeight: number) => {
    const ys: number[] = [];
    g.fillStyle = col;
    g.beginPath();
    g.moveTo(0, base);
    for (let x = 0; x <= W; x += 8) {
      const u = (x / W) * Math.PI * 2;
      const south = 0.5 + 0.5 * Math.cos(u - Math.PI * 0.1);
      const y =
        amp *
        (1.0 - southWeight + southWeight * south) *
        (0.55 + 0.25 * Math.sin(u * 3 + seed) + 0.14 * Math.sin(u * 7 + seed * 1.7) + 0.06 * Math.sin(u * 19 + seed * 3.1));
      ys.push(base - lift - y);
      g.lineTo(x, base - lift - y);
    }
    g.lineTo(W, base);
    g.closePath();
    g.fill();
    return ys;
  };

  ridge(140, 0.7, tint('#7b96a8', 0.45), 48, 0.78); // serras azuis ao fundo
  ridge(92, 2.2, tint('#6b8858', 0.30), 42, 0.72); // colinas médias arborizadas
  const near = ridge(56, 3.8, tint('#688a42', 0.16), 38, 0.65); // encostas verdes próximas

  // manchas escuras de ciprestes/pinheiros nas encostas próximas
  g.fillStyle = tint('#395628', 0.22);
  for (let k = 0; k < 1100; k++) {
    const x = rand() * W;
    const top = near[Math.min(near.length - 1, Math.floor(x / 8))];
    const y = top + 2 + rand() * (base - 38 - top);
    if (y > base - 40) continue;
    g.beginPath();
    g.ellipse(x, y, 2 + rand() * 3.5, 1.5 + rand() * 2.5, 0, 0, Math.PI * 2);
    g.fill();
  }
  g.fillStyle = tint('#5c7c3b', 0.18);
  g.fillRect(0, base - 40, W, 46);

  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.anisotropy = 4;
  const R = 3900;
  const height = 420;
  const geo = new THREE.CylinderGeometry(R, R, height, 128, 1, true);
  const mat = new THREE.MeshBasicMaterial({
    map: tex,
    transparent: true,
    side: THREE.BackSide,
    fog: false,
    depthWrite: false,
    alphaTest: 0.02,
  });
  const ring = new THREE.Mesh(geo, mat);
  ring.position.set(center.x, floorY - 40 + height / 2, center.z);
  ring.renderOrder = -2;
  ring.frustumCulled = false;
  group.add(ring);
}
