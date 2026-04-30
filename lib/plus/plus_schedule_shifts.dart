// プラスケジュール画面のシフト管理 (シフト保存 / 前週・前月コピー / 貼り付け / 管理ダイアログ)。
// _PlusScheduleContentState の private 状態 (_shifts / _holidays / _weekStart / _staffList /
// _dateKey / _undoService 等) を直接参照するため part + extension で抽出。
//
// 含むメソッド:
//   _saveShiftsAndHoliday / _showShiftManagementDialog /
//   _copyFromPreviousWeek / _captureWeekSnapshot / _restoreWeekSnapshot /
//   _pasteWeekShifts / _copyCurrentWeekShifts / _copyFromPreviousMonth

// ignore_for_file: library_private_types_in_public_api, invalid_use_of_protected_member, unused_element

part of '../plus_schedule_screen.dart';

extension PlusScheduleShifts on _PlusScheduleContentState {
  Future<void> _saveShiftsAndHoliday(DateTime date, List<Map<String, dynamic>> shifts, bool isHoliday) async {
    try {
      final monthKey = DateFormat('yyyy-MM').format(date);
      final dayKey = date.day.toString();
      final dateKey = _dateKey(date);

      final docRef = FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(monthKey);

      // 既存データを取得
      final doc = await docRef.get();
      Map<String, dynamic> allDays = {};
      List<String> holidays = [];

      if (doc.exists) {
        allDays = Map<String, dynamic>.from(doc.data()?['days'] ?? {});
        holidays = List<String>.from(doc.data()?['holidays'] ?? []);
      }

      // この日のシフトを更新
      allDays[dayKey] = shifts;

      // 休み設定を更新
      if (isHoliday) {
        if (!holidays.contains(dayKey)) {
          holidays.add(dayKey);
        }
      } else {
        holidays.remove(dayKey);
      }

      // 保存
      await docRef.set({
        'classroom': 'ビースマイリープラス湘南藤沢',
        'days': allDays,
        'holidays': holidays,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ローカルデータを更新（該当月分のみ）
      setState(() {
        _shiftData[dateKey] = shifts;
        // 該当月の_holidaysを再構築
        _holidays.removeWhere((k) => k.startsWith('$monthKey-'));
        for (final h in holidays) {
          _holidays.add('$monthKey-${h.padLeft(2, '0')}');
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シフトを保存しました')),
        );
      }
    } catch (e) {
      debugPrint('Error saving shifts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存に失敗しました')),
        );
      }
    }
  }

  void _showShiftManagementDialog() {
    final currentMonth = DateFormat('yyyy-MM').format(_weekStart);
    final previousMonth = DateFormat('yyyy-MM').format(
      DateTime(_weekStart.year, _weekStart.month - 1, 1)
    );
    final weekLabel = '${DateFormat('M/d', 'ja').format(_weekStart)}〜${DateFormat('M/d', 'ja').format(_weekStart.add(const Duration(days: 5)))}';
    final previousWeekStart = _weekStart.subtract(const Duration(days: 7));
    final previousWeekLabel = '${DateFormat('M/d', 'ja').format(previousWeekStart)}〜${DateFormat('M/d', 'ja').format(previousWeekStart.add(const Duration(days: 5)))}';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: context.colors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.settings, color: AppColors.primary),
                SizedBox(width: 8),
                Text('スケジュール管理', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 週単位コピー
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.date_range, size: 18, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text(
                              '週単位コピー',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '現在の週: $weekLabel',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _copyFromPreviousWeek();
                            },
                            icon: const Icon(Icons.content_copy, size: 18),
                            label: Text('$previousWeekLabelのスケジュールをコピー'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: context.colors.textOnPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '※先週のシフトとレッスンを今週にコピーします',
                          style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 月単位コピー
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_month, size: 18, color: context.colors.textSecondary),
                            SizedBox(width: 8),
                            Text(
                              '月単位コピー',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '現在の月: ${DateFormat('yyyy年M月', 'ja').format(_weekStart)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _copyFromPreviousMonth(previousMonth, currentMonth);
                            },
                            icon: const Icon(Icons.content_copy, size: 18),
                            label: Text('${DateFormat('M月', 'ja').format(DateTime(_weekStart.year, _weekStart.month - 1, 1))}のシフトをコピー'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '※前月のシフトデータを今月にコピーします',
                          style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // シフト希望の取り込み
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.how_to_vote, size: 18, color: const Color(0xFF388E3C)),
                            const SizedBox(width: 8),
                            const Text(
                              'シフト希望の取り込み',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '対象月: ${DateFormat('yyyy年M月', 'ja').format(_weekStart)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('plus_shift_requests')
                              .doc(currentMonth)
                              .get(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Text('提出状況を確認中...',
                                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary));
                            }
                            int count = 0;
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final staffs = Map<String, dynamic>.from(
                                  snapshot.data!.data() as Map? ?? {});
                              final staffsMap =
                                  Map<String, dynamic>.from(staffs['staffs'] ?? {});
                              count = staffsMap.length;
                            }
                            return Text(
                              '$count人が提出済み',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: count > 0 ? const Color(0xFF2E7D32) : context.colors.textSecondary,
                                  fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              final saved = await showPlusShiftDecisionDialog(
                                context,
                                DateTime(_weekStart.year, _weekStart.month, 1),
                              );
                              if (saved == true && mounted) {
                                await _loadShiftData();
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.edit_calendar, size: 18),
                            label: const Text('シフトを決定する'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF388E3C),
                              foregroundColor: context.colors.textOnPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '※希望をカレンダー上で確認しながら決定し、そのまま実シフトに反映できます',
                          style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 先週のスケジュールを今週にコピー
  Future<void> _copyFromPreviousWeek() async {
    final previousWeekStart = _weekStart.subtract(const Duration(days: 7));
    final currentWeekStartDate =
        DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    final currentWeekEndDate = currentWeekStartDate
        .add(const Duration(days: 5, hours: 23, minutes: 59, seconds: 59));

    try {
      await UndoService.run<Map<String, dynamic>>(
        context: context,
        label: '先週のスケジュールをコピー',
        doneMessage: '先週のスケジュールをコピーしました',
        captureSnapshot: () async =>
            _captureWeekSnapshot(currentWeekStartDate, currentWeekEndDate),
        execute: () async {
          // 1. 先週のシフトに必要な月docを全て取得
          final previousMonthKeys = <String>{};
          for (int i = 0; i < 6; i++) {
            previousMonthKeys.add(DateFormat('yyyy-MM')
                .format(previousWeekStart.add(Duration(days: i))));
          }
          final previousMonthDocs = <String, Map<String, dynamic>>{};
          for (final mk in previousMonthKeys) {
            final d = await FirebaseFirestore.instance
                .collection('plus_shifts')
                .doc(mk)
                .get();
            if (d.exists) {
              previousMonthDocs[mk] =
                  Map<String, dynamic>.from(d.data()?['days'] ?? {});
            }
          }

          // 2. 先週のレッスンを取得
          final previousWeekStartDate = DateTime(previousWeekStart.year,
              previousWeekStart.month, previousWeekStart.day);
          final previousWeekEndDate = previousWeekStartDate.add(
              const Duration(days: 5, hours: 23, minutes: 59, seconds: 59));

          final previousLessonsSnapshot = await FirebaseFirestore.instance
              .collection('plus_lessons')
              .where('date',
                  isGreaterThanOrEqualTo:
                      Timestamp.fromDate(previousWeekStartDate))
              .where('date',
                  isLessThanOrEqualTo: Timestamp.fromDate(previousWeekEndDate))
              .get();

          // 3. 先週のシフトを今週にコピー
          final shiftUpdatesByMonth =
              <String, Map<String, List<Map<String, dynamic>>>>{};
          final localUpdates = <String, List<Map<String, dynamic>>>{};
          for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
            final previousDate =
                previousWeekStart.add(Duration(days: dayIndex));
            final currentDate = _weekStart.add(Duration(days: dayIndex));
            final prevMk = DateFormat('yyyy-MM').format(previousDate);
            final prevDayKey = previousDate.day.toString();
            final curMk = DateFormat('yyyy-MM').format(currentDate);
            final curDayKey = currentDate.day.toString();

            final prevDays = previousMonthDocs[prevMk];
            if (prevDays != null && prevDays.containsKey(prevDayKey)) {
              final shifts = prevDays[prevDayKey];
              if (shifts is List) {
                final copied = shifts
                    .map((s) => Map<String, dynamic>.from(s as Map))
                    .toList();
                shiftUpdatesByMonth.putIfAbsent(curMk, () => {})[curDayKey] =
                    copied;
                localUpdates[_dateKey(currentDate)] = copied;
              }
            }
          }

          for (final entry in shiftUpdatesByMonth.entries) {
            final mk = entry.key;
            final updates = entry.value;
            final shiftDocRef = FirebaseFirestore.instance
                .collection('plus_shifts')
                .doc(mk);
            final shiftDoc = await shiftDocRef.get();

            if (shiftDoc.exists) {
              final existingDays =
                  Map<String, dynamic>.from(shiftDoc.data()?['days'] ?? {});
              updates.forEach((key, value) {
                existingDays[key] = value;
              });
              await shiftDocRef.update({
                'days': existingDays,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } else {
              await shiftDocRef.set({
                'classroom': 'ビースマイリープラス湘南藤沢',
                'days': updates,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }

          if (localUpdates.isNotEmpty && mounted) {
            setState(() {
              localUpdates.forEach((key, value) {
                _shiftData[key] = value;
              });
            });
          }

          // 4. 今週の既存レッスンを削除
          final existingLessonsSnapshot = await FirebaseFirestore.instance
              .collection('plus_lessons')
              .where('date',
                  isGreaterThanOrEqualTo:
                      Timestamp.fromDate(currentWeekStartDate))
              .where('date',
                  isLessThanOrEqualTo: Timestamp.fromDate(currentWeekEndDate))
              .get();

          final deleteBatch = FirebaseFirestore.instance.batch();
          for (final doc in existingLessonsSnapshot.docs) {
            deleteBatch.delete(doc.reference);
          }
          await deleteBatch.commit();

          // 5. 先週のレッスンを今週にコピー（日付を+7日）
          if (previousLessonsSnapshot.docs.isNotEmpty) {
            final addBatch = FirebaseFirestore.instance.batch();
            for (final doc in previousLessonsSnapshot.docs) {
              final data = doc.data();
              final previousDate = (data['date'] as Timestamp).toDate();
              final newDate = previousDate.add(const Duration(days: 7));
              final newRef = FirebaseFirestore.instance
                  .collection('plus_lessons')
                  .doc();
              addBatch.set(newRef, {
                ...data,
                'date': Timestamp.fromDate(newDate),
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
            await addBatch.commit();
          }

          await _loadLessonsForWeek();
          await _loadShiftData();
        },
        undo: (snap) async {
          await _restoreWeekSnapshot(snap);
          if (mounted) {
            await _loadLessonsForWeek();
            await _loadShiftData();
            setState(() {});
          }
        },
      );
    } catch (e) {
      debugPrint('Error copying from previous week: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  /// 指定週（[weekStart], [weekEnd]）の plus_shifts / plus_lessons の
  /// 現在の状態をスナップショットとして取得する。
  Future<Map<String, dynamic>> _captureWeekSnapshot(
    DateTime weekStart,
    DateTime weekEnd,
  ) async {
    // shifts: 各日について pre-existing days[dayKey] を保存（null は「キー無し」）
    final shiftsByMonth = <String, Map<String, dynamic>>{};
    for (int i = 0; i < 6; i++) {
      final d = weekStart.add(Duration(days: i));
      final mk = DateFormat('yyyy-MM').format(d);
      shiftsByMonth.putIfAbsent(mk, () => {});
    }
    for (final mk in shiftsByMonth.keys) {
      final doc = await FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(mk)
          .get();
      final days = doc.exists
          ? Map<String, dynamic>.from(doc.data()?['days'] ?? {})
          : <String, dynamic>{};
      final result = <String, dynamic>{};
      for (int i = 0; i < 6; i++) {
        final d = weekStart.add(Duration(days: i));
        if (DateFormat('yyyy-MM').format(d) != mk) continue;
        final dk = d.day.toString();
        result[dk] = days.containsKey(dk) ? days[dk] : null;
      }
      shiftsByMonth[mk] = {
        'docExists': doc.exists,
        'days': result,
      };
    }

    final lessonsSnap = await FirebaseFirestore.instance
        .collection('plus_lessons')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(weekEnd))
        .get();
    final lessons = lessonsSnap.docs
        .map((d) => {'id': d.id, 'data': d.data()})
        .toList();

    return {
      'weekStart': Timestamp.fromDate(weekStart),
      'weekEnd': Timestamp.fromDate(weekEnd),
      'shiftsByMonth': shiftsByMonth,
      'lessons': lessons,
    };
  }

  /// スナップショットから plus_shifts / plus_lessons の状態を復元する。
  Future<void> _restoreWeekSnapshot(Map<String, dynamic> snap) async {
    final weekStart = (snap['weekStart'] as Timestamp).toDate();
    final weekEnd = (snap['weekEnd'] as Timestamp).toDate();

    // shifts 復元
    final shiftsByMonth =
        Map<String, dynamic>.from(snap['shiftsByMonth'] as Map);
    for (final entry in shiftsByMonth.entries) {
      final mk = entry.key;
      final info = Map<String, dynamic>.from(entry.value as Map);
      final docExisted = info['docExists'] as bool;
      final preDays = Map<String, dynamic>.from(info['days'] as Map);
      final docRef =
          FirebaseFirestore.instance.collection('plus_shifts').doc(mk);
      final cur = await docRef.get();
      final curDays =
          cur.exists ? Map<String, dynamic>.from(cur.data()?['days'] ?? {}) : <String, dynamic>{};
      preDays.forEach((dk, preValue) {
        if (preValue == null) {
          curDays.remove(dk);
        } else {
          curDays[dk] = preValue;
        }
      });
      if (cur.exists) {
        await docRef.update({
          'days': curDays,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (docExisted || curDays.isNotEmpty) {
        await docRef.set({
          'classroom': 'ビースマイリープラス湘南藤沢',
          'days': curDays,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // lessons 復元: 現在の週のレッスンを一掃 → スナップショット時のレッスンを元の ID で再作成
    final curLessons = await FirebaseFirestore.instance
        .collection('plus_lessons')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(weekEnd))
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in curLessons.docs) {
      batch.delete(d.reference);
    }
    final lessons = (snap['lessons'] as List).cast<Map<String, dynamic>>();
    for (final l in lessons) {
      final id = l['id'] as String;
      final data = Map<String, dynamic>.from(l['data'] as Map);
      final ref =
          FirebaseFirestore.instance.collection('plus_lessons').doc(id);
      batch.set(ref, data);
    }
    await batch.commit();
  }

  // 現在の週のシフトとレッスンをコピー
  void _copyCurrentWeekShifts() {
    final copiedShifts = <int, List<Map<String, dynamic>>>{};

    for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
      final date = _weekStart.add(Duration(days: dayIndex));
      final shifts = _shiftData[_dateKey(date)] ?? [];

      if (shifts.isNotEmpty) {
        copiedShifts[dayIndex] = shifts.map((s) => Map<String, dynamic>.from(s)).toList();
      }
    }
    
    // レッスンもコピー（docIdを除外）
    final copiedLessons = _lessons.map((lesson) {
      final copy = Map<String, dynamic>.from(lesson);
      copy.remove('docId'); // 新規作成時に新しいIDが付与されるように
      return copy;
    }).toList();
    
    setState(() {
      _copiedWeekShifts = copiedShifts;
      _copiedWeekLessons = copiedLessons;
      _copiedWeekLabel = '${DateFormat('M/d', 'ja').format(_weekStart)}〜${DateFormat('M/d', 'ja').format(_weekStart.add(const Duration(days: 5)))}';
    });
  }

  // コピーしたシフトとレッスンを現在の週に貼り付け
  Future<void> _pasteWeekShifts() async {
    if (_copiedWeekShifts == null && _copiedWeekLessons == null) return;

    final currentWeekStartDate =
        DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    final currentWeekEndDate = currentWeekStartDate
        .add(const Duration(days: 5, hours: 23, minutes: 59, seconds: 59));

    try {
      await UndoService.run<Map<String, dynamic>>(
        context: context,
        label: 'スケジュールを貼り付け',
        doneMessage: 'スケジュールを貼り付けました',
        captureSnapshot: () async =>
            _captureWeekSnapshot(currentWeekStartDate, currentWeekEndDate),
        execute: () async {
          final weekKey = DateFormat('yyyy-MM-dd').format(_weekStart);

          // シフトの貼り付け
          if (_copiedWeekShifts != null) {
            final updatesByMonth =
                <String, Map<String, List<Map<String, dynamic>>>>{};
            final localUpdates = <String, List<Map<String, dynamic>>>{};

            for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
              final date = _weekStart.add(Duration(days: dayIndex));
              final mk = DateFormat('yyyy-MM').format(date);
              final dayKey = date.day.toString();

              if (_copiedWeekShifts!.containsKey(dayIndex)) {
                final shifts = _copiedWeekShifts![dayIndex]!;
                updatesByMonth.putIfAbsent(mk, () => {})[dayKey] = shifts;
                localUpdates[_dateKey(date)] = shifts;
              }
            }

            for (final entry in updatesByMonth.entries) {
              final mk = entry.key;
              final updates = entry.value;
              final docRef = FirebaseFirestore.instance
                  .collection('plus_shifts')
                  .doc(mk);
              final doc = await docRef.get();

              if (doc.exists) {
                final existingDays =
                    Map<String, dynamic>.from(doc.data()?['days'] ?? {});
                updates.forEach((key, value) {
                  existingDays[key] = value;
                });
                await docRef.update({
                  'days': existingDays,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              } else {
                await docRef.set({
                  'classroom': 'ビースマイリープラス湘南藤沢',
                  'days': updates,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
            }

            if (mounted) {
              setState(() {
                localUpdates.forEach((key, value) {
                  _shiftData[key] = value;
                });
              });
            }
          }

          // レッスンの貼り付け
          if (_copiedWeekLessons != null && _copiedWeekLessons!.isNotEmpty) {
            final batch = FirebaseFirestore.instance.batch();
            final lessonsRef = FirebaseFirestore.instance
                .collection('plus_lessons')
                .doc(weekKey)
                .collection('items');

            final existingLessons = await lessonsRef.get();
            for (final doc in existingLessons.docs) {
              batch.delete(doc.reference);
            }
            for (final lesson in _copiedWeekLessons!) {
              final newRef = lessonsRef.doc();
              batch.set(newRef, {
                ...lesson,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
            await batch.commit();

            await _loadLessonsForWeek();
          }
        },
        undo: (snap) async {
          await _restoreWeekSnapshot(snap);
          if (mounted) {
            await _loadLessonsForWeek();
            await _loadShiftData();
            setState(() {});
          }
        },
      );
    } catch (e) {
      debugPrint('Error pasting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  Future<void> _copyFromPreviousMonth(String fromMonth, String toMonth) async {
    try {
      // 前月ドキュメント存在チェック（無ければ何もしない）
      final fromCheck = await FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(fromMonth)
          .get();
      if (!fromCheck.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('前月のシフトデータがありません')),
          );
        }
        return;
      }
      if (!mounted) return;

      await UndoService.run<Map<String, dynamic>>(
        context: context,
        label: '前月のスケジュールをコピー',
        doneMessage: '前月のスケジュールをコピーしました',
        captureSnapshot: () async {
          final toDoc = await FirebaseFirestore.instance
              .collection('plus_shifts')
              .doc(toMonth)
              .get();
          return {
            'toMonth': toMonth,
            'docExists': toDoc.exists,
            'data': toDoc.exists ? toDoc.data() : null,
          };
        },
        execute: () async {
          final fromDoc = await FirebaseFirestore.instance
              .collection('plus_shifts')
              .doc(fromMonth)
              .get();
          final fromData = fromDoc.data()!;
          final fromDays = fromData['days'] as Map<String, dynamic>? ?? {};

          await FirebaseFirestore.instance
              .collection('plus_shifts')
              .doc(toMonth)
              .set({
            'classroom':
                fromData['classroom'] ?? 'ビースマイリープラス湘南藤沢',
            'days': fromDays,
            'copiedFrom': fromMonth,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            setState(() {
              _shiftData.removeWhere((k, _) => k.startsWith('$toMonth-'));
              _holidays.removeWhere((k) => k.startsWith('$toMonth-'));
              fromDays.forEach((dayKey, value) {
                if (value is List) {
                  final dateKey = '$toMonth-${dayKey.padLeft(2, '0')}';
                  _shiftData[dateKey] = List<Map<String, dynamic>>.from(
                    value.map((e) => Map<String, dynamic>.from(e as Map)),
                  );
                }
              });
              _loadedShiftMonths.add(toMonth);
            });
          }
        },
        undo: (snap) async {
          final docRef = FirebaseFirestore.instance
              .collection('plus_shifts')
              .doc(snap['toMonth'] as String);
          final docExisted = snap['docExists'] as bool;
          if (docExisted) {
            await docRef.set(Map<String, dynamic>.from(snap['data'] as Map));
          } else {
            await docRef.delete();
          }
          if (mounted) {
            _loadedShiftMonths.remove(snap['toMonth']);
            await _loadShiftData();
            setState(() {});
          }
        },
      );
    } catch (e) {
      debugPrint('Error copying shifts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シフトのコピーに失敗しました')),
        );
      }
    }
  }
}
