import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/crm_lead_adapter.dart';
import 'crm_home_utils.dart';
import 'crm_lead_card_compact.dart';
import 'crm_lead_model.dart';
import 'crm_lead_side_panel.dart';

/// 「今日整えたいこと」カードで使う柔らかめのアンバー。
/// `context.alerts.warning` より彩度を落とし、赤みを抑えたトーンにする。
/// 責める UI を避けるため、主要カードは専用トーンを使う。
class _SoftAmber {
  final Color background;
  final Color border;
  final Color text;
  final Color icon;
  const _SoftAmber({
    required this.background,
    required this.border,
    required this.text,
    required this.icon,
  });

  static _SoftAmber of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const _SoftAmber(
            background: Color(0xFF2C2519),
            border: Color(0xFFFFCC80),
            text: Color(0xFFFFE0B2),
            icon: Color(0xFFFFB74D),
          )
        : const _SoftAmber(
            background: Color(0xFFFFF6E5),
            border: Color(0xFFFFCC80),
            text: Color(0xFF5D4037),
            icon: Color(0xFFF57C00),
          );
  }
}

/// 新 CRM ホーム（入会グロース司令塔）。
/// Phase 2: Greeting / Top Cards / Urgent List / Closing の骨格を提供する。
/// サイドパネル（リード作業パネル）は Phase 3 で追加。
/// 行クリック時は `onOpenLead` を呼び出し、呼び出し側で詳細画面を開く。
class CrmHomeScreen extends StatefulWidget {
  final List<LeadView> docs;

  const CrmHomeScreen({super.key, required this.docs});

  @override
  State<CrmHomeScreen> createState() => _CrmHomeScreenState();
}

class _CrmHomeScreenState extends State<CrmHomeScreen> {
  /// 3 ペイン化の breakpoint。spec 準拠（旧 1100 から引き上げ）。
  static const double _kThreePaneBreakpoint = 1280;

  /// Urgent List の絞り込み（null=全件）
  CrmUrgentReason? _filter;

  /// 右サイドパネルで開いているリードの id。
  /// 2 ペイン常時表示モードでは初期表示時にリスト先頭を自動選択する。
  /// session 内のみ保持（リロードで先頭に戻る）。
  String? _selectedLeadId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final wide = cons.maxWidth >= _kThreePaneBreakpoint;

      // urgentRows / filteredRows をここで先に計算し、自動選択判定に使う。
      final now = DateTime.now();
      final docById = {for (final d in widget.docs) d.id: d};
      final leads = widget.docs.map(CrmLead.fromDoc).toList();
      final urgentRows = buildUrgentRows(leads, now: now);
      final filteredRows = _filter == null
          ? urgentRows
          : urgentRows.where((r) => r.reasons.contains(_filter)).toList();

      // 自動選択ロジック: 選択中 Lead が現在のフィルタ済みリストに無ければ
      // 先頭を自動選択（フィルタ chip タップ時 / 初期表示時 / 削除後）。
      String? effectiveSelectedId = _selectedLeadId;
      if (filteredRows.isNotEmpty) {
        final ids = filteredRows.map((r) => r.lead.id).toSet();
        if (effectiveSelectedId == null ||
            !ids.contains(effectiveSelectedId)) {
          effectiveSelectedId = filteredRows.first.lead.id;
          // build 中の setState は禁止のため次フレームで反映。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_selectedLeadId != effectiveSelectedId) {
              setState(() => _selectedLeadId = effectiveSelectedId);
            }
          });
        }
      }

      final selectedDoc = effectiveSelectedId == null
          ? null
          : docById[effectiveSelectedId];

      final home = _buildHome(
        context,
        leads: leads,
        urgentRows: urgentRows,
        filteredRows: filteredRows,
        now: now,
        selectedLeadId: effectiveSelectedId,
        onSelectLead: (id) => setState(() => _selectedLeadId = id),
      );

      if (!wide) {
        // 1280px 未満は従来のスライドオーバー方式（ホームのみ表示、
        // 詳細はカードタップ時にフルスクリーンで開く）。
        if (selectedDoc == null || _selectedLeadId == null) return home;
        return CrmLeadSidePanel(
          leadView: selectedDoc,
          onClose: () => setState(() => _selectedLeadId = null),
        );
      }

      // 2 ペイン常時表示。中央 45% / 右 55%（Flexible で伸縮可）。
      return Row(
        children: [
          Flexible(flex: 45, child: home),
          Flexible(
            flex: 55,
            child: selectedDoc == null
                ? _emptyDetailPlaceholder(context)
                : CrmLeadSidePanel(
                    // 常時表示なので閉じるボタン非表示（onClose=null）。
                    leadView: selectedDoc,
                  ),
          ),
        ],
      );
    });
  }

  Widget _emptyDetailPlaceholder(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.scaffoldBg,
      child: Center(
        child: Text(
          '今日整えたいリードはありません',
          style: TextStyle(color: c.textSecondary, fontSize: AppTextSize.body),
        ),
      ),
    );
  }

  Widget _buildHome(
    BuildContext context, {
    required List<CrmLead> leads,
    required List<CrmUrgentRow> urgentRows,
    required List<CrmUrgentRow> filteredRows,
    required DateTime now,
    required String? selectedLeadId,
    required ValueChanged<String> onSelectLead,
  }) {
    final tod = crmTimeOfDay(now);
    final summary = summarizeForHome(leads, now: now);
    final uniqueLeadCount = urgentRows.length;
    // 理由件数の合計は重複（1リードに複数理由）を含むため、ユニーク数より大きくなりうる。

    final monthly = _calcMonthly(leads, now);
    final userName = _currentUserName();

    // Step 1 (F_today_tab_polish): スクロール領域分離。
    // Greeting / TopCards / ClosingBanner は固定、中央リストだけ内部スクロール。
    return Container(
      color: context.colors.scaffoldBg,
      child: LayoutBuilder(builder: (context, cons) {
        // 上部セクション(Greeting + TopCards)は最大でも viewport 高さの 60% までに制限。
        // それを超える場合は内部スクロール。中央リストは残りの高さを Expanded で確保。
        final topMaxH = cons.maxHeight * 0.60;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: topMaxH),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Greeting(
                      userName: userName,
                      urgentLeadCount: uniqueLeadCount,
                      almostContractCount: summary.todayAlmostContract,
                      tod: tod,
                    ),
                    const SizedBox(height: 12),
                    _TopCardsRow(
                      summary: summary,
                      uniqueLeadCount: uniqueLeadCount,
                      monthly: monthly,
                      activeFilter: _filter,
                      onTapFilter: (f) => setState(() {
                        _filter = _filter == f ? null : f;
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _UrgentSection(
                  rows: filteredRows,
                  totalLeadCount: urgentRows.length,
                  totalObservations: summary.urgentTotal,
                  activeFilter: _filter,
                  onClearFilter: () => setState(() => _filter = null),
                  selectedLeadId: selectedLeadId,
                  onSelectLead: onSelectLead,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _ClosingBanner(
                remainingUrgent: summary.urgentTotal,
                tomorrowCount: _calcTomorrow(leads, now),
                tod: tod,
              ),
            ),
          ],
        );
      }),
    );
  }

  ({int enrolled, int goal, int inquired, int trial}) _calcMonthly(
      List<CrmLead> leads, DateTime now) {
    final monthStart = DateTime(now.year, now.month, 1);
    var enrolled = 0, inquired = 0, trial = 0;
    for (final l in leads) {
      final e = l.enrolledAt;
      if (e != null && !e.isBefore(monthStart) && e.isBefore(now)) {
        enrolled++;
      }
      final iq = l.inquiredAt;
      if (iq != null && !iq.isBefore(monthStart) && iq.isBefore(now)) {
        inquired++;
      }
      final t = l.trialAt;
      if (t != null && !t.isBefore(monthStart) && t.isBefore(now)) {
        trial++;
      }
    }
    // 目標値は未実装。暫定で 10 固定。設定機能は別フェーズ。
    return (enrolled: enrolled, goal: 10, inquired: inquired, trial: trial);
  }

  int _calcTomorrow(List<CrmLead> leads, DateTime now) {
    final t = DateTime(now.year, now.month, now.day + 1);
    var count = 0;
    for (final l in leads) {
      if (l.isClosed) continue;
      final n = l.nextActionAt;
      if (n != null &&
          n.year == t.year &&
          n.month == t.month &&
          n.day == t.day) {
        count++;
      }
    }
    return count;
  }

  String _currentUserName() {
    final u = FirebaseAuth.instance.currentUser;
    final n = u?.displayName;
    if (n != null && n.trim().isNotEmpty) return n;
    final e = u?.email;
    if (e != null && e.contains('@')) return e.split('@').first;
    return '管理者';
  }
}

// ---------------------------------------------------------- Greeting

class _Greeting extends StatelessWidget {
  final String userName;
  final int urgentLeadCount;
  final int almostContractCount;
  final CrmTimeOfDay tod;
  const _Greeting({
    required this.userName,
    required this.urgentLeadCount,
    required this.almostContractCount,
    required this.tod,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hello = crmHelloPrefix(tod);
    final suffix = crmGreetingSuffix(tod);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$hello、$userNameさん。',
            style: TextStyle(
              fontSize: AppTextSize.title,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '今日整えたいのは $urgentLeadCount 人、契約あと一歩は $almostContractCount 人です。$suffix。',
            style:
                TextStyle(fontSize: AppTextSize.body, color: c.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Top Cards

class _TopCardsRow extends StatelessWidget {
  final CrmHomeSummary summary;
  final int uniqueLeadCount;
  final ({int enrolled, int goal, int inquired, int trial}) monthly;
  final CrmUrgentReason? activeFilter;
  final ValueChanged<CrmUrgentReason> onTapFilter;

  const _TopCardsRow({
    required this.summary,
    required this.uniqueLeadCount,
    required this.monthly,
    required this.activeFilter,
    required this.onTapFilter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final isWide = cons.maxWidth >= 900;
      final urgent = _UrgentMainCard(
        summary: summary,
        uniqueLeadCount: uniqueLeadCount,
        activeFilter: activeFilter,
        onTapFilter: onTapFilter,
      );
      final today = _TodayCard(summary: summary);
      final monthlyCard = _MonthlyCard(
        enrolled: monthly.enrolled,
        goal: monthly.goal,
        inquired: monthly.inquired,
        trial: monthly.trial,
      );
      final insight = _InsightCard(summary: summary);

      if (!isWide) {
        return Column(
          children: [
            urgent,
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: today),
              const SizedBox(width: 12),
              Expanded(child: monthlyCard),
            ]),
            const SizedBox(height: 12),
            insight,
          ],
        );
      }

      // 6 : 2 : 2 : 2 比率
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 6, child: urgent),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: today),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: monthlyCard),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: insight),
          ],
        ),
      );
    });
  }
}

class _UrgentMainCard extends StatelessWidget {
  final CrmHomeSummary summary;
  final int uniqueLeadCount;
  final CrmUrgentReason? activeFilter;
  final ValueChanged<CrmUrgentReason> onTapFilter;

  const _UrgentMainCard({
    required this.summary,
    required this.uniqueLeadCount,
    required this.activeFilter,
    required this.onTapFilter,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isAllClear) {
      final s = context.alerts.success;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.border.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.spa, color: s.icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本日のやること完了 🌱',
                      style: TextStyle(
                          fontSize: AppTextSize.titleLg,
                          fontWeight: FontWeight.w700,
                          color: s.text)),
                  const SizedBox(height: 4),
                  Text('新しい気づきがあれば、ここに浮上します',
                      style: TextStyle(fontSize: AppTextSize.small, color: s.text)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final a = _SoftAmber.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: a.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: a.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.wb_twilight, color: a.icon, size: 22),
              const SizedBox(width: 8),
              Text('今日整えたいこと',
                  style: TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w700,
                      color: a.text)),
              const Spacer(),
              Text('$uniqueLeadCount',
                  style: TextStyle(
                      fontSize: AppTextSize.heroLg2,
                      fontWeight: FontWeight.w800,
                      color: a.icon,
                      height: 1.0)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text('人',
                    style: TextStyle(fontSize: AppTextSize.small, color: a.text)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '確認ポイントは合計 ${summary.urgentTotal} 件（同じリードで複数該当する場合があります）',
            style: TextStyle(
                fontSize: AppTextSize.caption,
                color: a.text.withValues(alpha: 0.75),
                height: 1.4),
          ),
          const SizedBox(height: 10),
          _breakdownRow(
            context,
            icon: Icons.schedule,
            label: '期限切れ',
            count: summary.overdueCount,
            reason: CrmUrgentReason.overdue,
            textColor: a.text,
          ),
          _breakdownRow(
            context,
            icon: Icons.assignment_late_outlined,
            label: '体験後のフォローがまだ',
            count: summary.trialFollowupMissing,
            reason: CrmUrgentReason.trialFollowupMissing,
            textColor: a.text,
          ),
          _breakdownRow(
            context,
            icon: Icons.hourglass_bottom,
            label: '契約が少し止まっている',
            count: summary.contractStalled,
            reason: CrmUrgentReason.contractStalled,
            textColor: a.text,
          ),
          _breakdownRow(
            context,
            icon: Icons.more_horiz,
            label: '次の一手を決める',
            count: summary.noNextAction,
            reason: CrmUrgentReason.noNextAction,
            textColor: a.text,
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
    required CrmUrgentReason reason,
    required Color textColor,
  }) {
    final active = activeFilter == reason;
    return InkWell(
      onTap: count == 0 ? null : () => onTapFilter(reason),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: textColor.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: textColor,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text('$count',
                style: TextStyle(
                  fontSize: AppTextSize.titleSm,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                )),
            const SizedBox(width: 2),
            Text('件',
                style: TextStyle(fontSize: AppTextSize.caption, color: textColor.withValues(alpha: 0.7))),
            const SizedBox(width: 6),
            Icon(active ? Icons.filter_alt : Icons.chevron_right,
                size: 16, color: textColor.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final CrmHomeSummary summary;
  const _TodayCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.alerts.info;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 18, color: s.icon),
              const SizedBox(width: 6),
              Text('今日進めると良い',
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          _row(context, '返信待ち', summary.todayReplyDue),
          _row(context, '見学日程調整', summary.todayTrialScheduling),
          _row(context, '契約あと一歩', summary.todayAlmostContract),
          _row(context, '担当を決める', summary.todayAssigneeMissing),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, int count) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: AppTextSize.small, color: c.textSecondary))),
          Text('$count',
              style: TextStyle(
                  fontSize: AppTextSize.titleSm,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary)),
          const SizedBox(width: 2),
          Text('人',
              style: TextStyle(fontSize: AppTextSize.xs, color: c.textTertiary)),
        ],
      ),
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  final int enrolled;
  final int goal;
  final int inquired;
  final int trial;
  const _MonthlyCard({
    required this.enrolled,
    required this.goal,
    required this.inquired,
    required this.trial,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ratio = goal == 0 ? 0.0 : (enrolled / goal).clamp(0.0, 1.2);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌸', style: TextStyle(fontSize: AppTextSize.titleSm)),
              const SizedBox(width: 6),
              Text('今月の歩み',
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$enrolled',
                  style: TextStyle(
                      fontSize: AppTextSize.hero,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      height: 1.0)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('/ $goal 人 入会',
                    style:
                        TextStyle(fontSize: AppTextSize.small, color: c.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: c.borderLight,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFFF9A8B)),
            ),
          ),
          const SizedBox(height: 10),
          _subRow(context, '問い合わせ', inquired),
          _subRow(context, '体験実施', trial),
        ],
      ),
    );
  }

  Widget _subRow(BuildContext context, String label, int count) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: AppTextSize.caption, color: c.textTertiary))),
          Text('$count',
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary)),
          const SizedBox(width: 2),
          Text('人',
              style: TextStyle(fontSize: AppTextSize.xs, color: c.textTertiary)),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final CrmHomeSummary summary;
  const _InsightCard({required this.summary});

  /// 優先度順に気づき候補を並べ、最初の1本を表示する。
  /// ルールベース検知（Phase 4 の insights コレクション連携）の前段として、
  /// 手元サマリから即座に出せる気づきを返す。
  ({String text, String? action})? _pickInsight() {
    if (summary.todayAssigneeMissing >= 5) {
      return (
        text: '担当未設定のリードが ${summary.todayAssigneeMissing} 人います。'
            '誰が持つかを決めると、対応が動きやすくなります。',
        action: '担当を決める'
      );
    }
    if (summary.contractStalled >= 3) {
      return (
        text: '入会手続き中で止まっているリードが ${summary.contractStalled} 件あります。'
            '停滞理由の確認がおすすめです。',
        action: null,
      );
    }
    if (summary.trialFollowupMissing >= 3) {
      return (
        text: '体験後のフォローがまだのリードが ${summary.trialFollowupMissing} 件。'
            '温度感が下がる前に接触したい時期です。',
        action: null,
      );
    }
    if (summary.noNextAction >= 5) {
      return (
        text: '次の一手が未設定のリードが ${summary.noNextAction} 件。'
            '先の動きが見えると、対応が迷わなくなります。',
        action: null,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insight = _pickInsight();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 18, color: context.alerts.info.icon),
              const SizedBox(width: 6),
              Text('気づき',
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          if (insight == null)
            Text(
              '今日の気づきは特にありません',
              style:
                  TextStyle(fontSize: AppTextSize.small, color: c.textTertiary, height: 1.5),
            )
          else ...[
            Text(
              insight.text,
              style: TextStyle(
                  fontSize: AppTextSize.small, color: c.textPrimary, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Urgent List

class _UrgentSection extends StatelessWidget {
  final List<CrmUrgentRow> rows;
  final int totalLeadCount;
  final int totalObservations;
  final CrmUrgentReason? activeFilter;
  final VoidCallback onClearFilter;
  final String? selectedLeadId;
  final ValueChanged<String> onSelectLead;

  const _UrgentSection({
    required this.rows,
    required this.totalLeadCount,
    required this.totalObservations,
    required this.activeFilter,
    required this.onClearFilter,
    required this.selectedLeadId,
    required this.onSelectLead,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('今日整えたいリード',
                style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(width: 8),
            if (activeFilter != null) ...[
              _filterChip(
                context,
                label: crmUrgentReasonLabel(activeFilter!),
                onClear: onClearFilter,
              ),
            ],
            const Spacer(),
            Text(
              activeFilter == null
                  ? '$totalLeadCount人 / $totalObservations件の確認ポイント'
                  : '絞り込み中 ${rows.length}人 / 全 $totalLeadCount人',
              style:
                  TextStyle(fontSize: AppTextSize.small, color: c.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Step 1 (F_today_tab_polish): リストだけ独立スクロール。
        // 親 (_buildHome) で Expanded > _UrgentSection の構成のため、
        // 内部の Expanded > ListView.builder で残り高さを使い切る。
        Expanded(
          child: rows.isEmpty
              ? _emptyState(context)
              : Container(
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.borderLight),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return CrmLeadCardCompact(
                        row: r,
                        selected: r.lead.id == selectedLeadId,
                        onTap: () => onSelectLead(r.lead.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(BuildContext context,
      {required String label, required VoidCallback onClear}) {
    final s = context.alerts.info;
    return InkWell(
      onTap: onClear,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: s.text,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.close, size: 12, color: s.icon),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 40, color: c.textTertiary),
          const SizedBox(height: 8),
          Text(
            activeFilter != null
                ? '該当するリードはありません'
                : '今すぐ対応するリードはありません',
            style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Closing

class _ClosingBanner extends StatelessWidget {
  final int remainingUrgent;
  final int tomorrowCount;
  final CrmTimeOfDay tod;
  const _ClosingBanner({
    required this.remainingUrgent,
    required this.tomorrowCount,
    required this.tod,
  });

  @override
  Widget build(BuildContext context) {
    final msg = crmClosingMessage(
      tod: tod,
      remainingUrgent: remainingUrgent,
      tomorrowCount: tomorrowCount,
    );
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.local_cafe_outlined, size: 18, color: c.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    fontSize: AppTextSize.body, color: c.textSecondary, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
