// Monta a pista (classe Track do web) a partir da fonte própria tools/tracks/<id>/<id>.json, com os mesmos
// ajustes em todas as ferramentas que precisam da MESMA pista do Godot (pista.ts, referencia.ts, paridade.ts):
// zebras e muros medidos, escape asfaltado limitado e mínimo, e o comprimento medido com mais cordas.
// A montagem em si (trackComCordas, montaPista, campos opcionais da fonte) fica em ./montaPista.ts, sem nada do
// Node, porque o gerador do cenário (tools/cenario/cenario.ts, no navegador) monta a mesma pista (Fase 2B, etapa F).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { montaPista } from './montaPista';

export { montaPista, trackComCordas } from './montaPista';

export const fonte = (id: string, f = `${id}.json`) => fileURLToPath(new URL(`${id}/${f}`, import.meta.url));

export function lePista(id: string): { data: any; track: ReturnType<typeof montaPista> } {
  const data = JSON.parse(readFileSync(fonte(id), 'utf8'));
  return { data, track: montaPista(data) };
}
