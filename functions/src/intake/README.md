# フォーム自動取り込み (intakeForm)

体験アンケート Google フォームの回答を `plus_families` に自動で upsert する Cloud Function と、それを呼び出す Apps Script のセット。

## 構成

```
Google フォーム
  └─ onFormSubmit (Apps Script: apps_script.gs)
       └─ HTTPS POST → exports.intakeForm (form_intake.js)
            └─ plus_families upsert
                 ├─ メール / 電話一致 → 既存 family.children[i] を更新
                 └─ 一致なし → 新規 family + child[0] 作成
```

通知は `plus_families.notifyUnread = true` を立てる。Flutter 側のサイドメニュー CRM アイコンの赤ポチがこれを購読している（CRMタブを開くと一括で false に戻る）。

## 初回セットアップ

### 1. シェアードシークレット生成

```bash
openssl rand -hex 32
# 出力例: 7a1c... (64文字)
```

この値を **2 か所** に同じ内容で設定する:
- Cloud Functions の Secret Manager（`INTAKE_FORM_SECRET`）
- Apps Script のスクリプトプロパティ（`INTAKE_SECRET`）

### 2. Cloud Functions Secret 登録

```bash
cd functions
firebase functions:secrets:set INTAKE_FORM_SECRET
# プロンプトで上で生成した値を貼り付け
```

確認:
```bash
firebase functions:secrets:access INTAKE_FORM_SECRET
```

### 3. Cloud Function デプロイ

```bash
firebase deploy --only functions:intakeForm
```

デプロイ後、コンソールに表示される URL を控える:
```
Function URL (intakeForm(asia-northeast1)):
https://asia-northeast1-bee-smiley-admin.cloudfunctions.net/intakeForm
```

### 4. Apps Script セットアップ

1. 体験アンケート Google フォームを開く
2. 右上「︙」→「スクリプトエディタ」（または該当スプレッドシートの「拡張機能 → Apps Script」）
3. `apps_script.gs` の中身を貼り付けて保存
4. 左サイドバー「⚙️ プロジェクトの設定」→「スクリプト プロパティ」で以下を追加:
   - `INTAKE_URL`    : 上で控えた Cloud Function の URL
   - `INTAKE_SECRET` : 上で生成したシークレット（Cloud Functions と同じ値）
5. 左サイドバー「⏰ トリガー」→「+ トリガーを追加」:
   - 実行する関数: `onFormSubmit`
   - イベントのソース: `フォームから`
   - イベントの種類: `フォーム送信時`
6. 初回実行時に Google アカウント承認のダイアログが出るので許可

### 5. 動作確認

スクリプトエディタで `_manualTest` 関数を実行 → ログを確認。
成功すると Firestore `plus_families` にダミーリードが追加される（`intake-test+...@example.com`）。
確認後、ダミーは管理画面から削除する。

実際のフォームから本番テスト送信して、CRM の赤ポチが点くこと、リードが自動作成されることを確認。

## 運用ルール

### マージキー
- メール OR 電話番号の **完全一致** で既存リードを検索
- 同じ family に氏名違いの子供が来た場合は children[] に追加（兄弟）
- 既存値は空文字以外で上書きしない（誤クリア防止）

### 既存値の保護
- ステージは初回のみ `considering` でセット。再送時は既存ステージを保持
- `inquiredAt` は初回のみセット。以降は更新しない（リード進行を巻き戻さない）

### 手動取り込みも可能
フォーム経由以外（電話・Instagram DM）の問い合わせは、CRM 画面から「新規リード」ボタンで手動作成。`notifyUnread` を立てる必要はない（手動作成者がそのまま対応する想定）。

## トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| 401 Unauthorized | シークレット不一致 | Cloud Functions Secret と Apps Script Properties を再確認 |
| 500 Internal Error | フォームの設問名変更 | `apps_script.gs` の `QUESTION_KEYS` を更新 |
| リードができない | トリガー未設定 | スクリプトエディタの「トリガー」を確認 |
| 重複リードができる | メール/電話表記揺れ | 電話は数字のみに正規化済み、メールは小文字化済み。それでも揺れる場合は手動マージ |

## 関連ファイル

- `form_intake.js` — Cloud Function 本体
- `apps_script.gs` — Apps Script コード（Google フォーム側）
- `../utils/setup.js` — Firebase Admin 初期化、Secret 定義
- `lib/main.dart` — `_setupCrmUnreadListener()` で notifyUnread を購読、サイドメニュー CRM アイコン赤ポチ
