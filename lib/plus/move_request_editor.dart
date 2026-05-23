// 移動希望の構造化エディタ。
// 候補（曜日 + 時間）を複数行で追加・編集できる。期限・メモも含む。
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import 'move_request.dart';

/// 編集状態を呼び出し元と共有するためのコントローラ。
/// （TextEditingController 風の使い方）
class MoveRequestEditController {
  MoveRequest _value;
  MoveRequest get value => _value;

  void Function()? _listener;

  MoveRequestEditController([MoveRequest? initial])
      : _value = initial ?? MoveRequest.empty;

  void setValue(MoveRequest v) {
    _value = v;
    _listener?.call();
  }

  void dispose() {
    _listener = null;
  }
}

class MoveRequestEditor extends StatefulWidget {
  final MoveRequestEditController controller;
  final List<String> timeSlots; // 例: ['9:30', '11:00', '14:00', '15:30']

  const MoveRequestEditor({
    super.key,
    required this.controller,
    required this.timeSlots,
  });

  @override
  State<MoveRequestEditor> createState() => _MoveRequestEditorState();
}

class _MoveRequestEditorState extends State<MoveRequestEditor> {
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController(text: widget.controller.value.note);
    widget.controller._listener = () {
      if (!mounted) return;
      // 外部から差し替えられた場合に同期
      if (_noteCtrl.text != widget.controller.value.note) {
        _noteCtrl.text = widget.controller.value.note;
      }
      setState(() {});
    };
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  MoveRequest get _v => widget.controller.value;

  void _update(MoveRequest next) {
    widget.controller.setValue(next);
    setState(() {});
  }

  void _addCandidate() {
    final next = [..._v.candidates];
    final nextPriority = next.isEmpty
        ? 1
        : (next.map((c) => c.priority).reduce((a, b) => a > b ? a : b)) + 1;
    next.add(MoveRequestCandidate(
      weekday: 3,
      startTime: widget.timeSlots.isNotEmpty ? widget.timeSlots.first : '9:30',
      priority: nextPriority,
    ));
    _update(_v.copyWith(candidates: next));
  }

  void _removeCandidate(int index) {
    final next = [..._v.candidates]..removeAt(index);
    // 優先度を1から振り直す
    final reindexed = <MoveRequestCandidate>[];
    for (var i = 0; i < next.length; i++) {
      reindexed.add(MoveRequestCandidate(
        weekday: next[i].weekday,
        startTime: next[i].startTime,
        priority: i + 1,
      ));
    }
    _update(_v.copyWith(candidates: reindexed));
  }

  void _updateCandidate(int index, {int? weekday, String? startTime}) {
    final next = [..._v.candidates];
    final c = next[index];
    next[index] = MoveRequestCandidate(
      weekday: weekday ?? c.weekday,
      startTime: startTime ?? c.startTime,
      priority: c.priority,
    );
    _update(_v.copyWith(candidates: next));
  }

  Future<void> _pickExpiresAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _v.expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      _update(_v.copyWith(expiresAt: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 候補リスト
        if (_v.candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '候補を追加してください',
              style: TextStyle(
                fontSize: AppTextSize.small,
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          ..._v.candidates.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _CandidateRow(
                candidate: c,
                timeSlots: widget.timeSlots,
                onChanged: (weekday, startTime) => _updateCandidate(
                  i,
                  weekday: weekday,
                  startTime: startTime,
                ),
                onRemove: () => _removeCandidate(i),
              ),
            );
          }),
        // 候補追加ボタン
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addCandidate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('候補を追加', style: TextStyle(fontSize: AppTextSize.body)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 期限
        Row(
          children: [
            Icon(Icons.event, size: 16, color: context.colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              '期限',
              style: TextStyle(
                fontSize: AppTextSize.small,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _pickExpiresAt,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: context.colors.borderMedium),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _v.expiresAt != null
                      ? '${DateFormat('y/M/d').format(_v.expiresAt!)} まで'
                      : '期限なし',
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: _v.expiresAt != null
                        ? context.colors.textPrimary
                        : context.colors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_v.expiresAt != null)
              IconButton(
                icon: Icon(Icons.close,
                    size: 14, color: context.colors.iconMuted),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () =>
                    _update(_v.copyWith(clearExpiresAt: true)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // メモ
        TextField(
          controller: _noteCtrl,
          decoration: InputDecoration(
            hintText: 'メモ（経緯・保護者の温度感など）',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
          ),
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(fontSize: AppTextSize.body),
          onChanged: (v) {
            _update(_v.copyWith(note: v));
          },
        ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final MoveRequestCandidate candidate;
  final List<String> timeSlots;
  final void Function(int? weekday, String? startTime) onChanged;
  final VoidCallback onRemove;

  const _CandidateRow({
    required this.candidate,
    required this.timeSlots,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.borderLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 優先度バッジ
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${candidate.priority}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppTextSize.small,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 曜日
          DropdownButton<int>(
            value: candidate.weekday,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 1, child: Text('月')),
              DropdownMenuItem(value: 2, child: Text('火')),
              DropdownMenuItem(value: 3, child: Text('水')),
              DropdownMenuItem(value: 4, child: Text('木')),
              DropdownMenuItem(value: 5, child: Text('金')),
              DropdownMenuItem(value: 6, child: Text('土')),
            ],
            onChanged: (v) => onChanged(v, null),
          ),
          const SizedBox(width: 12),
          // 時間
          DropdownButton<String>(
            value: timeSlots.contains(candidate.startTime)
                ? candidate.startTime
                : null,
            isDense: true,
            underline: const SizedBox.shrink(),
            hint: Text(candidate.startTime),
            items: timeSlots
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => onChanged(null, v),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: context.colors.iconMuted),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 表示専用ウィジェット（リスト/ホバーで使う）
class MoveRequestDisplay extends StatelessWidget {
  final MoveRequest value;
  final bool compact; // ホバー等で文字を小さく表示する場合

  const MoveRequestDisplay({
    super.key,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? AppTextSize.small : AppTextSize.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value.candidates.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: value.sortedCandidates.map((c) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.aiAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${c.priority}. ${c.displayLabel}',
                  style: TextStyle(
                    fontSize: fontSize,
                    color: AppColors.aiAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        if (value.expiresAt != null) ...[
          if (value.candidates.isNotEmpty) const SizedBox(height: 4),
          Text(
            '〜${DateFormat('M/d').format(value.expiresAt!)}まで',
            style: TextStyle(
              fontSize: fontSize - 1,
              color: context.colors.textSecondary,
            ),
          ),
        ],
        if (value.note.isNotEmpty) ...[
          if (value.candidates.isNotEmpty || value.expiresAt != null)
            const SizedBox(height: 4),
          Text(
            value.note,
            style: TextStyle(
              fontSize: fontSize,
              color: context.colors.textPrimary,
            ),
            maxLines: compact ? 3 : 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
