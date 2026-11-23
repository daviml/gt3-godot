// Malha da pista: asfalto, faixas brancas, zebras, grama até o muro, guard-rail, linha de chegada,
// terreno em volta seguindo a altitude, árvores e arquibancadas simples.
//
// Fase 2B etapa F: a pista é a nova (a da física, tools/tracks/interlagos/interlagos.json, com camber), o relevo é o
// do LiDAR (interlagos-terrain.json, grade de 8 m), o OSM é o da fonte própria e a referência do Garage 61 é a
// reconvertida na pista nova (data/reference/interlagos-porsche.json). Metros da pista antiga: ./sNovo.ts.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { buildExtras } from '@web/render/scenery';
import { buildBarriers, buildBridge, buildGrid, buildPatches } from '@web/render/trackDetails';
import { buildBanners, buildCornerDetails, buildMarshalPosts, buildPits, buildStands, occupied } from '@web/render/trackside';
import { buildOsmScenery, OsmData } from '@web/render/osmScenery';
import osm from '../../tracks/interlagos/interlagos-osm.json';
import terrain from '../../tracks/interlagos/interlagos-terrain.json';
import { mulberry32 } from '@web/util/random';
import type { Quality } from '@web/render/quality';
import { plantTrees, TreeSpot } from '@web/render/trees';
import { pbr, phTexture, setHiRes } from '@web/render/textures';
import { buildHorizon, buildTowers, HAZE } from '@web/render/surroundings';
import porscheRef from '../../../data/reference/interlagos-porsche.json';
import { applyLiveAsphaltUV2 } from '../liveAsphalt';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { TINTA, tintaEscura } from './tintas';
import { aplicarPerfil } from './perfil';
import { L_ANTIGO, sNovo } from './sNovo';

/**
 * Pintura da borda de Interlagos (PLANO-INTERLAGOS-DETALHES.md, Fase 1): uma tabela só com as medidas, em vez
 * de números espalhados. Onde cada uma aparece (e com que largura de faixa verde) fica no perfil lateral,
 * `data/track/visual_profile.json` (./perfil.ts, faixas "zebra", "pintura", "salsicha").
 *
 * Medidas e fonte (20/11/2026):
 * - Satélite Esri World Imagery (tiles z19, 0,27 m/px, recortes em build/interlagos/sat_zebras/, alinhados à pista):
 *   a modulação clara/escura das zebras se repete a cada 2,4–2,9 m (Curva do Sol interna 2,6 m, saída 2,4 m,
 *   S do Senna 2,9 m) e tem largura FWHM de 1,1–1,6 m nas zebras normais (com ~0,4 m de desfoque do satélite).
 *   O satélite mostra o padrão real antigo amarelo-verde-branco-verde (blocos de ~1,2 m); o LMU usa
 *   amarelo-branco-verde de 3 blocos. Nos dois o bloco verde volta a cada ~2,4 m, então o ciclo fica 2,4 m.
 * - Vídeo do LMU (quadros do atlas, projetados no chão com a câmera de comparação: 2,14 m de altura, 12° para
 *   baixo, FOV vertical 50°, escala corrigida ×0,9 pela largura do carro): zebra normal 0,9–1,0 m (s 650),
 *   zebra larga de saída 1,5–1,8 m (s 760, s 2480), bloco 0,7–0,8 m, linha branca 0,16–0,19 m (s 650, 2040,
 *   3420), vão de asfalto entre linha e zebra ~0,1 m, faixa verde atrás 0,2 m (Curva do Sol) a 1,0 m
 *   (Pinheirinho), salsicha amarela 0,4 m (Ferradura). Altura da salsicha: não dá para medir no vídeo; 6 cm.
 * - Cores: albedos de ./tintas.ts (TINTA), calibrados para dar na tela as medianas do LMU sob a luz do jogo.
 * Ordem dos blocos no sentido da volta (LMU): à esquerda amarelo → branco → verde (s 650), à direita
 * amarelo → verde → branco (s 760). A textura é a mesma; a da esquerda é lida com v invertido.
 */
export const BORDA = {
  linha: { larg: 0.18, vao: 0.1, lift: 0.008 },
  zebra: {
    larg: 1.0, // zebra normal (física 1,2 m)
    largSaida: 1.6, // zebra larga do lado de fora na saída (física 2,2 m)
    bloco: 0.8, // comprimento de cada bloco de cor
    cores: [TINTA.amarelo, TINTA.verde, TINTA.branco], // amarelo, verde, branco (ordem no sentido da volta, lado direito)
    lift: 0.015 // perfil baixo: só a tinta, sem degrau visível
  },
  faixaVerde: { cor: TINTA.verdeVivo, lift: 0.01 }, // pintura verde atrás da zebra (largura no perfil)
  salsicha: { larg: 0.4, alt: 0.06, cor: TINTA.amarelo } // "salsicha" amarela elevada
} as const;

/** largura visual da zebra a partir da largura da física (1,2 → normal; 2,2 → larga de saída) */
function kerbVisual(k: number): number {
  if (k <= 0) return 0;
  const z = BORDA.zebra;
  const t = Math.max(0, Math.min(1, (k - 1.2) / (2.2 - 1.2)));
  return z.larg + (z.largSaida - z.larg) * t;
}

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
 * Grão e sujeira são proporcionais à cor (multiplicam): as tintas são albedos escuros calibrados (./tintas.ts), e um
 * grão somado de ±17 ou uma mancha marrom por cima mudariam o tom delas (um canal em 0 só pode subir).
 */
function weather(g: CanvasRenderingContext2D, w: number, h: number, seed: number, rubber: number) {
  const rand = mulberry32(seed);
  const img = g.getImageData(0, 0, w, h);
  for (let i = 0; i < img.data.length; i += 4) {
    const f = 1 + ((rand() - 0.5) * 34 + (rand() < 0.04 ? -40 : 0)) / 230; // grão + pontinhos de agregado
    img.data[i] *= f;
    img.data[i + 1] *= f;
    img.data[i + 2] *= f;
  }
  g.putImageData(img, 0, 0);
  g.globalCompositeOperation = 'multiply';
  for (let i = 0; i < 90; i++) {
    g.fillStyle = `rgba(175, 160, 135, ${0.08 + rand() * 0.16})`;
    g.beginPath();
    g.ellipse(rand() * w, rand() * h, 4 + rand() * w * 0.2, 6 + rand() * 30, 0, 0, Math.PI * 2);
    g.fill();
  }
  g.globalCompositeOperation = 'source-over';
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
    g.fillStyle = TINTA.branco;
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
  g.fillStyle = TINTA.linha;
  g.fillRect(0, 0, 32, 512);
  weather(g, 32, 512, 13, 2);
  const rand = mulberry32(17);
  for (let i = 0; i < 14; i++) {
    g.fillStyle = `rgba(60, 58, 55, ${0.15 + rand() * 0.25})`;
    g.fillRect(rand() * 32, rand() * 512, 2 + rand() * 6, 1 + rand() * 5);
  }
  return canvasTexture(c, renderer);
}

/**
 * Zebra: um ciclo de blocos de tinta (BORDA.zebra.cores, um bloco cada) gastos e com borracha das rodas que
 * sobem nela. A textura repete a cada ciclo (vScale = blocos × BORDA.zebra.bloco). Com o flipY do canvas, v
 * crescente percorre o canvas de baixo para cima: o primeiro da lista fica embaixo (primeiro no sentido da volta).
 */
function kerbTexture(colors: readonly string[], renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 384;
  const g = c.getContext('2d')!;
  const h = c.height / colors.length;
  colors.forEach((col, i) => {
    const y = c.height - (i + 1) * h;
    g.fillStyle = col;
    g.fillRect(0, y, 64, h);
    // junta entre blocos
    g.fillStyle = 'rgba(30, 30, 30, 0.45)';
    g.fillRect(0, y, 64, 2);
  });
  weather(g, 64, c.height, 19, 5);
  return canvasTexture(c, renderer);
}

/** Tinta lisa de uma cor (faixa verde atrás da zebra, salsicha), com o mesmo desgaste das outras pinturas. */
function solidPaintTexture(color: string, seed: number, renderer: THREE.WebGLRenderer): THREE.Texture {
  const c = document.createElement('canvas');
  c.width = 32;
  c.height = 256;
  const g = c.getContext('2d')!;
  g.fillStyle = color;
  g.fillRect(0, 0, 32, 256);
  weather(g, 32, 256, seed, 4);
  return canvasTexture(c, renderer);
}

/**
 * Salsicha: perfil trapezoidal baixo (sobe no primeiro quarto, plano, desce no último quarto) entre os
 * deslocamentos a e b (a < b), em [i0, i1). 3 quadriláteros por amostra de 2 m.
 */
function sausage(
  track: Track,
  a: (i: number) => number,
  b: (i: number) => number,
  base: number,
  height: number,
  include: (i: number) => boolean
): THREE.BufferGeometry {
  const S = track.samples;
  const N = S.length;
  const pos: number[] = [];
  const uv: number[] = [];
  const idx: number[] = [];
  const v = new THREE.Vector3();
  const prof = [[0, 0], [0.25, 1], [0.75, 1], [1, 0]] as const;
  let prev = -1;
  for (let k = 0; k <= N; k++) {
    const i = k % N;
    if (!include(i)) {
      prev = -1;
      continue;
    }
    const s = S[i];
    const first = pos.length / 3;
    const a0 = a(i);
    const w = b(i) - a0;
    for (const [f, h] of prof) {
      v.copy(s.p).addScaledVector(s.r, a0 + f * w).addScaledVector(s.n, base + h * height);
      pos.push(v.x, v.y, v.z);
      uv.push(f, (k * STEP) / 4);
    }
    if (prev >= 0) for (let q = 0; q < 3; q++) idx.push(prev + q, prev + q + 1, first + q, prev + q + 1, first + q + 1, first + q);
    prev = first;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
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
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s0.r, new THREE.Vector3(0, 1, 0), s0.t.clone().negate()));
  group.add(g);
}

export function buildTrack(track: Track, scene: THREE.Scene, renderer: THREE.WebGLRenderer, quality: Quality) {
  setHiRes(quality.extreme);
  const S = track.samples;
  // larguras visuais de zebra e escape e posição das barreiras: perfil lateral (data/track/visual_profile.json,
  // ./perfil.ts). Grava kerbL/R, runL/R e wallL/R nas amostras; a física do jogo (Track.gd) não muda.
  const perfil = aplicarPerfil(track);
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
  mesh(applyLiveAsphaltUV2(ribbon(track, i => -S[i].wl, i => S[i].wr, 0, 4, 4), track, porscheRef), asphalt);
  /**
   * tinta sobre o asfalto: a textura de cor pintada + o relevo e a rugosidade do asfalto por baixo. `nome` vira
   * "pinta:<nome>" no GLB (cenario.ts), para o Godot e as ferramentas de medição saberem qual tinta é qual.
   */
  const paintOn = (map: THREE.Texture, offset: number, roughness = 1, nome = '') =>
    new THREE.MeshStandardMaterial({
      name: nome,
      map,
      normalMap: asphaltNormal,
      normalScale: new THREE.Vector2(0.6, 0.6),
      roughnessMap: asphaltArm,
      roughness,
      polygonOffset: true,
      polygonOffsetFactor: offset
    });

  // ---- borda pintada (medidas: tabela BORDA no topo do arquivo; onde há o quê: perfil lateral) ----
  const PL = perfil.L;
  const PR = perfil.R;
  // largura visual da zebra listrada (0 onde o trecho não tem zebra listrada) e da borda pintada inteira
  // (zebra + faixa verde + salsicha), que é onde começa o escape pintado
  // (classe declarada no perfil, `visual`, vale mesmo onde a física não tem zebra)
  const larguraZebra = (a: (typeof PL)[number], k: number) =>
    !a.listrada ? 0 : a.zebraVisual === 'normal' ? BORDA.zebra.larg : a.zebraVisual === 'saida' ? BORDA.zebra.largSaida : kerbVisual(k);
  const zebraL = S.map((s, i) => larguraZebra(PL[i], s.kerbL));
  const zebraR = S.map((s, i) => larguraZebra(PR[i], s.kerbR));
  const bordaL = S.map((_, i) => zebraL[i] + (PL[i].verde + PL[i].salsicha));
  const bordaR = S.map((_, i) => zebraR[i] + (PR[i].verde + PR[i].salsicha));

  // linha branca contínua nas duas bordas, por dentro do asfalto, com um vão de asfalto até a zebra (LMU)
  const white = paintOn(lineTexture(renderer), -2, 0.8, 'linha');
  const ln = BORDA.linha;
  mesh(mergeGeometries([
    ribbon(track, i => -S[i].wl + ln.vao, i => -S[i].wl + ln.vao + ln.larg, ln.lift, 0, 10),
    ribbon(track, i => S[i].wr - ln.vao - ln.larg, i => S[i].wr - ln.vao, ln.lift, 0, 10)
  ]), white);

  // zebras: amarelo / verde / branco, blocos de BORDA.zebra.bloco; a da esquerda com v invertido (ordem do LMU)
  const zb = BORDA.zebra;
  const kerbMat = paintOn(kerbTexture(zb.cores, renderer), 0, 0.75, 'zebra');
  const ciclo = zb.bloco * zb.cores.length;
  mesh(mergeGeometries([
    ribbon(track, i => -S[i].wl - zebraL[i], i => -S[i].wl, zb.lift, 0, -ciclo, i => zebraL[i] > 0),
    ribbon(track, i => S[i].wr, i => S[i].wr + zebraR[i], zb.lift, 0, ciclo, i => zebraR[i] > 0)
  ]), kerbMat);

  // faixa verde pintada atrás da zebra e salsicha amarela (faixas "pintura" e "salsicha" do perfil)
  const temL = (i: number) => PL[i].verde > 0;
  const temR = (i: number) => PR[i].verde > 0;
  const fv = BORDA.faixaVerde;
  const greenMat = paintOn(solidPaintTexture(fv.cor, 23, renderer), -1, 0.8, 'faixa_verde');
  mesh(mergeGeometries([
    ribbon(track, i => -S[i].wl - zebraL[i] - PL[i].verde, i => -S[i].wl - zebraL[i], fv.lift, 0, 8, temL),
    ribbon(track, i => S[i].wr + zebraR[i], i => S[i].wr + zebraR[i] + PR[i].verde, fv.lift, 0, 8, temR)
  ]), greenMat);
  const salL = (i: number) => PL[i].salsicha > 0;
  const salR = (i: number) => PR[i].salsicha > 0;
  const salMat = paintOn(solidPaintTexture(BORDA.salsicha.cor, 29, renderer), 0, 0.7, 'salsicha');
  const salGeos = [
    S.some((_, i) => salL(i)) && sausage(track, i => -S[i].wl - bordaL[i], i => -S[i].wl - bordaL[i] + PL[i].salsicha, zb.lift, BORDA.salsicha.alt, salL),
    S.some((_, i) => salR(i)) && sausage(track, i => S[i].wr + bordaR[i] - PR[i].salsicha, i => S[i].wr + bordaR[i], zb.lift, BORDA.salsicha.alt, salR)
  ].filter(Boolean) as THREE.BufferGeometry[];
  if (salGeos.length) mesh(mergeGeometries(salGeos), salMat);

  // escapes asfaltados pintados: verde vivo (LMU), verde-água e vermelho com faixas brancas (cores: ./tintas.ts)
  const runMats = {
    verde: paintOn(runoffTexture(renderer, TINTA.verdeVivo, tintaEscura(TINTA.verdeVivo)), -1, 1, 'escape_verde'),
    agua: paintOn(runoffTexture(renderer, TINTA.verdeAgua, tintaEscura(TINTA.verdeAgua)), -1, 1, 'escape_agua'),
    vermelho: paintOn(runoffTexture(renderer, TINTA.vermelho, tintaEscura(TINTA.vermelho), true), -1, 1, 'escape_vermelho')
  };
  const runColor = (i: number, side: -1 | 1): keyof typeof runMats => (side < 0 ? PL : PR)[i].escapeCor;
  for (const c of Object.keys(runMats) as (keyof typeof runMats)[]) {
    // o fim do escape segue a física (kerb + run); o começo encosta na borda pintada visual (mais estreita)
    mesh(ribbon(track, i => -S[i].wl - S[i].kerbL - S[i].runL, i => -S[i].wl - Math.min(bordaL[i], S[i].kerbL), -0.008, 4, 8, i => S[i].runL > 0 && runColor(i, -1) === c), runMats[c]);
    mesh(ribbon(track, i => S[i].wr + Math.min(bordaR[i], S[i].kerbR), i => S[i].wr + S[i].kerbR + S[i].runR, -0.008, 4, 8, i => S[i].runR > 0 && runColor(i, 1) === c), runMats[c]);
  }

  // grama da borda até o muro: verde e seca misturadas como nas fotos
  const grassMat = terrainMaterial(renderer);
  mesh(ribbon(track, i => -S[i].wallL - 1, i => -S[i].wl, -0.03, 6, 6), grassMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wallR + 1, -0.03, 6, 6), grassMat);

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
  buildBridge(track, group, renderer, heightAt);
  const floorY = group.userData.floorY as number;
  if (full) {
    const ring = buildTowers(track, group, heightAt, floorY);
    buildHorizon(group, ring.center, floorY, HAZE);
    buildScenery(track, group, heightAt, renderer, quality.extreme);
  }
  buildExtras(track, group, heightAt);
  if (full) buildOsmScenery(osm as unknown as OsmData, track, group, heightAt, renderer, quality.extreme);
  scene.add(group);
}

/**
 * Grade de relevo (tools/tracks/interlagos/interlagos-terrain.json: LiDAR GeoSampa a cada 8 m desde a Fase 2B; antes
 * SRTM de 40 m) suavizada e alinhada à altura da pista: devolve a altura do relevo real em coordenadas do jogo. O
 * alinhamento usa a mediana da diferença ao longo do traçado (igual ao tools/pista.ts, que faz o terrain.json).
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
    for (let i = -4; i <= 4; i++) for (let j = -4; j <= 4; j++) {
      for (const k of buckets.get(`${cx + i},${cz + j}`) ?? []) {
        const p = S[k].p;
        const d2 = (p.x - x) ** 2 + (p.z - z) ** 2;
        if (d2 < best) {
          best = d2;
          h = p.y;
        }
      }
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
  const farMat = new THREE.MeshStandardMaterial({ color: 0x758344, roughness: 0.95, metalness: 0 });
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
  const MAX = 5200;
  for (let tries = 0; tries < 9000 && spots.length < MAX; tries++) {
    const s = S[Math.floor(rand() * S.length)];
    // reta dos boxes: arquibancada e paddock, sem mata (s antigo 3734 e 120 → s novo)
    if (s.s > sNovo(L_ANTIGO - 560) || s.s < sNovo(120)) continue;
    const side = rand() < 0.5 ? -1 : 1;
    const off = (side < 0 ? s.wallL : s.wallR) + 10 + Math.pow(rand(), 1.4) * 150;
    p.copy(s.p).addScaledVector(s.r, side * off);
    const infield = insidePoly(p.x, p.z, loop);
    if (!infield && rand() < 0.35) continue;
    const k = 5 + Math.floor(rand() * (infield ? 10 : 6));
    const spread = 7 + rand() * 14;
    for (let t = 0; t < k && spots.length < MAX; t++) {
      const a = rand() * Math.PI * 2;
      const r = Math.sqrt(rand()) * spread;
      const x = p.x + Math.cos(a) * r;
      const z = p.z + Math.sin(a) * r;
      if (!free(x, z, s.p.y)) continue;
      // no chão do terreno (não na altura da pista mais próxima: em barranco a árvore flutuaria)
      spots.push({ x, y: heightAt(x, z) - 0.2, z, scale: 2.0 + rand() * 1.5, yaw: rand() * Math.PI * 2 });
    }
  }
  plantTrees(spots, group, renderer, extreme, rand);
}
