// Malha da pista: asfalto, faixas brancas, zebras, grama até o muro, guard-rail, linha de chegada,
// terreno em volta seguindo a altitude, árvores e arquibancadas simples.
import * as THREE from 'three';
import { STEP, Track } from '@web/track/track';
import { buildExtras } from '@web/render/scenery';
import { buildBarriers, buildBridge, buildGrid, buildPatches } from '@web/render/trackDetails';
import { buildBanners, buildCornerDetails, buildMarshalPosts, buildPits, buildStands, occupied } from '@web/render/trackside';
import { buildOsmScenery, OsmData } from '@web/render/osmScenery';
import osm from '../../../../gt3-time-attack/data/tracks/interlagos-osm.json';
import terrain from '../../../../gt3-time-attack/data/tracks/interlagos-terrain.json';
import { mulberry32 } from '@web/util/random';
import type { Quality } from '@web/render/quality';
import { plantTrees, TreeSpot } from '@web/render/trees';
import { pbr, phTexture, setHiRes } from '@web/render/textures';
import { buildHorizon, buildTowers, HAZE } from '@web/render/surroundings';
import porscheRef from '../../../../gt3-time-attack/data/reference/interlagos-porsche.json';
import { applyLiveAsphaltUV2 } from '../liveAsphalt';

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
  weather(g, 64, 512, 19, 15);
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
  g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(s0.r, new THREE.Vector3(0, 1, 0), s0.t.clone().negate()));
  group.add(g);
}

export function buildTrack(track: Track, scene: THREE.Scene, renderer: THREE.WebGLRenderer, quality: Quality) {
  setHiRes(quality.extreme);
  const S = track.samples;
  const k43track = track.length / 4300;
  const smooth = (a: number, b: number, x: number) => {
    const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
  };
  const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
  // Ajusta larguras visuais de escape, zebras e barreiras quadro a quadro (01..30)
  // mantendo a física intacta (Track.gd) e alinhando barreiras/escapes ao LMU.
  for (let i = 0; i < S.length; i++) {
    const sm = S[i].s / k43track;
    const oKL = S[i].kerbL;
    const oKR = S[i].kerbR;
    const oRL = S[i].runL;
    const oRR = S[i].runR;
    const oWL = S[i].wallL;
    const oWR = S[i].wallR;

    // --- Zebras extras onde faltam ---
    if (sm >= 580 && sm <= 785) S[i].kerbL = Math.max(oKL, 1.2);
    if (sm >= 1385 && sm <= 1580) S[i].kerbL = Math.max(oKL, 1.2);
    if (sm >= 1580 && sm <= 1760) S[i].kerbR = Math.max(oKR, 1.2);
    if (sm >= 2510 && sm <= 2610) S[i].kerbL = Math.max(oKL, 1.6);
    if (sm >= 2900 && sm < 2980) S[i].kerbR = Math.max(oKR, 1.4);
    if (sm >= 2980 && sm <= 3235) S[i].kerbR = Math.max(oKR, 1.6);
    if (sm >= 3235 && sm <= 3420) S[i].kerbR = Math.max(oKR, 2.0);
    if (sm >= 3550 && sm <= 3650) S[i].kerbL = Math.max(oKL, 1.4);

    // --- Lado Direito (runR e wallR) ---
    let tRR = oRR;
    let tWR = oWR;
    if (sm < 155 || sm >= 3440) {
      if (sm >= 3440 && sm < 3465) {
        const k = smooth(3440, 3465, sm);
        tRR = lerp(oRR, 1.4, k);
        tWR = lerp(oWR, S[i].wr + 1.4, k);
      } else {
        tRR = 1.4;
        tWR = S[i].wr + 1.4;
      }
    } else if (sm >= 155 && sm < 385) {
      if (sm < 255) tRR = lerp(1.2, 4.8, smooth(170, 255, sm));
      else if (sm < 305) tRR = lerp(4.8, 7.2, smooth(255, 305, sm));
      else tRR = 7.2;
      if (sm < 170) tRR = lerp(1.4, tRR, smooth(155, 170, sm));
      const tight = S[i].wr + S[i].kerbR + tRR;
      tWR = sm < 170 ? lerp(S[i].wr + 1.4, tight, smooth(155, 170, sm)) : tight;
    } else if (sm >= 385 && sm < 545) {
      tRR = sm < 530 ? lerp(7.2, 3.5, smooth(385, 530, sm)) : lerp(3.5, 0, smooth(530, 545, sm));
      const extra = lerp(0, 3.0, smooth(375, 415, sm));
      const base = S[i].wr + S[i].kerbR + tRR + extra;
      tWR = sm < 525 ? base : lerp(base, S[i].wr + 6.2, smooth(525, 545, sm));
    } else if (sm >= 545 && sm < 775) {
      tRR = 0;
      tWR = S[i].wr + 6.2;
    } else if (sm >= 775 && sm < 1150) {
      tRR = 0;
      tWR = lerp(S[i].wr + 6.2, S[i].wr + 7.0, smooth(775, 795, sm));
    } else if (sm >= 1150 && sm < 1385) {
      tRR = sm < 1365 ? 0 : lerp(0, 7.5, smooth(1365, 1385, sm));
      tWR = sm < 1365
        ? lerp(S[i].wr + 7.0, S[i].wr + 7.5, smooth(1145, 1165, sm))
        : lerp(S[i].wr + 7.5, S[i].wr + S[i].kerbR + 7.5, smooth(1365, 1385, sm));
    } else if (sm >= 1385 && sm <= 1800) {
      if (sm <= 1660) {
        tRR = 7.5;
        tWR = S[i].wr + S[i].kerbR + 7.5;
      } else if (sm <= 1760) {
        const k = smooth(1660, 1690, sm);
        tRR = lerp(7.5, 5.5, k);
        tWR = lerp(S[i].wr + S[i].kerbR + 7.5, oWR, k);
      } else {
        tRR = lerp(5.5, oRR, smooth(1760, 1800, sm));
        tWR = oWR;
      }
    } else if (sm >= 1970 && sm <= 2245) {
      const inK = smooth(1970, 1990, sm);
      const out = smooth(2180, 2245, sm);
      tRR = lerp(lerp(oRR, 1.0, inK), oRR, out);
      tWR = lerp(lerp(oWR, S[i].wr + 9.0, inK), oWR, out);
    } else if (sm >= 2255 && sm <= 2490) {
      const k = smooth(2255, 2275, sm) * (1 - smooth(2470, 2490, sm));
      tRR = lerp(oRR, 0, k);
      tWR = lerp(oWR, S[i].wr + 5.5, k);
    } else if (sm >= 2495 && sm <= 2625) {
      const k = smooth(2495, 2515, sm) * (1 - smooth(2605, 2625, sm));
      tRR = lerp(oRR, 0, k);
      tWR = lerp(oWR, S[i].wr + 9.0, k);
    } else if (sm >= 2665 && sm <= 2855) {
      const k = smooth(2665, 2685, sm) * (1 - smooth(2835, 2855, sm));
      tRR = lerp(oRR, 0.6, k);
    } else if (sm >= 2890 && sm < 3235) {
      const k = smooth(2890, 2915, sm);
      tRR = lerp(oRR, 8.2, k);
      tWR = lerp(oWR, S[i].wr + S[i].kerbR + 8.2, k);
    } else if (sm >= 3235 && sm < 3440) {
      const out = smooth(3415, 3440, sm);
      const t1 = smooth(3235, 3255, sm);
      const rrMid = lerp(8.2, 0, t1);
      const wrMid = lerp(S[i].wr + S[i].kerbR + 8.2, S[i].wr + S[i].kerbR + 2.8, t1);
      tRR = lerp(rrMid, 1.4, out);
      tWR = lerp(wrMid, S[i].wr + 1.4, out);
    }
    S[i].runR = tRR;
    S[i].wallR = tWR;

    // --- Lado Esquerdo (runL e wallL) ---
    let tRL = oRL;
    let tWL = oWL;
    if (sm < 155 || sm >= 4040) {
      tRL = 1.4;
      tWL = S[i].wl + 1.4;
    } else if (sm >= 155 && sm < 385) {
      tRL = sm < 285
        ? Math.max(oRL, 0.85)
        : sm < 305
          ? Math.max(oRL, lerp(0.85, 2.6, smooth(285, 305, sm)))
          : Math.max(oRL, 2.6);
      if (sm < 170) tRL = lerp(1.4, tRL, smooth(155, 170, sm));
      const tight = S[i].wl + S[i].kerbL + tRL;
      tWL = sm < 170 ? lerp(S[i].wl + 1.4, tight, smooth(155, 170, sm)) : tight;
    } else if (sm >= 385 && sm < 580) {
      tRL = lerp(Math.max(oRL, 2.6), 3.0, smooth(380, 395, sm));
      tWL = S[i].wl + S[i].kerbL + tRL;
    } else if (sm >= 580 && sm < 785) {
      const k = smooth(575, 595, sm);
      tRL = lerp(3.0, 0.5, k);
      tWL = lerp(S[i].wl + S[i].kerbL + 3.0, S[i].wl + 10.5, k);
    } else if (sm >= 785 && sm <= 1375) {
      const inK = smooth(780, 800, sm);
      tRL = sm < 1355 ? lerp(0.5, 0, inK) : lerp(0, 0.4, smooth(1355, 1385, sm));
      tWL = sm < 1355
        ? lerp(S[i].wl + 10.5, S[i].wl + 3.2, inK)
        : lerp(S[i].wl + 3.2, S[i].wl + 6.0, smooth(1355, 1385, sm));
    } else if (sm > 1375 && sm <= 1580) {
      tRL = 0.4;
      tWL = S[i].wl + 6.0;
    } else if (sm > 1580 && sm < 1800) {
      const inK = smooth(1580, 1610, sm);
      const outK = smooth(1775, 1800, sm);
      tRL = lerp(lerp(0.4, 0, inK), 1.8, outK);
      tWL = lerp(lerp(S[i].wl + 6.0, S[i].wl + 3.2, inK), S[i].wl + 6.5, outK);
    } else if (sm >= 1800 && sm < 2010) {
      tRL = sm < 1980 ? 1.8 : lerp(1.8, 2.2, smooth(1980, 2010, sm));
      tWL = sm < 1980 ? S[i].wl + 6.5 : lerp(S[i].wl + 6.5, S[i].wl + 6.8, smooth(1980, 2010, sm));
    } else if (sm >= 2010 && sm < 2130) {
      const k = smooth(2005, 2025, sm);
      tRL = lerp(2.2, 8.5, k);
      tWL = lerp(S[i].wl + 6.8, S[i].wl + S[i].kerbL + 8.5, k);
    } else if (sm >= 2130 && sm <= 2270) {
      const inK = smooth(2125, 2145, sm);
      const out = smooth(2245, 2270, sm);
      tRL = lerp(lerp(8.5, 1.8, inK), oRL, out);
      tWL = lerp(lerp(S[i].wl + S[i].kerbL + 8.5, S[i].wl + 6.5, inK), oWL, out);
    } else if (sm >= 2480 && sm <= 2810) {
      const k = smooth(2480, 2500, sm);
      tRL = lerp(oRL, 0, k);
      tWL = lerp(oWL, S[i].wl + S[i].kerbL + 4.5, k);
    } else if (sm > 2810 && sm < 2900) {
      const k = smooth(2810, 2830, sm) * (1 - smooth(2880, 2900, sm));
      tRL = lerp(0, 4.0, k);
      tWL = lerp(S[i].wl + S[i].kerbL + 4.5, S[i].wl + S[i].kerbL + 6.5, smooth(2810, 2830, sm));
      if (sm >= 2880) tWL = lerp(S[i].wl + S[i].kerbL + 6.5, S[i].wl + 12.0, smooth(2880, 2900, sm));
    } else if (sm >= 2900 && sm <= 3375) {
      const midK = smooth(3205, 3235, sm);
      const out = smooth(3345, 3375, sm);
      tRL = lerp(lerp(0.5, 0, midK), oRL, out);
      tWL = lerp(lerp(S[i].wl + 12.0, S[i].wl + 8.5, midK), oWL, out);
    } else if (sm >= 3500 && sm < 3540) {
      tWL = lerp(oWL, S[i].wl + 3.8, smooth(3500, 3525, sm));
    } else if (sm >= 3540 && sm < 3680) {
      const inK = smooth(3540, 3560, sm);
      const outK = smooth(3665, 3680, sm);
      tRL = lerp(0, 2.0, inK) * (1 - outK);
      tWL = lerp(lerp(S[i].wl + 3.8, S[i].wl + S[i].kerbL + 2.0, inK), S[i].wl + 2.2, outK);
    } else if (sm >= 3680 && sm < 3860) {
      tRL = 0;
      tWL = S[i].wl + 2.2;
    } else if (sm >= 3860 && sm < 4040) {
      tRL = 0;
      const openK = smooth(3860, 3915, sm);
      const joinK = smooth(4015, 4040, sm);
      tWL = lerp(lerp(S[i].wl + 2.2, S[i].wl + 9.4, openK), S[i].wl + 11.7, joinK);
    }
    S[i].runL = tRL;
    S[i].wallL = tWL;
  }
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

  // zebras de Interlagos nas cores do Brasil: amarelo vivo, verde escuro, branco (blocos de 1,5 m)
  const kerbMat = paintOn(kerbTexture(['#ffd000', '#0d5e2e', '#f0f0ea', '#0d5e2e'], renderer), 0, 0.75);
  // largura por lado: a de fora alarga na saída das curvas
  mesh(ribbon(track, i => -S[i].wl - S[i].kerbL, i => -S[i].wl, 0.012, 0, 6, i => S[i].kerbL > 0), kerbMat);
  mesh(ribbon(track, i => S[i].wr, i => S[i].wr + S[i].kerbR, 0.012, 0, 6, i => S[i].kerbR > 0), kerbMat);

  // escapes asfaltados pintados: verde escuro rico (LMU), verde-água e vermelho com faixas brancas
  const runMats = {
    verde: paintOn(runoffTexture(renderer, '#0b6b45', '#095c3b'), -1),
    agua: paintOn(runoffTexture(renderer, '#0d685c', '#0a564c'), -1),
    vermelho: paintOn(runoffTexture(renderer, '#cc1e24', '#b81a20', true), -1)
  };
  const k43 = track.length / 4300;
  const runColor = (i: number, side: -1 | 1): keyof typeof runMats => {
    const s = S[i].s / k43;
    if (side > 0 && s > 700 && s < 900) return 'vermelho';
    if ((s > 1950 && s < 2260) || (s > 3100 && s < 3450)) return 'verde';
    return 'verde';
  };
  for (const c of Object.keys(runMats) as (keyof typeof runMats)[]) {
    mesh(ribbon(track, i => -S[i].wl - S[i].kerbL - S[i].runL, i => -S[i].wl - S[i].kerbL, -0.008, 4, 8, i => S[i].runL > 0 && runColor(i, -1) === c), runMats[c]);
    mesh(ribbon(track, i => S[i].wr + S[i].kerbR, i => S[i].wr + S[i].kerbR + S[i].runR, -0.008, 4, 8, i => S[i].runR > 0 && runColor(i, 1) === c), runMats[c]);
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
    // reta dos boxes: arquibancada e paddock, sem mata
    if (s.s > track.length - 560 || s.s < 120) continue;
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
