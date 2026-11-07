// Correções dos modelos GT3 feitas na exportação (prep.ts), para o Godot só carregar pronto:
//  - fixNormals: igual ao fixNormals() do carView.ts do web — malhas com as normais para dentro (Mustang, M6)
//    têm as normais invertidas;
//  - splitWheels: a roda exportada pelo build-cars.mjs do web vem com pinça e suporte grudados (tudo o que
//    cabe no raio do pneu). Separa, por peça conectada, o que não dá a volta no eixo (pinça, suporte) num nó
//    caliper_XX que esterça e acompanha a suspensão mas não gira; e copia o que gira por dentro do pneu
//    (aro, disco) num nó blur_XX, filho da roda, que o Godot usa para o desfoque da roda girando.
import type { Document, Primitive } from '@gltf-transform/core';

const WHEELS = ['FL', 'FR', 'RL', 'RR'];

function indicesOf(p: Primitive): ArrayLike<number> {
  const idx = p.getIndices();
  if (idx) return idx.getArray()!;
  const n = p.getAttribute('POSITION')!.getCount();
  return Uint32Array.from({ length: n }, (_, i) => i);
}

/** Inverte as normais das primitivas em que a normal guardada discorda da ordem dos vértices (glTF: anti-horário). */
export function fixNormals(doc: Document): string[] {
  const flipped: string[] = [];
  const done = new Set<Primitive>();
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const p of mesh.listPrimitives()) {
      if (done.has(p)) continue;
      done.add(p);
      const pos = p.getAttribute('POSITION'), nor = p.getAttribute('NORMAL');
      if (!pos || !nor || p.getMode() !== 4) continue;
      const idx = indicesOf(p);
      const P = pos.getArray()!, N = nor.getArray()!;
      let agree = 0, total = 0;
      for (let t = 0; t + 2 < idx.length; t += 3) {
        const a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
        const abx = P[b] - P[a], aby = P[b + 1] - P[a + 1], abz = P[b + 2] - P[a + 2];
        const acx = P[c] - P[a], acy = P[c + 1] - P[a + 1], acz = P[c + 2] - P[a + 2];
        // normal da face (comprimento = 2 × área: pondera por área) · soma das normais dos vértices
        const fx = aby * acz - abz * acy, fy = abz * acx - abx * acz, fz = abx * acy - aby * acx;
        const d = fx * (N[a] + N[b] + N[c]) + fy * (N[a + 1] + N[b + 1] + N[c + 1]) + fz * (N[a + 2] + N[b + 2] + N[c + 2]);
        agree += d;
        total += Math.abs(d);
      }
      if (total > 0 && agree / total < -0.3) {
        const n2 = nor.clone(); // o accessor pode ser compartilhado com outra primitiva
        const arr = n2.getArray()!;
        for (let i = 0; i < arr.length; i++) arr[i] = -arr[i];
        p.setAttribute('NORMAL', n2);
        flipped.push(`${mesh.getName()}/${p.getMaterial()?.getName() ?? '?'}`);
      }
    }
  }
  return flipped;
}

/** Separa pinça/suporte (não giram) e o miolo da roda (para o desfoque). Devolve um resumo por roda. */
export function splitWheels(doc: Document, radius: number[]): string[] {
  const root = doc.getRoot();
  const buffer = root.listBuffers()[0];
  const report: string[] = [];
  WHEELS.forEach((suf, wi) => {
    const node = root.listNodes().find(n => n.getName() === `wheel_${suf}`);
    const mesh = node?.getMesh();
    if (!node || !mesh) return;
    const R = radius[wi];
    const s = node.getScale();
    const spin = doc.createMesh(`wheel_${suf}`), still = doc.createMesh(`caliper_${suf}`), blur = doc.createMesh(`blur_${suf}`);
    const stillMats: string[] = [];
    let stillTris = 0, spinTris = 0;
    for (const p of mesh.listPrimitives()) {
      const P = p.getAttribute('POSITION')!.getArray()!;
      const idx = indicesOf(p);
      const nv = P.length / 3;
      // solda vértices na mesma posição (costuras de UV) e junta peças conectadas (union-find)
      const weld = new Int32Array(nv);
      const key = new Map<string, number>();
      for (let i = 0; i < nv; i++) {
        const k = `${Math.round(P[3 * i] * s[0] * 2000)},${Math.round(P[3 * i + 1] * s[1] * 2000)},${Math.round(P[3 * i + 2] * s[2] * 2000)}`;
        let w = key.get(k);
        if (w === undefined) key.set(k, (w = i));
        weld[i] = w;
      }
      const parent = Int32Array.from({ length: nv }, (_, i) => i);
      const find = (x: number): number => {
        while (parent[x] !== x) x = parent[x] = parent[parent[x]];
        return x;
      };
      const union = (a: number, b: number) => {
        a = find(a);
        b = find(b);
        if (a !== b) parent[a] = b;
      };
      for (let t = 0; t + 2 < idx.length; t += 3) {
        union(weld[idx[t]], weld[idx[t + 1]]);
        union(weld[idx[t]], weld[idx[t + 2]]);
      }
      // por peça: setores de 10° ocupados em volta do eixo (X), raio mínimo/máximo e tamanho
      type C = { bins: Set<number>; rmin: number; rmax: number; lo: number[]; hi: number[] };
      const comps = new Map<number, C>();
      const r = new Float32Array(nv);
      for (let i = 0; i < nv; i++) {
        const x = P[3 * i] * s[0], y = P[3 * i + 1] * s[1], z = P[3 * i + 2] * s[2];
        r[i] = Math.hypot(y, z);
        const c0 = find(weld[i]);
        let c = comps.get(c0);
        if (!c) comps.set(c0, (c = { bins: new Set(), rmin: Infinity, rmax: 0, lo: [x, y, z], hi: [x, y, z] }));
        if (r[i] > 0.02) c.bins.add(Math.floor(((Math.atan2(z, y) + Math.PI) / (2 * Math.PI)) * 36) % 36);
        c.rmin = Math.min(c.rmin, r[i]);
        c.rmax = Math.max(c.rmax, r[i]);
        [x, y, z].forEach((v, k) => {
          c!.lo[k] = Math.min(c!.lo[k], v);
          c!.hi[k] = Math.max(c!.hi[k], v);
        });
      }
      const isStill = new Map<number, boolean>();
      for (const [k, c] of comps) {
        const size = Math.hypot(c.hi[0] - c.lo[0], c.hi[1] - c.lo[1], c.hi[2] - c.lo[2]);
        // pinça: arco parcial (≤ metade da volta), longe do cubo, grande (porca e válvula são pequenas)
        isStill.set(k, c.bins.size <= 18 && c.rmin > 0.3 * R && c.rmax < 0.97 * R && size > 0.12);
      }
      const a: number[] = [], b: number[] = [], m: number[] = [];
      for (let t = 0; t + 2 < idx.length; t += 3) {
        const tri = [idx[t], idx[t + 1], idx[t + 2]];
        if (isStill.get(find(weld[tri[0]]))) a.push(...tri);
        else {
          b.push(...tri);
          if (tri.every(v => r[v] < 0.8 * R)) m.push(...tri);
        }
      }
      const add = (dst: typeof spin, tris: number[]) => {
        if (!tris.length) return;
        const acc = doc.createAccessor().setType('SCALAR').setArray(Uint32Array.from(tris)).setBuffer(buffer);
        const q = doc.createPrimitive().setIndices(acc).setMaterial(p.getMaterial());
        for (const sem of p.listSemantics()) q.setAttribute(sem, p.getAttribute(sem));
        dst.addPrimitive(q);
      };
      add(spin, b);
      add(still, a);
      add(blur, m);
      if (a.length) stillMats.push(`${p.getMaterial()?.getName()}(${a.length / 3})`);
      stillTris += a.length / 3;
      spinTris += b.length / 3;
    }
    node.setMesh(spin);
    mesh.dispose();
    if (still.listPrimitives().length) {
      const n = doc.createNode(`caliper_${suf}`).setMesh(still)
        .setTranslation(node.getTranslation()).setRotation(node.getRotation()).setScale(s);
      const par = node.getParentNode();
      if (par) par.addChild(n);
      else for (const sc of root.listScenes()) if (sc.listChildren().includes(node)) sc.addChild(n);
    } else still.dispose();
    if (blur.listPrimitives().length) node.addChild(doc.createNode(`blur_${suf}`).setMesh(blur));
    else blur.dispose();
    report.push(`${suf}: gira ${spinTris} tri, parado ${stillTris} tri ${stillMats.join(' ')}`);
  });
  return report;
}

