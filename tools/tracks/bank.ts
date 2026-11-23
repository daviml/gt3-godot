// Inclinação lateral (camber) opcional por pista. O Track do web projeta a lateral r no plano horizontal (pista
// "reta" de lado, como Interlagos). Quando a fonte tem `bank` (rad por ponto, + = lado direito mais alto), gira r
// em torno da tangente: r' = normalize(r·cos θ + n·sen θ), n' = r' × t. O Godot (scripts/track/track.gd) faz a
// mesma conta a partir do `bank` gravado no track.json, então física e malha do cenário ficam iguais.
import { Vector3 } from 'three';
import type { Track } from '../../../gt3-time-attack/src/track/track';

/** aplica o camber às amostras (r, n) e devolve o ângulo de cada amostra; sem `bank` na fonte, não mexe em nada */
export function applyBank(track: Track, bank: number[] | undefined): number[] | null {
  if (!bank?.length) return null;
  const S = track.samples;
  const N = S.length;
  const M = bank.length;
  const out: number[] = [];
  const r = new Vector3();
  for (let i = 0; i < N; i++) {
    const x = (i / N) * M;
    const a = Math.floor(x) % M;
    const th = bank[a] + (bank[(a + 1) % M] - bank[a]) * (x - Math.floor(x));
    const s = S[i];
    r.copy(s.r).multiplyScalar(Math.cos(th)).addScaledVector(s.n, Math.sin(th)).normalize();
    s.r.copy(r);
    s.n.crossVectors(s.r, s.t).normalize();
    out.push(th);
  }
  return out;
}

/**
 * Largura máxima do escape asfaltado pintado (runL/runR) que o Track do web põe por curvatura (até 12 m, como os
 * de Interlagos). Em Laguna (LMU) é só uma faixa verde de ~2,5 m atrás da zebra; depois vem brita. Vale para a
 * física (track.json) e para o cenário. Sem `maxRunoff` na fonte, não mexe em nada.
 */
export function clampRunoff(track: Track, max: number | undefined) {
  if (max === undefined) return;
  for (const s of track.samples) {
    s.runL = s.runL > 0 ? Math.min(s.runL, max) : 0;
    s.runR = s.runR > 0 ? Math.min(s.runR, max) : 0;
  }
}

/**
 * Distância real dos muros (wallLeft/wallRight em m a partir do centro), medida do OSM + satélite.
 * Sem `wallLeft`/`wallRight` na fonte (Laguna Seca), não mexe em nada. `minGap` = distância mínima do muro à
 * borda (padrão 2,5 m, o mesmo do Track; Interlagos usa menos: muro dos boxes e outros colados na pista).
 */
export function applyWalls(track: Track, wallLeft: number[] | undefined, wallRight: number[] | undefined, minGap = 2.5) {
  if (!wallLeft?.length || !wallRight?.length) return;
  const S = track.samples;
  const N = S.length;
  const M = wallLeft.length;
  for (let i = 0; i < N; i++) {
    const x = (i / N) * M;
    const a = Math.floor(x) % M;
    const b = (a + 1) % M;
    const f = x - Math.floor(x);
    const s = S[i];
    s.wallL = Math.max(s.wl + minGap, wallLeft[a] + (wallLeft[b] - wallLeft[a]) * f);
    s.wallR = Math.max(s.wr + minGap, wallRight[a] + (wallRight[b] - wallRight[a]) * f);
    s.runL = Math.min(s.runL, Math.max(0, s.wallL - s.wl - s.kerbL - 1.0));
    s.runR = Math.min(s.runR, Math.max(0, s.wallR - s.wr - s.kerbR - 1.0));
  }
}

/**
 * Escape asfaltado mínimo (runLeft/runRight em m depois da borda + zebra), ex.: a faixa de aceleração da saída dos
 * boxes de Interlagos, que é asfalto e não grama. Nunca passa do muro (0,5 m antes). Sem os campos, não mexe em nada.
 */
export function applyRunoffMin(track: Track, runLeft: number[] | undefined, runRight: number[] | undefined) {
  if (!runLeft?.length || !runRight?.length) return;
  const S = track.samples;
  const N = S.length;
  const M = runLeft.length;
  for (let i = 0; i < N; i++) {
    const x = (i / N) * M;
    const a = Math.floor(x) % M;
    const b = (a + 1) % M;
    const f = x - Math.floor(x);
    const s = S[i];
    const rl = runLeft[a] + (runLeft[b] - runLeft[a]) * f;
    const rr = runRight[a] + (runRight[b] - runRight[a]) * f;
    if (rl > 0) s.runL = Math.max(s.runL, Math.min(rl, s.wallL - s.wl - s.kerbL - 0.5));
    if (rr > 0) s.runR = Math.max(s.runR, Math.min(rr, s.wallR - s.wr - s.kerbR - 0.5));
  }
}

/**
 * Zebras reais medidas no satélite + vídeo (kerbLeft/kerbRight em m a partir da borda da pista).
 * Sem `kerbLeft`/`kerbRight` na fonte (Laguna Seca), não mexe em nada.
 */
export function applyKerbs(track: Track, kerbLeft: number[] | undefined, kerbRight: number[] | undefined) {
  if (!kerbLeft?.length || !kerbRight?.length) return;
  const S = track.samples;
  const N = S.length;
  const M = kerbLeft.length;
  for (let i = 0; i < N; i++) {
    const x = (i / N) * M;
    const a = Math.floor(x) % M;
    const b = (a + 1) % M;
    const f = x - Math.floor(x);
    const s = S[i];
    const kl = kerbLeft[a] + (kerbLeft[b] - kerbLeft[a]) * f;
    const kr = kerbRight[a] + (kerbRight[b] - kerbRight[a]) * f;
    s.kerbL = kl > 0.25 ? kl : 0;
    s.kerbR = kr > 0.25 ? kr : 0;
    s.kerb = s.kerbL > 0 || s.kerbR > 0;
  }
}
