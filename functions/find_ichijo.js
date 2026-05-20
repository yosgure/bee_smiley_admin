// gcloud auth application-default login で作られた ADC を使用
// 一條さん（families または plus_families）と関連 chat_rooms の調査

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'bee-smiley-admin',
});
const db = admin.firestore();

function matches(name) {
  if (!name) return false;
  const n = String(name).replace(/\s/g, '');
  return n.includes('一條') || n.includes('一条');
}

(async () => {
  const candidates = [];

  // families コレクション
  const famSnap = await db.collection('families').get();
  famSnap.forEach(doc => {
    const d = doc.data();
    const parentName = `${d.lastName || ''}${d.firstName || ''}`;
    const children = Array.isArray(d.children) ? d.children : [];
    const childMatch = children.some(c => matches(`${c.lastName || ''}${c.firstName || ''}`));
    if (matches(parentName) || childMatch) {
      candidates.push({ collection: 'families', id: doc.id, uid: d.uid, parentName, children: children.map(c => `${c.lastName||''}${c.firstName||''}`) });
    }
  });

  // plus_families コレクション
  const plusSnap = await db.collection('plus_families').get();
  plusSnap.forEach(doc => {
    const d = doc.data();
    const parentName = `${d.lastName || ''}${d.firstName || ''}`;
    const children = Array.isArray(d.children) ? d.children : [];
    const childMatch = children.some(c => matches(`${c.lastName || ''}${c.firstName || ''}`));
    if (matches(parentName) || childMatch) {
      candidates.push({ collection: 'plus_families', id: doc.id, uid: d.uid, parentName, children: children.map(c => `${c.lastName||''}${c.firstName||''}`) });
    }
  });

  console.log('一條/一条 候補:', JSON.stringify(candidates, null, 2));
  if (candidates.length === 0) return process.exit(0);

  for (const c of candidates) {
    const identifier = c.uid || c.id;
    if (!identifier) continue;
    console.log(`\n===== ${c.collection}/${c.id} uid=${c.uid} でルーム検索 =====`);
    const rooms = await db.collection('chat_rooms')
      .where('members', 'array-contains', identifier)
      .get();
    console.log(`ルーム数: ${rooms.size}`);

    for (const room of rooms.docs) {
      const r = room.data();
      console.log(`\n-- Room ${room.id} (${r.groupName || '1on1'}) --`);
      console.log(`  members: ${JSON.stringify(r.members)}`);
      console.log(`  names: ${JSON.stringify(r.names)}`);
      console.log(`  type: ${r.type}`);
      console.log(`  isParentChat: ${r.isParentChat}`);
      console.log(`  isFamilyChat: ${r.isFamilyChat}`);
      console.log(`  lastMessage: ${r.lastMessage}`);
      console.log(`  lastMessageTime: ${r.lastMessageTime?.toDate()}`);
      const msgs = await room.ref.collection('messages').orderBy('createdAt', 'desc').limit(5).get();
      console.log(`  messages(${msgs.size}):`);
      msgs.forEach(m => {
        const md = m.data();
        const t = md.createdAt ? md.createdAt.toDate().toISOString() : 'NULL';
        console.log(`    [${t}] sender=${md.senderId} "${(md.text||'').slice(0,50)}"`);
      });
    }
  }
  process.exit(0);
})().catch(e => {
  console.error(e);
  process.exit(1);
});
