// HUG 5種類ドキュメント (アセスメント/個別支援計画/議事録/モニタリング) と
// ケア記録 (連絡帳) を ai_student_profiles にミラーする。
// syncHugDocs (UI), syncHugDocsScheduled (毎朝6時JST), fetchHugCareRecordBody (遅延読込) の3つを export。

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const cheerio = require("cheerio");

const { db, FieldValue, hugUsername, hugPassword } = require('../utils/setup');
const { HUG_BASE_URL, hugFetch, loginToHug } = require('../utils/hug-client');

const HUG_DOC_TYPES = {
  assessment:     { label: 'アセスメント',         urlPath: 'individual_assessment.php' },
  carePlanDraft:  { label: '個別支援計画書(原案)',   urlPath: 'individual_care-plan.php' },
  beforeMeeting:  { label: 'サービス担当者会議議事録', urlPath: 'individual_before-meeting.php' },
  carePlanMain:   { label: '個別支援計画書',         urlPath: 'individual_care-plan-main.php' },
  monitoring:     { label: 'モニタリング',           urlPath: 'individual_monitoring.php' },
};

async function scrapeHugSituationList(cookies) {
  const rows = [];
  const seenPages = new Set();
  for (let page = 1; page <= 20; page++) {
    const url = `${HUG_BASE_URL}/individual_situation.php?page=${page}`;
    const res = await hugFetch(url, {}, cookies);
    const html = await res.text();
    const $ = cheerio.load(html);

    const pageHash = html.length + ':' + (html.indexOf('<tbody') || 0);
    if (seenPages.has(pageHash)) break;
    seenPages.add(pageHash);

    const pageRowsBefore = rows.length;
    $('table tbody tr, table tr').each((_, tr) => {
      const $tr = $(tr);
      const childLink = $tr.find('a[href*="profile_children.php"]').first();
      if (!childLink.length) return;
      const childHref = childLink.attr('href') || '';
      const cIdMatch = childHref.match(/id=(\d+)/);
      if (!cIdMatch) return;
      const cId = cIdMatch[1];
      const childName = childLink.text().trim();
      if (!childName) return;

      const tdTexts = $tr.find('td').map((_, td) => $(td).text().trim().replace(/\s+/g, ' ')).get();
      const facility = tdTexts.find((t) => t.includes('教室')) || tdTexts[1] || '';
      let planDate = 0;
      for (const t of tdTexts) {
        const m = t.match(/^(\d{4})[\/\-.年](\d{1,2})[\/\-.月](\d{1,2})/);
        if (m) {
          planDate = parseInt(m[1] + m[2].padStart(2, '0') + m[3].padStart(2, '0'), 10);
          break;
        }
      }
      if (planDate === 0) {
        for (const t of tdTexts) {
          const digits = t.replace(/[^0-9]/g, '');
          if (/^\d{8}$/.test(digits) && digits.startsWith('20')) {
            planDate = parseInt(digits, 10);
            break;
          }
        }
      }

      const docIds = {};
      for (const [type, cfg] of Object.entries(HUG_DOC_TYPES)) {
        const escaped = cfg.urlPath.replace(/\./g, '\\.').replace(/\-/g, '\\-');
        const pattern = new RegExp(escaped + '\\?mode=detail&id=(\\d+)');
        const link = $tr.find(`a[href*="${cfg.urlPath}?mode=detail"]`).first();
        if (link.length) {
          const href = link.attr('href') || '';
          const m = href.match(pattern);
          if (m) docIds[type] = m[1];
        }
      }

      rows.push({ cId, childName, planDate, facility, docIds });
    });

    if (rows.length === pageRowsBefore) break;

    const hasNext = $(`a[href*="individual_situation.php?page=${page + 1}"]`).length > 0;
    if (!hasNext) break;
  }

  const byChild = {};
  for (const row of rows) {
    if (!byChild[row.cId]) {
      byChild[row.cId] = {
        cId: row.cId,
        childName: row.childName,
        facility: row.facility,
        latestPlanDate: 0,
        docMeta: {},
      };
    }
    const agg = byChild[row.cId];
    if (row.planDate > agg.latestPlanDate) {
      agg.latestPlanDate = row.planDate;
      agg.childName = row.childName;
      agg.facility = row.facility;
    }
    for (const [type, hugId] of Object.entries(row.docIds)) {
      if (!hugId) continue;
      const prev = agg.docMeta[type];
      if (!prev || row.planDate > prev.planDate) {
        agg.docMeta[type] = { hugId, planDate: row.planDate };
      }
    }
  }
  console.log(`[HUG] scraped situation list: ${rows.length} rows, ${Object.keys(byChild).length} unique children`);
  return Object.values(byChild);
}

function extractHugDocumentText(html) {
  const $ = cheerio.load(html);
  $('script, style, nav, header, footer').remove();
  $('.global-nav, #header_top, #header, #footer, .footer, .copyright, .breadcrumb, #sidemenu, #menu').remove();
  $('button, input[type="button"], input[type="submit"]').remove();
  $('a:contains("戻る"), a:contains("印刷"), a:contains("PDFを出力"), a:contains("編集する"), a:contains("ログアウト")').remove();

  const lines = [];
  const seen = new Set();
  const push = (s) => {
    if (!s) return;
    const t = s.replace(/\s+/g, ' ').trim();
    if (t && !seen.has(t)) { seen.add(t); lines.push(t); }
  };

  const title = $('h1, h2').first().text().trim();
  if (title) push(`## ${title}`);

  $('dl, .info, .assessment-info, .right-box').each((_, el) => {
    const t = $(el).text().replace(/[\t\r]+/g, ' ').replace(/\n\s*\n/g, '\n').trim();
    if (t && t.length < 500) push(t);
  });

  $('table').each((_, table) => {
    $(table).find('tr').each((_, row) => {
      const cells = $(row).find('th, td');
      if (cells.length === 0) return;
      const texts = cells.map((_, c) => $(c).text().replace(/[\t\r]+/g, ' ').replace(/\n\s*\n/g, '\n').trim()).get();
      if (cells.length === 1) {
        push(texts[0]);
      } else {
        const label = texts[0];
        const value = texts.slice(1).join(' / ');
        if (label && value) push(`${label}: ${value}`);
        else if (label) push(label);
      }
    });
  });

  return lines.join('\n');
}

async function fetchHugDocumentDetail(cookies, type, hugId) {
  const cfg = HUG_DOC_TYPES[type];
  if (!cfg) throw new Error(`unknown doc type: ${type}`);
  const url = `${HUG_BASE_URL}/${cfg.urlPath}?mode=detail&id=${hugId}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const rawText = extractHugDocumentText(html);
  return { url, rawText, hugId };
}

async function scrapeHugCareRecords(cookies, fromDate, toDate, cIds) {
  const byChildId = {};
  let extractedCount = 0;
  const debugAttempts = [];

  const fromStr = formatYmdHyphen(fromDate);
  const toStr = formatYmdHyphen(toDate);

  const targetCIds = Array.isArray(cIds) ? cIds.filter(Boolean).map(String) : [];
  if (targetCIds.length === 0) {
    console.warn('[HUG] scrapeHugCareRecords: no target c_ids provided');
    return byChildId;
  }

  for (const cId of targetCIds) {
    const seenPages = new Set();

    for (let page = 1; page <= 50; page++) {
      const body = new URLSearchParams();
      body.append('mode', 'search');
      body.append('children', cId);
      body.append('date', fromStr);
      body.append('date_end', toStr);
      body.append('page', String(page));
      body.append('search', '1');

      const url = `${HUG_BASE_URL}/contact_book.php`;
      const res = await hugFetch(url, {
        method: 'POST',
        body,
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      }, cookies);
      const html = await res.text();
      const $ = cheerio.load(html);
      const pageHash = html.length + ':' + (html.indexOf('<tbody') || 0);
      if (seenPages.has(pageHash)) break;
      seenPages.add(pageHash);

      if (page === 1) {
        const tbodyRows = $('table tbody tr').length;
        const firstRowCells = $('table tbody tr').first().find('td').map((_, td) => $(td).text().replace(/\s+/g, ' ').trim()).get().slice(0, 12);
        debugAttempts.push({
          cId,
          page,
          htmlLength: html.length,
          tbodyRows,
          firstRowCells,
        });
        console.log(`[HUG] care records c_id=${cId} page=${page} tbodyRows=${tbodyRows}`);
      }

      let pageRows = 0;
      $('table tbody tr, table tr').each((_, tr) => {
        const $tr = $(tr);
        const cells = $tr.find('td').map((_, td) => $(td).text().replace(/\s+/g, ' ').trim()).get();
        if (cells.length === 0) return;

        let dateText = '';
        for (const c of cells) {
          if (/^\d{4}\/\d{1,2}\/\d{1,2}$/.test(c)) { dateText = c; break; }
        }
        if (!dateText) return;

        const recDate = parseHugDate(dateText);
        if (!recDate) return;
        if (recDate < fromDate || recDate > toDate) return;

        const previewHref = $tr.find('a[href*="mode=preview"]').first().attr('href') || '';
        const bookIdMatch = previewHref.match(/[?&]id=(\d+)/);
        const rowCIdMatch = previewHref.match(/[?&]c_id=(\d+)/);
        const sIdMatch = previewHref.match(/[?&]s_id=(\d+)/);
        const bookId = bookIdMatch ? bookIdMatch[1] : null;
        const rowCId = rowCIdMatch ? rowCIdMatch[1] : cId;
        const sId = sIdMatch ? sIdMatch[1] : null;

        const activity = cells[3] || '';
        const attendance = cells[4] || '';
        let recorder = '';
        for (let i = cells.length - 1; i >= 0; i--) {
          const t = cells[i];
          if (/^\d{4}\/\d{1,2}\/\d{1,2}/.test(t)) continue;
          if (t.length > 1 && t.length < 20 && !/\d{4}/.test(t)) { recorder = t; break; }
        }

        if (!byChildId[rowCId]) byChildId[rowCId] = [];
        byChildId[rowCId].push({
          date: dateText,
          activity,
          attendance,
          recorder,
          bookId,
          cId: rowCId,
          sId,
        });
        pageRows++;
        extractedCount++;
      });

      if (pageRows === 0) break;
    }
  }

  console.log(`[HUG] care records: extracted ${extractedCount} rows across ${Object.keys(byChildId).length} children (searched ${targetCIds.length})`);
  try {
    await db.collection('hug_sync_logs').add({
      kind: 'care_records_debug',
      from: fromStr,
      to: toStr,
      extractedCount,
      childrenCount: Object.keys(byChildId).length,
      searchedCIds: targetCIds.length,
      attempts: debugAttempts.slice(0, 20),
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (_) {}
  return byChildId;
}

function formatYmdHyphen(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function parseHugDate(s) {
  const m = s.match(/^(\d{4})\/(\d{1,2})\/(\d{1,2})$/);
  if (!m) return null;
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
}

function formatYmd(d) {
  return `${d.getFullYear()}/${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`;
}

async function fetchHugCareRecordBodyImpl(cookies, bookId, cId, sId) {
  const qs = new URLSearchParams({ mode: 'preview', id: String(bookId) });
  if (cId) qs.append('c_id', String(cId));
  if (sId) qs.append('s_id', String(sId));
  const url = `${HUG_BASE_URL}/contact_book.php?${qs.toString()}`;
  const res = await hugFetch(url, {}, cookies);
  const html = await res.text();
  const $ = cheerio.load(html);
  $('script, style, nav, header, footer, button').remove();
  $('#header, #footer, .print, #sidemenu').remove();
  const bodies = [];
  $('table tr').each((_, tr) => {
    const tds = $(tr).find('td').map((_, td) => $(td).text().replace(/\s+/g, ' ').trim()).get();
    for (const t of tds) {
      if (t.length >= 10 && !/^\d{4}\/\d{1,2}\/\d{1,2}$/.test(t) && !t.includes('ビースマイリー')) {
        bodies.push(t);
      }
    }
  });
  return bodies.join('\n');
}

async function buildStudentNameIndex() {
  const snap = await db.collection('families').get();
  const index = {};
  for (const doc of snap.docs) {
    const data = doc.data();
    const lastName = (data.lastName || '').replace(/\s+/g, '');
    const familyUid = data.uid || doc.id;
    const children = data.children || [];
    for (const child of children) {
      const firstName = (child.firstName || '').replace(/\s+/g, '');
      if (!firstName) continue;
      const classrooms = child.classrooms || (child.classroom ? [child.classroom] : []);
      const inScope = classrooms.some((c) => typeof c === 'string' && c.includes('湘南藤沢'));
      if (!inScope) continue;
      const fullName = `${lastName}${firstName}`;
      const studentId = child.studentId || `${familyUid}_${firstName}`;
      index[fullName] = {
        studentId,
        studentName: `${data.lastName || ''} ${child.firstName || ''}`.trim(),
        familyUid,
      };
    }
  }
  return index;
}

async function syncHugDocsCore(options = {}) {
  const targetStudentId = options.studentId || null;
  const cookies = await loginToHug();
  const situationRows = await scrapeHugSituationList(cookies);
  const nameIndex = await buildStudentNameIndex();

  const targetCIds = [];
  for (const row of situationRows) {
    const resolved = nameIndex[row.childName.replace(/\s+/g, '')];
    if (!resolved) continue;
    if (targetStudentId && resolved.studentId !== targetStudentId) continue;
    if (row.cId) targetCIds.push(row.cId);
  }

  const toDate = new Date();
  const fromDate = new Date();
  fromDate.setMonth(fromDate.getMonth() - 6);
  let careRecordsByCId = {};
  try {
    careRecordsByCId = await scrapeHugCareRecords(cookies, fromDate, toDate, targetCIds);
  } catch (e) {
    console.error('[HUG] care records scrape failed:', e.message);
  }

  const summary = {
    totalChildren: situationRows.length,
    synced: 0,
    skippedUnmapped: 0,
    errors: [],
  };
  const unmapped = [];

  for (const row of situationRows) {
    const resolved = nameIndex[row.childName.replace(/\s+/g, '')];
    if (!resolved) {
      summary.skippedUnmapped++;
      unmapped.push({ hugChildName: row.childName, hugCId: row.cId });
      continue;
    }
    if (targetStudentId && resolved.studentId !== targetStudentId) continue;

    const hugDocs = {};
    for (const type of Object.keys(HUG_DOC_TYPES)) {
      const meta = row.docMeta?.[type];
      if (!meta) {
        hugDocs[type] = { status: 'not-created', fetchedAt: FieldValue.serverTimestamp() };
        continue;
      }
      try {
        const detail = await fetchHugDocumentDetail(cookies, type, meta.hugId);
        hugDocs[type] = {
          hugId: meta.hugId,
          rawText: detail.rawText,
          url: detail.url,
          status: 'ok',
          planDate: meta.planDate,
          fetchedAt: FieldValue.serverTimestamp(),
        };
      } catch (e) {
        console.error(`[HUG] detail fetch failed for ${row.childName} ${type}:`, e);
        hugDocs[type] = { status: 'error', error: e.message, fetchedAt: FieldValue.serverTimestamp() };
        summary.errors.push({ childName: row.childName, type, error: e.message });
      }
    }

    const careRecords = (careRecordsByCId[row.cId] || []).slice().sort((a, b) => b.date.localeCompare(a.date));
    for (const rec of careRecords.slice(0, 5)) {
      if (!rec.bookId || rec.body) continue;
      try {
        rec.body = await fetchHugCareRecordBodyImpl(cookies, rec.bookId, rec.cId, rec.sId);
      } catch (e) {
        console.warn(`[HUG] care record body fetch failed id=${rec.bookId}:`, e.message);
      }
    }

    const hugProfileUrl = row.cId
      ? `${HUG_BASE_URL}/profile_children.php?mode=profile&id=${row.cId}`
      : '';

    await db.collection('ai_student_profiles').doc(resolved.studentId).set({
      studentId: resolved.studentId,
      studentName: resolved.studentName,
      familyUid: resolved.familyUid,
      hugCId: row.cId,
      hugProfileUrl,
      hugDocs,
      latestPlanDate: row.latestPlanDate || 0,
      hugCareRecords: careRecords,
      hugCareRecordsRange: {
        from: formatYmd(fromDate),
        to: formatYmd(toDate),
      },
      lastSyncedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    summary.synced++;
  }

  await db.collection('hug_settings').doc('unmapped_children').set({
    unmapped,
    updatedAt: FieldValue.serverTimestamp(),
  });

  await db.collection('hug_sync_logs').add({
    kind: 'docs',
    summary,
    targetStudentId,
    startedAt: FieldValue.serverTimestamp(),
  });

  console.log(`[HUG] docs sync done:`, JSON.stringify(summary));
  return summary;
}

exports.syncHugDocs = onCall(
  {
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 540,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    try {
      const studentId = request.data?.studentId || null;
      const result = await syncHugDocsCore({ studentId });
      return { success: true, ...result };
    } catch (e) {
      console.error('syncHugDocs error:', e);
      throw new HttpsError('internal', `HUG同期エラー: ${e.message}`);
    }
  }
);

exports.fetchHugCareRecordBody = onCall(
  {
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 60,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', '認証が必要です');
    const bookId = request.data?.bookId;
    const cId = request.data?.cId;
    const sId = request.data?.sId;
    if (!bookId) throw new HttpsError('invalid-argument', 'bookId が必要です');
    try {
      const cookies = await loginToHug();
      const body = await fetchHugCareRecordBodyImpl(cookies, String(bookId), cId ? String(cId) : null, sId ? String(sId) : null);
      return { success: true, bookId: String(bookId), body };
    } catch (e) {
      console.error('fetchHugCareRecordBody error:', e);
      throw new HttpsError('internal', `HUG取得エラー: ${e.message}`);
    }
  }
);

exports.syncHugDocsScheduled = onSchedule(
  {
    schedule: '0 6 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 540,
    secrets: [hugUsername, hugPassword],
  },
  async () => {
    try {
      const result = await syncHugDocsCore();
      console.log('[HUG] scheduled docs sync:', JSON.stringify(result));
    } catch (e) {
      console.error('[HUG] scheduled docs sync error:', e);
    }
  }
);
