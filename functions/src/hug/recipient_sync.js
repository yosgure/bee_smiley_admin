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
  getHugMappings,
  findMapping,
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
 * 各児童は 2 つの tr に分かれる:
 *   tr1: <button onclick="location.href='...id=N'">詳細</button> | 名前(ふりがな) | 性別 | (空) | 上限管理事業者 | 最終更新
 *   tr2: 受給者証番号 | 給付支給量 | 合計契約支給量 | 年齢 | 適用期間
 *
 * 戻り値: [{ hugChildId, name, supplyDays, contractDays }]
 */
function parseProfileChildrenHtml(html) {
  const $ = cheerio.load(html);
  const rows = [];

  $('table').each((_, table) => {
    const headText = $(table).find('th').text();
    if (!headText.includes('給付支給量') || !headText.includes('合計契約支給量')) return;

    const trs = $(table).find('tbody > tr').toArray();
    for (let i = 0; i + 1 < trs.length; i += 2) {
      const $first = $(trs[i]);
      const $second = $(trs[i + 1]);

      // 詳細ボタンの onclick から hugChildId を抽出
      const button = $first.find('button[onclick]').first();
      const onclick = button.attr('onclick') || '';
      const idMatch = onclick.match(/[?&]id=(\d+)/);
      if (!idMatch) continue;
      const hugChildId = idMatch[1];

      // 名前: td.td-l に "赤間草月（あかまそうげつ） さん" 形式で入っている
      const nameRaw = $first.find('td.td-l').text().trim().replace(/\s+/g, ' ');
      // 全角括弧前まで
      const name = nameRaw.split(/[（(]/)[0].trim();

      // 第 2 行の td: [受給者証番号][給付支給量][合計契約支給量][年齢][適用期間]
      const tds = $second.find('> td');
      let supplyDays = null;
      let contractDays = null;
      if (tds.length >= 3) {
        supplyDays = parseDays($(tds[1]).text());
        contractDays = parseDays($(tds[2]).text());
      }

      rows.push({
        hugChildId: String(hugChildId),
        name,
        supplyDays,
        contractDays,
      });
    }
  });
  return rows;
}

/**
 * Hug ログイン → profile_children.php を全ページ取得 → パース。
 */
async function fetchRecipientLimits(debugInfo = null) {
  const cookies = await loginToHug();

  const allRows = [];
  const seenHugIds = new Set();
  const pageInfos = [];
  for (let page = 1; page <= 20; page++) {
    const url = page === 1 ? PROFILE_URL : `${PROFILE_URL}?page=${page}`;
    const res = await hugFetch(url, {}, cookies);
    const html = await res.text();
    const pageRows = parseProfileChildrenHtml(html);
    console.log(`[recipient] page=${page} html length=${html.length} rows=${pageRows.length}`);
    pageInfos.push({ page, length: html.length, rows: pageRows.length });

    // 重複・空ページで打ち切り
    let added = 0;
    for (const r of pageRows) {
      if (seenHugIds.has(r.hugChildId)) continue;
      seenHugIds.add(r.hugChildId);
      allRows.push(r);
      added++;
    }
    if (pageRows.length === 0 || added === 0) break;
  }
  if (debugInfo) {
    debugInfo.pages = pageInfos;
    debugInfo.totalRows = allRows.length;
  }
  const rows = allRows;
  return rows;
}

/**
 * パース結果を plus_families に書き戻し。
 * 解決順:
 *   1. children[i].hugChildId 一致
 *   2. legacy hug_settings/child_mapping から名前で hugChildId を解決して一致
 *   3. (フォールバック) スクレイプ結果の name でも比較
 */
async function applyToFirestore(rows, debugInfo = null) {
  const now = new Date();
  const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  const byHugId = new Map();
  for (const r of rows) byHugId.set(String(r.hugChildId), r);

  // legacy mapping (name → hugChildId)
  const { childMapping } = await getHugMappings();

  // スクレイプ結果の name → row
  const byName = new Map();
  for (const r of rows) {
    if (r.name) byName.set(String(r.name).replace(/\s/g, ''), r);
  }

  let updatedFamilies = 0;
  let updatedChildren = 0;
  const unresolvedNames = [];

  const snap = await db.collection('plus_families').get();
  for (const famDoc of snap.docs) {
    const data = famDoc.data();
    const children = Array.isArray(data.children) ? data.children : [];
    if (children.length === 0) continue;
    const familyLastName = (data.lastName || '').toString().trim();

    let dirty = false;
    const newChildren = children.map((child) => {
      if (!child || typeof child !== 'object') return child;
      const firstName = (child.firstName || '').toString().trim();

      // 解決ステップ 1: child.hugChildId
      let r = null;
      if (child.hugChildId) {
        r = byHugId.get(String(child.hugChildId));
      }
      // 解決ステップ 2: legacy mapping から hugChildId 取得
      if (!r) {
        const candidates = [
          `${familyLastName}${firstName}`,
          `${familyLastName} ${firstName}`,
          firstName,
        ];
        for (const cand of candidates) {
          const id = findMapping(childMapping, cand);
          if (id && byHugId.has(String(id))) {
            r = byHugId.get(String(id));
            break;
          }
        }
      }
      // 解決ステップ 3: スクレイプ結果の名前で一致
      if (!r) {
        const candidates = [
          `${familyLastName}${firstName}`,
          firstName,
        ];
        for (const cand of candidates) {
          const key = cand.replace(/\s/g, '');
          if (byName.has(key)) {
            r = byName.get(key);
            break;
          }
        }
      }

      if (!r) {
        if (firstName) unresolvedNames.push(`${familyLastName} ${firstName}`.trim());
        return child;
      }

      const prev = (child.recipientCard && typeof child.recipientCard === 'object')
        ? child.recipientCard
        : {};
      const next = {
        ...prev,
        supplyDays: r.supplyDays,
        contractDays: r.contractDays,
        supplyMonth: monthKey,
        lastSyncedAt: new Date(),
      };
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

  if (debugInfo) {
    debugInfo.unresolvedNames = unresolvedNames.slice(0, 50);
    debugInfo.unresolvedCount = unresolvedNames.length;
    debugInfo.scrapedNames = rows.map((r) => r.name).slice(0, 50);
  }

  return { totalRows: rows.length, updatedFamilies, updatedChildren };
}

async function syncCore({ debug = false } = {}) {
  const debugInfo = {};
  const rows = await fetchRecipientLimits(debug ? debugInfo : null);
  console.log(`[syncHugRecipientLimits] parsed ${rows.length} rows`);
  const result = await applyToFirestore(rows, debug ? debugInfo : null);
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
