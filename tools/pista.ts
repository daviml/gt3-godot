// Exporta para o Godot uma pista que NÃO vem do jogo web (Interlagos continua no prep.ts, sem mudança).
// Fonte: tools/tracks/<id>/<id>.json (TrackData do web + sections), <id>-terrain.json e <id>-osm.json, gerados
// pelos scripts da própria pasta (build_track.py, build_osm.py). Usa a mesma classe Track do web (zebras, muros e
// escapes automáticos) e a mesma lógica de relevo do prep.ts.
//
//  data/tracks/<id>/track.json    amostras a cada 2 m (stride 16) + sections
//  data/tracks/<id>/terrain.json  grade de relevo (LiDAR + altura da pista perto dela)
//  data/tracks/<id>/osm.json      arredores do OpenStreetMap (só as ferramentas usam)
//
// uso (de REPOS/gt3-godot/tools): npx vite-node pista.ts -- laguna-seca
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Track } from '../../gt3-time-attack/src/track/track';
import { applyBank, clampRunoff } from './tracks/bank';

const id = process.argv.slice(2).filter(a => a !== '--')[0];
if (!id || id === 'interlagos') throw new Error('uso: npx vite-node pista.ts -- <id>  (Interlagos é pelo prep.ts)');
const OUT = new URL('../', import.meta.url);
const src = (f: string) => fileURLToPath(new URL(`tracks/${id}/${f}`, import.meta.url));
const out = (p: string) => {
  const f = fileURLToPath(new URL(p, OUT));
  mkdirSync(fileURLToPath(new URL('.', new URL(p, OUT))), { recursive: true });
  return f;
};
const json = (p: string, v: unknown) => writeFileSync(out(p), JSON.stringify(v));
const r2 = (x: number) => Math.round(x * 100) / 100;
const r4 = (x: number) => Math.round(x * 10000) / 10000;
const r6 = (x: number) => Math.round(x * 1e6) / 1e6;
const dir = `data/tracks/${id}/`;

// ---------- pista
const data = JSON.parse(readFileSync(src(`${id}.json`), 'utf8'));
const track = new Track(data);
const S = track.samples;
// escape asfaltado limitado (opcional, `maxRunoff` na fonte): igual no cenário (tools/cenario/cenario.ts)
clampRunoff(track, data.maxRunoff);

// trechos com nome: s da fonte (linha de 1 m) → s desta pista (Catmull-Rom a cada 2 m), na proporção do comprimento
const k = track.length / (data.points.length * 4);
const sections = (data.sections ?? []).map((c: { name: string; s0: number; s1: number }) => ({ name: c.name, s0: r2(c.s0 * k), s1: r2(c.s1 * k) }));
// a que passa pela linha de chegada fica por último (section_at pega a última que começou antes de s)
sections.sort((a: { s0: number; s1: number }, b: { s0: number; s1: number }) => (a.s1 < a.s0 ? 1e9 : a.s0) - (b.s1 < b.s0 ? 1e9 : b.s0));
const flat: number[] = [];
for (const s of S) {
  flat.push(r4(s.p.x), r4(s.p.y), r4(s.p.z), r6(s.t.x), r6(s.t.y), r6(s.t.z), r6(s.r.x), r6(s.r.z),
    r2(s.wl), r2(s.wr), r2(s.kerbL), r2(s.kerbR), r2(s.runL), r2(s.runR), r2(s.wallL), r2(s.wallR));
}
// camber (opcional): grava r/n horizontais (acima) e o ângulo; o Godot gira igual ao applyBank
const bank = applyBank(track, data.bank);
json(dir + 'track.json', { n: S.length, step: 2, stride: 16, length: r2(track.length), s: flat, sections,
  ...(bank ? { bank: bank.map(r6) } : {}) });
console.log(id, S.length, 'amostras,', Math.round(track.length), 'm,', sections.length, 'trechos');

// ---------- relevo (igual ao prep.ts: grade suavizada, alinhada pela mediana; perto da pista, a altura dela)
const T = JSON.parse(readFileSync(src(`${id}-terrain.json`), 'utf8'));
const { x0, z0, step, nx, nz } = T;
const at = (i: number, j: number) => T.h[Math.max(0, Math.min(nz - 1, j)) * nx + Math.max(0, Math.min(nx - 1, i))];
const sm = new Float32Array(nx * nz);
for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
  let a = 0;
  for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) a += at(i + di, j + dj) * (di || dj ? 1 : 2);
  sm[j * nx + i] = a / 10;
}
const raw = (x: number, z: number) => {
  const fx = Math.max(0, Math.min(nx - 1.001, (x - x0) / step));
  const fz = Math.max(0, Math.min(nz - 1.001, (z - z0) / step));
  const i = Math.floor(fx), j = Math.floor(fz), u = fx - i, v = fz - j;
  const g = (a: number, b: number) => sm[b * nx + a];
  return (g(i, j) * (1 - u) + g(i + 1, j) * u) * (1 - v) + (g(i, j + 1) * (1 - u) + g(i + 1, j + 1) * u) * v;
};
const diffs = S.filter((_, k) => k % 5 === 0).map(s => raw(s.p.x, s.p.z) - s.p.y).sort((a, b) => a - b);
const offset = diffs[Math.floor(diffs.length / 2)];
console.log('relevo: LiDAR − pista, mediana', offset.toFixed(2), 'm; p10/p90',
  (diffs[Math.floor(diffs.length * 0.1)] - offset).toFixed(2), (diffs[Math.floor(diffs.length * 0.9)] - offset).toFixed(2));
let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
for (const s of S) { minX = Math.min(minX, s.p.x); maxX = Math.max(maxX, s.p.x); minZ = Math.min(minZ, s.p.z); maxZ = Math.max(maxZ, s.p.z); }
const PAD = 700, CELL = 8;
minX -= PAD; minZ -= PAD; maxX += PAD; maxZ += PAD;
const coarse = 40;
const buckets = new Map<string, number[]>();
S.forEach((s, i) => {
  const k = `${Math.floor(s.p.x / coarse)},${Math.floor(s.p.z / coarse)}`;
  if (!buckets.has(k)) buckets.set(k, []);
  buckets.get(k)!.push(i);
});
const heightAt = (x: number, z: number) => {
  const cx = Math.floor(x / coarse), cz = Math.floor(z / coarse);
  let best = Infinity, h = 0, bi = -1;
  for (let i = -4; i <= 4; i++) for (let j = -4; j <= 4; j++) for (const k of buckets.get(`${cx + i},${cz + j}`) ?? []) {
    const p = S[k].p;
    const d2 = (p.x - x) ** 2 + (p.z - z) ** 2;
    if (d2 < best) { best = d2; h = p.y; bi = k; }
  }
  const g = raw(x, z) - offset;
  if (best === Infinity) return g - 0.6;
  const s = S[bi];
  const lat = (x - s.p.x) * s.r.x + (z - s.p.z) * s.r.z;
  const wall = lat < 0 ? s.wallL : s.wallR;
  const d = Math.max(0, Math.abs(lat) - wall);
  const far = Math.max(0, Math.min(1, (d - 10) / 90));
  return h * (1 - far) + g * far - 0.35 - Math.min(1.5, d * 0.01);
};
const tnx = Math.ceil((maxX - minX) / CELL) + 1, tnz = Math.ceil((maxZ - minZ) / CELL) + 1;
const th: number[] = [];
for (let j = 0; j < tnz; j++) for (let i = 0; i < tnx; i++) th.push(r2(heightAt(minX + i * CELL, minZ + j * CELL)));
json(dir + 'terrain.json', { x0: minX, z0: minZ, cell: CELL, nx: tnx, nz: tnz, h: th });
console.log('relevo', tnx, 'x', tnz);

copyFileSync(src(`${id}-osm.json`), out(dir + 'osm.json'));
console.log('osm ok');
