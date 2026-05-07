/// ホーム（入会グロース司令塔）で使う集計・文言ヘルパー。
/// Phase 1 ではロジックのみ。UI は Phase 2 で利用する。
library;

import 'crm_lead_model.dart';

/// 督促（今すぐ対応）の分類
enum CrmUrgentReason {
  /// 次の一手の予定日を超過している
  overdue,
  /// 体験後24h以内にフォロー接触がない
  trialFollowupMissing,
  /// 入会手続中で7日以上動きがない
  contractStalled,
  /// 次の一手が未設定で、最終接触から24h経過
  noNextAction,
}

/// 分類ラベル（UI 用）
String crmUrgentReasonLabel(CrmUrgentReason r) => switch (r) {
      CrmUrgentReason.overdue => '期限切れ',
      CrmUrgentReason.trialFollowupMissing => '体験未実施 (予定経過)',
      CrmUrgentReason.contractStalled => '契約停滞',
      CrmUrgentReason.noNextAction => '次の一手を決める',
    };

/// 督促判定に使う閾値（CLAUDE.md の Alert Thresholds と整合）
class CrmUrgentThresholds {
  static const staleConsideringDays = 3;
  static const staleProcessingDays = 7;
  static const trialFollowupHours = 24;
  static const noNextActionHours = 24;
}

/// 1件のリードに対して「今すぐ対応」の理由を列挙する。
/// 対応終了ステージ（won/lost/withdrawn）は空配列。
List<CrmUrgentReason> urgentReasonsFor(CrmLead lead, {DateTime? now}) {
  if (lead.isClosed) return const [];
  final ref = now ?? DateTime.now();
  final reasons = <CrmUrgentReason>[];

  // 1) 予定日超過
  final na = lead.nextActionAt;
  if (na != null && ref.isAfter(na)) {
    reasons.add(CrmUrgentReason.overdue);
  }

  // 2) 体験未実施 (v3): 体験予定日が経過したのに体験実施日が空
  //    キャンセル/再調整漏れの検出を兼ねる。
  //    体験実施済み (trialActualDate あり) の場合は対象外。
  final trialPlanned = lead.trialAt;
  if (trialPlanned != null &&
      ref.isAfter(trialPlanned) &&
      lead.trialActualDate == null) {
    reasons.add(CrmUrgentReason.trialFollowupMissing);
  }

  // 3) 契約停滞: onboarding で 7 日以上動きなし
  if (lead.stage == 'onboarding') {
    final last = lead.lastContactAt ?? lead.inquiredAt;
    if (last != null &&
        ref.difference(last).inDays >=
            CrmUrgentThresholds.staleProcessingDays) {
      reasons.add(CrmUrgentReason.contractStalled);
    }
  }

  // 4) 次の一手未設定: 最終接触から 24h 経過しても設定されていない
  if (!lead.hasNextAction) {
    final since = lead.sinceLastContact(ref);
    if (since != null &&
        since.inHours >= CrmUrgentThresholds.noNextActionHours) {
      reasons.add(CrmUrgentReason.noNextAction);
    }
  }

  return reasons;
}

/// 優先度スコア（小さいほど優先度高い）。ソート用。
int urgentPriority(CrmUrgentReason r) => switch (r) {
      CrmUrgentReason.overdue => 0,
      CrmUrgentReason.trialFollowupMissing => 1,
      CrmUrgentReason.contractStalled => 2,
      CrmUrgentReason.noNextAction => 3,
    };

/// 「今日進めると良い」カテゴリ
enum CrmTodayCategory {
  /// 今日が返信・連絡予定日
  replyDue,
  /// 見学・体験の日程調整候補
  trialScheduling,
  /// 契約あと一歩（onboarding + 感触 positive 想定）
  almostContract,
  /// 担当者未設定（責めず「今日決めると良い」側で浮上）
  assigneeMissing,
}

String crmTodayCategoryLabel(CrmTodayCategory c) => switch (c) {
      CrmTodayCategory.replyDue => '返信待ち',
      CrmTodayCategory.trialScheduling => '見学日程調整',
      CrmTodayCategory.almostContract => '契約あと一歩',
      CrmTodayCategory.assigneeMissing => '担当を決める',
    };

/// 「今日進めると良い」判定。
///
/// 方針:
/// - replyDue / trialScheduling は督促と重複しないよう、urgent がないときのみ計上。
/// - almostContract は「入会手続中のリード総数」と一致させるため、停滞・期限切れに
///   関わらず onboarding 全件を計上する（停滞は別途 urgent 側にも現れる）。
///   これにより「契約あと一歩」の件数が直感的な入会手続中件数と一致する。
List<CrmTodayCategory> todayCategoriesFor(CrmLead lead, {DateTime? now}) {
  if (lead.isClosed) return const [];
  final ref = now ?? DateTime.now();
  final cats = <CrmTodayCategory>[];
  final urgent = urgentReasonsFor(lead, now: now);

  if (urgent.isEmpty) {
    final na = lead.nextActionAt;
    if (na != null && _isSameDay(na, ref)) {
      cats.add(CrmTodayCategory.replyDue);
    }
    if (lead.stage == 'considering' && lead.trialAt == null) {
      cats.add(CrmTodayCategory.trialScheduling);
    }
  }

  if (lead.stage == 'onboarding') {
    cats.add(CrmTodayCategory.almostContract);
  }

  // 担当者未設定は責めず、柔らかく「決めると良い」側へ。
  // 対応終了ステージは除外。assigneeUid/Name どちらも空のケースを対象。
  final hasAssignee =
      (lead.assigneeUid != null && lead.assigneeUid!.isNotEmpty) ||
          (lead.assigneeName != null && lead.assigneeName!.isNotEmpty);
  if (!hasAssignee) {
    cats.add(CrmTodayCategory.assigneeMissing);
  }

  return cats;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------- 時間帯別文言

enum CrmTimeOfDay { earlyMorning, midday, afternoon, evening }

CrmTimeOfDay crmTimeOfDay([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h >= 5 && h < 11) return CrmTimeOfDay.earlyMorning;
  if (h >= 11 && h < 15) return CrmTimeOfDay.midday;
  if (h >= 15 && h < 19) return CrmTimeOfDay.afternoon;
  return CrmTimeOfDay.evening;
}

/// Greeting の末尾（時間帯別）
String crmGreetingSuffix(CrmTimeOfDay tod) => switch (tod) {
      CrmTimeOfDay.earlyMorning => '午前中にここまで進むと、午後が少し楽になります',
      CrmTimeOfDay.midday => 'お昼までにあと少しだけ先に進めておくと安心です',
      CrmTimeOfDay.afternoon => '夕方の返信対応が多い時間です。短いものから片付けましょう',
      CrmTimeOfDay.evening => '今日はここまで進みました。明日の優先も見えています',
    };

/// おはよう／こんにちは／こんばんは の時間帯挨拶
String crmHelloPrefix(CrmTimeOfDay tod) => switch (tod) {
      CrmTimeOfDay.earlyMorning => 'おはようございます',
      CrmTimeOfDay.midday => 'こんにちは',
      CrmTimeOfDay.afternoon => 'こんにちは',
      CrmTimeOfDay.evening => 'こんばんは',
    };

/// Closing メッセージ。
/// `remainingUrgent` は残りの今すぐ対応件数、`tomorrowCount` は翌日予定件数。
String crmClosingMessage({
  required CrmTimeOfDay tod,
  required int remainingUrgent,
  required int tomorrowCount,
}) {
  if (remainingUrgent == 0) {
    return '本日分クリア。対応の流れがきれいに整いました';
  }
  return switch (tod) {
    CrmTimeOfDay.earlyMorning => 'あと $remainingUrgent 件で本日分クリア。まずは1件目から ☕',
    CrmTimeOfDay.midday => 'あと $remainingUrgent 件 / 無理のない範囲で ☺︎',
    CrmTimeOfDay.afternoon => 'あと $remainingUrgent 件 / 今日はここまで進みました',
    CrmTimeOfDay.evening =>
      'お疲れさまでした。明日の優先は $tomorrowCount 件です',
  };
}

// ---------------------------------------------------------- 集計サマリ

class CrmHomeSummary {
  final int urgentTotal;
  final int overdueCount;
  final int trialFollowupMissing;
  final int contractStalled;
  final int noNextAction;

  final int todayReplyDue;
  final int todayTrialScheduling;
  final int todayAlmostContract;
  final int todayAssigneeMissing;

  const CrmHomeSummary({
    required this.urgentTotal,
    required this.overdueCount,
    required this.trialFollowupMissing,
    required this.contractStalled,
    required this.noNextAction,
    required this.todayReplyDue,
    required this.todayTrialScheduling,
    required this.todayAlmostContract,
    required this.todayAssigneeMissing,
  });

  bool get isAllClear => urgentTotal == 0;
}

/// リード群からホーム用サマリを計算する。
CrmHomeSummary summarizeForHome(Iterable<CrmLead> leads, {DateTime? now}) {
  int overdue = 0, trialMiss = 0, stalled = 0, noNext = 0;
  int reply = 0, trial = 0, almost = 0, assignee = 0;

  for (final lead in leads) {
    final reasons = urgentReasonsFor(lead, now: now);
    for (final r in reasons) {
      switch (r) {
        case CrmUrgentReason.overdue:
          overdue++;
        case CrmUrgentReason.trialFollowupMissing:
          trialMiss++;
        case CrmUrgentReason.contractStalled:
          stalled++;
        case CrmUrgentReason.noNextAction:
          noNext++;
      }
    }
    // todayCategoriesFor 側で urgent との重複制御を行うため、常に呼び出す。
    // almostContract は onboarding 全件に重複計上される（督促と両立しうる）。
    for (final c in todayCategoriesFor(lead, now: now)) {
      switch (c) {
        case CrmTodayCategory.replyDue:
          reply++;
        case CrmTodayCategory.trialScheduling:
          trial++;
        case CrmTodayCategory.almostContract:
          almost++;
        case CrmTodayCategory.assigneeMissing:
          assignee++;
      }
    }
  }

  return CrmHomeSummary(
    urgentTotal: overdue + trialMiss + stalled + noNext,
    overdueCount: overdue,
    trialFollowupMissing: trialMiss,
    contractStalled: stalled,
    noNextAction: noNext,
    todayReplyDue: reply,
    todayTrialScheduling: trial,
    todayAlmostContract: almost,
    todayAssigneeMissing: assignee,
  );
}

/// Urgent List に表示する行データ
class CrmUrgentRow {
  final CrmLead lead;
  final List<CrmUrgentReason> reasons;
  const CrmUrgentRow({required this.lead, required this.reasons});

  /// 督促理由なしの Lead（次の一手設定済みなど）でも CrmUrgentRow を作る場合があるため
  /// nullable にする。
  CrmUrgentReason? get topReason => reasons.isEmpty
      ? null
      : reasons.reduce(
          (a, b) => urgentPriority(a) <= urgentPriority(b) ? a : b);
}

/// Urgent List 生成（優先度順）
List<CrmUrgentRow> buildUrgentRows(Iterable<CrmLead> leads, {DateTime? now}) {
  final rows = <CrmUrgentRow>[];
  for (final lead in leads) {
    final reasons = urgentReasonsFor(lead, now: now);
    if (reasons.isEmpty) continue;
    rows.add(CrmUrgentRow(lead: lead, reasons: reasons));
  }
  rows.sort((a, b) {
    // buildUrgentRows は reasons 非空のみ追加するため topReason は必ず非null
    final pa = urgentPriority(a.topReason!);
    final pb = urgentPriority(b.topReason!);
    if (pa != pb) return pa.compareTo(pb);
    // 同じ理由内では最終接触が古い順
    final la = a.lead.lastContactAt ?? a.lead.inquiredAt;
    final lb = b.lead.lastContactAt ?? b.lead.inquiredAt;
    if (la == null && lb == null) return 0;
    if (la == null) return 1;
    if (lb == null) return -1;
    return la.compareTo(lb);
  });
  return rows;
}

/// 相対時間表記（日本語、短縮）
String crmRelativeTime(DateTime? dt, {DateTime? now}) {
  if (dt == null) return '—';
  final ref = now ?? DateTime.now();
  final diff = ref.difference(dt);
  if (diff.isNegative) {
    final d = -diff.inMinutes;
    if (d < 60) return 'あと$d分';
    if (d < 60 * 24) return 'あと${(d / 60).floor()}時間';
    return 'あと${(d / (60 * 24)).floor()}日';
  }
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  if (diff.inDays < 7) return '${diff.inDays}日前';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}週間前';
  return '${(diff.inDays / 30).floor()}ヶ月前';
}
