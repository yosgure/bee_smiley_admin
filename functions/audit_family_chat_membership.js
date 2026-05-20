// 全 family_ プレフィックスチャットを調査し、上田さん(QkWDUJgux7hGkgvZbfzeuJEO4TA2)が
// members に含まれていないルームを一覧出力。

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'bee-smiley-admin',
});
const db = admin.firestore();

const UEDA_UID = 'QkWDUJgux7hGkgvZbfzeuJEO4TA2';

(async () => {
  const snap = await db.collection('chat_rooms').get();
  const allRooms = snap.docs;
  console.log(`総ルーム数: ${allRooms.length}`);

  const familyRooms = allRooms.filter(d => d.id.startsWith('family_'));
  console.log(`family_ プレフィックスルーム数: ${familyRooms.length}\n`);

  // staffs を取得して uid セット作成 (members の中で誰がスタッフか判定するため)
  const staffSnap = await db.collection('staffs').get();
  const staffUidToName = new Map();
  staffSnap.forEach(d => {
    const data = d.data();
    if (data.uid) staffUidToName.set(data.uid, data.name);
  });

  const includesUeda = [];
  const excludesUeda = [];

  for (const room of familyRooms) {
    const r = room.data();
    const members = Array.isArray(r.members) ? r.members : [];
    const names = r.names || {};
    const parentMember = members.find(m => !staffUidToName.has(m));
    const parentName = parentMember ? (names[parentMember] || '???') : '(保護者不明)';
    const staffMembers = members.filter(m => staffUidToName.has(m)).map(m => names[m] || staffUidToName.get(m) || m);
    const last = r.lastMessageTime?.toDate();

    const info = {
      roomId: room.id,
      parentName,
      staffMembers,
      memberCount: members.length,
      lastMessageTime: last ? last.toISOString().slice(0, 10) : 'なし',
    };

    if (members.includes(UEDA_UID)) {
      includesUeda.push(info);
    } else {
      excludesUeda.push(info);
    }
  }

  console.log(`=== 上田さんが members に含まれている家族チャット (${includesUeda.length}件) ===`);
  includesUeda.sort((a, b) => (b.lastMessageTime || '').localeCompare(a.lastMessageTime || ''));
  includesUeda.forEach(r => {
    console.log(`  ${r.lastMessageTime}  ${r.parentName.padEnd(15)} staff=[${r.staffMembers.join(', ')}]`);
  });

  console.log(`\n=== 上田さんが members に含まれていない家族チャット (${excludesUeda.length}件) ===`);
  excludesUeda.sort((a, b) => (b.lastMessageTime || '').localeCompare(a.lastMessageTime || ''));
  excludesUeda.forEach(r => {
    console.log(`  ${r.lastMessageTime}  ${r.parentName.padEnd(15)} staff=[${r.staffMembers.join(', ')}]  roomId=${r.roomId}`);
  });

  process.exit(0);
})().catch(e => {
  console.error(e);
  process.exit(1);
});
