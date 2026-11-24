const CACHE="mis-encargos-v3";
const ASSETS=["./","./index.html","./config.js","./manifest.webmanifest","./icon.svg","./icon-192.png","./icon-512.png"];
self.addEventListener("install",e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS))));
self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))));
self.addEventListener("fetch",e=>{if(e.request.method!=="GET")return;const u=new URL(e.request.url);if(u.origin!==location.origin)return;e.respondWith(caches.match(e.request).then(c=>c||fetch(e.request).then(r=>{const copy=r.clone();caches.open(CACHE).then(cache=>cache.put(e.request,copy));return r}).catch(()=>caches.match("./index.html"))))});
self.addEventListener("push",e=>{let data={title:"Mis Encargos",body:"Tienes una actualización pendiente."};try{data={...data,...e.data.json()}}catch(_){}e.waitUntil(self.registration.showNotification(data.title,{body:data.body,icon:"./icon-192.png",badge:"./icon-192.png",data:{url:data.url||"./"}}))});
self.addEventListener("notificationclick",e=>{e.notification.close();e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{for(const c of list){if("focus" in c)return c.focus()}return clients.openWindow(e.notification.data?.url||"./")}))});
