// Exporta para o Godot uma pista com fonte própria em tools/tracks/<id>/ (Laguna Seca, Imola e, desde a Fase 2B,
// Interlagos). Fonte: <id>.json (TrackData do web + sections), <id>-terrain.json e <id>-osm.json, gerados pelos
// scripts da própria pasta (build_track.py, build_osm.py). Usa a mesma classe Track do web (zebras, muros e
// escapes automáticos), os ajustes de tools/tracks/fonte.ts e a mesma lógica de relevo do prep.ts.
//
//  <data_dir>/track.json    amostras a cada 2 m (stride 16) + sections (+ bank, se a fonte tiver)
//  <data_dir>/terrain.json  grade de relevo (LiDAR + altura da pista perto dela)
//  <data_dir>/osm.json      arredores do OpenStreetMap (só as ferramentas usam)
//
// <data_dir> = o `data_dir` da pista em data/tracks.json (Interlagos: data/track/; as outras: data/tracks/<id>/).
//
// uso (de REPOS/gt3-godot/tools): npx vite-node pista.ts -- laguna-seca
//                                 npx vite-node pista.ts -- interlagos --saida=../build/tmp/x   (outra pasta)
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { applyBank } from './tracks/bank';
import { fonte, montaPista } from './tracks/fonte';

const args = process.argv.slice(2).filter(a => a !== '--');
const id = args.find(a => !a.startsWith('--'));
if (!id) throw new Error('uso: npx vite-node pista.ts -- <id> [--saida=<pasta>]');
const ROOT = fileURLToPath(new URL('../', import.meta.url));
const tracks = JSON.parse(readFileSync(resolve(ROOT, 'data/tracks.json'), 'utf8')) as { id: string; data_dir: string }[];
const info = tracks.find(t => t.id === id);
const saida = args.find(a => a.startsWith('--saida='))?.slice(8);
const dir = saida ? resolve(process.cwd(), saida)
  : resolve(ROOT, (info?.data_dir ?? `res://data/tracks/${id}/`).replace('res://', ''));
mkdirSync(dir, { recursive: true });
const src = (f: string) => fonte(id, f);
const out = (f: string) => resolve(dir, f);
const json = (f: string, v: unknown) => writeFileSync(out(f), JSON.stringify(v));
const r2 = (x: number) => Math.round(x * 100) / 100;
const r4 = (x: number) => Math.round(x * 10000) / 10000;
const r6 = (x: number) => Math.round(x * 1e6) / 1e6;

// ---------- pista
const data = JSON.parse(readFileSync(src(`${id}.json`), 'utf8'));
// zebras e muros reais medidos, escape asfaltado limitado (`maxRunoff`) e mínimo (`runLeft/Right`), cordas
const track = montaPista(data);
const S = track.samples;

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
json('track.json', { n: S.length, step: 2, stride: 16, length: r2(track.length), s: flat, sections,
  ...(bank ? { bank: bank.map(r6) } : {}) });
let lo = Infinity, hi = 0;
for (let i = 0; i < S.length; i++) {
  const d = Math.hypot(S[(i + 1) % S.length].p.x - S[i].p.x, S[(i + 1) % S.length].p.z - S[i].p.z);
  lo = Math.min(lo, d); hi = Math.max(hi, d);
}
console.log(id, S.length, 'amostras,', Math.round(track.length), 'm,', sections.length, 'trechos; espaçamento em planta',
  lo.toFixed(3), '–', hi.toFixed(3), 'm →', dir);

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
json('terrain.json', { x0: minX, z0: minZ, cell: CELL, nx: tnx, nz: tnz, h: th });
console.log('relevo', tnx, 'x', tnz);

copyFileSync(src(`${id}-osm.json`), out('osm.json'));
console.log('osm ok');
