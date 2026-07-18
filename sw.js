/* ============================================================================
   SLAM Re-Entry — Service Worker
   ----------------------------------------------------------------------------
   Makes the app installable and launchable OFFLINE underground by caching the
   static app shell (HTML, vendored Supabase/Chart libs, self-hosted fonts,
   icons). This is purely an ASSET cache — it never touches Supabase data.

   SAFETY / CORRECTNESS RULES (do not break):
   - Only same-origin GET requests are ever served from cache.
   - Supabase API + auth calls are cross-origin (…supabase.co) and are NEVER
     intercepted — they pass straight through to the network so reads, writes,
     token refresh, and the app's own offline sync queue all behave exactly as
     before. Gas records and queued writes are the app's responsibility, not
     the service worker's.
   - Non-GET requests (writes) are never cached.

   UPDATING THE APP: bump CACHE_VERSION below. On the next visit the new worker
   installs, precaches the fresh shell, and the old cache is deleted on activate.
   ========================================================================== */

const CACHE_VERSION = 'v2';
const CACHE_NAME = 'slam-shell-' + CACHE_VERSION;

// App-shell assets to precache so the app opens with zero signal.
const ASSETS = [
  './',
  './index.html',
  './dashboard.html',
  './manifest.json',
  './dashboard.webmanifest',
  './vendor/supabase.js',
  './vendor/chart.umd.min.js',
  './vendor/fonts/montserrat.css',
  './vendor/fonts/montserrat-latin.woff2',
  './vendor/fonts/montserrat-latin-ext.woff2',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      // Best-effort precache: a single missing/renamed asset must not abort the
      // whole install (which would leave the app with no offline shell at all).
      .then((cache) => Promise.allSettled(ASSETS.map((url) => cache.add(url))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;

  // Never cache writes.
  if (req.method !== 'GET') return;

  // Never intercept cross-origin requests — most importantly the Supabase API
  // and auth endpoints. Let the browser handle them normally.
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // HTML navigations: network-first so an online launch always gets the latest
  // app, with a cache fallback so it still opens underground with no signal.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
    );
    return;
  }

  // Static assets (vendored libs, fonts, icons): cache-first for instant loads,
  // falling back to the network and caching the result.
  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res && res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      });
    })
  );
});
