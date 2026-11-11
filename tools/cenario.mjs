// Exporta o cenário da pista do jogo web para o Godot (ver tools/cenario/cenario.ts):
//   assets/track/cenario.glb       malhas e texturas da pista e dos arredores
//   data/track/arvores_pos.json    árvores: [x, y, z, tamanho, espécie, giro, tom] × n
// uso (de REPOS/gt3-godot/tools): node cenario.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';
import { NodeIO } from '@gltf-transform/core';
import { dedup, prune, weld } from '@gltf-transform/functions';

const out = p => {
  const f = fileURLToPath(new URL(`../${p}`, import.meta.url));
  mkdirSync(fileURLToPath(new URL('.', new URL(`../${p}`, import.meta.url))), { recursive: true });
  return f;
};
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
  await page.goto('http://localhost:5199/', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => 'exportar' in window, null, { timeout: 120000 });
  const r = await page.evaluate(() => window.exportar());
  const rawGlb = Buffer.from(r.glb, 'base64');
  const io = new NodeIO();
  const doc = await io.readBinary(new Uint8Array(rawGlb));
  await doc.transform(weld(), dedup(), prune());
  const glb = Buffer.from(await io.writeBinary(doc));
  writeFileSync(out('assets/track/cenario.glb'), glb);
  writeFileSync(out('data/track/arvores_pos.json'), JSON.stringify(r.trees));
  console.log(`cenario.glb ${(glb.length / 1e6).toFixed(1)} MB (antes ${(rawGlb.length / 1e6).toFixed(1)} MB),`, JSON.stringify(r.stats));
  console.log('trechos:', r.sections.join(', '));
} finally {
  await browser.close();
  await server.close();
}
