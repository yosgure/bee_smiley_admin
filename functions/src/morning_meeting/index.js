// 朝会の音声録音から議事録を自動生成する Cloud Function。
// Firebase Storage 上の音声ファイルパスを受け取り、Gemini API に投げて整形済み議事録を返す。

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getStorage } = require("firebase-admin/storage");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { geminiApiKey } = require("../utils/setup");

const GEMINI_MODEL = "gemini-2.5-flash";

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
- 発言者が特定できる場合は「（〇〇さん）」のように補足する。特定できない場合は省略`;

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
      const [buffer] = await file.download();

      const genAI = new GoogleGenerativeAI(geminiApiKey.value());
      const model = genAI.getGenerativeModel({
        model: GEMINI_MODEL,
        systemInstruction: SYSTEM_INSTRUCTION,
      });

      const contextLines = [];
      if (meetingDate) contextLines.push(`実施日: ${meetingDate}`);
      if (participants.length > 0) {
        contextLines.push(`参加者: ${participants.join("、")}`);
      }
      const userPrompt =
        (contextLines.length > 0 ? contextLines.join("\n") + "\n\n" : "") +
        "以下の音声は本日の朝会の録音です。上記フォーマットとルールに従って議事録として整形してください。";

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
