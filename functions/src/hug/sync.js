// HUG への保存済みコンテンツ下書き同期。
// カテゴリ別ルーティング: 欠席系 → attendance.php / 子育てサポート系 → record_proceedings.php / それ以外 → contact_book.php。
// syncToHug (manual) と syncToHugScheduled (cron) で syncToHugCore を共有する。

const fetch = require("node-fetch");
const cheerio = require("cheerio");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const { db, hugUsername, hugPassword } = require('../utils/setup');
const {
  HUG_BASE_URL,
  hugFetch,
  loginToHug,
  getHugMappings,
  normalizeName,
  findMapping,
} = require('../utils/hug-client');

/**
 * 記録一覧ページから児童名→r_id, c_idのマッピングを構築
 */
async function getChildRecordIds(cookies, date) {
  const url = `${HUG_BASE_URL}/contact_book.php?f_id=1&date=${date}&state=clear`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const childMap = {};

  // HUG が返したレコードの実 cal_date を onclick/href から抽出。
  // 指定日に記録が無いと HUG が直近の別日付の記録を返してくる場合があるため、
  // 後段で厳密に日付一致を検証して誤上書きを防ぐ。
  const parseCalDate = (s) => {
    const m = (s || '').match(/cal_date=(\d{4}-\d{2}-\d{2})/);
    return m ? m[1] : null;
  };

  $('button').each((_, el) => {
    const onclick = $(el).attr('onclick') || '';
    const idMatch = onclick.match(/id=(\d+)/);
    const cidMatch = onclick.match(/c_id=(\d+)/);
    if (idMatch && cidMatch && onclick.includes('mode=edit')) {
      const rId = idMatch[1];
      const cId = cidMatch[1];
      const realCalDate = parseCalDate(onclick) || date;

      const row = $(el).closest('tr');
      const nameCell = row.find('td').eq(1).text().trim();
      const name = nameCell.replace(/さん.*$/, '').trim();

      if (name && cId) {
        childMap[name] = { rId, cId, calDate: realCalDate };
      }
    }
  });

  $('a[href*="mode=preview"]').each((_, el) => {
    const href = $(el).attr('href') || '';
    const idMatch = href.match(/id=(\d+)/);
    const cidMatch = href.match(/c_id=(\d+)/);
    if (idMatch && cidMatch) {
      const rId = idMatch[1];
      const cId = cidMatch[1];
      const realCalDate = parseCalDate(href) || date;

      const row = $(el).closest('tr');
      const nameCell = row.find('td').eq(1).text().trim();
      const name = nameCell.replace(/さん.*$/, '').trim();

      if (name && cId && !childMap[name]) {
        childMap[name] = { rId, cId, calDate: realCalDate };
      }
    }
  });

  console.log(`Found ${Object.keys(childMap).length} children on ${date}`);
  return childMap;
}

/**
 * 児童の編集ページからフォームhiddenフィールドを全取得
 */
async function getEditPageFields(cookies, rId, calDate, cId) {
  const url = `${HUG_BASE_URL}/contact_book.php?mode=edit&id=${rId}&cal_date=${calDate}&c_id=${cId}`;
  console.log('[getEditPageFields] URL:', url);
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const allFieldNames = [];
  $('form input').each((_, el) => {
    allFieldNames.push(`input[${$(el).attr('type')}] name=${$(el).attr('name')}`);
  });
  $('form textarea').each((_, el) => {
    allFieldNames.push(`textarea name=${$(el).attr('name')}`);
  });
  $('form select').each((_, el) => {
    allFieldNames.push(`select name=${$(el).attr('name')}`);
  });
  console.log('[getEditPageFields] ALL form fields:', JSON.stringify(allFieldNames));

  const fields = {};
  $('form input[type="hidden"]').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) fields[name] = value;
  });

  $('form select').each((_, el) => {
    const name = $(el).attr('name');
    const selectedValue = $(el).find('option[selected]').attr('value') || $(el).find('option').first().attr('value') || '';
    if (name && !fields[name]) fields[name] = selectedValue;
  });

  $('form textarea').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).text() || '';
    if (name && !fields[name]) fields[name] = value;
  });

  return fields;
}

/**
 * hugに記録を下書き保存
 */
async function saveDraftToHug(cookies, formFields, recordStaffId, noteText) {
  console.log('[saveDraft] formFields keys:', Object.keys(formFields));

  const FormData = require('form-data');
  const formData = new FormData();

  for (const [key, value] of Object.entries(formFields)) {
    if (['note', 'note_hide', 'staff_note', 'staff_note_hide', 'mode', 'state', 'record_staff'].includes(key)) continue;
    formData.append(key, value);
  }

  formData.append('mode', 'regist');
  formData.append('state', '1');
  formData.append('record_staff', recordStaffId);

  formData.append('note', noteText);
  formData.append('note_hide', noteText);

  formData.append('staff_note', '');
  formData.append('staff_note_hide', '');

  console.log('[saveDraft] sending multipart/form-data POST');

  const postHeaders = {
    ...formData.getHeaders(),
    'Cookie': cookies,
  };

  const res = await fetch(`${HUG_BASE_URL}/contact_book.php`, {
    method: 'POST',
    headers: postHeaders,
    body: formData,
    redirect: 'manual',
  });

  const responseText = await res.text();
  console.log('[saveDraft] response status:', res.status);
  console.log('[saveDraft] response body (first 500):', responseText.substring(0, 500));

  return res.status === 302 || res.status === 200;
}

async function getRecordProceedingsForm(cookies) {
  const url = `${HUG_BASE_URL}/record_proceedings.php?mode=edit`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const hidden = {};
  $('form input[type="hidden"]').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) hidden[name] = value;
  });

  const addingMap = {};
  $('select[name="adding_children_id"] option').each((_, el) => {
    const v = $(el).attr('value') || '';
    const t = ($(el).text() || '').trim();
    if (v && v !== '0' && t) addingMap[t] = v;
  });

  return { hidden, addingMap };
}

function resolveAddingChildrenId(addingMap, categoryLabel) {
  const normalized = normalizeName(categoryLabel);

  // 「関係機関連携」カテゴリは HUG 側に（Ⅰ）と（Ⅱ）が併存する。
  // 現状の運用要件は（Ⅱ）固定のため、Ⅱ を含むラベルを優先的に選ぶ。
  if (normalized.includes('関係機関連携')) {
    for (const [label, id] of Object.entries(addingMap)) {
      const n = normalizeName(label);
      if (n.includes('関係機関連携') && (n.includes('Ⅱ') || n.includes('II'))) {
        return id;
      }
    }
  }

  for (const [label, id] of Object.entries(addingMap)) {
    const n = normalizeName(label);
    if (n === normalized) return id;
    if (n.includes(normalized) || normalized.includes(n)) return id;
  }
  return null;
}

async function fetchChildFacilityService(cookies, childId, addingChildrenId, interviewDate) {
  const body = new URLSearchParams();
  body.append('rp_id', 'insert');
  body.append(`c_id_list[${childId}]`, String(childId));
  body.append(`f_id_list[${childId}]`, '1');
  body.append('interview_date', interviewDate);
  body.append('adding_children_id', String(addingChildrenId));
  body.append('change_type', 'adding_children');
  body.append('mode', 'getData');

  const res = await fetch(`${HUG_BASE_URL}/ajax/ajax_record_proceedings.php`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'X-Requested-With': 'XMLHttpRequest',
      'Accept': '*/*',
      'Cookie': cookies,
    },
    body: body.toString(),
    redirect: 'manual',
  });
  const txt = await res.text();
  if (!txt) throw new Error('ajax_record_proceedings.php から空のレスポンス');
  let data;
  try { data = JSON.parse(txt); }
  catch (e) { throw new Error(`ajax_record_proceedings.php のJSONパースに失敗: ${e.message}`); }

  const facilityDom = (data.facility_dom || {})[childId] || '';
  const childrenInfo = (data.children_info || {})[childId] || '';

  const fIdMatch = facilityDom.match(/value=["'](\d+)["']\s+selected/);
  const fId = fIdMatch ? fIdMatch[1] : null;

  const sIdMatch = childrenInfo.match(/name=["']c_id_list\[\d+\]\[s_id\]["'][^>]*value=["'](\d+)["']/);
  const sId = sIdMatch ? sIdMatch[1] : null;

  if (!fId || !sId) {
    throw new Error(`児童(c_id=${childId})の契約施設/サービスが取得できません (f_id=${fId}, s_id=${sId})`);
  }
  return { fId, sId };
}

async function saveToRecordProceedings(cookies, params) {
  const { hidden, addingChildrenId, childId, recorderStaffId, dateStr, title, content, startTime, endTime } = params;

  const [y, m, d] = dateStr.split('-');
  const interviewDate = `${y}年${m}月${d}日`;

  const { fId, sId } = await fetchChildFacilityService(cookies, childId, addingChildrenId, interviewDate);
  console.log(`[recordProceedings] c_id=${childId} → f_id=${fId} s_id=${sId}`);

  // "HH:MM" → ["HH", "MM"]、未指定なら空文字。
  // HUG 側は hour/minute を別フィールドで受ける（zero-padding は不問）。
  const splitHM = (s) => {
    if (!s || typeof s !== 'string' || !s.includes(':')) return ['', ''];
    const [h, m] = s.split(':');
    return [h || '', m || ''];
  };
  const [startHour, startMin] = splitHM(startTime);
  const [endHour, endMin] = splitHM(endTime);

  const FormData = require('form-data');
  const formData = new FormData();

  const skipKeys = new Set(['adding_children_id', 'mode', 'id', 'draft_flg', 'title']);
  for (const [key, value] of Object.entries(hidden)) {
    if (skipKeys.has(key)) continue;
    if (key.startsWith('c_id_list[0]')) continue;
    formData.append(key, value);
  }

  formData.append('adding_children_id', addingChildrenId);
  formData.append('title', '');
  formData.append(`c_id_list[${childId}][id]`, String(childId));
  formData.append(`c_id_list[${childId}][person_absence_note]`, '');
  formData.append(`c_id_list[${childId}][f_id]`, String(fId));
  formData.append(`c_id_list[${childId}][s_id]`, String(sId));
  formData.append('recorder', String(recorderStaffId));
  formData.append('interview_staff[]', String(recorderStaffId));
  formData.append('interview_date', interviewDate);
  formData.append('start_hour', startHour);
  formData.append('start_time', startMin);
  formData.append('end_hour', endHour);
  formData.append('end_time', endMin);
  formData.append('start_hour2', '');
  formData.append('start_time2', '');
  formData.append('end_hour2', '');
  formData.append('end_time2', '');
  formData.append('add_date', '');
  formData.append('nursing_support_date', '');
  formData.append('ro_list[1][related_organizations]', '');
  formData.append('ro_list[1][related_organizations_manager]', '');
  formData.append('ro_list[2][related_organizations]', '');
  formData.append('ro_list[2][related_organizations_manager]', '');
  formData.append('support_office_id', '0');
  formData.append('support_office_manager', '');
  formData.append('customize[title][]', title || '');
  formData.append('customize[contents][]', content || '');
  formData.append('draft_flg', 'created');
  formData.append('mode', 'regist');
  formData.append('id', 'insert');

  console.log('[recordProceedings] sending multipart POST',
    `adding_children_id=${addingChildrenId} c_id=${childId} f_id=${fId} s_id=${sId} recorder=${recorderStaffId} date=${interviewDate}`);

  const postHeaders = {
    ...formData.getHeaders(),
    'Cookie': cookies,
  };

  const res = await fetch(`${HUG_BASE_URL}/record_proceedings.php`, {
    method: 'POST',
    headers: postHeaders,
    body: formData,
    redirect: 'manual',
  });

  const body = await res.text();
  console.log('[recordProceedings] response status:', res.status, 'Location:', res.headers.get('location'));
  console.log('[recordProceedings] response body length:', body.length);

  if (res.status === 302) return true;

  const $err = cheerio.load(body);
  const errorTexts = [];
  $err('.error, .alert, .warning, .msg_error, p.err, .err, [class*="error"]').each((_, el) => {
    const t = $err(el).text().trim();
    if (t && t.length > 3) errorTexts.push(t);
  });
  const pageTitle = $err('title').text().trim();
  console.error('[recordProceedings] page title:', pageTitle);
  console.error('[recordProceedings] validation errors:', JSON.stringify(errorTexts.slice(0, 10)));
  const bodyIdx = body.indexOf('入力内容に誤り');
  const errIdx = body.search(/err|error|alert/i);
  const snippetIdx = bodyIdx > 0 ? bodyIdx : (errIdx > 0 ? errIdx : 0);
  console.error('[recordProceedings] body snippet:', body.substring(Math.max(0, snippetIdx - 200), snippetIdx + 800).replace(/\s+/g, ' '));

  throw new Error(
    errorTexts.length > 0
      ? `HUGのバリデーションエラー: ${errorTexts.slice(0, 3).join(' / ')}`
      : `HUG保存失敗 (status=${res.status})`
  );
}

async function findAttendanceRecord(cookies, childId, dateStr) {
  const detailUrl = `${HUG_BASE_URL}/attendance.php?mode=detail&f_id=1&date=${dateStr}`;
  const res = await hugFetch(detailUrl, {}, cookies);
  const html = await res.text();

  const editUrlStrs = [...new Set(
    Array.from(html.matchAll(/attendance\.php\?[^"'\s<>]*mode=edit[^"'\s<>]*/g)).map(m => m[0])
  )];
  if (editUrlStrs.length === 0) {
    throw new Error(`${dateStr} の出席表が見つかりません (f_id=1)。HUG上で該当日の出席レコードが作成されているか確認してください。`);
  }

  const fetchEditPage = async (u) => {
    let lastErr = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const r = await hugFetch(`${HUG_BASE_URL}/${u}`, {}, cookies);
        const h = await r.text();
        const $ = cheerio.load(h);
        const cId = $('input[name="c_id"]').attr('value') || '';
        const fId = $('input[name="f_id"]').attr('value') || '';
        const rId = $('input[name="r_id"]').attr('value') || '';
        const sId = $('input[name="s_id"]').attr('value') || '';
        if (!cId && attempt === 0) {
          await new Promise((res) => setTimeout(res, 300));
          continue;
        }
        return { editUrl: u, cId, fId, rId, sId };
      } catch (e) {
        lastErr = e;
        if (attempt === 0) await new Promise((res) => setTimeout(res, 300));
      }
    }
    return { editUrl: u, cId: '', fId: '', rId: '', sId: '', error: lastErr?.message || 'unknown' };
  };
  const results = await Promise.all(editUrlStrs.map(fetchEditPage));

  const match = results.find((r) => String(r.cId) === String(childId));
  if (!match) {
    const emptyCount = results.filter((r) => !r.cId).length;
    throw new Error(
      `c_id=${childId} の出席レコードが ${dateStr} 内に見つかりません。` +
      `検査対象: ${results.length}件, 空レス: ${emptyCount}件, c_ids=${results.map(r => r.cId).join(',')}`
    );
  }
  return match;
}

/**
 * HUGの「児童を追加」(attendance.php?mode=add) で出席表に行を作成する。
 * 振替・スポット利用や未来日など、その日の出席表に行が無い児童向け。
 * 追加された行はHUG側で自動的に「出席」になる（時刻は未設定のため、
 * 呼び出し側で saveToAttendance により時刻を設定する）。
 */
async function addAttendanceRow(cookies, { childId, dateStr }) {
  const addUrl = `${HUG_BASE_URL}/attendance.php?mode=add&date=${dateStr}&f_id=1`;
  const res = await hugFetch(addUrl, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);

  const forms = $('form').filter((_, f) => $(f).find('input[name="mode"][value="regist_add"]').length > 0);
  if (forms.length === 0) {
    throw new Error(`HUGの「児童を追加」フォームが開けません (${dateStr})`);
  }
  const form = forms.first();

  const childOpt = form.find('select[name="children"] option').filter(
    (_, o) => String($(o).attr('value')) === String(childId)
  );
  if (childOpt.length === 0) {
    throw new Error(`c_id=${childId} がHUGの「児童を追加」の児童リストにありません (${dateStr})`);
  }

  const fields = {};
  form.find('input[type="hidden"], input[type="text"]').each((_, el) => {
    const name = $(el).attr('name');
    if (name) fields[name] = $(el).attr('value') || '';
  });
  form.find('input[type="radio"]:checked').each((_, el) => {
    const name = $(el).attr('name');
    if (name) fields[name] = $(el).attr('value') || '';
  });
  form.find('select').each((_, el) => {
    const name = $(el).attr('name');
    if (!name) return;
    const selected = $(el).find('option[selected]').attr('value');
    // ブラウザは未選択でも先頭optionの値を送信するため、selectedが無ければ先頭値で補完
    fields[name] = selected !== undefined ? selected : ($(el).find('option').first().attr('value') || '');
  });
  fields['children'] = String(childId);

  // CSRFトークンのサーバー側検証（login / monitoring と同じ事前フライト。失敗しても続行）
  try {
    const csrfToken = fields['csrf_token_from_client'] || '';
    const modeToken = fields['mode_token'] || 'add';
    const tokenUrl = `${HUG_BASE_URL}/ajax/ajax_token.php?token=${encodeURIComponent(csrfToken)}&mode=${encodeURIComponent(modeToken)}&hug_page_url=attendance.php`;
    await hugFetch(tokenUrl, {}, cookies);
  } catch (e) {
    console.warn('[attendance:add] token check failed:', e.message);
  }

  const FormData = require('form-data');
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) {
    fd.append(k, v == null ? '' : String(v));
  }

  console.log(`[attendance:add] POST regist_add c_id=${childId} date=${dateStr}`);
  const postRes = await fetch(`${HUG_BASE_URL}/attendance.php`, {
    method: 'POST',
    headers: { ...fd.getHeaders(), 'Cookie': cookies },
    body: fd,
    redirect: 'manual',
  });
  await postRes.text();
  console.log(`[attendance:add] response status=${postRes.status} Location=${postRes.headers.get('location')}`);
  if (postRes.status !== 302 && postRes.status !== 200) {
    throw new Error(`HUG「児童を追加」のPOSTに失敗しました (status=${postRes.status})`);
  }

  // 反映確認: 行が実際に作成されたか（作成されていなければ throw）
  return findAttendanceRecord(cookies, childId, dateStr);
}

async function saveToAttendance(cookies, params) {
  const { childId, dateStr, content, recorderStaffId, startTime, endTime } = params;
  const attendValue = params.attendValue || '2';
  const FormData = require('form-data');

  // コマ時刻（'15:30'）を HUG select 値（ゼロ埋めなし: hour='15', min='30'）に変換
  const parseTime = (t) => {
    if (!t || typeof t !== 'string') return null;
    const parts = t.split(':');
    if (parts.length !== 2) return null;
    const h = parseInt(parts[0], 10);
    const mi = parseInt(parts[1], 10);
    if (Number.isNaN(h) || Number.isNaN(mi)) return null;
    return { hour: String(h), min: String(mi) };
  };
  const startT = parseTime(startTime);
  const endT = parseTime(endTime);

  const MAX_CYCLES = 3;
  let lastCheckedAttend = null;
  let lastBody = '';
  let lastStatus = 0;
  let lastErrorTexts = [];
  let editUrl = '';

  for (let cycle = 0; cycle < MAX_CYCLES; cycle++) {
    if (cycle > 0) {
      await new Promise((res) => setTimeout(res, 600));
      console.log(`[attendance] retry cycle=${cycle + 1} for c_id=${childId} attend=${attendValue}`);
    }

    const record = await findAttendanceRecord(cookies, childId, dateStr);
    editUrl = `${HUG_BASE_URL}/${record.editUrl}`;
    const isInsert = /[?&]id=insert(&|$)/.test(record.editUrl);
    console.log(`[attendance] cycle=${cycle + 1} c_id=${childId} date=${dateStr} attend=${attendValue} editUrl=${record.editUrl} isInsert=${isInsert}`);

    const editRes = await hugFetch(editUrl, {}, cookies);
    const editHtml = await editRes.text();
    const $ = cheerio.load(editHtml);

    const fields = {};
    $('form input[type="hidden"]').each((_, el) => {
      const name = $(el).attr('name');
      const value = $(el).attr('value') || '';
      if (name) fields[name] = value;
    });
    $('form select').each((_, el) => {
      const name = $(el).attr('name');
      if (!name) return;
      const selected = $(el).find('option[selected]').attr('value');
      if (selected !== undefined) fields[name] = selected;
    });
    $('form textarea').each((_, el) => {
      const name = $(el).attr('name');
      const value = $(el).text() || '';
      if (name) fields[name] = value;
    });
    $('form input[type="radio"]:checked').each((_, el) => {
      const name = $(el).attr('name');
      const value = $(el).attr('value') || '';
      if (name) fields[name] = value;
    });

    const formData = new FormData();
    const skipKeys = new Set(['attend', 'attend_flg', 'absence_note', 'absence_note_staff', 'absence_note3', 'absence_note_staff3']);
    // 時刻を渡された場合のみ入室/退室時間を上書き（未指定ならHUGの既定値を保持）
    if (startT) { skipKeys.add('s_hour'); skipKeys.add('s_min'); }
    if (endT) { skipKeys.add('e_hour'); skipKeys.add('e_min'); }
    for (const [key, value] of Object.entries(fields)) {
      if (skipKeys.has(key)) continue;
      formData.append(key, value);
    }
    formData.append('attend', attendValue);
    formData.append('attend_flg', attendValue);
    if (startT) { formData.append('s_hour', startT.hour); formData.append('s_min', startT.min); }
    if (endT) { formData.append('e_hour', endT.hour); formData.append('e_min', endT.min); }
    if (attendValue === '2') {
      // 欠席（連絡あり）のみ欠席メモを記録
      formData.append('absence_note_staff', String(recorderStaffId || ''));
      formData.append('absence_note', content || '');
      formData.append('absence_note_staff3', String(recorderStaffId || ''));
      formData.append('absence_note3', content || '');
    } else {
      // 出席(1) / 欠席（加算なし）(3) は欠席メモ無し
      formData.append('absence_note_staff', '');
      formData.append('absence_note', '');
      formData.append('absence_note_staff3', '');
      formData.append('absence_note3', '');
    }

    const postUrl = editUrl;
    console.log(`[attendance] sending POST (cycle=${cycle + 1}) url=${postUrl} c_id=${childId} recorder=${recorderStaffId} attend=${attendValue}`);

    const postHeaders = {
      ...formData.getHeaders(),
      'Cookie': cookies,
    };
    const postRes = await fetch(postUrl, {
      method: 'POST',
      headers: postHeaders,
      body: formData,
      redirect: 'manual',
    });
    lastBody = await postRes.text();
    lastStatus = postRes.status;
    console.log(`[attendance] response status=${lastStatus} Location=${postRes.headers.get('location')}`);

    if (lastStatus !== 302 && lastStatus !== 200) {
      const $err = cheerio.load(lastBody);
      const errorTexts = [];
      $err('.error, .err, .alert, .warning, [class*="err"]').each((_, el) => {
        const t = $err(el).text().trim();
        if (t && t.length > 3) errorTexts.push(t);
      });
      lastErrorTexts = errorTexts;
      continue;
    }

    for (let vAttempt = 0; vAttempt < 2; vAttempt++) {
      if (vAttempt > 0) await new Promise((res) => setTimeout(res, 500));
      try {
        const verifyRes = await hugFetch(editUrl, {}, cookies);
        const verifyHtml = await verifyRes.text();
        const $v = cheerio.load(verifyHtml);
        lastCheckedAttend = $v('input[name="attend"]').filter((_, el) => $v(el).attr('checked') !== undefined).attr('value');
        console.log(`[attendance] verify(cycle=${cycle + 1},attempt=${vAttempt + 1}): checked attend=${lastCheckedAttend}, expected=${attendValue}`);
        if (String(lastCheckedAttend) === String(attendValue)) return true;
      } catch (e) {
        console.error('[attendance] verify fetch error:', e.message);
      }
    }
  }

  throw new Error(
    lastErrorTexts.length > 0
      ? `HUGのバリデーションエラー: ${lastErrorTexts.slice(0, 3).join(' / ')}`
      : `HUG保存に失敗しました（${MAX_CYCLES}回再試行後も attend=${lastCheckedAttend || '未設定'} のまま）。期待: ${attendValue} status=${lastStatus}`
  );
}

/**
 * メイン同期処理（HTTPトリガーとスケジュールトリガーで共有）
 */
async function syncToHugCore(contentIds = null) {
  let snapshot;
  if (contentIds && contentIds.length > 0) {
    const docs = await Promise.all(
      contentIds.map((id) => db.collection('saved_ai_contents').doc(id).get())
    );
    snapshot = docs.filter((d) => d.exists);
  } else {
    const result = await db.collection('saved_ai_contents').get();
    snapshot = result.docs;
  }

  if (snapshot.length === 0) {
    return { success: true, message: '処理対象なし', successCount: 0, failCount: 0, errors: [] };
  }

  const { childMapping, staffMapping } = await getHugMappings();
  const cookies = await loginToHug();

  const dateRecordCache = {};
  let recordProceedingsForm = null;

  let successCount = 0;
  let failCount = 0;
  const errors = [];

  for (const doc of snapshot) {
    const docData = doc.data ? doc.data() : doc.data;
    const docRef = doc.ref || doc;
    const docId = doc.id;

    try {
      const studentName = docData.studentName || '';
      const dateTs = docData.date;
      const content = docData.content || '';
      const recorderName = docData.recorderName || '';
      const category = docData.category || '';

      let dateStr;
      if (dateTs && dateTs.toDate) {
        const d = dateTs.toDate();
        const jst = new Date(d.getTime() + 9 * 60 * 60 * 1000);
        dateStr = `${jst.getUTCFullYear()}-${String(jst.getUTCMonth() + 1).padStart(2, '0')}-${String(jst.getUTCDate()).padStart(2, '0')}`;
      } else if (typeof dateTs === 'string') {
        dateStr = dateTs;
      } else {
        throw new Error('日付が不正です');
      }

      const hugChildId = findMapping(childMapping, studentName);
      if (!hugChildId) {
        throw new Error(`児童「${studentName}」のhugマッピングが未設定です。hug_settings/child_mappingに登録してください。`);
      }

      // 出席登録（attend=1）。記録者マッピングは任意（HUGの記録者欄は空でも可）。
      // 出席表に行が無い場合（振替/スポット/未来日）は「児童を追加」で行を作成してから時刻を設定する。
      if (normalizeName(category) === '出席') {
        const attendStaffId = findMapping(staffMapping, recorderName);
        const attendanceParams = {
          childId: hugChildId,
          dateStr,
          content: '',
          recorderStaffId: attendStaffId || '',
          attendValue: '1',
          startTime: docData.startTime || '',
          endTime: docData.endTime || '',
        };
        try {
          let success = false;
          try {
            success = await saveToAttendance(cookies, attendanceParams);
          } catch (e) {
            if (!/出席レコードが|出席表が見つかりません/.test(e.message || '')) throw e;
            // 行が無い → HUGの「児童を追加」で行を作成してから再試行
            console.log(`[attendance:present] row not found → adding child row: ${studentName} ${dateStr}`);
            await addAttendanceRow(cookies, { childId: hugChildId, dateStr });
            success = await saveToAttendance(cookies, attendanceParams);
          }
          if (success) {
            await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
            successCount++;
            console.log(`[attendance:present] synced: ${studentName} ${dateStr}`);
          } else {
            failCount++;
            errors.push({ docId, studentName, error: 'HUG（出席表）への保存に失敗しました' });
          }
        } catch (e) {
          const raw = e.message || '';
          const friendly = /児童リストにありません/.test(raw)
            ? `${studentName} さんがHUGの「児童を追加」の児童リストに見つかりません。HUG側の契約状況を確認してください。`
            : raw;
          throw new Error(friendly);
        }
        continue;
      }

      const isNoAddAbsence =
        normalizeName(category).includes('欠席（加算なし）') ||
        normalizeName(category).includes('欠席(加算なし)');

      const hugStaffId = findMapping(staffMapping, recorderName);
      if (!hugStaffId && !isNoAddAbsence) {
        throw new Error(`記録者「${recorderName}」のhugマッピングが未設定です。hug_settings/staff_mappingに登録してください。`);
      }

      if (normalizeName(category).includes('欠席（加算なし）') || normalizeName(category).includes('欠席(加算なし)')) {
        const success = await saveToAttendance(cookies, {
          childId: hugChildId,
          dateStr,
          content: '',
          recorderStaffId: hugStaffId,
          attendValue: '3',
        });
        if (success) {
          await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
          successCount++;
          console.log(`[attendance:skip] synced: ${studentName} ${dateStr}`);
        } else {
          failCount++;
          errors.push({ docId, studentName, error: 'HUG（出席表・加算なし）への保存に失敗しました' });
        }
        continue;
      }

      if (normalizeName(category).includes('欠席連絡') || normalizeName(category).includes('欠席')) {
        const success = await saveToAttendance(cookies, {
          childId: hugChildId,
          dateStr,
          content,
          recorderStaffId: hugStaffId,
          attendValue: '2',
        });
        if (success) {
          await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
          successCount++;
          console.log(`[attendance] synced: ${studentName} ${dateStr} ${category}`);
        } else {
          failCount++;
          errors.push({ docId, studentName, error: 'HUG（出席表）への保存に失敗しました' });
        }
        continue;
      }

      // 加算系カテゴリ → record_proceedings.php（各種加算・議事録管理）
      // resolveAddingChildrenId が部分一致で HUG 側の「家族支援加算（Ⅰ）」等を引き当てる。
      const ADDING_CATEGORIES = ['子育てサポート', '家族支援', '関係機関連携'];
      const isAddingCategory = ADDING_CATEGORIES.some(
        (prefix) => normalizeName(category).includes(prefix)
      );
      if (isAddingCategory) {
        if (!recordProceedingsForm) {
          recordProceedingsForm = await getRecordProceedingsForm(cookies);
        }
        const { hidden, addingMap } = recordProceedingsForm;
        const addingChildrenId = resolveAddingChildrenId(addingMap, category);
        if (!addingChildrenId) {
          throw new Error(`HUGの加算一覧に「${category}」に該当する選択肢が見つかりません。`);
        }

        const success = await saveToRecordProceedings(cookies, {
          hidden,
          addingChildrenId,
          childId: hugChildId,
          recorderStaffId: hugStaffId,
          dateStr,
          title: category,
          content,
          startTime: docData.startTime || '',
          endTime: docData.endTime || '',
        });

        if (success) {
          await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
          successCount++;
          console.log(`[recordProceedings] synced: ${studentName} ${dateStr} ${category}`);
        } else {
          failCount++;
          errors.push({ docId, studentName, error: 'HUG（加算・議事録）への保存に失敗しました' });
        }
        continue;
      }

      // ここに到達 = 欠席系・子育てサポート系のいずれにも該当しない場合のみ。
      // 既知のケア記録系ラベル以外を silent fallback でケア記録に流さない（既存記録の誤上書き防止）。
      const normalizedCategory = normalizeName(category);
      const isCareRecordCategory = normalizedCategory.includes('ケア記録') ||
        normalizedCategory.includes('ケア') ||
        normalizedCategory === '記録';
      if (!isCareRecordCategory) {
        throw new Error(
          `カテゴリ「${category}」のHUG送信先が判定できません。` +
          `欠席系 / 子育てサポート / ケア記録 のいずれかのカテゴリで送信してください。`
        );
      }

      if (!dateRecordCache[dateStr]) {
        dateRecordCache[dateStr] = await getChildRecordIds(cookies, dateStr);
      }
      const childRecords = dateRecordCache[dateStr];
      console.log(`[sync] Looking for "${studentName}" (c_id=${hugChildId}) in ${Object.keys(childRecords).length} records on ${dateStr}`);
      console.log(`[sync] Available children:`, JSON.stringify(Object.entries(childRecords).map(([k, v]) => `${k}(c_id=${v.cId},r_id=${v.rId})`)));

      let recordInfo = childRecords[studentName];
      if (!recordInfo) {
        const normalizedStudent = normalizeName(studentName);
        for (const [name, info] of Object.entries(childRecords)) {
          if (normalizeName(name) === normalizedStudent) {
            recordInfo = info;
            console.log(`[sync] Name matched (normalized): "${name}" → rId=${info.rId}`);
            break;
          }
        }
      }
      if (!recordInfo) {
        for (const [name, info] of Object.entries(childRecords)) {
          if (String(info.cId) === String(hugChildId)) {
            recordInfo = info;
            console.log(`[sync] Matched by c_id: "${name}" (c_id=${info.cId}) → rId=${info.rId}`);
            break;
          }
        }
      }

      if (!recordInfo) {
        throw new Error(
          `${dateStr} に ${studentName}さんの HUG 療育記録が見つかりません。` +
          `HUG 上で該当日に療育記録が作成されていることを確認してから再試行してください。`
        );
      }

      // 安全装置: HUG が指定日のレコードではなく直近の別日付のレコードを返してきた場合、
      // 既存記録（過去日・公開済みの可能性あり）を上書きする事故を防ぐため拒否する。
      if (recordInfo.calDate && recordInfo.calDate !== dateStr) {
        throw new Error(
          `${dateStr} に ${studentName}さんの HUG 療育記録が存在しません` +
          `（HUG が直近の ${recordInfo.calDate} の記録を返してきましたが、別日付の記録の上書きは安全のため拒否しました）。` +
          `HUG 上で ${dateStr} の療育記録を作成してから再試行してください。`
        );
      }

      console.log(`[sync] Using recordInfo: rId=${recordInfo.rId}, cId=${recordInfo.cId}, calDate=${recordInfo.calDate || dateStr}`);

      const formFields = await getEditPageFields(cookies, recordInfo.rId, recordInfo.calDate || dateStr, recordInfo.cId || hugChildId);
      if (!formFields.c_id) {
        throw new Error(
          `${dateStr} の ${studentName}さんの編集ページが取得できません。HUG 上の記録状態を確認してください。`
        );
      }

      const success = await saveDraftToHug(cookies, formFields, hugStaffId, content);

      if (success) {
        await (docRef.delete ? docRef.delete() : db.collection('saved_ai_contents').doc(docId).delete());
        successCount++;
        console.log(`Successfully synced: ${studentName} (${dateStr})`);
      } else {
        failCount++;
        errors.push({ docId, studentName, error: 'hugへの保存に失敗しました' });
      }
    } catch (error) {
      console.error(`Error processing ${docId}:`, error.message);
      failCount++;
      errors.push({ docId, studentName: docData.studentName || '', error: error.message });
    }
  }

  return { success: true, successCount, failCount, errors };
}

/**
 * HTTPトリガー: 管理画面の「hugへ送信」ボタンから呼び出し
 */
exports.syncToHug = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 120,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }

    const contentIds = request.data?.contentIds || null;

    try {
      const result = await syncToHugCore(contentIds);
      return result;
    } catch (error) {
      console.error('syncToHug error:', error);
      throw new HttpsError('internal', `hug同期エラー: ${error.message}`);
    }
  }
);

/**
 * hugマッピング設定を管理するCloud Function
 * hug一覧ページをスクレイピングして児童名・スタッフ名とIDの対応を自動取得
 */
exports.fetchHugMappings = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 60,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }

    try {
      const cookies = await loginToHug();

      const today = new Date();
      const dateStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
      const url = `${HUG_BASE_URL}/contact_book.php?f_id=1&date=${dateStr}&state=clear`;
      const res = await hugFetch(url, {}, cookies);
      const html = await res.text();
      const $ = cheerio.load(html);

      const children = [];
      const seen = new Set();
      $('select option').each((_, el) => {
        const value = $(el).attr('value') || '';
        const text = $(el).text().trim();
        if (value && /^\d+$/.test(value) && text && text !== '--' && text !== '----'
            && text.length > 1 && !/^[ぁ-ん]$/.test(text) && !seen.has(value)) {
          seen.add(value);
          children.push({ name: text, cId: value });
        }
      });

      const staffList = [];
      if (children.length > 0) {
        const firstChild = children[0];
        const editUrl = `${HUG_BASE_URL}/contact_book.php?mode=edit&id=insert&cal_date=${dateStr}&c_id=${firstChild.cId}`;
        const editRes = await hugFetch(editUrl, {}, cookies);
        const editHtml = await editRes.text();
        const $edit = cheerio.load(editHtml);

        $edit('select[name="record_staff"] option').each((_, el) => {
          const value = $edit(el).attr('value') || '';
          const text = $edit(el).text().trim();
          if (value && text) {
            staffList.push({ name: text, staffId: value });
          }
        });
      }

      return { success: true, children, staffList };
    } catch (error) {
      console.error('fetchHugMappings error:', error);
      throw new HttpsError('internal', `hugマッピング取得エラー: ${error.message}`);
    }
  }
);

/**
 * スケジュールトリガー: 毎日18時に自動実行
 */
exports.syncToHugScheduled = onSchedule(
  {
    schedule: '0 18 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 120,
    secrets: [hugUsername, hugPassword],
  },
  async () => {
    try {
      const result = await syncToHugCore();
      console.log('Scheduled sync result:', JSON.stringify(result));
    } catch (error) {
      console.error('Scheduled syncToHug error:', error);
    }
  }
);

// ローカル検証用（test_attendance_add_flow.js から HUG_LOCAL_TEST=1 で使用。
// 通常時は export しないため index.js 経由のデプロイ対象には現れない）
if (process.env.HUG_LOCAL_TEST) {
  exports.__test__ = { addAttendanceRow, saveToAttendance, findAttendanceRecord };
}
