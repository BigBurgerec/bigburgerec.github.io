/* Módulo de restaurante · service worker de la pantalla en tienda (se publica como sw.js, alcance ./pantalla).
   Solo permite instalar la pantalla como app a pantalla completa y abrirla aunque el wifi parpadee: primero la red, si falla, la copia guardada.
   Nunca guarda llamadas a la base (Supabase): los pedidos y la carta siempre van en vivo. */
const CACHE = 'pantalla-v1';
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
  await self.clients.claim();
})()));
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== self.location.origin) return;   // la base y las fuentes, directo a la red
  e.respondWith((async () => {
    try {
      const r = await fetch(e.request);
      if (r.ok) { const c = await caches.open(CACHE); c.put(e.request, r.clone()); }
      return r;
    } catch (err) {
      const r = await caches.match(e.request);
      if (r) return r;
      throw err;
    }
  })());
});
