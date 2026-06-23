// KPI閲覧権限の初回付与（ブートストラップ）。
// 上田洋介・上田藍 の staffs ドキュメントに kpiAccess=true をセットする。
// 以降は本人たちが管理画面のスイッチで付与/解除できる。
// 実行: node bootstrap_kpi_access.js

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'bee-smiley-admin',
});
const db = admin.firestore();

// 対象（loginId で特定）。氏名でも照合する。
const targets = [
  { loginId: 'yosukeueda', name: '上田洋介' },
  { loginId: 'aiueda', name: '上田藍' },
];

(async () => {
  const snap = await db.collection('staffs').get();
  const hits = [];
  snap.forEach((doc) => {
    const d = doc.data();
    const name = (d.name || '').replace(/\s/g, '');
    const loginId = d.loginId || '';
    const matched = targets.find(
      (t) => loginId === t.loginId || name === t.name
    );
    if (matched) hits.push({ id: doc.id, name: d.name, loginId, uid: d.uid });
  });

  console.log('対象スタッフ:', JSON.stringify(hits, null, 2));
  if (hits.length === 0) {
    console.log('該当なし。loginId/氏名を確認してください。');
    process.exit(1);
  }

  const batch = db.batch();
  for (const h of hits) {
    batch.update(db.collection('staffs').doc(h.id), { kpiAccess: true });
  }
  await batch.commit();
  console.log(`${hits.length} 名に kpiAccess=true を付与しました。`);
  process.exit(0);
})().catch((e) => {
  console.error('失敗:', e);
  process.exit(1);
});
