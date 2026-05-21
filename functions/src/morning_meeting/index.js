// 朝会の音声録音から議事録を自動生成する Cloud Function。
// Firebase Storage 上の音声ファイルパスを受け取り、Gemini API に投げて整形済み議事録を返す。

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getStorage } = require("firebase-admin/storage");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { db, geminiApiKey } = require("../utils/setup");

const GEMINI_MODEL = "gemini-3.5-flash";

const SYSTEM_INSTRUCTION = `あなたは児童発達支援施設「Bee Smiley」の朝会（毎朝10分程度）議事録作成アシスタントです。スタッフ間の会話音声から、見やすい議事録を整形してください。

【出力フォーマット】
■ 共有事項
・xxx

■ 議題・相談事項
・xxx

■ 決定事項
・xxx

■ TODO・次のアクション
・xxx（担当：xxx／期日：xxx）

【ルール】
- 不明瞭な発言・雑談・フィラー（「えー」「あの」など）は省略する
- 児童名や個人情報は記載してよい（内部資料）
- 議事録は必ず日本語で書く
- マークダウン記法（**太字** や ### 見出し等）は使わない
- 該当する項目が無い見出しは、その見出しごと省略する
- 重複する内容はまとめる
- 発言者が特定できる場合は「（〇〇さん）」のように補足する。特定できない場合は省略
- 名前が出てきた場合、ユーザープロンプトで提示される「児童・スタッフ名簿」に該当者がいれば必ずその正式な漢字表記を使う。読みが同じで漢字が異なる場合も名簿側を優先。名簿に該当者がいない場合のみ、聞き取れた読みをカタカナで記述する`;

async function loadRoster() {
  try {
    const [familiesSnap, staffsSnap] = await Promise.all([
      db.collection("plus_families").get(),
      db.collection("staffs").get(),
    ]);

    const childSet = new Map();
    familiesSnap.forEach((doc) => {
      const d = doc.data() || {};
      const parentLastName = (d.lastName || "").toString().trim();
      const cs = Array.isArray(d.children) ? d.children : [];
      for (const c of cs) {
        const last = (c.lastName || parentLastName || "").toString().trim();
        const first = (c.firstName || "").toString().trim();
        const lastKana = (c.lastNameKana || "").toString().trim();
        const firstKana = (c.firstNameKana || "").toString().trim();
        if (!first && !last) continue;
        const name = `${last} ${first}`.replace(/\s+/g, " ").trim();
        const kana = `${lastKana} ${firstKana}`.replace(/\s+/g, " ").trim();
        const entry = kana ? `${name}（${kana}）` : name;
        childSet.set(name, entry);
      }
    });

    const staffSet = new Map();
    staffsSnap.forEach((doc) => {
      const d = doc.data() || {};
      const name = (d.name || "").toString().trim();
      const kana = (d.kana || "").toString().trim();
      if (!name) return;
      const entry = kana ? `${name}（${kana}）` : name;
      staffSet.set(name, entry);
    });

    return {
      children: Array.from(childSet.values()).sort((a, b) => a.localeCompare(b, "ja")),
      staffs: Array.from(staffSet.values()).sort((a, b) => a.localeCompare(b, "ja")),
    };
  } catch (e) {
    console.warn("[generateMorningMeetingMinutes] loadRoster failed:", e.message);
    return { children: [], staffs: [] };
  }
}

const ALLOWED_MIMES = new Set([
  "audio/webm",
  "audio/mp4",
  "audio/m4a",
  "audio/x-m4a",
  "audio/aac",
  "audio/mpeg",
  "audio/mp3",
  "audio/wav",
  "audio/x-wav",
  "audio/ogg",
  "audio/opus",
]);

const MAX_AUDIO_BYTES = 20 * 1024 * 1024; // 20MB

exports.generateMorningMeetingMinutes = onCall(
  {
    region: "asia-northeast1",
    timeoutSeconds: 540,
    memory: "1GiB",
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    const data = request.data || {};
    const audioPath = typeof data.audioPath === "string" ? data.audioPath.trim() : "";
    const mimeType =
      typeof data.mimeType === "string" && ALLOWED_MIMES.has(data.mimeType)
        ? data.mimeType
        : "audio/webm";
    const participants = Array.isArray(data.participants)
      ? data.participants.filter((s) => typeof s === "string" && s.trim().length > 0)
      : [];
    const meetingDate = typeof data.meetingDate === "string" ? data.meetingDate : "";

    if (!audioPath) {
      throw new HttpsError("invalid-argument", "audioPath が必要です");
    }
    if (!audioPath.startsWith("meeting_minutes/")) {
      throw new HttpsError("invalid-argument", "audioPath が不正です");
    }

    try {
      const bucket = getStorage().bucket();
      const file = bucket.file(audioPath);
      const [exists] = await file.exists();
      if (!exists) {
        throw new HttpsError("not-found", "音声ファイルが見つかりません");
      }
      const [metadata] = await file.getMetadata();
      const size = Number(metadata.size || 0);
      if (size > MAX_AUDIO_BYTES) {
        throw new HttpsError(
          "failed-precondition",
          `音声ファイルが大きすぎます (${Math.round(size / 1024 / 1024)}MB > 20MB)`,
        );
      }
      const [[buffer], roster] = await Promise.all([
        file.download(),
        loadRoster(),
      ]);

      const genAI = new GoogleGenerativeAI(geminiApiKey.value());
      const model = genAI.getGenerativeModel({
        model: GEMINI_MODEL,
        systemInstruction: SYSTEM_INSTRUCTION,
      });

      const promptLines = [];
      if (meetingDate) promptLines.push(`実施日: ${meetingDate}`);
      if (participants.length > 0) {
        promptLines.push(`参加者: ${participants.join("、")}`);
      }
      if (promptLines.length > 0) promptLines.push("");

      if (roster.staffs.length > 0 || roster.children.length > 0) {
        promptLines.push(
          "音声内に名前が登場した場合は、以下の名簿の正式な漢字表記を必ず使ってください。",
          "読みが同じで漢字が異なる場合も名簿側を優先。名簿に該当者がいない場合のみカタカナで記述してください。",
        );
        if (roster.staffs.length > 0) {
          promptLines.push("", "【スタッフ名簿】");
          for (const s of roster.staffs) promptLines.push(`- ${s}`);
        }
        if (roster.children.length > 0) {
          promptLines.push("", "【児童名簿】");
          for (const c of roster.children) promptLines.push(`- ${c}`);
        }
        promptLines.push("");
      }

      promptLines.push(
        "以下の音声は本日の朝会の録音です。上記フォーマットとルールに従って議事録として整形してください。",
      );
      const userPrompt = promptLines.join("\n");

      const result = await model.generateContent([
        { inlineData: { mimeType, data: buffer.toString("base64") } },
        { text: userPrompt },
      ]);

      const minutes = (result.response.text() || "").trim();
      if (!minutes) {
        throw new HttpsError("internal", "議事録が生成されませんでした（空の応答）");
      }

      const usage = result.response.usageMetadata || {};
      console.log(
        `[generateMorningMeetingMinutes] path=${audioPath} size=${size} ` +
          `roster=staffs:${roster.staffs.length}/children:${roster.children.length} ` +
          `prompt=${usage.promptTokenCount || 0} candidate=${usage.candidatesTokenCount || 0} ` +
          `total=${usage.totalTokenCount || 0} resultLen=${minutes.length}`,
      );

      return { minutes, model: GEMINI_MODEL };
    } catch (err) {
      console.error("[generateMorningMeetingMinutes] error:", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", `議事録生成失敗: ${err.message || err}`);
    }
  },
);
