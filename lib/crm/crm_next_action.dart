/// 対応結果・感触・次の一手プリセットの選択肢マスタ。
/// 既存 `CrmOptions`（crm_lead_screen.dart）を補完する形で配置する。
/// Phase 1 では定義のみ。UI から参照されるのは Phase 3 以降。
library;

/// 対応結果（outcome）
class CrmOutcome {
  final String id;
  final String label;
  const CrmOutcome(this.id, this.label);
}

const List<CrmOutcome> crmOutcomes = [
  CrmOutcome('reached', '話せた'),
  CrmOutcome('not_reached', '繋がらなかった'),
  CrmOutcome('completed', '完了した'),
  CrmOutcome('pending', 'まだ動きなし'),
];

/// 感触（feeling）: reached / completed のときに必須入力を想定。
class CrmFeeling {
  final String id;
  final String label;
  final String emoji;
  const CrmFeeling(this.id, this.label, this.emoji);
}

const List<CrmFeeling> crmFeelings = [
  CrmFeeling('positive', '前向き', '👍'),
  CrmFeeling('considering', '検討中', '🤔'),
  CrmFeeling('negative', '難しそう', '👎'),
];

/// 次の一手の種別。
/// 既存 `CrmOptions.activityTypes` は「履歴の種別」なので別概念として分ける。
class CrmNextActionType {
  final String id;
  final String label;
  const CrmNextActionType(this.id, this.label);
}

const List<CrmNextActionType> crmNextActionTypes = [
  CrmNextActionType('followup_call', 'フォロー電話'),
  CrmNextActionType('followup_message', 'フォロー連絡（メール/LINE）'),
  CrmNextActionType('trial_followup', '体験後フォロー'),
  CrmNextActionType('trial_arrange', '体験日程調整'),
  CrmNextActionType('contract_arrange', '契約説明の調整'),
  CrmNextActionType('doc_send', '資料送付'),
  CrmNextActionType('permit_check', '受給者証状況確認'),
  CrmNextActionType('soft_reapproach', 'ソフト再接触'),
  CrmNextActionType('escalate', '上長へ共有'),
  CrmNextActionType('custom', 'カスタム入力'),
];

/// 次の一手プリセット。
/// ステージ × 感触 で提示する候補を出し分ける。
class CrmNextActionPreset {
  final String id;
  final String label;
  final String typeId; // CrmNextActionType.id に対応
  final Duration offsetFromNow; // 標準オフセット（記録時刻からの差）
  const CrmNextActionPreset({
    required this.id,
    required this.label,
    required this.typeId,
    required this.offsetFromNow,
  });
}

/// ステージ → 感触 → プリセット一覧
const Map<String, Map<String, List<CrmNextActionPreset>>>
    _crmNextActionPresets = {
  'considering': {
    'positive': [
      CrmNextActionPreset(
          id: 'c_p_1',
          label: '3日以内に体験予約の提案',
          typeId: 'trial_arrange',
          offsetFromNow: Duration(days: 3)),
      CrmNextActionPreset(
          id: 'c_p_2',
          label: '資料を追加送付',
          typeId: 'doc_send',
          offsetFromNow: Duration(days: 1)),
      CrmNextActionPreset(
          id: 'c_p_3',
          label: '体験日時を2案提示',
          typeId: 'trial_arrange',
          offsetFromNow: Duration(days: 2)),
    ],
    'considering': [
      CrmNextActionPreset(
          id: 'c_c_1',
          label: '3日後に再連絡',
          typeId: 'followup_call',
          offsetFromNow: Duration(days: 3)),
      CrmNextActionPreset(
          id: 'c_c_2',
          label: '1週間後に状況確認',
          typeId: 'followup_message',
          offsetFromNow: Duration(days: 7)),
      CrmNextActionPreset(
          id: 'c_c_3',
          label: '空き枠情報を再共有',
          typeId: 'doc_send',
          offsetFromNow: Duration(days: 2)),
    ],
    'negative': [
      CrmNextActionPreset(
          id: 'c_n_1',
          label: '2週間後にソフト再接触',
          typeId: 'soft_reapproach',
          offsetFromNow: Duration(days: 14)),
      CrmNextActionPreset(
          id: 'c_n_2',
          label: '他事業所決定の場合は失注登録',
          typeId: 'custom',
          offsetFromNow: Duration(days: 3)),
    ],
  },
  'onboarding': {
    'positive': [
      CrmNextActionPreset(
          id: 'o_p_1',
          label: '契約説明日を提案',
          typeId: 'contract_arrange',
          offsetFromNow: Duration(days: 2)),
      CrmNextActionPreset(
          id: 'o_p_2',
          label: '受給者証の状況確認',
          typeId: 'permit_check',
          offsetFromNow: Duration(days: 3)),
      CrmNextActionPreset(
          id: 'o_p_3',
          label: '契約書類を準備',
          typeId: 'contract_arrange',
          offsetFromNow: Duration(days: 1)),
    ],
    'considering': [
      CrmNextActionPreset(
          id: 'o_c_1',
          label: '3日後に契約意思再確認',
          typeId: 'followup_call',
          offsetFromNow: Duration(days: 3)),
      CrmNextActionPreset(
          id: 'o_c_2',
          label: '不安点のヒアリング',
          typeId: 'followup_call',
          offsetFromNow: Duration(days: 2)),
    ],
    'negative': [
      CrmNextActionPreset(
          id: 'o_n_1',
          label: '失注リスクあり：上長に共有',
          typeId: 'escalate',
          offsetFromNow: Duration(days: 1)),
    ],
  },
};

/// ステージ × 感触 → プリセット。該当がなければ空配列。
List<CrmNextActionPreset> nextActionPresetsFor({
  required String stage,
  required String feeling,
}) {
  return _crmNextActionPresets[stage]?[feeling] ?? const [];
}

/// 記録保存時に提案すべきステージ遷移。
/// 返り値は「提案遷移先ステージID、理由」。提案がなければ null。
/// 勝手に遷移せず、UI で確認ダイアログを出すための判定関数。
({String toStage, String reason})? suggestStageTransition({
  required String currentStage,
  required String activityType,
  required String? outcome,
  required String? feeling,
  required String? nextType,
  required int recentNegativeCount,
  required bool contractCompleted,
}) {
  // 1) 契約ステップ完了 → 入会
  if (contractCompleted && currentStage == 'onboarding') {
    return (toStage: 'won', reason: '契約が完了しました。入会に進めますか？');
  }

  // 2) 体験完了 → 検討中（既に検討中なら提案しない）
  if (activityType == 'visit' &&
      outcome == 'completed' &&
      currentStage != 'considering' &&
      currentStage != 'onboarding' &&
      !{'won', 'lost', 'withdrawn'}.contains(currentStage)) {
    return (toStage: 'considering', reason: '体験が完了しました。検討中へ移しますか？');
  }

  // 3) 契約調整アクションの完了 → 入会手続中
  if (outcome == 'completed' &&
      nextType == 'contract_arrange' &&
      currentStage == 'considering') {
    return (toStage: 'onboarding', reason: '契約調整が進みました。入会手続中へ移しますか？');
  }

  // 4) 感触 negative が連続 → 失注候補
  if (feeling == 'negative' &&
      recentNegativeCount >= 2 &&
      !{'won', 'lost', 'withdrawn'}.contains(currentStage)) {
    return (toStage: 'lost', reason: '感触が続けて厳しいようです。失注候補として扱いますか？');
  }

  return null;
}
