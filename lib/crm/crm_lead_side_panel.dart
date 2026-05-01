import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../widgets/app_feedback.dart';
import '../crm_lead_screen.dart' show CrmOptions, CrmLeadEditScreen;
import 'crm_home_utils.dart';
import 'crm_lead_model.dart';
import 'crm_next_action.dart';

/// リード作業サイドパネル（Phase 3）。
///
/// ホームで見ていた文脈（期限切れ・次の一手・最終接触）をパネル上部に
/// 引き継ぎ、管理者がホームから目を離さず「書き込める」ワークスペースを提供する。
/// 幅は標準 560px。Esc または × で閉じる。
///
/// ドキュメントは DocumentReference 経由で stream 購読し、保存後に即時再描画。
class CrmLeadSidePanel extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> leadRef;
  final VoidCallback onClose;

  const CrmLeadSidePanel({
    super.key,
    required this.leadRef,
    required this.onClose,
  });

  @override
  State<CrmLeadSidePanel> createState() => _CrmLeadSidePanelState();
}

class _CrmLeadSidePanelState extends State<CrmLeadSidePanel> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KeyboardListener(
      focusNode: _focus,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      child: Material(
        color: c.scaffoldBg,
        elevation: 8,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.leadRef.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()));
            }
            if (!snap.data!.exists) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('リードが見つかりません',
                          style: TextStyle(color: c.textSecondary))));
            }
            final lead = CrmLead.fromSnapshot(snap.data!);
            return _Body(
              lead: lead,
              leadRef: widget.leadRef,
              onClose: widget.onClose,
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final CrmLead lead;
  final DocumentReference<Map<String, dynamic>> leadRef;
  final VoidCallback onClose;
  const _Body({
    required this.lead,
    required this.leadRef,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        _Header(lead: lead, onClose: onClose, leadRef: leadRef),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UrgentContextStrip(lead: lead),
                const SizedBox(height: 16),
                _NextActionBlock(lead: lead, leadRef: leadRef),
                const SizedBox(height: 20),
                _RecordForm(lead: lead, leadRef: leadRef),
                const SizedBox(height: 20),
                _HistorySection(lead: lead),
                const SizedBox(height: 20),
                _ChildInfoSection(lead: lead),
                const SizedBox(height: 12),
                _ParentInfoSection(lead: lead),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    // C-crm-1 でこのサイドパネル経路は一時的に無効化中
                    // （DocumentReference→LeadView ブリッジが未実装）。
                    // CRM画面側で _openLeadInPanel を Navigator.push に切替済み。
                    onPressed: null,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('詳細を編集'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      side: BorderSide(color: c.borderMedium),
                      textStyle: const TextStyle(fontSize: AppTextSize.small),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- Header

class _Header extends StatelessWidget {
  final CrmLead lead;
  final DocumentReference<Map<String, dynamic>> leadRef;
  final VoidCallback onClose;
  const _Header(
      {required this.lead, required this.leadRef, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        lead.childFullName.isEmpty
                            ? '（名前未登録）'
                            : lead.childFullName,
                        style: TextStyle(
                            fontSize: AppTextSize.title,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _stagePill(context, lead.stage),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${CrmOptions.labelOf(CrmOptions.sources, lead.source)}'
                  ' ・ 担当 ${lead.assigneeName ?? "未設定"}',
                  style:
                      TextStyle(fontSize: AppTextSize.caption, color: c.textTertiary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: c.textSecondary,
            tooltip: '閉じる (Esc)',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  Widget _stagePill(BuildContext context, String stage) {
    final color = CrmOptions.stageColor(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(CrmOptions.stageLabel(stage),
          style: TextStyle(
              fontSize: AppTextSize.xs, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

// ---------------------------------------------------------- 督促文脈バー

class _UrgentContextStrip extends StatelessWidget {
  final CrmLead lead;
  const _UrgentContextStrip({required this.lead});

  @override
  Widget build(BuildContext context) {
    final reasons = urgentReasonsFor(lead);
    final last = lead.lastContactAt ?? lead.inquiredAt;
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record,
              size: 10,
              color: reasons.isEmpty ? AppColors.successBorder : AppColors.warningBorder),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (reasons.isEmpty)
                  Text('督促はありません',
                      style: TextStyle(
                          fontSize: AppTextSize.small, color: c.textSecondary))
                else
                  ...reasons.map((r) => _reasonChip(context, r)),
                Text('最終接触 ${crmRelativeTime(last)}',
                    style: TextStyle(
                        fontSize: AppTextSize.caption, color: c.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reasonChip(BuildContext context, CrmUrgentReason r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFFCC80).withValues(alpha: 0.5)),
      ),
      child: Text(crmUrgentReasonLabel(r),
          style: const TextStyle(
              fontSize: AppTextSize.xs,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5D4037))),
    );
  }
}

// ---------------------------------------------------------- 次の一手

class _NextActionBlock extends StatelessWidget {
  final CrmLead lead;
  final DocumentReference<Map<String, dynamic>> leadRef;
  const _NextActionBlock({required this.lead, required this.leadRef});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasNext = lead.hasNextAction;
    final at = lead.nextActionAt;
    final note = lead.nextActionNote;
    final typeId = lead.nextActionType;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOverdue = at != null && at.isBefore(DateTime.now());

    // ダーク/ライトで浮かない落ち着いたアンバー
    final bg = hasNext
        ? (isDark ? const Color(0xFF2A2319) : const Color(0xFFFFF0D4))
        : c.cardBg;
    final borderC = hasNext
        ? const Color(0xFFFFB74D).withValues(alpha: 0.5)
        : c.borderLight;
    final amberText =
        isDark ? const Color(0xFFFFE0B2) : const Color(0xFF5D4037);
    final amberIcon =
        isDark ? const Color(0xFFFFB74D) : const Color(0xFFE67E22);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: amberIcon),
              const SizedBox(width: 6),
              Text('次の一手',
                  style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: FontWeight.w700,
                      color: hasNext ? amberText : c.textPrimary)),
              if (hasNext && isOverdue) ...[
                const SizedBox(width: 8),
                _statusTag(context,
                    label: '期限超過',
                    color: const Color(0xFFE67E22),
                    isDark: isDark),
              ] else if (hasNext && at != null) ...[
                const SizedBox(width: 8),
                _statusTag(context,
                    label: '次回予定',
                    color: const Color(0xFF1976D2),
                    isDark: isDark),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (hasNext) ...[
            if (at != null)
              Text(
                DateFormat('M/d (E) HH:mm', 'ja').format(at),
                style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.w700,
                    color: amberText),
              ),
            const SizedBox(height: 4),
            Text(
              [
                if (typeId != null) _typeLabel(typeId),
                if (note.isNotEmpty) note,
              ].where((s) => s.isNotEmpty).join(' / '),
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: amberText.withValues(alpha: 0.85)),
            ),
          ] else ...[
            Text(
              '次の一手がまだ決まっていません。\n決めると、ホームの「今日整えたいリード」に自然に並びます。',
              style: TextStyle(
                  fontSize: AppTextSize.small, color: c.textTertiary, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionBtn(
                context,
                icon: Icons.edit_note,
                label: '対応を記録',
                primary: true,
                onTap: () => _scrollToRecordForm(context),
              ),
              if (lead.parentTel.isNotEmpty)
                _actionBtn(
                  context,
                  icon: Icons.call,
                  label: '電話番号を確認',
                  onTap: () => _callPhone(context, lead.parentTel),
                ),
              _actionBtn(
                context,
                icon: Icons.event_outlined,
                label: '日程変更',
                onTap: () => _editSchedule(context, lead, leadRef),
              ),
              _actionBtn(
                context,
                icon: Icons.note_add_outlined,
                label: 'メモだけ残す',
                onTap: () => _quickMemo(context, lead, leadRef),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String id) {
    for (final t in crmNextActionTypes) {
      if (t.id == id) return t.label;
    }
    return id;
  }

  Widget _statusTag(BuildContext context,
      {required String label,
      required Color color,
      required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: AppTextSize.xs,
              fontWeight: FontWeight.w700,
              color: isDark ? color : color.withValues(alpha: 0.9))),
    );
  }

  Widget _actionBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final c = context.colors;
    return primary
        ? FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF57C00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(
                  fontSize: AppTextSize.small, fontWeight: FontWeight.w700),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textPrimary,
              side: BorderSide(color: c.borderMedium),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle: const TextStyle(
                  fontSize: AppTextSize.small, fontWeight: FontWeight.w600),
            ),
          );
  }

  void _scrollToRecordForm(BuildContext context) {
    // 記録フォームは下に置いてあるので、フォーカスを送るだけで十分。
    // 厳密なスクロールは将来対応。今は SnackBar で案内。
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('下の「対応を記録する」から記録してください'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _callPhone(BuildContext context, String tel) async {
    await Clipboard.setData(ClipboardData(text: tel));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('電話番号をクリップボードにコピー: $tel'),
            duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _editSchedule(
    BuildContext context,
    CrmLead lead,
    DocumentReference<Map<String, dynamic>> leadRef,
  ) async {
    final now = DateTime.now();
    final initial = lead.nextActionAt ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await leadRef.update({
      'nextActionAt': Timestamp.fromDate(dt),
      'updatedAt': Timestamp.now(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
    });
  }

  Future<void> _quickMemo(
    BuildContext context,
    CrmLead lead,
    DocumentReference<Map<String, dynamic>> leadRef,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メモだけ残す'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'メモ内容',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final body = controller.text.trim();
    if (body.isEmpty) return;
    final u = FirebaseAuth.instance.currentUser;
    final activity = CrmActivity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'memo',
      body: body,
      at: DateTime.now(),
      authorId: u?.uid,
      authorName: u?.displayName ?? u?.email ?? '',
    );
    await leadRef.update({
      'activities': FieldValue.arrayUnion([activity.toMap()]),
      'lastActivityAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'updatedBy': u?.uid ?? '',
    });
  }
}

// ---------------------------------------------------------- 記録フォーム

class _RecordForm extends StatefulWidget {
  final CrmLead lead;
  final DocumentReference<Map<String, dynamic>> leadRef;
  const _RecordForm({required this.lead, required this.leadRef});

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  bool _expanded = false;
  String _activityType = 'tel';
  String? _outcome;
  String? _feeling;
  String _memo = '';
  final TextEditingController _memoCtrl = TextEditingController();

  String? _nextPresetId;
  String? _nextTypeId;
  DateTime? _nextAt;

  bool _saving = false;

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  bool get _feelingRequired =>
      _outcome == 'reached' || _outcome == 'completed';
  bool get _canSave {
    if (_memo.trim().isEmpty) return false;
    if (_feelingRequired && _feeling == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Text('✏️', style: TextStyle(fontSize: AppTextSize.titleSm)),
                  const SizedBox(width: 6),
                  Text('対応を記録する',
                      style: TextStyle(
                          fontSize: AppTextSize.body,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary)),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, '種別'),
                  _segmented<String>(
                    items: CrmOptions.activityTypes
                        .map((t) => (id: t.id, label: t.label))
                        .toList(),
                    value: _activityType,
                    onChanged: (v) => setState(() => _activityType = v),
                  ),
                  const SizedBox(height: 10),
                  _label(context, '対応結果'),
                  _segmented<String?>(
                    items: crmOutcomes
                        .map<({String? id, String label})>(
                            (o) => (id: o.id, label: o.label))
                        .toList(),
                    value: _outcome,
                    onChanged: (v) => setState(() {
                      _outcome = v;
                      if (!_feelingRequired) _feeling = null;
                    }),
                  ),
                  if (_feelingRequired) ...[
                    const SizedBox(height: 10),
                    _label(context, '感触 *'),
                    _segmented<String?>(
                      items: crmFeelings
                          .map<({String? id, String label})>(
                              (f) => (id: f.id, label: '${f.emoji} ${f.label}'))
                          .toList(),
                      value: _feeling,
                      onChanged: (v) => setState(() => _feeling = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _label(context, 'メモ'),
                  TextField(
                    controller: _memoCtrl,
                    maxLines: 3,
                    onChanged: (v) => setState(() => _memo = v),
                    decoration: InputDecoration(
                      hintText: '話した内容、決まったこと、次の懸念など',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(10),
                      isDense: true,
                      hintStyle: TextStyle(
                          color: c.textTertiary, fontSize: AppTextSize.small),
                    ),
                    style: const TextStyle(fontSize: AppTextSize.body),
                  ),
                  const SizedBox(height: 14),
                  _label(context, '次の一手'),
                  _PresetPicker(
                    stage: widget.lead.stage,
                    feeling: _feeling ?? 'considering',
                    selectedId: _nextPresetId,
                    onSelected: (preset) => setState(() {
                      _nextPresetId = preset.id;
                      _nextTypeId = preset.typeId;
                      _nextAt = DateTime.now().add(preset.offsetFromNow);
                    }),
                    onCustom: () => setState(() {
                      _nextPresetId = 'custom';
                      _nextTypeId = 'custom';
                      _nextAt = DateTime.now().add(const Duration(days: 3));
                    }),
                  ),
                  if (_nextAt != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 14, color: c.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('M/d (E) HH:mm', 'ja').format(_nextAt!),
                          style: TextStyle(
                              fontSize: AppTextSize.small, color: c.textSecondary),
                        ),
                        TextButton(
                          onPressed: _pickNextDate,
                          child: const Text('日時変更',
                              style: TextStyle(fontSize: AppTextSize.caption)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _expanded = false),
                        child: const Text('閉じる'),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        onPressed: _canSave && !_saving ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 16),
                        label: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary)),
    );
  }

  Widget _segmented<T>({
    required List<({T id, String label})> items,
    required T value,
    required ValueChanged<T> onChanged,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((it) {
        final selected = it.id == value;
        return ChoiceChip(
          label: Text(it.label, style: const TextStyle(fontSize: AppTextSize.caption)),
          selected: selected,
          onSelected: (_) => onChanged(it.id),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }

  Future<void> _pickNextDate() async {
    final now = DateTime.now();
    final base = _nextAt ?? now.add(const Duration(days: 3));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;
    setState(() {
      _nextAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final u = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final activity = CrmActivity(
      id: now.millisecondsSinceEpoch.toString(),
      type: _activityType,
      body: _memo.trim(),
      at: now,
      authorId: u?.uid,
      authorName: u?.displayName ?? u?.email ?? '',
      outcome: _outcome,
      feeling: _feeling,
      nextPresetId: _nextPresetId,
    );
    final update = <String, dynamic>{
      'activities': FieldValue.arrayUnion([activity.toMap()]),
      'lastActivityAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      'updatedBy': u?.uid ?? '',
    };
    if (_nextAt != null) {
      update['nextActionAt'] = Timestamp.fromDate(_nextAt!);
    }
    if (_nextTypeId != null) {
      update['nextActionType'] = _nextTypeId;
    }
    try {
      await widget.leadRef.update(update);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _expanded = false;
        _memo = '';
        _memoCtrl.clear();
        _outcome = null;
        _feeling = null;
        _nextPresetId = null;
        _nextTypeId = null;
        _nextAt = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('記録しました'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppFeedback.info(context, '保存エラー: $e');
    }
  }
}

class _PresetPicker extends StatelessWidget {
  final String stage;
  final String feeling;
  final String? selectedId;
  final ValueChanged<CrmNextActionPreset> onSelected;
  final VoidCallback onCustom;
  const _PresetPicker({
    required this.stage,
    required this.feeling,
    required this.selectedId,
    required this.onSelected,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final presets = nextActionPresetsFor(stage: stage, feeling: feeling);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in presets)
          ChoiceChip(
            label: Text(p.label, style: const TextStyle(fontSize: AppTextSize.caption)),
            selected: selectedId == p.id,
            onSelected: (_) => onSelected(p),
            visualDensity: VisualDensity.compact,
          ),
        ChoiceChip(
          label: const Text('カスタム入力', style: TextStyle(fontSize: AppTextSize.caption)),
          selected: selectedId == 'custom',
          onSelected: (_) => onCustom(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- 履歴

class _HistorySection extends StatelessWidget {
  final CrmLead lead;
  const _HistorySection({required this.lead});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final activities = lead.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('📋', style: TextStyle(fontSize: AppTextSize.titleSm)),
            const SizedBox(width: 6),
            Text('対応履歴',
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(width: 8),
            Text('${activities.length}件',
                style:
                    TextStyle(fontSize: AppTextSize.caption, color: c.textTertiary)),
          ],
        ),
        const SizedBox(height: 8),
        if (activities.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Text('まだ履歴がありません',
                style: TextStyle(fontSize: AppTextSize.small, color: c.textTertiary)),
          )
        else
          ...activities.take(20).map((a) => _tile(context, a)),
      ],
    );
  }

  Widget _tile(BuildContext context, CrmActivity a) {
    final c = context.colors;
    final typeLabel = CrmOptions.labelOf(CrmOptions.activityTypes, a.type);
    final outcomeLabel = a.outcome == null
        ? ''
        : (crmOutcomes.where((o) => o.id == a.outcome).firstOrNull?.label ??
            '');
    final feeling = a.feeling == null
        ? null
        : crmFeelings.where((f) => f.id == a.feeling).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: c.chipBg,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(typeLabel,
                    style: TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary)),
              ),
              const SizedBox(width: 6),
              if (outcomeLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: context.alerts.info.background,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(outcomeLabel,
                      style: TextStyle(
                          fontSize: AppTextSize.xs,
                          fontWeight: FontWeight.w700,
                          color: context.alerts.info.text)),
                ),
              if (feeling != null) ...[
                const SizedBox(width: 6),
                Text(feeling.emoji,
                    style: const TextStyle(fontSize: AppTextSize.bodyMd)),
              ],
              const Spacer(),
              if (a.at != null)
                Text(
                  DateFormat('M/d HH:mm', 'ja').format(a.at!),
                  style: TextStyle(
                      fontSize: AppTextSize.xs, color: c.textTertiary),
                ),
            ],
          ),
          if (a.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.body,
                style: TextStyle(
                    fontSize: AppTextSize.small, color: c.textPrimary, height: 1.4)),
          ],
          if (a.authorName != null && a.authorName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(a.authorName!,
                style: TextStyle(fontSize: AppTextSize.xs, color: c.textTertiary)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- 児童・保護者情報

class _ChildInfoSection extends StatelessWidget {
  final CrmLead lead;
  const _ChildInfoSection({required this.lead});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _InfoBox(
      icon: '🧒',
      title: '児童情報',
      rows: [
        if (lead.childKana.isNotEmpty) ('ふりがな', lead.childKana),
        if (lead.childAge != null) ('年齢', '${lead.childAge}歳'),
        if (lead.childBirthDate != null)
          ('生年月日',
              DateFormat('yyyy/M/d', 'ja').format(lead.childBirthDate!)),
      ],
      fallback: Text('児童の詳細情報が未入力です',
          style: TextStyle(fontSize: AppTextSize.small, color: c.textTertiary)),
    );
  }
}

class _ParentInfoSection extends StatelessWidget {
  final CrmLead lead;
  const _ParentInfoSection({required this.lead});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ch = lead.preferredChannel;
    return _InfoBox(
      icon: '👪',
      title: '保護者・連絡先',
      rows: [
        if (lead.parentFullName.isNotEmpty) ('氏名', lead.parentFullName),
        if (lead.parentTel.isNotEmpty) ('TEL', lead.parentTel),
        if (lead.parentEmail.isNotEmpty) ('Email', lead.parentEmail),
        if (lead.parentLine.isNotEmpty) ('LINE', lead.parentLine),
        if (ch.isNotEmpty)
          ('連絡手段', CrmOptions.labelOf(CrmOptions.channels, ch)),
      ],
      fallback: Text('連絡先が未入力です',
          style: TextStyle(fontSize: AppTextSize.small, color: c.textTertiary)),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String icon;
  final String title;
  final List<(String, String)> rows;
  final Widget fallback;
  const _InfoBox({
    required this.icon,
    required this.title,
    required this.rows,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: AppTextSize.bodyMd)),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.small,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            fallback
          else
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(r.$1,
                            style: TextStyle(
                                fontSize: AppTextSize.caption, color: c.textTertiary)),
                      ),
                      Expanded(
                        child: Text(r.$2,
                            style: TextStyle(
                                fontSize: AppTextSize.small, color: c.textPrimary)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
