// Google フォーム自動取り込み Cloud Function。
// Apps Script の onFormSubmit から HTTPS POST で呼ばれ、plus_families に upsert する。
//
// パイプライン:
//   Google Form
//     └─ onFormSubmit (Apps Script)
//          └─ HTTPS POST → exports.intakeForm
//               └─ plus_families upsert
//                    ├─ メール / 電話一致 → 既存 family.children[i] を更新
//                    └─ 一致なし → 新規 family + child[0] 作成
//
// 認証: Apps Script から `x-intake-secret` ヘッダで shared secret を送る。
// Secret Manager の `INTAKE_FORM_SECRET` と一致しなければ 401。

const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { Timestamp } = require('firebase-admin/firestore');
const { db, FieldValue } = require('../utils/setup');

const intakeFormSecret = defineSecret('INTAKE_FORM_SECRET');

// ===== 正規化ヘルパー =====

function s(v) {
  if (v == null) return '';
  return String(v).trim();
}

function normalizePhone(phone) {
  // 数字以外を除去（ハイフン、スペース、括弧、+81 など）
  return s(phone).replace(/\D/g, '');
}

function normalizeEmail(email) {
  return s(email).toLowerCase();
}

function normalizeGender(g) {
  const v = s(g);
  if (v.includes('男')) return '男子';
  if (v.includes('女')) return '女子';
  return v || 'その他';
}

function normalizePermitStatus(v) {
  // 「有」「あり」「持っている」→ have / 「無」「なし」→ none / 「申請中」→ applying
  const x = s(v);
  if (!x) return null;
  if (/(申請中|手続中|準備)/.test(x)) return 'applying';
  if (/(有|あり|持って|所持|済)/.test(x)) return 'have';
  if (/(無|なし|未|これから)/.test(x)) return 'none';
  return null;
}

function normalizeSource(v) {
  // Apps Script 側で日本語ラベルが入る前提。CRM の source 値と揃えるため簡易マッピング。
  const x = s(v);
  if (!x) return '';
  if (/Instagram|インスタ/i.test(x)) return 'Instagram';
  if (/Google|検索/i.test(x)) return 'Google検索';
  if (/紹介|友人|知人/.test(x)) return '紹介';
  if (/HP|ホームページ|ウェブ|Web/i.test(x)) return 'HP';
  if (/SNS/i.test(x)) return 'SNS';
  if (/チラシ|ポスター/.test(x)) return 'チラシ';
  return x; // そのまま保存
}

function parseTimestamp(v) {
  if (!v) return Timestamp.now();
  // Apps Script から ISO8601 or 'YYYY/MM/DD HH:mm:ss' で来る想定
  const d = new Date(s(v));
  if (isNaN(d.getTime())) return Timestamp.now();
  return Timestamp.fromDate(d);
}

function normalizeBirthDate(v) {
  // plus_families スキーマでは 'YYYY/MM/DD' 文字列で保存
  const x = s(v);
  if (!x) return '';
  const m = x.match(/^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})/);
  if (!m) return x;
  const yyyy = m[1].padStart(4, '0');
  const mm = m[2].padStart(2, '0');
  const dd = m[3].padStart(2, '0');
  return `${yyyy}/${mm}/${dd}`;
}

// ===== 既存リード検索 =====

/**
 * メール OR 電話番号の完全一致で既存 family を検索。
 * 一致したら { familyDoc, childIndex } を返す。
 * 兄弟児童がいる場合、children[] の中で氏名が一番近いものを選ぶ（なければ index 0）。
 */
async function findExistingFamily({ email, phone, childLastName, childFirstName }) {
  const candidates = [];

  if (email) {
    const snap = await db
      .collection('plus_families')
      .where('email', '==', email)
      .limit(5)
      .get();
    snap.forEach((doc) => candidates.push(doc));
  }

  if (phone) {
    const snap = await db
      .collection('plus_families')
      .where('phone', '==', phone)
      .limit(5)
      .get();
    snap.forEach((doc) => {
      if (!candidates.some((c) => c.id === doc.id)) {
        candidates.push(doc);
      }
    });
  }

  if (candidates.length === 0) return null;

  // 兄弟児童一致を試す
  for (const famDoc of candidates) {
    const children = (famDoc.data().children || []);
    const matchIdx = children.findIndex(
      (c) =>
        s(c.lastName) === s(childLastName) &&
        s(c.firstName) === s(childFirstName)
    );
    if (matchIdx >= 0) {
      return { familyDoc: famDoc, childIndex: matchIdx, isNewChild: false };
    }
  }

  // 氏名一致なし → 同じ家族に新しい兄弟として追加
  const famDoc = candidates[0];
  return {
    familyDoc: famDoc,
    childIndex: (famDoc.data().children || []).length,
    isNewChild: true,
  };
}

// ===== upsert 本体 =====

/**
 * Apps Script からの payload を plus_families の構造に変換して upsert。
 *
 * @param {object} p - 正規化済み payload
 * @returns {object} { familyId, childIndex, action: 'created'|'updated'|'sibling-added' }
 */
async function upsertFromForm(p) {
  const submittedAt = parseTimestamp(p.submittedAt);
  const email = normalizeEmail(p.email);
  const phone = normalizePhone(p.phone);

  if (!email && !phone) {
    throw new Error('email も phone も無いペイロードは取り込めません');
  }

  // 児童側に積むフィールド（既存スキーマ + 新規）
  const childPayload = {
    lastName: s(p.childLastName),
    firstName: s(p.childFirstName),
    lastNameKana: s(p.childLastNameKana),
    firstNameKana: s(p.childFirstNameKana),
    birthDate: normalizeBirthDate(p.childBirthDate),
    gender: normalizeGender(p.childGender),
    kindergarten: s(p.kindergarten),
    grade: s(p.grade),
    mainConcern: s(p.mainConcern),
    likes: s(p.likes),
    dislikes: s(p.dislikes),
    medicalHistory: s(p.medicalHistory),
    diagnosis: s(p.diagnosis),
    trialAttendee: s(p.trialAttendee),
    permitStatus: normalizePermitStatus(p.permitStatus) || 'none',
    source: normalizeSource(p.source),
    memo: s(p.memo),
    intakeFormRaw: p.raw || null, // 生回答を念のため保存
    inquiredAt: submittedAt,
    lastActivityAt: submittedAt,
    // 児童ごとの未読フラグ（リードカードの NEW バッジ用）
    notifyUnread: true,
    notifyUnreadAt: submittedAt,
  };

  // 家族レベルに積むフィールド
  // family.notifyUnread は children のいずれかが未読ならtrue（サイドメニュー赤ポチ用ロールアップ）
  const familyPayload = {
    lastName: s(p.parentLastName),
    firstName: s(p.parentFirstName),
    lastNameKana: s(p.parentLastNameKana),
    firstNameKana: s(p.parentFirstNameKana),
    phone,
    email,
    address: s(p.address),
    postalCode: s(p.postalCode),
    notifyUnread: true,
    notifyUnreadAt: submittedAt,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: 'form_intake',
  };

  const existing = await findExistingFamily({
    email,
    phone,
    childLastName: childPayload.lastName,
    childFirstName: childPayload.firstName,
  });

  // ----- 新規 family -----
  if (!existing) {
    const newChild = {
      ...childPayload,
      stage: 'considering',
      status: '検討中',
      createdAt: submittedAt,
      updatedAt: submittedAt,
      createdBy: 'form_intake',
    };
    const ref = await db.collection('plus_families').add({
      ...familyPayload,
      children: [newChild],
      createdAt: FieldValue.serverTimestamp(),
      createdBy: 'form_intake',
    });
    return { familyId: ref.id, childIndex: 0, action: 'created' };
  }

  // ----- 既存 family + 既存 child（更新） -----
  if (!existing.isNewChild) {
    const famRef = existing.familyDoc.ref;
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(famRef);
      const data = snap.data() || {};
      const children = Array.isArray(data.children) ? [...data.children] : [];
      const idx = existing.childIndex;
      const oldChild = children[idx] || {};

      // 既存値を尊重（空文字で上書きしない）
      const merged = { ...oldChild };
      Object.entries(childPayload).forEach(([k, v]) => {
        if (v == null || v === '') return;
        // 既に値が入っていて、フォームから空でない値が来た場合のみ上書き
        // ただし stage / inquiredAt は既存リードを優先（リード進行中の戻りを防ぐ）
        if (k === 'inquiredAt') return;
        merged[k] = v;
      });
      merged.updatedAt = submittedAt;

      children[idx] = merged;
      const famUpdate = { children };
      // 家族レベルも空でない値だけ上書き
      Object.entries(familyPayload).forEach(([k, v]) => {
        if (v == null || v === '') return;
        const existingVal = data[k];
        if (typeof existingVal === 'string' && existingVal && typeof v === 'string') {
          // 既存値が入ってるなら上書きしない（誤クリア防止）
          return;
        }
        famUpdate[k] = v;
      });
      // notifyUnread は常に true（既読化はクライアント側で）
      famUpdate.notifyUnread = true;
      famUpdate.notifyUnreadAt = submittedAt;

      tx.update(famRef, famUpdate);
      return { familyId: famRef.id, childIndex: idx, action: 'updated' };
    });
  }

  // ----- 既存 family + 新規 child（兄弟追加） -----
  const famRef = existing.familyDoc.ref;
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(famRef);
    const data = snap.data() || {};
    const children = Array.isArray(data.children) ? [...data.children] : [];
    const newChild = {
      ...childPayload,
      stage: 'considering',
      status: '検討中',
      createdAt: submittedAt,
      updatedAt: submittedAt,
      createdBy: 'form_intake',
    };
    children.push(newChild);
    tx.update(famRef, {
      children,
      notifyUnread: true,
      notifyUnreadAt: submittedAt,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: 'form_intake',
    });
    return { familyId: famRef.id, childIndex: children.length - 1, action: 'sibling-added' };
  });
}

// ===== HTTPS エンドポイント =====

exports.intakeForm = onRequest(
  {
    region: 'asia-northeast1',
    secrets: [intakeFormSecret],
    cors: false,
    timeoutSeconds: 60,
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    // 認証
    const provided = req.headers['x-intake-secret'];
    const expected = intakeFormSecret.value();
    if (!provided || provided !== expected) {
      console.warn('[intakeForm] auth failed');
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    try {
      const payload = req.body || {};
      const result = await upsertFromForm(payload);
      console.log('[intakeForm] success:', result);
      res.status(200).json({ ok: true, ...result });
    } catch (err) {
      console.error('[intakeForm] error:', err);
      res.status(500).json({ error: err.message || String(err) });
    }
  }
);
