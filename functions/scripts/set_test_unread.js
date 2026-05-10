// テスト用: intake-test+ で始まるメール（_manualTest 由来）の plus_families に対して、
// child.notifyUnread = true / family.notifyUnread = true を立てる。
// Cloud Function を再デプロイしなくても NEW バッジ表示を確認できるようにするため。
//
// 実行: ADC（gcloud auth application-default login）が必要。
//   cd functions && node scripts/set_test_unread.js

const admin = require('firebase-admin');

admin.initializeApp({ projectId: 'bee-smiley-admin' });
const db = admin.firestore();

(async () => {
  const snap = await db.collection('plus_families').get();
  let updated = 0;
  let scanned = 0;
  for (const doc of snap.docs) {
    scanned++;
    const data = doc.data();
    const email = data.email || '';
    if (!email.startsWith('intake-test+')) continue;

    const children = (data.children || []).map((c) => ({
      ...c,
      notifyUnread: true,
      notifyUnreadAt: admin.firestore.Timestamp.now(),
    }));
    await doc.ref.update({
      children,
      notifyUnread: true,
      notifyUnreadAt: admin.firestore.Timestamp.now(),
    });
    console.log('  UPDATED', doc.id, email, `(${children.length} children)`);
    updated++;
  }
  console.log(`Scanned ${scanned} families, updated ${updated}.`);
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
