// HUG モニタリング下書き作成。INSERT モードのみ・多重ガード付き。
// getMonitoringFormInfo (事前確認) と createMonitoringDraft (本書き込み) を提供する。

const fetch = require("node-fetch");
const cheerio = require("cheerio");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { db, FieldValue, hugUsername, hugPassword } = require('../utils/setup');
const { HUG_BASE_URL, hugFetch, loginToHug } = require('../utils/hug-client');

async function scrapeMonitoringList(cookies, cId) {
  const url = `${HUG_BASE_URL}/individual_monitoring.php?c_id=${cId}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const rows = [];
  $('table tbody tr, table tr').each((_, tr) => {
    const tds = $(tr).find('td');
    if (tds.length < 6) return;
    const texts = tds.map((_, td) => $(td).text().trim().replace(/\s+/g, ' ')).get();
    if (!texts.some((t) => t.includes('児童発達支援') || t.includes('放課後等デイサービス'))) return;

    let kaisuu = 0;
    for (const t of texts) {
      const m = t.match(/^(\d+)$/);
      if (m) { kaisuu = parseInt(m[1], 10); break; }
    }
    if (kaisuu === 0) return;

    const allText = texts.join(' | ');
    const detailLink = $(tr).find('button[onclick*="mode=detail"]').attr('onclick') || '';
    const detailMatch = detailLink.match(/id=(\d+)/);
    const existingId = detailMatch ? detailMatch[1] : null;

    let status = 'unknown';
    if (allText.includes('削除済')) status = 'deleted';
    else if (allText.includes('下書き')) status = 'draft';
    else if (allText.includes('公開')) status = 'published';
    else if (allText.includes('非公開')) status = 'private';
    else if (allText.includes('未作成')) status = 'not_created';

    rows.push({ kaisuu, existingId, status, rawText: allText });
  });

  rows.sort((a, b) => b.kaisuu - a.kaisuu);
  return rows;
}

async function fetchMonitoringInsertForm(cookies, cId, fId) {
  const url = `${HUG_BASE_URL}/individual_monitoring.php?mode=edit&c_id=${cId}&f_id=${fId}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);
  const form = $('form').first();
  if (!form.length) throw new Error('insert form not found');

  const fields = {};
  form.find('input[type="hidden"], input[type="text"], input[type="number"]').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    fields[name] = $(el).attr('value') || '';
  });
  form.find('input[type="radio"]').each((_, el) => {
    const name = $(el).attr('name');
    if (!name || $(el).attr('checked') === undefined) return;
    fields[name] = $(el).attr('value') || '';
  });
  form.find('input[type="checkbox"]').each((_, el) => {
    const name = $(el).attr('name');
    if (!name || $(el).attr('checked') === undefined) return;
    fields[name] = $(el).attr('value') || '1';
  });
  form.find('select').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    const selected = $(el).find('option[selected]').attr('value');
    fields[name] = selected !== undefined
      ? selected
      : ($(el).find('option').first().attr('value') || '');
  });
  form.find('textarea').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    fields[name] = $(el).text() || '';
  });

  const goals = [];
  form.find('input[type="hidden"][name^="order["]').each((_, el) => {
    const nm = $(el).attr('name') || '';
    const m = nm.match(/^order\[(\d+)\]$/);
    if (!m) return;
    const gid = m[1];
    const row = $(el).closest('tr');
    const tds = row.find('td');
    const category = tds.eq(1).text().trim();
    const goalText = tds.eq(2).text().trim();
    goals.push({
      id: gid,
      order: fields[`order[${gid}]`] || '0',
      category,
      goalText,
    });
  });
  goals.sort((a, b) => parseInt(a.order || 0) - parseInt(b.order || 0));

  return { url, fields, goals, html };
}

exports.getMonitoringFormInfo = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 90,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    const { studentId } = request.data || {};
    if (!studentId) throw new HttpsError('invalid-argument', 'studentId が必要です');

    const profileDoc = await db.collection('ai_student_profiles').doc(studentId).get();
    if (!profileDoc.exists) throw new HttpsError('not-found', 'プロファイルが見つかりません');
    const profile = profileDoc.data() || {};
    const hugCId = profile.hugCId;
    if (!hugCId) throw new HttpsError('failed-precondition', 'hugCId 未マッピング');

    const cookies = await loginToHug();
    const form = await fetchMonitoringInsertForm(cookies, String(hugCId), '1');
    const targetKaisuu = parseInt(form.fields['origin_kaisuu'] || '0', 10);
    const list = await scrapeMonitoringList(cookies, String(hugCId));
    const conflict = list.find((r) => r.kaisuu === targetKaisuu && r.status !== 'deleted') || null;

    return {
      targetKaisuu,
      idField: form.fields['id'] || '',
      goals: form.goals.map((g) => ({
        id: g.id,
        category: g.category,
        goalText: g.goalText,
        title: `[${g.category}] ${g.goalText}`,
      })),
      conflict: conflict ? { kaisuu: conflict.kaisuu, status: conflict.status } : null,
    };
  }
);

exports.createMonitoringDraft = onCall(
  {
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 180,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');

    const { studentId, considerations, longTerm, shortTerm, remark } = request.data || {};
    if (!studentId) throw new HttpsError('invalid-argument', 'studentId が必要です');
    if (!Array.isArray(considerations) || considerations.length === 0) {
      throw new HttpsError('invalid-argument', 'considerations (配列) が必要です');
    }

    const profileDoc = await db.collection('ai_student_profiles').doc(studentId).get();
    if (!profileDoc.exists) throw new HttpsError('not-found', 'プロファイルが見つかりません');
    const profile = profileDoc.data() || {};
    const hugCId = profile.hugCId;
    if (!hugCId) throw new HttpsError('failed-precondition', 'hugCId が未マッピングです');
    const studentName = profile.studentName || '';
    const fId = '1';

    const cookies = await loginToHug();

    const form = await fetchMonitoringInsertForm(cookies, String(hugCId), fId);
    const targetKaisuu = parseInt(form.fields['origin_kaisuu'] || '0', 10);
    if (!targetKaisuu) {
      throw new HttpsError('failed-precondition', 'HUGから作成回数を取得できませんでした');
    }

    const list = await scrapeMonitoringList(cookies, String(hugCId));
    const conflict = list.find((r) => r.kaisuu === targetKaisuu && r.status !== 'deleted');
    if (conflict) {
      throw new HttpsError(
        'failed-precondition',
        `作成回数${targetKaisuu}のモニタリングは既に存在します（状態: ${conflict.status}）。上書きを避けるため書き込みを中止しました。`
      );
    }
    const idField = form.fields['id'];
    if (idField !== 'insert') {
      throw new HttpsError(
        'failed-precondition',
        `INSERTモードではありません (id=${idField})。書き込みを中止しました。`
      );
    }

    if (form.goals.length === 0) {
      throw new HttpsError('failed-precondition', '目標行が取得できませんでした');
    }
    if (considerations.length !== form.goals.length) {
      throw new HttpsError(
        'failed-precondition',
        `考察項目数 (${considerations.length}) と HUG の目標数 (${form.goals.length}) が一致しません`
      );
    }

    for (const g of form.goals) {
      const existing = (form.fields[`consideration[${g.id}][${g.id}]`] || '').trim();
      if (existing.length > 0) {
        throw new HttpsError(
          'failed-precondition',
          `goalId=${g.id} に既に考察が入力されています。中止しました。`
        );
      }
    }
    const existingLong = (form.fields['consideration_monita'] || '').trim();
    const existingShort = (form.fields['consideration_monita2'] || '').trim();
    const existingRemark = (form.fields['monitoring_remark'] || '').trim();
    if (existingLong || existingShort || existingRemark) {
      throw new HttpsError('failed-precondition', '長期/短期/備考のいずれかに既に入力があります。中止しました。');
    }

    const logRef = await db.collection('monitoring_write_log').add({
      studentId,
      studentName,
      hugCId: String(hugCId),
      originKaisuu: form.fields['origin_kaisuu'] || '',
      goalCount: form.goals.length,
      considerations,
      longTerm: longTerm || '',
      shortTerm: shortTerm || '',
      remark: remark || '',
      formFieldsSnapshot: form.fields,
      createdAt: FieldValue.serverTimestamp(),
      status: 'pending',
    });

    const merged = { ...form.fields };
    merged.moni_draft_flg = '1';
    merged.created_name = '10';

    form.goals.forEach((g, i) => {
      merged[`achievement[${g.id}][${g.id}]`] = '3';
      merged[`achievement_text[${g.id}][${g.id}]`] = '';
      merged[`evaluation[${g.id}][${g.id}]`] = '1';
      merged[`evaluation_text[${g.id}][${g.id}]`] = '';
      merged[`consideration[${g.id}][${g.id}]`] = String(considerations[i] || '').slice(0, 2000);
    });
    merged.consideration_monita = String(longTerm || '').slice(0, 2000);
    merged.consideration_monita2 = String(shortTerm || '').slice(0, 2000);
    merged.hope_of_the_person = '';
    merged.demands_of_your_family = '';
    merged.needs_of_stakeholders = '';
    merged.monitoring_remark = String(remark || '').slice(0, 2000);

    try {
      const csrfToken = merged.csrf_token_from_client || '';
      const modeToken = merged.mode_token || 'nomode';
      const hugPageUrl = merged.hug_page_url || 'individual_monitoring.php';
      const tokenUrl = `${HUG_BASE_URL}/ajax/ajax_token.php?token=${encodeURIComponent(csrfToken)}&mode=${encodeURIComponent(modeToken)}&hug_page_url=${encodeURIComponent(hugPageUrl)}`;
      await hugFetch(tokenUrl, {}, cookies);
    } catch (e) {
      console.warn('[monitoring] token check failed:', e.message);
    }

    const FormData = require('form-data');
    const fd = new FormData();
    for (const [k, v] of Object.entries(merged)) {
      fd.append(k, v == null ? '' : String(v));
    }

    const postRes = await fetch(`${HUG_BASE_URL}/individual_monitoring.php`, {
      method: 'POST',
      headers: { ...fd.getHeaders(), 'Cookie': cookies },
      body: fd,
      redirect: 'manual',
    });
    const postText = await postRes.text();
    console.log('[monitoring] INSERT POST status:', postRes.status, 'len:', postText.length);

    const ok = postRes.status === 302 || postRes.status === 200;
    await logRef.update({
      status: ok ? 'success' : 'failed',
      postStatus: postRes.status,
      completedAt: FieldValue.serverTimestamp(),
    });

    if (!ok) {
      throw new HttpsError('internal', `HUG POST失敗 status=${postRes.status}`);
    }

    return {
      success: true,
      logId: logRef.id,
      kaisuu: form.fields['origin_kaisuu'] || '',
      goalCount: form.goals.length,
      listUrl: `${HUG_BASE_URL}/individual_monitoring.php?c_id=${hugCId}`,
    };
  }
);
