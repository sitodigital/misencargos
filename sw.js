
const CACHE = "mis-encargos-v4";

const ASSETS = [
  "./",
  "./index.html",
  "./config.js",
  "./manifest.webmanifest",
  "./icon.svg",
  "./icon-192.png",
  "./icon-512.png",
  "./apple-touch-icon.png"
];

// Instalar la nueva versión
self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

// Activar la nueva versión y retirar las cachés antiguas
self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys =>
        Promise.all(
          keys
            .filter(key =>
              key.startsWith("mis-encargos-") && key !== CACHE
            )
            .map(key => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

// Internet primero; caché como alternativa
self.addEventListener("fetch", event => {
  const request = event.request;

  if (request.method !== "GET") return;
  if (request.headers.has("range")) return;

  const url = new URL(request.url);

  // No interceptar Supabase, fuentes ni servicios externos
  if (url.origin !== self.location.origin) return;

  event.respondWith((async () => {
    try {
      // Evitar reutilizar una respuesta antigua de la caché HTTP
      const freshRequest = new Request(request, {
        cache: "no-store"
      });

      const response = await fetch(freshRequest);

      if (response && response.status === 200 &&
          response.type === "basic") {
        const cache = await caches.open(CACHE);
        await cache.put(request, response.clone());
      }

      return response;

    } catch (error) {
      // Si no hay Internet, intentar recuperar la copia guardada
      const cached = await caches.match(request);

      if (cached) return cached;

      // Para páginas, mostrar la última versión disponible
      if (request.mode === "navigate") {
        const fallback = await caches.match("./index.html");
        if (fallback) return fallback;
      }

      return new Response("No hay conexión a Internet.", {
        status: 503,
        headers: {
          "Content-Type": "text/plain; charset=utf-8"
        }
      });
    }
  })());
});

// NOTIFICACIONES PUSH: se conservan
self.addEventListener("push", event => {
  let data = {
    title: "Mis Encargos",
    body: "Tienes una actualización pendiente."
  };

  try {
    data = { ...data, ...event.data.json() };
  } catch (_) {}

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "./icon-192.png",
      badge: "./icon-192.png",
      data: {
        url: data.url || "./"
      }
    })
  );
});

// Al pulsar una notificación, abrir la aplicación
self.addEventListener("notificationclick", event => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({
      type: "window",
      includeUncontrolled: true
    }).then(list => {
      for (const client of list) {
        if ("focus" in client) return client.focus();
      }

      return clients.openWindow(
        event.notification.data?.url || "./"
      );
    })
  );
});
