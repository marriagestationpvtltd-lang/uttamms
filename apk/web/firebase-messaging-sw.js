// Firebase Messaging Service Worker for Marriage Station Web
// This file enables background push notifications via Firebase Cloud Messaging.
//
// HOW TO CONFIGURE:
//   1. Replace the firebaseConfig values below with your project's web config
//      from the Firebase Console → Project Settings → Your apps → Web app.
//   2. Set your VAPID key in the Firebase Console →
//      Project Settings → Cloud Messaging → Web Push certificates.
//   3. Pass the VAPID key when calling
//      FirebaseMessaging.instance.getToken(vapidKey: '<YOUR_VAPID_KEY>').

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// TODO: Replace with your Firebase web app configuration
// (Firebase Console → Project Settings → Your apps → Web app → SDK setup and config)
firebase.initializeApp({
  apiKey: 'AIzaSyA6BqEPNDcAZORqSrKcMUEpxRagJbZci9w',
  authDomain: 'digitallamicomnp.firebaseapp.com',
  databaseURL: 'https://digitallamicomnp-default-rtdb.firebaseio.com',
  projectId: 'digitallamicomnp',
  storageBucket: 'digitallamicomnp.firebasestorage.app',
  messagingSenderId: '477405059891',
  appId: '1:477405059891:web:86dc05c92a2406b84d7c46',
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message:', payload);

  const notificationTitle = payload.notification?.title ?? 'Marriage Station';
  const notificationOptions = {
    body: payload.notification?.body ?? '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data,
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click – open or focus the app
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(windowClients) {
      for (var i = 0; i < windowClients.length; i++) {
        var client = windowClients[i];
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
