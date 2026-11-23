// Monta a pista (classe Track do web) a partir da fonte própria tools/tracks/<id>/<id>.json, com os mesmos
// ajustes em todas as ferramentas que precisam da MESMA pista do Godot: pista.ts, referencia.ts, paridade.ts (via
// ./fonte.ts, no Node) e, desde a Fase 2B etapa F, o gerador do cenário (tools/cenario/cenario.ts, no navegador).
// Por isso este arquivo não importa nada do Node (fs/url): o vite do gerador também o carrega.
//
// Campos opcionais da fonte (sem eles, nada muda: Laguna e Imola saem idênticas byte a byte):
//   arcLengthDivisions  cordas que o CatmullRomCurve3 usa para medir o comprimento e espaçar as amostras.
//                       O Track usa o padrão do three.js (200): numa volta de 4,3 km são cordas de ~21 m, que
//                       encurtam a pista (Interlagos: 4.300 m para uma curva de 4.308,6 m) e espaçam as amostras
//                       de 2,00 a 2,07 m (o s do jogo deixa de ser metro).
//   wallMinGap          distância mínima do muro à borda da pista (m; padrão 2,5, o do Track/applyWalls)
//   runLeft/runRight    escape asfaltado mínimo (m, depois da borda + zebra), ex.: faixa de aceleração dos boxes
import { Curve as CurveTools } from 'three';
import { Curve as CurveWeb } from '../../../gt3-time-attack/node_modules/three/build/three.module.js';
import { Track, type TrackData } from '../../../gt3-time-attack/src/track/track';
import { applyKerbs, applyRunoffMin, applyWalls, clampRunoff } from './bank';

/** new Track(data) com `arcLengthDivisions` cordas (só durante a construção; depois volta ao padrão) */
export function trackComCordas(data: TrackData, div: number | undefined): Track {
  if (!div) return new Track(data);
  const protos = [...new Set([CurveTools.prototype, CurveWeb.prototype])];
  const orig = protos.map(p => p.getLengths);
  for (const p of protos) {
    const base = p.getLengths;
    p.getLengths = function (this: InstanceType<typeof CurveWeb>, d?: number) {
      return base.call(this, d ?? div);
    };
  }
  try {
    return new Track(data);
  } finally {
    protos.forEach((p, k) => { p.getLengths = orig[k]; });
  }
}

/** a pista como o Godot a recebe (antes do camber, que o pista.ts aplica e grava à parte) */
export function montaPista(data: any): Track {
  const track = trackComCordas(data as TrackData, data.arcLengthDivisions);
  if (data.arcLengthDivisions) {
    // conferência: com o patch valendo, o espaçamento real das amostras fica em 2 m ± 1%
    const S = track.samples;
    let lo = Infinity, hi = 0;
    for (let i = 0; i < S.length; i++) {
      const d = S[i].p.distanceTo(S[(i + 1) % S.length].p);
      lo = Math.min(lo, d); hi = Math.max(hi, d);
    }
    if (lo < 1.97 || hi > 2.03) throw new Error(`arcLengthDivisions não pegou: amostras de ${lo.toFixed(3)} a ${hi.toFixed(3)} m`);
  }
  applyKerbs(track, data.kerbLeft, data.kerbRight);
  applyWalls(track, data.wallLeft, data.wallRight, data.wallMinGap);
  clampRunoff(track, data.maxRunoff);
  applyRunoffMin(track, data.runLeft, data.runRight);
  return track;
}
