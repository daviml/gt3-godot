// Exporta os arredores distantes do jogo web para o Godot (etapa 9 do PLANO; ver tools/cenario/arredores.ts):
//   data/track/torres.json         anel de torres: [x, base, z, giro, largura, altura, profundidade, cor] × n
//   data/track/horizonte.json      cilindro do horizonte (centro, raio, altura, segmentos)
//   assets/track/horizonte.png     textura do horizonte (morros e cidade em camadas, já azulados)
// uso (de REPOS/gt3-godot/tools): node arredores.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';

const out = p => {
  const f = fileURLToPath(new URL(`../${p}`, import.meta.url));
  mkdirSync(fileURLToPath(new URL('.', new URL(`../${p}`, import.meta.url))), { recursive: true });
  return f;
};
const server = await createServer({ configFile: fileURLToPath(new URL('cenario/vite.config.ts', import.meta.url)), server: { port: 5198 } });
await server.listen();
const browser = await chromium.launch({ args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'] });
try {
  const page = await browser.newPage();
  page.on('console', m => console.log('  [página]', m.text()));
  page.on('pageerror', e => console.log('  [erro]', e.message));
  await page.goto('http://localhost:5198/arredores.html', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => 'exportar' in window, null, { timeout: 120000 });
  const r = await page.evaluate(() => window.exportar());
  if (!r.horizon) throw new Error('horizonte não encontrado');
  writeFileSync(out('data/track/torres.json'), JSON.stringify(r.towers));
  const { png, ...h } = r.horizon;
  writeFileSync(out('data/track/horizonte.json'), JSON.stringify(h));
  writeFileSync(out('assets/track/horizonte.png'), Buffer.from(png, 'base64'));
  console.log(`torres: ${r.towers.length / 8}, horizonte:`, JSON.stringify(h));
} finally {
  await browser.close();
  await server.close();
}
