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
async function fetchRecipientLimits() {
  const cookies = await loginToHug();

  // GET。既定で当月分が表示される想定。
  const res = await hugFetch(PROFILE_URL, {}, cookies);
  const html = await res.text();
  if (!html.includes('profile_children.php')) {
    throw new Error('profile_children.php の取得に失敗（ログイン切れ?）');
  }

  let rows = parseProfileChildrenHtml(html);

  // 取れない場合は POST で当月を明示送信して再試行
  if (rows.length === 0) {
    const $form = cheerio.load(html);
    const formData = {};
    $form('form input[type="hidden"]').each((_, el) => {
      const name = $form(el).attr('name');
      const value = $form(el).attr('value') || '';
      if (name) formData[name] = value;
    });
    const now = new Date();
    formData['pccontract_y'] = String(now.getFullYear());
    formData['pccontract_m'] = String(now.getMonth() + 1);
    // 契約施設チェックは name="contract_facility[]" などの可能性。
    // hidden を全部送るだけで GET と同等になる想定。
    const postRes = await hugFetch(PROFILE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(formData).toString(),
    }, cookies);
    const postHtml = await postRes.text();
    rows = parseProfileChildrenHtml(postHtml);
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

async function syncCore() {
  const rows = await fetchRecipientLimits();
  console.log(`[syncHugRecipientLimits] parsed ${rows.length} rows`);
  const result = await applyToFirestore(rows);
  console.log('[syncHugRecipientLimits] result:', JSON.stringify(result));
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
      return await syncCore();
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
