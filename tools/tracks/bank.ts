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
