// Exporta os arredores distantes do jogo web para o Godot (etapa 9 do PLANO; ver tools/cenario/arredores.ts):
//   data/track/torres.json         anel de torres: [x, base, z, giro, largura, altura, profundidade, cor] × n
//   data/track/horizonte.json      cilindro do horizonte (centro, raio, altura, segmentos)
//   assets/track/horizonte.png     textura do horizonte (morros e cidade em camadas, já azulados)
// uso (de REPOS/gt3-godot/tools): node arredores.mjs [--track=<id>]   (sem --track: Interlagos)
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';

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
const server = await createServer({ configFile: fileURLToPath(new URL('cenario/vite.config.ts', import.meta.url)), server: { port: 5198 } });
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
  await page.goto('http://localhost:5198/arredores.html', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => 'exportar' in window, null, { timeout: 120000 });
  const r = await page.evaluate(() => window.exportar());
  if (!r.horizon) throw new Error('horizonte não encontrado');
  writeFileSync(out(dataDir + 'torres.json'), JSON.stringify(r.towers));
  const { png, ...h } = r.horizon;
  writeFileSync(out(dataDir + 'horizonte.json'), JSON.stringify(h));
  writeFileSync(out(assetDir + 'horizonte.png'), Buffer.from(png, 'base64'));
  console.log(`torres: ${r.towers.length / 8}, horizonte:`, JSON.stringify(h));
} finally {
  await browser.close();
  await server.close();
}
