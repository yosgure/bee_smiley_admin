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

### Alert Thresholds（`crm_lead_screen.dart` / `crm_home_utils.dart` に定数化）
- `STALE_CONSIDERING_DAYS = 3`
- `STALE_PROCESSING_DAYS = 7`
- `RECIPIENT_CARD_STALE_DAYS = 14`
- `SURVEY_DELAY_DAYS = 7` — 問い合わせ受付からアンケート回収までの上限（超えると督促タブに浮上）
- `NO_NEXT_ACTION_HOURS = 24`
- `TRIAL_FOLLOWUP_HOURS = 24`

### Urgent Reason Categories（`CrmUrgentReason`）
督促タブに表示する分類:
- `overdue` — 次の一手の予定日を超過
- `trialFollowupMissing` — 体験予定日経過＋体験実施日未入力
- `contractStalled` — 入会手続中で 7 日以上動きなし
- `surveyNotReceived` — 検討中で問い合わせから 7 日経過＋アンケート未回収
- `noNextAction` — 次のアクション未設定 + 最終接触から 24h 経過

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
- 1 リードは常に「次のアクション」を 1 つだけ持つ（`nextActionAt` + `nextActionNote` + `nextActionType`）
- 完了時は次のアクションの内容入力が必須（空のまま完了不可）
- lead-CRM context では独立した tasks の概念を導入しない（汎用タスク機能とは別）
- **検討中**ステージにおいて「次のアクション」は基本的に**保護者側の動き待ち**を表す。
  期日 = 「この日まで動きが無ければスタッフから催促する締切」と統一して扱う。
  待ち事項（種別）と能動アクション（状況確認・その他）を同じ枠で扱うため、
  かつての「待ち状態」セクションは復活させない。

### Memo Separation
3 種類のメモを混同しない:
- `activities[]` — 過去の対応実績（履歴タイムライン）
- `nextActionNote` — 1 件の次のアクション（補足メモ）
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

## CRM UI Architecture (v3)

CRM 関連 UI は **目的別** に役割を分離する:

| UI | ファイル | 目的 | 主な使い手 |
|---|---|---|---|
| **サイドパネル** | `crm_lead_side_panel.dart` | リード進行管理（ステージ遷移・次の一手・対応履歴） + 軽量メタ情報（媒体・希望条件・備考） | 現場スタッフ |
| **児童マスタ画面** | `crm_lead_screen.dart` `CrmLeadEditScreen` (※将来リネーム) | HUG同期情報の編集。リード〜在籍生徒〜退会者まで全員に対応 | 事務 |
| **データベースタブ** | `crm_lead_screen.dart` `_CrmTableView` | 全児童の検索・絞り込み・一覧 | 経営者 + スタッフ |
| **管理タブ保護者・児童(bsp)** | `student_manage_screen.dart` | 退会済アーカイブ・データ操作（重複機能廃止後の特化用途） | 管理者 |
| **分析タブ** | (未実装) | 集計・可視化のみ | 経営者 |

### Side Panel Sections（v3 仕様）
固定順:
1. **ステージ遷移ボタン**（具体ボタン式 — Stage Transition UI 参照）
2. **進捗チェックリスト**（Stage-Specific Checklists 参照）
3. **次のアクション**（1 件のみ — Single Next Action 参照）
4. **対応履歴**（`activities[]`）
5. **基本情報**: 全項目クリックでインライン編集可。
   - 連絡先: 保護者氏名（姓名スペース区切り） / 電話 / メール / 媒体（ドロップダウン）
   - 児童属性: 生年月日（日付ピッカー） / 性別（ChoiceChip） / 園 / 学年
   - 主訴・特性（5 項目）: アンケート + ヒアリング 2 層構造（後述）
   - 体験メモ / 備考（独立、2 層化しない）

### Intake / Hearing Two-Layer Fields
主訴・好きなこと・苦手なこと・既往歴・診断名 の 5 項目は 2 層構造で持つ:
- **アンケート由来**（既存フィールド）: `mainConcern` / `likes` / `dislikes` / `medicalHistory` / `diagnosis`
  - フォーム自動取り込み時に保護者の言葉で入る
  - 編集可だが原則そのまま保持（保護者の原文として）
- **ヒアリング追記**（新規フィールド）: `mainConcernHearing` / `likesHearing` / `dislikesHearing` / `medicalHistoryHearing` / `diagnosisHearing`
  - スタッフが来所ヒアリングで深掘りした内容を書き加える
  - サイドパネル UI では「アンケート」「ヒアリング」のタグ付きで 2 行表示

電話・メールはインライン編集可、別アイコンで発信/メーラー起動を分離。

旧「待ち状態」セクションは廃止（後述）。

### Child Master Screen
旧 `CrmLeadEditScreen` を「児童マスタ画面」として位置づける。スコープ:
- リード段階・入会手続き中・在籍生徒・退会者すべてで開ける
- 内容: 児童詳細（生年月日 / 性別 / 園 / 学年 / 既往歴 / 診断名）/ 保護者情報（姓名 / ふりがな / 電話 / メール / 住所 / 続柄）/ 受給者証 / 契約日 / 支援計画
- 開く導線: ①サイドパネルの「編集」ボタン ②データベースタブの行タップ ③管理タブ保護者・児童画面の児童カードタップ
- フェーズ別ステッパーUI（①体験前/②体験後/...）は廃止予定（将来 Stage Transition UI に統合）

### Database Tab Specification
- 粒度: **児童 1 件 = 1 行**（`plus_families.children[]` フラット化）
- 列: 児童名 / 年齢 / ステージ / 教室 / 保護者 / 媒体 / 問い合わせ日 / 入会日 / 次の一手期限
- フィルタ: ステージ複数選択 / 教室 / 媒体 / 入会日範囲 / 退会済含むトグル
- 検索: 児童名 / 保護者名 / 電話 部分一致
- 並び: 列ヘッダクリックでソート切替
- 表示範囲: リード + 在籍生徒 + 退会者すべて（フィルタで絞る）
- タップ: 児童マスタ画面を開く

### Stage-Specific Checklists (v3)
進捗チェックリストはステージごとに切り替わる。現ステージのみ Firestore に保存。
ステージ遷移（検討中 → 入会手続中）時は新ステージ用の初期値で上書きされ、過去のチェック状態は保持しない。

**検討中 (5 項目)**: inquired (問い合わせ受付), trial_scheduled (体験日決定),
survey_received (アンケート回収), trial_completed (体験実施),
intent_confirmed (入会意向の確認)

**入会手続中 (5 項目)**: assessment_hearing_date_set (アセスメントヒアリング日決定),
contract_date_set (契約日決定), assessment_created (アセスメント作成),
support_plan_created (個別支援計画書作成), planning_meeting_done (策定会議)

**自動チェック項目** (UI で disabled、元フィールドから派生):
- `inquired` ← `inquiredAt` が非 null
- `trial_scheduled` ← `trialAt` が非 null
- `survey_received` ← `surveyReceivedAt` が非 null（フォーム自動取り込み時に自動セット）
- `trial_completed` ← `trialActualDate` が非 null（trialAt 経過のみでは入らない）

`trialAt` 経過 + `trialActualDate` 空 = 督促タブに「体験未実施 (予定経過)」表示。
キャンセル/再調整漏れの検出を兼ねる。

受給者証は別フィールド `permitStatus`（none / applying / have）、両ステージ共通。

### Next Action Types
ハードコード `_nextActionTypes` 定数（`crm_lead_side_panel.dart`）。
ステージで絞り込み、種別選択時に期日デフォルト自動セット。
将来 `nextActionTypes` Firestore コレクションに切り出し可能。

**検討中（保護者の動き待ち系 + 能動アクション）**:
- `visit_other_facility` 他施設見学
- `family_consultation` 家族で相談
- `day_increase_request` 日数増枠対応
- `other_facility_withdrawal` 他事業所退所手続き
- `recipient_cert_application` 受給者証申請
- `attendance_schedule_adjust` 通所日程調整
- `status_check` 状況確認（能動）

**入会手続中（進捗を進めるための汎用カテゴリ）**:
- `contact_confirm` 連絡・確認
- `schedule_adjust` 日程調整
- `document_creation` 書類作成
- `meeting_adjust` 会議調整

入会手続中ステージでは、達成項目の記録は **進捗チェックリスト 5 項目**（アセスメントヒアリング日決定 / 契約日決定 / アセスメント作成 / 個別支援計画書作成 / 策定会議）側で行う。「次のアクション」種別は、それを進めるためのスタッフ視点の汎用カテゴリに留める。

**全ステージ共通**:
- `other` その他（補足必須要件は撤廃済み — v3）

## Form Auto-Import (Google フォーム自動取り込み)

体験アンケート (Google フォーム) の回答を **plus_families** に自動同期する。

### パイプライン
```
Google フォーム
  └─ onFormSubmit (Apps Script)
       └─ HTTPS POST → Cloud Functions
            └─ plus_families に upsert
                 ├─ メール / 電話一致 → 既存 family.children[i] を更新
                 └─ 一致なし → 新規 family + child[0] 作成
```

### マージキー
**メール OR 電話番号の完全一致**で既存リードを検索し、見つかれば更新。なければ新規作成。

### 初期値
- `stage`: `considering`（検討中）
- `inquiredAt`: フォーム回答時刻
- `source`: フォームの「お知りになりました」をマッピング
- 通知未読フラグ: `notifyUnread = true`

### フィールドマッピング（フォーム → Firestore）
| フォーム項目 | Firestore (`plus_families`) |
|---|---|
| 保護者様のお名前 | `lastName` + `firstName`（姓名分割） |
| 保護者様のお名前（ふりがな） | `lastNameKana` + `firstNameKana` |
| お子さまのお名前 | `children[].lastName` + `firstName` |
| お子さまのお名前（ふりがな） | `children[].lastNameKana` + `firstNameKana` |
| お子さまの誕生日 | `children[].birthDate` |
| お子様の性別 | `children[].gender`（男子/女子/その他） |
| ご住所 | `address` |
| メールアドレス | `email` |
| 電話番号 | `phone` |
| 受給者証の有無 | `children[].permitStatus`（有→have / 無→none） |
| 診断名 | `children[].diagnosis` |
| 幼稚園/保育園名 | `children[].school` |
| 学年 | `children[].grade` |
| 体験理由 | `children[].mainConcern`（主訴） |
| 好きなこと・得意なこと | `children[].likes` |
| 嫌いなこと・苦手なこと | `children[].dislikes` |
| 既往歴 | `children[].medicalHistory` |
| 体験当日来所予定 | `children[].trialAttendee` |
| 認知経路 | `source`（媒体） |
| その他 | `memo` |

## Unread Notification Badge

新規リードの取り込みや未確認の動きをサイドメニュー CRM アイコンの **赤ポチ** で示す。

- 判定: `plus_families` のうち `notifyUnread == true` が1件以上ある
- 既読化: 該当リードを開いた時に `notifyUnread = false` に更新
- 実装: Firestore リスナーでカウント監視、サイドメニュー側で Badge ウィジェット表示
- FCM・プッシュ通知は使わない（アプリ内バッジのみ）

## Removed Fields / Features (v3)

以下は削除済み・削除予定。マイグレーションで Firestore からも除去:
- `confidence`（A/B/C 入会確度）— 分析価値が薄く運用負担が大きいため廃止
- `partnerCategory` — 媒体の二重管理になっていたため廃止
- 待ち状態関連 (`waitReason` / `waitDeadline` / `waitNote`) — UI もコメントアウトのまま運用されていなかったため正式廃止
- `nextActionType == 'other'` 選択時の補足必須バリデーション — 入力負担削減のため撤廃

待ち状態廃止後の挙動: 「他事業所決定待ち」「受給者証申請中」のような本当に待つしかないリードも、督促タブの「次の一手未設定」アラートに表示される（実害なしと判断）。
