// 通知系 Cloud Functions: チャット・お知らせ・入退室の FCM 配信。
// staff/family の fcmTokens を集約し、無効トークンを cleanupInvalidTokens で削除する。

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { db, messaging, FieldValue, cleanupInvalidTokens } = require('../utils/setup');

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

      let senderName = "不明";
      const names = chatData.names || {};
      if (names[senderId]) {
        senderName = names[senderId];
      }

      const participants = chatData.members || [];
      const recipientIds = participants.filter((id) => id !== senderId);

      if (recipientIds.length === 0) return null;

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
// チャットメッセージにスタンプが付いた時、送信者へ通知
// ==========================================
// 既存レガシー: stamps[emoji] が int の場合もある。配列でない場合は空配列扱い。
exports.onChatStampAdded = onDocumentUpdated(
  {
    document: "chat_rooms/{chatId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;

    try {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const beforeStamps = before.stamps || {};
      const afterStamps = after.stamps || {};

      // 新規に追加された (emoji, uid) ペアを抽出
      const added = [];
      for (const emoji of Object.keys(afterStamps)) {
        const afterList = Array.isArray(afterStamps[emoji]) ? afterStamps[emoji] : [];
        const beforeList = Array.isArray(beforeStamps[emoji]) ? beforeStamps[emoji] : [];
        for (const uid of afterList) {
          if (!beforeList.includes(uid)) {
            added.push({ emoji, uid });
          }
        }
      }
      if (added.length === 0) return null;

      const senderId = after.senderId;
      if (!senderId) return null;

      // 自分で自分のメッセージにスタンプを押した分は通知対象外
      const recipients = added.filter((a) => a.uid !== senderId);
      if (recipients.length === 0) return null;

      const chatDoc = await db.collection("chat_rooms").doc(chatId).get();
      if (!chatDoc.exists) return null;
      const names = chatDoc.data().names || {};

      // 送信者の fcm トークン取得（staffs → families の順に検索）
      let senderDocRef = null;
      let senderTokens = [];
      let senderNotifyChat = true;
      const senderStaffSnap = await db
        .collection("staffs")
        .where("uid", "==", senderId)
        .limit(1)
        .get();
      if (!senderStaffSnap.empty) {
        const d = senderStaffSnap.docs[0];
        senderDocRef = d.ref;
        senderTokens = d.data().fcmTokens || [];
        senderNotifyChat = d.data().notifyChat !== false;
      } else {
        const senderFamilySnap = await db
          .collection("families")
          .where("uid", "==", senderId)
          .limit(1)
          .get();
        if (!senderFamilySnap.empty) {
          const d = senderFamilySnap.docs[0];
          senderDocRef = d.ref;
          senderTokens = d.data().fcmTokens || [];
          senderNotifyChat = d.data().notifyChat !== false;
        }
      }
      if (!senderNotifyChat || senderTokens.length === 0) return null;

      // 同じユーザーが複数 emoji を一度に追加した場合に備えて集約
      const byUid = new Map();
      for (const { emoji, uid } of recipients) {
        if (!byUid.has(uid)) byUid.set(uid, []);
        byUid.get(uid).push(emoji);
      }

      const tokenDocMap = senderTokens.map((t) => ({ token: t, docRef: senderDocRef }));

      for (const [reacterUid, emojis] of byUid.entries()) {
        const reacterName = names[reacterUid] || "誰か";
        const emojiStr = emojis.join("");
        const response = await messaging.sendEachForMulticast({
          tokens: senderTokens,
          notification: {
            title: `${reacterName}さん`,
            body: `あなたのメッセージにスタンプを付けました ${emojiStr}`,
          },
          data: {
            type: "chat_stamp",
            chatId: chatId,
            messageId: messageId,
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
        console.log(`スタンプ通知送信: ${response.successCount}件成功, ${response.failureCount}件失敗`);
        await cleanupInvalidTokens(response, tokenDocMap);
      }

      return null;
    } catch (error) {
      console.error(JSON.stringify({
        function: 'onChatStampAdded',
        chatId,
        messageId,
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

      const familiesSnap = await db.collection("families")
        .where("fcmTokens", "!=", [])
        .get();

      for (const familyDoc of familiesSnap.docs) {
        const familyData = familyDoc.data();

        if (familyData.notifyAnnouncement === false) continue;

        if (target === "specific" && targetClassrooms.length > 0) {
          const children = familyData.children || [];
          const isTarget = children.some((child) => {
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
