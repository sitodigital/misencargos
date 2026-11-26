
const CACHE = "mis-encargos-v3";

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(["./", "./index.html"]))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key =>
          key.startsWith("mis-encargos-") && key !== CACHE
        ).map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isHtml =
    request.mode === "navigate" ||
    request.destination === "document" ||
    url.pathname.endsWith(".html") ||
    url.pathname.endsWith("/");

  if (isHtml) {
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then(cache => cache.put(request, copy));
          }
          return response;
        })
        .catch(async () =>
          (await caches.match(request)) ||
          (await caches.match("./index.html")) ||
          Response.error()
        )
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE).then(cache => cache.put(request, copy));
        }
        return response;
      });
    })
  );
});

self.addEventListener("push", event => {
  let data = {
    title: "Mis Encargos",
    body: "Tienes una actualización pendiente."
  };

  try {
    if (event.data) data = { ...data, ...event.data.json() };
  } catch (_) {}

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "./icon.svg",
      data: { url: data.url || "./" }
    })
  );
});

self.addEventListener("notificationclick", event => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true })
      .then(list => {
        for (const client of list) {
          if ("focus" in client) return client.focus();
        }
        return clients.openWindow(
          event.notification.data?.url || "./"
        );
      })
  );
});
