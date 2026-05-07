# F1: 失注理由必須化

## ゴール
失注 48 件中 48 件が `lossReason='other'` で改善学習が停止している状態を解消し、以後の失注は理由が必ず分類されるようにする。

## 背景・根本原因
- `crm_lead_screen.dart:457` の CSV インポート処理が `'lossReason': stage == 'lost' ? 'other' : null` と強制 'other' を入れていた
- ライブ編集の必須選択は L1635 で実装済み
- しかし `lossDetail` の必須（other 選択時）と `lostAt` の自動セットは未実装

## 実装内容
1. CSV インポートの強制 'other' を削除し、CSV 値を尊重（空なら null）
2. `lossReason == 'other'` のとき `lossDetail` を必須化（バリデーション追加）
3. ステージ遷移で 'lost' に変わった瞬間に `lostAt = serverTimestamp()` を自動セット
4. 同様に 'withdrawn' に変わったとき `withdrawnAt` を自動セット
5. データベースタブに「未分類失注」フィルタを追加（`stage=='lost' && lossReason==null`）

## 触るファイル
- `lib/crm_lead_screen.dart`（CSV import L420-465 / save L1635 / データベースタブのフィルタ）

## Validation
- [ ] 既存 48 件: lossReason は CSV 由来なので残る。新規失注で必須選択モーダルが出る
- [ ] other 選択時に詳細欄が必須になる
- [ ] ライブで 'lost' 遷移時に lostAt が入る
- [ ] データベースタブで「未分類失注」フィルタが機能する
- [ ] `flutter analyze` 警告ゼロ
- [ ] ブラウザ動作確認 → 上田レビュー

## 学び・詰まった点
（実装後に追記）
