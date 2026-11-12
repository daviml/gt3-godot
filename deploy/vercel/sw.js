// Service Worker para GT3 Time Attack PWA
const CACHE_NAME = 'gt3-time-attack-v1';
const PRECACHE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './index.icon.png',
  './index.apple-touch-icon.png',
  './index.png',
  './index.js'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(PRECACHE_ASSETS).catch((err) => {
        console.warn('[SW] Falha ao pré-cachear alguns assets do shell:', err);
      });
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    Promise.all([
      self.clients.claim(),
      caches.keys().then((keys) => {
        return Promise.all(
          keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
        );
      })
    ])
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Arquivos pesados de engine e assets (.pck e .wasm):
  // Deixa o HTTP cache nativo do navegador (gerenciado via vercel.json immutable)
  // tratar, evitando estouro de cota (QuotaExceededError) no Cache Storage do iOS Safari.
  if (url.pathname.endsWith('.pck') || url.pathname.endsWith('.wasm')) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Demais arquivos (shell HTML, manifest, ícones, scripts): Stale-While-Revalidate
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic') {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache).catch(() => {});
          });
        }
        return networkResponse;
      }).catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});
