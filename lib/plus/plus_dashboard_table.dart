// プラスダッシュボードのレギュラースケジュール表 (曜日 x 時間帯のグリッド)。
// _PlusDashboardContentState の extension として private メンバを直接参照する。
// 追加/編集/削除ダイアログ自体は親側 (_show*Dialog) に残し、ここからは呼び出すだけ。

// ignore_for_file: library_private_types_in_public_api

part of '../plus_dashboard_screen.dart';

extension PlusDashboardTable on _PlusDashboardContentState {
  Widget _buildScheduleTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const timeColumnWidth = 60.0;
        const headerHeight = 40.0;
        const footerHeight = 40.0;
        const borderWidth = 1.0;

        final cellWidth = (constraints.maxWidth - timeColumnWidth - borderWidth * 2) / 6;
        final cellHeight = (constraints.maxHeight - headerHeight - footerHeight - borderWidth * 2) / 4;

        return Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.borderMedium, width: borderWidth),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              children: [
                _buildHeaderRow(cellWidth, timeColumnWidth, headerHeight),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTimeColumn(timeColumnWidth, cellHeight),
                      ...List.generate(6, (dayIndex) => _buildDayColumn(dayIndex, cellWidth, cellHeight)),
                    ],
                  ),
                ),
                _buildFooterRow(cellWidth, timeColumnWidth, footerHeight),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeColumn(double width, double cellHeight) {
    return SizedBox(
      width: width,
      child: Column(
        children: List.generate(_timeSlots.length, (index) {
          return Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  top: index == 0 ? BorderSide(color: context.colors.borderMedium) : BorderSide.none,
                  bottom: BorderSide(color: context.colors.borderMedium),
                ),
              ),
              child: Text(
                _timeSlots[index],
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: AppTextSize.small,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayColumn(int dayIndex, double cellWidth, double cellHeight) {
    final day = _weekDays[dayIndex];
    return Expanded(
      child: Column(
        children: List.generate(_timeSlots.length, (slotIndex) {
          final timeSlot = _timeSlots[slotIndex];
          final students = _regularSchedule[day]?[timeSlot] ?? [];
          return Expanded(
            child: _buildCell(day, timeSlot, students, cellHeight, cellWidth, slotIndex),
          );
        }),
      ),
    );
  }

  Widget _buildHeaderRow(double cellWidth, double timeColumnWidth, double headerHeight) {
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: const Text(''),
          ),
          ...List.generate(_weekDays.length, (index) {
            final day = _weekDays[index];
            final isSaturday = day == '土';
            return Expanded(
              child: Center(
                child: Text(
                  day,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyMd,
                    color: isSaturday ? AppColors.primary : context.colors.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCell(String day, String timeSlot, List<Map<String, dynamic>> students, double cellHeight, double cellWidth, int slotIndex) {
    return GestureDetector(
      onTap: () {
        _showAddStudentDialog(day, timeSlot);
      },
      child: SizedBox.expand(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            border: Border(
              top: slotIndex == 0 ? BorderSide(color: context.colors.borderMedium) : BorderSide.none,
              bottom: BorderSide(color: context.colors.borderMedium),
              left: BorderSide(color: context.colors.borderMedium),
            ),
          ),
          child: students.isEmpty
              ? null
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildStudentsGrouped(day, timeSlot, students),
                  ),
                ),
        ),
      ),
    );
  }

  /// セル内の生徒を groupId でグルーピングし、同じセット（同 gid が 2 人以上）は
  /// 1 つの Container（左バー1本）にまとめて描画する。
  List<Widget> _buildStudentsGrouped(
      String day, String timeSlot, List<Map<String, dynamic>> students) {
    // 元のインデックスを保持しつつ、同じ groupId が連続するように並び替え
    final firstIndex = <String, int>{};
    for (int i = 0; i < students.length; i++) {
      final gid = students[i]['groupId'] as String?;
      if (gid != null && gid.isNotEmpty && !firstIndex.containsKey(gid)) {
        firstIndex[gid] = i;
      }
    }
    final mult = students.length + 1;
    final sorted = students.asMap().entries.map((e) {
      final i = e.key;
      final s = e.value;
      final gid = s['groupId'] as String?;
      final eff = (gid != null && gid.isNotEmpty && firstIndex.containsKey(gid))
          ? firstIndex[gid]!
          : i;
      return MapEntry(eff * mult + i, (origIndex: i, student: s));
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final List<Widget> widgets = [];
    List<({int origIndex, Map<String, dynamic> student})> currentGroup = [];
    String? currentGid;

    void flushGroup() {
      if (currentGroup.isEmpty) return;
      final isSet = currentGid != null &&
          currentGid!.isNotEmpty &&
          currentGroup.length >= 2;
      if (isSet) {
        final firstStudent = currentGroup.first.student;
        final course = firstStudent['course'] as String? ?? '通常';
        final color = _courseColors[course] ?? AppColors.info;
        widgets.add(Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 2)),
          ),
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: currentGroup
                .map((e) =>
                    _buildStudentItem(day, timeSlot, e.origIndex, e.student))
                .toList(),
          ),
        ));
      } else {
        for (final e in currentGroup) {
          widgets
              .add(_buildStudentItem(day, timeSlot, e.origIndex, e.student));
        }
      }
      currentGroup = [];
    }

    for (final entry in sorted) {
      final s = entry.value;
      final gid = s.student['groupId'] as String?;
      if (gid == currentGid && currentGroup.isNotEmpty) {
        currentGroup.add(s);
      } else {
        flushGroup();
        currentGroup = [s];
        currentGid = gid;
      }
    }
    flushGroup();
    return widgets;
  }

  Widget _buildStudentItem(String day, String timeSlot, int index, Map<String, dynamic> student) {
    final name = student['name'] as String;
    final course = student['course'] as String? ?? '通常';
    final scheduleNote = student['note'] as String? ?? '';
    final color = _courseColors[course] ?? AppColors.info;

    final studentNote = _studentNotes.firstWhere(
      (n) => n['studentName'] == name,
      orElse: () => <String, dynamic>{},
    );
    final therapyPlan = studentNote['therapyPlan'] as String? ?? '';
    final schoolVisit = studentNote['schoolVisit'] as String? ?? '';
    final schoolConsultation = studentNote['schoolConsultation'] as String? ?? '';
    final moveRequest = studentNote['moveRequest'] as String? ?? '';

    final hasTask = _tasks.any((t) => t['studentName'] == name && t['completed'] != true);

    final hasAnyNote = scheduleNote.isNotEmpty ||
        therapyPlan.isNotEmpty ||
        schoolVisit.isNotEmpty ||
        schoolConsultation.isNotEmpty ||
        moveRequest.isNotEmpty ||
        hasTask;

    final textColor = course == '通常' ? context.colors.textPrimary : color;

    final courseInitial = course != '通常' && course.isNotEmpty
        ? '(${course.substring(0, 1)})'
        : '';

    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: AppTextSize.bodyMd,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (courseInitial.isNotEmpty)
                Text(
                  courseInitial,
                  style: TextStyle(
                    color: textColor,
                    fontSize: AppTextSize.small,
                  ),
                ),
            ],
          ),
        ),
        if (hasAnyNote)
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(6, 6),
              painter: _NoteTrianglePainter(color: context.colors.textPrimary),
            ),
          ),
      ],
    );

    // セット編集モード中はチェックボックスを左に出し、タップで選択切替
    // （左バーは _buildStudentsGrouped でグループ全体を 1 つの Container として描画）
    final studentId = student['id'] as String?;
    if (widget.setEditMode && studentId != null) {
      final isSelected = widget.selectedIds.contains(studentId);
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onToggleSelect?.call(studentId),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 14,
                  color: isSelected
                      ? AppColors.primary
                      : context.colors.textTertiary,
                ),
              ),
              Expanded(child: IgnorePointer(child: content)),
            ],
          ),
        ),
      );
    }

    if (!hasAnyNote) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showEditStudentDialog(day, timeSlot, index, student),
            onLongPress: () => _showDeleteConfirmDialog(day, timeSlot, index, student),
            child: content,
          ),
        ),
      );
    }

    final key = GlobalKey();
    const popupWidth = 180.0;

    void showOverlay() {
      _hideCurrentOverlay();

      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final overlay = Overlay.of(context);
      final offset = renderBox.localToGlobal(Offset.zero);

      final widgets = <Widget>[];
      if (therapyPlan.isNotEmpty) {
        widgets.add(const Text('【療育プラン】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(therapyPlan, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      if (schoolVisit.isNotEmpty) {
        widgets.add(const Text('【園連携】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(schoolVisit, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      if (schoolConsultation.isNotEmpty) {
        widgets.add(const Text('【就学相談】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(schoolConsultation, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      if (moveRequest.isNotEmpty) {
        widgets.add(const Text('【移動希望】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(moveRequest, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      final studentTasks = _tasks.where((t) => t['studentName'] == name && t['completed'] != true).toList();
      if (studentTasks.isNotEmpty) {
        widgets.add(const Text('【タスク】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        for (var task in studentTasks) {
          final title = task['title'] as String? ?? '';
          final dueDate = task['dueDate'] as Timestamp?;
          final dueDateStr = dueDate != null ? ' (${DateFormat('M/d').format(dueDate.toDate())})' : '';
          widgets.add(Text('・$title$dueDateStr', style: TextStyle(fontSize: AppTextSize.small)));
        }
        widgets.add(const SizedBox(height: 8));
      }
      if (scheduleNote.isNotEmpty) {
        widgets.add(const Text('【メモ】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(scheduleNote, style: TextStyle(fontSize: AppTextSize.small)));
      }
      if (widgets.isNotEmpty && widgets.last is SizedBox) {
        widgets.removeLast();
      }

      final popupContent = Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: context.colors.cardBg,
        child: Container(
          width: popupWidth,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widgets,
          ),
        ),
      );

      _currentOverlay = OverlayEntry(
        builder: (ctx) {
          final left = offset.dx + renderBox.size.width + 4;

          return Positioned(
            top: offset.dy,
            left: left,
            child: popupContent,
          );
        },
      );

      overlay.insert(_currentOverlay!);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        key: key,
        cursor: SystemMouseCursors.click,
        onEnter: (_) => showOverlay(),
        onExit: (_) => _hideCurrentOverlay(),
        child: GestureDetector(
          onTap: () {
            _hideCurrentOverlay();
            _showEditStudentDialog(day, timeSlot, index, student);
          },
          onLongPress: () {
            _hideCurrentOverlay();
            _showDeleteConfirmDialog(day, timeSlot, index, student);
          },
          child: content,
        ),
      ),
    );
  }

  Widget _buildFooterRow(double cellWidth, double timeColumnWidth, double footerHeight) {
    return Container(
      height: footerHeight,
      decoration: BoxDecoration(
        color: context.colors.tagBg,
      ),
      child: Row(
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: const Center(
              child: Text(
                '計',
                style: TextStyle(
                  fontSize: AppTextSize.small,
                ),
              ),
            ),
          ),
          ...List.generate(_weekDays.length, (index) {
            final day = _weekDays[index];
            int count = 0;
            for (var slot in _timeSlots) {
              count += _regularSchedule[day]?[slot]?.length ?? 0;
            }
            return Expanded(
              child: Center(
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: AppTextSize.body,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 右上三角マーク用のカスタムペインター
class _NoteTrianglePainter extends CustomPainter {
  final Color color;

  _NoteTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
