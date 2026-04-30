// 保護者/スタッフ アカウントの作成・パスワード初期化・削除と Custom Claims マイグレーション。
// 全 callable で「呼び出し元が staffs に存在するか」をチェックして管理者権限を担保している。

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, auth, FieldValue, FIXED_DOMAIN, initialPassword } = require('../utils/setup');

async function assertStaffCaller(request) {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }
  const callerUid = request.auth.uid;
  const staffDoc = await db
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }
}

/**
 * 保護者アカウントを作成する
 */
exports.createParentAccount = onCall({ region: 'asia-northeast1', secrets: [initialPassword] }, async (request) => {
  await assertStaffCaller(request);

  const { loginId, familyData } = request.data;

  if (!loginId || loginId.trim() === '') {
    throw new HttpsError('invalid-argument', 'ログインIDが必要です');
  }

  const email = loginId.trim() + FIXED_DOMAIN;

  try {
    const userRecord = await auth.createUser({
      email: email,
      password: initialPassword.value(),
      emailVerified: false,
    });

    await auth.setCustomUserClaims(userRecord.uid, { role: 'parent' });

    const saveData = {
      ...familyData,
      loginId: loginId.trim(),
      uid: userRecord.uid,
      isInitialPassword: true,
      createdAt: FieldValue.serverTimestamp(),
    };

    const docRef = await db.collection('families').add(saveData);

    return {
      success: true,
      uid: userRecord.uid,
      docId: docRef.id,
      message: '保護者アカウントを作成しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'createParentAccount', loginId: loginId?.trim(), error: error.message }));

    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'このログインIDは既に使用されています');
    }

    throw new HttpsError('internal', error.message);
  }
});

/**
 * パスワードを初期化する
 */
exports.resetParentPassword = onCall({ region: 'asia-northeast1', secrets: [initialPassword] }, async (request) => {
  await assertStaffCaller(request);

  const { targetUid, familyDocId } = request.data;

  if (!targetUid) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDが必要です');
  }

  try {
    await auth.updateUser(targetUid, {
      password: initialPassword.value(),
    });

    if (familyDocId) {
      await db.collection('families').doc(familyDocId).update({
        isInitialPassword: true,
      });
    }

    return {
      success: true,
      message: 'パスワードを初期化しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'resetParentPassword', targetUid, error: error.message }));
    throw new HttpsError('internal', error.message);
  }
});

/**
 * 保護者のログインIDを変更する（Auth email + Firestore loginId を同期更新）
 */
exports.updateParentLoginId = onCall({ region: 'asia-northeast1' }, async (request) => {
  await assertStaffCaller(request);

  const { targetUid, familyDocId, newLoginId } = request.data;

  if (!targetUid || !familyDocId) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDとファミリードキュメントIDが必要です');
  }

  const trimmedLoginId = (newLoginId || '').trim();
  if (trimmedLoginId === '') {
    throw new HttpsError('invalid-argument', '新しいログインIDを入力してください');
  }

  const existing = await db
    .collection('families')
    .where('loginId', '==', trimmedLoginId)
    .limit(1)
    .get();

  if (!existing.empty && existing.docs[0].id !== familyDocId) {
    throw new HttpsError('already-exists', 'このログインIDは既に使用されています');
  }

  const newEmail = trimmedLoginId + FIXED_DOMAIN;

  try {
    await auth.updateUser(targetUid, { email: newEmail });

    await db.collection('families').doc(familyDocId).update({
      loginId: trimmedLoginId,
    });

    return {
      success: true,
      message: 'ログインIDを変更しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'updateParentLoginId', targetUid, familyDocId, error: error.message }));

    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'このログインIDは既に使用されています');
    }

    throw new HttpsError('internal', error.message);
  }
});

/**
 * 保護者アカウントを削除する
 */
exports.deleteParentAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
  await assertStaffCaller(request);

  const { targetUid, familyDocId } = request.data;

  try {
    if (targetUid) {
      try {
        await auth.deleteUser(targetUid);
      } catch (authError) {
        if (authError.code !== 'auth/user-not-found') {
          throw authError;
        }
      }
    }

    if (familyDocId) {
      await db.collection('families').doc(familyDocId).delete();
    }

    return {
      success: true,
      message: 'アカウントを削除しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'deleteParentAccount', targetUid, familyDocId, error: error.message }));
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを作成する
 */
exports.createStaffAccount = onCall({ region: 'asia-northeast1', secrets: [initialPassword] }, async (request) => {
  await assertStaffCaller(request);

  const { loginId, staffData } = request.data;

  if (!loginId || loginId.trim() === '') {
    throw new HttpsError('invalid-argument', 'ログインIDが必要です');
  }

  const email = loginId.trim() + FIXED_DOMAIN;

  try {
    const userRecord = await auth.createUser({
      email: email,
      password: initialPassword.value(),
      emailVerified: false,
    });

    await auth.setCustomUserClaims(userRecord.uid, { role: 'staff' });

    const saveData = {
      ...staffData,
      loginId: loginId.trim(),
      uid: userRecord.uid,
      isInitialPassword: true,
      createdAt: FieldValue.serverTimestamp(),
    };

    const docRef = await db.collection('staffs').add(saveData);

    return {
      success: true,
      uid: userRecord.uid,
      docId: docRef.id,
      message: 'スタッフアカウントを作成しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'createStaffAccount', loginId: loginId?.trim(), error: error.message }));

    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'このログインIDは既に使用されています');
    }

    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフのパスワードを初期化する
 */
exports.resetStaffPassword = onCall({ region: 'asia-northeast1', secrets: [initialPassword] }, async (request) => {
  await assertStaffCaller(request);

  const { targetUid, staffDocId } = request.data;

  if (!targetUid) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDが必要です');
  }

  try {
    await auth.updateUser(targetUid, {
      password: initialPassword.value(),
    });

    if (staffDocId) {
      await db.collection('staffs').doc(staffDocId).update({
        isInitialPassword: true,
      });
    }

    return {
      success: true,
      message: 'パスワードを初期化しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'resetStaffPassword', targetUid, error: error.message }));
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを削除する
 */
exports.deleteStaffAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
  await assertStaffCaller(request);

  const { targetUid, staffDocId } = request.data;

  try {
    if (targetUid) {
      try {
        await auth.deleteUser(targetUid);
      } catch (authError) {
        if (authError.code !== 'auth/user-not-found') {
          throw authError;
        }
      }
    }

    if (staffDocId) {
      await db.collection('staffs').doc(staffDocId).delete();
    }

    return {
      success: true,
      message: 'アカウントを削除しました',
    };

  } catch (error) {
    console.error(JSON.stringify({ function: 'deleteStaffAccount', targetUid, staffDocId, error: error.message }));
    throw new HttpsError('internal', error.message);
  }
});

// ==========================================
// 既存ユーザーへの Custom Claims マイグレーション
// ==========================================
exports.migrateCustomClaims = onCall({ region: 'asia-northeast1' }, async (request) => {
  await assertStaffCaller(request);

  let staffCount = 0;
  let familyCount = 0;

  const allStaffs = await db.collection('staffs').get();
  for (const doc of allStaffs.docs) {
    const uid = doc.data().uid;
    if (uid) {
      try {
        await auth.setCustomUserClaims(uid, { role: 'staff' });
        staffCount++;
      } catch (e) {
        console.error(`Failed to set claims for staff uid=${uid}:`, e.message);
      }
    }
  }

  const allFamilies = await db.collection('families').get();
  for (const doc of allFamilies.docs) {
    const uid = doc.data().uid;
    if (uid) {
      try {
        await auth.setCustomUserClaims(uid, { role: 'parent' });
        familyCount++;
      } catch (e) {
        console.error(`Failed to set claims for parent uid=${uid}:`, e.message);
      }
    }
  }

  console.log(`Custom Claims migration completed: ${staffCount} staff, ${familyCount} families`);
  return { success: true, staffCount, familyCount };
});

// ==========================================
// マイグレーション: classroom → classrooms 配列
// ==========================================
exports.migrateClassroomToClassrooms = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const snapshot = await db.collection("families").get();
    let updated = 0;
    let skipped = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const children = data.children || [];
      let needsUpdate = false;

      const updatedChildren = children.map((child) => {
        if (child.classrooms && Array.isArray(child.classrooms) && child.classrooms.length > 0) {
          return child;
        }
        const classroom = child.classroom || "";
        needsUpdate = true;
        return { ...child, classrooms: classroom ? [classroom] : [] };
      });

      if (needsUpdate) {
        await doc.ref.update({ children: updatedChildren });
        updated++;
      } else {
        skipped++;
      }
    }

    return { updated, skipped, total: snapshot.size };
  }
);
