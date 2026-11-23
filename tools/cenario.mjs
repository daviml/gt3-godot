// Exporta o cenário da pista do jogo web para o Godot (ver tools/cenario/cenario.ts):
//   assets/track/cenario.glb       malhas e texturas da pista e dos arredores
//   data/track/arvores_pos.json    árvores: [x, y, z, tamanho, espécie, giro, tom] × n
// uso (de REPOS/gt3-godot/tools): node cenario.mjs [--track=<id>]   (sem --track: Interlagos)
//   --out=<pasta>       grava lá em vez do projeto
//   --preview           só PNGs de conferência (build/compare/<pista>/preview)
//   --extrair-perfil    obsoleto desde a Fase 2B etapa F (o perfil é da pista nova: interlagos/migrarPerfil2B.ts)
// Antes de gravar, confere que a pista do gerador é a do <data>/track.json da física (n, posição ≤ 1 cm, larguras,
// zebras, escapes e muros); Interlagos usa a fonte própria tools/tracks/interlagos/ desde a etapa F.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';
import { NodeIO } from '@gltf-transform/core';
import { dedup, prune, weld } from '@gltf-transform/functions';

// --out=<pasta>: grava lá em vez do projeto (conferência, sem sobrescrever o que existe)
const outRoot = process.argv.find(a => a.startsWith('--out='))?.slice(6);
const out = p => {
  const f = outRoot ? `${outRoot}/${p}` : fileURLToPath(new URL(`../${p}`, import.meta.url));
  mkdirSync(dirname(f), { recursive: true });
  return f;
};
// --track=<id>: outra pista (módulos e dados trocados no vite.config.ts); sem ela, Interlagos nos caminhos de sempre
const trackArg = process.argv.find(a => a.startsWith('--track='))?.slice(8) ?? 'interlagos';
const other = trackArg !== 'interlagos';
const dataDir = other ? `data/tracks/${trackArg}/` : 'data/track/';
const assetDir = other ? `assets/tracks/${trackArg}/` : 'assets/track/';
process.env.TRACK = trackArg;

/**
 * O cenário tem de ser montado na MESMA pista da física: as amostras do Track do gerador (antes do perfil visual)
 * contra o <dataDir>/track.json do jogo — mesmo n, posição a ≤ 1 cm, larguras, zebras, escapes e muros a ≤ 1 cm.
 * Divergência = erro (o GLB não é gravado).
 */
function conferePista(r) {
  const t = JSON.parse(readFileSync(fileURLToPath(new URL(`../${dataDir}track.json`, import.meta.url)), 'utf8'));
  const A = r.amostras;
  if (A.length !== t.n) throw new Error(`pista do gerador com ${A.length} amostras, ${dataDir}track.json com ${t.n}`);
  const st = t.stride;
  // track.json: x y z tx ty tz rx rz wl wr kerbL kerbR runL runR wallL wallR (r antes do camber)
  const campos = { wl: [6, 8], wr: [7, 9], kerbL: [8, 10], kerbR: [9, 11], runL: [10, 12], runR: [11, 13], wallL: [12, 14], wallR: [13, 15] };
  let pos = 0, onde = 0;
  const maxc = Object.fromEntries(Object.keys(campos).map(k => [k, 0]));
  for (let i = 0; i < A.length; i++) {
    const a = A[i], b = t.s.slice(i * st, i * st + st);
    const d = Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    if (d > pos) { pos = d; onde = i; }
    for (const [k, [ia, ib]] of Object.entries(campos)) maxc[k] = Math.max(maxc[k], Math.abs(a[ia] - b[ib]));
  }
  const fmt = Object.entries(maxc).map(([k, v]) => `${k} ${v.toFixed(3)}`).join(', ');
  console.log(`pista do gerador × ${dataDir}track.json: n ${A.length}, comprimento ${r.length} × ${t.length} m, posição máx ${(pos * 100).toFixed(2)} cm (amostra ${onde}); máx |Δ| (m): ${fmt}`);
  // track.json grava posição com 4 casas e o resto com 2 (arredondamento: ≤ 0,005 m)
  if (pos > 0.01 || Object.values(maxc).some(v => v > 0.0101) || Math.abs(r.length - t.length) > 0.01)
    throw new Error('o cenário não está na mesma pista da física (rode tools/pista.ts ou confira tools/tracks/montaPista.ts)');
}
const server = await createServer({ configFile: fileURLToPath(new URL('cenario/vite.config.ts', import.meta.url)), server: { port: 5199 } });
await server.listen();
let browser;
const launchArgs = ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'];
for (const opts of [{}, { channel: 'chrome' }, { channel: 'msedge' }]) {
  try {
    browser = await chromium.launch({ args: launchArgs, ...opts });
    break;
  } catch {}
}
if (!browser) browser = await chromium.launch({ args: launchArgs });
try {
  const page = await browser.newPage();
  page.on('console', m => console.log('  [página]', m.text()));
  page.on('pageerror', e => console.log('  [erro]', e.message));
  const isPreview = process.argv.includes('--preview');
  // --extrair-perfil: refaz data/track/visual_profile.json (Interlagos) a partir do código antigo do gerador
  // (tools/cenario/interlagos/extrairPerfil.ts) e confere amostra por amostra; não exporta o GLB
  const isPerfil = process.argv.includes('--extrair-perfil');
  if (isPerfil && other) throw new Error('--extrair-perfil só existe para Interlagos');
  // Fase 2B etapa F: o perfil passou para a pista nova (migrarPerfil2B.ts); o extrator reconstruía a v1 da pista
  // antiga do web e apagaria tudo (edições da Fase 2 e a migração)
  if (isPerfil) throw new Error('--extrair-perfil está obsoleto desde a Fase 2B (etapa F): o perfil é da pista nova; ver tools/cenario/interlagos/migrarPerfil2B.ts');
  await page.goto(isPerfil ? 'http://localhost:5199/perfil.html' : 'http://localhost:5199/', { waitUntil: 'domcontentloaded' });
  if (isPerfil) {
    await page.waitForFunction(() => 'extrairPerfil' in window, null, { timeout: 120000 });
    const r = await page.evaluate(() => window.extrairPerfil());
    const f = out(dataDir + 'visual_profile.json');
    writeFileSync(f, r.texto);
    console.log(`visual_profile.json: ${(r.texto.length / 1024).toFixed(1)} KB, fatias esq ${r.fatias.esq} / dir ${r.fatias.dir} → ${f}`);
    console.log('conferência (perfil × código antigo, por amostra):', JSON.stringify(r.conferencia));
  } else if (isPreview) {
    await page.waitForFunction(() => 'preview' in window, null, { timeout: 120000 });
    const shots = await page.evaluate(() => window.preview());
    const prevDir = out(`build/compare/${trackArg}/preview`);
    mkdirSync(prevDir, { recursive: true });
    for (const s of shots) writeFileSync(`${prevDir}/${s.name}.png`, Buffer.from(s.b64, 'base64'));
    console.log(`preview ${trackArg}: ${shots.length} PNGs em ${prevDir}`);
  } else {
    await page.waitForFunction(() => 'exportar' in window, null, { timeout: 120000 });
    const r = await page.evaluate(() => window.exportar());
    conferePista(r);
    const rawGlb = Buffer.from(r.glb, 'base64');
    const io = new NodeIO();
    const doc = await io.readBinary(new Uint8Array(rawGlb));
    await doc.transform(weld(), dedup(), prune());
    const glb = Buffer.from(await io.writeBinary(doc));
    writeFileSync(out(assetDir + 'cenario.glb'), glb);
    writeFileSync(out(dataDir + 'arvores_pos.json'), JSON.stringify(r.trees));
    writeFileSync(out(dataDir + 'props.json'), JSON.stringify(r.props ?? []));
    console.log(`cenario.glb ${(glb.length / 1e6).toFixed(1)} MB (antes ${(rawGlb.length / 1e6).toFixed(1)} MB), props: ${(r.props ?? []).length},`, JSON.stringify(r.stats));
    console.log('trechos:', r.sections.join(', '));
  }
} finally {
  await browser.close();
  await server.close();
}
