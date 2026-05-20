// 上田さんが members に含まれていない4件の家族チャットについて、
// 保護者の子供の classroom と、そのclassroomを担当するスタッフを表示する。

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'bee-smiley-admin',
});
const db = admin.firestore();

const TARGETS = [
  { roomId: 'family_pFXXmEH8LaX1Za5mYpaHmFDAVbS2', parent: '一條 梨乃', parentUid: 'pFXXmEH8LaX1Za5mYpaHmFDAVbS2' },
  { roomId: 'family_NPEWYjXwANfkDY4JHiwOoVEhC4K3', parent: '川嶋 英芳', parentUid: 'NPEWYjXwANfkDY4JHiwOoVEhC4K3' },
  { roomId: 'family_8okvkKUngfN88Y5GtJpJNSI58Ix1', parent: '大野 春奈', parentUid: '8okvkKUngfN88Y5GtJpJNSI58Ix1' },
  { roomId: 'family_WIgxKZvEDOPVagnFhQnVOSeEq332', parent: '玉城 詔子', parentUid: 'WIgxKZvEDOPVagnFhQnVOSeEq332' },
];

function getChildClassrooms(child) {
  // 子供データ内の classroom フィールドを推測
  const arr = [];
  if (child.classroom) arr.push(child.classroom);
  if (Array.isArray(child.classrooms)) arr.push(...child.classrooms);
  return arr;
}

(async () => {
  // staffs ロード
  const staffSnap = await db.collection('staffs').get();
  const staffs = staffSnap.docs.map(d => ({ id: d.id, ...d.data() }));

  for (const t of TARGETS) {
    console.log(`\n========= ${t.parent} (uid=${t.parentUid}) =========`);
    // families から保護者検索
    let famSnap = await db.collection('families').where('uid', '==', t.parentUid).get();
    let famDoc = famSnap.docs[0];
    if (!famDoc) {
      // plus_families から
      famSnap = await db.collection('plus_families').where('uid', '==', t.parentUid).get();
      famDoc = famSnap.docs[0];
    }
    if (!famDoc) {
      console.log('  families/plus_families 双方に見つからず');
      continue;
    }
    const fam = famDoc.data();
    console.log(`  family doc: ${famDoc.ref.parent.id}/${famDoc.id}`);
    const children = Array.isArray(fam.children) ? fam.children : [];
    const allClassrooms = new Set();
    children.forEach(c => {
      const cn = `${c.lastName||''}${c.firstName||''}`;
      const cr = getChildClassrooms(c);
      console.log(`    child: ${cn}  classroom=${JSON.stringify(cr)}  status=${c.status}`);
      cr.forEach(x => allClassrooms.add(x));
    });
    console.log(`  集約 classrooms: ${JSON.stringify([...allClassrooms])}`);

    // 該当クラスを担当するスタッフ
    const matched = staffs.filter(s => {
      const sc = Array.isArray(s.classrooms) ? s.classrooms : [];
      return sc.some(c => allClassrooms.has(c));
    });
    console.log(`  該当 classroom 担当スタッフ (${matched.length}名):`);
    matched.forEach(s => console.log(`    ${s.uid}  ${s.name}  classrooms=${JSON.stringify(s.classrooms)}`));

    if (matched.length === 0) {
      console.log(`  →フォールバック: 全スタッフ (${staffs.length}名) を表示`);
      staffs.forEach(s => console.log(`    ${s.uid}  ${s.name}  classrooms=${JSON.stringify(s.classrooms)}`));
    }

    // 現状のroom members
    const roomDoc = await db.collection('chat_rooms').doc(t.roomId).get();
    if (roomDoc.exists) {
      const r = roomDoc.data();
      console.log(`  現在の room members: ${JSON.stringify(r.members)}`);
      console.log(`  現在の room names:   ${JSON.stringify(r.names)}`);
    }
  }
  process.exit(0);
})().catch(e => {
  console.error(e);
  process.exit(1);
});
