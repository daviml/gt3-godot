/**
 * Fase 2B, etapa F: s da pista ANTIGA de Interlagos → s da pista NOVA (PLANO-INTERLAGOS-DETALHES.md).
 *
 * Até a etapa E o cenário era montado na pista do jogo web (4.294 m, 2.147 amostras); desde a F ele é montado na
 * pista do Godot (tools/tracks/interlagos/interlagos.json → data/track/track.json: 4.308 m, 2.154 amostras). Todo
 * metro escrito no código ou no perfil para a pista antiga passa por aqui para continuar no MESMO lugar físico:
 *
 *   sNovo(sAntigo)    s real da pista antiga (o do track.json antigo, amostra i ↔ s = 2·i) → s da nova
 *   sNovo4300(s)      s "numa volta de 4.300 m" (convenção do código antigo, que fazia s · comprimento / 4300)
 *                     → s da nova. É o que o código antigo calculava (s · 4294/4300) levado pelo mapa.
 *   iNovo4300(s)      índice da amostra nova mais próxima de sNovo4300(s) (Math.round, sem dar a volta: o código
 *                     que pede s > 4300 continua fazendo % N, como antes)
 *   s4300(sNovo)      o inverso de sNovo4300: para comparar o s de uma amostra nova com constantes antigas
 *   dNovo(sAntigo)    lateral do centro antigo em relação ao novo (m, > 0 à direita de quem corre)
 *
 * Mapa: tools/tracks/interlagos/s_antigo_novo.json (mapa_s.py: cada amostra antiga projetada na polilinha nova,
 * como Track.locate; monotônico; periódico: s antigo + 4.294 ↔ s novo + 4.308). Fora de [0, 4294) vale o período.
 */
import mapa from '../../tracks/interlagos/s_antigo_novo.json';

const M = mapa as { s_antigo: number[]; s_novo: number[]; d: number[]; comprimentoAntigo: number; comprimentoNovo: number };
export const L_ANTIGO = M.comprimentoAntigo;
export const L_NOVO = M.comprimentoNovo;
const STEP = 2;
// pontos do mapa com o fecho da volta (s antigo L_ANTIGO ↔ s novo L_NOVO)
const XA = [...M.s_antigo, L_ANTIGO];
const XN = [...M.s_novo.map(x => Math.max(0, x)), L_NOVO];
const DD = [...M.d, M.d[0]];

function interp(x: number, xs: number[], ys: number[]): number {
  if (x <= xs[0]) return ys[0];
  let lo = 0;
  let hi = xs.length - 1;
  if (x >= xs[hi]) return ys[hi];
  while (hi - lo > 1) {
    const m = (lo + hi) >> 1;
    if (xs[m] <= x) lo = m;
    else hi = m;
  }
  const t = (x - xs[lo]) / (xs[hi] - xs[lo] || 1);
  return ys[lo] + (ys[hi] - ys[lo]) * t;
}

/** s da pista antiga (m) → s da pista nova (m); periódico */
export function sNovo(sAntigo: number): number {
  const k = Math.floor(sAntigo / L_ANTIGO);
  return interp(sAntigo - k * L_ANTIGO, XA, XN) + k * L_NOVO;
}

/** s da pista nova (m) → s da pista antiga (m); periódico */
export function sAntigo(sNovo_: number): number {
  const k = Math.floor(sNovo_ / L_NOVO);
  return interp(sNovo_ - k * L_NOVO, XN, XA) + k * L_ANTIGO;
}

/** lateral do centro antigo em relação ao novo (m, > 0 à direita): um objeto a `l` da linha antiga fica a `l + d` da nova */
export function dNovo(sAntigo_: number): number {
  const k = Math.floor(sAntigo_ / L_ANTIGO);
  return interp(sAntigo_ - k * L_ANTIGO, XA, DD);
}

/** s "numa volta de 4.300 m" do código antigo → s da pista nova */
export const sNovo4300 = (s: number) => sNovo((s * L_ANTIGO) / 4300);
/** índice da amostra nova em sNovo4300(s) (sem % N) */
export const iNovo4300 = (s: number) => Math.round(sNovo4300(s) / STEP);
/** s da pista nova → s "numa volta de 4.300 m" (para comparar com as constantes antigas) */
export const s4300 = (sNovo_: number) => (sAntigo(sNovo_) * 4300) / L_ANTIGO;
/** dNovo de um s "numa volta de 4.300 m": para o que era posto a uma lateral fixa do CENTRO antigo (tendas, prédio) */
export const dNovo4300 = (s: number) => dNovo((s * L_ANTIGO) / 4300);
/** índice da amostra nova no s antigo real (m) (sem % N) */
export const iNovo = (sAntigo_: number) => Math.round(sNovo(sAntigo_) / STEP);
