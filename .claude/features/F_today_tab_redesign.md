# F_today_tab_redesign: 今日タブの 3 ペイン化

## ゴール
毎朝の Lead 整理作業を、マウス移動最小・クリック最小で進められる UI にする。Salesforce/HubSpot/Pipedrive 共通の「左ナビ + 中央リスト + 右詳細」3 ペイン構造に揃える。

## スコープ
1. 中央リスト: 6 カラムテーブル → 2 行コンパクトカード
2. 右詳細: クリック開閉式 → 常時表示 + 初期表示時に最上位 Lead を自動選択
3. 上部サマリ: padding 圧縮で縦サイズ 50-60% に（折りたたみは入れない、サブ項目は常時表示）
4. breakpoint: 1100 → 1280px、未満は従来のスライドオーバー方式維持

## 触るファイル
- `lib/crm/crm_lead_card_compact.dart`（新規）
- `lib/crm/crm_lead_side_panel.dart`（onClose nullable 化、× ボタンと Esc を conditional）
- `lib/crm/crm_home_screen.dart`（_UrgentSection 置換、2 ペイン常時表示、padding 圧縮）

## 触らないもの
- `crm_home_utils.dart`（集計ロジック流用）
- `crm_lead_screen.dart`（データベース・分析タブには影響なし）
- 既存 `_CrmTableView`（データベースタブで継続使用）

## Validation
- [ ] 初期表示時、最上位 Lead が右に自動選択
- [ ] カードクリックで右パネル即切り替え
- [ ] フィルタ chip タップ時、選択中 Lead が新フィルタに該当しない場合は新リスト先頭を自動選択
- [ ] 中央リストカードが 2 行・横幅コンパクト
- [ ] 上部サマリの縦サイズが圧縮されている
- [ ] 既存アクション（対応記録 / 電話 / 日程変更 / メモ）が動作
- [ ] 1280px 以上で 2 ペイン、未満で従来のスライドオーバー
- [ ] flutter analyze 警告ゼロ
- [ ] design-tokens 違反 0 件
- [ ] データベース / 分析タブが破壊なし

## 学び・詰まった点
（実装後に追記）
