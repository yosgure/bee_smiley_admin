const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();

const FIXED_DOMAIN = '@bee-smiley.com';
const INITIAL_PASSWORD = 'pass1234';

/**
 * 保護者アカウントを作成する
 */
exports.createParentAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }

  // 呼び出し元がスタッフかどうか確認
  const callerUid = request.auth.uid;
  const staffDoc = await admin.firestore()
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }

  const { loginId, familyData } = request.data;

  if (!loginId || loginId.trim() === '') {
    throw new HttpsError('invalid-argument', 'ログインIDが必要です');
  }

  const email = loginId.trim() + FIXED_DOMAIN;

  try {
    // Firebase Authでユーザー作成
    const userRecord = await admin.auth().createUser({
      email: email,
      password: INITIAL_PASSWORD,
      emailVerified: false,
    });

    // Firestoreに保護者データを保存
    const saveData = {
      ...familyData,
      loginId: loginId.trim(),
      uid: userRecord.uid,
      isInitialPassword: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const docRef = await admin.firestore().collection('families').add(saveData);

    return {
      success: true,
      uid: userRecord.uid,
      docId: docRef.id,
      message: '保護者アカウントを作成しました',
    };

  } catch (error) {
    console.error('Error creating parent account:', error);

    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'このログインIDは既に使用されています');
    }

    throw new HttpsError('internal', error.message);
  }
});

/**
 * パスワードを初期化する
 */
exports.resetParentPassword = onCall({ region: 'asia-northeast1' }, async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }

  // 呼び出し元がスタッフかどうか確認
  const callerUid = request.auth.uid;
  const staffDoc = await admin.firestore()
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }

  const { targetUid, familyDocId } = request.data;

  if (!targetUid) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDが必要です');
  }

  try {
    // パスワードをリセット
    await admin.auth().updateUser(targetUid, {
      password: INITIAL_PASSWORD,
    });

    // Firestoreのフラグを更新
    if (familyDocId) {
      await admin.firestore().collection('families').doc(familyDocId).update({
        isInitialPassword: true,
      });
    }

    return {
      success: true,
      message: 'パスワードを初期化しました',
    };

  } catch (error) {
    console.error('Error resetting password:', error);
    throw new HttpsError('internal', error.message);
  }
});

/**
 * 保護者アカウントを削除する
 */
exports.deleteParentAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }

  // 呼び出し元がスタッフかどうか確認
  const callerUid = request.auth.uid;
  const staffDoc = await admin.firestore()
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }

  const { targetUid, familyDocId } = request.data;

  try {
    // Firebase Authからユーザー削除
    if (targetUid) {
      try {
        await admin.auth().deleteUser(targetUid);
      } catch (authError) {
        // ユーザーが存在しない場合は無視
        if (authError.code !== 'auth/user-not-found') {
          throw authError;
        }
      }
    }

    // Firestoreから削除
    if (familyDocId) {
      await admin.firestore().collection('families').doc(familyDocId).delete();
    }

    return {
      success: true,
      message: 'アカウントを削除しました',
    };

  } catch (error) {
    console.error('Error deleting account:', error);
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを作成する
 */
exports.createStaffAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }

  // 呼び出し元がスタッフかどうか確認
  const callerUid = request.auth.uid;
  const staffDoc = await admin.firestore()
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }

  const { loginId, staffData } = request.data;

  if (!loginId || loginId.trim() === '') {
    throw new HttpsError('invalid-argument', 'ログインIDが必要です');
  }

  const email = loginId.trim() + FIXED_DOMAIN;

  try {
    // Firebase Authでユーザー作成
    const userRecord = await admin.auth().createUser({
      email: email,
      password: INITIAL_PASSWORD,
      emailVerified: false,
    });

    // Firestoreにスタッフデータを保存
    const saveData = {
      ...staffData,
      loginId: loginId.trim(),
      uid: userRecord.uid,
      isInitialPassword: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const docRef = await admin.firestore().collection('staffs').add(saveData);

    return {
      success: true,
      uid: userRecord.uid,
      docId: docRef.id,
      message: 'スタッフアカウントを作成しました',
    };

  } catch (error) {
    console.error('Error creating staff account:', error);

    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'このログインIDは既に使用されています');
    }

    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフのパスワードを初期化する
 */
exports.resetStaffPassword = onCall({ region: 'asia-northeast1' }, async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }

  // 呼び出し元がスタッフかどうか確認
  const callerUid = request.auth.uid;
  const staffDoc = await admin.firestore()
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }

  const { targetUid, staffDocId } = request.data;

  if (!targetUid) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDが必要です');
  }

  try {
    // パスワードをリセット
    await admin.auth().updateUser(targetUid, {
      password: INITIAL_PASSWORD,
    });

    // Firestoreのフラグを更新
    if (staffDocId) {
      await admin.firestore().collection('staffs').doc(staffDocId).update({
        isInitialPassword: true,
      });
    }

    return {
      success: true,
      message: 'パスワードを初期化しました',
    };

  } catch (error) {
    console.error('Error resetting password:', error);
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを削除する
 */
exports.deleteStaffAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', '認証が必要です');
  }

  // 呼び出し元がスタッフかどうか確認
  const callerUid = request.auth.uid;
  const staffDoc = await admin.firestore()
    .collection('staffs')
    .where('uid', '==', callerUid)
    .limit(1)
    .get();

  if (staffDoc.empty) {
    throw new HttpsError('permission-denied', '管理者権限が必要です');
  }

  const { targetUid, staffDocId } = request.data;

  try {
    // Firebase Authからユーザー削除
    if (targetUid) {
      try {
        await admin.auth().deleteUser(targetUid);
      } catch (authError) {
        if (authError.code !== 'auth/user-not-found') {
          throw authError;
        }
      }
    }

    // Firestoreから削除
    if (staffDocId) {
      await admin.firestore().collection('staffs').doc(staffDocId).delete();
    }

    return {
      success: true,
      message: 'アカウントを削除しました',
    };

  } catch (error) {
    console.error('Error deleting account:', error);
    throw new HttpsError('internal', error.message);
  }
});