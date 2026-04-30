// プラスケジュール画面: 月カレンダービュー (日曜除く 6 列レイアウト)。
// セルにレッスンを 4 コマ表示、ホバーで詳細ポップアップ、クリックで週ビュー遷移。
// _PlusScheduleContentState の private 状態 (_monthViewDate / _selectedFilters /
// _courseColors / _timeSlots / _isHoliday / _hideCurrentOverlay 他) を直接参照。

// ignore_for_file: library_private_types_in_public_api, invalid_use_of_protected_member

part of '../plus_schedule_screen.dart';

extension PlusScheduleCalendar on _PlusScheduleContentState {
  Widget _buildMonthCalendar() {
    final year = _monthViewDate.year;
    final month = _monthViewDate.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final lastDayOfMonth = DateTime(year, month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;

    // 月曜始まりで計算（日曜は除外）
    final firstWeekday = firstDayOfMonth.weekday; // 1=月曜, 7=日曜
    final startOffset = firstWeekday - 1;

    final today = DateTime.now();
    final days = ['月', '火', '水', '木', '金', '土']; // 日曜を除外

    // 日付リストを作成（日曜を除く）
    List<DateTime?> calendarDays = [];

    // 月初の空白
    for (int i = 0; i < startOffset; i++) {
      calendarDays.add(null);
    }

    // 各日付を追加（日曜日以外）
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday != DateTime.sunday) {
        calendarDays.add(date);
      }
    }

    // 週ごとに分割（6列）
    List<List<DateTime?>> weeks = [];
    List<DateTime?> currentWeek = [];

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);

      if (date.weekday == DateTime.sunday) continue;

      if (currentWeek.isEmpty && weeks.isEmpty) {
        for (int i = 0; i < date.weekday - 1; i++) {
          currentWeek.add(null);
        }
      }

      currentWeek.add(date);

      if (date.weekday == DateTime.saturday) {
        weeks.add(currentWeek);
        currentWeek = [];
      }
    }

    if (currentWeek.isNotEmpty) {
      while (currentWeek.length < 6) {
        currentWeek.add(null);
      }
      weeks.add(currentWeek);
    }

    return Container(
      color: context.colors.cardBg,
      child: Column(
        children: [
          // 曜日ヘッダー（日曜除く）
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              border: Border(bottom: BorderSide(color: context.colors.borderMedium)),
            ),
            child: Row(
              children: List.generate(6, (index) {
                final isSaturday = index == 5;
                return Expanded(
                  child: Center(
                    child: Text(
                      days[index],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.body,
                        color: isSaturday ? AppColors.primary : context.colors.textPrimary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // カレンダーグリッド
          Expanded(
            child: Column(
              children: weeks.map((week) {
                return Expanded(
                  child: Row(
                    children: week.map((date) {
                      if (date == null) {
                        return Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: context.colors.chipBg,
                              border: Border(
                                right: BorderSide(color: context.colors.borderMedium),
                                bottom: BorderSide(color: context.colors.borderMedium),
                              ),
                            ),
                          ),
                        );
                      }

                      final isToday = date.year == today.year &&
                                     date.month == today.month &&
                                     date.day == today.day;
                      final isSaturday = date.weekday == DateTime.saturday;
                      final isHoliday = _isHoliday(date);

                      return Expanded(
                        child: _buildMonthCalendarCell(
                          date, date.day, isToday, isSaturday, isHoliday,
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 月カレンダーのセル
  Widget _buildMonthCalendarCell(
    DateTime date, int dayNumber, bool isToday, bool isSaturday, bool isHoliday,
  ) {
    final lessons = _getLessonsForDate(date);

    // フィルタリング適用
    var filteredLessons = lessons;
    if (!_selectedFilters.contains('all')) {
      if (_selectedFilters.isEmpty) {
        filteredLessons = [];
      } else {
        filteredLessons = lessons.where((lesson) {
          final teachers = lesson['teachers'] as List<dynamic>? ?? [];
          if (teachers.contains('全員')) return true;
          for (final teacher in teachers) {
            if (_selectedFilters.contains(teacher)) return true;
          }
          return false;
        }).toList();
      }
    }

    // ホバー用のキー
    final cellKey = GlobalKey();

    void showCellOverlay() {
      if (filteredLessons.isEmpty) return;

      _hideCurrentOverlay();

      final renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final overlay = Overlay.of(context);
      final offset = renderBox.localToGlobal(Offset.zero);
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;

      const popupWidth = 220.0;
      final bool showOnLeft = offset.dx + renderBox.size.width + popupWidth > screenWidth;
      final bool showAbove = offset.dy > screenHeight * 0.5;

      _currentOverlay = OverlayEntry(
        builder: (ctx) {
          double left;
          if (showOnLeft) {
            left = offset.dx - popupWidth - 4;
          } else {
            left = offset.dx + renderBox.size.width + 4;
          }
          if (left < 4) left = 4;

          final popupContent = Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: context.colors.dialogBg,
            child: Container(
              width: popupWidth,
              constraints: BoxConstraints(maxHeight: screenHeight * 0.6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderMedium),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('M月d日 (E)', 'ja').format(date),
                        style: const TextStyle(
                          fontSize: AppTextSize.titleSm,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 時間帯ごとのレッスン（タスクなし）
                      ..._timeSlots.asMap().entries.map((entry) {
                        final slotIndex = entry.key;
                        final slotLabel = entry.value;
                        final slotLessons = filteredLessons.where((l) => l['slotIndex'] == slotIndex).toList();

                        if (slotLessons.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slotLabel,
                              style: TextStyle(
                                fontSize: AppTextSize.caption,
                                fontWeight: FontWeight.bold,
                                color: context.colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...slotLessons.map((lesson) {
                              final course = lesson['course'] as String? ?? '通常';
                              final color = _courseColors[course] ?? AppColors.primary;
                              final teachers = lesson['teachers'] as List<dynamic>? ?? [];
                              final room = lesson['room'] as String? ?? '';
                              final teacherNames = teachers.isNotEmpty
                                  ? teachers.map((t) {
                                      final lastName = t.toString().split(' ').first;
                                      return lastName.length > 2 ? lastName.substring(0, 2) : lastName;
                                    }).join('・')
                                  : '';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        lesson['studentName'] ?? '',
                                        style: const TextStyle(
                                          fontSize: AppTextSize.body,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (teacherNames.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        teacherNames,
                                        style: TextStyle(
                                          fontSize: AppTextSize.caption,
                                          color: context.colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                    if (room.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        room,
                                        style: TextStyle(
                                          fontSize: AppTextSize.caption,
                                          color: context.colors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          );

          if (showAbove) {
            return Positioned(
              bottom: screenHeight - offset.dy + 4,
              left: left,
              child: popupContent,
            );
          } else {
            return Positioned(
              top: offset.dy,
              left: left,
              child: popupContent,
            );
          }
        },
      );

      overlay.insert(_currentOverlay!);
    }

    return GestureDetector(
      onTap: () {
        _hideCurrentOverlay();
        setState(() {
          _weekStart = _getMonday(date);
          _viewMode = 0;
        });
        _loadShiftData();
        _loadLessonsForWeek();
        _loadAllTasks();
      },
      child: MouseRegion(
        key: cellKey,
        cursor: SystemMouseCursors.click,
        onEnter: (_) => showCellOverlay(),
        onExit: (_) => _hideCurrentOverlay(),
        child: Container(
          decoration: BoxDecoration(
            color: isHoliday ? context.colors.chipBg : context.colors.cardBg,
            border: Border(
              right: BorderSide(color: context.colors.borderMedium),
              bottom: BorderSide(color: context.colors.borderMedium),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 日付ヘッダー（中央寄せ、タスク件数なし）
              Container(
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isToday ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: AppTextSize.body,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday
                            ? Colors.white
                            : (isSaturday ? AppColors.primary : context.colors.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
              // 4コマ（時間帯）ごとのレッスン表示 - 縦に4列
              if (!isHoliday)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(4, (slotIndex) {
                        final slotLessons = filteredLessons.where((l) => l['slotIndex'] == slotIndex).toList();
                        final timeLabels = ['9:30', '11:00', '14:00', '15:30'];
                        return Expanded(
                          child: Container(
                            padding: const EdgeInsets.only(right: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1, bottom: 1),
                                  child: Text(
                                    timeLabels[slotIndex],
                                    style: TextStyle(
                                      fontSize: AppTextSize.small,
                                      color: context.colors.textTertiary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: slotLessons.isEmpty
                                      ? const SizedBox.shrink()
                                      : SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: slotLessons.map((lesson) {
                                              final course = lesson['course'] as String? ?? '通常';
                                              final color = _courseColors[course] ?? AppColors.primary;
                                              final studentName = lesson['studentName'] as String? ?? '';
                                              final nameParts = studentName.split(' ');
                                              final firstName = nameParts.length > 1 ? nameParts[1] : studentName;

                                              final teachers = lesson['teachers'] as List<dynamic>? ?? [];
                                              final teacherInitials = teachers.isNotEmpty
                                                  ? teachers.map((t) {
                                                      final name = t.toString().split(' ').first;
                                                      return name.isNotEmpty ? name[0] : '';
                                                    }).join('')
                                                  : '';

                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 1),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 2,
                                                      height: 13,
                                                      decoration: BoxDecoration(
                                                        color: color,
                                                        borderRadius: BorderRadius.circular(1),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 2),
                                                    Flexible(
                                                      child: Text.rich(
                                                        TextSpan(
                                                          children: [
                                                            TextSpan(
                                                              text: firstName,
                                                              style: const TextStyle(fontSize: AppTextSize.caption),
                                                            ),
                                                            if (teacherInitials.isNotEmpty)
                                                              TextSpan(
                                                                text: ' $teacherInitials',
                                                                style: TextStyle(
                                                                  fontSize: AppTextSize.caption,
                                                                  color: context.colors.textTertiary,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
