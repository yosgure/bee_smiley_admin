import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/crm_lead_adapter.dart';
import 'crm_home_utils.dart';
import 'crm_lead_card_compact.dart';
import 'crm_lead_model.dart';
import 'crm_lead_side_panel.dart';

/// CRM「今日」タブのトップレベル画面。
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

  /// ステージタブ。F_today_tab_polish_v2 改善 C で追加。
  /// 'all' / 'considering' / 'onboarding'。デフォルト 'all'。
  String _stageTab = 'all';

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
      // _filter (chip) と _stageTab (タブ) の AND フィルタ。
      final filteredRows = urgentRows.where((r) {
        if (_filter != null && !r.reasons.contains(_filter)) return false;
        if (_stageTab != 'all' && r.lead.stage != _stageTab) return false;
        return true;
      }).toList();
      // 各ステージの件数（タブのバッジ用）。
      final consideringCount =
          urgentRows.where((r) => r.lead.stage == 'considering').length;
      final onboardingCount =
          urgentRows.where((r) => r.lead.stage == 'onboarding').length;

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
        consideringCount: consideringCount,
        onboardingCount: onboardingCount,
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
    required int consideringCount,
    required int onboardingCount,
    required DateTime now,
    required String? selectedLeadId,
    required ValueChanged<String> onSelectLead,
  }) {
    final tod = crmTimeOfDay(now);
    final summary = summarizeForHome(leads, now: now);
    final uniqueLeadCount = urgentRows.length;
    final monthly = _calcMonthly(leads, now);

    // F_today_tab_polish_v2: 改善 A (挨拶削除) + B (4 カード→1 行) + C (タブ統合)。
    return Container(
      color: context.colors.scaffoldBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _TodaySummaryStrip(
              uniqueLeadCount: uniqueLeadCount,
              consideringCount: consideringCount,
              onboardingCount: onboardingCount,
              activeStageTab: _stageTab,
              onStageTabChanged: (v) => setState(() => _stageTab = v),
              activeFilter: _filter,
              onTapFilter: (f) => setState(() {
                _filter = _filter == f ? null : f;
              }),
              summary: summary,
              monthly: monthly,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _ClosingBanner(
              remainingUrgent: summary.urgentTotal,
              tomorrowCount: _calcTomorrow(leads, now),
              tod: tod,
            ),
          ),
        ],
      ),
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

}

// ---------------------------------------------------------- Today Summary Strip

/// F_today_tab_polish_v2 改善 B+C: 旧 4 カードを 1 行のストリップに統合。
/// 左: ステージタブ（検討中/入会手続中/全て）
/// 中央: 今日の確認ポイント（期限切れ/フォロー漏れ/停滞/次の手）— タップで filter chip と同じ挙動
/// 右: 今月入会 + 気づき件数（読み取り専用）
class _TodaySummaryStrip extends StatelessWidget {
  final int uniqueLeadCount;
  final int consideringCount;
  final int onboardingCount;
  final String activeStageTab;
  final ValueChanged<String> onStageTabChanged;
  final CrmUrgentReason? activeFilter;
  final ValueChanged<CrmUrgentReason> onTapFilter;
  final CrmHomeSummary summary;
  final ({int enrolled, int goal, int inquired, int trial}) monthly;

  const _TodaySummaryStrip({
    required this.uniqueLeadCount,
    required this.consideringCount,
    required this.onboardingCount,
    required this.activeStageTab,
    required this.onStageTabChanged,
    required this.activeFilter,
    required this.onTapFilter,
    required this.summary,
    required this.monthly,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // ステージタブ
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: 'considering',
                    label: Text('検討中 ($consideringCount)')),
                ButtonSegment(
                    value: 'onboarding',
                    label: Text('入会手続中 ($onboardingCount)')),
                ButtonSegment(
                    value: 'all',
                    label: Text('全て ($uniqueLeadCount)')),
              ],
              selected: {activeStageTab},
              onSelectionChanged: (s) => onStageTabChanged(s.first),
              style: ButtonStyle(
                textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: AppTextSize.small)),
                padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 16),
            _separator(c),
            const SizedBox(width: 12),
            // 今日の確認ポイント — タップで filter
            _reasonCount(context, '期限切れ', summary.overdueCount,
                CrmUrgentReason.overdue),
            const SizedBox(width: 8),
            _reasonCount(context, 'フォロー漏れ',
                summary.trialFollowupMissing,
                CrmUrgentReason.trialFollowupMissing),
            const SizedBox(width: 8),
            _reasonCount(context, '停滞', summary.contractStalled,
                CrmUrgentReason.contractStalled),
            const SizedBox(width: 8),
            _reasonCount(context, '次の手', summary.noNextAction,
                CrmUrgentReason.noNextAction),
            const SizedBox(width: 12),
            _separator(c),
            const SizedBox(width: 12),
            // 今月 N/M 入会
            _readonlyMetric(
                context, '今月', '${monthly.enrolled}/${monthly.goal} 入会'),
            const SizedBox(width: 12),
            _separator(c),
            const SizedBox(width: 12),
            // 気づき件数（暫定: 担当未設定など簡易ルール）
            _readonlyMetric(context, '気づき',
                '${summary.todayAssigneeMissing > 0 ? 1 : 0} 件'),
          ],
        ),
      ),
    );
  }

  Widget _separator(AppColorScheme c) =>
      Container(width: 1, height: 22, color: c.borderLight);

  Widget _reasonCount(BuildContext context, String label, int count,
      CrmUrgentReason reason) {
    final c = context.colors;
    final selected = activeFilter == reason;
    final base = c.scaffoldBgAlt;
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.15) : base,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => onTapFilter(reason),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textSecondary)),
              const SizedBox(width: 4),
              Text('$count',
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.bold,
                      color: selected
                          ? AppColors.primary
                          : c.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readonlyMetric(BuildContext context, String label, String value) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: AppTextSize.caption, color: c.textSecondary)),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w600,
                color: c.textPrimary)),
      ],
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
