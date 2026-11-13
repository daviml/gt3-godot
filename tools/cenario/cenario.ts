// Monta a pista com o próprio código do jogo web (buildTrack de src/render/trackView.ts) e exporta para o Godot:
//   GLB com tudo o que é malha (pista, zebras, escapes, borracha, muros, placas, arquibancadas, pits, prédios...)
//   + lista de árvores (posição, tamanho, espécie, giro, tom) para os impostores do Godot.
// O que o web faz em shader próprio (onBeforeCompile) não vai no GLB: o material sai só com um nome e o Godot
// põe o shader equivalente (asfalto, grama, fachada) ou as texturas da Poly Haven (ph:<nome>).
// Os anéis de prédios e o horizonte (surroundings.ts) ficam para a etapa 12.
import * as THREE from 'three';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { Track, type TrackData } from '../../../gt3-time-attack/src/track/track';
import { buildTrack } from '../../../gt3-time-attack/src/render/trackView';
import { QUALITIES } from '../../../gt3-time-attack/src/render/quality';
import interlagos from '../../../gt3-time-attack/data/tracks/interlagos.json';

// guarda a URL de cada textura carregada (o nome diz qual textura da Poly Haven é)
const load0 = THREE.TextureLoader.prototype.load;
THREE.TextureLoader.prototype.load = function (url: string, ...rest: any[]) {
  const t = (load0 as any).call(this, url, ...rest) as THREE.Texture;
  t.userData.url = url;
  return t;
};
const phName = (t: THREE.Texture | null | undefined) => {
  const m = /textures\/([a-z0-9_]+?)_(diff|nor_gl|arm)/.exec(t?.userData?.url ?? '');
  return m ? m[1] : null;
};

const CROWD_COLS = 8;
const CROWD_ROWS = 4;

function bake(im: THREE.InstancedMesh): THREE.BufferGeometry | null {
  if (!im.count) return null;
  const parts: THREE.BufferGeometry[] = [];
  const m = new THREE.Matrix4();
  const cell = im.geometry.getAttribute('aCell') as THREE.BufferAttribute | undefined;
  const base = im.geometry.clone();
  for (const k of Object.keys(base.attributes)) if (k.startsWith('a')) base.deleteAttribute(k);
  for (let i = 0; i < im.count; i++) {
    im.getMatrixAt(i, m);
    const g = base.clone().applyMatrix4(m);
    if (cell) {
      // torcida: a figura do atlas que o shader do web escolhia por aCell vai direto no UV
      const c = cell.getX(i);
      const uv = g.getAttribute('uv') as THREE.BufferAttribute;
      for (let v = 0; v < uv.count; v++)
        uv.setXY(v, (uv.getX(v) + (c % CROWD_COLS)) / CROWD_COLS, (uv.getY(v) + Math.floor(c / CROWD_COLS)) / CROWD_ROWS);
    }
    if (im.instanceColor) {
      const col = new THREE.Color();
      im.getColorAt(i, col);
      const arr = new Float32Array(g.getAttribute('position').count * 3);
      for (let v = 0; v < arr.length; v += 3) arr.set([col.r, col.g, col.b], v);
      g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
    }
    parts.push(g.index ? g.toNonIndexed() : g);
  }
  return mergeGeometries(parts);
}

async function run() {
  const renderer = new THREE.WebGLRenderer();
  const scene = new THREE.Scene();
  const track = new Track(interlagos as unknown as TrackData);
  buildTrack(track, scene, renderer, QUALITIES.extremo);
  scene.updateMatrixWorld(true);

  const trees: number[] = [];
  const stats: Record<string, number> = {};
  const count = (k: string, n = 1) => (stats[k] = (stats[k] ?? 0) + n);
  const mats = new Map<THREE.Material, THREE.Material>();
  const remove: THREE.Object3D[] = [];
  const add: [THREE.Object3D, THREE.Object3D][] = [];

  const convert = (m: THREE.Material, geo: THREE.BufferGeometry): THREE.Material | null => {
    if (mats.has(m)) return mats.get(m)!;
    const sm = m as THREE.MeshStandardMaterial;
    const ph = phName(sm.map);
    const custom = sm.onBeforeCompile !== THREE.Material.prototype.onBeforeCompile;
    let out: THREE.Material | null = m;
    if (ph === 'asphalt_track' && custom) out = new THREE.MeshStandardMaterial({ name: 'asfalto' });
    else if (ph === 'leafy_grass') out = new THREE.MeshStandardMaterial({ name: 'grama', roughness: 0.99 });
    else if (ph) out = new THREE.MeshStandardMaterial({ name: `ph:${ph}`, color: sm.color, side: sm.side });
    else if (sm.map && phName(sm.normalMap) === 'asphalt_track') {
      // tinta sobre o asfalto (paintOn): a cor pintada fica; relevo e rugosidade do asfalto o Godot põe
      const c = sm.clone();
      c.normalMap = null;
      c.roughnessMap = null;
      c.name = 'pinta';
      out = c;
    } else if (custom && sm.vertexColors && geo.getAttribute('aWin')) {
      const c = new THREE.MeshStandardMaterial({ name: 'fachada', vertexColors: true, roughness: sm.roughness, side: sm.side });
      out = c;
    } else if (custom && geo.getAttribute('aCell')) {
      // torcida: o atlas fica; a figura de cada pessoa vai no UV (bake)
      out = new THREE.MeshStandardMaterial({ name: 'torcida', map: sm.map, alphaTest: sm.alphaTest, side: sm.side, roughness: sm.roughness });
    } else if (custom) out = null; // shader sem equivalente aqui (torres do anel: etapa 12)
    else if ((m as THREE.MeshBasicMaterial).isMeshBasicMaterial && m.side === THREE.BackSide) out = null; // horizonte
    mats.set(m, out!);
    return out;
  };

  scene.traverse(o => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh) return;
    const geo = mesh.geometry;
    if ((mesh as THREE.InstancedMesh).isInstancedMesh && geo.getAttribute('aTree')) {
      // árvores impostoras: x, y, z, tamanho, espécie, giro, tom
      const im = mesh as THREE.InstancedMesh;
      const at = geo.getAttribute('aTree') as THREE.BufferAttribute;
      const m = new THREE.Matrix4();
      const p = new THREE.Vector3();
      const q = new THREE.Quaternion();
      const s = new THREE.Vector3();
      for (let i = 0; i < im.count; i++) {
        im.getMatrixAt(i, m);
        m.premultiply(im.matrixWorld).decompose(p, q, s);
        trees.push(+p.x.toFixed(2), +p.y.toFixed(2), +p.z.toFixed(2), +s.x.toFixed(3), at.getX(i), +at.getY(i).toFixed(3), +at.getZ(i).toFixed(3));
      }
      count('árvores', im.count);
      remove.push(mesh);
      return;
    }
    const mat = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    const conv = mat.map(m => convert(m, geo));
    if (conv.some(m => m === null)) {
      count('descartado (etapa 12)');
      remove.push(mesh);
      return;
    }
    let g = geo;
    if ((mesh as THREE.InstancedMesh).isInstancedMesh) {
      const b = bake(mesh as THREE.InstancedMesh);
      count('instâncias assadas', (mesh as THREE.InstancedMesh).count);
      remove.push(mesh);
      if (!b) return;
      g = b;
    } else if (geo.getAttribute('aWin')) {
      // fachada: o tipo de janela (aWin) vai no segundo UV
      g = geo.clone();
      const w = geo.getAttribute('aWin') as THREE.BufferAttribute;
      const uv1 = new Float32Array(w.count * 2);
      for (let i = 0; i < w.count; i++) uv1[i * 2] = w.getX(i);
      g.setAttribute('uv1', new THREE.BufferAttribute(uv1, 2));
      g.deleteAttribute('aWin');
    }
    const out = new THREE.Mesh(g, Array.isArray(mesh.material) ? conv : conv[0]);
    out.position.copy(mesh.position);
    out.quaternion.copy(mesh.quaternion);
    out.scale.copy(mesh.scale);
    // ordem de desenho e sombra no nome (o glTF não guarda): o Godot lê
    out.name = `${mesh.userData.essential ? 'ess_' : ''}o${mesh.renderOrder}_s${mesh.castShadow ? 1 : 0}`;
    remove.push(mesh);
    add.push([mesh.parent!, out]);
    count('malhas');
  });
  for (const o of remove) o.parent?.remove(o);
  for (const [p, o] of add) p.add(o);

  // junta as malhas do mesmo material, ordem e sombra numa só por região de 250 m: o web desenha centenas de
  // peças soltas (postes, placas, casinhas...), que no Godot viram centenas de draw calls. As faixas que dão a
  // volta inteira (> 400 m) ficam como estão.
  scene.updateMatrixWorld(true);
  const groups = new Map<string, THREE.Mesh[]>();
  const box = new THREE.Box3();
  const ctr = new THREE.Vector3();
  const size = new THREE.Vector3();
  scene.traverse(o => {
    const m = o as THREE.Mesh;
    if (!m.isMesh || Array.isArray(m.material)) return;
    box.setFromObject(m).getCenter(ctr);
    box.getSize(size);
    if (Math.max(size.x, size.z) > 400) return;
    const g = m.geometry;
    const key = [(m.material as THREE.Material).uuid, m.name, Object.keys(g.attributes).sort().join(','), !!g.index,
      Math.floor(ctr.x / 250), Math.floor(ctr.z / 250)].join('|');
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(m);
  });
  for (const list of groups.values()) {
    if (list.length < 2) continue;
    const merged = mergeGeometries(list.map(m => m.geometry.clone().applyMatrix4(m.matrixWorld)));
    if (!merged) continue;
    const out = new THREE.Mesh(merged, list[0].material);
    out.name = list[0].name;
    for (const m of list) m.parent?.remove(m);
    scene.add(out);
    count('juntadas', list.length - 1);
  }

  // Fatiar a torcida em blocos de 120 m fora do runtime (elimina o _split_crowd em GDScript ao abrir a pista)
  const CROWD_CELL = 120;
  const crowdMeshes: THREE.Mesh[] = [];
  scene.updateMatrixWorld(true);
  scene.traverse(o => {
    const m = o as THREE.Mesh;
    if (!m.isMesh || Array.isArray(m.material)) return;
    if ((m.material as THREE.Material).name === 'torcida') crowdMeshes.push(m);
  });
  for (const cm of crowdMeshes) {
    const geo = cm.geometry.clone().applyMatrix4(cm.matrixWorld);
    const g = geo.index ? geo.toNonIndexed() : geo;
    const pos = g.getAttribute('position') as THREE.BufferAttribute;
    const attrs = Object.keys(g.attributes);
    const buckets = new Map<string, number[]>();
    for (let t = 0; t + 2 < pos.count; t += 3) {
      const cx = (pos.getX(t) + pos.getX(t + 1) + pos.getX(t + 2)) / 3;
      const cz = (pos.getZ(t) + pos.getZ(t + 1) + pos.getZ(t + 2)) / 3;
      const key = `${Math.floor(cx / CROWD_CELL)},${Math.floor(cz / CROWD_CELL)}`;
      let list = buckets.get(key);
      if (!list) buckets.set(key, (list = []));
      list.push(t, t + 1, t + 2);
    }
    const parent = cm.parent ?? scene;
    parent.remove(cm);
    for (const [key, verts] of buckets) {
      const sub = new THREE.BufferGeometry();
      for (const k of attrs) {
        const src = g.getAttribute(k) as THREE.BufferAttribute;
        const sz = src.itemSize;
        const arr = new Float32Array(verts.length * sz);
        for (let i = 0; i < verts.length; i++) {
          const vi = verts[i];
          for (let e = 0; e < sz; e++) arr[i * sz + e] = src.array[vi * sz + e];
        }
        sub.setAttribute(k, new THREE.BufferAttribute(arr, sz));
      }
      const block = new THREE.Mesh(sub, cm.material);
      block.name = `${cm.name}_c_${key.replace(',', '_')}`;
      parent.add(block);
      count('blocos_torcida');
    }
  }

  const glb = (await new GLTFExporter().parseAsync(scene, { binary: true, maxTextureSize: 2048 })) as ArrayBuffer;
  const bytes = new Uint8Array(glb);
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return { glb: btoa(bin), trees, stats, sections: track.sections.map(s => s.name) };
}

(window as any).exportar = run;
