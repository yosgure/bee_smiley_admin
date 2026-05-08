// Hug の profile_children.php から各児童の「給付支給量」「合計契約支給量」を取得し、
// plus_families.children[].recipientCard.{supplyDays, contractDays, supplyMonth, lastSyncedAt}
// に反映する。
//
// - syncHugRecipientLimits  : 手動 (onCall)
// - syncHugRecipientLimitsScheduled : 毎日 04:00 JST 実行 (cron)

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const cheerio = require("cheerio");

const { db, FieldValue, hugUsername, hugPassword } = require('../utils/setup');
const {
  HUG_BASE_URL,
  hugFetch,
  loginToHug,
} = require('../utils/hug-client');

const PROFILE_URL = `${HUG_BASE_URL}/profile_children.php`;

/**
 * "10日" / "5日" 等から数値部分だけ取り出す。空欄は null。
 */
function parseDays(text) {
  if (!text) return null;
  const m = String(text).replace(/[\s　]/g, '').match(/(\d+)/);
  if (!m) return null;
  return parseInt(m[1], 10);
}

/**
 * プロフィール一覧ページの HTML から児童行をパース。
 * 戻り値: [{ hugChildId, name, supplyDays, contractDays }]
 */
function parseProfileChildrenHtml(html) {
  const $ = cheerio.load(html);
  const rows = [];
  // ヘッダー判定: 「給付支給量」「合計契約支給量」「児童名」 を含むテーブルのみ対象
  $('table').each((_, table) => {
    const headText = $(table).find('th').text();
    if (!headText.includes('給付支給量') || !headText.includes('合計契約支給量')) return;

    // 各 tr に対応する 詳細リンクから hugChildId 抽出 + tdTexts から日数抽出
    $(table).find('tbody tr, tr').each((_, tr) => {
      const $tr = $(tr);
      const detailLink = $tr.find('a[href*="profile_children.php"]').first();
      if (!detailLink.length) return;
      const href = detailLink.attr('href') || '';
      const idMatch = href.match(/[?&]id=(\d+)/);
      if (!idMatch) return;
      const hugChildId = idMatch[1];

      // 児童名（ふりがな前まで）
      const nameCell = $tr.find('td').eq(1).text().trim();
      const name = nameCell.split(/\s|（/)[0] || nameCell;

      // 各 td テキストを集めて、給付/合計契約 の位置を特定
      const tds = $tr.find('td').map((_, td) => $(td).text().trim().replace(/\s+/g, ' ')).get();
      // 列順: [詳細] [児童名/ふりがな + 受給者証] [給付支給量] [合計契約支給量] [性別/年齢] ...
      // 給付支給量・合計契約支給量は連続した2セルに入る想定。
      let supplyDays = null;
      let contractDays = null;
      // 「N日」形式のセルを上から順に2つ拾う（ヒューリスティック）
      const dayCells = tds.filter((t) => /^\d+日?$/.test(t.replace(/[\s　]/g, '')));
      if (dayCells.length >= 2) {
        supplyDays = parseDays(dayCells[0]);
        contractDays = parseDays(dayCells[1]);
      } else if (dayCells.length === 1) {
        // 給付支給量だけ取れたケース
        supplyDays = parseDays(dayCells[0]);
      }

      rows.push({ hugChildId: String(hugChildId), name, supplyDays, contractDays });
    });
  });
  return rows;
}

/**
 * Hug ログイン → profile_children.php を取得 → パース。
 */
async function fetchRecipientLimits(debugInfo = null) {
  const cookies = await loginToHug();

  // GET 取得（既定状態の HTML 確認用）
  const res = await hugFetch(PROFILE_URL, {}, cookies);
  const html = await res.text();
  const getInfo = {
    length: html.length,
    has給付: html.includes('給付支給量'),
    has全部: html.includes('全部で'),
    snippet: html.substring(0, 800).replace(/\s+/g, ' '),
  };
  console.log(`[recipient] GET html length=${html.length}, includes(給付支給量)=${html.includes('給付支給量')}, includes(全部で)=${html.includes('全部で')}`);
  if (debugInfo) debugInfo.get = getInfo;

  let rows = parseProfileChildrenHtml(html);
  console.log(`[recipient] parsed from GET: ${rows.length} rows`);
  if (debugInfo) debugInfo.getRows = rows.length;

  // GET で取れない場合は フォーム解析 + POST で再試行
  if (rows.length === 0) {
    const $form = cheerio.load(html);

    // フォーム特定 (name="search" など) を探す
    let $targetForm = null;
    $form('form').each((_, f) => {
      const html = $form(f).html() || '';
      if (html.includes('pccontract') || html.includes('contract_facility')) {
        $targetForm = $form(f);
      }
    });
    if (!$targetForm) {
      $targetForm = $form('form').first();
    }

    const formData = {};
    $targetForm.find('input[type="hidden"]').each((_, el) => {
      const name = $form(el).attr('name');
      const value = $form(el).attr('value') || '';
      if (name) formData[name] = value;
    });
    // 全 input の name 一覧をログ
    const allInputs = [];
    $targetForm.find('input, select').each((_, el) => {
      const name = $form(el).attr('name');
      const type = $form(el).attr('type') || $form(el).get(0).tagName;
      const value = $form(el).attr('value') || '';
      const checked = $form(el).attr('checked') !== undefined;
      if (name) allInputs.push(`${type}:${name}=${value}${checked ? '(checked)' : ''}`);
    });
    console.log(`[recipient] form inputs: ${allInputs.join(', ')}`);

    const now = new Date();
    formData['pccontract_y'] = String(now.getFullYear());
    formData['pccontract_m'] = String(now.getMonth() + 1);

    // 全 checkbox (チェックされているもの) を含める
    $targetForm.find('input[type="checkbox"]').each((_, el) => {
      const name = $form(el).attr('name');
      const value = $form(el).attr('value') || 'on';
      if (!name) return;
      // 既存値があれば配列に
      if (formData[name] !== undefined) {
        if (!Array.isArray(formData[name])) formData[name] = [formData[name]];
        formData[name].push(value);
      } else {
        formData[name] = value;
      }
    });

    // 検索ボタン
    formData['search'] = '検索';

    // URLSearchParams で配列対応
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(formData)) {
      if (Array.isArray(v)) {
        for (const vv of v) params.append(k, vv);
      } else {
        params.append(k, v);
      }
    }
    console.log(`[recipient] POST body keys: ${Object.keys(formData).join(', ')}`);

    const postRes = await hugFetch(PROFILE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    }, cookies);
    const postHtml = await postRes.text();
    console.log(`[recipient] POST status=${postRes.status}, html length=${postHtml.length}, includes(給付支給量)=${postHtml.includes('給付支給量')}, includes(全部で)=${postHtml.includes('全部で')}`);

    rows = parseProfileChildrenHtml(postHtml);
    console.log(`[recipient] parsed from POST: ${rows.length} rows`);

    if (debugInfo) {
      debugInfo.postStatus = postRes.status;
      debugInfo.postLength = postHtml.length;
      debugInfo.postHas給付 = postHtml.includes('給付支給量');
      debugInfo.postHas全部 = postHtml.includes('全部で');
      debugInfo.postRows = rows.length;
      debugInfo.formInputs = allInputs;
      const idx = postHtml.indexOf('給付支給量');
      if (idx >= 0) {
        const startIdx = Math.max(0, idx - 200);
        debugInfo.snippetNear給付 = postHtml.substring(startIdx, startIdx + 1500).replace(/\s+/g, ' ');
      } else {
        debugInfo.bodySnippet = postHtml.substring(0, 1500).replace(/\s+/g, ' ');
      }
    }

    if (rows.length === 0) {
      const idx = postHtml.indexOf('給付支給量');
      const startIdx = Math.max(0, idx - 200);
      console.log(`[recipient] html snippet near 給付支給量 (idx=${idx}):`);
      console.log(postHtml.substring(startIdx, startIdx + 1500).replace(/\s+/g, ' '));
    }
  }

  return rows;
}

/**
 * パース結果を plus_families に書き戻し。
 * children[i].hugChildId が一致するレコードを更新。
 */
async function applyToFirestore(rows) {
  const now = new Date();
  const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  const byHugId = new Map();
  for (const r of rows) byHugId.set(String(r.hugChildId), r);

  let updatedFamilies = 0;
  let updatedChildren = 0;

  const snap = await db.collection('plus_families').get();
  for (const famDoc of snap.docs) {
    const data = famDoc.data();
    const children = Array.isArray(data.children) ? data.children : [];
    if (children.length === 0) continue;

    let dirty = false;
    const newChildren = children.map((child) => {
      if (!child || typeof child !== 'object') return child;
      const hugId = child.hugChildId ? String(child.hugChildId) : null;
      if (!hugId) return child;
      const r = byHugId.get(hugId);
      if (!r) return child;
      const prev = (child.recipientCard && typeof child.recipientCard === 'object')
        ? child.recipientCard
        : {};
      const next = {
        ...prev,
        supplyDays: r.supplyDays,
        contractDays: r.contractDays,
        supplyMonth: monthKey,
        lastSyncedAt: FieldValue.serverTimestamp(),
      };
      // 値に変化がなければスキップ
      if (
        prev.supplyDays === next.supplyDays &&
        prev.contractDays === next.contractDays &&
        prev.supplyMonth === next.supplyMonth
      ) {
        return child;
      }
      dirty = true;
      updatedChildren++;
      return { ...child, recipientCard: next };
    });

    if (dirty) {
      await famDoc.ref.update({ children: newChildren });
      updatedFamilies++;
    }
  }

  return { totalRows: rows.length, updatedFamilies, updatedChildren };
}

async function syncCore({ debug = false } = {}) {
  const debugInfo = {};
  const rows = await fetchRecipientLimits(debug ? debugInfo : null);
  console.log(`[syncHugRecipientLimits] parsed ${rows.length} rows`);
  const result = await applyToFirestore(rows);
  console.log('[syncHugRecipientLimits] result:', JSON.stringify(result));
  if (debug) result.debug = debugInfo;
  return result;
}

exports.syncHugRecipientLimits = onCall(
  {
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 300,
    secrets: [hugUsername, hugPassword],
  },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    try {
      const debug = !!(request.data && request.data.debug);
      return await syncCore({ debug });
    } catch (error) {
      console.error('syncHugRecipientLimits error:', error);
      throw new HttpsError('internal', error.message || 'sync failed');
    }
  }
);

exports.syncHugRecipientLimitsScheduled = onSchedule(
  {
    schedule: '0 4 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-northeast1',
    memory: '512MiB',
    timeoutSeconds: 300,
    secrets: [hugUsername, hugPassword],
  },
  async () => {
    try {
      const result = await syncCore();
      console.log('Scheduled syncHugRecipientLimits result:', JSON.stringify(result));
    } catch (error) {
      console.error('Scheduled syncHugRecipientLimits error:', error);
    }
  }
);
