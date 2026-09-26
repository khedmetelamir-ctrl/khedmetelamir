const CACHE='kea-v-hardening15';
const SHELL=['./','./index.html','./logo.png','./logo-192.png','./logo-512.png','./manifest.webmanifest'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;
  event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request).then(res=>{const copy=res.clone();if(event.request.url.startsWith(self.location.origin))caches.open(CACHE).then(c=>c.put(event.request,copy));return res}).catch(()=>caches.match('./index.html'))));
});

self.addEventListener('push',event=>{
  let data={title:'خدمة الأمير',body:'لديك إشعار جديد.',icon:'logo-192.png',tag:'kea-push'};
  try{if(event.data)data={...data,...event.data.json()}}catch(e){try{if(event.data)data.body=event.data.text()}catch(_e){}}
  event.waitUntil(self.registration.showNotification(data.title,{body:data.body,icon:data.icon||'logo-192.png',tag:data.tag||'kea-push'}));
});
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
    for(const client of list){if('focus' in client)return client.focus()}
    if(clients.openWindow)return clients.openWindow('./');
  }));
});
