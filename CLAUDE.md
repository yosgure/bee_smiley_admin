# プロジェクトルール

## デプロイ（どのセッションからでも実行可）

1. `git fetch --all` で最新を取得
2. `git branch -a --no-merged main` で未マージブランチを確認し、すべてmainにマージする
3. `flutter pub get` → `flutter build web --no-tree-shake-icons` でビルド
4. `firebase deploy --only hosting` でデプロイ
5. Firestoreルール等に変更があれば `firebase deploy --only firestore:rules` も実行

- **必ずmainブランチに切り替えてから**ビルド＆デプロイすること。別ブランチからデプロイすると他のセッションの変更が消える
- デプロイ前に他セッションの未マージブランチを全てmainにマージすること

## 開発

- 作業開始前に `git pull` を実行すること（最新の変更を取り込む）
- PRは作成しないこと（コミットしてpushするだけ）

## 動作確認

- UI変更の実装が完了したら、ユーザーに聞かずに自動的にローカルdevサーバーを起動すること
- コマンド: `flutter run -d chrome --web-port=<ポート番号>`
- ポート番号はセッションごとに変える（8080, 8081, 8082...）、既に使われている場合は別のポートを使う
- サーバー起動後、ユーザーに「localhost:<ポート番号> で確認してください」と伝えること
- 確認時はホットリロード（r）ではなくホットリスタート（R）を使うこと（定数・マップ・static変数の変更はホットリロードでは反映されないため）
- 本番環境 (bee-smiley-admin.web.app) での確認はデプロイ後のみ

## CRM Design Rules

### User Segmentation
- CRM は 2 種類のユーザーを想定: 経営者（ダッシュボード中心）と現場スタッフ（タスク中心）
- 現場スタッフのデフォルト表示は「督促タブ」、経営者は「分析タブ」（将来的にロール別分岐）
- カード情報密度は現場向けは高め、経営者向けは可視化優先

### Stage Transitions
- ステージ遷移は DAG: `検討中 → 入会手続中 → 入会 → 退会` / `(any) → 失注`
- `失注` と `退会` への遷移時は理由を選択必須（`CrmOptions.lossReasons` / `CrmOptions.withdrawalReasons`）
- `検討中` → `入会` の直接遷移は禁止（必ず `入会手続中` を経由）
- 遷移可否は `CrmOptions.canTransition(from, to)` で検証

### Alert Thresholds（`crm_lead_screen.dart` に定数化）
- `STALE_CONSIDERING_DAYS = 3`
- `STALE_PROCESSING_DAYS = 7`
- `RECIPIENT_CARD_STALE_DAYS = 14`

### Design Tokens
- アラート色は `context.alerts.{warning|urgent|info|success}` を必ず経由する（`Colors.red` / `Colors.blue` の直接指定禁止）
- 全テキストは WCAG AA コントラスト（4.5:1）を満たすこと
- 定義は `lib/app_theme.dart` の `AlertPalette`

## 既知のデータ品質問題

### plus_families.children[] の status フィールド整合性
旧 families コレクションから plus_families への移行時、status フィールドが未更新のまま残っているレコードが多数。実態は「入会」だが status='検討中'/'入会手続中' のまま、または status=null の子供が多い。

### 暫定対応
予定/ダッシュボード画面のフィルタは「lost/withdrawn 除外」のブラックリスト方式で運用中（`plus_schedule_screen.dart:953`, `plus_dashboard_screen.dart:124`, `ai_chat_main_screen.dart:101`）。

### 本来の解決
CRM の Lead ステージ管理が安定したら、status フィールドをステージから自動同期する仕組みを入れる（Cloud Functions の onUpdate トリガー）。それまでは現フィルタ維持。

## CRM Lead Model Rules

### Single Next Action
- 1 リードは常に「次の一手」を 1 つだけ持つ（`nextActionAt` + `nextActionNote`）
- 完了時は次の一手の内容入力が必須（空のまま完了不可）
- lead-CRM context では独立した tasks の概念を導入しない（汎用タスク機能とは別）

### Memo Separation
3 種類のメモを混同しない:
- `activities[]` — 過去の対応実績（履歴タイムライン）
- `nextActionNote` — 1 件の未来の予定
- `memo` — 常時のプロフィールメモ（アレルギー・家庭事情・保護者意向等）

汎用「メモ」ボタン・フィールドは禁止。

### Stage Transition UI
- 抽象「ステージ変更」コントロール禁止。現ステージに応じた具体ボタン:
  - `considering` → 「入会手続き開始」
  - `onboarding` → 「入会完了」
  - `won` → 「退会処理」
  - `considering`/`onboarding` のサブメニュー → 「失注として記録」
- 失注 / 退会 への遷移は理由必須

### Contact Channels
サポートする連絡手段: 電話 / メール / 来所。
LINE は連絡手段に含めない（UI から削除済み、スキーマは互換性のため保持）。

### Future Schema Renames（Phase 1）
- `nextActionAt` → `nextActionDate`
- `nextActionNote` → `nextActionContent`
- `memo` → `profileNote`
（リネーム時はマイグレーションスクリプト + 双方向参照対応必須）

### Lead Detail 7-Section Layout (v2)
リード詳細パネルは以下の固定セクション順:
1. 基本情報 (連絡先 + 媒体 + 備考)
2. 進捗 (受給者証 + 7 項目チェックリスト + 進捗バー)
3. 次の一手 (1 件のみ)
4. 待ち状態 (該当時のみ表示)
5. 児童プロフィール (生年月日 / 性別 / 園 / 主訴 / 好き / 苦手 / 体験メモ)
6. 日程
7. 対応履歴

### Stage-Specific Checklists (v3)
進捗チェックリストはステージごとに切り替わる。現ステージのみ Firestore に保存。
ステージ遷移（検討中 → 入会手続中）時は新ステージ用の初期値で上書きされ、過去のチェック状態は保持しない。

**検討中 (6 項目)**: inquiry_received, pre_trial_hearing, trial_scheduled,
trial_completed, post_trial_followup, intent_confirmed

**入会手続中 (7 項目)**: file_created, hug_registered, assessment_done,
contract_sent, contract_received, support_plan_created, support_plan_explained

**自動チェック項目** (UI で disabled、元フィールドから派生):
- `inquiry_received` ← `inquiredAt` が非 null
- `trial_scheduled` ← `trialAt` が非 null
- `trial_completed` ← `trialActualDate` が非 null（trialAt 経過のみでは入らない）

`trialAt` 経過 + `trialActualDate` 空 = 督促タブに「体験未実施 (予定経過)」表示。
キャンセル/再調整漏れの検出を兼ねる。

受給者証は別フィールド `permitStatus`（none / applying / have）、両ステージ共通。

### Waiting State (待ち状態)
固定 6 理由: 他事業所決定待ち / 受給者証申請中 / 家庭事情 / 空き枠待ち / 連絡待ち / その他。
**待ち状態の Lead は「次の一手未設定」アラート対象外**（待つのが正しい状態）。
ただし「次の一手の期限超過」は引き続きアラート対象。

### Next Action Types
ハードコード `_nextActionTypes` 定数（`crm_lead_side_panel.dart`）。
ステージで絞り込み、種別選択時に期日デフォルト自動セット。`other` のみ補足必須。
将来 `nextActionTypes` Firestore コレクションに切り出し可能。
