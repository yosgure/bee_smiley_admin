// KPI（OKR週次進捗）のカテゴリ初期登録。スクショ準拠。
// gcloud auth application-default login で作られた ADC を使用。
// 固定ID(set)なので何度実行しても重複しない。
// 実行: node seed_kpi_categories.js

const admin = require('firebase-admin');
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'bee-smiley-admin',
});
const db = admin.firestore();

const categories = [
  { id: 'bs_shonanfujisawa', name: 'BS湘南藤沢', objective: '生徒数の増加と継続', krContent: '生徒数を60人達成 (年間目標基準)', krTarget: 15 },
  { id: 'bs_shonandai', name: 'BS湘南台', objective: '生徒数の増加と継続', krContent: '生徒数を60人達成 (年間目標基準)', krTarget: 15 },
  { id: 'bsp_shonanfujisawa', name: 'BSP湘南藤沢', objective: '生徒数の増加と継続', krContent: 'コマ数を66コマ達成 (年間目標基準)', krTarget: 17 },
  { id: 'salon_lite', name: 'サロン_LITE', objective: '会員数の拡大', krContent: '会員数を200人達成 (年間目標基準)', krTarget: 50 },
  { id: 'salon_std', name: 'サロン_STD', objective: '会員数の拡大', krContent: '会員数を60人達成 (年間目標基準)', krTarget: 15 },
  { id: 'course_0_3', name: '養成講座0-3', objective: '受講者数の確保', krContent: '受講者数を30人達成 (年間目標基準)', krTarget: 20 },
  { id: 'course_3_6', name: '養成講座3-6', objective: '受講者数の確保', krContent: '受講者数を30人達成 (年間目標基準)', krTarget: 20 },
  { id: 'course_sensory', name: '感覚統合講座', objective: '受講者数の確保', krContent: '受講者数を20人達成 (年間目標基準)', krTarget: 5 },
  { id: 'course_dev', name: '発達支援講座', objective: '受講者数の確保', krContent: '受講者数を40人達成 (年間目標基準)', krTarget: 5 },
  { id: 'course_art', name: 'アートdeモンテ講座', objective: '受講者数の確保', krContent: '受講者数を20人達成 (年間目標基準)', krTarget: 5 },
  { id: 'intro_support', name: '導入サポート', objective: '導入企業の獲得', krContent: '導入者数を20社達成 (年間目標基準)', krTarget: 5 },
];

(async () => {
  const batch = db.batch();
  categories.forEach((c, i) => {
    const { id, ...rest } = c;
    batch.set(db.collection('kpi_categories').doc(id), { ...rest, order: i });
  });
  await batch.commit();
  console.log(`KPIカテゴリ ${categories.length} 件を登録しました。`);
  process.exit(0);
})().catch((e) => {
  console.error('登録失敗:', e);
  process.exit(1);
});
