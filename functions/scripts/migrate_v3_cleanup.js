// Phase 1 マイグレーション: v3 で不要になったフィールドを物理削除。
//
// 削除対象:
//   - family.partnerCategory
//   - family.notifyUnreadAt（一部レガシー、未読化システムでは個別child側に置く）
//   - children[].confidence (A/B/C)
//   - children[].partnerCategory
//   - children[].waitReason / waitDeadline / waitNote
//
// 実行: ADC（gcloud auth application-default login）必須。
//   cd functions && node scripts/migrate_v3_cleanup.js

const admin = require('firebase-admin');

admin.initializeApp({ projectId: 'bee-smiley-admin' });
const db = admin.firestore();

const FIELDS_TO_DELETE_FROM_FAMILY = ['partnerCategory'];
const FIELDS_TO_DELETE_FROM_CHILD = [
  'confidence',
  'partnerCategory',
  'waitReason',
  'waitDeadline',
  'waitNote',
];

(async () => {
  const snap = await db.collection('plus_families').get();
  let scanned = 0;
  let updated = 0;
  let totalDeletedFields = 0;

  for (const doc of snap.docs) {
    scanned++;
    const data = doc.data();
    let needUpdate = false;
    const update = {};

    // family レベル
    for (const f of FIELDS_TO_DELETE_FROM_FAMILY) {
      if (f in data) {
        update[f] = admin.firestore.FieldValue.delete();
        needUpdate = true;
        totalDeletedFields++;
      }
    }

    // children
    const oldChildren = Array.isArray(data.children) ? data.children : [];
    let childrenChanged = false;
    const newChildren = oldChildren.map((c) => {
      const child = { ...c };
      for (const f of FIELDS_TO_DELETE_FROM_CHILD) {
        if (f in child) {
          delete child[f];
          childrenChanged = true;
          totalDeletedFields++;
        }
      }
      return child;
    });

    if (childrenChanged) {
      update.children = newChildren;
      needUpdate = true;
    }

    if (needUpdate) {
      await doc.ref.update(update);
      console.log(`  UPDATED ${doc.id}`);
      updated++;
    }
  }

  console.log(
      `\nScanned ${scanned} families, updated ${updated} (${totalDeletedFields} fields removed).`);
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
