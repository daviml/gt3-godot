// Barreiras, pontes/pórticos, grid, remendos e desgaste do asfalto de Imola, guiados pelo perfil
// declarativo (tools/tracks/imola/visual_profile.json) com wrapS=wrapT=RepeatWrapping e sem KHR_texture_transform.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { mulberry32 } from '@web/util/random';
import profile from '../../tracks/imola/visual_profile.json';

const LAP = profile.lapLength;

export type AdScheme = 'verde' | 'vermelho' | 'amarelo' | 'branco' | 'azul';
type Kind = 'rail' | 'rail_green' | 'wall' | 'tecpro' | 'none';

interface ResolvedZone {
  s0: number;
  s1: number;
  side: -1 | 1;
  kind: Kind;
  ads: AdScheme | null;
  fence: boolean;
  billboard: boolean;
  i0: number;
  i1: number;
}

const AD_SETS: Record<AdScheme, [string, string, string][]> = {
  verde: [
    ['#0b5d34', '#e8d068', 'AUTODROMO'],
    ['#0b5d34', '#ffffff', 'IMOLA GP'],
    ['#0b5d34', '#e8d068', 'SANTERNO'],
    ['#0b5d34', '#ffffff', 'GT3 TIME ATTACK'],
  ],
  vermelho: [
    ['#c8102e', '#ffffff', 'MODENA OIL'],
    ['#c8102e', '#ffffff', 'PISTA CORSA'],
    ['#18181b', '#ffffff', 'TURBO 16V'],
    ['#c8102e', '#ffffff', 'IMOLA GP'],
  ],
  amarelo: [
    ['#f2c500', '#c8102e', 'EMILIA EXPRESS'],
    ['#f2c500', '#111111', 'BOLOGNA RACING'],
    ['#f2c500', '#c8102e', 'EMILIA EXPRESS'],
    ['#f2c500', '#111111', 'MOTOR VALLEY'],
  ],
  branco: [
    ['#f4f4f2', '#1d4fa3', 'RACE CONTROL'],
    ['#f4f4f2', '#c8102e', 'TECNICA ITALIA'],
    ['#f4f4f2', '#1d4fa3', 'RACE CONTROL'],
    ['#f4f4f2', '#0b5d34', 'EMILIA ROMAGNA'],
  ],
  azul: [
    ['#0f2f6e', '#f2c500', 'GOMME CORSA'],
    ['#16377a', '#ffffff', 'SANTERNO BLU'],
    ['#0f2f6e', '#f2c500', 'GOMME CORSA'],
    ['#16377a', '#ffffff', 'MOTOR VALLEY'],
  ],
};

const TOPPERS: Record<AdScheme, [string, string, string]> = {
  amarelo: ['#ffcc00', '#d40511', 'EMILIA EXPRESS'],
  azul: ['#0f3c96', '#f2c500', 'GOMME CORSA'],
  vermelho: ['#d0101e', '#ffffff', 'MODENA OIL'],
  branco: ['#ffffff', '#1d4fa3', 'TECNICA ITALIA'],
  verde: ['#0b5d34', '#e8d068', 'AUTODROMO'],
};

function topperCanvas(scheme: AdScheme): HTMLCanvasElement {
  const [bg, fg, text] = TOPPERS[scheme];
  const c = document.createElement('canvas');
  c.width = 1024;
  c.height = 64;
  const g = c.getContext('2d')!;
  g.fillStyle = bg;
  g.fillRect(0, 0, 1024, 64);
  g.fillStyle = fg;
  g.font = '900 italic 42px Arial';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText(text, 256, 34, 440);
  g.fillText(text, 768, 34, 440);
  g.fillRect(0, 0, 1024, 3);
  g.fillRect(0, 61, 1024, 3);
  return c;
}

export function adCanvas(scheme: AdScheme, panels: number, pw: number, ph: number): HTMLCanvasElement {
  const set = AD_SETS[scheme];
  const c = document.createElement('canvas');
  c.width = pw * panels;
  c.height = ph;
  const g = c.getContext('2d')!;
  for (let k = 0; k < panels; k++) {
    const [bg, fg, text] = set[k % set.length];
    const x = k * pw;
    g.fillStyle = bg;
    g.fillRect(x, 0, pw, ph);
    g.fillStyle = fg;
    g.globalAlpha = 0.85;
    g.fillRect(x, ph * 0.86, pw, ph * 0.06);
    g.globalAlpha = 1;
    g.font = `900 italic ${Math.round(ph * 0.46)}px Arial`;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(text, x + pw / 2, ph * 0.46, pw * 0.9);
    g.fillStyle = 'rgba(0,0,0,0.35)';
    g.fillRect(x, 0, 2, ph);
  }
  return c;
}

/** Garante wrapS = wrapT = RepeatWrapping para compatibilidade estrita com Godot 4. */
export function tex(c: HTMLCanvasElement, renderer: THREE.WebGLRenderer, repeat = true): THREE.Texture {
  const t = new THREE.CanvasTexture(c);
  const mode = repeat ? THREE.RepeatWrapping : THREE.ClampToEdgeWrapping;
  t.wrapS = mode;
  t.wrapT = mode;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

function tecproTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 96;
  const g = c.getContext('2d')!;
  for (let k = 0; k < 4; k++) {
    const x = k * 128;
    const grad = g.createLinearGradient(0, 0, 0, 96);
    grad.addColorStop(0, '#4f7bc8');
    grad.addColorStop(0.14, '#1b4a9e');
    grad.addColorStop(0.82, '#143c82');
    grad.addColorStop(1, '#0c2758');
    g.fillStyle = grad;
    g.fillRect(x, 0, 128, 96);
    const side = g.createLinearGradient(x, 0, x + 128, 0);
    side.addColorStop(0, 'rgba(0,0,0,0.45)');
    side.addColorStop(0.08, 'rgba(0,0,0,0)');
    side.addColorStop(0.92, 'rgba(0,0,0,0)');
    side.addColorStop(1, 'rgba(0,0,0,0.45)');
    g.fillStyle = side;
    g.fillRect(x, 0, 128, 96);
    g.fillStyle = k % 2 ? '#ffffff' : '#f2c500';
    g.font = '900 italic 24px Arial';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(k % 2 ? 'IMOLA GP' : 'GOMME CORSA', x + 64, 50, 114);
  }
  return tex(c, renderer, true);
}

function fenceTexture(): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  g.strokeStyle = 'rgba(200, 205, 210, 0.85)';
  g.lineWidth = 2;
  g.beginPath();
  g.moveTo(0, 0);
  g.lineTo(64, 64);
  g.moveTo(64, 0);
  g.lineTo(0, 64);
  g.stroke();
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

/** Textura de pneus já com 3 fileiras empilhadas no canvas (sem tex.repeat). */
function tyreStackTexture(): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 96;
  const g = c.getContext('2d')!;
  for (let k = 0; k < 3; k++) {
    const y = k * 32;
    const grad = g.createLinearGradient(0, y, 0, y + 32);
    grad.addColorStop(0, '#0c0c0c');
    grad.addColorStop(0.25, '#2a2a2a');
    grad.addColorStop(0.5, '#343434');
    grad.addColorStop(0.75, '#262626');
    grad.addColorStop(1, '#0a0a0a');
    g.fillStyle = grad;
    g.fillRect(0, y, 256, 32);
    g.fillStyle = 'rgba(0,0,0,0.35)';
    for (let x = 0; x < 256; x += 6) g.fillRect(x, y + 8, 2, 16);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

export function barrierLayout(track: Track) {
  const S = track.samples;
  const N = S.length;
  const k = track.length / LAP;
  const def = profile.barrierDefault;
  const kind: Record<-1 | 1, Kind[]> = {
    [-1]: new Array(N).fill(def.kind as Kind),
    [1]: new Array(N).fill(def.kind as Kind),
  };
  const ads: Record<-1 | 1, (AdScheme | null)[]> = {
    [-1]: new Array(N).fill((def.ads as AdScheme | null) ?? null),
    [1]: new Array(N).fill((def.ads as AdScheme | null) ?? null),
  };
  const fence: Record<-1 | 1, boolean[]> = {
    [-1]: new Array(N).fill(!!def.fence),
    [1]: new Array(N).fill(!!def.fence),
  };

  // Aplica faixas declarativas do visual_profile.json
  const zones: ResolvedZone[] = [];
  for (const z of profile.barrierZones) {
    const i0 = Math.round((z.s0 * k) / STEP);
    const i1 = Math.round((z.s1 * k) / STEP);
    const side = (z.side as -1 | 1);
    const count = i1 >= i0 ? i1 - i0 : i1 + N - i0;
    for (let step = 0; step <= count; step++) {
      const j = (i0 + step) % N;
      kind[side][j] = z.kind as Kind;
      ads[side][j] = (z.ads as AdScheme | null) ?? null;
      fence[side][j] = !!z.fence;
    }
    zones.push({
      s0: z.s0,
      s1: z.s1,
      side,
      kind: z.kind as Kind,
      ads: (z.ads as AdScheme | null) ?? null,
      fence: !!z.fence,
      billboard: !!z.billboard,
      i0,
      i1,
    });
  }

  // Abre o muro direito onde a pit lane do OSM entra/sai (4420..525)
  const open = profile.pitOpenRange;
  const pitSide = (profile.pitSide as -1 | 1);
  for (let i = 0; i < N; i++) {
    const sm = S[i].s / k;
    const inPitOpen = open.s0 > open.s1 ? sm > open.s0 || sm < open.s1 : sm > open.s0 && sm < open.s1;
    if (inPitOpen) {
      kind[pitSide][i] = 'none';
      ads[pitSide][i] = null;
      fence[pitSide][i] = false;
    }
  }
  return { kind, ads, fence, zones };
}

export function buildBarriers(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, concreteMat: THREE.Material) {
  const S = track.samples;
  const N = S.length;
  const lay = barrierLayout(track);

  const strip = (
    side: -1 | 1,
    h0: number,
    in0: number,
    h1: number,
    in1: number,
    include: (i: number) => boolean,
    mat: THREE.Material,
    vScale: number,
    shadow = true
  ) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    const v = new THREE.Vector3();
    let prev = -1;
    for (let k = 0; k <= N; k++) {
      const i = k % N;
      if (!include(i)) {
        prev = -1;
        continue;
      }
      const s = S[i];
      const wall = side < 0 ? s.wallL : s.wallR;
      const base = pos.length / 3;
      for (const [h, inset, u] of [[h0, in0, 0], [h1, in1, 1]]) {
        v.copy(s.p).addScaledVector(s.r, side * (wall - inset));
        v.y += h;
        pos.push(v.x, v.y, v.z);
        uv.push((side < 0 ? 1 : -1) * ((k * STEP) / vScale), u);
      }
      // Garante ordem correta das faces (normal apontada para dentro da pista: +r na esquerda, -r na direita)
      if (prev >= 0) {
        if (side < 0) idx.push(prev, base, prev + 1, prev + 1, base, base + 1);
        else idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
      }
      prev = base;
    }
    if (!idx.length) return;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, mat);
    m.castShadow = shadow;
    m.receiveShadow = true;
    m.userData.essential = true;
    group.add(m);
  };

  const railMat = new THREE.MeshStandardMaterial({ color: 0xc2c6ca, metalness: 0.3, roughness: 0.55, side: THREE.DoubleSide });
  const greenRailMat = new THREE.MeshStandardMaterial({ color: 0x16733b, metalness: 0.25, roughness: 0.55, side: THREE.DoubleSide });
  const greenWallMat = new THREE.MeshStandardMaterial({ color: 0x146c37, roughness: 0.72, side: THREE.DoubleSide });
  const capMat = new THREE.MeshStandardMaterial({ color: 0xbdbcb6, roughness: 0.9, side: THREE.DoubleSide });
  const fenceTex = fenceTexture();
  const fenceMat = new THREE.MeshStandardMaterial({
    map: fenceTex,
    transparent: true,
    alphaTest: 0.3,
    side: THREE.DoubleSide,
    metalness: 0.5,
    roughness: 0.5,
  });
  const tecMat = new THREE.MeshStandardMaterial({ map: tecproTexture(renderer), roughness: 0.55, side: THREE.DoubleSide });
  const tecTop = new THREE.MeshStandardMaterial({ color: 0x1b4a9e, roughness: 0.55, side: THREE.DoubleSide });

  const adMats = new Map<AdScheme, THREE.Material>();
  const adMat = (a: AdScheme) => {
    if (!adMats.has(a)) {
      adMats.set(
        a,
        new THREE.MeshStandardMaterial({
          map: tex(adCanvas(a, 4, 256, 64), renderer, true),
          roughness: 0.55,
          side: THREE.FrontSide,
          polygonOffset: true,
          polygonOffsetFactor: -1,
        })
      );
    }
    return adMats.get(a)!;
  };

  const topMats = new Map<AdScheme, THREE.Material>();
  const topMat = (a: AdScheme) => {
    if (!topMats.has(a)) {
      topMats.set(a, new THREE.MeshStandardMaterial({ map: tex(topperCanvas(a), renderer, true), roughness: 0.45, side: THREE.FrontSide }));
    }
    return topMats.get(a)!;
  };
  const topperAt = (side: -1 | 1, i: number): AdScheme | null =>
    lay.kind[side][i] === 'wall' ? lay.ads[side][i] : lay.kind[side][i] === 'tecpro' ? 'amarelo' : null;
  const cableMat = new THREE.MeshStandardMaterial({ color: 0x3c4146, metalness: 0.6, roughness: 0.45, side: THREE.DoubleSide });

  for (const side of [-1, 1] as const) {
    const K = lay.kind[side];
    const rail = (i: number) => K[i] === 'rail';
    const railG = (i: number) => K[i] === 'rail_green';
    const wall = (i: number) => K[i] === 'wall';
    const wallGreen = (i: number) => K[i] === 'wall' && lay.ads[side][i] === null;
    const wallAd = (i: number) => K[i] === 'wall' && lay.ads[side][i] !== null;
    const tec = (i: number) => K[i] === 'tecpro';
    const fence = (i: number) => lay.fence[side][i];

    strip(side, 0.38, 0, 0.70, 0, rail, railMat, 4);
    strip(side, 0.82, 0, 1.14, 0, rail, railMat, 4);
    // Guard-rail verde triplo (subida Variante Alta)
    strip(side, 0.22, 0, 0.48, 0, railG, greenRailMat, 4);
    strip(side, 0.58, 0, 0.84, 0, railG, greenRailMat, 4);
    strip(side, 0.94, 0, 1.20, 0, railG, greenRailMat, 4);

    // Muros: concreto onde há placas, verde FIA onde não há placa (característico de Imola!)
    strip(side, -0.3, 0, 1.15, 0, wallAd, concreteMat, 4);
    strip(side, -0.3, 0, 1.15, 0, wallGreen, greenWallMat, 4);
    strip(side, 1.15, 0, 1.15, -0.25, wall, capMat, 4, false);

    for (const a of Object.keys(AD_SETS) as AdScheme[]) {
      strip(side, 0.16, 0.025, 1.00, 0.025, i => wall(i) && lay.ads[side][i] === a, adMat(a), 36, false);
    }
    strip(side, -0.2, 0, 1.0, 0, tec, tecMat, 6);
    strip(side, 1.0, 0, 1.0, -0.6, tec, tecTop, 6, false);
    for (const a of Object.keys(TOPPERS) as AdScheme[]) {
      strip(side, 1.17, -0.10, 1.62, -0.10, i => wall(i) && !fence(i) && topperAt(side, i) === a, topMat(a), 8, false);
      strip(side, 1.0, -0.30, 1.45, -0.30, i => tec(i) && topperAt(side, i) === a, topMat(a), 8, false);
    }
    // Alambrado
    strip(side, 1.15, 0, 4.2, 0, fence, fenceMat, 0.6, false);
    strip(side, 4.2, 0, 5.0, 0.7, fence, fenceMat, 0.6, false);
    for (const h of [1.9, 3.0, 4.15]) strip(side, h, -0.03, h + 0.035, -0.03, fence, cableMat, 4, false);
    strip(side, 4.95, 0.66, 4.99, 0.68, fence, cableMat, 4, false);
  }

  // Postes do alambrado e guard-rails
  const postGeo = new THREE.BoxGeometry(0.1, 1, 0.1).translate(0, 0.5, 0);
  const postMat = new THREE.MeshStandardMaterial({ color: 0x80858a, metalness: 0.6, roughness: 0.5 });
  const posts = new THREE.InstancedMesh(postGeo, postMat, N * 2);
  const fencePostMat = new THREE.MeshStandardMaterial({ color: 0x4a4f55, metalness: 0.6, roughness: 0.45 });
  const fencePosts = new THREE.InstancedMesh(postGeo, fencePostMat, N);
  const arms = new THREE.InstancedMesh(postGeo, fencePostMat, N);
  let fp = 0, n = 0, a = 0;
  const m = new THREE.Matrix4(), sc = new THREE.Vector3(), q = new THREE.Quaternion(), q0 = new THREE.Quaternion(), p = new THREE.Vector3();
  for (let i = 0; i < N; i += 2) {
    const s = S[i];
    for (const side of [-1, 1] as const) {
      const tall = lay.fence[side][i];
      const rail = lay.kind[side][i] === 'rail' || lay.kind[side][i] === 'rail_green';
      if (tall ? i % 4 : !rail) continue;
      const off = side * ((side < 0 ? s.wallL : s.wallR) + 0.08);
      p.set(s.p.x + s.r.x * off, s.p.y + s.r.y * off, s.p.z + s.r.z * off);
      if (tall) {
        m.compose(p, q0, sc.set(1.7, 4.3, 1.7));
        fencePosts.setMatrixAt(fp++, m);
        p.y += 4.25;
        q.setFromAxisAngle(s.t, -side * 0.7);
        m.compose(p, q, sc.set(1.5, 1.05, 1.5));
        arms.setMatrixAt(a++, m);
      } else {
        m.compose(p, q0, sc.set(1, 1.2, 1));
        posts.setMatrixAt(n++, m);
      }
    }
  }
  posts.count = n;
  fencePosts.count = fp;
  arms.count = a;
  group.add(posts, fencePosts, arms);

  // Pilhas de pneus declaradas em visual_profile.json (sempre essenciais no Mínimo)
  const tyreGeo = new THREE.CylinderGeometry(0.39, 0.39, 0.72, 10).translate(0, 0.36, 0);
  const tyreMat = new THREE.MeshStandardMaterial({ map: tyreStackTexture(), roughness: 0.95 });
  const tyres = new THREE.InstancedMesh(tyreGeo, tyreMat, 2200);
  const UP = new THREE.Vector3(0, 1, 0);
  let t = 0;
  const k = track.length / LAP;
  for (const tb of profile.tyreBarriers) {
    const i0 = Math.round((tb.s0 * k) / STEP);
    const i1 = Math.round((tb.s1 * k) / STEP);
    const side = tb.side as -1 | 1;
    for (let i = i0; i <= i1 && t < 2198; i++) {
      const s = S[((i % N) + N) % N];
      if (lay.kind[side][((i % N) + N) % N] === 'none') continue;
      const off = side * ((side < 0 ? s.wallL : s.wallR) - 0.45);
      for (const along of [-0.5, 0.5]) {
        p.set(s.p.x + s.r.x * off + s.t.x * along, s.p.y + s.r.y * off, s.p.z + s.r.z * off + s.t.z * along);
        m.compose(p, q.setFromAxisAngle(UP, i + along), sc.set(1, 1, 1));
        tyres.setMatrixAt(t++, m);
      }
    }
  }
  tyres.count = t;
  tyres.userData.essential = true;
  group.add(tyres);

  buildBillboards(track, group, renderer, lay.zones);
}

function buildBillboards(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer, zones: ResolvedZone[]) {
  const S = track.samples;
  const N = S.length;
  const legMat = new THREE.MeshStandardMaterial({ color: 0x5b6066, metalness: 0.5, roughness: 0.5 });
  const backMat = new THREE.MeshStandardMaterial({ color: 0x505358, roughness: 0.8 });
  const tmp = new THREE.Vector3();
  zones.forEach((z, k) => {
    if (!z.billboard || !z.ads) return;
    const i = Math.round((z.i0 + z.i1) / 2) % N;
    const s = S[i];
    const wall = z.side < 0 ? s.wallL : s.wallR;
    const base = s.p.clone().addScaledVector(s.r, z.side * (wall + 7));
    const loc = track.locate(tmp.copy(base));
    if (loc && Math.abs(loc.i - i) > 20 && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + 4) return;
    const set = AD_SETS[z.ads];
    const c = adCanvas(z.ads, 1, 512, 128);
    if (set.length > 1) {
      const [bg, fg, text] = set[k % set.length];
      const g = c.getContext('2d')!;
      g.fillStyle = bg;
      g.fillRect(0, 0, 512, 128);
      g.fillStyle = fg;
      g.fillRect(0, 110, 512, 8);
      g.font = '900 italic 60px Arial';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(text, 256, 58, 470);
    }
    const face = new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.5 });
    const board = new THREE.Group();
    const panel = new THREE.Mesh(new THREE.BoxGeometry(14, 3.5, 0.2), [backMat, backMat, backMat, backMat, face, backMat]);
    panel.position.y = 4.6;
    board.add(panel);
    for (const x of [-4.5, 4.5]) {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.3, 4.5, 0.3), legMat);
      leg.position.set(x, 1.0, -0.3);
      board.add(leg);
    }
    board.traverse(o => (o.castShadow = true));
    board.position.copy(base).setY(s.p.y - 0.5);
    const look = s.t.clone().multiplyScalar(-1).addScaledVector(s.r, -z.side * 0.8).setY(0).normalize();
    board.lookAt(board.position.clone().add(look));
    group.add(board);
  });
}

export function signMaterial(renderer: THREE.WebGLRenderer, t1: string, t2: string, bg: string, fg: string, accent: string, panels = 1) {
  const pw = 512;
  const c = document.createElement('canvas');
  c.width = pw * panels;
  c.height = 192;
  const g = c.getContext('2d')!;
  for (let p = 0; p < panels; p++) {
    const x0 = p * pw;
    g.fillStyle = bg;
    g.fillRect(x0, 0, pw, 192);
    g.fillStyle = accent;
    g.fillRect(x0, 172, pw, 20);
    g.fillStyle = fg;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.font = '900 italic ' + (t2 ? 70 : 94) + 'px Arial';
    g.fillText(t1, x0 + pw / 2, t2 ? 66 : 92, pw - 28);
    if (t2) {
      g.font = '700 46px Arial';
      g.fillText(t2, x0 + pw / 2, 138, pw - 36);
    }
  }
  return new THREE.MeshStandardMaterial({ map: tex(c, renderer, false), roughness: 0.5 });
}

export function buildBridge(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const S = track.samples;
  const N = S.length;
  const mats = {
    steel: new THREE.MeshStandardMaterial({ color: 0x3b3f45, metalness: 0.5, roughness: 0.5 }),
    light: new THREE.MeshStandardMaterial({ color: 0xa9adb1, metalness: 0.45, roughness: 0.5 }),
    concrete: new THREE.MeshStandardMaterial({ color: 0xb0aea6, roughness: 0.9 }),
  };

  for (const br of profile.bridges) {
    const s = S[((Math.round((br.s * track.length) / LAP / STEP) % N) + N) % N];
    const span = s.wallL + s.wallR + 8;
    const half = span / 2;
    const g = new THREE.Group();
    const box = (w: number, h: number, d: number, x: number, y: number, z: number, mat: THREE.Material | THREE.Material[]) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      m.position.set(x, y, z);
      g.add(m);
      return m;
    };

    const schemeMap: Record<string, [string, string, string]> = {
      gantry_green: ['#0b5d34', '#e8d068', '#083b21'],
      truss_blue: ['#0f2f6e', '#ffffff', '#f2c500'],
      truss_yellow: ['#f2c500', '#0f2f6e', '#c8102e'],
      overpass_yellow: ['#f2c500', '#c8102e', '#111111'],
      truss_red: ['#c8102e', '#ffffff', '#18181b'],
      truss_white: ['#f2f2ef', '#0f2f6e', '#c8102e'],
    };
    const [bg, fg, acc] = schemeMap[br.kind] ?? ['#18181b', '#ffffff', '#0b5d34'];

    if (br.kind === 'gantry_green') {
      const h = 6.6;
      const sign = signMaterial(renderer, br.t1, br.t2, bg, fg, acc, 3);
      for (const x of [-half, half]) box(1.2, h + 3.0, 1.4, x, (h + 3.0) / 2 - 1.5, 0, mats.steel);
      box(span + 1.2, 2.4, 0.8, 0, h + 1.2, 0, [mats.steel, mats.steel, mats.steel, mats.steel, sign, sign]);
      // Caixa do semáforo de largada
      const lights = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.85, 0.45), new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.4 }));
      lights.position.set(0, h + 2.8, 0.25);
      g.add(lights);
      for (let k = 0; k < 5; k++) {
        const led = new THREE.Mesh(
          new THREE.CircleGeometry(0.18, 12),
          new THREE.MeshStandardMaterial({ color: 0x2a0000, emissive: 0x330000 })
        );
        led.position.set(-1.2 + k * 0.6, h + 2.8, 0.49);
        g.add(led);
      }
    } else if (br.kind === 'overpass_yellow') {
      // Viaduto largo de concreto + faixa amarela (como na descida para Rivazza, f_084)
      const h = 6.8;
      const sign = signMaterial(renderer, br.t1, br.t2, bg, fg, acc, 2);
      box(span + 4, 2.5, 4.2, 0, h + 1.25, 0, [mats.concrete, mats.concrete, mats.concrete, mats.concrete, sign, sign]);
      for (const x of [-half - 1.2, half + 1.2]) box(3.0, h + 4.5, 4.8, x, (h + 4.5) / 2 - 2.0, 0, mats.concrete);
    } else {
      // Passarela treliçada com faixa do evento
      const h = 6.6;
      const sign = signMaterial(renderer, br.t1, br.t2, bg, fg, acc, 2);
      box(span + 1.0, 1.9, 1.6, 0, h + 0.95, 0, [mats.light, mats.light, mats.light, mats.light, sign, sign]);
      for (const x of [-half - 0.6, half + 0.6]) box(1.8, h + 3.5, 2.2, x, (h + 3.5) / 2 - 1.5, 0, mats.concrete);
    }

    g.traverse(o => {
      o.castShadow = true;
      o.receiveShadow = true;
      o.userData.essential = true;
    });
    g.position.copy(s.p).addScaledVector(new THREE.Vector3(s.r.x, 0, s.r.z).normalize(), (s.wallR - s.wallL) / 2);
    g.quaternion.setFromRotationMatrix(
      new THREE.Matrix4().makeBasis(
        new THREE.Vector3(s.r.x, 0, s.r.z).normalize(),
        new THREE.Vector3(0, 1, 0),
        new THREE.Vector3(-s.t.x, 0, -s.t.z).normalize()
      )
    );
    group.add(g);
  }
}

function overlay(track: Track, lift: number, vScale: number, include: (i: number) => boolean, mat: THREE.Material) {
  const S = track.samples;
  const N = S.length;
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  let prev = -1;
  for (let k = 0; k <= N; k++) {
    const i = k % N;
    if (!include(i)) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const base = pos.length / 3;
    for (const [off, u] of [[-s.wl, 0], [s.wr, 1]] as const) {
      v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, lift);
      pos.push(v.x, v.y, v.z);
      uv.push(u, (k * STEP) / vScale);
    }
    if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
    prev = base;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  const mesh = new THREE.Mesh(g, mat);
  mesh.receiveShadow = true;
  return mesh;
}

export function buildGrid(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const L = track.length;
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 512;
  const g = c.getContext('2d')!;
  g.fillStyle = 'rgba(236,236,230,0.92)';
  const ppm = 512 / 16;
  for (const [x0, x1, y] of [[0.14, 0.44, 2], [0.56, 0.86, 10]]) {
    const top = 512 - y * ppm;
    g.fillRect(x0 * 512, top, (x1 - x0) * 512, 0.25 * ppm);
    g.fillRect(x0 * 512, top, 0.18 * ppm, 1.6 * ppm);
    g.fillRect(x1 * 512 - 0.18 * ppm, top, 0.18 * ppm, 1.6 * ppm);
  }
  const t = tex(c, renderer, true);
  const mat = new THREE.MeshStandardMaterial({
    map: t,
    transparent: true,
    depthWrite: false,
    roughness: 0.8,
    polygonOffset: true,
    polygonOffsetFactor: -3,
  });
  const S = track.samples;
  const mesh = overlay(track, 0.005, 16, i => S[i].s > L - 210 && S[i].s < L - 12, mat);
  mesh.renderOrder = 3;
  mesh.userData.essential = true;
  group.add(mesh);
}

export function buildPatches(track: Track, group: THREE.Group, renderer: THREE.WebGLRenderer) {
  const W = 256;
  const H = 4096;
  const ppm = H / 320;
  const c = document.createElement('canvas');
  c.width = W;
  c.height = H;
  const g = c.getContext('2d')!;
  const rand = mulberry32(420);
  // Desgaste sutil e emendas longitudinais de asfalto europeu
  for (let k = 0; k < 180; k++) {
    const edge = rand() < 0.65;
    const u = edge ? (rand() < 0.5 ? rand() * 0.22 : 1 - rand() * 0.22) : rand();
    const x = u * W;
    const y = rand() * H;
    const rx = (0.05 + rand() * 0.12) * W;
    const ry = (2 + rand() * 14) * ppm;
    const gr = g.createRadialGradient(x, y, 0, x, y, 1);
    const a = (edge ? 0.04 : 0.02) + rand() * 0.035;
    gr.addColorStop(0, `rgba(205, 203, 196, ${a})`);
    gr.addColorStop(1, 'rgba(205, 203, 196, 0)');
    g.save();
    g.translate(x, y);
    g.scale(rx, ry);
    g.translate(-x, -y);
    g.fillStyle = gr;
    g.beginPath();
    g.arc(x, y, 1, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }
  for (const u0 of [0.35, 0.67]) {
    let y = 0;
    while (y < H) {
      const len = (10 + rand() * 45) * ppm;
      const off = (rand() - 0.5) * 0.02 * W;
      g.fillStyle = `rgba(14, 14, 15, ${0.18 + rand() * 0.16})`;
      g.fillRect(u0 * W + off, y, 1.5 + rand() * 1.2, len);
      y += len + (rand() < 0.3 ? (3 + rand() * 12) * ppm : 0);
    }
  }
  const t = tex(c, renderer, true);
  const mat = new THREE.MeshStandardMaterial({
    map: t,
    transparent: true,
    depthWrite: false,
    roughness: 0.92,
    polygonOffset: true,
    polygonOffsetFactor: -1,
  });
  const mesh = overlay(track, 0.008, 320, () => true, mat);
  mesh.renderOrder = 1;
  group.add(mesh);
}
