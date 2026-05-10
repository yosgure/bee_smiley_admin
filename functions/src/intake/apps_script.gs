/**
 * 体験アンケート Google フォーム → Cloud Function 自動送信スクリプト。
 *
 * このコードは Google フォーム（または紐付くスプレッドシート）の Apps Script に
 * コピペし、トリガー「フォーム送信時 → onFormSubmit」を設定して使う。
 *
 * 事前設定:
 *   1. プロジェクトの設定 → スクリプトプロパティに以下を追加
 *      - INTAKE_URL    : Cloud Function の URL（デプロイ後に表示される URL）
 *                        例: https://asia-northeast1-bee-smiley-admin.cloudfunctions.net/intakeForm
 *      - INTAKE_SECRET : functions/utils/setup.js の INTAKE_FORM_SECRET と同じ値
 *
 *   2. トリガー設定（時計アイコン）
 *      - イベントのソース: フォームから
 *      - イベントの種類:   フォーム送信時
 *      - 実行する関数:     onFormSubmit
 *
 * フォームの設問名を変更した場合は、本ファイルの QUESTION_KEYS を合わせて更新すること。
 */

// 設問名 → ペイロードキー のマッピング。
// フォームの設問名を変えたらここを更新する必要がある。
const QUESTION_KEYS = {
  parentName:        '保護者様のお名前',
  parentNameKana:    '保護者様のお名前（ふりがな）',
  childName:         'お子さまのお名前',
  childNameKana:     'お子さまのお名前（ふりがな）',
  childBirthDate:    'お子さまの誕生日',
  childGender:       'お子様の性別',
  address:           'ご住所（郵便番号からお願いいたします）',
  email:             'メールアドレス',
  phone:             '電話番号',
  permitStatus:      '受給者証の有無',
  diagnosis:         '診断名',
  kindergarten:      '（お通いの場合）幼稚園/保育園名',
  grade:             '（お通いの場合）学年',
  mainConcern:       '体験に行ってみようと思った理由があればお知らせください。（お困りごと、不安なことなど）',
  likes:             'お子さまの好きなこと、得意なことをお知らせください。',
  dislikes:          'お子さまの嫌いなこと、苦手なことをお知らせください。',
  medicalHistory:    '既往歴はありますか？※ある場合はできるだけ詳しくお知らせください。',
  trialAttendee:     '体験当日の来所予定の方',
  source:            'どこからビースマイリーをお知りになりましたお知りになりましたか？',
  memo:              'その他お伝えしたいことがあればご記載ください。',
};

/**
 * フォーム送信時に呼ばれるエントリーポイント。
 * トリガー「フォーム送信時」をこの関数に紐付けること。
 */
function onFormSubmit(e) {
  try {
    const payload = buildPayload(e);
    const result = postToCloudFunction(payload);
    Logger.log('Intake success: ' + JSON.stringify(result));
  } catch (err) {
    Logger.log('Intake FAILED: ' + (err && err.stack ? err.stack : err));
    // 失敗時はメール通知（送信先を任意で追加）
    // MailApp.sendEmail('admin@bee-smiley.com', '[体験フォーム取り込み失敗]', String(err));
  }
}

/**
 * フォーム回答からペイロードを組み立て。
 */
function buildPayload(e) {
  const named = (e && e.namedValues) || {};
  const get = function (key) {
    const arr = named[key];
    if (!arr || arr.length === 0) return '';
    return String(arr[0] || '').trim();
  };

  const parentName     = splitName(get(QUESTION_KEYS.parentName));
  const parentNameKana = splitName(get(QUESTION_KEYS.parentNameKana));
  const childName      = splitName(get(QUESTION_KEYS.childName));
  const childNameKana  = splitName(get(QUESTION_KEYS.childNameKana));

  return {
    submittedAt: new Date().toISOString(),
    parentLastName:      parentName.last,
    parentFirstName:     parentName.first,
    parentLastNameKana:  parentNameKana.last,
    parentFirstNameKana: parentNameKana.first,
    childLastName:       childName.last,
    childFirstName:      childName.first,
    childLastNameKana:   childNameKana.last,
    childFirstNameKana:  childNameKana.first,
    childBirthDate:      get(QUESTION_KEYS.childBirthDate),
    childGender:         get(QUESTION_KEYS.childGender),
    address:             get(QUESTION_KEYS.address),
    email:               get(QUESTION_KEYS.email),
    phone:               get(QUESTION_KEYS.phone),
    permitStatus:        get(QUESTION_KEYS.permitStatus),
    diagnosis:           get(QUESTION_KEYS.diagnosis),
    kindergarten:        get(QUESTION_KEYS.kindergarten),
    grade:               get(QUESTION_KEYS.grade),
    mainConcern:         get(QUESTION_KEYS.mainConcern),
    likes:               get(QUESTION_KEYS.likes),
    dislikes:            get(QUESTION_KEYS.dislikes),
    medicalHistory:      get(QUESTION_KEYS.medicalHistory),
    trialAttendee:       get(QUESTION_KEYS.trialAttendee),
    source:              get(QUESTION_KEYS.source),
    memo:                get(QUESTION_KEYS.memo),
    // 生の回答も全部送る（フォームの設問追加に追従しやすいように）
    raw: named,
  };
}

/**
 * フルネームを姓と名に分割。スペース区切り（半角・全角）のみ対応。
 * スペースなしの場合は last のみに入れる（管理側で手動分割する想定）。
 */
function splitName(full) {
  const s = String(full || '').trim();
  if (!s) return { last: '', first: '' };
  const parts = s.split(/[\s　]+/).filter(function (p) { return p.length > 0; });
  if (parts.length >= 2) {
    return { last: parts[0], first: parts.slice(1).join('') };
  }
  return { last: s, first: '' };
}

/**
 * Cloud Function に POST。
 */
function postToCloudFunction(payload) {
  const props = PropertiesService.getScriptProperties();
  const url    = props.getProperty('INTAKE_URL');
  const secret = props.getProperty('INTAKE_SECRET');
  if (!url || !secret) {
    throw new Error('INTAKE_URL / INTAKE_SECRET が未設定です（プロジェクトのスクリプトプロパティを確認）');
  }

  const res = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'x-intake-secret': secret },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });

  const code = res.getResponseCode();
  const body = res.getContentText();
  if (code < 200 || code >= 300) {
    throw new Error('Cloud Function returned ' + code + ': ' + body);
  }
  return JSON.parse(body || '{}');
}

/**
 * 手動テスト用: スクリプトエディタから直接実行して動作確認できる。
 */
function _manualTest() {
  const fakeEvent = {
    namedValues: {
      '保護者様のお名前': ['テスト 太郎'],
      '保護者様のお名前（ふりがな）': ['てすと たろう'],
      'お子さまのお名前': ['テスト 花子'],
      'お子さまのお名前（ふりがな）': ['てすと はなこ'],
      'お子さまの誕生日': ['2021/04/19'],
      'お子様の性別': ['女子'],
      'メールアドレス': ['intake-test+' + Date.now() + '@example.com'],
      '電話番号': ['09000000000'],
      '受給者証の有無': ['無'],
      '診断名': ['なし'],
      '（お通いの場合）幼稚園/保育園名': ['テスト幼稚園'],
      '（お通いの場合）学年': ['年中'],
      '体験に行ってみようと思った理由があればお知らせください。（お困りごと、不安なことなど）': ['手動テスト'],
      'お子さまの好きなこと、得意なことをお知らせください。': ['ダンス'],
      'お子さまの嫌いなこと、苦手なことをお知らせください。': ['切り替え'],
      '既往歴はありますか？※ある場合はできるだけ詳しくお知らせください。': ['なし'],
      '体験当日の来所予定の方': ['母'],
      'どこからビースマイリーをお知りになりましたお知りになりましたか？': ['Instagram'],
      'その他お伝えしたいことがあればご記載ください。': ['手動テスト'],
    },
  };
  onFormSubmit(fakeEvent);
}
