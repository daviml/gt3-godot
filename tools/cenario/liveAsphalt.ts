import * as THREE from 'three';
import { Track } from '@web/track/track';

export interface TelemetryRef {
  d: number[];
  brake: number[];
}

/**
 * Aplica dados da telemetria real (Garage 61) ao atributo uv1 (UV2 no Godot) da malha de asfalto:
 *   UV2.x = distância lateral assinada em metros até o traçado ideal (para faixa emborrachada sutil)
 *   UV2.y = intensidade de freada forte [0..1] (para marcas longitudinais nas zonas de frenagem)
 *
 * A malha `ribbon` gera 2 vértices por amostra (borda esquerda -wl, borda direita +wr),
 * permitindo interpolação linear exata da distância lateral até a linha ideal pelo rasterizador da GPU.
 */
export function applyLiveAsphaltUV2(
  geo: THREE.BufferGeometry,
  track: Track,
  ref: TelemetryRef
): THREE.BufferGeometry {
  const S = track.samples;
  const N = S.length;
  const ok = ref.d.length === N && ref.brake.length === N;
  const dIdeal = ok
    ? Float32Array.from(ref.d, (x, i) => Math.max(-(S[i].wl - 0.9), Math.min(S[i].wr - 0.9, x)))
    : track.racingLine();

  const brakeZone = new Float32Array(N);
  if (ok) {
    for (let i = 0; i < N; i++) {
      let acc = 0;
      for (let j = -3; j <= 3; j++) {
        const p = ref.brake[(i + j + N) % N];
        // considera apenas freadas consistentes (>= 15% de pedal)
        acc += p >= 0.15 ? Math.min(1, (p - 0.12) / 0.55) : 0;
      }
      brakeZone[i] = Math.min(1, acc / 7);
    }
  }

  const posCount = geo.getAttribute('position').count;
  const expected = (N + 1) * 2;
  const uv1 = new Float32Array(posCount * 2);
  if (posCount === expected) {
    for (let k = 0; k <= N; k++) {
      const i = k % N;
      const s = S[i];
      const d = dIdeal[i];
      const b = brakeZone[i];
      const vIdx = k * 2;
      // borda esquerda (-wl) e borda direita (+wr)
      uv1[vIdx * 2] = -s.wl - d;
      uv1[vIdx * 2 + 1] = b;
      uv1[(vIdx + 1) * 2] = s.wr - d;
      uv1[(vIdx + 1) * 2 + 1] = b;
    }
  } else {
    for (let i = 0; i < posCount; i++) {
      uv1[i * 2] = 100.0;
      uv1[i * 2 + 1] = 0.0;
    }
  }
  geo.setAttribute('uv1', new THREE.BufferAttribute(uv1, 2));
  return geo;
}
