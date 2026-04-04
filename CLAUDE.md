# プロジェクトルール

## デプロイ（専用セッションが実行）

1. `git fetch --all` で最新を取得
2. `git branch -a --no-merged main` で未マージブランチを確認し、すべてmainにマージする
3. `flutter pub get` → `flutter build web --no-tree-shake-icons` でビルド
4. `firebase deploy --only hosting` でデプロイ
5. Firestoreルール等に変更があれば `firebase deploy --only firestore:rules` も実行

- 別ブランチからデプロイすると、他のセッションの変更が消える原因になる

## 開発

- 作業開始前に `git pull` を実行すること（最新の変更を取り込む）
- PRは作成しないこと（コミットしてpushするだけ）。mainへのマージとデプロイは専用セッションが行う

## 動作確認

- UI変更の実装が完了したら、ユーザーに聞かずに自動的にローカルdevサーバーを起動すること
- コマンド: `flutter run -d chrome --web-port=<ポート番号>`
- ポート番号はセッションごとに変える（8080, 8081, 8082...）、既に使われている場合は別のポートを使う
- サーバー起動後、ユーザーに「localhost:<ポート番号> で確認してください」と伝えること
- 確認時はホットリロード（r）ではなくホットリスタート（R）を使うこと（定数・マップ・static変数の変更はホットリロードでは反映されないため）
- 本番環境 (bee-smiley-admin.web.app) での確認はデプロイ後のみ
- firebase deploy は種類を問わず絶対に実行しないこと（--only hosting / --only functions / その他全て禁止。デプロイは専用セッションが行う）
