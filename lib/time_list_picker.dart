import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Googleカレンダー風の時刻ピッカー
/// 「時」と「分」を別々のロールで選択 or 直接入力（HH:MM）が可能
Future<TimeOfDay?> showTimeListPicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  // 分は5分刻み（0,5,10,...,55）
  const minuteStep = 5;
  final minutes = List<int>.generate(60 ~/ minuteStep, (i) => i * minuteStep);
  // 初期位置：近い5分スロットに丸める
  final nearestMinIdx = (initialTime.minute / minuteStep).round() % minutes.length;
  int selectedHour = initialTime.hour;
  int selectedMinute = minutes[nearestMinIdx];

  final inputController = TextEditingController(
    text: '${initialTime.hour}:${initialTime.minute.toString().padLeft(2, '0')}',
  );

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
      final hourController = FixedExtentScrollController(initialItem: selectedHour);
      final minuteController = FixedExtentScrollController(initialItem: nearestMinIdx);

      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 440),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
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
                  // 時・分の2ロール
                  Expanded(
                    child: Stack(
                      children: [
                        // 中央ハイライト
                        Center(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _WheelColumn(
                                controller: hourController,
                                itemCount: 24,
                                selectedIndex: selectedHour,
                                label: (i) => i.toString().padLeft(2, '0'),
                                onSelected: (i) {
                                  setState(() => selectedHour = i);
                                  inputController.text =
                                      '$selectedHour:${selectedMinute.toString().padLeft(2, '0')}';
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(':',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.textSecondary,
                                  )),
                            ),
                            Expanded(
                              child: _WheelColumn(
                                controller: minuteController,
                                itemCount: minutes.length,
                                selectedIndex: minutes.indexOf(selectedMinute),
                                label: (i) => minutes[i].toString().padLeft(2, '0'),
                                onSelected: (i) {
                                  setState(() => selectedMinute = minutes[i]);
                                  inputController.text =
                                      '$selectedHour:${selectedMinute.toString().padLeft(2, '0')}';
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
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
                        TextButton(
                          onPressed: () {
                            Navigator.pop(
                              ctx,
                              TimeOfDay(hour: selectedHour, minute: selectedMinute),
                            );
                          },
                          child: const Text('OK',
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _WheelColumn extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int itemCount;
  final int selectedIndex;
  final String Function(int) label;
  final ValueChanged<int> onSelected;

  const _WheelColumn({
    required this.controller,
    required this.itemCount,
    required this.selectedIndex,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      perspective: 0.003,
      diameterRatio: 1.8,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (ctx, index) {
          final isSelected = index == selectedIndex;
          return Center(
            child: Text(
              label(index),
              style: TextStyle(
                fontSize: isSelected ? 20 : 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                color: isSelected
                    ? AppColors.primary
                    : context.colors.textPrimary,
              ),
            ),
          );
        },
      ),
    );
  }
}
