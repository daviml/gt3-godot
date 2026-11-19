// Exporta os Hero Props de Imola para assets/props/imola/*.glb e otimiza via gltf-transform.
// uso (de REPOS/gt3-godot/tools): node props_imola.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';
import { chromium } from 'playwright-core';
import { NodeIO } from '@gltf-transform/core';
import { dedup, prune, weld } from '@gltf-transform/functions';

const root = dirname(fileURLToPath(import.meta.url));
const outDir = `${root}/../assets/props/imola`;
mkdirSync(outDir, { recursive: true });

const server = await createServer({ root: `${root}/cenario`, server: { port: 5198 } });
await server.listen();
const browser = await chromium.launch({
  channel: 'msedge',
  headless: true,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-webgl'],
});

try {
  const page = await browser.newPage();
  await page.goto('http://localhost:5198/props.html', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => 'exportProps' in window, null, { timeout: 60000 });
  const props = await page.evaluate(() => window.exportProps());
  const io = new NodeIO();
  for (const [id, data] of Object.entries(props)) {
    const raw = Buffer.from(data.b64, 'base64');
    const doc = await io.readBinary(new Uint8Array(raw));
    await doc.transform(weld(), dedup(), prune());
    const bin = Buffer.from(await io.writeBinary(doc));
    const dest = `${outDir}/${id}.glb`;
    writeFileSync(dest, bin);
    console.log(`${id}.glb: ${(bin.length / 1024).toFixed(1)} KB, ${data.tris} tris`);
  }
} finally {
  await browser.close();
  await server.close();
}
