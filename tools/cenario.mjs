// Exporta o cenário da pista do jogo web para o Godot (ver tools/cenario/cenario.ts):
//   assets/track/cenario.glb       malhas e texturas da pista e dos arredores
//   data/track/arvores_pos.json    árvores: [x, y, z, tamanho, espécie, giro, tom] × n
// uso (de REPOS/gt3-godot/tools): node cenario.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';

const out = p => {
  const f = fileURLToPath(new URL(`../${p}`, import.meta.url));
  mkdirSync(fileURLToPath(new URL('.', new URL(`../${p}`, import.meta.url))), { recursive: true });
  return f;
};
const server = await createServer({ configFile: fileURLToPath(new URL('cenario/vite.config.ts', import.meta.url)), server: { port: 5199 } });
await server.listen();
const browser = await chromium.launch({ args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'] });
try {
  const page = await browser.newPage();
  page.on('console', m => console.log('  [página]', m.text()));
  page.on('pageerror', e => console.log('  [erro]', e.message));
  await page.goto('http://localhost:5199/', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => 'exportar' in window, null, { timeout: 120000 });
  const r = await page.evaluate(() => window.exportar());
  const glb = Buffer.from(r.glb, 'base64');
  writeFileSync(out('assets/track/cenario.glb'), glb);
  writeFileSync(out('data/track/arvores_pos.json'), JSON.stringify(r.trees));
  console.log(`cenario.glb ${(glb.length / 1e6).toFixed(1)} MB,`, JSON.stringify(r.stats));
  console.log('trechos:', r.sections.join(', '));
} finally {
  await browser.close();
  await server.close();
}
