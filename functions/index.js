// Firebase Cloud Functions for Push Notifications & Account Management (v2)

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { Anthropic } = require("@anthropic-ai/sdk");
const fetch = require("node-fetch");
const cheerio = require("cheerio");
const { CookieJar, Cookie } = require("tough-cookie");

// Secret Manager でAPIキー・初期パスワードを管理
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const initialPassword = defineSecret("INITIAL_PASSWORD");
const hugUsername = defineSecret("HUG_USERNAME");
const hugPassword = defineSecret("HUG_PASSWORD");

// Claudeモデル定義
const CLAUDE_MAIN_MODEL = 'claude-sonnet-4-6';
const CLAUDE_SUMMARY_MODEL = 'claude-haiku-4-5-20251001';

/**
 * Claude API呼び出しの共通ラッパー（リトライ＋プロンプトキャッシュ対応）
 *
 * @param {object} params
 * @param {string} params.model - モデルID
 * @param {Array|string} params.system - systemプロンプト。配列にする場合は各要素に
 *     { type: 'text', text: '...', cache_control: { type: 'ephemeral' } } を含められる
 * @param {Array} params.messages - [{ role, content }]
 * @param {number} [params.maxTokens=2048]
 * @param {number} [params.maxRetries=3]
 */
async function callClaude({ model, system, messages, maxTokens = 2048, maxRetries = 3 }) {
  const client = new Anthropic({ apiKey: anthropicApiKey.value() });
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const response = await client.messages.create({
        model,
        max_tokens: maxTokens,
        system,
        messages,
      });
      const textBlocks = (response.content || []).filter((b) => b.type === 'text');
      const text = textBlocks.map((b) => b.text).join('\n').trim();
      console.log(`[Claude] model=${model} input=${response.usage?.input_tokens} cached=${response.usage?.cache_read_input_tokens || 0} output=${response.usage?.output_tokens}`);
      return text;
    } catch (err) {
      const status = err?.status || 0;
      const retryable = status === 429 || status === 500 || status === 503 || status === 529;
      if (retryable && attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 2000 + Math.random() * 1000;
        console.log(`[Claude] retry ${attempt + 1}/${maxRetries} after ${Math.round(delay)}ms (status=${status})`);
        await new Promise((r) => setTimeout(r, delay));
        continue;
      }
      throw err;
    }
  }
}

/**
 * Claudeのストリーミング API でデルタ受信ごとに onDelta(fullText, chunk) を呼ぶ。
 */
async function callClaudeStream({ model, system, messages, maxTokens = 4096, maxRetries = 3, onDelta }) {
  const client = new Anthropic({ apiKey: anthropicApiKey.value() });
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const stream = await client.messages.stream({
        model,
        max_tokens: maxTokens,
        system,
        messages,
      });
      let fullText = '';
      for await (const event of stream) {
        if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') {
          const chunk = event.delta.text || '';
          fullText += chunk;
          if (onDelta) {
            try { await onDelta(fullText, chunk); } catch (e) { console.warn('onDelta error:', e.message); }
          }
        }
      }
      const final = await stream.finalMessage();
      console.log(`[Claude-stream] model=${model} input=${final.usage?.input_tokens} cached=${final.usage?.cache_read_input_tokens || 0} output=${final.usage?.output_tokens}`);
      return fullText;
    } catch (err) {
      const status = err?.status || 0;
      const retryable = status === 429 || status === 500 || status === 503 || status === 529;
      if (retryable && attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 2000 + Math.random() * 1000;
        console.log(`[Claude-stream] retry ${attempt + 1}/${maxRetries} after ${Math.round(delay)}ms (status=${status})`);
        await new Promise((r) => setTimeout(r, delay));
        continue;
      }
      throw err;
    }
  }
}

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
          body: message.type === "image"
            ? "画像を送信しました"
            : message.type === "video"
            ? "動画を送信しました"
            : message.type === "file"
            ? "ファイルを送信しました"
            : message.text,
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
          const isTarget = children.some((child) => {
            // classrooms(配列)と旧classroom(文字列)の両方に対応
            const cls = child.classrooms || (child.classroom ? [child.classroom] : []);
            return cls.some((c) => targetClassrooms.includes(c));
          });
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
## HUGアセスメント情報（手動入力フォールバック）
${hugAssessment}

`;
  }

  // HUGドキュメント（自動同期された5種類の最新情報）
  const hugDocs = context.hugDocs;
  if (hugDocs && typeof hugDocs === 'object') {
    const labels = {
      assessment: 'アセスメント',
      carePlanDraft: '個別支援計画書(原案)',
      beforeMeeting: 'サービス担当者会議(支援会議)の議事録',
      carePlanMain: '個別支援計画書',
      monitoring: 'モニタリング',
    };
    const sections = [];
    for (const [key, label] of Object.entries(labels)) {
      const doc = hugDocs[key];
      if (doc && doc.rawText) {
        sections.push(`### ${label}\n${doc.rawText}`);
      }
    }
    if (sections.length > 0) {
      prompt += `
## HUGから自動取得した最新情報（同期済み）
${sections.join('\n\n')}

`;
    }
  }

  // AI児童プロファイル（蓄積された知見）
  const aiProfile = context.aiProfile;
  if (aiProfile && typeof aiProfile === 'object') {
    const sections = [];
    const labels = {
      strengths: '得意・好きなこと',
      challenges: '課題・苦手なこと',
      triggers: '不安・混乱のきっかけ',
      effectiveApproaches: '効果のあった支援方法',
      currentGoals: '現在の目標',
      recentWins: '最近の成功体験',
      familyContext: '家族関係のメモ',
      staffNotes: '担当者メモ',
    };
    for (const [key, label] of Object.entries(labels)) {
      const v = aiProfile[key];
      if (!v) continue;
      if (Array.isArray(v) && v.length > 0) {
        sections.push(`### ${label}\n${v.map((x) => `・${x}`).join('\n')}`);
      } else if (typeof v === 'string' && v.trim()) {
        sections.push(`### ${label}\n${v.trim()}`);
      }
    }
    if (sections.length > 0) {
      prompt += `
## この子について蓄積された知見（過去の相談から学んだこと）
${sections.join('\n\n')}

`;
    }
  }

  // 過去セッションの要約を注入（直近N件）
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
 * 会話履歴を要約する（Claude Haikuで処理、安価で十分な品質）
 */
async function summarizeConversation(messages, existingSummary) {
  let conversationText = '';
  messages.forEach(msg => {
    const role = msg.role === 'user' ? 'スタッフ' : 'AI';
    conversationText += `${role}: ${msg.content}\n\n`;
  });

  let summaryPrompt = `以下の会話を簡潔に要約してください。要点を箇条書きで整理し、300文字以内にまとめてください。\n\n`;

  if (existingSummary) {
    summaryPrompt += `【これまでの要約】\n${existingSummary}\n\n【追加の会話】\n${conversationText}\n上記を統合して、新しい要約を作成してください。`;
  } else {
    summaryPrompt += `【会話内容】\n${conversationText}`;
  }

  return await callClaude({
    model: CLAUDE_SUMMARY_MODEL,
    system: '日本語で回答してください。指示に従って簡潔にまとめてください。',
    messages: [{ role: 'user', content: summaryPrompt }],
    maxTokens: 600,
  });
}

/**
 * AIチャットメッセージを送信
 */
exports.sendAiMessage = onCall(
  {
    region: 'asia-northeast1',
    secrets: [anthropicApiKey],
    timeoutSeconds: 120,
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
    const RECENT_SUMMARY_COUNT = 10; // 過去セッション要約を何件まで渡すか

    try {
      // コンテキストを拡張: HUG自動同期データ＆AIプロファイル＆過去セッション要約をサーバー側で読み込み
      const studentId = context?.studentInfo?.studentId;
      const enrichedContext = { ...(context || {}) };
      if (studentId) {
        try {
          const profileDoc = await db.collection('ai_student_profiles').doc(studentId).get();
          if (profileDoc.exists) {
            const pd = profileDoc.data() || {};
            if (pd.hugDocs) enrichedContext.hugDocs = pd.hugDocs;
            if (pd.aiProfile) enrichedContext.aiProfile = pd.aiProfile;
          }
          // 過去セッション要約を時系列で取得
          const summariesSnap = await db
            .collection('ai_student_profiles').doc(studentId)
            .collection('session_summaries')
            .orderBy('endedAt', 'desc')
            .limit(RECENT_SUMMARY_COUNT)
            .get();
          if (!summariesSnap.empty) {
            enrichedContext.pastSummaries = summariesSnap.docs.reverse().map((d) => {
              const s = d.data();
              const date = s.endedAt?.toDate ? s.endedAt.toDate().toLocaleDateString('ja-JP') : '';
              return { date, summary: s.summary || '' };
            });
          }
        } catch (e) {
          console.warn(`[sendAiMessage] profile load failed for ${studentId}:`, e.message);
        }
      }
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

      // 4. 長大セッションの要約更新（Claude Haikuで処理）
      if (totalMessageCount > MESSAGE_THRESHOLD && !existingSummary) {
        const oldMessages = allMessagesSnap.docs.slice(0, -RECENT_MESSAGE_COUNT);
        const oldMessagesData = oldMessages.map(doc => doc.data());
        console.log(`Summarizing ${oldMessagesData.length} old messages...`);
        existingSummary = await summarizeConversation(oldMessagesData, null);
        await sessionRef.update({
          summary: existingSummary,
          summarizedAt: FieldValue.serverTimestamp(),
        });
      } else if (totalMessageCount > MESSAGE_THRESHOLD + 10 && existingSummary) {
        const messagesToSummarize = allMessagesSnap.docs.slice(0, -RECENT_MESSAGE_COUNT);
        const newMessagesCount = messagesToSummarize.length;
        const lastSummarizedCount = sessionData.lastSummarizedCount || MESSAGE_THRESHOLD - RECENT_MESSAGE_COUNT;
        if (newMessagesCount >= lastSummarizedCount + 10) {
          const newOldMessages = messagesToSummarize.slice(lastSummarizedCount);
          const newOldMessagesData = newOldMessages.map(doc => doc.data());
          existingSummary = await summarizeConversation(newOldMessagesData, existingSummary);
          await sessionRef.update({
            summary: existingSummary,
            summarizedAt: FieldValue.serverTimestamp(),
            lastSummarizedCount: newMessagesCount,
          });
        }
      }

      // 5. Claude向け messages 構築
      const claudeMessages = [];
      if (existingSummary) {
        const recentMessages = allMessagesSnap.docs.slice(-RECENT_MESSAGE_COUNT);
        claudeMessages.push({
          role: 'user',
          content: `【これまでの会話の要約】\n${existingSummary}\n\n上記を踏まえて会話を続けてください。`,
        });
        claudeMessages.push({
          role: 'assistant',
          content: 'はい、これまでの会話内容を理解しました。続きの相談をお聞かせください。',
        });
        recentMessages.forEach((doc) => {
          const data = doc.data();
          if (data.role && data.content) {
            claudeMessages.push({
              role: data.role === 'user' ? 'user' : 'assistant',
              content: data.content,
            });
          }
        });
      } else {
        const recentMessages = allMessagesSnap.docs.slice(-MESSAGE_THRESHOLD);
        recentMessages.forEach((doc) => {
          const data = doc.data();
          if (data.role && data.content) {
            claudeMessages.push({
              role: data.role === 'user' ? 'user' : 'assistant',
              content: data.content,
            });
          }
        });
      }

      // 6. システムプロンプト構築（キャッシュ可能な静的部分と動的部分に分割）
      const baseSystemPrompt = buildSystemPrompt(enrichedContext);
      const systemBlocks = [
        { type: 'text', text: baseSystemPrompt, cache_control: { type: 'ephemeral' } },
      ];
      if (commandScript) {
        systemBlocks.push({
          type: 'text',
          text: `\n\n## 今回のリクエストに対する出力指示（最優先で従うこと）\n${commandScript}\n`,
        });
      }

      // マークダウン除去用ヘルパー
      const stripMarkdown = (s) => (s || '')
        .replace(/```[\s\S]*?```/g, '')
        .replace(/\*\*([^*]+)\*\*/g, '$1')
        .replace(/\*([^*]+)\*/g, '$1')
        .replace(/~~([^~]+)~~/g, '$1')
        .replace(/`([^`]+)`/g, '$1')
        .replace(/^#{1,6}\s+/gm, '')
        .replace(/^>\s+/gm, '')
        .replace(/^[\*\-]\s+/gm, '・ ')
        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
        .replace(/^---+$/gm, '')
        .replace(/\n{3,}/g, '\n\n');

      // 7. Claude Sonnet 4.6 に投げる
      let aiResponse;
      if (commandScript) {
        // 構造化出力コマンドはストリーミング不要、単発リクエストで十分
        const augmentedMessage = `${message}\n\n---\n【出力指示】以下の指示に厳密に従って出力してください。会話形式や補足説明は不要です。指定されたフォーマットのみを出力してください。\n${commandScript}`;
        aiResponse = await callClaude({
          model: CLAUDE_MAIN_MODEL,
          system: systemBlocks,
          messages: [{ role: 'user', content: augmentedMessage }],
          maxTokens: 4096,
        });
        aiResponse = stripMarkdown(aiResponse);
        await messagesRef.add({
          role: 'assistant',
          content: aiResponse,
          createdAt: FieldValue.serverTimestamp(),
          status: 'sent',
        });
      } else {
        // 通常会話はストリーミングで逐次Firestoreへ反映
        const assistantDoc = await messagesRef.add({
          role: 'assistant',
          content: '',
          createdAt: FieldValue.serverTimestamp(),
          status: 'streaming',
        });

        let lastUpdate = 0;
        const UPDATE_INTERVAL_MS = 400;
        const onDelta = async (fullText) => {
          const now = Date.now();
          if (now - lastUpdate > UPDATE_INTERVAL_MS) {
            lastUpdate = now;
            await assistantDoc.update({ content: stripMarkdown(fullText) });
          }
        };

        const streamed = await callClaudeStream({
          model: CLAUDE_MAIN_MODEL,
          system: systemBlocks,
          messages: claudeMessages,
          maxTokens: 4096,
          onDelta,
        });

        aiResponse = stripMarkdown(streamed);
        // 最終確定: マークダウン除去済み＋ステータス更新
        await assistantDoc.update({
          content: aiResponse,
          status: 'sent',
          completedAt: FieldValue.serverTimestamp(),
        });
      }

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
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
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

      let conversationText = '';
      messages.forEach(msg => {
        const role = msg.role === 'user' ? 'スタッフ' : 'AI';
        conversationText += `${role}: ${msg.content}\n\n`;
      });

      const summaryPrompt = `以下の相談内容を3〜5文で簡潔に要約してください。重要な決定事項や次のアクションがあれば含めてください。

【会話内容】
${conversationText}`;

      const summary = await callClaude({
        model: CLAUDE_SUMMARY_MODEL,
        system: '日本語で簡潔に要約してください。',
        messages: [{ role: 'user', content: summaryPrompt }],
        maxTokens: 600,
      });

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

/**
 * セッション終了時に要約＋AIプロファイル更新を一括で行う。
 * - ai_student_profiles/{studentId}/session_summaries/{sessionId} にサマリ保存
 * - ai_student_profiles/{studentId}.aiProfile を差分更新
 * クライアントはユーザーが「このセッションを終了」or 画面離脱時に呼ぶ。
 */
exports.endAiSession = onCall(
  {
    region: 'asia-northeast1',
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    const { sessionId, studentId } = request.data || {};
    if (!sessionId) throw new HttpsError('invalid-argument', 'sessionIdが必要です');

    const sessionRef = db.collection('ai_chat_sessions').doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) return { success: false, reason: 'session_not_found' };
    const sessionData = sessionDoc.data() || {};
    const targetStudentId = studentId || sessionData.studentId;

    // 自由チャットや studentId 欠落時はスキップ（記録対象外）
    if (!targetStudentId) {
      return { success: false, reason: 'no_student_id' };
    }

    const messagesSnap = await sessionRef.collection('messages').orderBy('createdAt', 'asc').get();
    if (messagesSnap.docs.length < 3) {
      return { success: false, reason: 'not_enough_messages' };
    }

    const messages = messagesSnap.docs.map((d) => d.data());
    let conversationText = '';
    messages.forEach((msg) => {
      const role = msg.role === 'user' ? 'スタッフ' : 'AI';
      conversationText += `${role}: ${msg.content}\n\n`;
    });

    // 既存プロファイルを取得
    const profileRef = db.collection('ai_student_profiles').doc(targetStudentId);
    const profileDoc = await profileRef.get();
    const currentProfile = profileDoc.exists ? (profileDoc.data()?.aiProfile || {}) : {};

    // Claude Haiku に「要約＋プロファイル更新JSON」を1回で出力させる
    const prompt = `あなたは児童発達支援の記録を整理するアシスタントです。以下の相談会話を分析し、JSON形式で以下を出力してください。

出力JSONスキーマ:
{
  "sessionSummary": "この相談内容を200〜400字で要約。何を相談して何が分かったか。次に取り組むべきこと",
  "profile": {
    "strengths": ["得意・好きなこと（最大5件、重要な順）"],
    "challenges": ["課題・苦手なこと（最大5件、重要な順）"],
    "triggers": ["不安・混乱のきっかけ（最大5件）"],
    "effectiveApproaches": ["効果のあった支援方法（最大5件）"],
    "currentGoals": ["現在の目標（最大3件）"],
    "recentWins": ["最近の成功体験（最大5件、新しい順）"],
    "familyContext": "家族関係のメモ（2〜3文）",
    "staffNotes": "担当者メモ（2〜3文、運用上の留意点）"
  }
}

profileは新しい情報で更新してください。既存情報は引き続き重要なら残し、古くなったものや重複は整理して差し替えてください。情報が不足している項目は既存値を維持してください（省略してOK）。

【既存のプロファイル】
${JSON.stringify(currentProfile, null, 2)}

【今回の相談会話】
${conversationText}

JSONのみを出力してください。説明文・マークダウン（\`\`\`）は一切含めないでください。`;

    let aiOutput;
    try {
      aiOutput = await callClaude({
        model: CLAUDE_SUMMARY_MODEL,
        system: '日本語でJSON形式で回答してください。JSONオブジェクトのみを返し、説明文・マークダウンは一切含めないでください。',
        messages: [{ role: 'user', content: prompt }],
        maxTokens: 2000,
      });
    } catch (e) {
      console.error(`endAiSession Claude error:`, e.message);
      throw new HttpsError('internal', `要約生成エラー: ${e.message}`);
    }

    // JSON抽出（余計なマークダウンが入ったケースを救済）
    let parsed;
    try {
      const jsonText = aiOutput
        .replace(/^```json\s*/i, '')
        .replace(/^```\s*/i, '')
        .replace(/```\s*$/i, '')
        .trim();
      parsed = JSON.parse(jsonText);
    } catch (e) {
      console.error(`endAiSession JSON parse error:`, e.message, 'raw:', aiOutput.substring(0, 500));
      // パース失敗しても要約だけは保存
      parsed = { sessionSummary: aiOutput.substring(0, 500), profile: null };
    }

    const summary = (parsed.sessionSummary || '').toString().trim();
    const newProfile = parsed.profile || null;

    // セッション要約をサブコレクションに保存
    if (summary) {
      await profileRef.collection('session_summaries').doc(sessionId).set({
        sessionId,
        summary,
        endedAt: FieldValue.serverTimestamp(),
      });
      // ai_chat_sessions 側にも保存（履歴UIで即使えるよう）
      await sessionRef.update({
        endSummary: summary,
        endedAt: FieldValue.serverTimestamp(),
      });
    }

    // プロファイル更新（マージ）
    if (newProfile) {
      await profileRef.set({
        studentId: targetStudentId,
        aiProfile: {
          ...newProfile,
          version: (currentProfile.version || 0) + 1,
          updatedAt: new Date().toISOString(),
        },
      }, { merge: true });
    }

    console.log(`[endAiSession] ${sessionId} student=${targetStudentId} summary=${summary.length}chars profileUpdated=${!!newProfile}`);
    return { success: true, summary, profileUpdated: !!newProfile };
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
  // FormDataの場合、getHeaders()でContent-Typeにboundaryが含まれるため
  // headersのマージを慎重に行う
  const optHeaders = options.headers || {};
  const headers = (typeof optHeaders.getHeaders === 'function')
    ? { ...optHeaders }  // FormData.getHeaders()の結果はそのまま使う
    : { ...optHeaders };
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
async function saveDraftToHug(cookies, formFields, recordStaffId, noteText) {
  console.log('[saveDraft] formFields keys:', Object.keys(formFields));

  // hugのフォームはmultipart/form-dataで送信される
  // note（コメント欄）とnote_hide（hidden）の両方にセットする必要がある
  // staff_note（ケア記録）とstaff_note_hide（hidden）も同様
  const FormData = require('form-data');
  const formData = new FormData();

  // 既存のhiddenフィールドをセット
  for (const [key, value] of Object.entries(formFields)) {
    // note/note_hide/staff_note/staff_note_hide は後で上書きするのでスキップ
    if (['note', 'note_hide', 'staff_note', 'staff_note_hide', 'mode', 'state', 'record_staff'].includes(key)) continue;
    formData.append(key, value);
  }

  // 必須フィールド
  formData.append('mode', 'regist');
  formData.append('state', '1'); // 1=下書き
  formData.append('record_staff', recordStaffId);

  // コメント欄: noteとnote_hideの両方にAIテキストをセット
  formData.append('note', noteText);
  formData.append('note_hide', noteText);

  // ケア記録欄: 空
  formData.append('staff_note', '');
  formData.append('staff_note_hide', '');

  console.log('[saveDraft] sending multipart/form-data POST');

  // formData.getHeaders()でContent-Type（boundary含む）を取得し、Cookieとマージ
  const postHeaders = {
    ...formData.getHeaders(),
    'Cookie': cookies,
  };

  const res = await fetch(`${HUG_BASE_URL}/contact_book.php`, {
    method: 'POST',
    headers: postHeaders,
    body: formData,
    redirect: 'manual',
  });

  const responseText = await res.text();
  console.log('[saveDraft] response status:', res.status);
  console.log('[saveDraft] response body (first 500):', responseText.substring(0, 500));

  // リダイレクト（302）または200が返れば成功
  return res.status === 302 || res.status === 200;
}

/**
 * 各種加算・議事録管理 (record_proceedings.php) の編集ページから
 * hidden (CSRFトークン等) と加算種別マップを取得
 */
async function getRecordProceedingsForm(cookies) {
  const url = `${HUG_BASE_URL}/record_proceedings.php?mode=edit`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const hidden = {};
  $('form input[type="hidden"]').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) hidden[name] = value;
  });

  // 加算種別のマップ: ラベル(正規化済) → value
  const addingMap = {};
  $('select[name="adding_children_id"] option').each((_, el) => {
    const v = $(el).attr('value') || '';
    const t = ($(el).text() || '').trim();
    if (v && v !== '0' && t) addingMap[t] = v;
  });

  return { hidden, addingMap };
}

/**
 * ラベル(例:「子育てサポート」「子育てサポート加算」)から adding_children_id を解決
 */
function resolveAddingChildrenId(addingMap, categoryLabel) {
  const normalized = normalizeName(categoryLabel);
  for (const [label, id] of Object.entries(addingMap)) {
    const n = normalizeName(label);
    if (n === normalized) return id;
    if (n.includes(normalized) || normalized.includes(n)) return id;
  }
  return null;
}

/**
 * ajax_record_proceedings.php を叩いて、児童の f_id / s_id を取得
 * （画面上で児童選択時に走るAjaxをサーバから直接呼び出す）
 */
async function fetchChildFacilityService(cookies, childId, addingChildrenId, interviewDate) {
  const body = new URLSearchParams();
  body.append('rp_id', 'insert');
  body.append(`c_id_list[${childId}]`, String(childId));
  // 初回は f_id が不明なので 1 を仮で送る。単一施設テナントならこれで通る。
  body.append(`f_id_list[${childId}]`, '1');
  body.append('interview_date', interviewDate);
  body.append('adding_children_id', String(addingChildrenId));
  body.append('change_type', 'adding_children');
  body.append('mode', 'getData');

  const res = await fetch(`${HUG_BASE_URL}/ajax/ajax_record_proceedings.php`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'X-Requested-With': 'XMLHttpRequest',
      'Accept': '*/*',
      'Cookie': cookies,
    },
    body: body.toString(),
    redirect: 'manual',
  });
  const txt = await res.text();
  if (!txt) throw new Error('ajax_record_proceedings.php から空のレスポンス');
  let data;
  try { data = JSON.parse(txt); }
  catch (e) { throw new Error(`ajax_record_proceedings.php のJSONパースに失敗: ${e.message}`); }

  const facilityDom = (data.facility_dom || {})[childId] || '';
  const childrenInfo = (data.children_info || {})[childId] || '';

  // facility_dom から f_id を抽出（selected の option value）
  const fIdMatch = facilityDom.match(/value=["'](\d+)["']\s+selected/);
  const fId = fIdMatch ? fIdMatch[1] : null;

  // children_info HTML から s_id を抽出
  const sIdMatch = childrenInfo.match(/name=["']c_id_list\[\d+\]\[s_id\]["'][^>]*value=["'](\d+)["']/);
  const sId = sIdMatch ? sIdMatch[1] : null;

  if (!fId || !sId) {
    throw new Error(`児童(c_id=${childId})の契約施設/サービスが取得できません (f_id=${fId}, s_id=${sId})`);
  }
  return { fId, sId };
}

/**
 * 各種加算・議事録管理 (record_proceedings.php) に下書き保存
 */
async function saveToRecordProceedings(cookies, params) {
  const { hidden, addingChildrenId, childId, recorderStaffId, dateStr, title, content } = params;

  // interview_date は「YYYY年MM月DD日」形式
  const [y, m, d] = dateStr.split('-');
  const interviewDate = `${y}年${m}月${d}日`;

  // 児童の契約施設・サービスを動的取得
  const { fId, sId } = await fetchChildFacilityService(cookies, childId, addingChildrenId, interviewDate);
  console.log(`[recordProceedings] c_id=${childId} → f_id=${fId} s_id=${sId}`);

  const FormData = require('form-data');
  const formData = new FormData();

  // 後から明示的に送るフィールドは hidden の引き継ぎから除外
  // (同名で2回 append すると PHP は先頭値を採用するため空や0で上書きされる)
  // また c_id_list[0][...] は「未選択状態のプレースホルダ」。児童選択後は
  // c_id_list[<c_id>][...] に置き換わるべきなので、GET時の [0] は必ず捨てる。
  const skipKeys = new Set(['adding_children_id', 'mode', 'id', 'draft_flg', 'title']);
  for (const [key, value] of Object.entries(hidden)) {
    if (skipKeys.has(key)) continue;
    if (key.startsWith('c_id_list[0]')) continue;
    formData.append(key, value);
  }

  // 加算選択
  formData.append('adding_children_id', addingChildrenId);

  // タイトル（既存の手動入力レコードに揃えて空のまま送る）
  formData.append('title', '');

  // 児童（フォーム側は児童選択後に c_id_list[<c_id>][...] にフィールド名が変わる）
  formData.append(`c_id_list[${childId}][id]`, String(childId));
  formData.append(`c_id_list[${childId}][person_absence_note]`, '');
  formData.append(`c_id_list[${childId}][f_id]`, String(fId));
  formData.append(`c_id_list[${childId}][s_id]`, String(sId));

  // 記録者 / 対応スタッフ
  formData.append('recorder', String(recorderStaffId));
  formData.append('interview_staff[]', String(recorderStaffId));

  // 日時
  formData.append('interview_date', interviewDate);
  formData.append('start_hour', '');
  formData.append('start_time', '');
  formData.append('end_hour', '');
  formData.append('end_time', '');
  formData.append('start_hour2', '');
  formData.append('start_time2', '');
  formData.append('end_hour2', '');
  formData.append('end_time2', '');
  formData.append('add_date', '');
  formData.append('nursing_support_date', '');

  // 関係機関・相談支援事業所 (空)
  formData.append('ro_list[1][related_organizations]', '');
  formData.append('ro_list[1][related_organizations_manager]', '');
  formData.append('ro_list[2][related_organizations]', '');
  formData.append('ro_list[2][related_organizations_manager]', '');
  formData.append('support_office_id', '0');
  formData.append('support_office_manager', '');

  // 自由項目: タイトルに加算名、内容にAIテキスト
  formData.append('customize[title][]', title || '');
  formData.append('customize[contents][]', content || '');

  // 作成済みで保存（'draft' にすると下書き扱い）
  formData.append('draft_flg', 'created');
  formData.append('mode', 'regist');
  formData.append('id', 'insert');

  console.log('[recordProceedings] sending multipart POST',
    `adding_children_id=${addingChildrenId} c_id=${childId} f_id=${fId} s_id=${sId} recorder=${recorderStaffId} date=${interviewDate}`);

  const postHeaders = {
    ...formData.getHeaders(),
    'Cookie': cookies,
  };

  const res = await fetch(`${HUG_BASE_URL}/record_proceedings.php`, {
    method: 'POST',
    headers: postHeaders,
    body: formData,
    redirect: 'manual',
  });

  const body = await res.text();
  console.log('[recordProceedings] response status:', res.status, 'Location:', res.headers.get('location'));
  console.log('[recordProceedings] response body length:', body.length);

  // 成功時はリダイレクト(302)を返す。200はバリデーションエラーでフォームが再表示されている。
  if (res.status === 302) return true;

  // 200の場合はエラーメッセージを抽出。HUGはpタグやdiv.errなど色々なclassを使う。
  const $err = cheerio.load(body);
  const errorTexts = [];
  $err('.error, .alert, .warning, .msg_error, p.err, .err, [class*="error"]').each((_, el) => {
    const t = $err(el).text().trim();
    if (t && t.length > 3) errorTexts.push(t);
  });
  // ページタイトルも確認
  const pageTitle = $err('title').text().trim();
  console.error('[recordProceedings] page title:', pageTitle);
  console.error('[recordProceedings] validation errors:', JSON.stringify(errorTexts.slice(0, 10)));
  // body の一部をログに（エラー周辺を抽出）
  const bodyIdx = body.indexOf('入力内容に誤り');
  const errIdx = body.search(/err|error|alert/i);
  const snippetIdx = bodyIdx > 0 ? bodyIdx : (errIdx > 0 ? errIdx : 0);
  console.error('[recordProceedings] body snippet:', body.substring(Math.max(0, snippetIdx - 200), snippetIdx + 800).replace(/\s+/g, ' '));

  throw new Error(
    errorTexts.length > 0
      ? `HUGのバリデーションエラー: ${errorTexts.slice(0, 3).join(' / ')}`
      : `HUG保存失敗 (status=${res.status})`
  );
}

/**
 * 指定日の出席表 (attendance.php?mode=detail) から
 * 児童 c_id に対応する編集URL/r_id/s_idなどを特定する
 *
 * HUGの編集URLは2パターンあることに注意:
 *   A) 未登録(id=insert): attendance.php?mode=edit&r_id=<rId>&id=insert&s_id=<sId>
 *   B) 登録済み:           attendance.php?mode=edit&id=<attendance_id>&s_id=<sId>
 */
async function findAttendanceRecord(cookies, childId, dateStr) {
  // 施設は単一(f_id=1)想定。必要なら将来的に全施設を探索。
  const detailUrl = `${HUG_BASE_URL}/attendance.php?mode=detail&f_id=1&date=${dateStr}`;
  const res = await hugFetch(detailUrl, {}, cookies);
  const html = await res.text();

  // mode=edit URL を全部抽出（順序問わず）
  const editUrlStrs = [...new Set(
    Array.from(html.matchAll(/attendance\.php\?[^"'\s<>]*mode=edit[^"'\s<>]*/g)).map(m => m[0])
  )];
  if (editUrlStrs.length === 0) {
    throw new Error(`${dateStr} の出席表が見つかりません (f_id=1)。HUG上で該当日の出席レコードが作成されているか確認してください。`);
  }

  // 個別編集ページの取得は HUG 側で時折空レスポンスや切断が起きるため、
  // 最大2回までリトライする（連続失敗が「時々失敗する」現象の主因）
  const fetchEditPage = async (u) => {
    let lastErr = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const r = await hugFetch(`${HUG_BASE_URL}/${u}`, {}, cookies);
        const h = await r.text();
        const $ = cheerio.load(h);
        const cId = $('input[name="c_id"]').attr('value') || '';
        const fId = $('input[name="f_id"]').attr('value') || '';
        const rId = $('input[name="r_id"]').attr('value') || '';
        const sId = $('input[name="s_id"]').attr('value') || '';
        // c_id が取れなかったらセッション切れ/ロード失敗の可能性があるので再試行
        if (!cId && attempt === 0) {
          await new Promise((res) => setTimeout(res, 300));
          continue;
        }
        return { editUrl: u, cId, fId, rId, sId };
      } catch (e) {
        lastErr = e;
        if (attempt === 0) await new Promise((res) => setTimeout(res, 300));
      }
    }
    return { editUrl: u, cId: '', fId: '', rId: '', sId: '', error: lastErr?.message || 'unknown' };
  };
  const results = await Promise.all(editUrlStrs.map(fetchEditPage));

  const match = results.find((r) => String(r.cId) === String(childId));
  if (!match) {
    const emptyCount = results.filter((r) => !r.cId).length;
    throw new Error(
      `c_id=${childId} の出席レコードが ${dateStr} 内に見つかりません。` +
      `検査対象: ${results.length}件, 空レス: ${emptyCount}件, c_ids=${results.map(r => r.cId).join(',')}`
    );
  }
  return match;
}

/**
 * attendance.php の編集ページから hidden フィールドを引き継ぎつつ、
 * 欠席時対応加算理由(absence_note)を埋めて保存する
 *
 * @param attendValue '2' = 欠席(加算あり) / '3' = 欠席(加算を取らない)
 */
async function saveToAttendance(cookies, params) {
  const { childId, dateStr, content, recorderStaffId } = params;
  const attendValue = params.attendValue || '2';
  const FormData = require('form-data');

  // POST + verify をまとめて 1 サイクル。
  // editUrl に id=insert が入る場合、1回目の POST はレコード作成(attend=1デフォルト)で終わり、
  // 2回目以降で初めて attend 値が反映される。よって毎サイクル findAttendanceRecord を
  // やり直して最新の editUrl（id=insert→numeric に切り替わった状態）を取得する。
  const MAX_CYCLES = 3;
  let lastCheckedAttend = null;
  let lastBody = '';
  let lastStatus = 0;
  let lastErrorTexts = [];
  let editUrl = '';

  for (let cycle = 0; cycle < MAX_CYCLES; cycle++) {
    if (cycle > 0) {
      await new Promise((res) => setTimeout(res, 600));
      console.log(`[attendance] retry cycle=${cycle + 1} for c_id=${childId} attend=${attendValue}`);
    }

    // 毎サイクル編集URLを取り直す（id=insert → numeric への切替を拾う）
    const record = await findAttendanceRecord(cookies, childId, dateStr);
    editUrl = `${HUG_BASE_URL}/${record.editUrl}`;
    const isInsert = /[?&]id=insert(&|$)/.test(record.editUrl);
    console.log(`[attendance] cycle=${cycle + 1} c_id=${childId} date=${dateStr} attend=${attendValue} editUrl=${record.editUrl} isInsert=${isInsert}`);

    // 編集ページを取得してフォームのhidden/select値を引き継ぐ
    const editRes = await hugFetch(editUrl, {}, cookies);
    const editHtml = await editRes.text();
    const $ = cheerio.load(editHtml);

    const fields = {};
    $('form input[type="hidden"]').each((_, el) => {
      const name = $(el).attr('name');
      const value = $(el).attr('value') || '';
      if (name) fields[name] = value;
    });
    $('form select').each((_, el) => {
      const name = $(el).attr('name');
      if (!name) return;
      const selected = $(el).find('option[selected]').attr('value');
      if (selected !== undefined) fields[name] = selected;
    });
    $('form textarea').each((_, el) => {
      const name = $(el).attr('name');
      const value = $(el).text() || '';
      if (name) fields[name] = value;
    });
    $('form input[type="radio"]:checked').each((_, el) => {
      const name = $(el).attr('name');
      const value = $(el).attr('value') || '';
      if (name) fields[name] = value;
    });

    const formData = new FormData();
    const skipKeys = new Set(['attend', 'attend_flg', 'absence_note', 'absence_note_staff', 'absence_note3', 'absence_note_staff3']);
    for (const [key, value] of Object.entries(fields)) {
      if (skipKeys.has(key)) continue;
      formData.append(key, value);
    }
    formData.append('attend', attendValue);
    formData.append('attend_flg', attendValue);
    if (attendValue === '3') {
      formData.append('absence_note_staff', '');
      formData.append('absence_note', '');
      formData.append('absence_note_staff3', '');
      formData.append('absence_note3', '');
    } else {
      formData.append('absence_note_staff', String(recorderStaffId || ''));
      formData.append('absence_note', content || '');
      formData.append('absence_note_staff3', String(recorderStaffId || ''));
      formData.append('absence_note3', content || '');
    }

    // form action が未指定の場合は現在URL（editUrl）にPOSTされるのでそちらに合わせる。
    // 過去の attendance.php への POST は mode/id が欠落して HUG が無効POSTとして扱うことがあり、
    // 302 を返しつつ状態を更新しない原因になっていた。
    const postUrl = editUrl;
    console.log(`[attendance] sending POST (cycle=${cycle + 1}) url=${postUrl} c_id=${childId} recorder=${recorderStaffId} attend=${attendValue}`);

    const postHeaders = {
      ...formData.getHeaders(),
      'Cookie': cookies,
    };
    const postRes = await fetch(postUrl, {
      method: 'POST',
      headers: postHeaders,
      body: formData,
      redirect: 'manual',
    });
    lastBody = await postRes.text();
    lastStatus = postRes.status;
    console.log(`[attendance] response status=${lastStatus} Location=${postRes.headers.get('location')}`);

    if (lastStatus !== 302 && lastStatus !== 200) {
      const $err = cheerio.load(lastBody);
      const errorTexts = [];
      $err('.error, .err, .alert, .warning, [class*="err"]').each((_, el) => {
        const t = $err(el).text().trim();
        if (t && t.length > 3) errorTexts.push(t);
      });
      lastErrorTexts = errorTexts;
      continue; // 次サイクルへ
    }

    // verify を 2 回まで（反映遅延対策）
    for (let vAttempt = 0; vAttempt < 2; vAttempt++) {
      if (vAttempt > 0) await new Promise((res) => setTimeout(res, 500));
      try {
        const verifyRes = await hugFetch(editUrl, {}, cookies);
        const verifyHtml = await verifyRes.text();
        const $v = cheerio.load(verifyHtml);
        lastCheckedAttend = $v('input[name="attend"]').filter((_, el) => $v(el).attr('checked') !== undefined).attr('value');
        console.log(`[attendance] verify(cycle=${cycle + 1},attempt=${vAttempt + 1}): checked attend=${lastCheckedAttend}, expected=${attendValue}`);
        if (String(lastCheckedAttend) === String(attendValue)) return true;
      } catch (e) {
        console.error('[attendance] verify fetch error:', e.message);
      }
    }
    // ここに来たら保存未反映→次サイクルで再試行
  }

  throw new Error(
    lastErrorTexts.length > 0
      ? `HUGのバリデーションエラー: ${lastErrorTexts.slice(0, 3).join(' / ')}`
      : `HUG保存に失敗しました（${MAX_CYCLES}回再試行後も attend=${lastCheckedAttend || '未設定'} のまま）。期待: ${attendValue} status=${lastStatus}`
  );
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

  // 各種加算・議事録管理用のフォーム情報はカテゴリ利用時にのみ初期化（lazy）
  let recordProceedingsForm = null;

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
      const category = docData.category || '';

      // 日付をYYYY-MM-DD形式に変換（JST = UTC+9）
      let dateStr;
      if (dateTs && dateTs.toDate) {
        const d = dateTs.toDate();
        // Cloud FunctionsはUTCで動くため、JSTに変換（+9時間）
        const jst = new Date(d.getTime() + 9 * 60 * 60 * 1000);
        dateStr = `${jst.getUTCFullYear()}-${String(jst.getUTCMonth() + 1).padStart(2, '0')}-${String(jst.getUTCDate()).padStart(2, '0')}`;
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

      // 欠席（加算なし）は記録者不要 (HUGフォーム側でabsence_note_staffは空で送信)
      const isNoAddAbsence =
        normalizeName(category).includes('欠席（加算なし）') ||
        normalizeName(category).includes('欠席(加算なし)');

      // 記録者名 → hug record_staff ID のマッピング（スペース無視で検索）
      const hugStaffId = findMapping(staffMapping, recorderName);
      if (!hugStaffId && !isNoAddAbsence) {
        throw new Error(`記録者「${recorderName}」のhugマッピングが未設定です。hug_settings/staff_mappingに登録してください。`);
      }

      // カテゴリが「欠席（加算なし）」系なら attendance.php に attend=3 で送信
      if (normalizeName(category).includes('欠席（加算なし）') || normalizeName(category).includes('欠席(加算なし)')) {
        const success = await saveToAttendance(cookies, {
          childId: hugChildId,
          dateStr,
          content: '',
          recorderStaffId: hugStaffId,
          attendValue: '3',
        });
        if (success) {
          await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
          successCount++;
          console.log(`[attendance:skip] synced: ${studentName} ${dateStr}`);
        } else {
          failCount++;
          errors.push({ docId, studentName, error: 'HUG（出席表・加算なし）への保存に失敗しました' });
        }
        continue;
      }

      // カテゴリが「欠席連絡」系なら attendance.php に attend=2 で送信
      if (normalizeName(category).includes('欠席連絡') || normalizeName(category).includes('欠席')) {
        const success = await saveToAttendance(cookies, {
          childId: hugChildId,
          dateStr,
          content,
          recorderStaffId: hugStaffId,
          attendValue: '2',
        });
        if (success) {
          await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
          successCount++;
          console.log(`[attendance] synced: ${studentName} ${dateStr} ${category}`);
        } else {
          failCount++;
          errors.push({ docId, studentName, error: 'HUG（出席表）への保存に失敗しました' });
        }
        continue;
      }

      // カテゴリが「子育てサポート」系なら record_proceedings.php に送信
      if (normalizeName(category).includes('子育てサポート')) {
        if (!recordProceedingsForm) {
          recordProceedingsForm = await getRecordProceedingsForm(cookies);
        }
        const { hidden, addingMap } = recordProceedingsForm;
        const addingChildrenId = resolveAddingChildrenId(addingMap, category);
        if (!addingChildrenId) {
          throw new Error(`HUGの加算一覧に「${category}」に該当する選択肢が見つかりません。`);
        }

        const success = await saveToRecordProceedings(cookies, {
          hidden,
          addingChildrenId,
          childId: hugChildId,
          recorderStaffId: hugStaffId,
          dateStr,
          title: category,
          content,
        });

        if (success) {
          await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
          successCount++;
          console.log(`[recordProceedings] synced: ${studentName} ${dateStr} ${category}`);
        } else {
          failCount++;
          errors.push({ docId, studentName, error: 'HUG（加算・議事録）への保存に失敗しました' });
        }
        continue;
      }

      // 一覧ページから該当日のr_idを取得（キャッシュ）
      if (!dateRecordCache[dateStr]) {
        dateRecordCache[dateStr] = await getChildRecordIds(cookies, dateStr);
      }
      const childRecords = dateRecordCache[dateStr];
      console.log(`[sync] Looking for "${studentName}" (c_id=${hugChildId}) in ${Object.keys(childRecords).length} records on ${dateStr}`);
      console.log(`[sync] Available children:`, JSON.stringify(Object.entries(childRecords).map(([k, v]) => `${k}(c_id=${v.cId},r_id=${v.rId})`)));

      // 児童名でr_idを検索（スペース無視で照合）
      let recordInfo = childRecords[studentName];
      if (!recordInfo) {
        // スペース無視で名前照合
        const normalizedStudent = normalizeName(studentName);
        for (const [name, info] of Object.entries(childRecords)) {
          if (normalizeName(name) === normalizedStudent) {
            recordInfo = info;
            console.log(`[sync] Name matched (normalized): "${name}" → rId=${info.rId}`);
            break;
          }
        }
      }
      if (!recordInfo) {
        // c_idで照合（文字列として比較）
        for (const [name, info] of Object.entries(childRecords)) {
          if (String(info.cId) === String(hugChildId)) {
            recordInfo = info;
            console.log(`[sync] Matched by c_id: "${name}" (c_id=${info.cId}) → rId=${info.rId}`);
            break;
          }
        }
      }

      if (!recordInfo) {
        // 療育記録が HUG 上に存在しない日は連携しない（新規作成はしない）。
        // HUG のポリシー: 療育に来ていない生徒の記録は作成不可。
        throw new Error(
          `${dateStr} に ${studentName}さんの HUG 療育記録が見つかりません。` +
          `HUG 上で該当日に療育記録が作成されていることを確認してから再試行してください。`
        );
      }

      console.log(`[sync] Using recordInfo: rId=${recordInfo.rId}, cId=${recordInfo.cId}, calDate=${recordInfo.calDate || dateStr}`);

      // 編集ページからフォーム情報取得
      const formFields = await getEditPageFields(cookies, recordInfo.rId, recordInfo.calDate || dateStr, recordInfo.cId || hugChildId);
      if (!formFields.c_id) {
        throw new Error(
          `${dateStr} の ${studentName}さんの編集ページが取得できません。HUG 上の記録状態を確認してください。`
        );
      }

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

// ==========================================
// HUGドキュメント自動同期（アセスメント/個別支援計画/議事録/モニタリング）
// ==========================================

const HUG_DOC_TYPES = {
  assessment:     { label: 'アセスメント',         urlPath: 'individual_assessment.php' },
  carePlanDraft:  { label: '個別支援計画書(原案)',   urlPath: 'individual_care-plan.php' },
  beforeMeeting:  { label: 'サービス担当者会議議事録', urlPath: 'individual_before-meeting.php' },
  carePlanMain:   { label: '個別支援計画書',         urlPath: 'individual_care-plan-main.php' },
  monitoring:     { label: 'モニタリング',           urlPath: 'individual_monitoring.php' },
};

/**
 * 状況一覧ページを全ページ巡回し、c_id ごとに最新（作成回数が最大）の行を返す。
 * 行構造（調査済み）:
 *   - 児童名リンク: profile_children.php?mode=profile&id={c_id}
 *   - 各ドキュメントリンク: individual_{type}.php?mode=detail&id={docId}
 *     ※未作成の場合は mode=edit や 「未作成」テキストで detail リンクなし
 *   - 作成回数: 3列目
 */
async function scrapeHugSituationList(cookies) {
  const rows = [];
  const seenPages = new Set();
  for (let page = 1; page <= 20; page++) {
    const url = `${HUG_BASE_URL}/individual_situation.php?page=${page}`;
    const res = await hugFetch(url, {}, cookies);
    const html = await res.text();
    const $ = cheerio.load(html);

    // 無限ループ防止: 同じHTMLが返る（最終ページ超過）なら終了
    const pageHash = html.length + ':' + (html.indexOf('<tbody') || 0);
    if (seenPages.has(pageHash)) break;
    seenPages.add(pageHash);

    const pageRowsBefore = rows.length;
    $('table tbody tr, table tr').each((_, tr) => {
      const $tr = $(tr);
      const childLink = $tr.find('a[href*="profile_children.php"]').first();
      if (!childLink.length) return;
      const childHref = childLink.attr('href') || '';
      const cIdMatch = childHref.match(/id=(\d+)/);
      if (!cIdMatch) return;
      const cId = cIdMatch[1];
      const childName = childLink.text().trim();
      if (!childName) return;

      // 状況一覧の「作成日」カラムは yyyy/mm/dd 形式の日付。
      // 非数字を除去して YYYYMMDD の8桁整数を作り、新旧比較に使う。
      const tdTexts = $tr.find('td').map((_, td) => $(td).text().trim().replace(/\s+/g, ' ')).get();
      const facility = tdTexts.find((t) => t.includes('教室')) || tdTexts[1] || '';
      let planDate = 0;
      for (const t of tdTexts) {
        const m = t.match(/^(\d{4})[\/\-.年](\d{1,2})[\/\-.月](\d{1,2})/);
        if (m) {
          planDate = parseInt(m[1] + m[2].padStart(2, '0') + m[3].padStart(2, '0'), 10);
          break;
        }
      }
      // フォールバック: 8桁の数字列（YYYYMMDD）が直接入っているケース
      if (planDate === 0) {
        for (const t of tdTexts) {
          const digits = t.replace(/[^0-9]/g, '');
          if (/^\d{8}$/.test(digits) && digits.startsWith('20')) {
            planDate = parseInt(digits, 10);
            break;
          }
        }
      }

      const docIds = {};
      for (const [type, cfg] of Object.entries(HUG_DOC_TYPES)) {
        const escaped = cfg.urlPath.replace(/\./g, '\\.').replace(/\-/g, '\\-');
        const pattern = new RegExp(escaped + '\\?mode=detail&id=(\\d+)');
        const link = $tr.find(`a[href*="${cfg.urlPath}?mode=detail"]`).first();
        if (link.length) {
          const href = link.attr('href') || '';
          const m = href.match(pattern);
          if (m) docIds[type] = m[1];
        }
      }

      rows.push({ cId, childName, planDate, facility, docIds });
    });

    if (rows.length === pageRowsBefore) break; // このページで行が見つからなければ終了

    // 次ページリンクが存在するかチェック
    const hasNext = $(`a[href*="individual_situation.php?page=${page + 1}"]`).length > 0;
    if (!hasNext) break;
  }

  // c_idごとに全行を集約し、ドキュメント種類ごとに「最新の作成日を持つ行」を選ぶ。
  // 最新行でそのドキュメントが未作成でも、過去行に存在すればそちらにフォールバックする。
  const byChild = {};
  for (const row of rows) {
    if (!byChild[row.cId]) {
      byChild[row.cId] = {
        cId: row.cId,
        childName: row.childName,
        facility: row.facility,
        latestPlanDate: 0,
        docMeta: {}, // type -> { hugId, planDate }
      };
    }
    const agg = byChild[row.cId];
    if (row.planDate > agg.latestPlanDate) {
      agg.latestPlanDate = row.planDate;
      agg.childName = row.childName;
      agg.facility = row.facility;
    }
    for (const [type, hugId] of Object.entries(row.docIds)) {
      if (!hugId) continue;
      const prev = agg.docMeta[type];
      if (!prev || row.planDate > prev.planDate) {
        agg.docMeta[type] = { hugId, planDate: row.planDate };
      }
    }
  }
  console.log(`[HUG] scraped situation list: ${rows.length} rows, ${Object.keys(byChild).length} unique children`);
  return Object.values(byChild);
}

/**
 * 指定ドキュメントの詳細ページHTMLからテキストを抽出
 * - ナビ・フッタ・操作ボタンを除去
 * - テーブル行を "ラベル: 値" 形式で連結
 */
function extractHugDocumentText(html) {
  const $ = cheerio.load(html);
  // ノイズ除去
  $('script, style, nav, header, footer').remove();
  $('.global-nav, #header_top, #header, #footer, .footer, .copyright, .breadcrumb, #sidemenu, #menu').remove();
  $('button, input[type="button"], input[type="submit"]').remove();
  $('a:contains("戻る"), a:contains("印刷"), a:contains("PDFを出力"), a:contains("編集する"), a:contains("ログアウト")').remove();

  const lines = [];
  const seen = new Set();
  const push = (s) => {
    if (!s) return;
    const t = s.replace(/\s+/g, ' ').trim();
    if (t && !seen.has(t)) { seen.add(t); lines.push(t); }
  };

  // タイトル
  const title = $('h1, h2').first().text().trim();
  if (title) push(`## ${title}`);

  // ヘッダ付近の情報（施設名・作成日等）
  $('dl, .info, .assessment-info, .right-box').each((_, el) => {
    const t = $(el).text().replace(/[\t\r]+/g, ' ').replace(/\n\s*\n/g, '\n').trim();
    if (t && t.length < 500) push(t);
  });

  // テーブル行を "ラベル: 値" に変換
  $('table').each((_, table) => {
    $(table).find('tr').each((_, row) => {
      const cells = $(row).find('th, td');
      if (cells.length === 0) return;
      const texts = cells.map((_, c) => $(c).text().replace(/[\t\r]+/g, ' ').replace(/\n\s*\n/g, '\n').trim()).get();
      if (cells.length === 1) {
        push(texts[0]);
      } else {
        const label = texts[0];
        const value = texts.slice(1).join(' / ');
        if (label && value) push(`${label}: ${value}`);
        else if (label) push(label);
      }
    });
  });

  return lines.join('\n');
}

async function fetchHugDocumentDetail(cookies, type, hugId) {
  const cfg = HUG_DOC_TYPES[type];
  if (!cfg) throw new Error(`unknown doc type: ${type}`);
  const url = `${HUG_BASE_URL}/${cfg.urlPath}?mode=detail&id=${hugId}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const rawText = extractHugDocumentText(html);
  return { url, rawText, hugId };
}

/**
 * HUG の連絡帳(ケア記録・生活記録)一覧を全児童分スクレイプ。
 * contact_book.php?mode=search を複数ページに渡って取得し、
 * 各行から c_id と日付・活動内容・出欠・記録者・プレビューID を抽出する。
 * 期間はクライアント側でフィルタ（HUG側の param 仕様不明なため）。
 *
 * @returns { Map<cId, Array<{date, activity, attendance, recorder, bookId}>> }
 */
async function scrapeHugCareRecords(cookies, fromDate, toDate, cIds) {
  const byChildId = {};
  let extractedCount = 0;
  const debugAttempts = [];

  // HUG の連絡帳一覧は検索フォーム (POST) で生徒 (children=c_id) と
  // 期間 (date, date_end) を指定しないとデータが返らないため、
  // 対象生徒ごとに個別に POST を投げる。
  // 日付書式は編集URL の cal_date と同じ YYYY-MM-DD（ハイフン区切り）を使う。
  const fromStr = formatYmdHyphen(fromDate);
  const toStr = formatYmdHyphen(toDate);

  const targetCIds = Array.isArray(cIds) ? cIds.filter(Boolean).map(String) : [];
  if (targetCIds.length === 0) {
    console.warn('[HUG] scrapeHugCareRecords: no target c_ids provided');
    return byChildId;
  }

  for (const cId of targetCIds) {
    const seenPages = new Set();

    for (let page = 1; page <= 50; page++) {
      const body = new URLSearchParams();
      body.append('mode', 'search');
      body.append('children', cId);
      body.append('date', fromStr);
      body.append('date_end', toStr);
      body.append('page', String(page));
      // 検索ボタン相当
      body.append('search', '1');

      const url = `${HUG_BASE_URL}/contact_book.php`;
      const res = await hugFetch(url, {
        method: 'POST',
        body,
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      }, cookies);
      const html = await res.text();
      const $ = cheerio.load(html);
      const pageHash = html.length + ':' + (html.indexOf('<tbody') || 0);
      if (seenPages.has(pageHash)) break;
      seenPages.add(pageHash);

      if (page === 1) {
        const tbodyRows = $('table tbody tr').length;
        const firstRowCells = $('table tbody tr').first().find('td').map((_, td) => $(td).text().replace(/\s+/g, ' ').trim()).get().slice(0, 12);
        debugAttempts.push({
          cId,
          page,
          htmlLength: html.length,
          tbodyRows,
          firstRowCells,
        });
        console.log(`[HUG] care records c_id=${cId} page=${page} tbodyRows=${tbodyRows}`);
      }

      let pageRows = 0;
      $('table tbody tr, table tr').each((_, tr) => {
        const $tr = $(tr);
        const cells = $tr.find('td').map((_, td) => $(td).text().replace(/\s+/g, ' ').trim()).get();
        if (cells.length === 0) return;

        let dateText = '';
        for (const c of cells) {
          if (/^\d{4}\/\d{1,2}\/\d{1,2}$/.test(c)) { dateText = c; break; }
        }
        if (!dateText) return;

        const recDate = parseHugDate(dateText);
        if (!recDate) return;
        if (recDate < fromDate || recDate > toDate) return;

        // プレビューリンク: contact_book.php?mode=preview&id=X&c_id=Y&s_id=Z
        const previewHref = $tr.find('a[href*="mode=preview"]').first().attr('href') || '';
        const bookIdMatch = previewHref.match(/[?&]id=(\d+)/);
        const rowCIdMatch = previewHref.match(/[?&]c_id=(\d+)/);
        const sIdMatch = previewHref.match(/[?&]s_id=(\d+)/);
        const bookId = bookIdMatch ? bookIdMatch[1] : null;
        const rowCId = rowCIdMatch ? rowCIdMatch[1] : cId;
        const sId = sIdMatch ? sIdMatch[1] : null;

        const activity = cells[3] || '';
        const attendance = cells[4] || '';
        let recorder = '';
        for (let i = cells.length - 1; i >= 0; i--) {
          const t = cells[i];
          if (/^\d{4}\/\d{1,2}\/\d{1,2}/.test(t)) continue;
          if (t.length > 1 && t.length < 20 && !/\d{4}/.test(t)) { recorder = t; break; }
        }

        if (!byChildId[rowCId]) byChildId[rowCId] = [];
        byChildId[rowCId].push({
          date: dateText,
          activity,
          attendance,
          recorder,
          bookId,
          cId: rowCId,
          sId,
        });
        pageRows++;
        extractedCount++;
      });

      if (pageRows === 0) break;
    }
  }

  console.log(`[HUG] care records: extracted ${extractedCount} rows across ${Object.keys(byChildId).length} children (searched ${targetCIds.length})`);
  try {
    await db.collection('hug_sync_logs').add({
      kind: 'care_records_debug',
      from: fromStr,
      to: toStr,
      extractedCount,
      childrenCount: Object.keys(byChildId).length,
      searchedCIds: targetCIds.length,
      attempts: debugAttempts.slice(0, 20),
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (_) {}
  return byChildId;
}

function formatYmdHyphen(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function parseHugDate(s) {
  const m = s.match(/^(\d{4})\/(\d{1,2})\/(\d{1,2})$/);
  if (!m) return null;
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
}

function formatYmd(d) {
  return `${d.getFullYear()}/${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * ケア記録のプレビュー本文（本日の様子）を取得
 */
async function fetchHugCareRecordBody(cookies, bookId, cId, sId) {
  const qs = new URLSearchParams({ mode: 'preview', id: String(bookId) });
  if (cId) qs.append('c_id', String(cId));
  if (sId) qs.append('s_id', String(sId));
  const url = `${HUG_BASE_URL}/contact_book.php?${qs.toString()}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);
  $('script, style, nav, header, footer, button').remove();
  $('#header, #footer, .print, #sidemenu').remove();
  // 「本日の様子」テーブルのセルのうち、長文が含まれるセルを本文として採用
  const bodies = [];
  $('table tr').each((_, tr) => {
    const tds = $(tr).find('td').map((_, td) => $(td).text().replace(/\s+/g, ' ').trim()).get();
    for (const t of tds) {
      if (t.length >= 10 && !/^\d{4}\/\d{1,2}\/\d{1,2}$/.test(t) && !t.includes('ビースマイリー')) {
        bodies.push(t);
      }
    }
  });
  return bodies.join('\n');
}

/**
 * HUG児童名 → Firestore studentId 解決
 * families コレクションをスキャンし、lastName+firstName が一致し、
 * ビースマイリープラス湘南藤沢の利用児童を探す。
 */
async function buildStudentNameIndex() {
  const snap = await db.collection('families').get();
  const index = {};
  for (const doc of snap.docs) {
    const data = doc.data();
    const lastName = (data.lastName || '').replace(/\s+/g, '');
    const familyUid = data.uid || doc.id;
    const children = data.children || [];
    for (const child of children) {
      const firstName = (child.firstName || '').replace(/\s+/g, '');
      if (!firstName) continue;
      const classrooms = child.classrooms || (child.classroom ? [child.classroom] : []);
      const inScope = classrooms.some((c) => typeof c === 'string' && c.includes('湘南藤沢'));
      if (!inScope) continue;
      const fullName = `${lastName}${firstName}`;
      const studentId = child.studentId || `${familyUid}_${firstName}`;
      index[fullName] = {
        studentId,
        studentName: `${data.lastName || ''} ${child.firstName || ''}`.trim(),
        familyUid,
      };
    }
  }
  return index;
}

/**
 * HUG 5種類ドキュメントを全対象児童について同期
 * - 1日1回のスケジュール＋UI からの手動実行を想定
 * - 書き込み先: ai_student_profiles/{studentId}（hugDocs フィールド配下）
 */
async function syncHugDocsCore(options = {}) {
  const targetStudentId = options.studentId || null; // 指定あれば1名のみ
  const cookies = await loginToHug();
  const situationRows = await scrapeHugSituationList(cookies);
  const nameIndex = await buildStudentNameIndex();

  // ケア記録スクレイプ対象の c_id を決定
  // - 単独同期 (targetStudentId 指定) の場合は該当児童だけ
  // - 全件同期の場合はマッピング済み児童全員
  const targetCIds = [];
  for (const row of situationRows) {
    const resolved = nameIndex[row.childName.replace(/\s+/g, '')];
    if (!resolved) continue;
    if (targetStudentId && resolved.studentId !== targetStudentId) continue;
    if (row.cId) targetCIds.push(row.cId);
  }

  // ケア記録: 過去6ヶ月分を対象児童ごとに POST 検索
  const toDate = new Date();
  const fromDate = new Date();
  fromDate.setMonth(fromDate.getMonth() - 6);
  let careRecordsByCId = {};
  try {
    careRecordsByCId = await scrapeHugCareRecords(cookies, fromDate, toDate, targetCIds);
  } catch (e) {
    console.error('[HUG] care records scrape failed:', e.message);
  }

  const summary = {
    totalChildren: situationRows.length,
    synced: 0,
    skippedUnmapped: 0,
    errors: [],
  };
  const unmapped = [];

  for (const row of situationRows) {
    const resolved = nameIndex[row.childName.replace(/\s+/g, '')];
    if (!resolved) {
      summary.skippedUnmapped++;
      unmapped.push({ hugChildName: row.childName, hugCId: row.cId });
      continue;
    }
    if (targetStudentId && resolved.studentId !== targetStudentId) continue;

    const hugDocs = {};
    for (const type of Object.keys(HUG_DOC_TYPES)) {
      const meta = row.docMeta?.[type];
      if (!meta) {
        hugDocs[type] = { status: 'not-created', fetchedAt: FieldValue.serverTimestamp() };
        continue;
      }
      try {
        const detail = await fetchHugDocumentDetail(cookies, type, meta.hugId);
        hugDocs[type] = {
          hugId: meta.hugId,
          rawText: detail.rawText,
          url: detail.url,
          status: 'ok',
          planDate: meta.planDate,
          fetchedAt: FieldValue.serverTimestamp(),
        };
      } catch (e) {
        console.error(`[HUG] detail fetch failed for ${row.childName} ${type}:`, e);
        hugDocs[type] = { status: 'error', error: e.message, fetchedAt: FieldValue.serverTimestamp() };
        summary.errors.push({ childName: row.childName, type, error: e.message });
      }
    }

    const careRecords = (careRecordsByCId[row.cId] || []).slice().sort((a, b) => b.date.localeCompare(a.date));
    // 最新5件にはプレビュー本文を先行取得（9分タイムアウト内に収めるため上限）
    for (const rec of careRecords.slice(0, 5)) {
      if (!rec.bookId || rec.body) continue;
      try {
        rec.body = await fetchHugCareRecordBody(cookies, rec.bookId, rec.cId, rec.sId);
      } catch (e) {
        console.warn(`[HUG] care record body fetch failed id=${rec.bookId}:`, e.message);
      }
    }

    await db.collection('ai_student_profiles').doc(resolved.studentId).set({
      studentId: resolved.studentId,
      studentName: resolved.studentName,
      familyUid: resolved.familyUid,
      hugCId: row.cId,
      hugDocs,
      latestPlanDate: row.latestPlanDate || 0,
      hugCareRecords: careRecords,
      hugCareRecordsRange: {
        from: formatYmd(fromDate),
        to: formatYmd(toDate),
      },
      lastSyncedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    summary.synced++;
  }

  // 未マッピング一覧を保存（マッピング画面で表示できるように）
  await db.collection('hug_settings').doc('unmapped_children').set({
    unmapped,
    updatedAt: FieldValue.serverTimestamp(),
  });

  // 実行ログ
  await db.collection('hug_sync_logs').add({
    kind: 'docs',
    summary,
    targetStudentId,
    startedAt: FieldValue.serverTimestamp(),
  });

  console.log(`[HUG] docs sync done:`, JSON.stringify(summary));
  return summary;
}

/**
 * 手動実行 (UI「今すぐ同期」or 管理画面)
 */
exports.syncHugDocs = onCall(
  {
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 540,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    try {
      const studentId = request.data?.studentId || null;
      const result = await syncHugDocsCore({ studentId });
      return { success: true, ...result };
    } catch (e) {
      console.error('syncHugDocs error:', e);
      throw new HttpsError('internal', `HUG同期エラー: ${e.message}`);
    }
  }
);

/**
 * ケア記録本文の遅延取得（フロントから個別記録を開くときに呼ぶ）。
 * 事前フェッチ (最新5件) 以外の古い記録もこの callable で読み込める。
 */
exports.fetchHugCareRecordBody = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 60,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    const bookId = request.data?.bookId;
    const cId = request.data?.cId;
    const sId = request.data?.sId;
    if (!bookId) throw new HttpsError('invalid-argument', 'bookId が必要です');
    try {
      const cookies = await loginToHug();
      const body = await fetchHugCareRecordBody(cookies, String(bookId), cId ? String(cId) : null, sId ? String(sId) : null);
      return { success: true, bookId: String(bookId), body };
    } catch (e) {
      console.error('fetchHugCareRecordBody error:', e);
      throw new HttpsError('internal', `HUG取得エラー: ${e.message}`);
    }
  }
);

/**
 * スケジュール実行: 毎朝6時JST
 */
exports.syncHugDocsScheduled = onSchedule(
  {
    schedule: '0 6 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 540,
    secrets: [hugUsername, hugPassword],
  },
  async () => {
    try {
      const result = await syncHugDocsCore();
      console.log('[HUG] scheduled docs sync:', JSON.stringify(result));
    } catch (e) {
      console.error('[HUG] scheduled docs sync error:', e);
    }
  }
);

// ==========================================
// マイグレーション: classroom → classrooms 配列
// デプロイ後にFlutterアプリからonCallで呼び出す
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

// ==========================================
// モニタリング下書き作成 (AI生成 → HUGに下書き保存)
// ==========================================

/**
 * モニタリング編集ページからフォームの全フィールド値と目標行構造を抽出する。
 * 既存値を保持したままPOSTで上書き保存するため、全input/select/textareaを読む。
 */
async function fetchMonitoringFormFields(cookies, monitoringId, cId, fId) {
  const url = `${HUG_BASE_URL}/individual_monitoring.php?mode=edit&id=${monitoringId}&c_id=${cId}&f_id=${fId}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);
  const form = $('form').first();
  if (!form.length) throw new Error('monitoring edit form not found');

  const fields = {};

  form.find('input[type="hidden"], input[type="text"], input[type="number"]').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    fields[name] = $(el).attr('value') || '';
  });

  form.find('input[type="radio"]').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    if ($(el).attr('checked') !== undefined) fields[name] = $(el).attr('value') || '';
  });

  form.find('input[type="checkbox"]').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    if ($(el).attr('checked') !== undefined) fields[name] = $(el).attr('value') || '1';
  });

  form.find('select').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    const selected = $(el).find('option[selected]').attr('value');
    if (selected !== undefined) fields[name] = selected;
    else {
      const first = $(el).find('option').first().attr('value');
      if (first !== undefined) fields[name] = first;
    }
  });

  form.find('textarea').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    fields[name] = $(el).text() || '';
  });

  // 目標行の抽出: order[nnnn] の hidden から ID を集め、行内の「項目」と「達成目標」を読む
  const goals = [];
  form.find('input[type="hidden"][name^="order["]').each((_, el) => {
    const nm = $(el).attr('name') || '';
    const m = nm.match(/^order\[(\d+)\]$/);
    if (!m) return;
    const gid = m[1];
    const row = $(el).closest('tr');
    const tds = row.find('td');
    const category = tds.eq(1).text().trim();
    const goalText = tds.eq(2).text().trim();
    goals.push({ id: gid, order: fields[`order[${gid}]`] || '0', category, goalText });
  });
  goals.sort((a, b) => parseInt(a.order || 0) - parseInt(b.order || 0));

  return { url, fields, goals };
}

/**
 * Claudeでモニタリング考察を生成。
 * 入力: 8項目分の目標、個別支援計画、過去のケア記録
 * 出力: JSON { considerations[], longTerm, shortTerm, remark }
 */
async function generateMonitoringContent({ goals, carePlanText, careRecords }) {
  const goalsList = goals.map((g, i) =>
    `${i + 1}. [${g.category}] ${g.goalText}`
  ).join('\n');

  const recordsSnippet = (careRecords || [])
    .slice(0, 20)
    .map((r) => {
      const body = (r.body || '').replace(/\s+/g, ' ').slice(0, 400);
      return `[${r.date}] 活動:${r.activity || ''} 出席:${r.attendance || ''} 記録:${r.recorder || ''}\n${body}`;
    })
    .join('\n---\n')
    .slice(0, 10000);

  const planSnippet = (carePlanText || '').slice(0, 6000);

  const userPrompt = [
    '以下の個別支援計画とケア記録をもとに、モニタリング表の「考察」欄を日本語で生成してください。',
    '',
    '【目標一覧】',
    goalsList,
    '',
    '【個別支援計画書】',
    planSnippet,
    '',
    '【過去のケア記録（抜粋）】',
    recordsSnippet,
    '',
    '出力ルール:',
    '- 各「考察」は45〜90文字程度、ケア記録に現れた具体的な様子を踏まえて記述',
    '- 文体は「〜である」「〜だ」調で簡潔に、敬体(です・ます)は禁止',
    '- マークダウン記法は使用しない',
    '- 出力はJSONオブジェクトのみ、説明文やコードフェンスは一切含めない',
    '',
    '出力JSONスキーマ:',
    '{',
    '  "considerations": ["項目1の考察", ... 項目数分],',
    '  "longTerm": "長期目標に対する考察",',
    '  "shortTerm": "短期目標に対する考察",',
    '  "remark": ""',
    '}',
  ].join('\n');

  const text = await callClaude({
    model: CLAUDE_MAIN_MODEL,
    system: [{ type: 'text', text: 'あなたは放課後等デイサービス/児童発達支援施設のモニタリング作成を支援するAIです。必ずJSONのみを返します。' }],
    messages: [{ role: 'user', content: userPrompt }],
    maxTokens: 3000,
  });

  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error(`AIレスポンスからJSONを抽出できませんでした: ${text.slice(0, 200)}`);
  let json;
  try {
    json = JSON.parse(match[0]);
  } catch (e) {
    throw new Error(`AIレスポンスのJSONパース失敗: ${e.message}`);
  }
  if (!Array.isArray(json.considerations)) json.considerations = [];
  while (json.considerations.length < goals.length) json.considerations.push('');
  return json;
}

/**
 * HUGのモニタリング編集フォームへPOSTして下書き保存する。
 * 既存値を保持したまま、AI生成の考察 + 固定値のみ上書き。
 */
async function postMonitoringDraft(cookies, { fields, goals, content }) {
  // 保存前にCSRFトークンを再検証する (ajax_token.php) — HUGのJSが保存時に行う流れを再現
  const csrfToken = fields['csrf_token_from_client'] || '';
  const modeToken = fields['mode_token'] || 'nomode';
  const hugPageUrl = fields['hug_page_url'] || 'individual_monitoring.php';
  try {
    const tokenUrl = `${HUG_BASE_URL}/ajax/ajax_token.php?token=${encodeURIComponent(csrfToken)}&mode=${encodeURIComponent(modeToken)}&hug_page_url=${encodeURIComponent(hugPageUrl)}`;
    const tokenRes = await hugFetch(tokenUrl, {}, cookies);
    console.log('[monitoring] token check status:', tokenRes.status);
  } catch (e) {
    console.warn('[monitoring] token check failed:', e.message);
  }

  const merged = { ...fields };

  goals.forEach((g, i) => {
    merged[`achievement[${g.id}][${g.id}]`] = '3'; // 一部達成
    merged[`achievement_text[${g.id}][${g.id}]`] = '';
    merged[`evaluation[${g.id}][${g.id}]`] = '1'; // 継続
    merged[`evaluation_text[${g.id}][${g.id}]`] = '';
    merged[`consideration[${g.id}][${g.id}]`] = content.considerations[i] || '';
  });

  merged.consideration_monita = content.longTerm || '';
  merged.consideration_monita2 = content.shortTerm || '';
  merged.hope_of_the_person = '';
  merged.demands_of_your_family = '';
  merged.needs_of_stakeholders = '';
  merged.monitoring_remark = content.remark || '';
  merged.created_name = '10'; // フィリップス ヒロコ (value=10)
  merged.moni_draft_flg = '1'; // 下書き

  const FormData = require('form-data');
  const formData = new FormData();
  for (const [k, v] of Object.entries(merged)) {
    formData.append(k, v == null ? '' : String(v));
  }

  const res = await fetch(`${HUG_BASE_URL}/individual_monitoring.php`, {
    method: 'POST',
    headers: { ...formData.getHeaders(), 'Cookie': cookies },
    body: formData,
    redirect: 'manual',
  });
  const text = await res.text();
  console.log('[monitoring] POST status:', res.status, 'len:', text.length);
  const ok = res.status === 302 || res.status === 200;
  if (!ok) {
    console.error('[monitoring] POST failed preview:', text.substring(0, 500));
  }
  return { ok, status: res.status };
}

exports.saveMonitoringDraft = onCall(
  {
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 300,
    secrets: [hugUsername, hugPassword, anthropicApiKey],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    const studentId = request.data?.studentId;
    if (!studentId) throw new HttpsError('invalid-argument', 'studentId が必要です');

    try {
      const profileDoc = await db.collection('ai_student_profiles').doc(studentId).get();
      if (!profileDoc.exists) throw new HttpsError('not-found', 'ai_student_profiles が見つかりません');
      const profile = profileDoc.data() || {};
      const hugCId = profile.hugCId;
      const monitoring = profile.hugDocs?.monitoring || {};
      const monitoringId = monitoring.hugId;
      if (!hugCId) throw new HttpsError('failed-precondition', 'hugCId 未マッピング');
      if (!monitoringId) throw new HttpsError('failed-precondition', 'モニタリングの hugId が未取得（HUG側で一度モニタリング枠を作成してください）');

      const carePlanText = profile.hugDocs?.carePlanMain?.rawText || profile.hugDocs?.carePlanDraft?.rawText || '';
      const careRecords = Array.isArray(profile.hugCareRecords) ? profile.hugCareRecords : [];

      const fId = request.data?.fId || '1';

      const cookies = await loginToHug();
      const parsed = await fetchMonitoringFormFields(cookies, monitoringId, String(hugCId), String(fId));
      if (!parsed.goals.length) {
        throw new HttpsError('failed-precondition', 'モニタリングの目標行が取得できません。個別支援計画書の目標設定を確認してください');
      }

      console.log(`[monitoring] goals=${parsed.goals.length} plan=${carePlanText.length} records=${careRecords.length}`);

      const content = await generateMonitoringContent({
        goals: parsed.goals,
        carePlanText,
        careRecords,
      });

      const result = await postMonitoringDraft(cookies, {
        fields: parsed.fields,
        goals: parsed.goals,
        content,
      });

      if (!result.ok) throw new HttpsError('internal', `HUG保存失敗 status=${result.status}`);

      return {
        success: true,
        monitoringId,
        studentName: profile.studentName || '',
        goalCount: parsed.goals.length,
        editUrl: parsed.url,
        content,
      };
    } catch (e) {
      console.error('saveMonitoringDraft error:', e);
      if (e instanceof HttpsError) throw e;
      throw new HttpsError('internal', `モニタリング下書き作成エラー: ${e.message}`);
    }
  }
);
