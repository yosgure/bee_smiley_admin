# fastlane セットアップ手順

ストア提出を自動化するための初回セットアップ。一度終われば以降は CLI 一発で提出可能。

---

## 必須ファイルの配置場所

両方とも `~/.config/beesmiley/` 配下に置く（git 管理外）。
未作成なら：

```sh
mkdir -p ~/.config/beesmiley
```

| ファイル | パス |
|---|---|
| App Store Connect API キー | `~/.config/beesmiley/appstore_api.p8` |
| Google Play サービスアカウント JSON | `~/.config/beesmiley/playstore_service.json` |

---

## iOS: App Store Connect API キーの取得

1. https://appstoreconnect.apple.com にログイン
2. 「ユーザーとアクセス」→「統合」タブ → 「App Store Connect API」を選択
3. 「APIキー」タブで「+」→ 名前を入力（例: `fastlane`）→ アクセス権限を「App Manager」に → 「生成」
4. 生成された **.p8 ファイル**をダウンロード（一度しかDLできないので注意）
5. ダウンロードしたファイルをリネーム＆配置：

```sh
mv ~/Downloads/AuthKey_*.p8 ~/.config/beesmiley/appstore_api.p8
chmod 600 ~/.config/beesmiley/appstore_api.p8
```

6. 同じ画面の **Issuer ID**（上部）と **Key ID**（一覧の該当行）をメモ
7. シェルの環境変数に追加（`~/.zshrc` などに追記）：

```sh
export ASC_API_KEY_ID="XXXXXXXXXX"        # 10文字
export ASC_API_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # UUID
```

```sh
source ~/.zshrc
```

---

## Android: Google Play サービスアカウントの取得

1. https://console.cloud.google.com にログインし、プロジェクトを選択（または新規作成）
2. 左メニュー「IAM と管理」→「サービスアカウント」→「サービスアカウントを作成」
3. 名前を入力（例: `fastlane-supply`）→ 作成
4. 作成したアカウントを開く → 「キー」タブ → 「キーを追加」→「新しいキー」→ JSON → 「作成」
5. JSON ファイルがダウンロードされるので配置：

```sh
mv ~/Downloads/<プロジェクト名>-*.json ~/.config/beesmiley/playstore_service.json
chmod 600 ~/.config/beesmiley/playstore_service.json
```

6. https://play.google.com/console → 設定 → 「APIアクセス」
7. 「新しいサービスアカウントの招待」が表示されるので、4でJSONを生成したサービスアカウントのメールアドレスを選択
8. 権限：「アプリを表示」「リリースを管理」を付与（または全権限）→ 招待
9. 反映に数分〜1時間程度かかる場合あり

---

## 動作確認

```sh
cd /Users/uedayousuke/Desktop/フォルダ/bee_smiley_admin

# iOS：TestFlightへアップロードのみ（審査提出はしない）
cd ios && fastlane beta && cd ..

# iOS：審査提出まで自動化
cd ios && fastlane release && cd ..

# Android：内部テストへアップロード（公開はしない）
cd android && fastlane beta && cd ..

# Android：製品版へアップロード＋公開
cd android && fastlane release && cd ..

# Android：製品版に下書きとしてアップロード（Play Consoleで確認後手動公開）
cd android && fastlane draft && cd ..
```

---

## 通常リリース手順（セットアップ後）

```sh
cd /Users/uedayousuke/Desktop/フォルダ/bee_smiley_admin

# 1. バージョン更新（pubspec.yaml の version: をインクリメント）
# 2. ビルド
flutter build ipa --release --no-tree-shake-icons
flutter build appbundle --release --no-tree-shake-icons

# 3. 審査提出
cd ios && fastlane release && cd ..
cd android && fastlane release && cd ..
```

---

## トラブルシューティング

- **「No such file or directory」エラー** → `~/.config/beesmiley/` 配下のファイルパスを確認
- **iOS のアップロード時に「Invalid bundle」エラー** → `flutter build ipa` を再実行
- **Android で「Service account does not have permission」** → Play Console の API アクセスでサービスアカウントの権限を確認、付与後30分〜1時間待つ
- **fastlane match を使いたい** → 現状は手動署名（プロジェクト設定済み）。match 移行が必要なら別途設定
