// Firebase Cloud Functions for Push Notifications (v2)

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ==========================================
// チャットメッセージ送信時の通知
// ==========================================
exports.onChatMessageCreated = onDocumentCreated(
  {
    document: "chats/{chatId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const message = event.data.data();
    const chatId = event.params.chatId;

    try {
      const chatDoc = await db.collection("chats").doc(chatId).get();
      if (!chatDoc.exists) return null;

      const chatData = chatDoc.data();
      const senderId = message.senderId;
      const senderName = message.senderName || "不明";

      const participants = chatData.participants || [];
      const recipientIds = participants.filter((id) => id !== senderId);

      if (recipientIds.length === 0) return null;

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
            tokens.push(...staffData.fcmTokens);
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
            tokens.push(...familyData.fcmTokens);
          }
        }
      }

      if (tokens.length === 0) return null;

      const payload = {
        notification: {
          title: `${senderName}`,
          body: message.type === "image" ? "画像を送信しました" : message.text,
        },
        data: {
          type: "chat",
          chatId: chatId,
        },
      };

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        ...payload,
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

      const payload = {
        notification: {
          title: notification.title || "お知らせ",
          body: notification.body || "",
        },
        data: {
          type: "announcement",
          notificationId: event.params.notificationId,
        },
      };

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        ...payload,
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

      const payload = {
        notification: {
          title: "新しいイベント",
          body: eventData.title || "新しいイベントが登録されました",
        },
        data: {
          type: "event",
          eventId: event.params.eventId,
        },
      };

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        ...payload,
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
      const payload = {
        notification: {
          title: "アセスメントが公開されました",
          body: `${childName}さんのアセスメントが公開されました`,
        },
        data: {
          type: "assessment",
          assessmentId: event.params.assessmentId,
        },
      };

      const response = await messaging.sendEachForMulticast({
        tokens: tokens,
        ...payload,
      });

      console.log(`アセスメント通知送信: ${response.successCount}件成功`);
      return null;
    } catch (error) {
      console.error("アセスメント通知エラー:", error);
      return null;
    }
  }
);