// Impressão digital do cenario.glb (migração do perfil lateral, PLANO-INTERLAGOS-DETALHES.md Fase 2):
// por malha (nó), nome, material, nº de vértices/índices e hash dos atributos arredondados a 1e-4.
//
// uso (de REPOS/gt3-godot/tools):
//   node cenario/interlagos/impressao.mjs <cenario.glb> [--salvar=<saida.json>]
//   node cenario/interlagos/impressao.mjs <a.glb> --comparar=<b.glb | impressao.json>
// No modo --comparar com dois GLB, as malhas com hash diferente também mostram a maior diferença absoluta
// por atributo (para separar ruído de arredondamento de mudança real).
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname } from 'node:path';
import { NodeIO } from '@gltf-transform/core';

const args = process.argv.slice(2);
const arquivo = args.find(a => !a.startsWith('--'));
const salvar = args.find(a => a.startsWith('--salvar='))?.slice(9);
const comparar = args.find(a => a.startsWith('--comparar='))?.slice(11);
if (!arquivo) {
  console.log('uso: node impressao.mjs <cenario.glb> [--salvar=<json>] [--comparar=<glb|json>]');
  process.exit(1);
}

const io = new NodeIO();

async function ler(glb) {
  const bytes = readFileSync(glb);
  const doc = await io.readBinary(new Uint8Array(bytes));
  const root = doc.getRoot();
  const malhas = [];
  const brutos = [];
  root.listNodes().forEach((no, k) => {
    const mesh = no.getMesh();
    if (!mesh) return;
    mesh.listPrimitives().forEach((p, j) => {
      const h = createHash('sha1');
      const attrs = {};
      const raw = {};
      for (const sem of p.listSemantics().sort()) {
        const a = p.getAttribute(sem);
        const arr = a.getArray();
        const r = new Int32Array(arr.length);
        for (let i = 0; i < arr.length; i++) r[i] = Math.round(arr[i] * 1e4);
        h.update(sem).update(Buffer.from(r.buffer));
        attrs[sem] = a.getCount();
        raw[sem] = arr;
      }
      const idx = p.getIndices();
      if (idx) h.update('idx').update(Buffer.from(new Uint32Array(idx.getArray()).buffer));
      const t = no.getTranslation();
      const q = no.getRotation();
      const s = no.getScale();
      h.update('trs').update(Buffer.from(new Int32Array([...t, ...q, ...s].map(v => Math.round(v * 1e4))).buffer));
      malhas.push({
        no: k,
        nome: no.getName(),
        prim: j,
        material: p.getMaterial()?.getName() ?? null,
        vertices: p.getAttribute('POSITION')?.getCount() ?? 0,
        indices: idx ? idx.getCount() : 0,
        attrs,
        hash: h.digest('hex').slice(0, 16)
      });
      brutos.push({ raw, idx: idx?.getArray() });
    });
  });
  return { arquivo: glb, bytes: bytes.length, sha1: createHash('sha1').update(bytes).digest('hex'), malhas, brutos };
}

const semBrutos = r => ({ arquivo: r.arquivo, bytes: r.bytes, sha1: r.sha1, n: r.malhas.length, malhas: r.malhas });

const a = await ler(arquivo);
console.log(`${arquivo}: ${a.malhas.length} malhas, ${(a.bytes / 1e6).toFixed(2)} MB, sha1 ${a.sha1}`);
if (salvar) {
  mkdirSync(dirname(salvar), { recursive: true });
  writeFileSync(salvar, JSON.stringify(semBrutos(a), null, 1));
  console.log('impressão salva em', salvar);
}
if (comparar) {
  const b = comparar.endsWith('.json') ? JSON.parse(readFileSync(comparar, 'utf8')) : await ler(comparar);
  console.log(`comparando com ${comparar}: ${b.malhas.length} malhas, sha1 ${b.sha1}`);
  console.log(b.sha1 === a.sha1 ? 'GLB idêntico byte a byte' : 'GLB difere nos bytes');
  const n = Math.max(a.malhas.length, b.malhas.length);
  let iguais = 0;
  const difs = [];
  for (let i = 0; i < n; i++) {
    const x = a.malhas[i];
    const y = b.malhas[i];
    if (x && y && x.hash === y.hash && x.material === y.material && x.nome === y.nome) {
      iguais++;
      continue;
    }
    const d = { i, a: x && `${x.nome} ${x.material} v${x.vertices} i${x.indices}`, b: y && `${y.nome} ${y.material} v${y.vertices} i${y.indices}` };
    if (x && y && b.brutos && x.vertices === y.vertices) {
      const ra = a.brutos[i].raw;
      const rb = b.brutos[i].raw;
      d.maxDif = {};
      for (const k of Object.keys(ra)) {
        if (!rb[k]) continue;
        let m = 0;
        for (let e = 0; e < ra[k].length; e++) m = Math.max(m, Math.abs(ra[k][e] - rb[k][e]));
        d.maxDif[k] = m;
      }
    }
    difs.push(d);
  }
  console.log(`malhas: ${n}, idênticas: ${iguais}, diferentes: ${difs.length}`);
  for (const d of difs.slice(0, 50)) console.log(' ', JSON.stringify(d));
  process.exitCode = difs.length || a.malhas.length !== b.malhas.length ? 1 : 0;
}
