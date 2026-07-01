// HUG 保護者・児童プロフィール自動登録 Cloud Function。
//
// 入会完了時にクライアントから呼び出され、CRM の plus_families データを
// HUG の profile_parent.php / profile_children.php に POST して新規エントリを作る。
//
// 流れ:
//   1. plus_families.{familyId}.children[childIndex] を読み込み
//   2. profile_parent.php?mode=edit を GET → hidden + CSRF 取得
//   3. CRM データを保護者フォーム名にマッピングして POST → 新規 p_id 取得
//   4. profile_children.php?mode=edit&p_id={p_id} を GET → hidden + CSRF 取得
//   5. CRM データを児童フォーム名にマッピングして multipart で POST → 新規 c_id 取得
//   6. 結果を plus_families.{familyId}.{hugParentId / children[i].hugChildId} に保存
//
// 認証: 認証済みスタッフのみ呼び出し可。
// エラー: 段階別に詳細メッセージ。リトライ時は既存 hugParentId があれば保護者登録をスキップ。

const cheerio = require('cheerio');
const FormData = require('form-data');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const { db, hugUsername, hugPassword } = require('../utils/setup');
const {
  HUG_BASE_URL,
  hugFetch,
  loginToHug,
} = require('../utils/hug-client');

// ──────────────── マッピングテーブル ────────────────

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

const DEPOSIT_TYPE_TO_ID = {
  '普通': '1', '当座': '2', '納税準備': '3', '貯蓄': '4', 'その他': '5',
};

const USE_SERVICES_TO_ID = {
  '放課後等デイサービス': '1',
  '児童発達支援': '2',
  '保育所等訪問支援': '3',
};

const FAILURE_TYPE_TO_ID = {
  '障害児': '1',
  '重症心身障害児': '2',
  '指標該当児': '1', // 障害児扱い (HUG select に独立選択肢なし)
};

const SEX_TO_ID = {
  '男': '1', '男性': '1',
  '女': '2', '女性': '2',
};

// ──────────────── ヘルパー ────────────────

function formatDate(d) {
  if (!d) return '';
  const date = d.toDate ? d.toDate() : new Date(d);
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${y}/${m}/${day}`;
}

function parseHidden($, formSelector = 'form') {
  const out = {};
  $(`${formSelector} input[type="hidden"]`).each((_, el) => {
    const name = $(el).attr('name');
    const value = $(el).attr('value') || '';
    if (name) out[name] = value;
  });
  return out;
}

/**
 * 全フィールドのデフォルト値を GET レスポンスから抽出。
 * 児童フォームは fault_flg=1 で送る前提で受給者証関連も初期化される。
 */
function extractAllDefaults($, formSelector = 'form') {
  const data = {};
  $(`${formSelector} input`).each((_, el) => {
    const $el = $(el);
    const name = $el.attr('name');
    const type = $el.attr('type');
    if (!name) return;
    if (type === 'radio') {
      if ($el.attr('checked') !== undefined) {
        data[name] = $el.attr('value') || '';
      } else if (data[name] === undefined) {
        data[name] = '';
      }
    } else if (type === 'checkbox') {
      if ($el.attr('checked') !== undefined) {
        data[name] = $el.attr('value') || '1';
      }
    } else if (type !== 'file' && type !== 'button' && type !== 'submit') {
      data[name] = $el.attr('value') || '';
    }
  });
  $(`${formSelector} select`).each((_, el) => {
    const $el = $(el);
    const name = $el.attr('name');
    if (!name || name === '-') return;
    const sel = $el.find('option[selected]').attr('value');
    data[name] = sel !== undefined ? sel : '';
  });
  $(`${formSelector} textarea`).each((_, el) => {
    const $el = $(el);
    const name = $el.attr('name');
    if (!name) return;
    data[name] = $el.text() || '';
  });
  return data;
}

// ──────────────── 保護者登録 ────────────────

async function registerParent(cookies, family, nameOverride) {
  const getUrl = `${HUG_BASE_URL}/profile_parent.php?mode=edit`;
  const getRes = await hugFetch(getUrl, {}, cookies);
  const getHtml = await getRes.text();
  const $ = cheerio.load(getHtml);
  const hidden = parseHidden($);

  const parentLastName = family.lastName || '';
  const parentFirstName = family.firstName || '';
  // nameOverride（通所給付決定保護者名）があれば実績記録票の表記に合わせて優先。
  const realname = (nameOverride && nameOverride.realname)
    ? nameOverride.realname
    : (`${parentLastName} ${parentFirstName}`.trim() || parentLastName || parentFirstName);
  const furigana = (nameOverride && nameOverride.furigana)
    ? nameOverride.furigana
    : `${family.lastNameKana || ''} ${family.firstNameKana || ''}`.trim();

  const formData = {
    ...hidden,
    realname,
    furigana,
    postal: family.postalCode || '',
    pref: PREF_TO_ID[family.prefecture] || '',
    address1: `${family.city || ''}${family.addressDetail || ''}`,
    tel: family.phone || '',
    relationship: family.parentRelation || '',
    help_tel1: family.emergencyContacts?.[0]?.phone || '',
    help_contact1: family.emergencyContacts?.[0]?.name || '',
    help_tel2: family.emergencyContacts?.[1]?.phone || '',
    help_contact2: family.emergencyContacts?.[1]?.name || '',
    help_note: family.emergencyMemo || '',
    bank_name: [family.bankInfo?.bankName, family.bankInfo?.branchName]
      .filter(Boolean).join(' '),
    bank_name_kana: family.bankInfo?.bankNameKana || '',
    bank_branch_name_kana: family.bankInfo?.branchNameKana || '',
    bank_num: family.bankInfo?.bankCode || '',
    bank_branch_num: family.bankInfo?.branchCode || '',
    deposit_type: DEPOSIT_TYPE_TO_ID[family.bankInfo?.accountType] || '0',
    type_account_num: family.bankInfo?.accountNumber || '',
    holder_name: family.bankInfo?.holderName || realname,
    client_code: '',
    email: family.email || '',
    cc_email: '',
    login_id: '',
    password: '',
    note: '',
  };

  const postRes = await hugFetch(`${HUG_BASE_URL}/profile_parent.php?mode=detail&id=insert`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': getUrl,
    },
    body: new URLSearchParams(formData).toString(),
  }, cookies);
  const postHtml = await postRes.text();
  const $p = cheerio.load(postHtml);
  $p('script, style, link, meta').remove();
  const bodyText = $p('body').text();
  const success = bodyText.includes('登録が完了しました');
  if (!success) {
    const errors = [];
    $p('[class*="error"]').each((_, el) => {
      const t = $p(el).text().trim().replace(/\s+/g, ' ');
      if (t && t.length < 300) errors.push(t);
    });
    throw new Error(`保護者登録失敗: ${errors.join(' / ') || '不明なエラー'}`);
  }

  // 「続けて児童登録を行う」リンクから新規 p_id を抽出
  let newPid = null;
  $p('a[href], button[onclick]').each((_, el) => {
    const ref = $p(el).attr('href') || $p(el).attr('onclick') || '';
    const m = ref.match(/profile_children\.php[^"']*?[?&]p_id=(\d+)/);
    if (m && !newPid) newPid = m[1];
  });
  if (!newPid) {
    throw new Error('保護者登録は完了したが新規 p_id を取得できませんでした');
  }
  return newPid;
}

// ──────────────── 児童登録 ────────────────

async function registerChild(cookies, hugParentId, child, family) {
  const getUrl = `${HUG_BASE_URL}/profile_children.php?mode=edit&p_id=${hugParentId}`;
  const getRes = await hugFetch(getUrl, {}, cookies);
  const getHtml = await getRes.text();
  const $ = cheerio.load(getHtml);
  const baseData = extractAllDefaults($);

  const childLastName = child.lastName || '';
  const childFirstName = child.firstName || '';
  const realname = `${childLastName} ${childFirstName}`.trim() || childLastName || childFirstName;
  const furigana = `${child.lastNameKana || ''} ${child.firstNameKana || ''}`.trim();

  // 生年月日
  const birthDate = child.birthDate?.toDate
    ? child.birthDate.toDate()
    : (child.birthDate ? new Date(child.birthDate) : null);
  const birth_y = birthDate ? String(birthDate.getFullYear()) : '';
  const birth_m = birthDate ? String(birthDate.getMonth() + 1) : '';
  const birth_d = birthDate ? String(birthDate.getDate()) : '';

  const cert = child.recipientCert || {};

  const formData = {
    ...baseData,
    p_id: hugParentId,
    realname,
    furigana,
    sex: SEX_TO_ID[child.gender] || '1',
    birth_y, birth_m, birth_d,
    parent: hugParentId,

    // 受給者証は permitStatus='have' 前提でロックされている → fault_flg=1 固定
    fault_flg: '1',
    acceptance_date: formatDate(cert.startDate),
    fault_no: cert.certificateNumber || '',

    // 支給市町村は HUG マスタ依存。CRM の文字列とは ID マッピングが要るが、
    // 現状マスタが固定的に登録できないため空で送る（HUG側でスタッフが補完）。
    city_id: '',

    use_services: USE_SERVICES_TO_ID[cert.service] || '1',
    failure_type: FAILURE_TYPE_TO_ID[cert.disabilityType] || '1',

    // 受給者証関連の select 既定値（観察済の sentinel）
    medical_score_kubun: baseData.medical_score_kubun || '1',
    meal_offer_adding: baseData.meal_offer_adding || '0',
    supply_amount1: baseData.supply_amount1 || '0',
    supply_amount2: baseData.supply_amount2 || '-99',
    hoiku_supply_amount1: baseData.hoiku_supply_amount1 || '0',
    hoiku_supply_amount2: baseData.hoiku_supply_amount2 || '-99',

    // ラジオ既定値（未指定だとサーバー側で弾かれる）
    round_type: '1',
    manage_facility_type: '0',
    upper_limit_setting: '0',

    // 期間（給付決定期間）
    period_flg: cert.periodStart || cert.periodEnd ? '1' : '',
    payment_start: formatDate(cert.periodStart),
    payment_end: formatDate(cert.periodEnd),

    // アレルギーは CRM 未収集 → デフォルトで「無し」扱い
    none_allergy: '1',
  };

  // 受給者証加算系チェックボックス
  if (cert.specialSupport) formData.special_support_add = '1';
  if (cert.cochlearImplant) formData.cochlea_implant_flg = '1';
  if (cert.severeDisability) formData.strength_action_flg = '1';

  // 受給者証番号は HUG が 10桁半角数字を要求するためバリデーション
  if (!/^\d{10}$/.test(formData.fault_no)) {
    throw new Error('受給者証番号は半角数字10桁で入力してください');
  }
  if (!formData.acceptance_date) {
    throw new Error('受給者証の利用開始日が未設定です');
  }

  // multipart/form-data で POST（ブラウザ準拠）
  const fd = new FormData();
  for (const [k, v] of Object.entries(formData)) {
    fd.append(k, v == null ? '' : String(v));
  }
  const postRes = await hugFetch(`${HUG_BASE_URL}/profile_children.php?mode=detail&id=insert`, {
    method: 'POST',
    headers: {
      ...fd.getHeaders(),
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': getUrl,
    },
    body: fd,
  }, cookies);

  const postHtml = await postRes.text();
  const $c = cheerio.load(postHtml);
  $c('script, style, link, meta').remove();
  const bodyText = $c('body').text();
  const success = bodyText.includes('登録が完了しました');
  if (!success) {
    const errors = [];
    $c('[class*="error"]').each((_, el) => {
      const t = $c(el).text().trim().replace(/\s+/g, ' ');
      if (t && t.length < 300) errors.push(t);
    });
    throw new Error(`児童登録失敗: ${errors.join(' / ') || '不明なエラー'}`);
  }

  // 登録完了ページから「契約支給量を登録」リンク等の c_id を抽出
  let newCid = null;
  $c('a[href], button[onclick]').each((_, el) => {
    const ref = $c(el).attr('href') || $c(el).attr('onclick') || '';
    const m = ref.match(/[?&](c_id|id)=(\d+)/);
    if (m && !newCid && m[2] !== hugParentId) newCid = m[2];
  });
  return newCid; // 取れなくても登録自体は成功
}

// ──────────────── 公開関数 ────────────────

exports.hugRegisterFamily = onCall(
  {
    region: 'asia-northeast1',
    secrets: [hugUsername, hugPassword],
    timeoutSeconds: 180,
    memory: '512MiB',
  },
  async (request) => {
   try {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', '認証が必要です');
    }
    const { familyId, childIndex } = request.data || {};
    if (typeof familyId !== 'string' || !familyId) {
      throw new HttpsError('invalid-argument', 'familyId が必要です');
    }
    const ci = Number(childIndex);
    if (!Number.isInteger(ci) || ci < 0) {
      throw new HttpsError('invalid-argument', 'childIndex が不正です');
    }

    const famRef = db.collection('plus_families').doc(familyId);
    const famSnap = await famRef.get();
    if (!famSnap.exists) {
      throw new HttpsError('not-found', `家族が見つかりません: ${familyId}`);
    }
    const family = famSnap.data();
    const children = Array.isArray(family.children) ? family.children : [];
    if (ci >= children.length) {
      throw new HttpsError('not-found', `児童インデックス ${ci} が範囲外`);
    }
    const child = children[ci];
    if (child.hugChildId) {
      throw new HttpsError(
        'already-exists',
        `この児童は既に HUG 登録済みです (hugChildId=${child.hugChildId})`
      );
    }

    // 受給者証なし児童の「仮登録」: 架空の受給者証番号で fault_flg=1 のまま登録する。
    // 実績記録票を出すための運用。保護者名は実績の表記に合わせ payerName を優先。
    const provisional = (request.data && request.data.provisional) || null;
    const cert0 = child.recipientCert || {};
    let childForReg = child;
    let nameOverride = null;
    if (provisional) {
      if (!/^\d{10}$/.test(String(provisional.certNumber || ''))) {
        throw new HttpsError('invalid-argument', '架空の受給者証番号は半角数字10桁で指定してください');
      }
      if (!provisional.acceptanceDate) {
        throw new HttpsError('invalid-argument', '利用開始日が必要です');
      }
      if (cert0.payerName) {
        nameOverride = { realname: cert0.payerName, furigana: cert0.payerNameKana || '' };
      }
      childForReg = {
        ...child,
        recipientCert: {
          ...cert0,
          certificateNumber: String(provisional.certNumber),
          startDate: provisional.acceptanceDate, // 'YYYY/MM/DD' 文字列（formatDate が処理）
          service: provisional.service || cert0.service || '',
          monthlyDays: provisional.monthlyDays != null
            ? provisional.monthlyDays
            : cert0.monthlyDays,
        },
      };
    }

    console.log(`[hugRegisterFamily] start uid=${request.auth.uid} family=${familyId} child=${ci} provisional=${!!provisional}`);
    const cookies = await loginToHug();

    // 既存 hugParentId があれば保護者登録をスキップ（リトライ時の重複防止）
    let hugParentId = family.hugParentId || null;
    if (!hugParentId) {
      hugParentId = await registerParent(cookies, family, nameOverride);
      console.log(`[hugRegisterFamily] parent registered: p_id=${hugParentId}`);
      await famRef.update({
        hugParentId,
        hugParentRegisteredAt: FieldValue.serverTimestamp(),
      });
    } else {
      console.log(`[hugRegisterFamily] reusing existing hugParentId=${hugParentId}`);
    }

    let hugChildId;
    try {
      hugChildId = await registerChild(cookies, hugParentId, childForReg, family);
    } catch (err) {
      console.error('[hugRegisterFamily] child register failed:', err);
      throw new HttpsError('internal', err.message);
    }
    console.log(`[hugRegisterFamily] child registered: c_id=${hugChildId || '(unknown)'}`);

    // children[ci].hugChildId に書き戻し
    const newChildren = [...children];
    newChildren[ci] = {
      ...child,
      hugChildId: hugChildId || '',
      hugRegisteredAt: Timestamp.now(),
      // 仮登録（架空番号）の場合はフラグを立て、受給者証到着後の正式更新を促す。
      hugProvisional: provisional ? true : (child.hugProvisional || false),
    };
    await famRef.update({ children: newChildren });

    // hug_settings/child_mapping にも追加（既存連携との互換性）
    if (hugChildId) {
      const childName = `${child.lastName || ''} ${child.firstName || ''}`.trim();
      if (childName) {
        await db.collection('hug_settings').doc('child_mapping')
          .set({ [childName]: hugChildId }, { merge: true });
      }
    }

    return {
      hugParentId,
      hugChildId: hugChildId || null,
    };
   } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error('[hugRegisterFamily] fatal:',
      err && err.stack ? err.stack : err);
    throw new HttpsError('internal',
      `HUG登録に失敗しました: ${err && err.message ? err.message : String(err)}`);
   }
  }
);
