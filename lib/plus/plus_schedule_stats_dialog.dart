// plus_schedule_screen.dart の _showStatsDialog（459行）を切り出した part。
// extension 構文を使うことで本体内の private 識別子を無編集で維持できる。
part of '../plus_schedule_screen.dart';

extension _PlusScheduleStatsDialog on _PlusScheduleContentState {
  void _showStatsDialog() async {
    // 対象スタッフ（フルネーム）と1日あたりの目標コマ数のデフォルト
    final defaultTargets = <String, int>{
      '安保 さゆり': 3,
      '石川 真利': 2,
      '栗林 志織': 3,
      '松永 智栄': 3,
    };

    // _staffList から対象スタッフのidを引く（名前マッチング）
    // staffIdベースで集計する（plus_shiftsのname表記揺れに依存しないため）
    final targetStaff = <String, Map<String, dynamic>>{}; // staffId -> {name, slotTarget}
    for (final entry in defaultTargets.entries) {
      final fullName = entry.key;
      // _staffListから一致するスタッフを検索（前後空白・全半角空白を許容）
      final normalized = fullName.replaceAll(RegExp(r'[\s\u3000]'), '');
      final staff = _staffList.firstWhere(
        (s) {
          final n = (s['name'] as String? ?? '').replaceAll(RegExp(r'[\s\u3000]'), '');
          return n == normalized;
        },
        orElse: () => <String, dynamic>{},
      );
      if (staff.isEmpty) continue;
      final staffId = staff['id'] as String;
      final slotTarget = (staff['dailySlotTarget'] as int?) ?? entry.value;
      targetStaff[staffId] = {
        'name': fullName,
        'furigana': staff['furigana'] ?? fullName,
        'slotTarget': slotTarget,
      };
    }

    // 集計期間: 2026年3月31日 〜 昨日（実績）/ 未来（予定込み）
    final startDate = DateTime(2026, 3, 31);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.subtract(const Duration(days: 1)); // 昨日

    // 実績分（〜昨日）を取得
    final lessonsSnap = await FirebaseFirestore.instance
        .collection('plus_lessons')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .get();

    // 日付ごとのコマ（teachers配列）を集計（欠席除外）
    final lessonsByDate = <String, List<List<String>>>{};
    final futureLessonsByDate = <String, List<List<String>>>{};
    // スケジュール期限を特定（対象スタッフがアサインされている最後の日）
    DateTime scheduleHorizon = today;
    for (final doc in lessonsSnap.docs) {
      final data = doc.data();
      final course = data['course'] as String? ?? '';
      if (course.startsWith('欠席')) continue;
      final ts = data['date'] as Timestamp?;
      if (ts == null) continue;
      final dt = ts.toDate();
      final dtDate = DateTime(dt.year, dt.month, dt.day);
      final key = DateFormat('yyyy-MM-dd').format(dt);
      final teachers = (data['teachers'] as List<dynamic>? ?? [])
          .map((e) => e.toString().replaceAll(RegExp(r'[\s\u3000]'), ''))
          .toList();
      if (dtDate.isBefore(today)) {
        // 実績（昨日まで）
        lessonsByDate.putIfAbsent(key, () => []).add(teachers);
      } else {
        // 未来: 実際にアサインされたレッスンを記録
        futureLessonsByDate.putIfAbsent(key, () => []).add(teachers);
        // 対象スタッフがアサインされていればスケジュール期限を更新
        for (final staffId in targetStaff.keys) {
          final info = targetStaff[staffId]!;
          final fullNameNormalized = (info['name'] as String).replaceAll(RegExp(r'[\s\u3000]'), '');
          if (teachers.contains(fullNameNormalized) && dtDate.isAfter(scheduleHorizon)) {
            scheduleHorizon = dtDate;
          }
        }
      }
    }

    // 期間内のplus_shiftsを月単位で取得（未来分も含む）
    final shiftsByMonth = <String, Map<String, dynamic>>{};
    {
      var cursor = DateTime(startDate.year, startDate.month, 1);
      while (!cursor.isAfter(scheduleHorizon)) {
        final mk = DateFormat('yyyy-MM').format(cursor);
        try {
          final doc = await FirebaseFirestore.instance
              .collection('plus_shifts')
              .doc(mk)
              .get();
          if (doc.exists) shiftsByMonth[mk] = doc.data()!;
        } catch (_) {}
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    }

    // シフトからスタッフの日別ステータスを取得するヘルパー
    String _getShiftStatus(String staffId, DateTime date) {
      final monthKey = DateFormat('yyyy-MM').format(date);
      final dayKey = date.day.toString();
      final monthDoc = shiftsByMonth[monthKey];
      final days = monthDoc?['days'] as Map<String, dynamic>?;
      final daySlots = (days?[dayKey] as List<dynamic>?) ?? [];
      for (final slot in daySlots) {
        if (slot is Map) {
          final m = Map<String, dynamic>.from(slot);
          if (m['staffId'] == staffId) {
            final rawStatus = m['shiftStatus'] as String?;
            if (rawStatus != null) return rawStatus;
            if (m['isWorking'] == false) return 'off';
            return 'full';
          }
        }
      }
      return 'full';
    }

    bool _isHoliday(DateTime date) {
      final monthKey = DateFormat('yyyy-MM').format(date);
      final dayKey = date.day.toString();
      final monthDoc = shiftsByMonth[monthKey];
      final holidays = ((monthDoc?['holidays'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toSet();
      return holidays.contains(dayKey);
    }

    bool _isWorkingDay(DateTime date) {
      if (date.weekday == DateTime.sunday || date.weekday == DateTime.monday) return false;
      if (_isHoliday(date)) return false;
      return true;
    }

    // スタッフ(staffId)ごとの実施/目標を集計（〜昨日）
    final actualCounts = <String, int>{for (final id in targetStaff.keys) id: 0};
    final targetCounts = <String, int>{for (final id in targetStaff.keys) id: 0};

    var d = startDate;
    while (!d.isAfter(endDate)) {
      if (!_isWorkingDay(d)) {
        d = d.add(const Duration(days: 1));
        continue;
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(d);
      final dayLessons = lessonsByDate[dateKey] ?? const <List<String>>[];

      for (final staffId in targetStaff.keys) {
        final info = targetStaff[staffId]!;
        final fullNameNormalized = (info['name'] as String).replaceAll(RegExp(r'[\s\u3000]'), '');
        final slotTarget = info['slotTarget'] as int;
        final status = _getShiftStatus(staffId, d);

        if (status != 'off') {
          final dayTarget = status == 'half' ? (slotTarget - 1) : slotTarget;
          if (dayTarget > 0) {
            targetCounts[staffId] = targetCounts[staffId]! + dayTarget;
          }
          int actual = 0;
          for (final teachers in dayLessons) {
            if (teachers.contains(fullNameNormalized)) actual++;
          }
          actualCounts[staffId] = actualCounts[staffId]! + actual;
        }
      }

      d = d.add(const Duration(days: 1));
    }

    // 予定（未来）: 実際にアサインされているレッスン数をカウント
    final futureLessonsByStaff = <String, int>{for (final id in targetStaff.keys) id: 0};
    // 未来の目標（slotTarget × 出勤日数）も別途計算
    final futureTargetByStaff = <String, int>{for (final id in targetStaff.keys) id: 0};
    {
      var fd = today;
      while (!fd.isAfter(scheduleHorizon)) {
        if (!_isWorkingDay(fd)) {
          fd = fd.add(const Duration(days: 1));
          continue;
        }
        final dateKey = DateFormat('yyyy-MM-dd').format(fd);
        final dayLessons = futureLessonsByDate[dateKey] ?? const <List<String>>[];
        for (final staffId in targetStaff.keys) {
          final info = targetStaff[staffId]!;
          final fullNameNormalized = (info['name'] as String).replaceAll(RegExp(r'[\s\u3000]'), '');
          final slotTarget = info['slotTarget'] as int;
          final status = _getShiftStatus(staffId, fd);
          if (status != 'off') {
            final dayTarget = status == 'half' ? (slotTarget - 1) : slotTarget;
            if (dayTarget > 0) {
              futureTargetByStaff[staffId] = futureTargetByStaff[staffId]! + dayTarget;
            }
            // 実際にアサインされているコマ数をカウント
            int futureActual = 0;
            for (final teachers in dayLessons) {
              if (teachers.contains(fullNameNormalized)) futureActual++;
            }
            futureLessonsByStaff[staffId] = futureLessonsByStaff[staffId]! + futureActual;
          }
        }
        fd = fd.add(const Duration(days: 1));
      }
    }

    if (!mounted) return;

    bool showWithFuture = false; // false=不足(現在), true=不足(予定込)
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // 対象スタッフ（staffIdベース）をふりがな順でソート
            final sortedStaffIds = targetStaff.keys.toList()
              ..sort((a, b) {
                final fa = (targetStaff[a]!['furigana'] as String?) ?? '';
                final fb = (targetStaff[b]!['furigana'] as String?) ?? '';
                return fa.compareTo(fb);
              });

            // 相対不足を計算: 最小不足者を基準(0)にする
            final rawShortages = <String, int>{};
            final rawShortagesWithFuture = <String, int>{};
            for (final staffId in sortedStaffIds) {
              final actual = actualCounts[staffId] ?? 0;
              final target = targetCounts[staffId] ?? 0;
              final futureSlots = futureLessonsByStaff[staffId] ?? 0;
              rawShortages[staffId] = target - actual;
              final futureTarget = futureTargetByStaff[staffId] ?? 0;
              // 予定込み: (目標+未来目標) - (実績+実際の予定コマ数)
              rawShortagesWithFuture[staffId] = (target + futureTarget) - (actual + futureSlots);
            }
            final minShortage = rawShortages.values.isEmpty ? 0 : rawShortages.values.reduce((a, b) => a < b ? a : b);
            final minShortageWithFuture = rawShortagesWithFuture.values.isEmpty ? 0 : rawShortagesWithFuture.values.reduce((a, b) => a < b ? a : b);

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.bar_chart, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('コマ数集計', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3/31〜累計  一番入っている人を基準(0)とした相対不足',
                      style: TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    // トグル: 不足(現在) / 不足(予定込)
                    Container(
                      decoration: BoxDecoration(
                        color: context.colors.chipBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => showWithFuture = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: !showWithFuture ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '現在',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: AppTextSize.body,
                                    fontWeight: FontWeight.bold,
                                    color: !showWithFuture ? Colors.white : context.colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => showWithFuture = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: showWithFuture ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '予定',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: AppTextSize.body,
                                    fontWeight: FontWeight.bold,
                                    color: showWithFuture ? Colors.white : context.colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ヘッダー
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: context.colors.chipBg,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(flex: 3, child: Text('スタッフ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.body))),
                          Expanded(flex: 2, child: Text(showWithFuture ? '実績+予定' : '実績', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.body), textAlign: TextAlign.center)),
                          const Expanded(flex: 2, child: Text('目標', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.body), textAlign: TextAlign.center)),
                          const Expanded(flex: 2, child: Text('差分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.body), textAlign: TextAlign.center)),
                          const Expanded(flex: 2, child: Text('相対', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.body), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // データ行
                    ...sortedStaffIds.map((staffId) {
                      final info = targetStaff[staffId]!;
                      final name = info['name'] as String;
                      final lastName = name.split(' ').first;
                      final slotTarget = info['slotTarget'] as int;
                      final actual = actualCounts[staffId] ?? 0;
                      final target = targetCounts[staffId] ?? 0;
                      final futureSlots = futureLessonsByStaff[staffId] ?? 0;
                      final futureTarget = futureTargetByStaff[staffId] ?? 0;
                      // 予定込み: 実績+実際の予定 vs 目標+未来目標
                      final displayActual = showWithFuture ? actual + futureSlots : actual;
                      final displayTarget = showWithFuture ? target + futureTarget : target;
                      final rawDiff = displayTarget - displayActual;
                      final shortage = rawShortages[staffId]! - minShortage;
                      final shortageWithFuture = rawShortagesWithFuture[staffId]! - minShortageWithFuture;
                      final displayShortage = showWithFuture ? shortageWithFuture : shortage;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: context.colors.borderLight)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Text(lastName, style: const TextStyle(fontSize: AppTextSize.bodyMd)),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: ctx,
                                        builder: (editCtx) {
                                          int editTarget = slotTarget;
                                          return StatefulBuilder(
                                            builder: (editCtx, setEditState) => AlertDialog(
                                              title: Text('$lastName の1日あたり目標コマ数'),
                                              content: DropdownButton<int>(
                                                value: editTarget,
                                                items: [1, 2, 3, 4, 5, 6].map((d) => DropdownMenuItem(value: d, child: Text('$dコマ/日'))).toList(),
                                                onChanged: (v) {
                                                  if (v != null) setEditState(() => editTarget = v);
                                                },
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(editCtx), child: const Text('キャンセル')),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    await FirebaseFirestore.instance.collection('staffs').doc(staffId).update({'dailySlotTarget': editTarget});
                                                    info['slotTarget'] = editTarget;
                                                    final idx = _staffList.indexWhere((s) => s['id'] == staffId);
                                                    if (idx != -1) _staffList[idx]['dailySlotTarget'] = editTarget;
                                                    Navigator.pop(editCtx);
                                                    setDialogState(() {});
                                                  },
                                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: context.colors.textOnPrimary),
                                                  child: const Text('保存'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: Text(
                                      '(${slotTarget}/日)',
                                      style: TextStyle(fontSize: AppTextSize.caption, color: context.colors.textTertiary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$displayActual',
                                style: const TextStyle(fontSize: AppTextSize.bodyMd),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$displayTarget',
                                style: const TextStyle(fontSize: AppTextSize.bodyMd),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                rawDiff <= 0 ? '0' : '$rawDiff',
                                style: TextStyle(
                                  fontSize: AppTextSize.bodyMd,
                                  color: rawDiff <= 0 ? context.colors.textTertiary : context.colors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                displayShortage <= 0 ? '0' : '$displayShortage',
                                style: TextStyle(
                                  fontSize: AppTextSize.bodyMd,
                                  fontWeight: FontWeight.bold,
                                  color: displayShortage <= 0
                                      ? context.colors.textTertiary
                                      : showWithFuture ? AppColors.warning : AppColors.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('閉じる')),
              ],
            );
          },
        );
      },
    );
  }
}
