/**
 * Sorteio LOCAL das árvores de Interlagos (PLANO-INTERLAGOS-DETALHES.md, Fase 4, item 0).
 *
 * Até a Fase 2B as árvores vinham de uma sequência global de números aleatórios (`mulberry32(7)` e o `rand` do OSM):
 * qualquer mudança num setor (muro, escape, uma árvore a mais ou a menos) deslocava a sequência e movia árvores na
 * volta inteira (Fase 2: 280 de 7.052). Agora cada sorteio tem a sua semente:
 *   - por tentativa (mata do buildScenery: tentativa t → semente própria; o resultado de t só depende de t e do
 *     lugar onde ela cai);
 *   - por polígono (mata do OSM);
 *   - por posição (espécie, tom, giro e tamanho de cada árvore: a semente é a posição dela, em cm).
 */
import { mulberry32 } from '@web/util/random';

/** mistura inteiros em uma semente de 32 bits (FNV-1a + avalanche do murmur3) */
export function semente(...v: number[]): number {
  let h = 0x811c9dc5;
  for (const x of v) {
    let k = Math.round(x) | 0;
    for (let b = 0; b < 4; b++) {
      h ^= k & 0xff;
      h = Math.imul(h, 0x01000193);
      k >>>= 8;
    }
  }
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return h | 0;
}

/** gerador com semente local (inteiros: índice de tentativa, polígono, posição em cm...) */
export const randLocal = (...v: number[]) => mulberry32(semente(...v));

/** gerador com semente na posição (x, z) em cm, com um rótulo para separar usos */
export const randPosicao = (x: number, z: number, rotulo: number) => randLocal(rotulo, Math.round(x * 100), Math.round(z * 100));

/**
 * `rand` para o plantTrees do web (src/render/trees.ts), que sorteia 2 números por árvore (espécie e tom), na ordem
 * da lista: aqui cada par sai da posição da própria árvore, então incluir/tirar uma árvore não muda as outras.
 */
export function randPorArvore(spots: { x: number; z: number }[]): () => number {
  let c = 0;
  let r: () => number = () => 0;
  return () => {
    const i = c >> 1;
    if (i >= spots.length) throw new Error('randPorArvore: plantTrees pediu mais de 2 números por árvore');
    if ((c & 1) === 0) r = randPosicao(spots[i].x, spots[i].z, 0x7ee5);
    c++;
    return r();
  };
}
