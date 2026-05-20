// 4件の家族チャットの groupName を確認
const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: 'bee-smiley-admin' });
const db = admin.firestore();

const TARGETS = [
  'family_pFXXmEH8LaX1Za5mYpaHmFDAVbS2',
  'family_NPEWYjXwANfkDY4JHiwOoVEhC4K3',
  'family_8okvkKUngfN88Y5GtJpJNSI58Ix1',
  'family_WIgxKZvEDOPVagnFhQnVOSeEq332',
];

// 比較用に既に表示できているっぽい家族チャットも数件サンプル取得
const SAMPLES = [
  'family_', // 後で別ロジックで先頭の数件取る
];

(async () => {
  for (const id of TARGETS) {
    const doc = await db.collection('chat_rooms').doc(id).get();
    if (!doc.exists) { console.log(`${id}: not found`); continue; }
    const r = doc.data();
    console.log(`${id}`);
    console.log(`  groupName : ${JSON.stringify(r.groupName)}`);
    console.log(`  members(${(r.members||[]).length})`);
    console.log(`  names keys: ${Object.keys(r.names||{}).length}`);
    console.log('');
  }

  // 比較サンプル
  console.log('=== 既存(上田さんが入っていた)チャットの groupName 例 ===');
  const all = await db.collection('chat_rooms').get();
  let n = 0;
  for (const doc of all.docs) {
    if (!doc.id.startsWith('family_')) continue;
    if (TARGETS.includes(doc.id)) continue;
    const r = doc.data();
    if (!(r.members || []).includes('QkWDUJgux7hGkgvZbfzeuJEO4TA2')) continue;
    if (n++ >= 5) break;
    const parentMember = (r.members||[]).find(m => (r.names||{})[m] && !['QkWDUJgux7hGkgvZbfzeuJEO4TA2'].includes(m));
    console.log(`${doc.id}  groupName=${JSON.stringify(r.groupName)}  members=${(r.members||[]).length}`);
  }
  process.exit(0);
})();
