// HUG 新規保護者・児童登録フォームの構造を取得する診断用 Cloud Function。
//
// 目的:
//   1. profile_parent.php / profile_children.php の編集画面 HTML を解析し、
//      全 input/select/textarea の name・type・初期値・select 選択肢一覧を抽出。
//   2. 取得した hidden フィールドをそのまま echo back する形でダミーデータを
//      POST し、HUG にステージング登録できるかを検証。
//
// 一回し用なので、本実装の `hugRegisterFamily` が完成したら削除する。
//
// 認証: body の magic フィールドが一致した時のみ実行。

const cheerio = require('cheerio');
const { onRequest } = require('firebase-functions/v2/https');
const { hugUsername, hugPassword } = require('../utils/setup');
const {
  HUG_BASE_URL,
  hugFetch,
  loginToHug,
} = require('../utils/hug-client');

// 一時的なアクセス制御用マジック文字列。デプロイ後にこの値で curl 叩く。
// 調査完了次第ファイル削除＋デプロイで失効させる。
const INSPECT_MAGIC = 'hug-inspect-2026-05-21-bee';

/**
 * フォーム HTML から全フィールドを構造化抽出。
 */
function parseForm(html) {
  const $ = cheerio.load(html);
  const fields = [];

  $('form input').each((_, el) => {
    const $el = $(el);
    fields.push({
      tag: 'input',
      type: $el.attr('type') || 'text',
      name: $el.attr('name') || null,
      value: $el.attr('value') || '',
      placeholder: $el.attr('placeholder') || null,
      required: $el.attr('required') !== undefined,
      maxlength: $el.attr('maxlength') || null,
      checked: $el.attr('checked') !== undefined,
    });
  });

  $('form select').each((_, el) => {
    const $el = $(el);
    const opts = [];
    $el.find('option').each((__, op) => {
      opts.push({
        value: $(op).attr('value') || '',
        label: $(op).text().trim(),
        selected: $(op).attr('selected') !== undefined,
      });
    });
    fields.push({
      tag: 'select',
      name: $el.attr('name') || null,
      required: $el.attr('required') !== undefined,
      options: opts,
    });
  });

  $('form textarea').each((_, el) => {
    const $el = $(el);
    fields.push({
      tag: 'textarea',
      name: $el.attr('name') || null,
      value: $el.text() || '',
      placeholder: $el.attr('placeholder') || null,
      required: $el.attr('required') !== undefined,
    });
  });

  // ラベル文言（フォーム項目との対応把握用）
  const labels = [];
  $('label').each((_, el) => {
    const $el = $(el);
    labels.push({
      forName: $el.attr('for') || null,
      text: $el.text().trim().replace(/\s+/g, ' '),
    });
  });

  const $form = $('form').first();
  // フォーム周辺の表構造（HUGは <table> ベースのレイアウトなので、ラベル↔input の対応を <tr> で取得）
  const tableRows = [];
  $('form tr').each((_, tr) => {
    const $tr = $(tr);
    const labelTxt = $tr.find('th, td').first().text().trim().replace(/\s+/g, ' ');
    const inputs = [];
    $tr.find('input, select, textarea').each((__, inp) => {
      const $inp = $(inp);
      inputs.push({
        tag: inp.tagName || $inp.prop('tagName'),
        type: $inp.attr('type') || null,
        name: $inp.attr('name') || null,
      });
    });
    if (labelTxt || inputs.length) {
      tableRows.push({ label: labelTxt.slice(0, 60), inputs });
    }
  });

  return {
    formAction: $form.attr('action') || null,
    formMethod: $form.attr('method') || 'get',
    fieldCount: fields.length,
    fields,
    labels: labels.slice(0, 200),
    tableRows: tableRows.slice(0, 200),
  };
}

// 都道府県の名前 → HUG select value (1-47) マッピング
const PREF_TO_ID = {
  '北海道': '1', '青森県': '2', '秋田県': '3', '岩手県': '4', '宮城県': '5',
  '山形県': '6', '福島県': '7', '栃木県': '8', '新潟県': '9', '群馬県': '10',
  '埼玉県': '11', '茨城県': '12', '千葉県': '13', '東京都': '14', '神奈川県': '15',
  '山梨県': '16', '長野県': '17', '岐阜県': '18', '富山県': '19', '石川県': '20',
  '静岡県': '21', '愛知県': '22', '三重県': '23', '奈良県': '24', '和歌山県': '25',
  '福井県': '26', '滋賀県': '27', '京都府': '28', '大阪府': '29', '兵庫県': '30',
  '岡山県': '31', '鳥取県': '32', '島根県': '33', '広島県': '34', '山口県': '35',
  '香川県': '36', '徳島県': '37', '愛媛県': '38', '高知県': '39', '福岡県': '40',
  '佐賀県': '41', '大分県': '42', '熊本県': '43', '宮崎県': '44', '長崎県': '45',
  '鹿児島県': '46', '沖縄県': '47',
};

/**
 * テスト保護者登録（ダミーデータでPOSTしHUGにステージング登録）
 *
 * 流れ:
 *   1. profile_parent.php?mode=edit を GET → 全 hidden を取得
 *   2. CRM 由来のダミーデータと hidden をマージ → POST
 *   3. HUG のレスポンスから新規保護者IDを抽出
 *   4. 結果を JSON で返却
 *
 * ダミーデータは「★HUG連携テスト★」プレフィックス付きで識別可能。
 * 実行後 HUG 画面でレコードを確認し、不要なら削除する。
 */
exports.hugTestRegisterParent = onRequest(
  {
    region: 'asia-northeast1',
    secrets: [hugUsername, hugPassword],
    timeoutSeconds: 120,
    memory: '512MiB',
    cors: false,
  },
  async (req, res) => {
    try {
      const body = req.body || {};
      if (body.magic !== INSPECT_MAGIC) {
        res.status(403).json({ error: 'forbidden' });
        return;
      }

      const cookies = await loginToHug();
      console.log('[hugTestRegisterParent] logged in');

      // GET フォーム → hidden 取得
      const formUrl = `${HUG_BASE_URL}/profile_parent.php?mode=edit`;
      const getRes = await hugFetch(formUrl, {}, cookies);
      const html = await getRes.text();
      const $ = cheerio.load(html);

      const hidden = {};
      $('form input[type="hidden"]').each((_, el) => {
        const name = $(el).attr('name');
        const value = $(el).attr('value') || '';
        if (name) hidden[name] = value;
      });
      console.log('[hugTestRegisterParent] hidden fields:', JSON.stringify(hidden));

      // ダミーデータ
      const formData = {
        ...hidden,
        realname: '★HUG連携テスト★保護者ダミー',
        furigana: 'てすとだみー',
        postal: '251-0042',
        pref: PREF_TO_ID['神奈川県'],
        address1: '藤沢市辻堂東海岸1-2-3',
        tel: '09099990000',
        relationship: '父',
        help_tel1: '',
        help_contact1: '',
        help_tel2: '',
        help_contact2: '',
        help_note: '',
        bank_name: '',
        bank_name_kana: '',
        bank_branch_name_kana: '',
        bank_num: '',
        bank_branch_num: '',
        deposit_type: '0',
        type_account_num: '',
        holder_name: '',
        client_code: '',
        email: 'hug-test-dummy@example.com',
        cc_email: '',
        login_id: '',
        password: '',
        note: '★ HUG連携テスト用ダミー ★ スタッフは確認後削除してください。',
      };
      console.log('[hugTestRegisterParent] POST data keys:', Object.keys(formData).join(','));

      // POST
      const postUrl = `${HUG_BASE_URL}/profile_parent.php?mode=detail&id=insert`;
      const postRes = await hugFetch(postUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(formData).toString(),
      }, cookies);
      const postHtml = await postRes.text();
      const $$ = cheerio.load(postHtml);
      const pageTitle = $$('title').text().trim();
      const errorMsgs = [];
      $$('.error, .alert, .warning, .alert-danger').each((_, el) => {
        const t = $$(el).text().trim().replace(/\s+/g, ' ');
        if (t) errorMsgs.push(t);
      });

      // 新規保護者IDを抽出する手がかり:
      // 1. レスポンス URL（リダイレクト先）に id= が入る
      // 2. または HTML 内の hidden input id に新しい数値が入っている
      const responseUrl = postRes.url || '';
      const idFromUrl = (responseUrl.match(/id=(\d+)/) || [])[1];
      const idFromHidden = $$('form input[name="id"]').attr('value') || '';

      console.log('[hugTestRegisterParent] response status:', postRes.status);
      console.log('[hugTestRegisterParent] response URL:', responseUrl);
      console.log('[hugTestRegisterParent] page title:', pageTitle);
      console.log('[hugTestRegisterParent] errors:', JSON.stringify(errorMsgs));
      console.log('[hugTestRegisterParent] idFromUrl:', idFromUrl);
      console.log('[hugTestRegisterParent] idFromHidden:', idFromHidden);

      // body 内のテキストを抽出（成功メッセージ判定用）。
      $$('script, style, link, meta').remove();
      const bodyText = $$('body').text().replace(/\s+/g, ' ').trim();
      const echoedRealname = $$('input[name="realname"]').attr('value') || '';
      const success = bodyText.includes('登録が完了しました');

      // 成功時、続けて児童登録リンクに parent_id が入っているはず。
      // 全ての a[href] / button[onclick] を集めて id 系パラメータを抽出。
      const linkCandidates = [];
      $$('a[href], button[onclick]').each((_, el) => {
        const href = $$(el).attr('href') || $$(el).attr('onclick') || '';
        const text = $$(el).text().trim().replace(/\s+/g, ' ').slice(0, 60);
        if (href && /id=\d+|parent_id=\d+|parent=\d+/i.test(href)) {
          linkCandidates.push({ href, text });
        }
      });

      // 保護者一覧ページを取得し、最新登録 (realname 一致) の id を見つける
      let foundParentId = null;
      if (success) {
        try {
          // HUG の保護者一覧ページを試す（複数候補のうちあるものをヒット）
          for (const listPath of ['parents.php', 'parent_list.php']) {
            const listUrl = `${HUG_BASE_URL}/${listPath}`;
            const listRes = await hugFetch(listUrl, {}, cookies);
            if (!listRes.ok) continue;
            const listHtml = await listRes.text();
            const $$$ = cheerio.load(listHtml);
            // ★HUG連携テスト★ プレフィックスを含む行から profile_parent.php?id=XX を探す
            $$$('a[href*="profile_parent.php"]').each((_, a) => {
              const href = $$$(a).attr('href') || '';
              const row = $$$(a).closest('tr');
              const rowText = row.text();
              if (rowText.includes('★HUG連携テスト★')) {
                const m = href.match(/id=(\d+)/);
                if (m) foundParentId = m[1];
              }
            });
            if (foundParentId) break;
          }
        } catch (e) {
          console.warn('[hugTestRegisterParent] list scan failed:', e.message);
        }
      }

      res.json({
        status: postRes.status,
        responseUrl,
        pageTitle,
        success,
        echoedRealname,
        foundParentId,
        linkCandidates: linkCandidates.slice(0, 30),
        errors: errorMsgs,
        bodyTextSnippet: bodyText.substring(0, 3000),
      });
    } catch (err) {
      console.error('[hugTestRegisterParent] error:', err);
      res.status(500).json({ error: err.message, stack: err.stack });
    }
  }
);

/**
 * テスト児童登録（既存ダミー保護者IDに紐付け）
 */
exports.hugTestRegisterChild = onRequest(
  {
    region: 'asia-northeast1',
    secrets: [hugUsername, hugPassword],
    timeoutSeconds: 120,
    memory: '512MiB',
    cors: false,
  },
  async (req, res) => {
    try {
      const body = req.body || {};
      if (body.magic !== INSPECT_MAGIC) {
        res.status(403).json({ error: 'forbidden' });
        return;
      }
      const parentId = String(body.parentId || '');
      if (!parentId.match(/^\d+$/)) {
        res.status(400).json({ error: 'parentId(数字) を body に含めてください' });
        return;
      }

      const cookies = await loginToHug();

      // GET 児童登録フォーム（p_id 付き = 保護者紐付け）
      const formUrl = `${HUG_BASE_URL}/profile_children.php?mode=edit&p_id=${parentId}`;
      const getRes = await hugFetch(formUrl, {}, cookies);
      const html = await getRes.text();
      const $ = cheerio.load(html);

      // 全フィールドのデフォルト値を取得（hidden + text + select デフォルト + textarea）
      const baseData = {};
      $('form input').each((_, el) => {
        const $el = $(el);
        const name = $el.attr('name');
        const type = $el.attr('type');
        if (!name) return;
        if (type === 'radio') {
          // 選択中のラジオのみ
          if ($el.attr('checked') !== undefined) {
            baseData[name] = $el.attr('value') || '';
          } else if (baseData[name] === undefined) {
            baseData[name] = ''; // 未選択はとりあえず空
          }
        } else if (type === 'checkbox') {
          if ($el.attr('checked') !== undefined) {
            baseData[name] = $el.attr('value') || '1';
          }
          // チェック無しは POST に含めない（HTMLの仕様通り）
        } else if (type !== 'file' && type !== 'button' && type !== 'submit') {
          baseData[name] = $el.attr('value') || '';
        }
      });
      $('form select').each((_, el) => {
        const $el = $(el);
        const name = $el.attr('name');
        if (!name || name === '-') return;
        const sel = $el.find('option[selected]').attr('value');
        baseData[name] = sel !== undefined ? sel : '';
      });
      $('form textarea').each((_, el) => {
        const $el = $(el);
        const name = $el.attr('name');
        if (!name) return;
        baseData[name] = $el.text() || '';
      });
      console.log('[hugTestRegisterChild] base field count:', Object.keys(baseData).length);

      // 最小限の児童データ（fault_flg=0 で受給者証関連を省略）
      // 全ラジオボタンに既定値を設定（未選択だとサーバー側でエラーになる可能性）
      const formData = {
        ...baseData,
        realname: '★HUG連携テスト★児童ダミー',
        furigana: 'てすとだみー',
        sex: '1',
        birth_y: '2020',
        birth_m: '4',
        birth_d: '1',
        parent: parentId,
        fault_flg: '0',
        round_type: '1',
        manage_facility_type: '0',
        upper_limit_setting: '0',
      };
      // 空文字の日付テキストフィールドを POST から除外（HUG 側のバリデーション回避）
      const dateFields = ['acceptance_date', 'payment_start', 'payment_end',
        'hoiku_payment_start', 'hoiku_payment_end', 'provide_start', 'provide_end',
        'supply_start', 'supply_end', 'free_of_charge_start', 'free_of_charge_end',
        'school_history[0][start_date]', 'school_history[0][end_date]',
        'medical_care_score', 'strength_action_score', 'original_money',
        'koube_money', 'grant_ratio', 'fault_no'];
      for (const k of dateFields) {
        if (formData[k] === '') delete formData[k];
      }
      console.log('[hugTestRegisterChild] POST keys:', Object.keys(formData).join(','));

      const postUrl = `${HUG_BASE_URL}/profile_children.php?mode=detail&id=insert`;
      const postRes = await hugFetch(postUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(formData).toString(),
      }, cookies);
      const postHtml = await postRes.text();
      const $$ = cheerio.load(postHtml);
      $$('script, style, link, meta').remove();
      const bodyText = $$('body').text().replace(/\s+/g, ' ').trim();
      const success = bodyText.includes('登録が完了しました');
      const echoedRealname = $$('input[name="realname"]').attr('value') || '';

      const linkCandidates = [];
      $$('a[href], button[onclick]').each((_, el) => {
        const href = $$(el).attr('href') || $$(el).attr('onclick') || '';
        const text = $$(el).text().trim().replace(/\s+/g, ' ').slice(0, 60);
        if (href && /id=\d+|c_id=\d+|child_id=\d+/i.test(href)) {
          linkCandidates.push({ href, text });
        }
      });

      res.json({
        status: postRes.status,
        responseUrl: postRes.url || '',
        success,
        echoedRealname,
        linkCandidates: linkCandidates.slice(0, 30),
        bodyTextSnippet: bodyText.substring(0, 2500),
      });
    } catch (err) {
      console.error('[hugTestRegisterChild] error:', err);
      res.status(500).json({ error: err.message, stack: err.stack });
    }
  }
);

exports.hugInspectForms = onRequest(
  {
    region: 'asia-northeast1',
    secrets: [hugUsername, hugPassword],
    timeoutSeconds: 120,
    memory: '512MiB',
    cors: false,
  },
  async (req, res) => {
    try {
      const body = req.body || {};
      if (body.magic !== INSPECT_MAGIC) {
        res.status(403).json({ error: 'forbidden' });
        return;
      }

      const cookies = await loginToHug();
      console.log('[hugInspectForms] logged in to HUG');

      // 保護者新規登録ページ
      const parentUrl = `${HUG_BASE_URL}/profile_parent.php?mode=edit`;
      const parentRes = await hugFetch(parentUrl, {}, cookies);
      const parentHtml = await parentRes.text();
      const parentForm = parseForm(parentHtml);
      console.log(
        `[hugInspectForms] parent: ${parentForm.fieldCount} fields, action=${parentForm.formAction}`
      );
      const parentFieldNames = parentForm.fields
        .map((f) => `${f.tag}[${f.type || ''}] ${f.name}`)
        .join(', ');
      console.log(`[hugInspectForms] parent FIELDS: ${parentFieldNames}`);

      // 児童新規登録ページ
      const childUrl = `${HUG_BASE_URL}/profile_children.php?mode=edit`;
      const childRes = await hugFetch(childUrl, {}, cookies);
      const childHtml = await childRes.text();
      const childForm = parseForm(childHtml);
      console.log(
        `[hugInspectForms] child: ${childForm.fieldCount} fields, action=${childForm.formAction}`
      );
      const childFieldNames = childForm.fields
        .map((f) => `${f.tag}[${f.type || ''}] ${f.name}`)
        .join(', ');
      console.log(`[hugInspectForms] child FIELDS: ${childFieldNames}`);

      res.json({
        parent: parentForm,
        child: childForm,
      });
    } catch (err) {
      console.error('[hugInspectForms] error:', err);
      res.status(500).json({ error: err.message, stack: err.stack });
    }
  }
);
