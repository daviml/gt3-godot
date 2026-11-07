// Servidor só para exportar o cenário (tools/cenario.mjs): a página importa o código do jogo web e as texturas
// vêm do public/ dele.
import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

const web = fileURLToPath(new URL('../../../gt3-time-attack/', import.meta.url));
export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  publicDir: web + 'public',
  server: { fs: { allow: [fileURLToPath(new URL('../../../', import.meta.url))] } },
  logLevel: 'warn'
});
