import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Googleカレンダー風の時刻ピッカー
/// 15分刻みのリストから選択 or 直接入力（HH:MM）が可能
Future<TimeOfDay?> showTimeListPicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  // 10分刻みで0:00〜23:50の144個を生成
  final slots = <TimeOfDay>[];
  for (int h = 0; h < 24; h++) {
    for (int m = 0; m < 60; m += 10) {
      slots.add(TimeOfDay(hour: h, minute: m));
    }
  }
  // 初期表示位置（一番近いスロット）
  final initialIdx = (initialTime.hour * 60 + initialTime.minute) ~/ 10;
  final scrollController = ScrollController(
    // 1項目=44px。中央付近に来るよう少し上にオフセット
    initialScrollOffset: (initialIdx * 44.0 - 88).clamp(0.0, double.infinity),
  );
  final inputController = TextEditingController(
    text: '${initialTime.hour}:${initialTime.minute.toString().padLeft(2, '0')}',
  );

  String formatTime(TimeOfDay t) =>
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay? parseInput(String text) {
    final m = RegExp(r'^\s*(\d{1,2})\s*[:：]?\s*(\d{1,2})?\s*$').firstMatch(text);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    final mm = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (h == null || h < 0 || h > 23 || mm < 0 || mm > 59) return null;
    return TimeOfDay(hour: h, minute: mm);
  }

  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ヘッダー：直接入力欄
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: inputController,
                  autofocus: false,
                  keyboardType: TextInputType.datetime,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: '時刻',
                    hintText: '例: 9:30',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check, color: AppColors.primary),
                      tooltip: '入力した時刻で確定',
                      onPressed: () {
                        final t = parseInput(inputController.text);
                        if (t != null) Navigator.pop(ctx, t);
                      },
                    ),
                  ),
                  onSubmitted: (text) {
                    final t = parseInput(text);
                    if (t != null) Navigator.pop(ctx, t);
                  },
                ),
              ),
              const Divider(height: 1),
              // 10分刻みリスト
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: slots.length,
                  itemExtent: 44,
                  itemBuilder: (context, index) {
                    final t = slots[index];
                    final isSelected = index == initialIdx;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, t),
                      child: Container(
                        alignment: Alignment.center,
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : null,
                        child: Text(
                          formatTime(t),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primary
                                : context.colors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('キャンセル'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
