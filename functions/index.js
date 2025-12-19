// Firebase Cloud Functions for Push Notifications & Account Management (v2)

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const auth = getAuth();

const FIXED_DOMAIN = '@bee-smiley.com';
const INITIAL_PASSWORD = 'pass1234';

// ==========================================
// チャットメッセージ送信時の通知
// ==========================================
exports.onChatMessageCreated = onDocumentCreated(
  {
    document: "chat_rooms/{chatId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const message = event.data.data();
    const chatId = event.params.chatId;

    try {
      const chatDoc = await db.collection("chat_rooms").doc(chatId).get();
      if (!chatDoc.exists) return null;

      const chatData = chatDoc.data();
      const senderId = message.senderId;

      // 送信者の名前を取得
      let senderName = "不明";
      const names = chatData.names || {};
      if (names[senderId]) {
        senderName = names[senderId];
      }

      const participants = chatData.members || [];
      const recipientIds = participants.filter((id) => id !== senderId);

      if (recipientIds.length === 0) return null;

      // 送信者のトークンを取得（除外用）
      let senderTokens = [];
      const senderStaffSnap = await db
        .collection("staffs")
        .where("uid", "==", senderId)
        .limit(1)
        .get();
      if (!senderStaffSnap.empty) {
        senderTokens = senderStaffSnap.docs[0].data().fcmTokens || [];
      } else {
        const senderFamilySnap = await db
          .collection("families")
          .where("uid", "==", senderId)
          .limit(1)
          .get();
        if (!senderFamilySnap.empty) {
          senderTokens = senderFamilySnap.docs[0].data().fcmTokens || [];
        }
      }

      const tokens = [];

      for (const recipientId of recipientIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", recipientId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyChat !== false && staffData.fcmTokens) {
            // 送信者のトークンを除外
            const filteredTokens = staffData.fcmTokens.filter(
              (token) => !senderTokens.includes(token)
            );
            tokens.push(...filteredTokens);
          }
          continue;
        }

        const familySnap = await db
          .collection("families")
          .where("uid", "==", recipientId)
          .limit(1)
          .get();

        if (!familySnap.empty) {
          const familyData = familySnap.docs[0].data();
          if (familyData.notifyChat !== false && familyData.fcmTokens) {
            // 送信者のトークンを除外
            const filteredTokens = familyData.fcmTokens.filter(
              (token) => !senderTokens.includes(token)
            );
            tokens.push(...filteredTokens);
          }
        }
      }

      if (tokens.length === 0) return null;

      // 重複トークンを除去
      const uniqueTokens = [...new Set(tokens)];

      const response = await messaging.sendEachForMulticast({
        tokens: uniqueTokens,
        notification: {
          title: `${senderName}`,
          body: message.type === "image" ? "画像を送信しました" : message.text,
        },
        data: {
          type: "chat",
          chatId: chatId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
        webpush: {
          notification: {
            icon: "/icons/Icon-192.png",
          },
          fcmOptions: {
            link: "https://bee-smiley-admin.web.app",
          },
        },
      });

      console.log(`チャット通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("チャット通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// お知らせ作成時の通知
// ==========================================
exports.onNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const notification = event.data.data();

    try {
      const tokens = [];
      const target = notification.target || "all";
      const targetClassrooms = notification.targetClassrooms || [];

      const familiesSnap = await db.collection("families").get();

      for (const familyDoc of familiesSnap.docs) {
        const familyData = familyDoc.data();

        if (familyData.notifyAnnouncement === false) continue;

        if (target === "specific" && targetClassrooms.length > 0) {
          const children = familyData.children || [];
          const isTarget = children.some((child) =>
            targetClassrooms.includes(child.classroom)
          );
          if (!isTarget) continue;
        }

        if (familyData.fcmTokens) {
          tokens.push(...familyData.fcmTokens);
        }
      }

      if (tokens.length === 0) return null;

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: notification.title || "お知らせ",
          body: notification.body || "",
        },
        data: {
          type: "announcement",
          notificationId: event.params.notificationId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`お知らせ通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("お知らせ通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// イベント作成時の通知
// ==========================================
exports.onEventCreated = onDocumentCreated(
  {
    document: "events/{eventId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const eventData = event.data.data();

    if (eventData.isPublished !== true) return null;

    try {
      const tokens = [];

      const familiesSnap = await db.collection("families").get();

      for (const familyDoc of familiesSnap.docs) {
        const familyData = familyDoc.data();

        if (familyData.notifyEvent === false) continue;

        if (familyData.fcmTokens) {
          tokens.push(...familyData.fcmTokens);
        }
      }

      if (tokens.length === 0) return null;

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "新しいイベント",
          body: eventData.title || "新しいイベントが登録されました",
        },
        data: {
          type: "event",
          eventId: event.params.eventId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`イベント通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("イベント通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// アセスメント公開時の通知
// ==========================================
exports.onAssessmentPublished = onDocumentUpdated(
  {
    document: "assessments/{assessmentId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (before.isPublished === true || after.isPublished !== true) {
      return null;
    }

    try {
      const childId = after.childId;
      if (!childId) return null;

      const familiesSnap = await db.collection("families").get();
      const tokens = [];

      for (const familyDoc of familiesSnap.docs) {
        const familyData = familyDoc.data();

        if (familyData.notifyAssessment === false) continue;

        const children = familyData.children || [];
        const hasChild = children.some(
          (child) =>
            child.id === childId || child.firstName === after.childFirstName
        );

        if (!hasChild) continue;

        if (familyData.fcmTokens) {
          tokens.push(...familyData.fcmTokens);
        }
      }

      if (tokens.length === 0) return null;

      const childName = after.childLastName + " " + after.childFirstName;
      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "アセスメントが公開されました",
          body: `${childName}さんのアセスメントが公開されました`,
        },
        data: {
          type: "assessment",
          assessmentId: event.params.assessmentId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`アセスメント通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("アセスメント通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// カレンダー予定作成時の通知（担当講師向け）
// ==========================================
exports.onCalendarEventCreated = onDocumentCreated(
  {
    document: "calendar_events/{eventId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const eventData = event.data.data();

    try {
      const staffIds = eventData.staffIds || [];
      if (staffIds.length === 0) return null;

      const tokens = [];

      for (const staffId of staffIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", staffId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyCalendar !== false && staffData.fcmTokens) {
            tokens.push(...staffData.fcmTokens);
          }
        }
      }

      if (tokens.length === 0) return null;

      const startTime = eventData.startTime?.toDate();
      const dateStr = startTime
        ? `${startTime.getMonth() + 1}/${startTime.getDate()}`
        : "";

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "新しい予定が追加されました",
          body: `${dateStr} ${eventData.subject || "(件名なし)"}`,
        },
        data: {
          type: "calendar",
          eventId: event.params.eventId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`カレンダー追加通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("カレンダー追加通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// カレンダー予定更新時の通知（担当講師向け）
// ==========================================
exports.onCalendarEventUpdated = onDocumentUpdated(
  {
    document: "calendar_events/{eventId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const hasSignificantChange =
      before.subject !== after.subject ||
      before.startTime?.toMillis() !== after.startTime?.toMillis() ||
      before.endTime?.toMillis() !== after.endTime?.toMillis() ||
      JSON.stringify(before.staffIds) !== JSON.stringify(after.staffIds);

    if (!hasSignificantChange) return null;

    try {
      const staffIds = after.staffIds || [];
      if (staffIds.length === 0) return null;

      const tokens = [];

      for (const staffId of staffIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", staffId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyCalendar !== false && staffData.fcmTokens) {
            tokens.push(...staffData.fcmTokens);
          }
        }
      }

      if (tokens.length === 0) return null;

      const startTime = after.startTime?.toDate();
      const dateStr = startTime
        ? `${startTime.getMonth() + 1}/${startTime.getDate()}`
        : "";

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "予定が変更されました",
          body: `${dateStr} ${after.subject || "(件名なし)"}`,
        },
        data: {
          type: "calendar",
          eventId: event.params.eventId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`カレンダー変更通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("カレンダー変更通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// カレンダー予定削除時の通知（担当講師向け）
// ==========================================
exports.onCalendarEventDeleted = onDocumentDeleted(
  {
    document: "calendar_events/{eventId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const eventData = event.data.data();

    try {
      const staffIds = eventData.staffIds || [];
      if (staffIds.length === 0) return null;

      const tokens = [];

      for (const staffId of staffIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", staffId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyCalendar !== false && staffData.fcmTokens) {
            tokens.push(...staffData.fcmTokens);
          }
        }
      }

      if (tokens.length === 0) return null;

      const startTime = eventData.startTime?.toDate();
      const dateStr = startTime
        ? `${startTime.getMonth() + 1}/${startTime.getDate()}`
        : "";

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "予定が削除されました",
          body: `${dateStr} ${eventData.subject || "(件名なし)"}`,
        },
        data: {
          type: "calendar_deleted",
          eventId: event.params.eventId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`カレンダー削除通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("カレンダー削除通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// プラスレッスン作成時の通知（担当講師向け）
// ==========================================
exports.onPlusLessonCreated = onDocumentCreated(
  {
    document: "plus_lessons/{lessonId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const lessonData = event.data.data();

    try {
      const teacherNames = lessonData.teachers || [];
      if (teacherNames.length === 0) return null;

      const isAllStaff = teacherNames.includes("全員");

      const tokens = [];

      if (isAllStaff) {
        const staffSnap = await db.collection("staffs").get();
        for (const doc of staffSnap.docs) {
          const staffData = doc.data();
          const classrooms = staffData.classrooms || [];
          const isPlus = classrooms.some((c) => c.includes("プラス"));
          if (isPlus && staffData.notifyPlusSchedule !== false && staffData.fcmTokens) {
            tokens.push(...staffData.fcmTokens);
          }
        }
      } else {
        for (const teacherName of teacherNames) {
          const staffSnap = await db
            .collection("staffs")
            .where("name", "==", teacherName)
            .limit(1)
            .get();

          if (!staffSnap.empty) {
            const staffData = staffSnap.docs[0].data();
            if (staffData.notifyPlusSchedule !== false && staffData.fcmTokens) {
              tokens.push(...staffData.fcmTokens);
            }
          }
        }
      }

      if (tokens.length === 0) return null;

      const date = lessonData.date?.toDate();
      const dateStr = date
        ? `${date.getMonth() + 1}/${date.getDate()}`
        : "";
      const timeSlots = ["9:30〜", "11:00〜", "14:00〜", "15:30〜"];
      const timeStr = timeSlots[lessonData.slotIndex] || "";

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "新しいプラス予定が追加されました",
          body: `${dateStr} ${timeStr} ${lessonData.studentName || "(生徒未設定)"}`,
        },
        data: {
          type: "plus_schedule",
          lessonId: event.params.lessonId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`プラス追加通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("プラス追加通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// プラスレッスン更新時の通知（担当講師向け）
// ==========================================
exports.onPlusLessonUpdated = onDocumentUpdated(
  {
    document: "plus_lessons/{lessonId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const hasSignificantChange =
      before.studentName !== after.studentName ||
      before.date?.toMillis() !== after.date?.toMillis() ||
      before.slotIndex !== after.slotIndex ||
      JSON.stringify(before.teachers) !== JSON.stringify(after.teachers) ||
      before.room !== after.room;

    if (!hasSignificantChange) return null;

    try {
      const teacherNames = after.teachers || [];
      if (teacherNames.length === 0) return null;

      const isAllStaff = teacherNames.includes("全員");
      const tokens = [];

      if (isAllStaff) {
        const staffSnap = await db.collection("staffs").get();
        for (const doc of staffSnap.docs) {
          const staffData = doc.data();
          const classrooms = staffData.classrooms || [];
          const isPlus = classrooms.some((c) => c.includes("プラス"));
          if (isPlus && staffData.notifyPlusSchedule !== false && staffData.fcmTokens) {
            tokens.push(...staffData.fcmTokens);
          }
        }
      } else {
        for (const teacherName of teacherNames) {
          const staffSnap = await db
            .collection("staffs")
            .where("name", "==", teacherName)
            .limit(1)
            .get();

          if (!staffSnap.empty) {
            const staffData = staffSnap.docs[0].data();
            if (staffData.notifyPlusSchedule !== false && staffData.fcmTokens) {
              tokens.push(...staffData.fcmTokens);
            }
          }
        }
      }

      if (tokens.length === 0) return null;

      const date = after.date?.toDate();
      const dateStr = date
        ? `${date.getMonth() + 1}/${date.getDate()}`
        : "";
      const timeSlots = ["9:30〜", "11:00〜", "14:00〜", "15:30〜"];
      const timeStr = timeSlots[after.slotIndex] || "";

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "プラス予定が変更されました",
          body: `${dateStr} ${timeStr} ${after.studentName || "(生徒未設定)"}`,
        },
        data: {
          type: "plus_schedule",
          lessonId: event.params.lessonId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`プラス変更通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("プラス変更通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// プラスレッスン削除時の通知（担当講師向け）
// ==========================================
exports.onPlusLessonDeleted = onDocumentDeleted(
  {
    document: "plus_lessons/{lessonId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const lessonData = event.data.data();

    try {
      const teacherNames = lessonData.teachers || [];
      if (teacherNames.length === 0) return null;

      const isAllStaff = teacherNames.includes("全員");
      const tokens = [];

      if (isAllStaff) {
        const staffSnap = await db.collection("staffs").get();
        for (const doc of staffSnap.docs) {
          const staffData = doc.data();
          const classrooms = staffData.classrooms || [];
          const isPlus = classrooms.some((c) => c.includes("プラス"));
          if (isPlus && staffData.notifyPlusSchedule !== false && staffData.fcmTokens) {
            tokens.push(...staffData.fcmTokens);
          }
        }
      } else {
        for (const teacherName of teacherNames) {
          const staffSnap = await db
            .collection("staffs")
            .where("name", "==", teacherName)
            .limit(1)
            .get();

          if (!staffSnap.empty) {
            const staffData = staffSnap.docs[0].data();
            if (staffData.notifyPlusSchedule !== false && staffData.fcmTokens) {
              tokens.push(...staffData.fcmTokens);
            }
          }
        }
      }

      if (tokens.length === 0) return null;

      const date = lessonData.date?.toDate();
      const dateStr = date
        ? `${date.getMonth() + 1}/${date.getDate()}`
        : "";
      const timeSlots = ["9:30〜", "11:00〜", "14:00〜", "15:30〜"];
      const timeStr = timeSlots[lessonData.slotIndex] || "";

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: "プラス予定が削除されました",
          body: `${dateStr} ${timeStr} ${lessonData.studentName || "(生徒未設定)"}`,
        },
        data: {
          type: "plus_schedule_deleted",
          lessonId: event.params.lessonId,
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });

      console.log(`プラス削除通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("プラス削除通知エラー:", error);
      return null;
    }
  }
);

// ==========================================
// アカウント管理関数
// ==========================================

/**
 * 保護者アカウントを作成する
 */
exports.createParentAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
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

  const { loginId, familyData } = request.data;

  if (!loginId || loginId.trim() === '') {
    throw new HttpsError('invalid-argument', 'ログインIDが必要です');
  }

  const email = loginId.trim() + FIXED_DOMAIN;

  try {
    const userRecord = await auth.createUser({
      email: email,
      password: INITIAL_PASSWORD,
      emailVerified: false,
    });

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

  const { targetUid, familyDocId } = request.data;

  if (!targetUid) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDが必要です');
  }

  try {
    await auth.updateUser(targetUid, {
      password: INITIAL_PASSWORD,
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
    console.error('Error resetting password:', error);
    throw new HttpsError('internal', error.message);
  }
});

/**
 * 保護者アカウントを削除する
 */
exports.deleteParentAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
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
    console.error('Error deleting account:', error);
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを作成する
 */
exports.createStaffAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
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

  const { loginId, staffData } = request.data;

  if (!loginId || loginId.trim() === '') {
    throw new HttpsError('invalid-argument', 'ログインIDが必要です');
  }

  const email = loginId.trim() + FIXED_DOMAIN;

  try {
    const userRecord = await auth.createUser({
      email: email,
      password: INITIAL_PASSWORD,
      emailVerified: false,
    });

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

  const { targetUid, staffDocId } = request.data;

  if (!targetUid) {
    throw new HttpsError('invalid-argument', '対象ユーザーIDが必要です');
  }

  try {
    await auth.updateUser(targetUid, {
      password: INITIAL_PASSWORD,
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
    console.error('Error resetting password:', error);
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを削除する
 */
exports.deleteStaffAccount = onCall({ region: 'asia-northeast1' }, async (request) => {
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
    console.error('Error deleting account:', error);
    throw new HttpsError('internal', error.message);
  }
});

// 入退室通知を送信
exports.sendAttendanceNotification = onDocumentCreated(
  {
    document: "attendance_notifications/{docId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const data = event.data.data();
    
    if (!data || data.processed) return null;
    
    const fcmTokens = data.fcmTokens || [];
    const title = data.title;
    const body = data.body;
    const type = data.type;
    
    if (fcmTokens.length === 0) {
      console.log('No FCM tokens found');
      return null;
    }
    
    try {
      const response = await messaging.sendEachForMulticast({
        tokens: fcmTokens,
        notification: {
          title: title,
          body: body,
        },
        data: {
          type: 'attendance',
          action: type,
          studentName: data.studentName || '',
          lessonName: data.lessonName || '',
          classroom: data.classroom || '',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        apns: {
          payload: {
            aps: {
              badge: 1,
              sound: "default",
            },
          },
        },
        android: {
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
      });
      
      console.log(`入退室通知送信: ${response.successCount}件成功`);
      
      await event.data.ref.update({ 
        processed: true,
        processedAt: FieldValue.serverTimestamp(),
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
      
      return null;
    } catch (error) {
      console.error('入退室通知エラー:', error);
      await event.data.ref.update({ 
        processed: true,
        processedAt: FieldValue.serverTimestamp(),
        error: String(error),
      });
      return null;
    }
  }
);