// 共通インフラ: Firebase Admin 初期化、Secrets、Claude API ラッパー、FCM トークンクリーンアップ。
// 全モジュールがこのファイルから db / messaging / auth / secrets を取得する想定。

const { defineSecret } = require("firebase-functions/params");
const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { Anthropic } = require("@anthropic-ai/sdk");

// Secret Manager でAPIキー・初期パスワードを管理
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const initialPassword = defineSecret("INITIAL_PASSWORD");
const hugUsername = defineSecret("HUG_USERNAME");
const hugPassword = defineSecret("HUG_PASSWORD");

// Claudeモデル定義
const CLAUDE_MAIN_MODEL = 'claude-sonnet-4-6';
const CLAUDE_SUMMARY_MODEL = 'claude-haiku-4-5-20251001';

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const messaging = getMessaging();
const auth = getAuth();

const FIXED_DOMAIN = '@bee-smiley.com';

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

  const tokensToRemove = new Map();

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

module.exports = {
  // Firebase
  db,
  messaging,
  auth,
  FieldValue,
  FIXED_DOMAIN,
  // Secrets
  geminiApiKey,
  anthropicApiKey,
  initialPassword,
  hugUsername,
  hugPassword,
  // Claude
  CLAUDE_MAIN_MODEL,
  CLAUDE_SUMMARY_MODEL,
  callClaude,
  callClaudeStream,
  // Helpers
  cleanupInvalidTokens,
};
