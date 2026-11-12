// Exporta do jogo web (REPOS/gt3-time-attack) tudo o que o Godot usa. O web continua sendo a fonte dos dados:
// mudou pista, física ou carro lá → rodar isto de novo.
//
//  data/track/track.json     amostras da pista a cada 2 m (classe Track do jogo) + nomes das curvas (seções)
//  data/track/terrain.json   grade de relevo (SRTM + altura da pista perto dela, igual ao trackView.ts)
//  data/track/osm.json       arredores do OpenStreetMap (prédios, arquibancadas, lago, mata...)
//  data/track/arvores.json   atlas das árvores impostoras (tamanhos por espécie)
//  data/reference/*.json     voltas de referência do iRacing reamostradas na pista
//  data/cars.json            lista dos carros na ordem do menu
//  data/cars/<id>.json       carro pronto: nome, cor, som, modelo (rodas, entre-eixos) e acerto FINAL da física
//                            (GT3 base + acerto por posição do motor + data/cars/<id>.json, igual ao carParams())
//  data/sounds.json          bancos de motor (arquivo + giro de cada gravação) e efeitos
//  assets/cars/<id>/<id>.glb os 13 GT3 sem meshopt/quantização e com texturas PNG (o Godot não lê essas extensões)
//  assets/textures, assets/sky, assets/trees, assets/sounds
//
// uso (de REPOS/gt3-godot/tools): npx vite-node prep.ts            tudo
//                                 npx vite-node prep.ts -- dados   só JSON (rápido, sem modelos/texturas/sons)
//                                 npx vite-node prep.ts -- carros  JSON + os 13 GLB (sem texturas da pista/sons)
import { readFileSync, writeFileSync, copyFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Track } from '../../gt3-time-attack/src/track/track';
import { CARS, carParams, modelMeta } from '../../gt3-time-attack/src/cars';
import { trackSections } from '../../gt3-time-attack/src/render/osmScenery';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, EXTMeshoptCompression, EXTTextureWebP, KHRMeshQuantization } from '@gltf-transform/extensions';
import { compressTexture, dedup, dequantize, listTextureSlots, prune, weld } from '@gltf-transform/functions';
import { MeshoptDecoder } from 'meshoptimizer';
import sharp from 'sharp';
import { fixNormals, splitWheels } from './car_fix';

const WEB = new URL('../../gt3-time-attack/', import.meta.url);
const OUT = new URL('../', import.meta.url);
const web = (p: string) => fileURLToPath(new URL(p, WEB));
const out = (p: string) => {
  const f = fileURLToPath(new URL(p, OUT));
  mkdirSync(fileURLToPath(new URL('.', new URL(p, OUT))), { recursive: true });
  return f;
};
const json = (p: string, v: unknown) => writeFileSync(out(p), JSON.stringify(v));
const r2 = (x: number) => Math.round(x * 100) / 100;
const r4 = (x: number) => Math.round(x * 10000) / 10000;
const r6 = (x: number) => Math.round(x * 1e6) / 1e6;
const onlyData = process.argv.includes('dados');
const onlyCars = process.argv.includes('carros'); // só os modelos (com as correções do car_fix.ts)

// ---------- pista
const data = JSON.parse(readFileSync(web('data/tracks/interlagos.json'), 'utf8'));
const track = new Track(data);
const osm = JSON.parse(readFileSync(web('data/tracks/interlagos-osm.json'), 'utf8'));
track.sections = trackSections(osm, track); // como no buildOsmScenery: nomes das curvas a partir do OSM
const S = track.samples;
const flat: number[] = [];
for (const s of S) {
  // posição em 0,1 mm: arredondar em cm deixava degraus de até 5 mm a cada 2 m, que faziam o carro quicar
  flat.push(r4(s.p.x), r4(s.p.y), r4(s.p.z), r6(s.t.x), r6(s.t.y), r6(s.t.z), r6(s.r.x), r6(s.r.z),
    r2(s.wl), r2(s.wr), r2(s.kerbL), r2(s.kerbR), r2(s.runL), r2(s.runR), r2(s.wallL), r2(s.wallR));
}
json('data/track/track.json', {
  n: S.length, step: 2, stride: 16, length: r2(track.length), s: flat,
  sections: track.sections.map(c => ({ name: c.name, s0: r2(c.s0), s1: r2(c.s1) }))
});
console.log('pista', S.length, 'amostras,', Math.round(track.length), 'm,', track.sections.length, 'curvas com nome');

// ---------- relevo (mesma lógica de buildTerrain/srtmGrid em src/render/trackView.ts)
const T = JSON.parse(readFileSync(web('data/tracks/interlagos-terrain.json'), 'utf8'));
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
  // dentro da área da pista (até o muro) o chão fica na altura dela; depois mistura com o relevo real
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
json('data/track/terrain.json', { x0: minX, z0: minZ, cell: CELL, nx: tnx, nz: tnz, h: th });
console.log('relevo', tnx, 'x', tnz);

// ---------- arredores, árvores e referências (cópia direta; o formato é documentado no web)
copyFileSync(web('data/tracks/interlagos-osm.json'), out('data/track/osm.json'));
copyFileSync(web('data/arvores.json'), out('data/track/arvores.json'));
const refs = readdirSync(web('data/reference')).filter(f => f.endsWith('.json'));
for (const f of refs) copyFileSync(web(`data/reference/${f}`), out(`data/reference/${f}`));
console.log('osm, árvores e', refs.length, 'referências:', refs.join(', '));

// ---------- carros: acerto final (o mesmo objeto que o web entrega à física) + modelo
const index: Record<string, unknown>[] = [];
for (const c of CARS) {
  const meta = modelMeta(c.id);
  if (!meta) throw new Error(`sem data/models/${c.id}.json`);
  const params = carParams(c, meta);
  const wheels = meta.wheels.map(({ tris: _t, ...w }: any) => w);
  json(`data/cars/${c.id}.json`, {
    id: c.id, name: c.name, short: c.short, layout: c.layout, color: c.color, sound: c.sound,
    model: { ...meta, wheels, glb: `res://assets/cars/${c.id}/${c.id}.glb` },
    params
  });
  index.push({
    id: c.id, name: c.name, short: c.short, layout: c.layout, color: c.color,
    brand: c.brand, engine: c.engine, power: c.power, weight: c.weight, gears: c.gears
  });
}
json('data/cars.json', index);
console.log('acertos de', CARS.length, 'carros');

// ---------- sons: bancos do engine-sim (o giro de cada gravação segue o sound.ts: arquivo i → i×1000 rpm,
// exceto a primeira do tsp, que é 1100)
const banks: Record<string, { file: string; rpm: number }[]> = {};
for (const b of readdirSync(web('public/sounds/engines'))) {
  const n = readdirSync(web(`public/sounds/engines/${b}`)).filter(f => /^\d+\.wav$/.test(f)).length;
  banks[b] = Array.from({ length: n }, (_, i) => ({
    file: `res://assets/sounds/engines/${b}/${i + 1}.wav`,
    rpm: b === 'tsp' && i === 0 ? 1100 : (i + 1) * 1000
  }));
}
const fx = Object.fromEntries(readdirSync(web('public/sounds/fx')).filter(f => f.endsWith('.wav'))
  .map(f => [f.replace('.wav', ''), `res://assets/sounds/fx/${f}`]));
json('data/sounds.json', { banks, fx });
console.log('sons:', Object.keys(banks).length, 'bancos de motor,', Object.keys(fx).length, 'efeitos');

if (onlyData) {
  console.log('modo dados: modelos, texturas e sons não copiados');
  process.exit(0);
}

if (!onlyCars) for (const b of Object.keys(banks)) for (const f of readdirSync(web(`public/sounds/engines/${b}`))) {
  if (f.endsWith('.wav')) copyFileSync(web(`public/sounds/engines/${b}/${f}`), out(`assets/sounds/engines/${b}/${f}`));
}
if (!onlyCars) for (const f of readdirSync(web('public/sounds/fx'))) if (f.endsWith('.wav')) copyFileSync(web(`public/sounds/fx/${f}`), out(`assets/sounds/fx/${f}`));
const creditos = web('public/sounds/CREDITOS.md');
if (existsSync(creditos)) copyFileSync(creditos, out('assets/sounds/CREDITOS.md'));

// ---------- modelos (GLB com meshopt + webp → GLB enxuto para o Godot)
await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
const DROP = [EXTMeshoptCompression.EXTENSION_NAME, EXTTextureWebP.EXTENSION_NAME, KHRMeshQuantization.EXTENSION_NAME];
const AUX_SLOTS = new Set(['normalTexture', 'metallicRoughnessTexture', 'occlusionTexture']);
for (const c of CARS) {
  const doc = await io.read(web(`public/models/${c.id}.glb`));
  await doc.transform(dequantize(), weld(), dedup(), prune());
  for (const tex of doc.getRoot().listTextures()) {
    const imgBuf = tex.getImage();
    if (!imgBuf) continue;
    const slots = listTextureSlots(doc, tex);
    const meta = await sharp(imgBuf).metadata();
    let needsAlpha = false;
    if (meta.hasAlpha) {
      const st = await sharp(imgBuf).stats();
      needsAlpha = (st.channels[3]?.min ?? 255) < 250;
    }
    const isAuxOnly = slots.length > 0 && slots.every(s => AUX_SLOTS.has(s));
    if (isAuxOnly) {
      await compressTexture(tex, { encoder: sharp, targetFormat: 'png', effort: 85, resize: [512, 512] });
      if (meta.hasAlpha && !needsAlpha && tex.getImage()) {
        tex.setImage(await sharp(tex.getImage()!).removeAlpha().png({ compressionLevel: 9, effort: 8 }).toBuffer());
      }
    } else if (!needsAlpha) {
      await compressTexture(tex, { encoder: sharp, targetFormat: 'jpeg', quality: 90, chromaSubsampling: '4:4:4', resize: [1024, 1024] });
    } else {
      await compressTexture(tex, { encoder: sharp, targetFormat: 'png', effort: 85, resize: [1024, 1024] });
    }
  }
  for (const ext of doc.getRoot().listExtensionsUsed()) if (DROP.includes(ext.extensionName)) ext.dispose();
  // correções da etapa 6 (car_fix.ts): normais invertidas e pinça separada da roda
  const flipped = fixNormals(doc);
  const wheels = splitWheels(doc, modelMeta(c.id)!.wheels.map(w => w.r));
  await doc.transform(prune());
  await io.write(out(`assets/cars/${c.id}/${c.id}.glb`), doc);
  console.log('  carro', c.id, flipped.length ? `normais invertidas: ${flipped.join(', ')}` : '');
  for (const w of wheels) console.log('    ', w);
}
copyFileSync(web('data/models/creditos.json'), out('assets/cars/creditos.json'));
if (onlyCars) process.exit(0);

// ---------- texturas, céu e árvores
for (const n of ['asphalt_track', 'concrete_wall_008', 'leafy_grass', 'sparse_grass']) {
  for (const k of ['diff', 'nor_gl', 'arm']) {
    await sharp(web(`public/extremo/textures/${n}_${k}_2k.webp`)).png().toFile(out(`assets/textures/${n}_${k}.png`));
  }
}
copyFileSync(web('public/hdri/ceu_2k.hdr'), out('assets/sky/ceu_2k.hdr'));
for (const n of ['arvores_cor', 'arvores_normal']) await sharp(web(`public/extremo/trees/${n}.webp`)).png().toFile(out(`assets/trees/${n}.png`));
console.log('texturas, céu e árvores ok');
