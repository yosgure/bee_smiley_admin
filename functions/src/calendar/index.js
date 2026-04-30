// カレンダー/イベント/プラスレッスン系の Firestore トリガー通知。
// 担当スタッフ・保護者に対して、作成/変更/削除のタイミングで FCM を送る。

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { db, messaging, cleanupInvalidTokens } = require('../utils/setup');

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
// カレンダー予定作成/更新/削除（担当講師向け）
// ==========================================

async function collectStaffTokens(staffIds, notifyKey = 'notifyCalendar') {
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
      if (staffData[notifyKey] !== false && staffData.fcmTokens) {
        const docRef = staffSnap.docs[0].ref;
        staffData.fcmTokens.forEach((t) => {
          tokens.push(t);
          tokenDocMap.push({ token: t, docRef });
        });
      }
    }
  }
  return { tokens, tokenDocMap };
}

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

      const { tokens, tokenDocMap } = await collectStaffTokens(staffIds);
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
        apns: { payload: { aps: { badge: 1, sound: "default" } } },
        android: { notification: { sound: "default", channelId: "high_importance_channel" } },
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

      const { tokens, tokenDocMap } = await collectStaffTokens(staffIds);
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
        apns: { payload: { aps: { badge: 1, sound: "default" } } },
        android: { notification: { sound: "default", channelId: "high_importance_channel" } },
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

      const { tokens, tokenDocMap } = await collectStaffTokens(staffIds);
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
        apns: { payload: { aps: { badge: 1, sound: "default" } } },
        android: { notification: { sound: "default", channelId: "high_importance_channel" } },
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
// プラスレッスン作成/更新/削除（担当講師向け）
// ==========================================

async function collectPlusLessonTokens(teacherNames) {
  const tokens = [];
  const tokenDocMap = [];
  const isAllStaff = teacherNames.includes("全員");

  if (isAllStaff) {
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
  return { tokens, tokenDocMap };
}

const PLUS_TIME_SLOTS = ["9:30〜", "11:00〜", "14:00〜", "15:30〜"];

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

      const { tokens, tokenDocMap } = await collectPlusLessonTokens(teacherNames);
      if (tokens.length === 0) return null;

      const date = lessonData.date?.toDate();
      const dateStr = date ? `${date.getMonth() + 1}/${date.getDate()}` : "";
      const timeStr = PLUS_TIME_SLOTS[lessonData.slotIndex] || "";

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
        apns: { payload: { aps: { badge: 1, sound: "default" } } },
        android: { notification: { sound: "default", channelId: "high_importance_channel" } },
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

      const { tokens, tokenDocMap } = await collectPlusLessonTokens(teacherNames);
      if (tokens.length === 0) return null;

      const date = after.date?.toDate();
      const dateStr = date ? `${date.getMonth() + 1}/${date.getDate()}` : "";
      const timeStr = PLUS_TIME_SLOTS[after.slotIndex] || "";

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
        apns: { payload: { aps: { badge: 1, sound: "default" } } },
        android: { notification: { sound: "default", channelId: "high_importance_channel" } },
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

      const { tokens, tokenDocMap } = await collectPlusLessonTokens(teacherNames);
      if (tokens.length === 0) return null;

      const date = lessonData.date?.toDate();
      const dateStr = date ? `${date.getMonth() + 1}/${date.getDate()}` : "";
      const timeStr = PLUS_TIME_SLOTS[lessonData.slotIndex] || "";

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
        apns: { payload: { aps: { badge: 1, sound: "default" } } },
        android: { notification: { sound: "default", channelId: "high_importance_channel" } },
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
