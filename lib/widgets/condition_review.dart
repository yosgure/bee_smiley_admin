import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';

/// コンディション記録の共有モデル・可視化ウィジェット。
/// 保護者「ふりかえり」ビュー（parent_condition_screen.dart）と
/// 職員の面談ビュー（staff_condition_screen.dart）で共用する。

class ConditionCharacter {
  final String id;
  final String name;
  final String phrase; // 子ども向けの言葉
  final String emoji; // イラスト素材ができるまでの代用（将来 assetPath に差し替え）
  final Color color;

  const ConditionCharacter({
    required this.id,
    required this.name,
    required this.phrase,
    required this.emoji,
    required this.color,
  });
}

/// コンディションキャラクター（構想の基本5キャラ）。
/// 状態の意味が重ならないように選定されている。
const List<ConditionCharacter> kConditionCharacters = [
  ConditionCharacter(
    id: 'lion',
    name: 'げんきライオン',
    phrase: 'げんきいっぱい！やってみたい',
    emoji: '🦁',
    color: Color(0xFFF59E0B),
  ),
  ConditionCharacter(
    id: 'koala',
    name: 'のんびりコアラ',
    phrase: 'ゆっくりならできそう',
    emoji: '🐨',
    color: Color(0xFF66BB6A),
  ),
  ConditionCharacter(
    id: 'penguin',
    name: 'ねむねむペンギン',
    phrase: 'ねむいよ、ちょっとやすみたい',
    emoji: '🐧',
    color: Color(0xFF42A5F5),
  ),
  ConditionCharacter(
    id: 'squirrel',
    name: 'そわそわリス',
    phrase: 'まわりがきになっておちつかない',
    emoji: '🐿️',
    color: Color(0xFF9575CD),
  ),
  ConditionCharacter(
    id: 'panda',
    name: 'おやすみパンダ',
    phrase: 'つかれたよ、しっかりやすみたい',
    emoji: '🐼',
    color: Color(0xFF78909C),
  ),
];

ConditionCharacter? conditionCharacterById(String? id) {
  if (id == null) return null;
  for (final c in kConditionCharacters) {
    if (c.id == id) return c;
  }
  return null;
}

/// 疲れ度レベル（1〜5）の色。1=元気（緑）〜 5=限界（赤）。
Color conditionFatigueColor(int level) {
  switch (level) {
    case 1:
      return AppColors.success;
    case 2:
      return const Color(0xFF9CCC65);
    case 3:
      return AppColors.warning;
    case 4:
      return const Color(0xFFFB8C00);
    case 5:
      return AppColors.error;
    default:
      return const Color(0xFFBDBDBD);
  }
}

/// 月間ふりかえりカード群（キャラ分布・疲れ度推移・メモ一覧）。
/// [monthData] は dateKey('yyyy-MM-dd') → 日次記録データ のマップ。
class ConditionReviewCards extends StatelessWidget {
  final DateTime month;
  final Map<String, Map<String, dynamic>> monthData;

  const ConditionReviewCards({
    super.key,
    required this.month,
    required this.monthData,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCharDistCard(context),
        const SizedBox(height: 16),
        _buildFatigueChartCard(context),
        ..._buildNotesCard(context),
      ],
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: child,
    );
  }

  Widget _cardTitle(BuildContext context, IconData icon, String title,
      {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.bodyLarge,
                color: AppColors.primary)),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _buildCharDistCard(BuildContext context) {
    final counts = {for (final c in kConditionCharacters) c.id: 0};
    var recordedDays = 0;
    for (final d in monthData.values) {
      final charId = d['character'] as String?;
      if (charId != null && counts.containsKey(charId)) {
        counts[charId] = counts[charId]! + 1;
      }
      if (charId != null || (d['fatigue'] as int? ?? 0) > 0) recordedDays++;
    }
    final maxCount = counts.values.fold<int>(1, (a, b) => a > b ? a : b);

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(context, Icons.pets, 'キャラクターのぶんぷ',
              trailing: Text('記録 $recordedDays日',
                  style: TextStyle(
                      fontSize: AppTextSize.small,
                      color: context.colors.textSecondary))),
          const SizedBox(height: 12),
          ...kConditionCharacters.map((c) {
            final count = counts[c.id]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(c.emoji,
                      style: const TextStyle(fontSize: AppTextSize.titleLg)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 108,
                    child: Text(c.name,
                        style: const TextStyle(fontSize: AppTextSize.small)),
                  ),
                  Expanded(
                    child: Container(
                      height: 12,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: context.colors.chipBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: count / maxCount,
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text('$count日',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: AppTextSize.small,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFatigueChartCard(BuildContext context) {
    final points = <MapEntry<int, int>>[];
    monthData.forEach((dateKey, d) {
      final f = d['fatigue'] as int?;
      if (f != null && f >= 1 && f <= 5) {
        points.add(MapEntry(int.parse(dateKey.substring(8)), f));
      }
    });
    points.sort((a, b) => a.key.compareTo(b.key));
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final avg = points.isEmpty
        ? null
        : points.map((p) => p.value).reduce((a, b) => a + b) / points.length;

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(context, Icons.show_chart, 'つかれ度のすいい',
              trailing: avg == null
                  ? null
                  : Text('平均 ${avg.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: AppTextSize.small,
                          color: context.colors.textSecondary))),
          const SizedBox(height: 4),
          Text('1=元気 〜 5=限界に近い',
              style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: context.colors.textSecondary)),
          const SizedBox(height: 8),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('つかれ度の記録がありません',
                    style: TextStyle(color: context.colors.textSecondary)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 160,
              child: CustomPaint(
                painter: ConditionFatigueChartPainter(
                  points: points,
                  daysInMonth: daysInMonth,
                  gridColor: context.colors.borderLight,
                  labelColor: context.colors.textSecondary,
                  lineColor: context.colors.borderMedium,
                  levelColors: [
                    for (var lv = 1; lv <= 5; lv++) conditionFatigueColor(lv)
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNotesCard(BuildContext context) {
    final notes = monthData.entries
        .where((e) => (e.value['note'] ?? '').toString().trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (notes.isEmpty) return [];

    return [
      const SizedBox(height: 16),
      _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(
                context, Icons.sticky_note_2_outlined, '気になった様子・メモ'),
            const SizedBox(height: 12),
            ...notes.map((e) {
              final date = DateTime.parse(e.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        DateFormat('M/d(E)', 'ja').format(date),
                        style: const TextStyle(
                            fontSize: AppTextSize.small,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(e.value['note'].toString(),
                          style: const TextStyle(
                              fontSize: AppTextSize.body, height: 1.5)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ];
  }
}

/// 疲れ度の月間推移チャート（依存ライブラリなしの CustomPainter 実装）。
/// 横軸 = 日（1〜月末）、縦軸 = 疲れ度 1〜5（上ほど疲れている）。
/// 点は疲れ度レベルの色、点同士は控えめな線でつなぐ。
class ConditionFatigueChartPainter extends CustomPainter {
  final List<MapEntry<int, int>> points; // (日, 疲れ度) 昇順
  final int daysInMonth;
  final Color gridColor;
  final Color labelColor;
  final Color lineColor;
  final List<Color> levelColors; // index 0 = レベル1

  ConditionFatigueChartPainter({
    required this.points,
    required this.daysInMonth,
    required this.gridColor,
    required this.labelColor,
    required this.lineColor,
    required this.levelColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 22.0, rightPad = 8.0, topPad = 8.0, bottomPad = 20.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    double yFor(num level) => topPad + plotH * (5 - level) / 4;
    double xFor(int day) => daysInMonth <= 1
        ? leftPad
        : leftPad + plotW * (day - 1) / (daysInMonth - 1);

    // 横グリッド（レベル1〜5）と左ラベル
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var lv = 1; lv <= 5; lv++) {
      final y = yFor(lv);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      _label(canvas, '$lv', Offset(4, y - 6));
    }
    // 下部の日ラベル
    for (final d in const [1, 5, 10, 15, 20, 25, 30]) {
      if (d > daysInMonth) continue;
      _label(canvas, '$d', Offset(xFor(d) - 4, size.height - 14));
    }

    // 折れ線
    if (points.length >= 2) {
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(xFor(points.first.key), yFor(points.first.value));
      for (final p in points.skip(1)) {
        path.lineTo(xFor(p.key), yFor(p.value));
      }
      canvas.drawPath(path, linePaint);
    }
    // ドット（レベル色）
    for (final p in points) {
      canvas.drawCircle(
        Offset(xFor(p.key), yFor(p.value)),
        4.5,
        Paint()..color = levelColors[(p.value - 1).clamp(0, 4)],
      );
    }
  }

  void _label(Canvas canvas, String s, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(fontSize: AppTextSize.xs, color: labelColor)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant ConditionFatigueChartPainter old) =>
      old.points != points ||
      old.daysInMonth != daysInMonth ||
      old.gridColor != gridColor ||
      old.lineColor != lineColor;
}
