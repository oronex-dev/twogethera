{{flutter_js}}
{{flutter_build_config}}

// CP-013: the private beta is online-only. Remove Flutter's previous
// generated offline worker/cache once, then do not register a new worker.
async function clearLegacyOfflineState() {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
  }
  if ('caches' in window) {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
  }
}

clearLegacyOfflineState().finally(() => {
  _flutter.loader.load({ serviceWorkerSettings: null });
});
