// staffs[].fcmTokens / families[].fcmTokens の埋まり具合を確認。
// 通知が物理的に届いていないか、トークン取得が失敗しているかを判断。

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: 'bee-smiley-admin' });
const db = admin.firestore();

(async () => {
  // staffs
  const staffSnap = await db.collection('staffs').get();
  console.log(`=== staffs (${staffSnap.size}名) ===`);
  let staffWithToken = 0;
  staffSnap.forEach(d => {
    const data = d.data();
    const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    const notifyChat = data.notifyChat;
    const flag = tokens.length > 0 ? '✓' : '✗';
    if (tokens.length > 0) staffWithToken++;
    console.log(`  ${flag} ${(data.name||'').padEnd(20)} tokens=${tokens.length}  notifyChat=${notifyChat}`);
  });
  console.log(`  → トークン保有スタッフ: ${staffWithToken}/${staffSnap.size}\n`);

  // families
  const famSnap = await db.collection('families').get();
  console.log(`=== families (${famSnap.size}名 / 保護者) ===`);
  let famWithToken = 0;
  famSnap.forEach(d => {
    const data = d.data();
    const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    if (tokens.length > 0) famWithToken++;
  });
  console.log(`  → トークン保有: ${famWithToken}/${famSnap.size}\n`);

  // plus_families
  const plusSnap = await db.collection('plus_families').get();
  console.log(`=== plus_families (${plusSnap.size}名) ===`);
  let plusWithToken = 0;
  plusSnap.forEach(d => {
    const data = d.data();
    const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    if (tokens.length > 0) plusWithToken++;
  });
  console.log(`  → トークン保有: ${plusWithToken}/${plusSnap.size}`);

  process.exit(0);
})();
