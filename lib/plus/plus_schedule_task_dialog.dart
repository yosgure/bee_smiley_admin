// プラスケジュール画面: 月カレンダーセルから開く「日付別タスク一覧」ダイアログと
// その場でタスク追加するダイアログ。_PlusScheduleContentState の private 状態を
// 直接参照するため part + extension で抽出。

// ignore_for_file: library_private_types_in_public_api, invalid_use_of_protected_member

part of '../plus_schedule_screen.dart';

extension PlusScheduleTaskDialog on _PlusScheduleContentState {
  void _showTasksForDateDialog(DateTime date, List<Map<String, dynamic>> tasks) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // 最新のタスクリストを取得
          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          final currentTasks = _tasksByDueDate[dateKey] ?? [];

          return AlertDialog(
            backgroundColor: context.colors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.task_alt, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('M月d日 (E)', 'ja').format(date)} のタスク',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentTasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('タスクはありません', style: TextStyle(color: context.colors.textSecondary)),
                    )
                  else
                    ...currentTasks.map((task) {
                      final studentName = task['studentName'] as String?;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _showEditTaskDialog(context, task, () {
                            _showTasksForDateDialog(date, _tasksByDueDate[dateKey] ?? []);
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.colors.borderMedium),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (studentName != null && studentName.isNotEmpty)
                                      Text(
                                        studentName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    Text(
                                      task['title'] ?? '',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: studentName != null ? context.colors.textSecondary : context.colors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  await _completeTask(task['id']);
                                  setDialogState(() {});
                                  setState(() {});
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(content: Text('タスクを完了しました')),
                                  );
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                color: AppColors.success,
                                tooltip: '完了',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  // タスク追加ボタン
                  InkWell(
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showAddTaskDialogForDate(date);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.primary.withValues(alpha: 0.05),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 18, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'タスクを追加',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
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

  // 日付指定でタスク追加ダイアログ（ダッシュボードと同等のUI）
  void _showAddTaskDialogForDate(DateTime date) {
    String inputMode = 'student'; // 'student' or 'custom'
    Map<String, dynamic>? selectedStudent;
    final titleController = TextEditingController();
    final commentController = TextEditingController();
    DateTime selectedDueDate = date;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSave = inputMode == 'student'
              ? (selectedStudent != null && titleController.text.isNotEmpty)
              : titleController.text.isNotEmpty;

          return AlertDialog(
            backgroundColor: context.colors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.task_alt, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('タスクを追加', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 入力モード切り替え
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => inputMode = 'student'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'student'
                                  ? AppColors.primary
                                  : context.colors.borderLight,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '生徒',
                              style: TextStyle(
                                color: inputMode == 'student'
                                    ? context.colors.textOnPrimary
                                    : context.colors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => inputMode = 'custom'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'custom'
                                  ? AppColors.primary
                                  : context.colors.borderLight,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '自由記述',
                              style: TextStyle(
                                color: inputMode == 'custom'
                                    ? context.colors.textOnPrimary
                                    : context.colors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 生徒選択（生徒モードのみ）
                  if (inputMode == 'student') ...[
                    InkWell(
                      onTap: () => _showStudentSelectionDialog(
                        selectedStudent,
                        (student) => setDialogState(() => selectedStudent = student),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: context.colors.borderMedium),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 20, color: context.colors.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedStudent == null
                                    ? '生徒を選択'
                                    : selectedStudent!['name'] as String,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: selectedStudent == null
                                      ? context.colors.textSecondary
                                      : context.colors.textPrimary,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 内容入力（生徒モード）
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: '内容を入力',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ] else
                    // 内容入力（自由記述モード）
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: '内容を入力',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  const SizedBox(height: 16),
                  // 期限選択
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDueDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDueDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.colors.borderMedium),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 20, color: AppColors.accent.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              DateFormat('M月d日 (E)', 'ja').format(selectedDueDate),
                              style: TextStyle(
                                fontSize: 15,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // コメント（生徒モードのみ）
                  if (inputMode == 'student') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        hintText: 'コメント（任意）',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: canSave
                    ? () async {
                        final studentNameValue = inputMode == 'student'
                            ? (selectedStudent?['name'] as String?)
                            : null;
                        await _addTaskForStudent(
                          studentNameValue,
                          titleController.text,
                          selectedDueDate,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('タスクを追加しました')),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: context.colors.textOnPrimary,
                ),
                child: const Text('追加'),
              ),
            ],
          );
        },
      ),
    );
  }
}
