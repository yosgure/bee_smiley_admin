// AI チャット (個別支援計画相談): Claude を呼んで Firestore のセッションへ書き込む。
// 長文セッションは Haiku で要約しトークン消費を抑制。endAiSession は要約＋AIプロファイル更新を一括で行う。

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  db,
  FieldValue,
  anthropicApiKey,
  CLAUDE_MAIN_MODEL,
  CLAUDE_SUMMARY_MODEL,
  callClaude,
  callClaudeStream,
} = require('../utils/setup');

/**
 * システムプロンプトを構築
 */
function buildSystemPrompt(context) {
  const { studentInfo, supportPlan, recentMonitorings, hugAssessment, isFreeChat } = context || {};

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

    const MESSAGE_THRESHOLD = 20;
    const RECENT_MESSAGE_COUNT = 10;
    const RECENT_SUMMARY_COUNT = 10;

    try {
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

      await messagesRef.add({
        role: 'user',
        content: message,
        createdAt: FieldValue.serverTimestamp(),
        status: 'sent',
      });

      const sessionDoc = await sessionRef.get();
      const sessionData = sessionDoc.data() || {};
      let existingSummary = sessionData.summary || null;

      const allMessagesSnap = await messagesRef
        .orderBy('createdAt', 'asc')
        .get();

      const totalMessageCount = allMessagesSnap.docs.length;
      console.log(`Total messages: ${totalMessageCount}, Threshold: ${MESSAGE_THRESHOLD}`);

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

      let aiResponse;
      if (commandScript) {
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
        await assistantDoc.update({
          content: aiResponse,
          status: 'sent',
          completedAt: FieldValue.serverTimestamp(),
        });
      }

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

      if (sessionData.summary) {
        return { success: true, reason: 'already_summarized' };
      }

      const messagesSnap = await sessionRef
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .get();

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

    const profileRef = db.collection('ai_student_profiles').doc(targetStudentId);
    const profileDoc = await profileRef.get();
    const currentProfile = profileDoc.exists ? (profileDoc.data()?.aiProfile || {}) : {};

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
      parsed = { sessionSummary: aiOutput.substring(0, 500), profile: null };
    }

    const summary = (parsed.sessionSummary || '').toString().trim();
    const newProfile = parsed.profile || null;

    if (summary) {
      await profileRef.collection('session_summaries').doc(sessionId).set({
        sessionId,
        summary,
        endedAt: FieldValue.serverTimestamp(),
      });
      await sessionRef.update({
        endSummary: summary,
        endedAt: FieldValue.serverTimestamp(),
      });
    }

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
