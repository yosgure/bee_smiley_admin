// Firebase Cloud Functions for Push Notifications & Account Management (v2)

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const fetch = require("node-fetch");
const cheerio = require("cheerio");
const { CookieJar, Cookie } = require("tough-cookie");

// Secret Manager でAPIキー・初期パスワードを管理
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const initialPassword = defineSecret("INITIAL_PASSWORD");
const hugUsername = defineSecret("HUG_USERNAME");
const hugPassword = defineSecret("HUG_PASSWORD");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const auth = getAuth();

const FIXED_DOMAIN = '@bee-smiley.com';

// ==========================================
// FCMトークン クリーンアップ ヘルパー
// ==========================================

/**
 * sendEachForMulticast のレスポンスを確認し、
 * 無効なトークンを Firestore から削除する。
 *
 * @param {object} response - sendEachForMulticast の戻り値
 * @param {Array<{token: string, docRef: FirebaseFirestore.DocumentReference}>} tokenDocMap
 *   各トークンとそれが格納されている Firestore ドキュメントの対応表
 */
async function cleanupInvalidTokens(response, tokenDocMap) {
  if (!response || !response.responses || !tokenDocMap || tokenDocMap.length === 0) {
    return;
  }

  const invalidTokenErrors = new Set([
    'messaging/invalid-registration-token',
    'messaging/registration-token-not-registered',
  ]);

  const tokensToRemove = new Map(); // docRef.path -> [token1, token2, ...]

  response.responses.forEach((resp, idx) => {
    if (resp.error && invalidTokenErrors.has(resp.error.code)) {
      const entry = tokenDocMap[idx];
      if (entry && entry.docRef) {
        const path = entry.docRef.path;
        if (!tokensToRemove.has(path)) {
          tokensToRemove.set(path, { docRef: entry.docRef, tokens: [] });
        }
        tokensToRemove.get(path).tokens.push(entry.token);
      }
    }
  });

  if (tokensToRemove.size === 0) return;

  const cleanupPromises = [];
  for (const [path, { docRef, tokens }] of tokensToRemove) {
    console.log(`Removing ${tokens.length} invalid token(s) from ${path}`);
    cleanupPromises.push(
      docRef.update({
        fcmTokens: FieldValue.arrayRemove(...tokens),
      })
    );
  }

  try {
    await Promise.all(cleanupPromises);
    console.log(`Cleaned up invalid tokens from ${tokensToRemove.size} document(s)`);
  } catch (error) {
    console.error('Token cleanup error:', error);
  }
}

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
      const tokenDocMap = [];

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
            const docRef = staffSnap.docs[0].ref;
            filteredTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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
            const docRef = familySnap.docs[0].ref;
            filteredTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
          }
        }
      }

      if (tokens.length === 0) return null;

      // 重複トークンを除去（tokenDocMapも同期）
      const seen = new Set();
      const uniqueTokenDocMap = [];
      const uniqueTokens = [];
      for (const entry of tokenDocMap) {
        if (!seen.has(entry.token)) {
          seen.add(entry.token);
          uniqueTokens.push(entry.token);
          uniqueTokenDocMap.push(entry);
        }
      }

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

      console.log(`チャット通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, uniqueTokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onChatMessageCreated',
        chatId,
        messageId: event.params.messageId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];
      const target = notification.target || "all";
      const targetClassrooms = notification.targetClassrooms || [];

      // fcmTokensが存在する保護者のみ取得（トークンなしのドキュメントをスキップ）
      const familiesSnap = await db.collection("families")
        .where("fcmTokens", "!=", [])
        .get();

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

        const docRef = familyDoc.ref;
        familyData.fcmTokens.forEach((t) => {
          tokens.push(t);
          tokenDocMap.push({ token: t, docRef });
        });
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

      console.log(`お知らせ通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onNotificationCreated',
        notificationId: event.params.notificationId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      // fcmTokensが存在する保護者のみ取得
      const familiesSnap = await db.collection("families")
        .where("fcmTokens", "!=", [])
        .get();

      for (const familyDoc of familiesSnap.docs) {
        const familyData = familyDoc.data();

        if (familyData.notifyEvent === false) continue;

        const docRef = familyDoc.ref;
        familyData.fcmTokens.forEach((t) => {
          tokens.push(t);
          tokenDocMap.push({ token: t, docRef });
        });
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

      console.log(`イベント通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onEventCreated',
        eventId: event.params.eventId,
        error: error.message || String(error),
      }));
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

      // fcmTokensが存在する保護者のみ取得
      const familiesSnap = await db.collection("families")
        .where("fcmTokens", "!=", [])
        .get();
      const tokens = [];
      const tokenDocMap = [];

      for (const familyDoc of familiesSnap.docs) {
        const familyData = familyDoc.data();

        if (familyData.notifyAssessment === false) continue;

        const children = familyData.children || [];
        const hasChild = children.some(
          (child) =>
            child.id === childId || child.firstName === after.childFirstName
        );

        if (!hasChild) continue;

        const docRef = familyDoc.ref;
        familyData.fcmTokens.forEach((t) => {
          tokens.push(t);
          tokenDocMap.push({ token: t, docRef });
        });
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

      console.log(`アセスメント通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onAssessmentPublished',
        assessmentId: event.params.assessmentId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      for (const staffId of staffIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", staffId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyCalendar !== false && staffData.fcmTokens) {
            const docRef = staffSnap.docs[0].ref;
            staffData.fcmTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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

      console.log(`カレンダー追加通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onCalendarEventCreated',
        eventId: event.params.eventId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      for (const staffId of staffIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", staffId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyCalendar !== false && staffData.fcmTokens) {
            const docRef = staffSnap.docs[0].ref;
            staffData.fcmTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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

      console.log(`カレンダー変更通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onCalendarEventUpdated',
        eventId: event.params.eventId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      for (const staffId of staffIds) {
        const staffSnap = await db
          .collection("staffs")
          .where("uid", "==", staffId)
          .limit(1)
          .get();

        if (!staffSnap.empty) {
          const staffData = staffSnap.docs[0].data();
          if (staffData.notifyCalendar !== false && staffData.fcmTokens) {
            const docRef = staffSnap.docs[0].ref;
            staffData.fcmTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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

      console.log(`カレンダー削除通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onCalendarEventDeleted',
        eventId: event.params.eventId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      if (isAllStaff) {
        // fcmTokensが存在するスタッフのみ取得
        const staffSnap = await db.collection("staffs")
          .where("fcmTokens", "!=", [])
          .get();
        for (const doc of staffSnap.docs) {
          const staffData = doc.data();
          const classrooms = staffData.classrooms || [];
          const isPlus = classrooms.some((c) => c.includes("プラス"));
          if (isPlus && staffData.notifyPlusSchedule !== false) {
            const docRef = doc.ref;
            staffData.fcmTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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
              const docRef = staffSnap.docs[0].ref;
              staffData.fcmTokens.forEach((t) => {
                tokens.push(t);
                tokenDocMap.push({ token: t, docRef });
              });
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

      console.log(`プラス追加通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onPlusLessonCreated',
        lessonId: event.params.lessonId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      if (isAllStaff) {
        // fcmTokensが存在するスタッフのみ取得
        const staffSnap = await db.collection("staffs")
          .where("fcmTokens", "!=", [])
          .get();
        for (const doc of staffSnap.docs) {
          const staffData = doc.data();
          const classrooms = staffData.classrooms || [];
          const isPlus = classrooms.some((c) => c.includes("プラス"));
          if (isPlus && staffData.notifyPlusSchedule !== false) {
            const docRef = doc.ref;
            staffData.fcmTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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
              const docRef = staffSnap.docs[0].ref;
              staffData.fcmTokens.forEach((t) => {
                tokens.push(t);
                tokenDocMap.push({ token: t, docRef });
              });
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

      console.log(`プラス変更通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onPlusLessonUpdated',
        lessonId: event.params.lessonId,
        error: error.message || String(error),
      }));
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
      const tokenDocMap = [];

      if (isAllStaff) {
        // fcmTokensが存在するスタッフのみ取得
        const staffSnap = await db.collection("staffs")
          .where("fcmTokens", "!=", [])
          .get();
        for (const doc of staffSnap.docs) {
          const staffData = doc.data();
          const classrooms = staffData.classrooms || [];
          const isPlus = classrooms.some((c) => c.includes("プラス"));
          if (isPlus && staffData.notifyPlusSchedule !== false) {
            const docRef = doc.ref;
            staffData.fcmTokens.forEach((t) => {
              tokens.push(t);
              tokenDocMap.push({ token: t, docRef });
            });
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
              const docRef = staffSnap.docs[0].ref;
              staffData.fcmTokens.forEach((t) => {
                tokens.push(t);
                tokenDocMap.push({ token: t, docRef });
              });
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

      console.log(`プラス削除通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
      await cleanupInvalidTokens(response, tokenDocMap);
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onPlusLessonDeleted',
        lessonId: event.params.lessonId,
        error: error.message || String(error),
      }));
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
exports.createParentAccount = onCall({ region: 'asia-northeast1', secrets: [initialPassword] }, async (request) => {
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
      password: initialPassword.value(),
      emailVerified: false,
    });

    // Custom Claims を設定（セキュリティルールで role 判定に使用）
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
    console.error(JSON.stringify({ function: 'deleteParentAccount', targetUid, familyDocId, error: error.message }));
    throw new HttpsError('internal', error.message);
  }
});

/**
 * スタッフアカウントを作成する
 */
exports.createStaffAccount = onCall({ region: 'asia-northeast1', secrets: [initialPassword] }, async (request) => {
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
      password: initialPassword.value(),
      emailVerified: false,
    });

    // Custom Claims を設定（セキュリティルールで role 判定に使用）
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
    console.error(JSON.stringify({ function: 'deleteStaffAccount', targetUid, staffDocId, error: error.message }));
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
      
      console.log(`入退室通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);

      // 無効トークンをクリーンアップ（familyDocIdがある場合）
      if (data.familyDocId && response.failureCount > 0) {
        const familyRef = db.collection('families').doc(data.familyDocId);
        const tokenDocMap = fcmTokens.map((t) => ({ token: t, docRef: familyRef }));
        await cleanupInvalidTokens(response, tokenDocMap);
      }

      await event.data.ref.update({
        processed: true,
        processedAt: FieldValue.serverTimestamp(),
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
      
      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'sendAttendanceNotification',
        docId: event.params.docId,
        error: error.message || String(error),
      }));
      await event.data.ref.update({
        processed: true,
        processedAt: FieldValue.serverTimestamp(),
        error: error.message || String(error),
      });
      return null;
    }
  }
);

// ==========================================
// AI チャット機能（個別支援計画相談）
// ==========================================

/**
 * システムプロンプトを構築
 */
function buildSystemPrompt(context) {
  const { studentInfo, supportPlan, recentMonitorings, hugAssessment, isFreeChat } = context || {};

  // 自由チャット（生徒を選択していない場合）は最小限のプロンプト
  if (isFreeChat || !studentInfo) {
    return '日本語で回答してください。';
  }

  let prompt = `あなたは児童発達支援施設「Bee Smiley」の個別支援計画作成を支援する専門AIアシスタントです。

## あなたの役割
- 児童発達支援に関する専門的な知識を活用して、スタッフの相談に応じます
- 個別支援計画の作成・見直しをサポートします
- 子どもの発達段階や特性に応じた具体的なアドバイスを提供します

## 個別支援計画の構成項目
1. 長期目標
2. 短期目標
3. 健康と生活
4. 運動と感覚
5. 認知行動
6. 言語コミュニケーション
7. 人間関係や社会性
8. 家族支援
9. 移行支援
10. 地域支援

## 重要なルール
- モニタリングで「継続」とした達成目標は変更しないでください
- 支援内容は箇条書きではなく、一文で完結する形式で記述してください
- 考察や説明は簡潔にまとめてください
- 専門用語を使う場合は、必要に応じて補足説明を加えてください

## 出力フォーマットの指示
- マークダウン記法（**太字**、*イタリック*、###見出し など）は絶対に使用しないでください
- アスタリスク（*）は使用禁止です
- 見出しや強調が必要な場合は、「【】」や「■」「●」などの記号を使ってください
- 箇条書きには「・」や「-」を使ってください

`;

  prompt += `
## 相談対象の児童情報
- 氏名: ${studentInfo.lastName || ''} ${studentInfo.firstName || ''}
- 年齢: ${studentInfo.age || '不明'}
- 性別: ${studentInfo.gender || '不明'}
- 所属クラス: ${studentInfo.classroom || '不明'}
- 診断: ${studentInfo.diagnosis || '記載なし'}

`;

  if (supportPlan) {
    prompt += `
## 現在の個別支援計画
- 長期目標: ${supportPlan.longTermGoal || '未設定'}
`;
    if (supportPlan.shortTermGoals && supportPlan.shortTermGoals.length > 0) {
      prompt += `- 短期目標:\n`;
      supportPlan.shortTermGoals.forEach((g, i) => {
        prompt += `  ${i + 1}. ${g.goal || ''} (${g.category || ''})\n`;
      });
    }
    prompt += '\n';
  }

  if (recentMonitorings && recentMonitorings.length > 0) {
    prompt += `
## 直近のモニタリング結果
`;
    recentMonitorings.forEach(m => {
      let dateStr = '日付不明';
      if (m.date && m.date.toDate) {
        dateStr = m.date.toDate().toLocaleDateString('ja-JP');
      } else if (m.date && m.date._seconds) {
        dateStr = new Date(m.date._seconds * 1000).toLocaleDateString('ja-JP');
      }
      prompt += `- ${dateStr}: ${m.nextActions || '特記事項なし'}\n`;
    });
    prompt += '\n';
  }

  if (hugAssessment) {
    prompt += `
## HUGアセスメント情報（スタッフがHUGシステムから入力した情報）
${hugAssessment}

`;
  }

  // 過去セッションの要約を注入
  const pastSummaries = context.pastSummaries;
  if (pastSummaries && pastSummaries.length > 0) {
    prompt += `
## 過去の相談履歴（要約）
以下は過去の相談セッションの要約です。この文脈を踏まえて回答してください。
`;
    pastSummaries.forEach(s => {
      prompt += `- ${s.date}: ${s.summary}\n`;
    });
    prompt += '\n';
  }

  prompt += `
上記の情報を踏まえて、スタッフからの相談に丁寧に回答してください。
`;

  return prompt;
}

/**
 * 会話履歴を要約する
 */
async function summarizeConversation(genAI, messages, existingSummary) {
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

  let conversationText = '';
  messages.forEach(msg => {
    const role = msg.role === 'user' ? 'スタッフ' : 'AI';
    conversationText += `${role}: ${msg.content}\n\n`;
  });

  let summaryPrompt = `以下の会話を簡潔に要約してください。要点を箇条書きで整理し、300文字以内にまとめてください。

`;

  if (existingSummary) {
    summaryPrompt += `【これまでの要約】
${existingSummary}

【追加の会話】
${conversationText}

上記を統合して、新しい要約を作成してください。`;
  } else {
    summaryPrompt += `【会話内容】
${conversationText}`;
  }

  const result = await model.generateContent(summaryPrompt);
  return result.response.text();
}

/**
 * AIチャットメッセージを送信
 */
exports.sendAiMessage = onCall(
  {
    region: 'asia-northeast1',
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }

    const { sessionId, message, context, commandScript } = request.data;

    if (!sessionId || !message) {
      throw new HttpsError('invalid-argument', 'sessionIdとmessageが必要です');
    }

    const MESSAGE_THRESHOLD = 20;  // 要約を開始するメッセージ数
    const RECENT_MESSAGE_COUNT = 10;  // 要約後に保持する最新メッセージ数

    try {
      const sessionRef = db.collection('ai_chat_sessions').doc(sessionId);
      const messagesRef = sessionRef.collection('messages');

      // 1. ユーザーメッセージをFirestoreに保存
      await messagesRef.add({
        role: 'user',
        content: message,
        createdAt: FieldValue.serverTimestamp(),
        status: 'sent',
      });

      // 2. セッション情報を取得（要約があるか確認）
      const sessionDoc = await sessionRef.get();
      const sessionData = sessionDoc.data() || {};
      let existingSummary = sessionData.summary || null;

      // 3. 全メッセージ数を確認
      const allMessagesSnap = await messagesRef
        .orderBy('createdAt', 'asc')
        .get();

      const totalMessageCount = allMessagesSnap.docs.length;
      console.log(`Total messages: ${totalMessageCount}, Threshold: ${MESSAGE_THRESHOLD}`);

      // 4. Gemini API クライアント初期化
      const genAI = new GoogleGenerativeAI(geminiApiKey.value());

      // 5. メッセージ数が閾値を超えている場合、要約を作成
      if (totalMessageCount > MESSAGE_THRESHOLD && !existingSummary) {
        // 最新10件を除いた古いメッセージを要約
        const oldMessages = allMessagesSnap.docs.slice(0, -RECENT_MESSAGE_COUNT);
        const oldMessagesData = oldMessages.map(doc => doc.data());

        console.log(`Summarizing ${oldMessagesData.length} old messages...`);
        existingSummary = await summarizeConversation(genAI, oldMessagesData, null);

        // 要約をセッションに保存
        await sessionRef.update({
          summary: existingSummary,
          summarizedAt: FieldValue.serverTimestamp(),
        });
        console.log('Summary created and saved.');
      } else if (totalMessageCount > MESSAGE_THRESHOLD + 10 && existingSummary) {
        // 既に要約があり、さらに10件増えたら要約を更新
        const messagesToSummarize = allMessagesSnap.docs.slice(0, -RECENT_MESSAGE_COUNT);
        const newMessagesCount = messagesToSummarize.length;

        // 前回要約時からのメッセージ数を概算（10件単位で更新）
        const lastSummarizedCount = sessionData.lastSummarizedCount || MESSAGE_THRESHOLD - RECENT_MESSAGE_COUNT;

        if (newMessagesCount >= lastSummarizedCount + 10) {
          console.log(`Updating summary with ${newMessagesCount - lastSummarizedCount} new messages...`);

          // 前回要約後の新しいメッセージだけを取得
          const newOldMessages = messagesToSummarize.slice(lastSummarizedCount);
          const newOldMessagesData = newOldMessages.map(doc => doc.data());

          existingSummary = await summarizeConversation(genAI, newOldMessagesData, existingSummary);

          await sessionRef.update({
            summary: existingSummary,
            summarizedAt: FieldValue.serverTimestamp(),
            lastSummarizedCount: newMessagesCount,
          });
          console.log('Summary updated.');
        }
      }

      // 6. 会話履歴を構築
      let chatHistory = [];

      if (existingSummary) {
        // 要約がある場合：要約 + 最新10件
        const recentMessages = allMessagesSnap.docs.slice(-RECENT_MESSAGE_COUNT);

        // 要約をシステムコンテキストとして最初に追加
        chatHistory.push({
          role: 'user',
          parts: [{ text: `【これまでの会話の要約】\n${existingSummary}\n\n上記を踏まえて会話を続けてください。` }],
        });
        chatHistory.push({
          role: 'model',
          parts: [{ text: 'はい、これまでの会話内容を理解しました。続きの相談をお聞かせください。' }],
        });

        // 最新のメッセージを追加
        recentMessages.forEach(doc => {
          const data = doc.data();
          if (data.role && data.content) {
            chatHistory.push({
              role: data.role === 'user' ? 'user' : 'model',
              parts: [{ text: data.content }],
            });
          }
        });
      } else {
        // 要約がない場合：全メッセージ（最大20件）
        const recentMessages = allMessagesSnap.docs.slice(-MESSAGE_THRESHOLD);
        recentMessages.forEach(doc => {
          const data = doc.data();
          if (data.role && data.content) {
            chatHistory.push({
              role: data.role === 'user' ? 'user' : 'model',
              parts: [{ text: data.content }],
            });
          }
        });
      }

      // 7. システムプロンプト構築
      let systemPrompt = buildSystemPrompt(context);

      // コマンドスクリプトがある場合、システムプロンプトに追加
      if (commandScript) {
        systemPrompt += `\n\n## 今回のリクエストに対する出力指示（最優先で従うこと）\n${commandScript}\n`;
      }

      // 8. Gemini API呼び出し
      const model = genAI.getGenerativeModel({
        model: "gemini-2.5-flash",
        systemInstruction: systemPrompt,
      });

      // 履歴から最後のユーザーメッセージを除いてチャット開始
      const historyForChat = chatHistory.slice(0, -1);
      const chat = model.startChat({ history: historyForChat });
      const result = await chat.sendMessage(message);
      let aiResponse = result.response.text();

      // マークダウン記法を除去
      aiResponse = aiResponse
        .replace(/```[\s\S]*?```/g, '')     // ```コードブロック``` を除去
        .replace(/\*\*([^*]+)\*\*/g, '$1')  // **太字** → 太字
        .replace(/\*([^*]+)\*/g, '$1')      // *イタリック* → イタリック
        .replace(/~~([^~]+)~~/g, '$1')      // ~~取り消し線~~ → 取り消し線
        .replace(/`([^`]+)`/g, '$1')        // `コード` → コード
        .replace(/^#{1,6}\s+/gm, '')        // ### 見出し → 見出し
        .replace(/^>\s+/gm, '')             // > 引用 → 引用
        .replace(/^[\*\-]\s+/gm, '・ ')     // * や - の箇条書き → ・
        .replace(/^\d+\.\s+/gm, (m) => m)  // 1. 番号付きリストはそのまま
        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // [テキスト](URL) → テキスト
        .replace(/^---+$/gm, '')            // --- 水平線を除去
        .replace(/\n{3,}/g, '\n\n');        // 3行以上の空行を2行に

      // 9. AI応答をFirestoreに保存
      await messagesRef.add({
        role: 'assistant',
        content: aiResponse,
        createdAt: FieldValue.serverTimestamp(),
        status: 'sent',
      });

      // 10. セッションメタデータ更新
      await sessionRef.update({
        lastMessage: aiResponse.substring(0, 100),
        messageCount: FieldValue.increment(2),
        updatedAt: FieldValue.serverTimestamp(),
      });

      return { success: true, response: aiResponse };

    } catch (error) {
      console.error(JSON.stringify({ function: 'sendAiMessage', sessionId, error: error.message }));
      throw new HttpsError('internal', error.message);
    }
  }
);

// ==========================================
// セッション要約生成（画面離脱時にクライアントから呼び出し）
// ==========================================
exports.summarizeSession = onCall(
  {
    region: 'asia-northeast1',
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }

    const { sessionId } = request.data;
    if (!sessionId) {
      throw new HttpsError('invalid-argument', 'sessionIdが必要です');
    }

    try {
      const sessionRef = db.collection('ai_chat_sessions').doc(sessionId);
      const sessionDoc = await sessionRef.get();

      if (!sessionDoc.exists) {
        return { success: false, reason: 'session_not_found' };
      }

      const sessionData = sessionDoc.data();

      // 既に要約がある場合はスキップ（sendAiMessage内の要約と重複しないよう）
      if (sessionData.summary) {
        return { success: true, reason: 'already_summarized' };
      }

      // メッセージを取得
      const messagesSnap = await sessionRef
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .get();

      // メッセージが3件未満なら要約不要
      if (messagesSnap.docs.length < 3) {
        return { success: false, reason: 'not_enough_messages' };
      }

      const messages = messagesSnap.docs.map(doc => doc.data());

      // Gemini APIで要約生成
      const genAI = new GoogleGenerativeAI(geminiApiKey.value());
      const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

      let conversationText = '';
      messages.forEach(msg => {
        const role = msg.role === 'user' ? 'スタッフ' : 'AI';
        conversationText += `${role}: ${msg.content}\n\n`;
      });

      const summaryPrompt = `以下の相談内容を3〜5文で簡潔に要約してください。重要な決定事項や次のアクションがあれば含めてください。

【会話内容】
${conversationText}`;

      const result = await model.generateContent(summaryPrompt);
      const summary = result.response.text();

      // 要約をセッションに保存
      await sessionRef.update({
        summary: summary,
        summarizedAt: FieldValue.serverTimestamp(),
      });

      console.log(`Session ${sessionId} summarized: ${summary.substring(0, 50)}...`);
      return { success: true, summary: summary };

    } catch (error) {
      console.error(JSON.stringify({ function: 'summarizeSession', sessionId, error: error.message }));
      throw new HttpsError('internal', error.message);
    }
  }
);

// ==========================================
// 既存ユーザーへの Custom Claims マイグレーション
// ==========================================
exports.migrateCustomClaims = onCall({ region: 'asia-northeast1' }, async (request) => {
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

  let staffCount = 0;
  let familyCount = 0;

  // 全スタッフに role: 'staff' を設定
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

  // 全保護者に role: 'parent' を設定
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
// hug連携: 保存済みコンテンツをhugに下書き登録
// ==========================================

const HUG_BASE_URL = 'https://www.hug-beesmiley.link/hug/wm';

/**
 * Cookie文字列をヘッダー用に整形するヘルパー
 */
function parseCookies(setCookieHeaders) {
  if (!setCookieHeaders) return '';
  const headers = Array.isArray(setCookieHeaders) ? setCookieHeaders : [setCookieHeaders];
  return headers
    .map((h) => h.split(';')[0])
    .join('; ');
}

/**
 * fetch wrapper: Cookie付きリクエストを送る
 */
async function hugFetch(url, options = {}, cookies = '') {
  const headers = { ...(options.headers || {}) };
  if (cookies) {
    headers['Cookie'] = cookies;
  }
  return fetch(url, { ...options, headers, redirect: 'manual' });
}

/**
 * Cookieをマージするヘルパー
 */
function mergeCookies(existing, newCookies) {
  const cookieMap = {};
  [existing, newCookies].forEach((cs) => {
    if (!cs) return;
    cs.split('; ').forEach((c) => {
      const eqIdx = c.indexOf('=');
      if (eqIdx > 0) {
        const key = c.substring(0, eqIdx);
        cookieMap[key] = c;
      }
    });
  });
  return Object.values(cookieMap).join('; ');
}

/**
 * hugにログインしてセッションCookieを取得
 *
 * hugログインフォーム構造（調査済み）:
 *   action="/hug/wm/"  method="post"
 *   hidden: mode=login_pass, mode_token=nomode, csrf_token_from_client=..., hug_page_url=index.php
 *   text:   name="username"
 *   password: name="password"
 */
/**
 * リダイレクトを手動で追従しながらcookieを確実に収集するヘルパー
 */
async function fetchWithCookies(url, options = {}, cookies = '', maxRedirects = 5) {
  let currentUrl = url;
  let currentCookies = cookies;

  for (let i = 0; i < maxRedirects; i++) {
    const headers = { ...(options.headers || {}) };
    if (currentCookies) headers['Cookie'] = currentCookies;

    const res = await fetch(currentUrl, { ...options, headers, redirect: 'manual' });
    currentCookies = mergeCookies(currentCookies, parseCookies(res.headers.raw()['set-cookie']));

    console.log(`fetchWithCookies[${i}]: ${options.method || 'GET'} ${currentUrl} → ${res.status}`);

    if (res.status === 301 || res.status === 302 || res.status === 303 || res.status === 307) {
      const location = res.headers.get('location');
      if (!location) break;
      currentUrl = location.startsWith('http')
        ? location
        : `https://www.hug-beesmiley.link${location.startsWith('/') ? '' : '/'}${location}`;
      console.log(`fetchWithCookies[${i}]: redirect → ${currentUrl}`);
      // POST後のリダイレクトはGETに変更
      if (options.method === 'POST' && (res.status === 302 || res.status === 303)) {
        options = {};
      }
      continue;
    }

    return { res, cookies: currentCookies, html: await res.text() };
  }
  throw new Error('Too many redirects');
}

async function loginToHug() {
  const username = hugUsername.value();
  const password = hugPassword.value();
  const loginUrl = 'https://www.hug-beesmiley.link/hug/wm/';

  // 1. ログインページをGET（リダイレクトを手動追従しcookieを確実に収集）
  const getResult = await fetchWithCookies(loginUrl);
  let cookies = getResult.cookies;
  const $ = cheerio.load(getResult.html);

  console.log(`hug login page cookies: ${cookies ? 'obtained' : 'none'}`);

  // CSRFトークン等のhiddenフィールドを全て取得
  const formData = {};
  $('form input[type="hidden"]').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) formData[name] = value;
  });

  // ユーザー名・パスワードを追加
  formData['username'] = username;
  formData['password'] = password;

  console.log(`hug form fields: ${Object.keys(formData).join(', ')}`);
  console.log(`hug csrf token: ${formData['csrf_token_from_client'] ? 'present' : 'missing'}`);

  // 2. CSRFトークン検証（hugはsubmit前にajax_token.phpで検証が必要）
  const csrfToken = formData['csrf_token_from_client'] || '';
  const modeToken = formData['mode_token'] || 'nomode';
  const hugPageUrl = formData['hug_page_url'] || 'index.php';
  const tokenCheckUrl = `https://www.hug-beesmiley.link/hug/wm/ajax/ajax_token.php?token=${csrfToken}&mode=${modeToken}&hug_page_url=${hugPageUrl}`;
  const tokenCheckResult = await fetchWithCookies(tokenCheckUrl, {}, cookies);
  cookies = tokenCheckResult.cookies;
  console.log(`hug csrf token check result: ${tokenCheckResult.html.trim()}`);

  // 3. ログインPOST（リダイレクトを手動追従）
  const postResult = await fetchWithCookies(loginUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(formData).toString(),
  }, cookies);

  cookies = postResult.cookies;
  const responseHtml = postResult.html;

  console.log(`hug login POST response status: ${postResult.res.status}`);
  console.log(`hug login POST cookies: ${cookies ? cookies.substring(0, 100) : 'none'}`);

  // レスポンスHTMLのtitleを確認
  const $post = cheerio.load(responseHtml);
  const pageTitle = $post('title').text().trim();
  console.log(`hug login POST page title: ${pageTitle}`);
  // ログインフォーム周辺のHTMLを抽出（エラーメッセージを確認）
  const loginFormIdx = responseHtml.indexOf('loginForm');
  const bodyIdx = responseHtml.indexOf('<body');
  const relevantStart = loginFormIdx > 0 ? loginFormIdx - 200 : (bodyIdx > 0 ? bodyIdx : 0);
  console.log(`hug login POST html snippet: ${responseHtml.substring(relevantStart, relevantStart + 800).replace(/\s+/g, ' ')}`);

  // ログイン成功確認: レスポンスHTMLにログインフォームが含まれていないかチェック
  if (responseHtml.includes('name="password"') && responseHtml.includes('ログインID')) {
    // エラーメッセージがあるか確認
    const errorMsg = $post('.error, .alert, .warning, #error').text().trim();
    console.error(`hug login failed. Error on page: ${errorMsg || 'none'}`);
    throw new Error(`hug login failed: ログインに失敗しました。ID/パスワードを確認してください。${errorMsg ? ' (' + errorMsg + ')' : ''}`);
  }

  console.log('hug login successful');
  return cookies;
}

/**
 * 記録一覧ページから児童名→r_id, c_idのマッピングを構築
 *
 * 一覧ページの構造（調査済み）:
 *   - 編集ボタン: <button onclick="...mode=edit&id={r_id}&...&c_id={c_id}...">
 *   - 児童名: 同じ<tr>の2番目<td>に「松崎晃大さん」のように表示
 *   - 児童ドロップダウン: <select> に全児童の name→c_id マッピングあり
 */
async function getChildRecordIds(cookies, date) {
  const url = `${HUG_BASE_URL}/contact_book.php?f_id=1&date=${date}&state=clear`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const childMap = {}; // { 児童名: { rId, cId } }

  // 編集ボタンのonclickからr_id, c_idを抽出
  $('button').each((_, el) => {
    const onclick = $(el).attr('onclick') || '';
    const idMatch = onclick.match(/id=(\d+)/);
    const cidMatch = onclick.match(/c_id=(\d+)/);
    if (idMatch && cidMatch && onclick.includes('mode=edit')) {
      const rId = idMatch[1];
      const cId = cidMatch[1];

      // 同じ行の児童名を取得（2番目のtd）
      const row = $(el).closest('tr');
      const nameCell = row.find('td').eq(1).text().trim();
      // 「さん」を除去して名前を取得
      const name = nameCell.replace(/さん.*$/, '').trim();

      if (name && cId) {
        childMap[name] = { rId, cId, calDate: date };
      }
    }
  });

  // プレビューリンクからも取得（バックアップ）
  $('a[href*="mode=preview"]').each((_, el) => {
    const href = $(el).attr('href') || '';
    const idMatch = href.match(/id=(\d+)/);
    const cidMatch = href.match(/c_id=(\d+)/);
    if (idMatch && cidMatch) {
      const rId = idMatch[1];
      const cId = cidMatch[1];

      const row = $(el).closest('tr');
      const nameCell = row.find('td').eq(1).text().trim();
      const name = nameCell.replace(/さん.*$/, '').trim();

      if (name && cId && !childMap[name]) {
        childMap[name] = { rId, cId, calDate: date };
      }
    }
  });

  console.log(`Found ${Object.keys(childMap).length} children on ${date}`);
  return childMap;
}

/**
 * 児童の編集ページからフォームhiddenフィールドを全取得
 */
async function getEditPageFields(cookies, rId, calDate, cId) {
  const url = `${HUG_BASE_URL}/contact_book.php?mode=edit&id=${rId}&cal_date=${calDate}&c_id=${cId}`;
  console.log('[getEditPageFields] URL:', url);
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  // デバッグ: フォーム内の全フィールドを列挙
  const allFieldNames = [];
  $('form input').each((_, el) => {
    allFieldNames.push(`input[${$(el).attr('type')}] name=${$(el).attr('name')}`);
  });
  $('form textarea').each((_, el) => {
    allFieldNames.push(`textarea name=${$(el).attr('name')}`);
  });
  $('form select').each((_, el) => {
    allFieldNames.push(`select name=${$(el).attr('name')}`);
  });
  console.log('[getEditPageFields] ALL form fields:', JSON.stringify(allFieldNames));

  const fields = {};
  $('form input[type="hidden"]').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) fields[name] = value;
  });

  // selectのデフォルト値も取得
  $('form select').each((_, el) => {
    const name = $(el).attr('name');
    const selectedValue = $(el).find('option[selected]').attr('value') || $(el).find('option').first().attr('value') || '';
    if (name && !fields[name]) fields[name] = selectedValue;
  });

  // textareaの値も取得
  $('form textarea').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).text() || '';
    if (name && !fields[name]) fields[name] = value;
  });

  return fields;
}

/**
 * hugに記録を下書き保存
 */
async function saveDraftToHug(cookies, formFields, recordStaffId, staffNote) {
  console.log('[saveDraft] formFields keys:', Object.keys(formFields));
  console.log('[saveDraft] formFields:', JSON.stringify(formFields));

  const postData = new URLSearchParams({
    ...formFields,
    mode: 'regist',
    state: '1', // 1=下書き
    record_staff: recordStaffId,
    note: staffNote,       // コメント欄（保護者に公開される方）
    staff_note: '',        // ケア記録・生活記録欄（職員共有欄）
  });

  console.log('[saveDraft] POST body:', postData.toString().substring(0, 500));

  const res = await hugFetch(`${HUG_BASE_URL}/contact_book.php`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: postData.toString(),
  }, cookies);

  const responseText = await res.text();
  console.log('[saveDraft] response status:', res.status);
  console.log('[saveDraft] response body (first 1000):', responseText.substring(0, 1000));

  // リダイレクト（302）または200が返れば成功
  return res.status === 302 || res.status === 200;
}

/**
 * Firestoreのhugマッピング設定を取得
 * hug_settings/child_mapping: { "児童名": "hugのc_id" }
 * hug_settings/staff_mapping: { "記録者名": "hugのrecord_staff ID" }
 */
async function getHugMappings() {
  const childDoc = await db.collection('hug_settings').doc('child_mapping').get();
  const staffDoc = await db.collection('hug_settings').doc('staff_mapping').get();

  return {
    childMapping: childDoc.exists ? childDoc.data() : {},
    staffMapping: staffDoc.exists ? staffDoc.data() : {},
  };
}

/**
 * スペース（半角・全角）を除去して名前を正規化
 */
function normalizeName(name) {
  return (name || '').replace(/[\s\u3000]/g, '');
}

/**
 * マッピングからスペースを無視して検索
 * 例: "土持 諒人" → "土持諒人" でマッチ
 */
function findMapping(mapping, name) {
  // 完全一致を先に試す
  if (mapping[name] !== undefined) return mapping[name];
  // スペース除去して比較
  const normalized = normalizeName(name);
  for (const [key, value] of Object.entries(mapping)) {
    if (normalizeName(key) === normalized) return value;
  }
  return undefined;
}

/**
 * メイン同期処理（HTTPトリガーとスケジュールトリガーで共有）
 */
async function syncToHugCore(contentIds = null) {
  // 1. Firestoreから保存済みコンテンツを取得
  let query = db.collection('saved_ai_contents');

  let snapshot;
  if (contentIds && contentIds.length > 0) {
    // 指定されたドキュメントIDだけを処理
    const docs = await Promise.all(
      contentIds.map((id) => db.collection('saved_ai_contents').doc(id).get())
    );
    snapshot = docs.filter((d) => d.exists);
  } else {
    // 全件取得
    const result = await query.get();
    snapshot = result.docs;
  }

  if (snapshot.length === 0) {
    return { success: true, message: '処理対象なし', successCount: 0, failCount: 0, errors: [] };
  }

  // 2. hugのマッピング設定を取得
  const { childMapping, staffMapping } = await getHugMappings();

  // 3. hugにログイン
  const cookies = await loginToHug();

  // 4. 日付ごとに一覧ページを取得してr_idマップを構築（キャッシュ）
  const dateRecordCache = {}; // { 'YYYY-MM-DD': childMap }

  let successCount = 0;
  let failCount = 0;
  const errors = [];

  for (const doc of snapshot) {
    const docData = doc.data ? doc.data() : doc.data;
    const docRef = doc.ref || doc;
    const docId = doc.id;

    try {
      const studentName = docData.studentName || '';
      const dateTs = docData.date;
      const content = docData.content || '';
      const recorderName = docData.recorderName || '';

      // 日付をYYYY-MM-DD形式に変換
      let dateStr;
      if (dateTs && dateTs.toDate) {
        const d = dateTs.toDate();
        dateStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      } else if (typeof dateTs === 'string') {
        dateStr = dateTs;
      } else {
        throw new Error('日付が不正です');
      }

      // 児童名 → hug c_id のマッピング（スペース無視で検索）
      const hugChildId = findMapping(childMapping, studentName);
      if (!hugChildId) {
        throw new Error(`児童「${studentName}」のhugマッピングが未設定です。hug_settings/child_mappingに登録してください。`);
      }

      // 記録者名 → hug record_staff ID のマッピング（スペース無視で検索）
      const hugStaffId = findMapping(staffMapping, recorderName);
      if (!hugStaffId) {
        throw new Error(`記録者「${recorderName}」のhugマッピングが未設定です。hug_settings/staff_mappingに登録してください。`);
      }

      // 一覧ページから該当日のr_idを取得（キャッシュ）
      if (!dateRecordCache[dateStr]) {
        dateRecordCache[dateStr] = await getChildRecordIds(cookies, dateStr);
      }
      const childRecords = dateRecordCache[dateStr];

      // 児童名またはc_idでr_idを検索
      let recordInfo = childRecords[studentName];
      if (!recordInfo) {
        // 名前で見つからない場合、c_idで探す
        for (const [, info] of Object.entries(childRecords)) {
          if (info.cId === hugChildId) {
            recordInfo = info;
            break;
          }
        }
      }

      if (!recordInfo) {
        // 一覧に出ない場合は新規作成として直接編集ページにアクセス
        recordInfo = { rId: 'insert', cId: hugChildId, calDate: dateStr };
      }

      // 編集ページからフォーム情報取得
      const formFields = await getEditPageFields(cookies, recordInfo.rId, recordInfo.calDate || dateStr, recordInfo.cId || hugChildId);

      // 下書き保存
      const success = await saveDraftToHug(cookies, formFields, hugStaffId, content);

      if (success) {
        // Firestoreから該当ドキュメントを削除
        await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
        successCount++;
        console.log(`Successfully synced: ${studentName} (${dateStr})`);
      } else {
        failCount++;
        errors.push({ docId, studentName, error: 'hugへの保存に失敗しました' });
      }
    } catch (error) {
      console.error(`Error processing ${docId}:`, error.message);
      failCount++;
      errors.push({ docId, studentName: docData.studentName || '', error: error.message });
    }
  }

  return { success: true, successCount, failCount, errors };
}

/**
 * HTTPトリガー: 管理画面の「hugへ送信」ボタンから呼び出し
 */
exports.syncToHug = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 120,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    // スタッフ認証チェック
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }

    // contentIds が指定されていれば、その分だけ処理（UI側から選択送信対応）
    const contentIds = request.data?.contentIds || null;

    try {
      const result = await syncToHugCore(contentIds);
      return result;
    } catch (error) {
      console.error('syncToHug error:', error);
      throw new HttpsError('internal', `hug同期エラー: ${error.message}`);
    }
  }
);

/**
 * スケジュールトリガー: 毎日18時に自動実行
 */
/**
 * hugマッピング設定を管理するCloud Function
 * hug一覧ページをスクレイピングして児童名・スタッフ名とIDの対応を自動取得
 */
exports.fetchHugMappings = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 60,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }

    try {
      const cookies = await loginToHug();

      // 今日の日付で一覧ページを取得
      const today = new Date();
      const dateStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
      const url = `${HUG_BASE_URL}/contact_book.php?f_id=1&date=${dateStr}&state=clear`;
      const res = await hugFetch(url, {}, cookies);
      const html = await res.text();
      const $ = cheerio.load(html);

      // 児童情報をドロップダウンselectから抽出（全児童が含まれる）
      const children = [];
      const seen = new Set();
      $('select option').each((_, el) => {
        const value = $(el).attr('value') || '';
        const text = $(el).text().trim();
        // 児童名のoption: valueが数字で、textが日本語名（五十音indexやラベルを除外）
        if (value && /^\d+$/.test(value) && text && text !== '--' && text !== '----'
            && text.length > 1 && !/^[ぁ-ん]$/.test(text) && !seen.has(value)) {
          seen.add(value);
          children.push({ name: text, cId: value });
        }
      });

      // 編集ページからスタッフ情報を取得（最初の児童の編集ページを使用）
      const staffList = [];
      if (children.length > 0) {
        const firstChild = children[0];
        const editUrl = `${HUG_BASE_URL}/contact_book.php?mode=edit&id=insert&cal_date=${dateStr}&c_id=${firstChild.cId}`;
        const editRes = await hugFetch(editUrl, {}, cookies);
        const editHtml = await editRes.text();
        const $edit = cheerio.load(editHtml);

        $edit('select[name="record_staff"] option').each((_, el) => {
          const value = $edit(el).attr('value') || '';
          const text = $edit(el).text().trim();
          if (value && text) {
            staffList.push({ name: text, staffId: value });
          }
        });
      }

      return { success: true, children, staffList };
    } catch (error) {
      console.error('fetchHugMappings error:', error);
      throw new HttpsError('internal', `hugマッピング取得エラー: ${error.message}`);
    }
  }
);

const { onSchedule } = require("firebase-functions/v2/scheduler");

exports.syncToHugScheduled = onSchedule(
  {
    schedule: '0 18 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 120,
    secrets: [hugUsername, hugPassword],
  },
  async () => {
    try {
      const result = await syncToHugCore();
      console.log('Scheduled sync result:', JSON.stringify(result));
    } catch (error) {
      console.error('Scheduled syncToHug error:', error);
    }
  }
);

