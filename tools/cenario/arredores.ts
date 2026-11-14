// Arredores distantes (etapa 9 do PLANO; surroundings.ts do web): monta a pista com o próprio buildTrack do web e
// tira de lá o que o cenario.glb descarta por ser shader próprio:
//   - o anel de torres residenciais (InstancedMesh de caixas com a fachada no shader): posição, giro, tamanho e cor
//     de cada torre, que o Godot desenha num MultiMesh com shaders/torre.gdshader;
//   - o horizonte (cilindro com a textura de morros e cidade desenhada em canvas): a textura em PNG e o tamanho e a
//     posição do cilindro.
import * as THREE from 'three';
import { Track, type TrackData } from '../../../gt3-time-attack/src/track/track';
import { buildTrack } from '../../../gt3-time-attack/src/render/trackView';
import { QUALITIES } from '../../../gt3-time-attack/src/render/quality';
import interlagos from '../../../gt3-time-attack/data/tracks/interlagos.json';
// camber opcional (só pistas com "bank"; Interlagos não tem e nada muda): a malha inclina igual à física
import { applyBank, clampRunoff } from '../tracks/bank';

async function run() {
  const renderer = new THREE.WebGLRenderer();
  const scene = new THREE.Scene();
  const track = new Track(interlagos as unknown as TrackData);
  clampRunoff(track, (interlagos as { maxRunoff?: number }).maxRunoff);
  applyBank(track, (interlagos as { bank?: number[] }).bank);
  buildTrack(track, scene, renderer, QUALITIES.extremo);
  scene.updateMatrixWorld(true);

  const towers: number[] = [];
  let horizon: { png: string; x: number; y: number; z: number; radius: number; height: number; segments: number } | null = null;
  const m = new THREE.Matrix4();
  const p = new THREE.Vector3();
  const q = new THREE.Quaternion();
  const s = new THREE.Vector3();
  const e = new THREE.Euler();
  const c = new THREE.Color();
  scene.traverse(o => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh) return;
    const mat = mesh.material as THREE.MeshStandardMaterial;
    const geo = mesh.geometry;
    const im = mesh as THREE.InstancedMesh;
    if (im.isInstancedMesh && geo.type === 'BoxGeometry' && im.instanceColor &&
        mat.onBeforeCompile !== THREE.Material.prototype.onBeforeCompile) {
      // torres: x, base, z, giro, largura, altura, profundidade, cor (sRGB 0xRRGGBB)
      for (let i = 0; i < im.count; i++) {
        im.getMatrixAt(i, m);
        m.premultiply(im.matrixWorld).decompose(p, q, s);
        e.setFromQuaternion(q, 'YXZ');
        im.getColorAt(i, c);
        towers.push(+p.x.toFixed(2), +p.y.toFixed(2), +p.z.toFixed(2), +e.y.toFixed(4),
          +s.x.toFixed(2), +s.y.toFixed(2), +s.z.toFixed(2), c.getHex(THREE.SRGBColorSpace));
      }
    } else if ((mat as unknown as THREE.MeshBasicMaterial).isMeshBasicMaterial && mat.side === THREE.BackSide &&
               geo.type === 'CylinderGeometry') {
      const prm = (geo as THREE.CylinderGeometry).parameters;
      const canvas = mat.map!.image as HTMLCanvasElement;
      mesh.getWorldPosition(p);
      horizon = { png: canvas.toDataURL('image/png').split(',')[1], x: p.x, y: p.y, z: p.z,
        radius: prm.radiusTop, height: prm.height, segments: prm.radialSegments };
    }
  });
  return { towers, horizon };
}

(window as any).exportar = run;
