// 入会前アンケート（受給者証写真アップロード対応）の Cloud Functions。
//
// パイプライン:
//   CRM サイドパネル
//     └─ createIntakeToken (onCall, 認証スタッフ)  … リードごとの個別トークンを発行
//          └─ SMS で https://bee-smiley-admin.web.app/#/intake-final?t={token} を送付
//               └─ 保護者が入会前アンケート画面を開く
//                    ├─ getIntakeContext (onRequest, public)  … 本人確認用に氏名等を返す（最小限）
//                    └─ submitFinalIntake (onRequest, public)  … 回答＋受給者証写真を書き戻す
//
// セキュリティ:
//   - 個別トークン（推測不可能なランダム値）が鍵。intake_tokens/{token} に紐付けを保存。
//   - 受給者証画像は未認証 Storage 書き込みを許さず、関数が Admin SDK で保存する。
//   - 有効期限つき（既定 45 日）。

const crypto = require('crypto');
const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { Timestamp } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { db, FieldValue } = require('../utils/setup');

const TOKEN_TTL_DAYS = 45;
const MAX_IMAGES = 4;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024; // 1枚あたり 8MB

function s(v) {
  if (v == null) return '';
  return String(v).trim();
}

function newToken() {
  return crypto.randomBytes(24).toString('hex'); // 48文字
}

// ─────────────── トークン発行（スタッフ用） ───────────────

exports.createIntakeToken = onCall(
  { region: 'asia-northeast1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }
    const { familyId, childIndex, type } = request.data || {};
    if (typeof familyId !== 'string' || !familyId) {
      throw new HttpsError('invalid-argument', 'familyId が必要です');
    }
    const ci = Number(childIndex);
    if (!Number.isInteger(ci) || ci < 0) {
      throw new HttpsError('invalid-argument', 'childIndex が不正です');
    }
    const kind = type === 'trial' ? 'trial' : 'final';

    const famSnap = await db.collection('plus_families').doc(familyId).get();
    if (!famSnap.exists) {
      throw new HttpsError('not-found', `家族が見つかりません: ${familyId}`);
    }

    // 同じリード（家族・児童・種別）に未使用かつ未期限のリンクが既にあれば使い回す。
    // → 押すたびにURLが変わる／未使用リンクが量産されるのを防ぎ、安全側に倒す。
    // 等価フィルタのみなので複合インデックス不要（単一フィールドインデックスで処理される）。
    const existing = await db.collection('intake_tokens')
      .where('familyId', '==', familyId)
      .where('childIndex', '==', ci)
      .where('type', '==', kind)
      .where('usedAt', '==', null)
      .get();
    const nowMs = Date.now();
    let reusable = null;
    for (const d of existing.docs) {
      const dd = d.data() || {};
      if (dd.expiresAt && dd.expiresAt.toMillis() > nowMs) {
        // 期限が最も先のものを選ぶ（より長く使えるリンクを返す）
        if (!reusable || dd.expiresAt.toMillis() > reusable.expiresAt.toMillis()) {
          reusable = { token: d.id, expiresAt: dd.expiresAt };
        }
      }
    }
    if (reusable) {
      const url = `https://bee-smiley-admin.web.app/#/intake-final?t=${reusable.token}`;
      return {
        token: reusable.token,
        url,
        expiresAt: reusable.expiresAt.toMillis(),
        reused: true,
      };
    }

    const token = newToken();
    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000
    );
    await db.collection('intake_tokens').doc(token).set({
      familyId,
      childIndex: ci,
      type: kind,
      createdAt: now,
      createdBy: request.auth.uid,
      expiresAt,
      usedAt: null,
    });

    const url = `https://bee-smiley-admin.web.app/#/intake-final?t=${token}`;
    return { token, url, expiresAt: expiresAt.toMillis() };
  }
);

// ─────────────── トークン検証ヘルパー ───────────────

async function resolveToken(token) {
  if (!token || typeof token !== 'string') return null;
  const snap = await db.collection('intake_tokens').doc(token).get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (data.expiresAt && data.expiresAt.toMillis() < Date.now()) {
    return { expired: true };
  }
  return { ref: snap.ref, ...data };
}

// ─────────────── コンテキスト取得（本人確認・事前入力用） ───────────────

exports.getIntakeContext = onRequest(
  { region: 'asia-northeast1', cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    try {
      const token = (req.method === 'POST')
        ? (req.body && req.body.token)
        : req.query.token;
      const t = await resolveToken(token);
      if (!t) {
        res.status(404).json({ error: 'リンクが無効です' });
        return;
      }
      if (t.expired) {
        res.status(410).json({ error: 'リンクの有効期限が切れています' });
        return;
      }
      const famSnap = await db.collection('plus_families').doc(t.familyId).get();
      if (!famSnap.exists) {
        res.status(404).json({ error: '対象が見つかりません' });
        return;
      }
      const fam = famSnap.data();
      const child = (fam.children || [])[t.childIndex] || {};
      const cert = child.recipientCert || {};
      const ec0 = (Array.isArray(fam.emergencyContacts) ? fam.emergencyContacts[0] : null) || {};
      // 本人確認＋事前入力用に最小限だけ返す
      res.status(200).json({
        ok: true,
        parentName: `${s(fam.parentLastName)} ${s(fam.parentFirstName)}`.trim(),
        childName: `${s(child.lastName)} ${s(child.firstName)}`.trim(),
        prefill: {
          payerName: s(cert.payerName),
          payerNameKana: s(cert.payerNameKana),
          postalCode: s(fam.postalCode),
          prefecture: s(fam.prefecture),
          city: s(fam.city),
          addressDetail: s(fam.addressDetail),
          parentRelation: s(fam.parentRelation),
          emergencyName: s(ec0.name),
          emergencyPhone: s(ec0.phone),
          emergencyRelation: s(ec0.relation),
          kindergarten: s(child.kindergarten),
          kindergartenPhone: s(child.kindergartenPhone),
          homeroomTeacher: s(child.homeroomTeacher),
          grade: s(child.grade),
          hospitalName: s(child.hospitalName),
          hospitalPhone: s(child.hospitalPhone),
          doctorName: s(child.doctorName),
          familyComposition: s(child.familyComposition),
          troubles: s(child.troubles),
          permitStatus: s(child.permitStatus),
          certificateNumber: s(cert.certificateNumber),
        },
      });
    } catch (err) {
      console.error('[getIntakeContext] error:', err);
      res.status(500).json({ error: err.message || String(err) });
    }
  }
);

// ─────────────── 画像アップロード（Admin SDK） ───────────────

async function uploadCertImages(familyId, childIndex, images) {
  if (!Array.isArray(images) || images.length === 0) return [];
  if (images.length > MAX_IMAGES) {
    throw new Error(`画像は最大 ${MAX_IMAGES} 枚までです`);
  }
  const bucket = getStorage().bucket();
  const paths = [];
  for (let i = 0; i < images.length; i++) {
    const img = images[i] || {};
    const b64 = s(img.dataBase64);
    if (!b64) continue;
    const buf = Buffer.from(b64, 'base64');
    if (buf.length > MAX_IMAGE_BYTES) {
      throw new Error('画像サイズが大きすぎます（1枚 8MB まで）');
    }
    const contentType = s(img.contentType) || 'image/jpeg';
    const ext = contentType.includes('png') ? 'png' : 'jpg';
    const path = `intake_uploads/${familyId}/${childIndex}/cert_${Date.now()}_${i}.${ext}`;
    const file = bucket.file(path);
    await file.save(buf, { contentType, resumable: false });
    paths.push(path);
  }
  return paths;
}

// ─────────────── 回答の書き戻し ───────────────

exports.submitFinalIntake = onRequest(
  { region: 'asia-northeast1', cors: true, timeoutSeconds: 120, memory: '512MiB' },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    // ハニーポット
    if (req.body && req.body._hp) {
      res.status(200).json({ ok: true });
      return;
    }
    try {
      const p = req.body || {};
      const t = await resolveToken(p.token);
      if (!t) { res.status(404).json({ error: 'リンクが無効です' }); return; }
      if (t.expired) { res.status(410).json({ error: 'リンクの有効期限が切れています' }); return; }

      const { familyId, childIndex } = t;

      // 受給者証画像を先に Storage 保存
      const imagePaths = await uploadCertImages(familyId, childIndex, p.certImages);

      const famRef = db.collection('plus_families').doc(familyId);
      const now = Timestamp.now();

      await db.runTransaction(async (tx) => {
        const snap = await tx.get(famRef);
        if (!snap.exists) throw new Error('対象が見つかりません');
        const data = snap.data();
        const children = Array.isArray(data.children) ? [...data.children] : [];
        if (childIndex >= children.length) throw new Error('児童インデックスが範囲外です');
        const child = { ...(children[childIndex] || {}) };
        const cert = { ...(child.recipientCert || {}) };

        // 受給者証（実績記録票に載る保護者名は有無に関わらず必須運用）
        if (p.payerName !== undefined) cert.payerName = s(p.payerName);
        if (p.payerNameKana !== undefined) cert.payerNameKana = s(p.payerNameKana);
        if (p.certificateNumber !== undefined && s(p.certificateNumber)) {
          cert.certificateNumber = s(p.certificateNumber);
        }
        if (imagePaths.length) {
          cert.images = [...(Array.isArray(cert.images) ? cert.images : []), ...imagePaths];
        }
        child.recipientCert = cert;

        // 児童・保護者の各項目
        if (p.permitStatus !== undefined && s(p.permitStatus)) child.permitStatus = s(p.permitStatus);
        if (p.kindergarten !== undefined) child.kindergarten = s(p.kindergarten);
        if (p.kindergartenPhone !== undefined) child.kindergartenPhone = s(p.kindergartenPhone);
        if (p.homeroomTeacher !== undefined) child.homeroomTeacher = s(p.homeroomTeacher);
        if (p.grade !== undefined) child.grade = s(p.grade);
        if (p.hospitalName !== undefined) child.hospitalName = s(p.hospitalName);
        if (p.hospitalPhone !== undefined) child.hospitalPhone = s(p.hospitalPhone);
        if (p.doctorName !== undefined) child.doctorName = s(p.doctorName);
        if (p.familyComposition !== undefined) child.familyComposition = s(p.familyComposition);
        if (p.allergy !== undefined && s(p.allergy)) child.allergy = s(p.allergy);
        if (p.severeSymptoms !== undefined && s(p.severeSymptoms)) child.severeSymptoms = s(p.severeSymptoms);
        if (p.sensitivities !== undefined) child.sensitivities = s(p.sensitivities);
        if (p.precautions !== undefined) child.precautions = s(p.precautions);
        if (p.childWishes !== undefined) child.childWishes = s(p.childWishes);
        if (p.familyWishes !== undefined) child.familyWishes = s(p.familyWishes);
        if (p.troubles !== undefined) child.troubles = s(p.troubles);
        // その他お伝えしたいこと → 備考（CRMは child.memo を読む）。空は上書きしない。
        if (p.memo !== undefined && s(p.memo)) child.memo = s(p.memo);
        child.finalIntakeReceivedAt = now;
        child.updatedAt = now;
        children[childIndex] = child;

        const famUpdate = {
          children,
          notifyUnread: true,
          notifyUnreadAt: now,
        };
        // 住所・郵便番号・続柄は family レベル
        if (p.postalCode !== undefined && s(p.postalCode)) famUpdate.postalCode = s(p.postalCode);
        if (p.prefecture !== undefined && s(p.prefecture)) famUpdate.prefecture = s(p.prefecture);
        if (p.city !== undefined && s(p.city)) famUpdate.city = s(p.city);
        if (p.addressDetail !== undefined && s(p.addressDetail)) famUpdate.addressDetail = s(p.addressDetail);
        if (p.parentRelation !== undefined && s(p.parentRelation)) famUpdate.parentRelation = s(p.parentRelation);
        // 緊急連絡先（任意・1件：名前＋電話＋続柄）
        if ((p.emergencyName !== undefined && s(p.emergencyName)) ||
            (p.emergencyPhone !== undefined && s(p.emergencyPhone))) {
          const list = Array.isArray(data.emergencyContacts) ? [...data.emergencyContacts] : [];
          list[0] = {
            ...(list[0] || {}),
            name: s(p.emergencyName),
            phone: s(p.emergencyPhone),
            relation: s(p.emergencyRelation),
          };
          famUpdate.emergencyContacts = list;
        }
        tx.update(famRef, famUpdate);
      });

      await t.ref.update({ usedAt: now });
      res.status(200).json({ ok: true });
    } catch (err) {
      console.error('[submitFinalIntake] error:', err);
      res.status(500).json({ error: err.message || String(err) });
    }
  }
);
