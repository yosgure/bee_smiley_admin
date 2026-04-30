// plus_schedule_screen.dart の編集タスク・生徒詳細ナビゲーション (549行) を切り出した part。
// extension で State の private メンバを参照可能。
part of '../plus_schedule_screen.dart';

extension _PlusScheduleDialogsAndNav on _PlusScheduleContentState {
  void _showEditTaskDialog(BuildContext parentContext, Map<String, dynamic> task, VoidCallback onUpdate) {
    final titleController = TextEditingController(text: task['title'] ?? '');
    DateTime? dueDate = task['dueDate'] != null 
        ? (task['dueDate'] as Timestamp).toDate() 
        : null;
    
    showDialog(
      context: parentContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Dialog(
            backgroundColor: context.colors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ヘッダー
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, color: AppColors.primary, size: 22),
                        const SizedBox(width: 10),
                        const Text('タスクを編集', style: TextStyle(fontSize: AppTextSize.titleSm, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: Icon(Icons.close, color: context.colors.textTertiary, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                  // コンテンツ
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 生徒名
                        if (task['studentName'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 16, color: context.colors.textSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  task['studentName'] as String,
                                  style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        // タスク内容
                        Text('内容', style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: titleController,
                          maxLines: null,
                          minLines: 3,
                          decoration: InputDecoration(
                            hintText: 'タスクの内容を入力...',
                            hintStyle: TextStyle(color: context.colors.textHint),
                            filled: true,
                            fillColor: context.colors.tagBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: context.colors.borderLight),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: context.colors.borderLight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                          style: const TextStyle(fontSize: AppTextSize.bodyMd, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        // 期限日
                        Text('期限日', style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: dueDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setDialogState(() => dueDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.colors.tagBg,
                              border: Border.all(color: context.colors.borderLight),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 18, color: dueDate != null ? AppColors.primary : context.colors.textSecondary),
                                const SizedBox(width: 10),
                                Text(
                                  dueDate != null ? DateFormat('yyyy年M月d日').format(dueDate!) : '期限を設定...',
                                  style: TextStyle(
                                    fontSize: AppTextSize.bodyMd,
                                    color: dueDate != null ? context.colors.textPrimary : context.colors.textHint,
                                  ),
                                ),
                                const Spacer(),
                                if (dueDate != null)
                                  GestureDetector(
                                    onTap: () => setDialogState(() => dueDate = null),
                                    child: Icon(Icons.close, size: 18, color: context.colors.iconMuted),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // アクション
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(
                      children: [
                        // 削除ボタン
                        TextButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: dialogContext,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: context.colors.cardBg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                title: const Text('タスクを削除'),
                                content: const Text('このタスクを削除しますか？'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('キャンセル'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('削除', style: TextStyle(color: AppColors.error)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _completeTask(task['id']);
                              onUpdate();
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('削除'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.errorBorder,
                          ),
                        ),
                        const Spacer(),
                        // 保存ボタン
                        ElevatedButton(
                          onPressed: () async {
                            final newTitle = titleController.text.trim();
                            if (newTitle.isEmpty) return;

                            try {
                              await FirebaseFirestore.instance
                                  .collection('plus_tasks')
                                  .doc(task['id'])
                                  .update({
                                'title': newTitle,
                                'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
                              });
                              await _loadAllTasks();
                              onUpdate();
                              if (dialogContext.mounted) Navigator.pop(dialogContext);
                            } catch (e) {
                              debugPrint('Error updating task: $e');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: context.colors.textOnPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  // 生徒のタスクを取得
  List<Map<String, dynamic>> _getTasksForStudent(String studentName) {
    return _allTasks.where((t) => t['studentName'] == studentName).toList();
  }
  
  // 生徒メモを先読み（非同期でバックグラウンド読み込み）
  Future<void> _preloadStudentNotes(List<Map<String, dynamic>> lessons) async {
    final studentNames = lessons
        .map((l) => l['studentName'] as String?)
        .where((name) => name != null && name.isNotEmpty)
        .toSet();
    
    for (var name in studentNames) {
      if (name != null && !_studentNotes.containsKey(name)) {
        await _loadStudentNotes(name);
      }
    }
    
    // 読み込み完了後に再描画
    if (mounted) {
      setState(() {});
    }
  }
  
  // 生徒の全情報があるかチェック（ホバー表示用）
  bool _hasStudentInfo(String studentName) {
    final notes = _studentNotes[studentName];
    final tasks = _getTasksForStudent(studentName);
    
    if (notes != null) {
      if ((notes['therapyPlan'] ?? '').isNotEmpty) return true;
      if ((notes['schoolVisit'] ?? '').isNotEmpty) return true;
      if ((notes['schoolConsultation'] ?? '').isNotEmpty) return true;
      if ((notes['moveRequest'] ?? '').isNotEmpty) return true;
    }
    if (tasks.isNotEmpty) return true;
    
    return false;
  }

  // 生徒名から生徒詳細画面に遷移
  void _navigateToStudentDetail(String studentName) {
    final student = _allStudents.firstWhere(
      (s) => s['name'] == studentName,
      orElse: () => <String, dynamic>{},
    );
    if (student.isEmpty) return;
    final familyUid = student['familyUid'] as String? ?? '';
    final firstName = student['firstName'] as String? ?? '';
    if (familyUid.isEmpty || firstName.isEmpty) return;
    final studentId = '${familyUid}_$firstName';
    final isWide = MediaQuery.of(context).size.width >= 600;
    if (isWide) {
      AdminShell.showOverlay(
        context,
        StudentDetailScreen(
          studentId: studentId,
          studentName: studentName,
          onClose: () => AdminShell.hideOverlay(context),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentDetailScreen(
            studentId: studentId,
            studentName: studentName,
          ),
        ),
      );
    }
  }

  // familiesコレクションから全児童リストを取得（プラスのみ）
  Future<void> _loadStudentsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('families')
          .get();

      final students = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final familyUid = data['uid'] as String? ?? doc.id;
        final lastName = data['lastName'] as String? ?? '';
        final lastNameKana = data['lastNameKana'] as String? ?? '';
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

        for (var child in children) {
          final firstName = child['firstName'] as String? ?? '';
          final classrooms = getChildClassrooms(child);
          final classroom = classrooms.join(', ');

          // プラスの教室のみ
          if (firstName.isNotEmpty && classrooms.any((c) => c.contains('プラス'))) {
            // studentIdを生成（childにstudentIdがあればそれを使用）
            final studentId = child['studentId'] ?? '${familyUid}_$firstName';
            students.add({
            'name': '$lastName $firstName'.trim(),
            'firstName': firstName,
            'lastName': lastName,
            'lastNameKana': lastNameKana,
            'classroom': classroom,
            'course': child['course'] ?? '',
            'profileUrl': child['profileUrl'] ?? '',
            'meetingUrls': child['meetingUrls'] ?? [],
            'familyUid': familyUid,
            'studentId': studentId,
            'birthDate': child['birthDate'] ?? '',
          });
          }
        }
      }
      
      // ふりがな順でソート
      students.sort((a, b) {
        final kanaA = (a['lastNameKana'] as String?) ?? '';
        final kanaB = (b['lastNameKana'] as String?) ?? '';
        return kanaA.compareTo(kanaB);
      });

      // ai_student_profiles から自動取得済みのHUGプロフィールURLを上書き反映
      try {
        final profilesSnap = await FirebaseFirestore.instance
            .collection('ai_student_profiles')
            .get();
        final hugUrlByStudentId = <String, String>{};
        for (final doc in profilesSnap.docs) {
          final url = doc.data()['hugProfileUrl'] as String? ?? '';
          if (url.isNotEmpty) hugUrlByStudentId[doc.id] = url;
        }
        for (final s in students) {
          final sid = s['studentId'] as String?;
          if (sid == null) continue;
          final hugUrl = hugUrlByStudentId[sid];
          if (hugUrl != null && hugUrl.isNotEmpty) {
            s['profileUrl'] = hugUrl;
          }
        }
      } catch (e) {
        debugPrint('Error loading hugProfileUrl: $e');
      }

      if (mounted) {
        setState(() {
          _allStudents = students;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
    }
  }

  // Firestoreから週のレッスンデータを読み込み
  Future<void> _loadLessonsForWeek({bool showLoading = true}) async {
  if (!mounted) return;
  
  if (showLoading) {
    setState(() {
      _isLoadingLessons = true;
    });
  }
    
    try {
      // 週の開始日（月曜日）と終了日（土曜日）を日付のみで計算
      final weekStartDate = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
      final saturdayDate = weekStartDate.add(const Duration(days: 5));
      final weekEndDate = DateTime(saturdayDate.year, saturdayDate.month, saturdayDate.day, 23, 59, 59);
      
      // 開始日以降のデータを取得（クライアント側で終了日フィルタリング）
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStartDate))
          .orderBy('date')
          .get();
      
      if (!mounted) return;
      
      final lessons = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // dateがnullまたは不正な場合はスキップ
        final dateField = data['date'];
        if (dateField == null || dateField is! Timestamp) continue;
        
        final date = dateField.toDate();
        
        // 週の終了日より後ならスキップ
        if (date.isAfter(weekEndDate)) continue;
        
        // 日付のみで比較（時刻を無視）
        final dateOnly = DateTime(date.year, date.month, date.day);
        final weekStartOnly = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
        final dayIndex = dateOnly.difference(weekStartOnly).inDays;
        
        // 週の範囲外はスキップ
        if (dayIndex < 0 || dayIndex > 5) continue;
        
        lessons.add({
          'id': doc.id,
          'dayIndex': dayIndex,
          'slotIndex': data['slotIndex'] ?? 0,
          'studentName': data['studentName'] ?? '',
          'teachers': List<String>.from(data['teachers'] ?? []),
          'room': data['room'] ?? '',
          'course': data['course'] ?? '通常',
          'note': data['note'] ?? '',
          'link': data['link'] ?? '',
          'date': date,
          'isCustomEvent': data['isCustomEvent'] ?? false,
          'isEvent': data['isEvent'] ?? false,
          'title': data['title'] ?? '',
          'order': data['order'] ?? (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
        });
      }
      
      if (mounted) {
        // 同じセル内の順序を order（作成順）でソート
        lessons.sort((a, b) {
          final dayCompare = (a['dayIndex'] as int).compareTo(b['dayIndex'] as int);
          if (dayCompare != 0) return dayCompare;
          final slotCompare = (a['slotIndex'] as int).compareTo(b['slotIndex'] as int);
          if (slotCompare != 0) return slotCompare;
          return (a['order'] as int).compareTo(b['order'] as int);
        });
        
        setState(() {
          _lessons = lessons;
          _isLoadingLessons = false;
        });
        
        // 生徒メモを先読み（UIをブロックしない）
        _preloadStudentNotes(lessons);
        _loadCellMemosForWeek();
      }
    } catch (e) {
      debugPrint('Error loading lessons: $e');
      if (mounted) {
        setState(() {
          _isLoadingLessons = false;
        });
      }
    }
  }

  // 月カレンダー用のレッスンを読み込み
  Future<void> _loadLessonsForMonth() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingMonthLessons = true;
    });
    
    try {
      final monthStart = DateTime(_monthViewDate.year, _monthViewDate.month, 1);
      final monthEnd = DateTime(_monthViewDate.year, _monthViewDate.month + 1, 0, 23, 59, 59);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .orderBy('date')
          .get();
      
      if (!mounted) return;
      
      final lessons = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final dateField = data['date'];
        if (dateField == null || dateField is! Timestamp) continue;
        
        final date = dateField.toDate();
        
        lessons.add({
          'id': doc.id,
          'date': date,
          'slotIndex': data['slotIndex'] ?? 0,
          'studentName': data['studentName'] ?? '',
          'teachers': List<String>.from(data['teachers'] ?? []),
          'room': data['room'] ?? '',
          'course': data['course'] ?? '通常',
          'note': data['note'] ?? '',
          'isCustomEvent': data['isCustomEvent'] ?? false,
          'isEvent': data['isEvent'] ?? false,
          'title': data['title'] ?? '',
          'order': data['order'] ?? 0,
        });
      }
      
      lessons.sort((a, b) {
        final dateCompare = (a['date'] as DateTime).compareTo(b['date'] as DateTime);
        if (dateCompare != 0) return dateCompare;
        final slotCompare = (a['slotIndex'] as int).compareTo(b['slotIndex'] as int);
        if (slotCompare != 0) return slotCompare;
        return (a['order'] as int).compareTo(b['order'] as int);
      });
      
      if (mounted) {
        setState(() {
          _monthLessons = lessons;
          _isLoadingMonthLessons = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading month lessons: $e');
      if (mounted) {
        setState(() {
          _isLoadingMonthLessons = false;
        });
      }
    }
  }
  
  // 特定の日付のレッスンを取得
  List<Map<String, dynamic>> _getLessonsForDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return _monthLessons.where((lesson) {
      final lessonDate = lesson['date'] as DateTime;
      return lessonDate.year == dateOnly.year &&
             lessonDate.month == dateOnly.month &&
             lessonDate.day == dateOnly.day;
    }).toList();
  }
}
