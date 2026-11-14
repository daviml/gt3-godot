// Cópia do scripts/build-reference.ts do web, para pistas que não vêm do web (Interlagos continua lá).
// Converte uma volta exportada do Garage 61 (telemetria do iRacing, CSV a 60 Hz) na referência usada pelo
// ajuste de física (scripts/tune-physics.ts) e pela comparação no jogo.
// 1) lat/lon → coordenadas do jogo (mesma origem de data/tracks/interlagos.json)
// 2) o GPS do iRacing não bate com o OSM (até ~40 m): ajusta rotação + escala + translação para a volta
//    caber na largura da pista do jogo (scripts/ref-lib.ts)
// 3) reamostra por distância (uma linha a cada amostra da pista, 2 m): deslocamento lateral, velocidade,
//    g, pedais, marcha, rpm e o tempo em cada ponto
//
// uso (de REPOS/gt3-godot/tools): npx vite-node referencia.ts -- <pista> <volta.csv> <saida.json> "<rótulo>"
import { readFileSync, writeFileSync } from 'node:fs';
import { Vector3 } from 'three';
import { Track, TrackData } from '../../gt3-time-attack/src/track/track';
import type { Reference } from '../../gt3-time-attack/src/track/reference';
import { applyFit, fitLap, HZ, readLap } from '../../gt3-time-attack/scripts/ref-lib';

const args = process.argv.slice(2).filter(a => a !== '--');
const [trackId, inFile, outFile, label] = args;
if (!inFile || !outFile) throw new Error('uso: npx vite-node referencia.ts -- <pista> <volta.csv> <saida.json> "<rótulo>"');
const trackData = JSON.parse(readFileSync(new URL(`tracks/${trackId}/${trackId}.json`, import.meta.url), 'utf8'));
const track = new Track(trackData as TrackData);
const lap = readLap(inFile, trackData.origin);
const { n, speed, latA, longA, thr, brk, gear, rpm, steer } = lap;
const fit = fitLap(track, lap);
console.log('ajuste do GPS:', fit);
const p = new Vector3();

// ---- posição na pista de cada amostra (s contínuo ao longo da volta)
const N = track.samples.length;
const sArr: number[] = [];
const dArr: number[] = [];
let off = 0;
let last = -1;
for (let i = 0; i < n; i++) {
  const [x, z] = applyFit(fit, lap.x[i], lap.z[i]);
  const loc = track.locate(p.set(x, 0, z))!;
  let s = loc.s + off;
  if (last >= 0 && s < last - track.length / 2) { off += track.length; s += track.length; }
  sArr.push(s);
  dArr.push(loc.d);
  last = s;
}

// ---- reamostra em cada amostra da pista (2 m), começando pela primeira amostra depois do início da volta
const out: Reference = {
  label: label ?? inFile, lapTime: n / HZ, step: track.length / N,
  d: [], v: [], t: [], gLat: [], gLong: [], throttle: [], brake: [], gear: [], rpm: [], steer: []
};
for (let k = 0; k < N; k++) {
  // s da pista (0..length) → s contínuo da volta (a volta começa um pouco antes da linha)
  let s = k * out.step;
  while (s < sArr[0]) s += track.length;
  while (s > sArr[n - 1]) s -= track.length;
  let j = 0;
  while (j < n - 2 && sArr[j + 1] < s) j++;
  const u = Math.max(0, Math.min(1, (s - sArr[j]) / Math.max(1e-6, sArr[j + 1] - sArr[j])));
  const L = (a: number[]) => a[j] + (a[j + 1] - a[j]) * u;
  out.d.push(+L(dArr).toFixed(2));
  out.v.push(+L(speed).toFixed(2));
  const t = (j + u) / HZ;
  out.t.push(+(t >= out.lapTime ? t - out.lapTime : t).toFixed(3));
  out.gLat.push(+(L(latA) / 9.81).toFixed(3));
  out.gLong.push(+(L(longA) / 9.81).toFixed(3));
  out.throttle.push(+L(thr).toFixed(3));
  out.brake.push(+L(brk).toFixed(3));
  out.gear.push(gear[u < 0.5 ? j : j + 1]);
  out.rpm.push(Math.round(L(rpm)));
  out.steer.push(+L(steer).toFixed(4));
}
// emenda: o piloto cruza a linha em posições diferentes no começo e no fim da volta (metros de diferença);
// distribui o degrau nos últimos 150 m para o traçado fechar sem dobra
{
  // a emenda é onde o tempo volta a zero (pode não ser o índice 0)
  let w = 0;
  for (let k = 1; k < N; k++) if (out.t[k] < out.t[k - 1]) w = k;
  const last = (w - 1 + N) % N;
  const jump = out.d[w] - out.d[last];
  const B = Math.round(150 / out.step);
  for (let j = 0; j < B; j++) {
    const k = (w - B + j + N) % N;
    const u = 0.5 * (1 - Math.cos((Math.PI * (j + 1)) / B));
    out.d[k] = +(out.d[k] + jump * u).toFixed(2);
  }
}
writeFileSync(outFile, JSON.stringify(out));
console.log(`${N} pontos (a cada ${out.step.toFixed(2)} m), volta ${out.lapTime.toFixed(3)} s → ${outFile}`);
