/**
 * Fase 3 (PLANO-INTERLAGOS-DETALHES.md, setor 3): altura real do que fica além da borda no lado BAIXO de um trecho com
 * camber forte.
 *
 * Tudo o que o gerador põe ao lado da pista (faixas pintadas, grama até o muro, barreiras, pista dos boxes) segue o
 * plano inclinado da pista (s.p + s.r·d, com o camber do LiDAR em s.r). Na curva das Arquibancadas / começo da reta
 * dos boxes o camber chega a 7,4° (LiDAR conferido: 1,3 m de desnível em 10 m de pista), e a entrada dos boxes fica a
 * até 37 m da linha central: no plano ela desceria 4,5 m, mas o LiDAR mostra o chão quase plano depois da borda
 * (borda − 0,04·m: −1,4 m a 12 m do centro, −1,6 a −2,1 m entre 16 e 30 m, s 4030–4060). Além disso o terreno do
 * gerador ficava na altura do CENTRO − 0,6 m e cobria 3–5 m do asfalto do lado baixo (s ~3990–4080).
 *
 * `ajusteLateral(track, i, d)` = quanto SOMAR à altura de um ponto no plano da pista (amostra i, d metros do centro,
 * + = direita): 0 até a borda + 3 m e no lado alto; dali para fora, o chão passa a cair só PENDENTE (4%, a
 * queda média do LiDAR entre a borda e a pista dos boxes). Vale só
 * nos trechos de TRECHOS (s novo, com rampa de 20 m nas pontas); fora deles devolve 0 (nada muda no resto da volta).
 * `alturaLateral` = desnível do plano + ajuste (para o terreno, que não segue o plano).
 */
import type { Track } from '@web/track/track';

/** [s0, s1] (s novo; s1 < s0 = cruza a linha de chegada) onde o ajuste vale, com rampa de RAMPA m dentro das pontas */
const TRECHOS: [number, number][] = [[3900, 248]];
const RAMPA = 20;
const PENDENTE = 0.04;
export const FOLGA = 3;

function peso(track: Track, s: number): number {
  const L = track.length;
  let w = 0;
  for (const [a, b] of TRECHOS) {
    const len = (((b - a) % L) + L) % L;
    const x = (((s - a) % L) + L) % L;
    if (x > len) continue;
    w = Math.max(w, Math.min(1, x / RAMPA, (len - x) / RAMPA));
  }
  return w;
}

/** tangente do camber na amostra (+ = lado direito mais alto) */
function tanCamber(track: Track, i: number): number {
  const r = track.samples[i].r;
  return r.y / Math.hypot(r.x, r.z);
}

export function ajusteLateral(track: Track, i: number, d: number): number {
  const s = track.samples[i];
  const w = peso(track, s.s);
  if (w <= 0) return 0;
  const t = tanCamber(track, i);
  // lado baixo: d < 0 com t > 0 (esquerda mais baixa) ou d > 0 com t < 0
  if (d * t >= 0 || Math.abs(t) <= PENDENTE) return 0;
  const borda = (d < 0 ? s.wl : s.wr) + FOLGA;
  const alem = Math.abs(d) - borda;
  if (alem <= 0) return 0;
  return w * alem * (Math.abs(t) - PENDENTE);
}

/** desnível do chão em relação ao centro da amostra i, d metros para o lado (plano da pista + ajuste); 0 fora dos trechos */
export function alturaLateral(track: Track, i: number, d: number): number {
  const s = track.samples[i];
  const w = peso(track, s.s);
  if (w <= 0) return 0;
  const t = tanCamber(track, i);
  // plano da pista até a borda + FOLGA; dali para fora, plano no lado alto e queda de PENDENTE no lado baixo
  const e0 = s.wl + FOLGA;
  const e1 = s.wr + FOLGA;
  const dd = Math.max(-e0, Math.min(e1, d));
  const alem = d < -e0 ? -d - e0 : d > e1 ? d - e1 : 0;
  const baixo = d * t < 0;
  return w * (dd * t - (baixo ? alem * Math.min(PENDENTE, Math.abs(t)) : 0));
}

/** a amostra i está num trecho com ajuste? */
export function comAjuste(track: Track, i: number): boolean {
  return peso(track, track.samples[i].s) > 0;
}
