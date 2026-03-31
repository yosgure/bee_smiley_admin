const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function copyWeekToRegularSchedule() {
  const weekDays = ['月', '火', '水', '木', '金', '土'];
  const timeSlots = ['9:30〜', '11:00〜', '14:00〜', '15:30〜'];

  // 4/6（月）〜4/11（土）2026年
  const weekStart = new Date(2026, 3, 6); // month is 0-indexed
  const weekEnd = new Date(2026, 3, 11, 23, 59, 59);

  console.log(`取得期間: ${weekStart.toISOString()} 〜 ${weekEnd.toISOString()}`);

  // plus_lessonsから該当週のデータを取得
  const snapshot = await db.collection('plus_lessons')
    .where('date', '>=', admin.firestore.Timestamp.fromDate(weekStart))
    .where('date', '<=', admin.firestore.Timestamp.fromDate(weekEnd))
    .orderBy('date')
    .get();

  console.log(`取得レッスン数: ${snapshot.size}`);

  // 空のスケジュールを作成
  const schedule = {};
  for (const day of weekDays) {
    schedule[day] = {};
    for (const slot of timeSlots) {
      schedule[day][slot] = [];
    }
  }

  // レッスンをスケジュールに変換
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const dateField = data.date;
    if (!dateField) continue;

    const date = dateField.toDate();
    const dateOnly = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const weekStartOnly = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate());
    const dayIndex = Math.round((dateOnly - weekStartOnly) / (1000 * 60 * 60 * 24));
    const slotIndex = data.slotIndex || 0;

    if (dayIndex < 0 || dayIndex > 5 || slotIndex < 0 || slotIndex > 3) continue;

    const day = weekDays[dayIndex];
    const slot = timeSlots[slotIndex];

    const entry = {
      name: data.studentName || '',
      course: data.course || '通常',
      note: data.note || '',
    };

    if (data.isCustomEvent === true) {
      entry.isCustomEvent = true;
    }

    schedule[day][slot].push(entry);
    console.log(`  ${day} ${slot}: ${entry.name} (${entry.course})`);
  }

  // 結果表示
  let total = 0;
  for (const day of weekDays) {
    for (const slot of timeSlots) {
      total += schedule[day][slot].length;
    }
  }
  console.log(`\n合計エントリ数: ${total}`);

  // Firestoreに保存
  await db.collection('plus_regular_schedule').doc('data').set({
    schedule: schedule,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log('✅ plus_regular_schedule に保存完了');
  process.exit(0);
}

copyWeekToRegularSchedule().catch(e => {
  console.error('❌ エラー:', e);
  process.exit(1);
});
