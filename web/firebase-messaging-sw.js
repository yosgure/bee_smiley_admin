importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

// あなたのFirebase設定 (共有いただいたfirebase_options.dartと同じ情報です)
firebase.initializeApp({
  apiKey: "AIzaSyCG1ZISNTNRWR1-2mwkGBWaDssGAJ_kvEc",
  authDomain: "bee-smiley-admin.firebaseapp.com",
  projectId: "bee-smiley-admin",
  storageBucket: "bee-smiley-admin.firebasestorage.app",
  messagingSenderId: "964732214398",
  appId: "1:964732214398:web:5e5071a188d64a56d24c2f"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});