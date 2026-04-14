/**
 * マイグレーションスクリプト: families.children[].classroom → classrooms(配列)
 *
 * 実行方法:
 *   cd functions && node ../scripts/migrate_classroom_to_classrooms.js
 *
 * 処理:
 *   1. 全familiesドキュメントを取得
 *   2. children配列内の各childの classroom(文字列) → classrooms(配列) に変換
 *   3. 旧classroomフィールドは残す（後方互換のため）
 */

const admin = require("firebase-admin");

// Firebase Admin初期化（functions/ディレクトリから実行する場合）
const serviceAccount = require("./service-account.json");
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function migrate() {
  const snapshot = await db.collection("families").get();
  console.log(`Found ${snapshot.size} families documents`);

  let updated = 0;
  let skipped = 0;
  let errors = 0;

  for (const doc of snapshot.docs) {
    try {
      const data = doc.data();
      const children = data.children || [];
      let needsUpdate = false;

      const updatedChildren = children.map((child) => {
        // 既にclassrooms配列がある場合はスキップ
        if (child.classrooms && Array.isArray(child.classrooms) && child.classrooms.length > 0) {
          return child;
        }

        // classroom(文字列) → classrooms(配列) に変換
        const classroom = child.classroom || "";
        if (classroom) {
          needsUpdate = true;
          return {
            ...child,
            classrooms: [classroom],
            // 旧フィールドも残す（後方互換）
          };
        }

        // classroomが空の場合
        needsUpdate = true;
        return {
          ...child,
          classrooms: [],
        };
      });

      if (needsUpdate) {
        await doc.ref.update({ children: updatedChildren });
        updated++;
        console.log(`✓ Updated: ${doc.id} (${data.lastName || "?"} - ${children.length} children)`);
      } else {
        skipped++;
      }
    } catch (e) {
      errors++;
      console.error(`✗ Error: ${doc.id} - ${e.message}`);
    }
  }

  console.log(`\nDone! Updated: ${updated}, Skipped: ${skipped}, Errors: ${errors}`);
  process.exit(0);
}

migrate().catch((e) => {
  console.error("Migration failed:", e);
  process.exit(1);
});
