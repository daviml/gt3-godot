// Servidor só para exportar o cenário (tools/cenario.mjs): a página importa o código do jogo web e as texturas
// vêm do public/ dele.
//
// Outras pistas (TRACK=<id>, ex.: laguna-seca): o código do web continua sendo o mesmo, mas os módulos com coisa
// fixa de Interlagos (cores, trechos em metros, boxes, placas, torres...) são trocados por cópias adaptadas em
// tools/cenario/<pasta>/ (MODULES), e os dados de Interlagos pelos da pista (tools/tracks/<id>/, data/reference/).
// Interlagos (sem TRACK ou TRACK=interlagos) usa as cópias de tools/cenario/interlagos/ e, desde a Fase 2B etapa F,
// também a fonte própria (tools/tracks/interlagos/: a mesma pista da física) em vez dos dados do web.
import { defineConfig, type Plugin } from 'vite';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const web = fileURLToPath(new URL('../../../gt3-time-attack/', import.meta.url));
const godot = fileURLToPath(new URL('../../', import.meta.url));
const track = process.env.TRACK || 'interlagos';

/** pasta das cópias adaptadas dos módulos do web (tools/cenario/<pasta>/) */
const MODULES: Record<string, string> = { 'laguna-seca': 'laguna', imola: 'imola', interlagos: 'interlagos' };

/** dados de Interlagos → dados da pista (a referência alimenta a borracha e as placas de freada) */
const DATA: Record<string, Record<string, string>> = {
  'laguna-seca': {
    'data/tracks/interlagos.json': 'tools/tracks/laguna-seca/laguna-seca.json',
    'data/tracks/interlagos-osm.json': 'tools/tracks/laguna-seca/laguna-seca-osm.json',
    'data/tracks/interlagos-terrain.json': 'tools/tracks/laguna-seca/laguna-seca-terrain.json',
    'data/reference/interlagos-porsche.json': 'data/reference/laguna-seca-m4.json'
  },
  // Fase 2B etapa F: Interlagos também tem fonte própria (a pista do Godot); a referência é a do Porsche 992 do
  // Garage 61 reconvertida na pista nova (borracha e marcas de freada no traçado real)
  interlagos: {
    'data/tracks/interlagos.json': 'tools/tracks/interlagos/interlagos.json',
    'data/tracks/interlagos-osm.json': 'tools/tracks/interlagos/interlagos-osm.json',
    'data/tracks/interlagos-terrain.json': 'tools/tracks/interlagos/interlagos-terrain.json',
    'data/reference/interlagos-porsche.json': 'data/reference/interlagos-porsche.json'
  },
  imola: {
    'data/tracks/interlagos.json': 'tools/tracks/imola/imola.json',
    'data/tracks/interlagos-osm.json': 'tools/tracks/imola/imola-osm.json',
    'data/tracks/interlagos-terrain.json': 'tools/tracks/imola/imola-terrain.json',
    'data/reference/interlagos-porsche.json': 'data/reference/imola-m4.json'
  }
};

const norm = (p: string) => resolve(p).replace(/\\/g, '/').toLowerCase();

function trackRedirect(id: string): Plugin {
  const map = new Map<string, string>();
  for (const [from, to] of Object.entries(DATA[id] ?? {})) map.set(norm(web + from), resolve(godot + to));
  for (const m of ['trackView', 'trackDetails', 'trackside', 'scenery', 'surroundings', 'osmScenery']) {
    const own = fileURLToPath(new URL(`./${MODULES[id] ?? id}/${m}.ts`, import.meta.url));
    if (existsSync(own)) map.set(norm(web + `src/render/${m}.ts`), own);
  }
  return {
    name: 'track-redirect',
    enforce: 'pre',
    async resolveId(source, importer, opts) {
      const r = await this.resolve(source, importer, { ...opts, skipSelf: true });
      if (!r) return null;
      const to = map.get(norm(r.id.split('?')[0]));
      return to ?? r;
    }
  };
}

export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  publicDir: web + 'public',
  server: { fs: { allow: [fileURLToPath(new URL('../../../', import.meta.url))] } },
  resolve: { alias: { '@web': web + 'src' } },
  plugins: track ? [trackRedirect(track)] : [],
  logLevel: 'warn'
});
