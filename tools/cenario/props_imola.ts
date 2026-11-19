// Hero Props de Imola (torre_imola, portico_imola, marshal_post) em baixa contagem de triângulos (300-2500 tris)
// e fundações de -1,5 m, exportados via GLTFExporter para assets/props/imola/*.glb.
import * as THREE from 'three';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';

function countTris(root: THREE.Object3D): number {
  let tris = 0;
  root.traverse(o => {
    if (!(o instanceof THREE.Mesh)) return;
    const g = o.geometry;
    tris += g.index ? g.index.count / 3 : g.attributes.position.count / 3;
  });
  return Math.round(tris);
}

function makeCanvasTex(w: number, h: number, draw: (g: CanvasRenderingContext2D) => void): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  draw(c.getContext('2d')!);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = THREE.ClampToEdgeWrapping;
  t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function buildTorreImola(): THREE.Group {
  const g = new THREE.Group();
  g.name = 'torre_imola';

  const plinthMat = new THREE.MeshStandardMaterial({ color: 0x45494e, roughness: 0.85, metalness: 0.1 });
  const shaftMat = new THREE.MeshStandardMaterial({ color: 0x5c6168, roughness: 0.78, metalness: 0.12 });
  const accentGreen = new THREE.MeshStandardMaterial({ color: 0x0b6b38, roughness: 0.55 });
  const accentWhite = new THREE.MeshStandardMaterial({ color: 0xdeddd8, roughness: 0.65 });
  const accentRed = new THREE.MeshStandardMaterial({ color: 0xb81f28, roughness: 0.55 });
  const glassMat = new THREE.MeshStandardMaterial({ color: 0x1c3148, roughness: 0.14, metalness: 0.65 });
  const steelMat = new THREE.MeshStandardMaterial({ color: 0x8d939a, roughness: 0.42, metalness: 0.6 });
  const logoTex = makeCanvasTex(512, 128, ctx => {
    ctx.fillStyle = '#0b5d34';
    ctx.fillRect(0, 0, 512, 128);
    ctx.fillStyle = '#cd212a';
    ctx.fillRect(0, 0, 512, 14);
    ctx.fillStyle = '#f2f2ee';
    ctx.fillRect(0, 14, 512, 10);
    ctx.fillStyle = '#f4f4ee';
    ctx.font = 'bold 54px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('IMOLA', 256, 78);
  });
  const logoMat = new THREE.MeshStandardMaterial({ map: logoTex, roughness: 0.5 });

  const add = (geo: THREE.BufferGeometry, mat: THREE.Material | THREE.Material[], x: number, y: number, z: number) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    g.add(m);
    return m;
  };

  // Base e fundação até -1,5 m
  add(new THREE.BoxGeometry(5.6, 10.5, 5.6), plinthMat, 0, 3.75, 0);
  // Nervuras arquitetônicas na base e no fuste
  for (const ang of [0, 1, 2, 3]) {
    const sx = ang % 2 === 0 ? (ang === 0 ? 1 : -1) * 2.25 : 0;
    const sz = ang % 2 === 1 ? (ang === 1 ? 1 : -1) * 2.25 : 0;
    add(new THREE.BoxGeometry(ang % 2 ? 4.5 : 0.32, 12.6, ang % 2 ? 0.32 : 4.5), plinthMat, sx, 15.2, sz);
  }
  // Fuste principal da torre acima do prédio dos boxes (y=9..21.5)
  add(new THREE.BoxGeometry(4.4, 12.6, 4.4), shaftMat, 0, 15.2, 0);
  // Faixas tricolores verticais / laterais da torre de Imola
  add(new THREE.BoxGeometry(4.56, 1.4, 4.56), accentGreen, 0, 19.8, 0);
  add(new THREE.BoxGeometry(4.56, 0.9, 4.56), accentWhite, 0, 18.65, 0);
  add(new THREE.BoxGeometry(4.56, 1.1, 4.56), accentRed, 0, 17.65, 0);
  // Cabine de controle panorâmica envidraçada (y=21.5..25.2) + pilares metálicos perimetrais
  add(new THREE.BoxGeometry(7.2, 0.5, 7.2), plinthMat, 0, 21.5, 0);
  add(new THREE.BoxGeometry(6.6, 2.8, 6.6), glassMat, 0, 23.15, 0);
  for (const px of [-3.35, 0, 3.35]) {
    for (const pz of [-3.35, 0, 3.35]) {
      if (px === 0 && pz === 0) continue;
      add(new THREE.CylinderGeometry(0.11, 0.11, 2.9, 6), steelMat, px, 23.15, pz);
    }
  }
  add(new THREE.BoxGeometry(7.5, 0.65, 7.5), plinthMat, 0, 24.85, 0);
  // Painel de identificação nos 4 lados do coroamento
  const capMats = [logoMat, logoMat, plinthMat, plinthMat, logoMat, logoMat];
  add(new THREE.BoxGeometry(7.3, 1.35, 7.3), capMats, 0, 25.85, 0);
  // Mastro de cronometragem / antenas e prato de telemetria no topo
  add(new THREE.CylinderGeometry(0.14, 0.28, 5.2, 10), steelMat, 0, 29.1, 0);
  add(new THREE.CylinderGeometry(0.65, 0.65, 0.16, 12), steelMat, 0, 31.2, 0);
  add(new THREE.CylinderGeometry(0.05, 0.08, 3.2, 8), steelMat, 2.2, 27.9, 1.8);
  add(new THREE.CylinderGeometry(0.05, 0.08, 2.8, 8), steelMat, -2.0, 27.7, -1.6);

  return g;
}

function buildPorticoImola(): THREE.Group {
  const g = new THREE.Group();
  g.name = 'portico_imola';

  const steel = new THREE.MeshStandardMaterial({ color: 0x3b4046, roughness: 0.45, metalness: 0.55 });
  const dark = new THREE.MeshStandardMaterial({ color: 0x1b1d20, roughness: 0.55, metalness: 0.3 });
  const footer = new THREE.MeshStandardMaterial({ color: 0x7a7e82, roughness: 0.85 });

  const signTex = makeCanvasTex(1024, 160, ctx => {
    ctx.fillStyle = '#0b5d34';
    ctx.fillRect(0, 0, 1024, 160);
    ctx.fillStyle = '#cd212a';
    ctx.fillRect(0, 0, 1024, 10);
    ctx.fillStyle = '#f2f2ee';
    ctx.fillRect(0, 10, 1024, 8);
    ctx.fillStyle = '#e8d068';
    ctx.fillRect(0, 146, 1024, 14);
    ctx.fillStyle = '#ffffff';
    ctx.font = '900 italic 44px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('AUTODROMO ENZO E DINO FERRARI', 512, 68, 960);
    ctx.fillStyle = '#e8d068';
    ctx.font = 'bold 28px Arial';
    ctx.fillText('IMOLA  •  EMILIA-ROMAGNA', 512, 118, 800);
  });
  const signMat = new THREE.MeshStandardMaterial({ map: signTex, roughness: 0.48 });

  const span = 34.0;
  const half = span / 2;
  const clearH = 6.9;

  // Torres treliçadas laterais com fundação -1,5 m
  for (const sx of [-half, half]) {
    const base = new THREE.Mesh(new THREE.BoxGeometry(1.5, 2.0, 1.5), footer);
    base.position.set(sx, -0.5, 0);
    g.add(base);
    for (const [ox, oz] of [
      [-0.45, -0.45],
      [0.45, -0.45],
      [-0.45, 0.45],
      [0.45, 0.45],
    ]) {
      const col = new THREE.Mesh(new THREE.BoxGeometry(0.16, clearH + 3.2, 0.16), steel);
      col.position.set(sx + ox, (clearH + 3.2) / 2 - 1.0, oz);
      g.add(col);
    }
    for (const yh of [1.8, 4.2, 6.6]) {
      const brace = new THREE.Mesh(new THREE.BoxGeometry(1.06, 0.14, 1.06), steel);
      brace.position.set(sx, yh, 0);
      g.add(brace);
    }
  }

  // Travessa principal + placas dos dois lados
  const beam = new THREE.Mesh(
    new THREE.BoxGeometry(span + 1.4, 2.2, 0.9),
    [steel, steel, steel, steel, signMat, signMat]
  );
  beam.position.set(0, clearH + 1.1, 0);
  g.add(beam);

  // Truss superior acima do pórtico
  const topChord = new THREE.Mesh(new THREE.BoxGeometry(span + 1.2, 0.25, 0.7), steel);
  topChord.position.set(0, clearH + 2.75, 0);
  g.add(topChord);
  for (let x = -half + 1; x <= half - 1; x += 2.2) {
    const strut = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.65, 0.55), steel);
    strut.position.set(x, clearH + 2.38, 0);
    g.add(strut);
  }

  // Câmeras/sensores centrais de cronometragem sob o pórtico
  const boxPod = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.45, 0.55), dark);
  boxPod.position.set(0, clearH - 0.18, 0);
  g.add(boxPod);

  return g;
}

function buildMarshalPost(): THREE.Group {
  const g = new THREE.Group();
  g.name = 'marshal_post';

  const plinth = new THREE.MeshStandardMaterial({ color: 0x62666b, roughness: 0.88 });
  const cabin = new THREE.MeshStandardMaterial({ color: 0xd9dbd7, roughness: 0.72 });
  const orangeRoof = new THREE.MeshStandardMaterial({ color: 0xe36216, roughness: 0.55 });
  const glass = new THREE.MeshStandardMaterial({ color: 0x1d344a, roughness: 0.15, metalness: 0.6 });
  const railMat = new THREE.MeshStandardMaterial({ color: 0x9aa0a6, roughness: 0.45, metalness: 0.55 });
  const flagMat = new THREE.MeshStandardMaterial({ color: 0xf4cc00, roughness: 0.75, side: THREE.DoubleSide });

  const add = (geo: THREE.BufferGeometry, mat: THREE.Material, x: number, y: number, z: number) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    g.add(m);
    return m;
  };

  // Base em concreto com ancoragem de -1,5 m + degraus de acesso
  add(new THREE.BoxGeometry(2.6, 2.2, 2.4), plinth, 0, -0.4, 0);
  add(new THREE.BoxGeometry(1.1, 0.4, 0.6), plinth, 0, 0.2, 1.45);
  add(new THREE.BoxGeometry(1.1, 0.25, 0.4), plinth, 0, 0.45, 1.35);
  // Corpo da cabine
  add(new THREE.BoxGeometry(2.3, 2.35, 2.0), cabin, 0, 1.85, 0);
  // Faixa de janelas em torno da cabine
  add(new THREE.BoxGeometry(2.36, 0.85, 1.55), glass, 0, 2.25, 0);
  add(new THREE.BoxGeometry(1.75, 0.85, 2.06), glass, 0, 2.25, 0);
  // Telhado italiano saliente em laranja vivo com frisos
  add(new THREE.BoxGeometry(2.9, 0.22, 2.6), orangeRoof, 0, 3.12, 0);
  add(new THREE.BoxGeometry(2.5, 0.14, 2.2), plinth, 0, 3.28, 0);
  for (const rx of [-1.05, 0, 1.05]) add(new THREE.BoxGeometry(0.12, 0.1, 2.5), orangeRoof, rx, 3.26, 0);
  // Mastros de sinalização, luz âmbar e antena
  add(new THREE.CylinderGeometry(0.04, 0.045, 2.4, 8), railMat, 1.15, 4.15, 0.85);
  const flag = add(new THREE.PlaneGeometry(0.95, 0.62), flagMat, 1.63, 4.95, 0.85);
  flag.rotation.y = 0.2;
  add(new THREE.CylinderGeometry(0.03, 0.035, 1.8, 8), railMat, -1.15, 3.9, 0.85);
  add(new THREE.CylinderGeometry(0.11, 0.11, 0.24, 10), orangeRoof, -1.15, 4.85, 0.85);
  // Guarda-corpo perimetral metálico
  for (const sx of [-1.18, 0, 1.18]) {
    add(new THREE.CylinderGeometry(0.035, 0.035, 0.95, 6), railMat, sx, 0.48, -1.16);
  }
  add(new THREE.CylinderGeometry(0.035, 0.035, 2.4, 6), railMat, 0, 0.95, -1.16).rotation.z = Math.PI / 2;
  add(new THREE.CylinderGeometry(0.03, 0.03, 2.4, 6), railMat, 0, 0.55, -1.16).rotation.z = Math.PI / 2;

  return g;
}

async function exportProps(): Promise<Record<string, { b64: string; tris: number }>> {
  const exporter = new GLTFExporter();
  const builders: Record<string, () => THREE.Group> = {
    torre_imola: buildTorreImola,
    portico_imola: buildPorticoImola,
    marshal_post: buildMarshalPost,
  };
  const out: Record<string, { b64: string; tris: number }> = {};
  for (const [id, fn] of Object.entries(builders)) {
    const root = fn();
    root.updateMatrixWorld(true);
    const tris = countTris(root);
    const glb = (await exporter.parseAsync(root, { binary: true, maxTextureSize: 1024 })) as ArrayBuffer;
    const bytes = new Uint8Array(glb);
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    out[id] = { b64: btoa(bin), tris };
  }
  return out;
}

(window as any).exportProps = exportProps;
