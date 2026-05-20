// fix_orphan_family_chats.js で members を増やした結果、groupName が null の
// 3件 (川嶋/大野/玉城) がチャット一覧で「グループ」と表示されてしまう問題を修正。
// groupName を保護者名に揃える。
//
//   node fix_orphan_family_chats_groupname.js              # dry-run
//   node fix_orphan_family_chats_groupname.js --apply      # 本番反映

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: 'bee-smiley-admin' });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');

const TARGETS = [
  { roomId: 'family_NPEWYjXwANfkDY4JHiwOoVEhC4K3', parentUid: 'NPEWYjXwANfkDY4JHiwOoVEhC4K3' },
  { roomId: 'family_8okvkKUngfN88Y5GtJpJNSI58Ix1', parentUid: '8okvkKUngfN88Y5GtJpJNSI58Ix1' },
  { roomId: 'family_WIgxKZvEDOPVagnFhQnVOSeEq332', parentUid: 'WIgxKZvEDOPVagnFhQnVOSeEq332' },
];

(async () => {
  console.log(`=== ${APPLY ? '本番反映' : 'dry-run（--apply で本番反映）'} ===\n`);
  for (const t of TARGETS) {
    const roomRef = db.collection('chat_rooms').doc(t.roomId);
    const doc = await roomRef.get();
    if (!doc.exists) { console.log(`${t.roomId}: not found`); continue; }
    const r = doc.data();
    const parentName = (r.names || {})[t.parentUid];
    if (!parentName) {
      console.log(`${t.roomId}: 保護者名が names マップから見つからず — スキップ`);
      continue;
    }
    console.log(`${t.roomId}`);
    console.log(`  before groupName: ${JSON.stringify(r.groupName)}`);
    console.log(`  after  groupName: ${JSON.stringify(parentName)}`);
    if (APPLY) {
      await roomRef.update({ groupName: parentName });
      console.log('  → 更新しました ✓');
    }
    console.log('');
  }
  console.log(APPLY ? '=== 完了 ===' : '=== dry-run 完了 ===');
  process.exit(0);
})();
