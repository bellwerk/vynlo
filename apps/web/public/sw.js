/* global self */

// Vynlo deliberately does not register a fetch handler. Authenticated or
// workspace-owned responses are never cached indiscriminately, and Release 1
// does not support offline writes.
self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") {
    void self.skipWaiting();
  }
});
