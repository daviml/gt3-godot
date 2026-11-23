// Exporta do jogo web (REPOS/gt3-time-attack) tudo o que o Godot usa. O web continua sendo a fonte dos dados:
// mudou pista, física ou carro lá → rodar isto de novo.
//
//  data/track/arvores.json   atlas das árvores impostoras (tamanhos por espécie)
//  (pista, relevo, OSM e referências de Interlagos saem de tools/tracks/interlagos/ pelo tools/pista.ts e
//   tools/referencia.ts desde a Fase 2B; antes saíam daqui, do web)
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
import { writeFileSync, copyFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { CARS, carParams, modelMeta } from '../../gt3-time-attack/src/cars';
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
const onlyData = process.argv.includes('dados');
const onlyCars = process.argv.includes('carros'); // só os modelos (com as correções do car_fix.ts)

// ---------- pista de Interlagos: NÃO sai mais daqui (Fase 2B do PLANO-INTERLAGOS-DETALHES.md). A fonte é
// tools/tracks/interlagos/ (build_track.py) e o export é o tools/pista.ts -- interlagos (track.json, terrain.json,
// osm.json em data/track/); as referências do Garage 61 são as do tools/referencia.ts. As do web
// (data/reference/interlagos-*.json) são da pista antiga do web e não são mais copiadas.
// Daqui só sai o atlas das árvores (tamanhos por espécie), que não depende da geometria.
copyFileSync(web('data/arvores.json'), out('data/track/arvores.json'));
console.log('árvores ok (pista, relevo, osm e referências de Interlagos: tools/pista.ts e tools/referencia.ts)');

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
