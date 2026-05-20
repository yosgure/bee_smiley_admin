// 上田さんが members に含まれていない4件の家族チャットを、
// 「子供の classroom を担当するスタッフ全員 + 保護者」に統一する。
//
// 使い方:
//   node fix_orphan_family_chats.js              # dry-run（変更内容を表示するだけ）
//   node fix_orphan_family_chats.js --apply      # 実際に Firestore を更新

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'bee-smiley-admin',
});
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');

const TARGETS = [
  { roomId: 'family_pFXXmEH8LaX1Za5mYpaHmFDAVbS2', parent: '一條 梨乃' },
  { roomId: 'family_NPEWYjXwANfkDY4JHiwOoVEhC4K3', parent: '川嶋 英芳' },
  { roomId: 'family_8okvkKUngfN88Y5GtJpJNSI58Ix1', parent: '大野 春奈' },
  { roomId: 'family_WIgxKZvEDOPVagnFhQnVOSeEq332', parent: '玉城 詔子' },
];

function getChildClassrooms(child) {
  const arr = [];
  if (child.classroom) arr.push(child.classroom);
  if (Array.isArray(child.classrooms)) arr.push(...child.classrooms);
  return arr;
}

(async () => {
  console.log(`=== ${APPLY ? '本番反映モード' : 'dry-run（--apply を付けると本番反映）'} ===\n`);

  const staffSnap = await db.collection('staffs').get();
  const staffs = staffSnap.docs.map(d => ({ id: d.id, ...d.data() }));

  for (const t of TARGETS) {
    const roomRef = db.collection('chat_rooms').doc(t.roomId);
    const roomDoc = await roomRef.get();
    if (!roomDoc.exists) {
      console.log(`[${t.parent}] roomId ${t.roomId} が存在しない — スキップ`);
      continue;
    }
    const room = roomDoc.data();
    const parentUid = (room.members || []).find(m => !staffs.some(s => s.uid === m));
    if (!parentUid) {
      console.log(`[${t.parent}] 保護者 uid が members から特定できず — スキップ`);
      continue;
    }

    // 保護者の家族情報
    let famSnap = await db.collection('families').where('uid', '==', parentUid).get();
    let famDoc = famSnap.docs[0];
    if (!famDoc) {
      famSnap = await db.collection('plus_families').where('uid', '==', parentUid).get();
      famDoc = famSnap.docs[0];
    }
    if (!famDoc) {
      console.log(`[${t.parent}] families/plus_families 双方に見つからず — スキップ`);
      continue;
    }
    const fam = famDoc.data();
    const children = Array.isArray(fam.children) ? fam.children : [];
    const allClassrooms = new Set();
    children.forEach(c => getChildClassrooms(c).forEach(x => allClassrooms.add(x)));

    // 該当 classroom 担当スタッフ
    let matched = staffs.filter(s => {
      const sc = Array.isArray(s.classrooms) ? s.classrooms : [];
      return sc.some(c => allClassrooms.has(c));
    });
    // フォールバック: 該当ゼロなら全スタッフ
    if (matched.length === 0) matched = staffs;

    const newMembers = [parentUid, ...matched.map(s => s.uid).filter(Boolean)];
    // 重複排除
    const dedupedMembers = [...new Set(newMembers)];

    const newNames = { ...(room.names || {}) };
    // 保護者名は既存維持
    matched.forEach(s => {
      if (s.uid && !newNames[s.uid]) newNames[s.uid] = s.name;
    });

    const beforeMembers = JSON.stringify(room.members || []);
    const afterMembers = JSON.stringify(dedupedMembers);

    console.log(`========= ${t.parent} =========`);
    console.log(`  classrooms: ${JSON.stringify([...allClassrooms])}`);
    console.log(`  before members (${(room.members || []).length}): ${beforeMembers}`);
    console.log(`  after  members (${dedupedMembers.length}): ${afterMembers}`);
    const addedNames = matched
      .filter(s => s.uid && !(room.members || []).includes(s.uid))
      .map(s => s.name);
    console.log(`  追加するスタッフ: ${addedNames.join(', ')}`);

    // members が 2 名超になる場合、chat_screen.dart の UI 仕様で
    // groupName が空だと一覧で「グループ」と表示されてしまうため、
    // 保護者名を groupName にセットする。
    const update = {
      members: dedupedMembers,
      names: newNames,
    };
    if (dedupedMembers.length > 2 && !(room.groupName && String(room.groupName).trim().length > 0)) {
      const parentName = newNames[parentUid] || t.parent;
      update.groupName = parentName;
      console.log(`  groupName: null → "${parentName}"`);
    }

    if (APPLY) {
      await roomRef.update(update);
      console.log('  → 更新しました ✓');
    }
    console.log('');
  }

  if (!APPLY) {
    console.log('=== dry-run 完了。 --apply で本番反映 ===');
  } else {
    console.log('=== 完了 ===');
  }
  process.exit(0);
})().catch(e => {
  console.error(e);
  process.exit(1);
});
