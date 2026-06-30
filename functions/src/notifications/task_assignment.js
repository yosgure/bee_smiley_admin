// プラスのタスクに担当者が設定されたら、担当者へDMを1通送り、
// チャットのメンションベル（mentions に担当者uid）を点ける。
//
// トリガー: plus_tasks/{taskId} の作成
// 必要フィールド: assigneeId（staffsのドキュメントID）, createdBy（作成者のauth uid）
// 担当者のチャットuidは staffs/{assigneeId}.uid から解決する。

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { FieldValue } = require('firebase-admin/firestore');
const { db } = require('../utils/setup');

exports.notifyTaskAssignment = onDocumentCreated(
  { region: 'asia-northeast1', document: 'plus_tasks/{taskId}' },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const task = snap.data() || {};
    const assigneeId = task.assigneeId;
    const createdBy = task.createdBy;
    if (!assigneeId || !createdBy) return; // 担当者なし or 作成者不明はスキップ

    // 担当者のチャットuidと表示名を解決（staffs ドキュメントID → uid）
    let assigneeUid = assigneeId;
    let assigneeName = (task.assigneeName || '').toString();
    try {
      const sDoc = await db.collection('staffs').doc(assigneeId).get();
      if (sDoc.exists) {
        const sd = sDoc.data() || {};
        if (sd.uid) assigneeUid = sd.uid;
        if (!assigneeName) assigneeName = (sd.name || '').toString();
      }
    } catch (e) {
      console.warn('[notifyTaskAssignment] staff resolve failed:', e.message);
    }

    if (!assigneeUid || assigneeUid === createdBy) return; // 自分宛は通知しない

    // 作成者の表示名を解決（ルーム名表示用）
    let creatorName = '';
    try {
      const q = await db.collection('staffs')
        .where('uid', '==', createdBy).limit(1).get();
      if (!q.empty) creatorName = (q.docs[0].data().name || '').toString();
    } catch (e) {
      console.warn('[notifyTaskAssignment] creator resolve failed:', e.message);
    }

    // 既存の1:1 DMルームを探す（無ければ作成）
    let roomRef = null;
    try {
      const rooms = await db.collection('chat_rooms')
        .where('members', 'array-contains', createdBy).get();
      for (const r of rooms.docs) {
        const rd = r.data() || {};
        const members = Array.isArray(rd.members) ? rd.members : [];
        const isGroup =
          (rd.groupName && String(rd.groupName).trim() !== '') ||
          members.length > 2;
        if (!isGroup && members.length === 2 && members.includes(assigneeUid)) {
          roomRef = r.ref;
          break;
        }
      }
    } catch (e) {
      console.warn('[notifyTaskAssignment] room lookup failed:', e.message);
    }

    if (!roomRef) {
      roomRef = db.collection('chat_rooms').doc();
      await roomRef.set({
        roomId: roomRef.id,
        members: [createdBy, assigneeUid],
        names: { [createdBy]: creatorName, [assigneeUid]: assigneeName },
        groupName: null,
        photoUrl: null,
        lastMessage: 'チャット開始',
        lastMessageTime: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    // 本文を組み立て
    const title = (task.title || '').toString().trim();
    const student = (task.studentName || '').toString().trim();
    const lines = ['📋 タスクが割り当てられました'];
    const body = student ? `${student}：${title}` : title;
    if (body) lines.push(body);
    if (task.dueDate && task.dueDate.toDate) {
      const d = task.dueDate.toDate();
      const jst = new Date(d.getTime() + 9 * 3600 * 1000);
      lines.push(`期日：${jst.getUTCMonth() + 1}/${jst.getUTCDate()}`);
    }
    const text = lines.join('\n');

    await roomRef.collection('messages').add({
      senderId: createdBy,
      text,
      type: 'text',
      url: '',
      fileName: '',
      fileSize: 0,
      stamps: {},
      mentions: [assigneeUid],
      createdAt: FieldValue.serverTimestamp(),
      readBy: [createdBy],
    });
    await roomRef.update({
      lastMessage: lines[0],
      lastMessageTime: FieldValue.serverTimestamp(),
    });
    console.log(`[notifyTaskAssignment] DM sent: ${createdBy} -> ${assigneeUid}`);
  }
);
