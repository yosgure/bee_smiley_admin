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
      // 表示対象: 検討中 + 入会手続中（won/lost/withdrawn は除外）。
      // 旧実装は urgent reason 必須だったが、次の一手を設定すると即座にリストから
      // 消えるバグになっていたため、active な全 Lead を表示対象にする。
      final activeLeads = leads
          .where((l) =>
              l.stage == 'considering' || l.stage == 'onboarding')
          .toList();
      final urgentRows = buildUrgentRows(activeLeads, now: now);
      final urgentById = {for (final r in urgentRows) r.lead.id: r};
      // 全 active を CrmUrgentRow に変換（reasons 無しは空配列）
      final allRows = activeLeads
          .map((l) => urgentById[l.id] ?? CrmUrgentRow(lead: l, reasons: const []))
          .toList();
      // ステージタブのみフィルタ。督促理由カテゴリのフィルタ・ソートは廃止
      // （体験フォロー漏れ・契約停滞・次の一手未設定 は実質「次の一手未設定」と同義
      //  であり、絞り込む必要なし。期日昇順ソートで自然に上に来る）。
      final filteredRows = allRows.where((r) {
        if (_stageTab != 'all' && r.lead.stage != _stageTab) return false;
        return true;
      }).toList()
        // 期日昇順（期限超過 → 直近 → 未設定 の順）。
        ..sort((a, b) {
          final aNa = a.lead.nextActionAt;
          final bNa = b.lead.nextActionAt;
          if (aNa == null && bNa == null) return 0;
          if (aNa == null) return 1;
          if (bNa == null) return -1;
          return aNa.compareTo(bNa);
        });
      // バッジ件数: ステージ別の active 全件
      final consideringCount =
          activeLeads.where((l) => l.stage == 'considering').length;
      final onboardingCount =
          activeLeads.where((l) => l.stage == 'onboarding').length;

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
        activeLeadCount: activeLeads.length,
        consideringCount: consideringCount,
        onboardingCount: onboardingCount,
        now: now,
        selectedLeadId: effectiveSelectedId,
        onSelectLead: (id) {
          setState(() => _selectedLeadId = id);
          // 明示クリック時のみ NEW バッジを既読化（自動先頭選択では消えない）。
          docById[id]?.markRead();
        },
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

      // 2 ペイン常時表示。リスト 33% / 詳細 67%（v3.1: 詳細を広く取る）
      return Row(
        children: [
          Flexible(flex: 33, child: home),
          Flexible(
            flex: 67,
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
    required int activeLeadCount,
    required int consideringCount,
    required int onboardingCount,
    required DateTime now,
    required String? selectedLeadId,
    required ValueChanged<String> onSelectLead,
  }) {
    final summary = summarizeForHome(leads, now: now);
    // ストリップの「全て (N)」バッジは active 全件を表示。
    final uniqueLeadCount = activeLeadCount;
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
                activeFilter: _filter,
                onClearFilter: () => setState(() => _filter = null),
                selectedLeadId: selectedLeadId,
                onSelectLead: onSelectLead,
              ),
            ),
          ),
          // v3.4: 「あと N 件 / 今日はここまで」のクロージングバナーは削除（ノイズ）
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StageTab(
              label: '全て',
              count: uniqueLeadCount,
              selected: activeStageTab == 'all',
              onTap: () => onStageTabChanged('all'),
            ),
            const SizedBox(width: 8),
            _StageTab(
              label: '検討中',
              count: consideringCount,
              selected: activeStageTab == 'considering',
              onTap: () => onStageTabChanged('considering'),
            ),
            const SizedBox(width: 8),
            _StageTab(
              label: '入会手続中',
              count: onboardingCount,
              selected: activeStageTab == 'onboarding',
              onTap: () => onStageTabChanged('onboarding'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 軽量タブ。選択時のみ淡色背景。未選択は素のテキスト。
class _StageTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _StageTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: AppTextSize.small,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : c.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: selected ? AppColors.primary : c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- Urgent List

class _UrgentSection extends StatelessWidget {
  final List<CrmUrgentRow> rows;
  final CrmUrgentReason? activeFilter;
  final VoidCallback onClearFilter;
  final String? selectedLeadId;
  final ValueChanged<String> onSelectLead;

  const _UrgentSection({
    required this.rows,
    required this.activeFilter,
    required this.onClearFilter,
    required this.selectedLeadId,
    required this.onSelectLead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (activeFilter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                _filterChip(
                  context,
                  label: crmUrgentReasonLabel(activeFilter!),
                  onClear: onClearFilter,
                ),
              ],
            ),
          ),
        if (rows.isNotEmpty) _columnHeader(context),
        Expanded(
          child: rows.isEmpty
              ? _emptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 2),
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
      ],
    );
  }

  Widget _columnHeader(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      fontSize: AppTextSize.xs,
      fontWeight: FontWeight.w600,
      color: c.textTertiary,
      letterSpacing: 0.3,
    );
    // カード内レイアウトと同じ flex / width で揃える
    // 左 5px (ステータスバー) + 10px (内側パディング) = 15px インデント
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 4, 10, 6),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('名前', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 6, child: Text('次のアクション', style: style)),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text('期日', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
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

