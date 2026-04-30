// HUG (hug-beesmiley.link) スクレイピング/フォーム送信の共通クライアント。
// セッション管理 (loginToHug)、Cookie/リダイレクト処理、Firestore 上の名前マッピング解決を提供する。

const fetch = require("node-fetch");
const cheerio = require("cheerio");

const { db, hugUsername, hugPassword } = require('./setup');

const HUG_BASE_URL = 'https://www.hug-beesmiley.link/hug/wm';

/**
 * Cookie文字列をヘッダー用に整形するヘルパー
 */
function parseCookies(setCookieHeaders) {
  if (!setCookieHeaders) return '';
  const headers = Array.isArray(setCookieHeaders) ? setCookieHeaders : [setCookieHeaders];
  return headers
    .map((h) => h.split(';')[0])
    .join('; ');
}

/**
 * fetch wrapper: Cookie付きリクエストを送る
 */
async function hugFetch(url, options = {}, cookies = '') {
  const optHeaders = options.headers || {};
  const headers = (typeof optHeaders.getHeaders === 'function')
    ? { ...optHeaders }
    : { ...optHeaders };
  if (cookies) {
    headers['Cookie'] = cookies;
  }
  return fetch(url, { ...options, headers, redirect: 'manual' });
}

/**
 * Cookieをマージするヘルパー
 */
function mergeCookies(existing, newCookies) {
  const cookieMap = {};
  [existing, newCookies].forEach((cs) => {
    if (!cs) return;
    cs.split('; ').forEach((c) => {
      const eqIdx = c.indexOf('=');
      if (eqIdx > 0) {
        const key = c.substring(0, eqIdx);
        cookieMap[key] = c;
      }
    });
  });
  return Object.values(cookieMap).join('; ');
}

/**
 * リダイレクトを手動で追従しながらcookieを確実に収集するヘルパー
 */
async function fetchWithCookies(url, options = {}, cookies = '', maxRedirects = 5) {
  let currentUrl = url;
  let currentCookies = cookies;

  for (let i = 0; i < maxRedirects; i++) {
    const headers = { ...(options.headers || {}) };
    if (currentCookies) headers['Cookie'] = currentCookies;

    const res = await fetch(currentUrl, { ...options, headers, redirect: 'manual' });
    currentCookies = mergeCookies(currentCookies, parseCookies(res.headers.raw()['set-cookie']));

    console.log(`fetchWithCookies[${i}]: ${options.method || 'GET'} ${currentUrl} → ${res.status}`);

    if (res.status === 301 || res.status === 302 || res.status === 303 || res.status === 307) {
      const location = res.headers.get('location');
      if (!location) break;
      currentUrl = location.startsWith('http')
        ? location
        : `https://www.hug-beesmiley.link${location.startsWith('/') ? '' : '/'}${location}`;
      console.log(`fetchWithCookies[${i}]: redirect → ${currentUrl}`);
      if (options.method === 'POST' && (res.status === 302 || res.status === 303)) {
        options = {};
      }
      continue;
    }

    return { res, cookies: currentCookies, html: await res.text() };
  }
  throw new Error('Too many redirects');
}

async function loginToHug() {
  const username = hugUsername.value();
  const password = hugPassword.value();
  const loginUrl = 'https://www.hug-beesmiley.link/hug/wm/';

  const getResult = await fetchWithCookies(loginUrl);
  let cookies = getResult.cookies;
  const $ = cheerio.load(getResult.html);

  console.log(`hug login page cookies: ${cookies ? 'obtained' : 'none'}`);

  const formData = {};
  $('form input[type="hidden"]').each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) formData[name] = value;
  });

  formData['username'] = username;
  formData['password'] = password;

  console.log(`hug form fields: ${Object.keys(formData).join(', ')}`);
  console.log(`hug csrf token: ${formData['csrf_token_from_client'] ? 'present' : 'missing'}`);

  const csrfToken = formData['csrf_token_from_client'] || '';
  const modeToken = formData['mode_token'] || 'nomode';
  const hugPageUrl = formData['hug_page_url'] || 'index.php';
  const tokenCheckUrl = `https://www.hug-beesmiley.link/hug/wm/ajax/ajax_token.php?token=${csrfToken}&mode=${modeToken}&hug_page_url=${hugPageUrl}`;
  const tokenCheckResult = await fetchWithCookies(tokenCheckUrl, {}, cookies);
  cookies = tokenCheckResult.cookies;
  console.log(`hug csrf token check result: ${tokenCheckResult.html.trim()}`);

  const postResult = await fetchWithCookies(loginUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(formData).toString(),
  }, cookies);

  cookies = postResult.cookies;
  const responseHtml = postResult.html;

  console.log(`hug login POST response status: ${postResult.res.status}`);
  console.log(`hug login POST cookies: ${cookies ? cookies.substring(0, 100) : 'none'}`);

  const $post = cheerio.load(responseHtml);
  const pageTitle = $post('title').text().trim();
  console.log(`hug login POST page title: ${pageTitle}`);
  const loginFormIdx = responseHtml.indexOf('loginForm');
  const bodyIdx = responseHtml.indexOf('<body');
  const relevantStart = loginFormIdx > 0 ? loginFormIdx - 200 : (bodyIdx > 0 ? bodyIdx : 0);
  console.log(`hug login POST html snippet: ${responseHtml.substring(relevantStart, relevantStart + 800).replace(/\s+/g, ' ')}`);

  if (responseHtml.includes('name="password"') && responseHtml.includes('ログインID')) {
    const errorMsg = $post('.error, .alert, .warning, #error').text().trim();
    console.error(`hug login failed. Error on page: ${errorMsg || 'none'}`);
    throw new Error(`hug login failed: ログインに失敗しました。ID/パスワードを確認してください。${errorMsg ? ' (' + errorMsg + ')' : ''}`);
  }

  console.log('hug login successful');
  return cookies;
}

/**
 * Firestoreのhugマッピング設定を取得
 */
async function getHugMappings() {
  const childDoc = await db.collection('hug_settings').doc('child_mapping').get();
  const staffDoc = await db.collection('hug_settings').doc('staff_mapping').get();

  return {
    childMapping: childDoc.exists ? childDoc.data() : {},
    staffMapping: staffDoc.exists ? staffDoc.data() : {},
  };
}

/**
 * スペース（半角・全角）を除去して名前を正規化
 */
function normalizeName(name) {
  return (name || '').replace(/[\s　]/g, '');
}

/**
 * マッピングからスペースを無視して検索
 */
function findMapping(mapping, name) {
  if (mapping[name] !== undefined) return mapping[name];
  const normalized = normalizeName(name);
  for (const [key, value] of Object.entries(mapping)) {
    if (normalizeName(key) === normalized) return value;
  }
  return undefined;
}

module.exports = {
  HUG_BASE_URL,
  parseCookies,
  hugFetch,
  mergeCookies,
  fetchWithCookies,
  loginToHug,
  getHugMappings,
  normalizeName,
  findMapping,
};
