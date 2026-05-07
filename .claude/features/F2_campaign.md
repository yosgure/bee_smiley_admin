# F2: Campaign（打ち手）オブジェクト

## ゴール
施策単位で ROI を測定可能にする。「Instagram」全体ではなく「Instagram_Reel_教具紹介_2026Q2」単位で Lead 数・入会数・CAC・CVR を可視化する。

## 設計判断（上田事前回答）
1. media フィールドは破壊しない（共存）
2. cost は nullable（null = CAC 算出不可、organic は null 推奨）
3. 空状態 + 「最初の施策を起案」CTA
4. channel enum は既存 CrmOptions.sources と完全一致
5. businessId フィールドを最初から両対応スキーマに含める（値は 'Plus' 固定）

## スキーマ
```
campaigns/{id}:
  businessId: 'Plus'
  name, channel, type, cost (nullable), startDate, endDate (nullable),
  hypothesis, expectedLeads, expectedConversions,
  status: 'planning' | 'running' | 'reviewing' | 'archived',
  retrospective (nullable, F9 で AI 生成),
  createdAt, updatedAt, createdBy
plus_families.children[].sourceCampaignId: string | null  // 既存 source は破壊しない
```

## 実装範囲
- `lib/crm/campaign.dart`（新規: モデル + 集計ヘルパー）
- `lib/crm/campaign_form_dialog.dart`（新規: 起案 / 編集）
- `lib/crm/campaign_section.dart`（新規: カンバン + 空状態 CTA）
- `lib/crm_lead_screen.dart`（_CrmDashboardView に CampaignSection 挿入、Lead 詳細パネルに sourceCampaign セレクタ）
- `firestore.rules`（campaigns コレクション）

## F2 で実装しないもの
- Cloud Functions 自動集計（クライアント計算で十分、F6 で整える）
- Gemini による起案補助・打ち手レビュー（F9 と一緒に）
- ROI ランキング・勝ちパターン順ソート

## Validation
- [ ] 分析タブ「媒体別KPI」直下にカンバンセクションが現れる
- [ ] 空状態 → CTA → フォーム → 作成 → カンバン表示
- [ ] カード長押しでステータス変更
- [ ] Lead に sourceCampaignId 紐付け → カードの actualLeads が即時反映
- [ ] cost null 時 CAC は「-」
- [ ] 既存 Lead（sourceCampaignId なし）の挙動が変わらない
- [ ] flutter analyze 警告ゼロ

## 学び・詰まった点
（実装後に追記）
