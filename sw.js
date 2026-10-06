/* Service worker dell'agenda: rende l'app installabile e utilizzabile senza internet.
   - La pagina (index.html) si aggiorna "prima dalla rete": se c'è connessione arriva sempre l'ultima versione,
     altrimenti si usa la copia salvata.
   - Calendario, icone e manifest: "prima dalla copia salvata" (i file hanno la versione nel nome o cambiano raramente).
   - I DATI non passano mai di qui: restano in IndexedDB nel browser.
   Ad ogni nuova pubblicazione cambia VERSIONE: l'app propone "Aggiorna" e ricarica. */
const VERSIONE = 'agenda-nails-1.1.0';
const DA_SALVARE = [
  './',
  './index.html',
  './manifest.webmanifest',
  './vendor/fullcalendar-6.1.21.min.js',
  './icone/icona-192.png',
  './icone/icona-512.png',
  './icone/icona-maskable-512.png',
  './icone/apple-touch-icon.png',
  './icone/favicon-32.png'
];
const CDN_CALENDARIO = 'https://cdn.jsdelivr.net/npm/fullcalendar@6.1.21/index.global.min.js';

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(VERSIONE);
    await cache.addAll(DA_SALVARE);
    // la copia del calendario dalla CDN (stessa richiesta CORS fatta dalla pagina, con controllo d'integrità)
    try { const r = await fetch(new Request(CDN_CALENDARIO, { mode: 'cors', credentials: 'omit' })); if (r.ok) await cache.put(CDN_CALENDARIO, r); } catch (err) { /* offline: si userà la copia in vendor/ */ }
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== VERSIONE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => { if (e.data && e.data.tipo === 'aggiorna') self.skipWaiting(); });

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (req.mode === 'navigate') { e.respondWith(primaRete(req)); return; }
  if (url.origin === self.location.origin || url.href === CDN_CALENDARIO) e.respondWith(primaCache(req));
});

async function primaRete(req) {
  const cache = await caches.open(VERSIONE);
  try {
    const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 4000);
    const r = await fetch(req, { signal: ctrl.signal }); clearTimeout(t);
    if (r.ok) cache.put('./index.html', r.clone());
    return r;
  } catch (err) {
    return (await cache.match('./index.html')) || (await cache.match('./')) || new Response('Agenda non disponibile offline: aprila una volta con internet.', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
  }
}
async function primaCache(req) {
  const cache = await caches.open(VERSIONE);
  const trovato = await cache.match(req, { ignoreSearch: true });
  if (trovato) return trovato;
  const r = await fetch(req);
  if (r.ok && (r.type === 'basic' || r.type === 'cors')) cache.put(req, r.clone());
  return r;
}
