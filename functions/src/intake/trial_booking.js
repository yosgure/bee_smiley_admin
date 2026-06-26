// 体験予約（HP問い合わせ用・自前予約システム）の Cloud Functions。
//
// 枠モデル:
//   trial_config/default        … 標準時間帯 timeSlots + classroom（スタッフがCRMで編集）
//   trial_slots/{date_HHMM}     … 公開枠。status: 'open' | 'booked'（1枠1組）
//                                  公開日選択時にスタッフがCRMから生成、予約で booked 化
//
// 公開フォーム:
//   getTrialSlots     … 空き枠（今日以降・open）を日付ごとに返す（public）
//   submitTrialBooking … 枠を確保しリードを upsert（plus_families, stage=considering, trialAt=枠日時）
//
// 詳細な体験前アンケートは別途SMS/メールで送付（2段アンケート構想）。

const { onRequest } = require('firebase-functions/v2/https');
const { Timestamp } = require('firebase-admin/firestore');
const { db, FieldValue } = require('../utils/setup');

function s(v) {
  if (v == null) return '';
  return String(v).trim();
}
function normPhone(v) {
  return s(v).replace(/\D/g, '');
}
function normEmail(v) {
  return s(v).toLowerCase();
}
function normGender(v) {
  const x = s(v);
  if (x.includes('男')) return '男子';
  if (x.includes('女')) return '女子';
  return x || 'その他';
}
function jstToday() {
  return new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10);
}
const WEEK = ['日', '月', '火', '水', '木', '金', '土'];
function weekdayOf(dateStr) {
  // dateStr 'YYYY-MM-DD' をJST正午で評価して曜日を出す
  const d = new Date(`${dateStr}T12:00:00+09:00`);
  return WEEK[d.getDay()];
}

// ─────────────── 空き枠取得（公開） ───────────────

exports.getTrialSlots = onRequest(
  { region: 'asia-northeast1', cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    try {
      const today = jstToday();
      // open のみ取得し、日付フィルタ/並べ替えはJS側（複合インデックス不要）
      const snap = await db.collection('trial_slots')
        .where('status', '==', 'open').get();
      const rows = [];
      snap.forEach((doc) => {
        const d = doc.data();
        // 当日・過去は予約不可（翌日以降のみ表示）
        if (s(d.date) > today) {
          rows.push({ id: doc.id, date: s(d.date), start: s(d.start), end: s(d.end) });
        }
      });
      rows.sort((a, b) =>
        a.date === b.date ? a.start.localeCompare(b.start) : a.date.localeCompare(b.date));
      // 日付ごとにまとめる
      const byDate = {};
      for (const r of rows) {
        (byDate[r.date] = byDate[r.date] || []).push({ id: r.id, start: r.start, end: r.end });
      }
      const dates = Object.keys(byDate).sort().map((date) => ({
        date,
        weekday: weekdayOf(date),
        slots: byDate[date],
      }));
      res.status(200).json({ ok: true, dates });
    } catch (err) {
      console.error('[getTrialSlots] error:', err);
      res.status(500).json({ error: err.message || String(err) });
    }
  }
);

// ─────────────── リード upsert（メール/電話一致 or 新規） ───────────────

async function findOrCreateLead(p, trialAt, submittedAt) {
  const email = normEmail(p.email);
  const phone = normPhone(p.phone);

  const childPayload = {
    lastName: s(p.childLastName),
    firstName: s(p.childFirstName),
    gender: normGender(p.childGender),
    birthDate: s(p.childBirthDate), // 'YYYY/MM/DD' 文字列
  };

  // 既存family検索（email→phone）
  let famDoc = null;
  if (email) {
    const q = await db.collection('plus_families')
      .where('email', '==', email).limit(1).get();
    if (!q.empty) famDoc = q.docs[0];
  }
  if (!famDoc && phone) {
    const q = await db.collection('plus_families')
      .where('phone', '==', phone).limit(1).get();
    if (!q.empty) famDoc = q.docs[0];
  }

  if (!famDoc) {
    // 新規family + child[0]
    const newChild = {
      ...childPayload,
      stage: 'considering',
      inquiredAt: submittedAt,
      trialAt,
      source: 'HP予約',
      notifyUnread: true,
      notifyUnreadAt: submittedAt,
    };
    const ref = await db.collection('plus_families').add({
      lastName: s(p.parentLastName),
      firstName: s(p.parentFirstName),
      email,
      phone,
      children: [newChild],
      notifyUnread: true,
      notifyUnreadAt: submittedAt,
      createdAt: submittedAt,
    });
    return { familyId: ref.id, childIndex: 0 };
  }

  // 既存family：同名の子がいれば更新、なければ兄弟追加
  const data = famDoc.data();
  const children = Array.isArray(data.children) ? [...data.children] : [];
  const idx = children.findIndex((c) =>
    s(c.lastName) === childPayload.lastName && s(c.firstName) === childPayload.firstName);
  if (idx >= 0) {
    children[idx] = {
      ...children[idx],
      ...childPayload,
      trialAt,
      notifyUnread: true,
      notifyUnreadAt: submittedAt,
      updatedAt: submittedAt,
    };
  } else {
    children.push({
      ...childPayload,
      stage: 'considering',
      inquiredAt: submittedAt,
      trialAt,
      source: 'HP予約',
      notifyUnread: true,
      notifyUnreadAt: submittedAt,
    });
  }
  await famDoc.ref.update({
    children,
    notifyUnread: true,
    notifyUnreadAt: submittedAt,
  });
  return { familyId: famDoc.id, childIndex: idx >= 0 ? idx : children.length - 1 };
}

// ─────────────── 予約確定（公開） ───────────────

exports.submitTrialBooking = onRequest(
  { region: 'asia-northeast1', cors: true, timeoutSeconds: 60 },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    if (req.body && req.body._hp) {
      res.status(200).json({ ok: true });
      return;
    }
    try {
      const p = req.body || {};
      const slotId = s(p.slotId);
      if (!slotId) { res.status(400).json({ error: '枠が選択されていません' }); return; }
      if (!s(p.parentLastName) || !s(p.childLastName)) {
        res.status(400).json({ error: 'お名前を入力してください' }); return;
      }
      if (!s(p.email) && !s(p.phone)) {
        res.status(400).json({ error: 'メールアドレスか電話番号は必須です' }); return;
      }

      const slotRef = db.collection('trial_slots').doc(slotId);
      const submittedAt = Timestamp.now();

      // 1) 枠を先に確保（二重予約防止）
      const slot = await db.runTransaction(async (tx) => {
        const snap = await tx.get(slotRef);
        if (!snap.exists) throw new Error('NOT_FOUND');
        const d = snap.data();
        if (d.status !== 'open') throw new Error('TAKEN');
        // 当日・過去は予約不可（翌日以降のみ）
        if (s(d.date) <= jstToday()) throw new Error('PAST');
        tx.update(slotRef, { status: 'booked', bookedAt: submittedAt });
        return d;
      }).catch((e) => {
        if (e.message === 'NOT_FOUND' || e.message === 'TAKEN') return null;
        if (e.message === 'PAST') return 'PAST';
        throw e;
      });

      if (slot === 'PAST') {
        res.status(409).json({ error: '当日のご予約はできません。翌日以降の枠をお選びください。' });
        return;
      }
      if (!slot) {
        res.status(409).json({ error: 'この日時は埋まってしまいました。別の枠をお選びください。' });
        return;
      }

      // 2) 体験日時を組み立て、リードを upsert
      const trialAt = Timestamp.fromDate(
        new Date(`${slot.date}T${slot.start}:00+09:00`));
      let lead;
      try {
        lead = await findOrCreateLead(p, trialAt, submittedAt);
      } catch (err) {
        // リード作成失敗時は枠を開放してエラー
        await slotRef.update({ status: 'open', bookedAt: FieldValue.delete() });
        throw err;
      }

      // 3) 枠に予約者情報を紐付け
      await slotRef.update({
        familyId: lead.familyId,
        childIndex: lead.childIndex,
        parentName: `${s(p.parentLastName)} ${s(p.parentFirstName)}`.trim(),
        childName: `${s(p.childLastName)} ${s(p.childFirstName)}`.trim(),
      });

      res.status(200).json({
        ok: true,
        date: slot.date,
        start: slot.start,
        end: slot.end,
      });
    } catch (err) {
      console.error('[submitTrialBooking] error:', err);
      res.status(500).json({ error: err.message || String(err) });
    }
  }
);
