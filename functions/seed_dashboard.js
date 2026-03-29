const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function seed() {
  const classroom = 'ビースマイリー湘南藤沢';

  // まず既存データを確認
  const existing = await db.collection('bee_dashboard_courses').where('classroom', '==', classroom).get();
  if (!existing.empty) {
    console.log(`既に${existing.size}件のコースが存在します。スキップします。`);
    console.log('強制的に上書きする場合は既存データを削除してから再実行してください。');
    process.exit(0);
  }

  // コース作成
  const courses = [
    { courseName: 'プリスクール', startTime: '10:00', endTime: '13:00', capacity: 5, order: 0 },
    { courseName: 'ベビーコース', startTime: '10:00', endTime: '11:00', capacity: 6, order: 1 },
    { courseName: 'プレキッズコース', startTime: '11:30', endTime: '12:30', capacity: 8, order: 2 },
    { courseName: 'キッズコース', startTime: '14:30', endTime: '16:30', capacity: 8, order: 3 },
  ];

  for (const c of courses) {
    await db.collection('bee_dashboard_courses').add({ classroom, ...c });
    console.log(`コース追加: ${c.courseName}`);
  }

  // スケジュールデータ
  const schedule = {
    'プリスクール': {
      '月': [{ name: '眞田', type: 'teacher', note: '' }],
      '火': [{ name: '大槻 信智', type: 'student', note: '' }],
      '水': [],
      '木': [
        { name: '富山', type: 'teacher', note: '' },
        { name: '阪本', type: 'teacher', note: '' },
        { name: '大野裕陽', type: 'student', note: '' },
        { name: '大野 智春', type: 'student', note: '' },
        { name: '伴瀬 葵郁', type: 'student', note: '~5月?' },
      ],
      '金': [],
      '土': [],
    },
    'ベビーコース': {
      '月': [],
      '火': [{ name: '西岡', type: 'teacher', note: '' }],
      '水': [
        { name: '廣瀬 美桜', type: 'student', note: '' },
        { name: '玉置萌乃佳', type: 'student', note: '' },
      ],
      '木': [],
      '金': [
        { name: '富山', type: 'teacher', note: '' },
        { name: '白川 蓮絃', type: 'student', note: '' },
        { name: '山口 幸也', type: 'student', note: '' },
      ],
      '土': [
        { name: '西岡', type: 'teacher', note: '' },
        { name: '高木 理央', type: 'student', note: '' },
        { name: '小田 唯織', type: 'student', note: '' },
        { name: '西原 七穂', type: 'student', note: '' },
        { name: '大澤 怜生', type: 'student', note: '' },
        { name: '山廣 華', type: 'student', note: '' },
      ],
    },
    'プレキッズコース': {
      '月': [],
      '火': [
        { name: '西岡', type: 'teacher', note: '' },
        { name: '村川 月咲', type: 'student', note: '4月' },
      ],
      '水': [{ name: '西岡', type: 'teacher', note: '' }],
      '木': [],
      '金': [{ name: '富山', type: 'teacher', note: '' }],
      '土': [
        { name: '西岡', type: 'teacher', note: '' },
        { name: '松山 佳奈', type: 'student', note: '' },
        { name: '一條 帆花', type: 'student', note: '' },
        { name: '里 紬季', type: 'student', note: '' },
        { name: '田中 快', type: 'student', note: '' },
        { name: '高木 望央', type: 'student', note: '' },
        { name: '木下 岳', type: 'student', note: '' },
        { name: '高宮 螢', type: 'student', note: '' },
      ],
    },
    'キッズコース': {
      '月': [
        { name: '富山', type: 'teacher', note: '' },
        { name: '中山 朔', type: 'student', note: '' },
        { name: '山田珠奈', type: 'student', note: '' },
        { name: '松本 凛', type: 'student', note: '' },
        { name: '大石 奏', type: 'student', note: '' },
      ],
      '火': [
        { name: '西岡', type: 'teacher', note: '' },
        { name: '石井美咲', type: 'student', note: '4月' },
        { name: '望月 奈緒', type: 'student', note: '' },
        { name: '水野 はる', type: 'student', note: '' },
      ],
      '水': [
        { name: '西岡', type: 'teacher', note: '' },
        { name: '山本 翠', type: 'student', note: '' },
        { name: '川﨑 一輝', type: 'student', note: '' },
        { name: '山本 楠', type: 'student', note: '' },
      ],
      '木': [
        { name: '富山', type: 'teacher', note: '' },
        { name: '佐藤 衣吹', type: 'student', note: '' },
        { name: '堀本 ひまり', type: 'student', note: '' },
        { name: 'ルイス ありあ', type: 'student', note: '4月体' },
        { name: '國府田 葵', type: 'student', note: '' },
      ],
      '金': [
        { name: '富山', type: 'teacher', note: '' },
        { name: '山田 駒', type: 'student', note: '' },
      ],
      '土': [
        { name: '西岡', type: 'teacher', note: '' },
        { name: '米倉 悠翔', type: 'student', note: '' },
        { name: '岩田 明弓', type: 'student', note: '' },
        { name: '神村律', type: 'student', note: '' },
        { name: '大崎 梨愛', type: 'student', note: '' },
      ],
    },
  };

  await db.collection('bee_dashboard_schedule').doc(classroom).set({
    schedule,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log('スケジュールデータ投入完了');

  console.log('全データ投入完了!');
  process.exit(0);
}

seed().catch(e => {
  console.error('Error:', e);
  process.exit(1);
});
