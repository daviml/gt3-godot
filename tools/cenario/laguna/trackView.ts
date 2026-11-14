// Cópia adaptada para Laguna Seca (tools/cenario/vite.config.ts troca o módulo do web por este só com
// TRACK=laguna-seca). Como no LMU: zebras vermelho/branco, faixa verde pintada atrás delas, brita/areia bege até o
// muro onde o satélite mostra (laguna-seca-surfaces.json), relevo do LiDAR seguindo o camber perto da pista,
// carvalhos esparsos. Asfalto e grama recebem as cores no Godot (data/tracks.json → visual).
// Malha da pista: asfalto, faixas brancas, zebras, grama até o muro, guard-rail, linha de chegada,
// terreno em volta seguindo a altitude, árvores e arquibancadas simples.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { buildExtras } from './scenery';
import { buildBarriers, buildBridge, buildGrid, buildPatches } from './trackDetails';
import { buildBanners, buildCornerDetails, buildMarshalPosts, buildPits, buildStands, occupied } from './trackside';
import { buildOsmScenery, OsmData } from '@web/render/osmScenery';
import osm from '../../tracks/laguna-seca/laguna-seca-osm.json';
import terrain from '../../tracks/laguna-seca/laguna-seca-terrain.json';
import surfaces from '../../tracks/laguna-seca/laguna-seca-surfaces.json';
import { mulberry32 } from '@web/util/random';
import type { Quality } from '@web/render/quality';
import { plantTrees, TreeSpot } from '@web/render/trees';
import { pbr, phTexture, setHiRes } from '@web/render/textures';
import { buildHorizon, buildTowers, HAZE } from './surroundings';

/**
 * Terreno: grama verde-amarelada (leafy_grass) e palha seca alaranjada (sparse_grass) misturadas por um ruído em
 * coordenadas de mundo (manchas de dezenas de metros), cada uma lida em duas escalas para a repetição de 6 m não
 * aparecer; terra vermelha só em trilhas finas e falhas pequenas.
 * Os UVs vêm em metros/6 (como no resto da pista).
 */
function terrainMaterial(renderer: THREE.WebGLRenderer): THREE.MeshStandardMaterial {
  const mat = pbr('leafy_grass', renderer, { color: 0xbccb98 });
  const dry = phTexture('sparse_grass', 'diff', renderer);
  mat.onBeforeCompile = shader => {
    shader.uniforms.dryMap = { value: dry };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec2 vGround;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvGround = (modelMatrix * vec4(transformed, 1.0)).xz;');
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        uniform sampler2D dryMap;
        varying vec2 vGround;
        float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float vnoise(vec2 p) {
          vec2 i = floor(p), f = fract(p);
          f = f * f * (3.0 - 2.0 * f);
          return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
        }`
      )
      .replace(
        '#include <map_fragment>',
        `vec2 gp = vGround;
        float n = vnoise(gp * 0.012) * 0.6 + vnoise(gp * 0.05) * 0.3 + vnoise(gp * 0.3) * 0.1;
        vec3 green = mix(texture2D(map, vMapUv).rgb, texture2D(map, vMapUv * 0.21 + 0.37).rgb, 0.45);
        vec3 dryC = mix(texture2D(dryMap, vMapUv * 0.8).rgb, texture2D(dryMap, vMapUv * 0.17 + 0.61).rgb, 0.45);
        // grama de Interlagos no LMU: verde-amarelada seca, puxando para o laranja em manchas grandes; nada de
        // chão bege liso. A grama "verde" já sai amarelada e a seca vira palha alaranjada (não terra).
        float lg = dot(green, vec3(0.3, 0.59, 0.11));
        green = mix(vec3(lg), green, 1.25) * vec3(1.02, 1.0, 0.62);
        float ld = dot(dryC, vec3(0.3, 0.59, 0.11));
        vec3 straw = vec3(ld) * vec3(1.32, 1.08, 0.55) * (0.85 + 0.3 * texture2D(map, vMapUv * 0.5).g);
        float dryK = smoothstep(0.45, 0.8, n);
        // variação de tom em escala grande (a grama nunca é de uma cor só) e manchas finas mais verdes
        float tone = 0.82 + 0.34 * vnoise(gp * 0.03 + 7.0);
        float lush = smoothstep(0.55, 0.8, vnoise(gp * 0.09 + 13.0)) * 0.5;
        vec3 grassC = mix(mix(green, straw, dryK * 0.75), green * vec3(0.85, 1.0, 0.9), lush * (1.0 - dryK));
        diffuseColor.rgb *= grassC * tone;
        // terra vermelha só em trilhas finas e pequenas falhas (antes: manchas grandes de chão liso)
        float tr = abs(vnoise(gp * 0.018 + 31.0) - 0.5);
        float trail = (1.0 - smoothstep(0.004, 0.012, tr)) * smoothstep(0.4, 0.7, vnoise(gp * 0.01 + 3.0));
        float bald = smoothstep(0.78, 0.86, vnoise(gp * 0.12 + 5.0) * 0.7 + vnoise(gp * 0.9) * 0.3);
        float dirt = max(trail, bald * 0.7);
        vec3 soil = vec3(0.50, 0.30, 0.18) * (0.75 + 0.5 * texture2D(dryMap, vMapUv * 1.7).r);
        diffuseColor.rgb = mix(diffuseColor.rgb, soil, dirt * 0.85);`
      );
  };
  return mat;
}

/** Faixa ao longo da pista entre dois deslocamentos laterais (a e b, + = direita), em [i0, i1). */
function ribbon(
  track: Track,
  a: (i: number) => number,
  b: (i: number) => number,
  lift: number,
  uScale: number,
  vScale: number,
  include: (i: number) => boolean = () => true
): THREE.BufferGeometry {
  const S = track.samples;
  const N = S.length;
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  let prev = -1; // primeiro vértice da amostra anterior incluída (-1 = trecho interrompido)
  for (let k = 0; k <= N; k++) {
    const i = k % N;
    if (!include(i)) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const base = pos.length / 3;
    for (const [off, u] of [[a(i), 0], [b(i), 1]] as const) {
      v.copy(s.p).addScaledVector(s.r, off).addScaledVector(s.n, lift);
      pos.push(v.x, v.y, v.z);
      uv.push(uScale ? off / uScale : u, (k * STEP) / vScale);
    }
    if (prev >= 0) idx.push(prev, prev + 1, base, prev + 1, base + 1, base);
    prev = base;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/**
 * Desgaste de tinta sobre o canvas: grão fino (a tinta sobre o asfalto não é lisa), manchas de sujeira e
 * riscos de borracha no sentido da pista (eixo v = altura do canvas).
 */
function weather(g: CanvasRenderingContext2D, w: number, h: number, seed: number, rubber: number) {
  const rand = mulberry32(seed);
  const img = g.getImageData(0, 0, w, h);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (rand() - 0.5) * 34 + (rand() < 0.04 ? -40 : 0); // grão + pontinhos de agregado
    img.data[i] += n;
    img.data[i + 1] += n;
    img.data[i + 2] += n;
  }
  g.putImageData(img, 0, 0);
  for (let i = 0; i < 90; i++) {
    g.fillStyle = `rgba(70, 60, 45, ${0.03 + rand() * 0.06})`;
    g.beginPath();
    g.ellipse(rand() * w, rand() * h, 4 + rand() * w * 0.2, 6 + rand() * 30, 0, 0, Math.PI * 2);
    g.fill();
  }
  for (let i = 0; i < rubber; i++) {
    const x = rand() * w;
    const y = rand() * h;
    g.fillStyle = `rgba(18, 18, 20, ${0.08 + rand() * 0.22})`;
    g.fillRect(x, y, 1 + rand() * w * 0.06, 20 + rand() * h * 0.4);
  }
}

function canvasTexture(c: HTMLCanvasElement, renderer: THREE.WebGLRenderer): THREE.Texture {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  return t;
}

/**
 * Escape pintado em dois tons sobre asfalto, com sujeira e marcas de pneu de quem passou por ali. Em
 * Interlagos a maioria é verde; alguns são verde-água; na saída da Curva do Sol, vermelho com faixas brancas.
 */
function runoffTexture(renderer: THREE.WebGLRenderer, base: string, band: string, stripes = false): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 512;
  const g = c.getContext('2d')!;
  g.fillStyle = base;
  g.fillRect(0, 0, 256, 512);
  // faixa de tom diferente perto da pista
  g.fillStyle = band;
  g.fillRect(0, 0, 80, 512);
  if (stripes) {
    // faixas brancas transversais a cada 4 m (textura de 8 m)
    g.fillStyle = '#e8e6e0';
    for (const y of [0, 256]) g.fillRect(0, y, 256, 26);
  }
  weather(g, 256, 512, 11, 30);
  return canvasTexture(c, renderer);
}

/** Faixa branca da borda: tinta bem branca (como no LMU), pouco gasta, com poucas falhas. */
function lineTexture(renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 32;
  c.height = 512;
  const g = c.getContext('2d')!;
  g.fillStyle = '#f4f4f0';
  g.fillRect(0, 0, 32, 512);
  weather(g, 32, 512, 13, 2);
  const rand = mulberry32(17);
  for (let i = 0; i < 14; i++) {
    g.fillStyle = `rgba(60, 58, 55, ${0.15 + rand() * 0.25})`;
    g.fillRect(rand() * 32, rand() * 512, 2 + rand() * 6, 1 + rand() * 5);
  }
  return canvasTexture(c, renderer);
}

/** Zebra: blocos de tinta (cores alternadas, 3 m cada) gastos e com borracha das rodas que sobem nela. */
function kerbTexture(colors: string[], renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 512;
  const g = c.getContext('2d')!;
  const h = 512 / colors.length;
  colors.forEach((col, i) => {
    g.fillStyle = col;
    g.fillRect(0, i * h, 64, h);
    // junta entre blocos
    g.fillStyle = 'rgba(30, 30, 30, 0.5)';
    g.fillRect(0, i * h, 64, 2);
  });
  weather(g, 64, 512, 19, 40);
  return canvasTexture(c, renderer);
}

/** Pórtico de largada sobre a linha de chegada, com o semáforo (5 luzes) e um painel. */
function buildStartGantry(track: Track, group: THREE.Group) {
  const s0 = track.samples[0];
  const mat = new THREE.MeshStandardMaterial({ color: 0x2b2e33, metalness: 0.5, roughness: 0.5 });
  const g = new THREE.Group();
  const span = s0.wl + s0.wr + 4;
  const h = 6.5;
  for (const x of [-span / 2, span / 2]) {
    const pole = new THREE.Mesh(new THREE.BoxGeometry(0.4, h, 0.4), mat);
    pole.position.set(x, h / 2, 0);
    g.add(pole);
  }
  const beam = new THREE.Mesh(new THREE.BoxGeometry(span, 0.6, 0.5), mat);
  beam.position.set(0, h, 0);
  g.add(beam);
  const lights = new THREE.Mesh(new THREE.BoxGeometry(3.2, 0.8, 0.35), new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.4 }));
  lights.position.set(0, h - 0.7, 0.1);
  g.add(lights);
  for (let k = 0; k < 5; k++) {
    const led = new THREE.Mesh(new THREE.CircleGeometry(0.18, 16), new THREE.MeshStandardMaterial({ color: 0x2a0000, emissive: 0x330000 }));
    led.position.set(-1.2 + k * 0.6, h - 0.7, 0.29);
    g.add(led);
  }
  g.traverse(o => (o.castShadow = true));
  // centralizado na pista, de frente para quem chega
  g.position.copy(s0.p).addScaledVector(s0.r, (s0.wr - s0.wl) / 2);
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(new THREE.Vector3(s0.r.x, 0, s0.r.z).normalize(), new THREE.Vector3(0, 1, 0), new THREE.Vector3(-s0.t.x, 0, -s0.t.z).normalize()) /* em pé, mesmo com camber */);
  group.add(g);
}

export function buildTrack(track: Track, scene: THREE.Scene, renderer: THREE.WebGLRenderer, quality: Quality) {
  setHiRes(quality.extreme);
  const S = track.samples;
  const group = new THREE.Group();
  const mesh = (g: THREE.BufferGeometry, m: THREE.Material, shadow = true) => {
    const o = new THREE.Mesh(g, m);
    o.receiveShadow = shadow;
    group.add(o);
    return o;
  };

  // asfalto de autódromo (textura de 4 m)
  const asphaltNormal = phTexture('asphalt_track', 'nor_gl', renderer);
  const asphaltArm = phTexture('asphalt_track', 'arm', renderer);
  const asphalt = pbr('asphalt_track', renderer, { color: 0xffffff });
  // asfalto de Interlagos no LMU: cinza-amarronzado médio (~RGB 130/115/92), não cinza neutro. A textura
  // sozinha fica quase preta: clareia e esquenta mantendo o grão, lida também numa segunda escala (a repetição
  // de 4 m some) e com manchas de tom de 20–50 m em coordenadas de mundo: trechos recapeados mais escuros e
  // menos marrons, trechos velhos mais claros e desbotados. Borracha e remendos escurecem por cima.
  asphalt.onBeforeCompile = shader => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec2 vGround;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvGround = (modelMatrix * vec4(transformed, 1.0)).xz;');
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        varying vec2 vGround;
        float aHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float aNoise(vec2 p) {
          vec2 i = floor(p), f = fract(p);
          f = f * f * (3.0 - 2.0 * f);
          return mix(mix(aHash(i), aHash(i + vec2(1, 0)), f.x), mix(aHash(i + vec2(0, 1)), aHash(i + vec2(1, 1)), f.x), f.y);
        }`
      )
      .replace(
        '#include <map_fragment>',
        `#include <map_fragment>
        diffuseColor.rgb = mix(diffuseColor.rgb, texture2D(map, vMapUv * 0.23 + 0.41).rgb, 0.4);
        diffuseColor.rgb = diffuseColor.rgb * vec3(1.22, 1.0, 0.66) + vec3(0.035, 0.026, 0.014);
        vec2 gp = vGround;
        float big = aNoise(gp / 45.0) * 0.65 + aNoise(gp / 18.0 + 13.0) * 0.35;
        float newer = smoothstep(0.6, 0.68, big);
        float older = smoothstep(0.36, 0.28, big);
        diffuseColor.rgb *= mix(vec3(1.0), vec3(0.64, 0.65, 0.7), newer);
        diffuseColor.rgb *= mix(vec3(1.0), vec3(1.18, 1.16, 1.13), older);
        diffuseColor.rgb *= 0.92 + 0.16 * aNoise(gp / 7.0 + 3.0);`
      );
  };
  mesh(ribbon(track, i => -S[i].wl, i => S[i].wr, 0, 4, 4), asphalt);
  /** tinta sobre o asfalto: a textura de cor pintada + o relevo e a rugosidade do asfalto por baixo */
  const paintOn = (map: THREE.Texture, offset: number, roughness = 1) =>
    new THREE.MeshStandardMaterial({
      map,
      normalMap: asphaltNormal,
      normalScale: new THREE.Vector2(0.6, 0.6),
      roughnessMap: asphaltArm,
      roughness,
      polygonOffset: true,
      polygonOffsetFactor: offset
    });

  // faixas brancas nas bordas
  const white = paintOn(lineTexture(renderer), -2, 0.8);
  // largas como no LMU (~35 cm), por dentro da borda do asfalto
  mesh(ribbon(track, i => -S[i].wl, i => -S[i].wl + 0.35, 0.004, 0, 10), white);
  mesh(ribbon(track, i => S[i].wr - 0.35, i => S[i].wr, 0.004, 0, 10), white);

  // zebras de Interlagos nas cores do Brasil: amarelo, verde, branco, verde (blocos de 1,5 m), levemente elevadas
  // Laguna (LMU): vermelho e branco, blocos de 1,5 m
  const kerbMat = paintOn(kerbTexture(['#c41e24', '#eeede8', '#c41e24', '#eeede8'], renderer), 0, 0.75);
  // largura por lado: a de fora alarga na saída das curvas
  mesh(ribbon(track, i => -S[i].wl - S[i].kerbL, i => -S[i].wl, 0.012, 0, 6, i => S[i].kerbL > 0), kerbMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wr + S[i].kerbR, 0.012, 0, 6, i => S[i].kerbR > 0), kerbMat);

  // escapes asfaltados pintados: verde (a maioria), verde-água (Ferradura/Laranjinha e Junção/Café) e
  // vermelho com faixas brancas na saída da Curva do Sol, por fora
  // Laguna (LMU): faixa verde pintada logo atrás da zebra/borda
  const runMats = { verde: paintOn(runoffTexture(renderer, '#2e8a4c', '#2a7f46'), -1) };
  const runColor = (_i: number, _side: -1 | 1): keyof typeof runMats => 'verde';
  // pintura verde larga e contínua por dentro (LMU): Andretti, T8, Rainey (esquerdas) e T10 (direita).
  // Só visual: a física continua com 2,5 m de escape asfaltado (maxRunoff) e brita/grama depois.
  const WIDE: [number, number, -1 | 1, number][] = [[430, 600, -1, 4.5], [2425, 2470, -1, 3.5], [2600, 2800, -1, 4.0], [2925, 3060, 1, 4.0]];
  const kL = track.length / 3598;
  const wideAt = (i: number, side: -1 | 1) => {
    const sm = S[i].s / kL;
    let w = 0;
    for (const [a, b, sd, ww] of WIDE) {
      if (sd !== side || sm < a - 12 || sm > b + 12) continue;
      w = Math.max(w, ww * Math.min(1, (sm - (a - 12)) / 12, ((b + 12) - sm) / 12));
    }
    const wall = (side < 0 ? S[i].wallL - S[i].wl - S[i].kerbL : S[i].wallR - S[i].wr - S[i].kerbR) - 1;
    return Math.max(0, Math.min(w, wall));
  };
  mesh(ribbon(track, i => -S[i].wl - S[i].kerbL - wideAt(i, -1), i => -S[i].wl - S[i].kerbL, -0.006, 4, 8, i => wideAt(i, -1) > 0.05), runMats.verde);
  mesh(ribbon(track, i => S[i].wr + S[i].kerbR, i => S[i].wr + S[i].kerbR + wideAt(i, 1), -0.006, 4, 8, i => wideAt(i, 1) > 0.05), runMats.verde);
  for (const c of Object.keys(runMats) as (keyof typeof runMats)[]) {
    mesh(ribbon(track, i => -S[i].wl - S[i].kerbL - S[i].runL, i => -S[i].wl - S[i].kerbL, -0.008, 4, 8, i => S[i].runL > 0 && runColor(i, -1) === c), runMats[c]);
    mesh(ribbon(track, i => S[i].wr + S[i].kerbR, i => S[i].wr + S[i].kerbR + S[i].runR, -0.008, 4, 8, i => S[i].runR > 0 && runColor(i, 1) === c), runMats[c]);
  }

  // grama da borda até o muro: verde e seca misturadas como nas fotos
  // da borda até o muro: brita/areia bege onde o satélite mostra areia, mato seco no resto
  const grassMat = terrainMaterial(renderer);
  const sandMat = new THREE.MeshStandardMaterial({ name: 'brita', color: 0xcdb487, roughness: 1 });
  const sandL = (i: number) => (surfaces.sandL[i] ?? 1) >= 0.5;
  const sandR = (i: number) => (surfaces.sandR[i] ?? 1) >= 0.5;
  // vizinhas incluídas nas pontas para os trechos emendarem sem buraco
  const near = (f: (i: number) => boolean, want: boolean) => (i: number) =>
    f(i) === want || f((i + 1) % S.length) === want || f((i - 1 + S.length) % S.length) === want;
  mesh(ribbon(track, i => -S[i].wallL - 1, i => -S[i].wl, -0.03, 6, 6, near(sandL, false)), grassMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wallR + 1, -0.03, 6, 6, near(sandR, false)), grassMat);
  mesh(ribbon(track, i => -S[i].wallL - 1, i => -S[i].wl, -0.025, 6, 6, near(sandL, true)), sandMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wallR + 1, -0.025, 6, 6, near(sandR, true)), sandMat);

  const concrete = pbr('concrete_wall_008', renderer, { color: 0xe4e2dc, side: THREE.DoubleSide });
  // Mínimo (celular fraco): só o que ajuda a pilotar — pista, muros, boxes, grid, terreno e placas de freada
  const full = !quality.minimal;
  buildBarriers(track, group, renderer, concrete);
  if (full) buildStands(track, group, renderer, concrete);
  buildPits(track, group, renderer, asphalt);
  if (full) {
    buildBanners(track, group, renderer);
    buildMarshalPosts(track, group);
    buildCornerDetails(track, group);
    buildPatches(track, group, renderer);
  }
  buildGrid(track, group, renderer);
  buildBridge(track, group, renderer);

  // linha de chegada quadriculada em s = 0
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 8;
  const g2 = c.getContext('2d')!;
  for (let x = 0; x < 16; x++) for (let y = 0; y < 2; y++) {
    g2.fillStyle = (x + y) % 2 ? '#111' : '#f4f4f4';
    g2.fillRect(x * 4, y * 4, 4, 4);
  }
  const chk = new THREE.CanvasTexture(c);
  chk.magFilter = THREE.NearestFilter;
  chk.colorSpace = THREE.SRGBColorSpace;
  const s0 = S[0];
  const line = new THREE.Mesh(
    new THREE.PlaneGeometry(s0.wl + s0.wr, 1.2),
    new THREE.MeshStandardMaterial({ map: chk, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -4 })
  );
  line.position.copy(s0.p).addScaledVector(s0.r, (s0.wr - s0.wl) / 2).addScaledVector(s0.n, 0.006);
  line.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s0.r, s0.t.clone().negate(), s0.n));
  line.receiveShadow = true;
  group.add(line);
  buildStartGantry(track, group);

  const heightAt = buildTerrain(track, group, grassMat);
  // pit lane real (OSM) com a separação pintada verde/branca do lado da pista
  {
    const c = document.createElement('canvas');
    c.width = 64;
    c.height = 256;
    const g = c.getContext('2d')!;
    g.fillStyle = '#2e8a4c';
    g.fillRect(0, 0, 64, 256);
    g.fillStyle = '#eeede8';
    for (let y = -64; y < 256; y += 32) {
      g.beginPath();
      g.moveTo(0, y);
      g.lineTo(64, y + 40);
      g.lineTo(64, y + 52);
      g.lineTo(0, y + 12);
      g.fill();
    }
    weather(g, 64, 256, 31, 6);
    buildPitLane(track, group, asphalt, white, paintOn(canvasTexture(c, renderer), -2), concrete, heightAt);
  }
  const floorY = group.userData.floorY as number;
  if (full) {
    const ring = buildTowers(track, group, heightAt, floorY);
    buildHorizon(group, ring.center, floorY, HAZE);
    buildScenery(track, group, heightAt, renderer, quality.extreme);
    buildPaddock(track, group, heightAt);
  }
  buildExtras(track, group, heightAt);
  if (full) buildOsmScenery(osm as unknown as OsmData, track, group, heightAt, renderer, quality.extreme);
  scene.add(group);
}

/**
 * Grade SRTM (data/tracks/interlagos-terrain.json) suavizada e alinhada à altura da pista: devolve a altura do
 * relevo real em coordenadas do jogo. O alinhamento usa a mediana da diferença ao longo do traçado.
 */
function srtmGrid(S: Track['samples']): (x: number, z: number) => number {
  const T = terrain as { x0: number; z0: number; step: number; nx: number; nz: number; h: number[] };
  const { x0, z0, step, nx, nz } = T;
  const at = (i: number, j: number) => T.h[Math.max(0, Math.min(nz - 1, j)) * nx + Math.max(0, Math.min(nx - 1, i))];
  // suavização 3x3 (tira o "ruído" de prédios e copas que o satélite mede)
  const sm = new Float32Array(nx * nz);
  for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
    let a = 0;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) a += at(i + di, j + dj) * (di || dj ? 1 : 2);
    sm[j * nx + i] = a / 10;
  }
  const raw = (x: number, z: number) => {
    const fx = Math.max(0, Math.min(nx - 1.001, (x - x0) / step));
    const fz = Math.max(0, Math.min(nz - 1.001, (z - z0) / step));
    const i = Math.floor(fx);
    const j = Math.floor(fz);
    const u = fx - i;
    const v = fz - j;
    const g = (a: number, b: number) => sm[b * nx + a];
    return (g(i, j) * (1 - u) + g(i + 1, j) * u) * (1 - v) + (g(i, j + 1) * (1 - u) + g(i + 1, j + 1) * u) * v;
  };
  const diffs = S.filter((_, k) => k % 5 === 0).map(s => raw(s.p.x, s.p.z) - s.p.y).sort((a, b) => a - b);
  const offset = diffs[Math.floor(diffs.length / 2)];
  return (x, z) => raw(x, z) - offset;
}

/** Terreno em grade: perto da pista segue a altura dela (um pouco abaixo, para não furar); longe, o relevo real. */
function buildTerrain(track: Track, group: THREE.Group, grassMat: THREE.MeshStandardMaterial): (x: number, z: number) => number {
  const S = track.samples;
  const box = new THREE.Box3();
  S.forEach(s => box.expandByPoint(s.p));
  box.expandByScalar(700);
  const cell = 12;
  const nx = Math.ceil((box.max.x - box.min.x) / cell);
  const nz = Math.ceil((box.max.z - box.min.z) / cell);
  // índice rápido por grade grossa
  const coarse = 40;
  const buckets = new Map<string, number[]>();
  S.forEach((s, i) => {
    if (i % 3) return;
    const k = `${Math.floor(s.p.x / coarse)},${Math.floor(s.p.z / coarse)}`;
    if (!buckets.has(k)) buckets.set(k, []);
    buckets.get(k)!.push(i);
  });
  const gridAt = srtmGrid(S);
  const heightAt = (x: number, z: number) => {
    // trecho de pista mais próximo (até ~160 m)
    const cx = Math.floor(x / coarse);
    const cz = Math.floor(z / coarse);
    let best = Infinity;
    let h = 0;
    let bk = -1;
    for (let i = -4; i <= 4; i++) for (let j = -4; j <= 4; j++) {
      for (const k of buckets.get(`${cx + i},${cz + j}`) ?? []) {
        const p = S[k].p;
        const d2 = (p.x - x) ** 2 + (p.z - z) ** 2;
        if (d2 < best) {
          best = d2;
          h = p.y;
          bk = k;
        }
      }
    }
    if (bk >= 0) {
      // camber: o chão perto da pista segue o plano inclinado dela (até o muro + 2 m)
      const s = S[bk];
      const rh = Math.hypot(s.r.x, s.r.z);
      const lat = ((x - s.p.x) * s.r.x + (z - s.p.z) * s.r.z) / rh;
      const lim = (lat < 0 ? s.wallL : s.wallR) + 2;
      h += (s.r.y / rh) * Math.max(-lim, Math.min(lim, lat));
    }
    // relevo real (SRTM) longe da pista; perto dela, a altura da própria pista (os cortes e aterros da pista
    // não aparecem no satélite de 30 m)
    const g = gridAt(x, z);
    if (best === Infinity) return g - 0.6;
    const d = Math.sqrt(best);
    const far = Math.max(0, Math.min(1, (d - 20) / 90));
    return h * (1 - far) + g * far - 0.6 - Math.min(1.5, d * 0.01);
  };
  const geo = new THREE.PlaneGeometry(nx * cell, nz * cell, nx, nz);
  geo.rotateX(-Math.PI / 2);
  geo.translate((box.min.x + box.max.x) / 2, 0, (box.min.z + box.max.z) / 2);
  const pos = geo.attributes.position as THREE.BufferAttribute;
  for (let i = 0; i < pos.count; i++) pos.setY(i, heightAt(pos.getX(i), pos.getZ(i)));
  // uv em metros (grama repete a cada 6 m)
  const uv = geo.attributes.uv as THREE.BufferAttribute;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, pos.getX(i) / 6, pos.getZ(i) / 6);
  geo.computeVertexNormals();
  const terrain = new THREE.Mesh(geo, grassMat);
  terrain.receiveShadow = true;
  group.add(terrain);

  // chão distante até o horizonte (some na neblina; material simples sem noise/texturas por pixel)
  let minY = Infinity;
  for (let i = 0; i < pos.count; i++) minY = Math.min(minY, pos.getY(i));
  const farGeo = new THREE.PlaneGeometry(12000, 12000);
  const farMat = new THREE.MeshStandardMaterial({ color: 0x9a8858, roughness: 0.95, metalness: 0 }); // palha seca
  const far = new THREE.Mesh(farGeo, farMat);
  far.rotation.x = -Math.PI / 2;
  far.position.set((box.min.x + box.max.x) / 2, minY - 2, (box.min.z + box.max.z) / 2);
  group.add(far);
  group.userData.floorY = minY - 2;
  return heightAt;
}

/** o ponto está dentro do polígono? (par-ímpar) */
function insidePoly(x: number, z: number, poly: [number, number][]) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i];
    const [xj, zj] = poly[j];
    if (zi > z !== zj > z && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) c = !c;
  }
  return c;
}

/**
 * Mata fora dos muros (impostores), além da mata e das fileiras reais do OSM. Em Interlagos as árvores formam
 * capões fechados e altos (8–15 m), não árvores soltas tipo savana: cada ponto sorteado vira um grupo de 5–14
 * árvores, mais denso no miolo da pista (atrás do Laranjinha/Pinheirinho) e longe da reta dos boxes.
 */
function buildScenery(
  track: Track,
  group: THREE.Group,
  heightAt: (x: number, z: number) => number,
  renderer: THREE.WebGLRenderer,
  extreme: boolean
) {
  const S = track.samples;
  const rand = mulberry32(7);
  const p = new THREE.Vector3();
  const tmp = new THREE.Vector3();
  const spots: TreeSpot[] = [];
  const water = (osm as unknown as OsmData).water;
  // miolo da pista: dentro do polígono do traçado
  const loop = S.filter((_, i) => i % 4 === 0).map(s => [s.p.x, s.p.z] as [number, number]);
  const free = (x: number, z: number, y: number) => {
    const loc = track.locate(tmp.set(x, y, z));
    // não plantar em cima da pista nem colado no muro (o carro passa a 3–4 m)
    if (loc && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + 7) return false;
    // nem em arquibancada, pit lane, garagens ou no lago
    if (occupied(track, x, z, y)) return false;
    return !water.some(w => insidePoly(x, z, w));
  };
  // Laguna (LMU): carvalhos irregulares. Pontos sorteados na área toda e aceitos por um campo de ruído (grupos
  // soltos, nada de fileira ao longo do muro), mais densos nos morros da T6, do Corkscrew e da Rainey e nas
  // manchas de mata do OSM (osm.woods); tamanhos bem variados e alguns carvalhos grandes isolados.
  const hash = (x: number, z: number) => {
    const h = Math.sin(x * 127.1 + z * 311.7) * 43758.5453;
    return h - Math.floor(h);
  };
  const vnoise = (x: number, z: number) => {
    const ix = Math.floor(x), iz = Math.floor(z);
    const fx = x - ix, fz = z - iz;
    const ux = fx * fx * (3 - 2 * fx), uz = fz * fz * (3 - 2 * fz);
    const a = hash(ix, iz), b = hash(ix + 1, iz), c = hash(ix, iz + 1), d = hash(ix + 1, iz + 1);
    return (a * (1 - ux) + b * ux) * (1 - uz) + (c * (1 - ux) + d * ux) * uz;
  };
  const woods = ((osm as unknown as { woods?: [number, number][][] }).woods ?? []);
  const DENSE: [number, number][] = [[1840, 2020], [2360, 2570], [2590, 2830]];
  const kD = track.length / 3598;
  const near = S.filter((_, i) => i % 4 === 0);
  const box = new THREE.Box3();
  S.forEach(s => box.expandByPoint(s.p));
  box.expandByScalar(260);
  const MAX = 3400;
  for (let tries = 0; tries < 90000 && spots.length < MAX; tries++) {
    const x = box.min.x + rand() * (box.max.x - box.min.x);
    const z = box.min.z + rand() * (box.max.z - box.min.z);
    // amostra de pista mais próxima (a cada 8 m)
    let bd = Infinity;
    let bs = near[0];
    for (const s of near) {
      const d2 = (s.p.x - x) ** 2 + (s.p.z - z) ** 2;
      if (d2 < bd) { bd = d2; bs = s; }
    }
    const dist = Math.sqrt(bd);
    if (dist > 250 || bs.s > track.length - 270 || bs.s < 120) continue;
    const sm = bs.s / kD;
    const dense = DENSE.some(([a, b]) => sm > a && sm < b);
    const inWood = woods.some(poly => insidePoly(x, z, poly));
    // grupos soltos: ruído em ~45 m e ~12 m
    const n = vnoise(x / 45, z / 45) * 0.7 + vnoise(x / 12 + 7.3, z / 12 + 1.9) * 0.3;
    const want = inWood ? 0.42 : dense ? 0.5 : 0.62;
    const p0 = inWood ? 0.55 : dense ? 0.4 : 0.12;
    if (n < want || rand() > p0 * (dist < 60 ? 0.7 : 1)) continue;
    if (!free(x, z, bs.p.y)) continue;
    const giant = rand() < 0.07;
    const scale = giant ? 3.4 + rand() * 1.4 : 1.3 + Math.pow(rand(), 1.6) * 2.4;
    spots.push({ x, y: heightAt(x, z) - 0.2, z, scale, yaw: rand() * Math.PI * 2 });
  }
  plantTrees(spots, group, renderer, extreme, rand);
}

/**
 * Paddock cheio como no LMU (T2/T3 e atrás dos boxes): tendas brancas, carretas das equipes e dois guindastes,
 * nas áreas asfaltadas do OSM perto da pista (estacionamentos e paddock). Tudo em InstancedMesh (o exportador
 * assa e junta por região de 250 m): poucas chamadas de desenho. Só a partir do Leve.
 */
function buildPaddock(track: Track, group: THREE.Group, heightAt: (x: number, z: number) => number) {
  const S = track.samples;
  const rand = mulberry32(391);
  const tmp = new THREE.Vector3();
  const polys = ((osm as unknown as { paved?: [number, number][][] }).paved ?? []).filter(poly => {
    const cx = poly.reduce((a, q) => a + q[0], 0) / poly.length;
    const cz = poly.reduce((a, q) => a + q[1], 0) / poly.length;
    // (o locate do web só acha a pista até ~48 m; aqui vale a amostra mais próxima)
    let best = Infinity;
    for (let i = 0; i < S.length; i += 4) best = Math.min(best, (S[i].p.x - cx) ** 2 + (S[i].p.z - cz) ** 2);
    return Math.sqrt(best) < 260;
  });
  const free = (x: number, z: number) => {
    const loc = track.locate(tmp.set(x, heightAt(x, z), z));
    if (loc && Math.abs(loc.d) < (loc.d < 0 ? loc.wallL : loc.wallR) + 8) return false;
    return !occupied(track, x, z, tmp.y);
  };
  const UP = new THREE.Vector3(0, 1, 0);
  const tentBody = new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0);
  const tentRoof = new THREE.ConeGeometry(0.72, 1, 4, 1).rotateY(Math.PI / 4).translate(0, 0.5, 0);
  const box = new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0);
  const white = new THREE.MeshStandardMaterial({ color: 0xf2f2ee, roughness: 0.8 });
  const truckMat = new THREE.MeshStandardMaterial({ roughness: 0.5, metalness: 0.2, vertexColors: true });
  const MAXT = 260;
  const bodies = new THREE.InstancedMesh(tentBody, white, MAXT);
  const roofs = new THREE.InstancedMesh(tentRoof, white, MAXT);
  const trailers = new THREE.InstancedMesh(box, truckMat, 120);
  const cabs = new THREE.InstancedMesh(box, truckMat, 120);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const col = new THREE.Color();
  const TRUCK = ['#f4f4f2', '#f4f4f2', '#1d1d1f', '#c8102e', '#14306b', '#8a8f96'];
  let nt = 0;
  let nk = 0;
  const inside = (x: number, z: number, poly: [number, number][]) => insidePoly(x, z, poly);
  // cota de tendas e carretas por área, na proporção do tamanho (senão as primeiras da lista levam tudo)
  const polyArea = (poly: [number, number][]) => {
    let a = 0;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) a += poly[j][0] * poly[i][1] - poly[i][0] * poly[j][1];
    return Math.abs(a) / 2;
  };
  const total = polys.reduce((a, poly) => a + polyArea(poly), 0) || 1;
  for (const poly of polys) {
    const share = polyArea(poly) / total;
    const capT = nt + Math.ceil(MAXT * share);
    const capK = nk + Math.ceil(120 * share);
    const nt0 = nt;
    const nk0 = nk;
    const xs = poly.map(v => v[0]);
    const zs = poly.map(v => v[1]);
    const [x0, x1, z0, z1] = [Math.min(...xs), Math.max(...xs), Math.min(...zs), Math.max(...zs)];
    const area = (x1 - x0) * (z1 - z0);
    const tries = Math.min(900, Math.round(area / 90));
    for (let k = 0; k < tries; k++) {
      const x = x0 + rand() * (x1 - x0);
      const z = z0 + rand() * (z1 - z0);
      if (!inside(x, z, poly) || !free(x, z)) continue;
      const y = heightAt(x, z) - 0.1;
      const yaw = Math.round(rand() * 4) * (Math.PI / 2) + (rand() - 0.5) * 0.1;
      q.setFromAxisAngle(UP, yaw);
      if (nt >= Math.min(MAXT, capT) && nk >= Math.min(120, capK)) break;
      if (rand() < 0.62 && nt < Math.min(MAXT, capT)) {
        // tenda branca 3–8 m, às vezes em fileira de 2–3
        const w = 3 + rand() * 5;
        const n = rand() < 0.4 ? 2 + Math.floor(rand() * 2) : 1;
        for (let j = 0; j < n && nt < Math.min(MAXT, capT); j++) {
          const ox = x + Math.cos(yaw) * j * (w + 0.4);
          const oz = z - Math.sin(yaw) * j * (w + 0.4);
          m.compose(new THREE.Vector3(ox, y, oz), q, new THREE.Vector3(w, 2.4, w));
          bodies.setMatrixAt(nt, m);
          m.compose(new THREE.Vector3(ox, y + 2.4, oz), q, new THREE.Vector3(w, 1.4, w));
          roofs.setMatrixAt(nt, m);
          nt++;
        }
      } else if (nk < Math.min(120, capK)) {
        // carreta de equipe (13,6 m) com cavalo mecânico, cor da equipe
        col.set(TRUCK[Math.floor(rand() * TRUCK.length)]);
        const dir = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
        m.compose(new THREE.Vector3(x, y + 0.4, z), q, new THREE.Vector3(2.5, 3.6, 13.6));
        trailers.setMatrixAt(nk, m);
        trailers.setColorAt(nk, col);
        const c2 = new THREE.Vector3(x, y + 0.3, z).addScaledVector(dir, 8.6);
        m.compose(c2, q, new THREE.Vector3(2.5, 3.2, 3));
        cabs.setMatrixAt(nk, m);
        cabs.setColorAt(nk, col.multiplyScalar(0.85));
        nk++;
      }
    }
    {
      const cx = poly.reduce((acc, v) => acc + v[0], 0) / poly.length;
      const cz = poly.reduce((acc, v) => acc + v[1], 0) / poly.length;
      console.info('paddock área ' + Math.round(polyArea(poly)) + ' m² em (' + Math.round(cx) + ', ' + Math.round(cz) + '): ' + (nt - nt0) + ' tendas, ' + (nk - nk0) + ' carretas');
    }
  }
  bodies.count = roofs.count = nt;
  trailers.count = cabs.count = nk;
  for (const im of [bodies, roofs, trailers, cabs]) {
    im.instanceMatrix.needsUpdate = true;
    im.castShadow = true;
    group.add(im);
  }
  // dois guindastes amarelos (vistos no LMU atrás da T3)
  const yellow = new THREE.MeshStandardMaterial({ color: 0xf2c200, roughness: 0.6, metalness: 0.3 });
  let cranes = 0;
  for (const poly of polys) {
    if (cranes >= 2) break;
    const cx = poly.reduce((a, v) => a + v[0], 0) / poly.length;
    const cz = poly.reduce((a, v) => a + v[1], 0) / poly.length;
    if (!free(cx, cz)) continue;
    const y = heightAt(cx, cz);
    const g = new THREE.Group();
    const base = new THREE.Mesh(new THREE.BoxGeometry(3, 2.5, 8), yellow);
    base.position.y = 1.25;
    const boom = new THREE.Mesh(new THREE.BoxGeometry(0.8, 26, 0.8), yellow);
    boom.position.set(0, 13, -3);
    boom.rotation.x = -0.45;
    g.add(base, boom);
    g.position.set(cx, y, cz);
    g.rotation.y = rand() * Math.PI * 2;
    g.traverse(o => (o.castShadow = true));
    group.add(g);
    cranes++;
  }
  console.info('paddock: ' + nt + ' tendas, ' + nk + ' carretas, ' + cranes + ' guindastes em ' + polys.length + ' áreas');
}

/**
 * Pit lane de Laguna inteira, do OSM (osm.pitLane, conferida no satélite): entrada depois da T10, faixa dos boxes à
 * esquerda da reta e saída por dentro da Andretti, onde se junta à pista (LMU). Asfalto da pista, faixa branca do
 * lado de fora, separação pintada verde/branca do lado da pista e os muros do OSM colados nela (muro dos boxes).
 * Só visual (a física não tem pit lane). Na altura do plano da pista (com o camber), acima da brita/grama dela.
 */
function buildPitLane(
  track: Track, group: THREE.Group, asphalt: THREE.Material, white: THREE.Material, hatch: THREE.Material,
  concrete: THREE.Material, heightAt: (x: number, z: number) => number
) {
  const S = track.samples;
  const data = osm as unknown as { pitLane?: [number, number][][]; walls?: [number, number][][] };
  const line0 = data.pitLane?.[0];
  if (!line0 || line0.length < 2) return;
  // densifica a cada 2 m e suaviza (Chaikin) para tirar os cantos do OSM
  let pts: [number, number][] = [];
  for (let k = 1; k < line0.length; k++) {
    const [ax, az] = line0[k - 1];
    const [bx, bz] = line0[k];
    const n = Math.max(1, Math.ceil(Math.hypot(bx - ax, bz - az) / 2));
    for (let j = 0; j < n; j++) pts.push([ax + ((bx - ax) * j) / n, az + ((bz - az) * j) / n]);
  }
  pts.push(line0[line0.length - 1]);
  for (let it = 0; it < 3; it++) {
    const out: [number, number][] = [pts[0]];
    for (let k = 0; k < pts.length - 1; k++) {
      const [ax, az] = pts[k];
      const [bx, bz] = pts[k + 1];
      out.push([ax * 0.75 + bx * 0.25, az * 0.75 + bz * 0.25], [ax * 0.25 + bx * 0.75, az * 0.25 + bz * 0.75]);
    }
    out.push(pts[pts.length - 1]);
    pts = out;
  }
  // altura: plano da pista mais próxima (até 70 m), senão o terreno
  const plane = (x: number, z: number) => {
    let bd = Infinity;
    let bs = S[0];
    for (let i = 0; i < S.length; i += 2) {
      const d2 = (S[i].p.x - x) ** 2 + (S[i].p.z - z) ** 2;
      if (d2 < bd) { bd = d2; bs = S[i]; }
    }
    const rh = Math.hypot(bs.r.x, bs.r.z);
    const lat = ((x - bs.p.x) * bs.r.x + (z - bs.p.z) * bs.r.z) / rh;
    const onPlane = bs.p.y + (bs.r.y / rh) * lat;
    const d = Math.sqrt(bd);
    if (d < 45) return { y: onPlane, toTrack: [bs.p.x - x, bs.p.z - z] as [number, number], d };
    const f = Math.min(1, (d - 45) / 30);
    return { y: onPlane * (1 - f) + (heightAt(x, z) + 0.5) * f, toTrack: [bs.p.x - x, bs.p.z - z] as [number, number], d };
  };
  const N = pts.length;
  const P = pts.map(([x, z]) => ({ x, z, ...plane(x, z) }));
  // comprimento acumulado e largura: 8 m, afinando para 3 m nos 45 m das pontas (onde se junta à pista)
  const acc: number[] = [0];
  for (let k = 1; k < N; k++) acc.push(acc[k - 1] + Math.hypot(P[k].x - P[k - 1].x, P[k].z - P[k - 1].z));
  const L = acc[N - 1];
  const width = (k: number) => 3 + 5 * Math.min(1, acc[k] / 45, (L - acc[k]) / 45);
  // lateral (direita do sentido da polilinha) e de que lado fica a pista
  const lat = P.map((p, k) => {
    const a = P[Math.max(0, k - 1)];
    const b = P[Math.min(N - 1, k + 1)];
    const tx = b.x - a.x;
    const tz = b.z - a.z;
    const l = Math.hypot(tx, tz) || 1;
    const rx = -tz / l;
    const rz = tx / l;
    const trackSide = Math.sign(rx * p.toTrack[0] + rz * p.toTrack[1]) || 1;
    return { rx, rz, trackSide };
  });
  const strip = (a: (k: number) => number, b: (k: number) => number, lift: number, mat: THREE.Material, vScale: number) => {
    const pos: number[] = [];
    const uv: number[] = [];
    const idx: number[] = [];
    for (let k = 0; k < N; k++) {
      const p = P[k];
      const { rx, rz } = lat[k];
      for (const [off, u] of [[a(k), 0], [b(k), 1]] as const) {
        pos.push(p.x + rx * off, p.y + lift, p.z + rz * off);
        uv.push(u, acc[k] / vScale);
      }
      if (k > 0) {
        const base = k * 2;
        idx.push(base - 2, base - 1, base, base - 1, base + 1, base);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    // a ordem dos lados depende do sentido: garante a face para cima
    const nrm = g.getAttribute('normal') as THREE.BufferAttribute;
    if (nrm.getY(0) < 0) {
      for (let k = 0; k < idx.length; k += 3) [idx[k + 1], idx[k + 2]] = [idx[k + 2], idx[k + 1]];
      g.setIndex(idx);
      g.computeVertexNormals();
    }
    const m = new THREE.Mesh(g, mat);
    m.receiveShadow = true;
    m.userData.essential = true;
    group.add(m);
    return m;
  };
  const half = (k: number) => width(k) / 2;
  strip(k => -half(k), k => half(k), 0.03, asphalt, 4);
  // faixa branca do lado de fora (longe da pista) e a separação pintada verde/branca do lado da pista
  strip(k => -lat[k].trackSide * half(k), k => -lat[k].trackSide * (half(k) - 0.3), 0.036, white, 10);
  strip(k => lat[k].trackSide * half(k), k => lat[k].trackSide * (half(k) - 0.9), 0.036, hatch, 4);
  // muros do OSM colados na pit lane (muro dos boxes): concreto de 1,1 m
  const near = (x: number, z: number) => {
    let bd = Infinity;
    for (let k = 0; k < N; k += 3) bd = Math.min(bd, (P[k].x - x) ** 2 + (P[k].z - z) ** 2);
    return Math.sqrt(bd);
  };
  const wallPos: number[] = [];
  const wallIdx: number[] = [];
  for (const w of data.walls ?? []) {
    for (let k = 1; k < w.length; k++) {
      const [ax, az] = w[k - 1];
      const [bx, bz] = w[k];
      const mx = (ax + bx) / 2;
      const mz = (az + bz) / 2;
      if (near(mx, mz) > 7) continue;
      const ya = plane(ax, az).y;
      const yb = plane(bx, bz).y;
      const base = wallPos.length / 3;
      wallPos.push(ax, ya, az, bx, yb, bz, bx, yb + 1.1, bz, ax, ya + 1.1, az);
      wallIdx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
  }
  if (wallIdx.length) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(wallPos, 3));
    const uv: number[] = [];
    for (let k = 0; k < wallPos.length / 12; k++) uv.push(0, 0, 1, 0, 1, 0.3, 0, 0.3);
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setIndex(wallIdx);
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, concrete);
    m.castShadow = true;
    m.receiveShadow = true;
    m.userData.essential = true;
    group.add(m);
  }
  console.info('pit lane: ' + Math.round(L) + ' m, ' + wallIdx.length / 6 + ' trechos de muro');
}
