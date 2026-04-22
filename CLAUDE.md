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
