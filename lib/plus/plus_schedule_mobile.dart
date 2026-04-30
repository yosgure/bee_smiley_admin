// プラスケジュール画面のスマホ用 UI 群 (閲覧 + ボトムシート編集)。
// _PlusScheduleContentState の private 状態 (_mobileSelectedDate / _isMobileSideMenuOpen /
// _hoveredStudentName / _pendingAbsenceData / _lessons / _staffList / _selectedFilters /
// _viewMode / _weekStart / _isLoadingLessons / _isHoliday / _courseColors 他) を直接参照。
//
// 含むメソッド:
//   _buildMobileUI / _buildMobileSideMenu / _buildMobileFilterItem / _buildMobileHeader /
//   _buildMobileViewModeTab / _goToPreviousDay / _goToNextDay / _goToToday /
//   _showMobileDatePicker / _buildMobileDayView / _buildMobileTimeSlot /
//   _buildMobileLessonCard / _showMobileLessonDetail / _buildMobileDetailRow

// ignore_for_file: library_private_types_in_public_api, invalid_use_of_protected_member

part of '../plus_schedule_screen.dart';

extension PlusScheduleMobile on _PlusScheduleContentState {
  Widget _buildMobileUI() {
    // ダッシュボードモードの場合
    if (_viewMode == 1) {
      return SafeArea(
        child: Column(
          children: [
            _buildMobileHeader(),
            const Expanded(
              child: PlusDashboardContent(),
            ),
          ],
        ),
      );
    }

    // 選択中の日付の週が現在読み込み中の週と異なる場合、再読み込み
    final currentDateWeekStart = _getMonday(_currentMobileDate);
    if (currentDateWeekStart != _weekStart && !_isLoadingLessons) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _weekStart = currentDateWeekStart;
            _isLoadingLessons = true;
          });
          _loadShiftData();
          _loadLessonsForWeek();
        }
      });
    }

    return SafeArea(
      child: Stack(
        children: [
          // メインコンテンツ
          Column(
            children: [
              _buildMobileHeader(),
              Expanded(
                child: _isLoadingLessons
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity == null) return;
                          // 左スワイプ → 翌日
                          if (details.primaryVelocity! < -100) {
                            _goToNextDay();
                          }
                          // 右スワイプ → 前日
                          else if (details.primaryVelocity! > 100) {
                            _goToPreviousDay();
                          }
                        },
                        child: _buildMobileDayView(),
                      ),
              ),
            ],
          ),
          // オーバーレイ（サイドメニュー表示時）
          if (_isMobileSideMenuOpen)
            GestureDetector(
              onTap: () => setState(() => _isMobileSideMenuOpen = false),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          // サイドメニュー
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            left: _isMobileSideMenuOpen ? 0 : -280,
            top: 0,
            bottom: 0,
            width: 280,
            child: _buildMobileSideMenu(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMobileSideMenu() {
    final plusStaff = _staffList.where((s) =>
  s['isPlus'] == true && s['showInSchedule'] != false
).toList();
    final staffColors = [
      Color(0xFF2196F3),
      Color(0xFF009688),
      Color(0xFF9C27B0),
      Color(0xFFFF9800),
      Color(0xFFE91E63),
      Color(0xFF3F51B5),
      Color(0xFF4CAF50),
      Color(0xFFF44336),
      Color(0xFF00BCD4),
      Color(0xFFFFC107),
    ];
    
    return Material(
      elevation: 16,
      child: Container(
        color: context.colors.cardBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: AppColors.primary),
                  SizedBox(width: 12),
                  Text(
                    '講師フィルター',
                    style: TextStyle(
                      fontSize: AppTextSize.titleSm,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // フィルターリスト
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // 全て
                  _buildMobileFilterItem('all', '全て', AppColors.primary, isSpecial: true),
                  const Divider(height: 16),
                  // スタッフリスト
                  ...plusStaff.asMap().entries.map((entry) {
                    final index = entry.key;
                    final staff = entry.value;
                    final name = staff['name'] as String? ?? '';
                    final color = staffColors[index % staffColors.length];
                    return _buildMobileFilterItem(name, name, color);
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMobileFilterItem(String key, String label, Color color, {bool isSpecial = false}) {
    final isSelected = _selectedFilters.contains(key) || 
                      (_selectedFilters.contains('all') && key != 'all');
    
    return InkWell(
      onTap: () {
        setState(() {
          if (key == 'all') {
            _selectedFilters = {'all'};
          } else {
            _selectedFilters.remove('all');
            if (_selectedFilters.contains(key)) {
              _selectedFilters.remove(key);
              if (_selectedFilters.isEmpty) {
                _selectedFilters = {'all'};
              }
            } else {
              _selectedFilters.add(key);
            }
            // 全て選択されたら「全て」に戻す
            final plusStaff = _staffList.where((s) => s['isPlus'] == true).toList();
            final allStaffNames = plusStaff.map((s) => s['name'] as String).toSet();
            if (_selectedFilters.containsAll(allStaffNames)) {
              _selectedFilters = {'all'};
            }
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                border: Border.all(color: isSelected ? color : context.colors.iconMuted, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: isSpecial ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMobileHeader() {
    final dateStr = DateFormat('M月d日 (E)', 'ja').format(_currentMobileDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(
          bottom: BorderSide(color: context.colors.borderLight),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上段: ナビゲーション
          SizedBox(
            height: 48,
            child: Row(
              children: [
                if (_viewMode == 0) ...[
                  // スケジュールモード: ハンバーガーメニュー + 日付ナビ
                  IconButton(
                    icon: Icon(Icons.menu, size: 22, color: context.colors.textPrimary),
                    tooltip: 'メニュー',
                    onPressed: () => setState(() => _isMobileSideMenuOpen = true),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: context.colors.textSecondary),
                          onPressed: _goToPreviousDay,
                        ),
                        GestureDetector(
                          onTap: () => _showMobileDatePicker(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: AppTextSize.title,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right, color: context.colors.textSecondary),
                          onPressed: _goToNextDay,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _goToToday,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('今日', style: TextStyle(fontSize: AppTextSize.body)),
                  ),
                  _buildMobilePlusMenuButton(),
                ] else ...[
                  // ダッシュボードモード: タイトル
                  const SizedBox(width: 12),
                  Icon(Icons.dashboard_outlined, size: 20, color: context.colors.textPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'ダッシュボード',
                    style: TextStyle(
                      fontSize: AppTextSize.titleSm,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
              ],
            ),
          ),
          // 下段: ビューモード切り替えタブ
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.chipBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _buildMobileViewModeTab(0, Icons.calendar_today, '週'),
                  _buildMobileViewModeTab(1, Icons.dashboard_outlined, 'ダッシュボード'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileViewModeTab(int mode, IconData icon, String label) {
    final isSelected = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_viewMode != mode) {
            _hideCurrentOverlay();
            setState(() {
              _viewMode = mode;
            });
            _saveViewMode(mode);
          }
        },
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? AppColors.primary : context.colors.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.primary : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _goToPreviousDay() {
    setState(() {
      _mobileSelectedDate = _currentMobileDate.subtract(const Duration(days: 1));
      final newWeekStart = _getMonday(_currentMobileDate);
      if (newWeekStart != _weekStart) {
        _weekStart = newWeekStart;
        _loadShiftData();
        _loadLessonsForWeek();
      }
    });
  }
  
  void _goToNextDay() {
    setState(() {
      _mobileSelectedDate = _currentMobileDate.add(const Duration(days: 1));
      final newWeekStart = _getMonday(_currentMobileDate);
      if (newWeekStart != _weekStart) {
        _weekStart = newWeekStart;
        _loadShiftData();
        _loadLessonsForWeek();
      }
    });
  }
  
  void _goToToday() {
    setState(() {
      _mobileSelectedDate = DateTime.now();
      final newWeekStart = _getMonday(_currentMobileDate);
      if (newWeekStart != _weekStart) {
        _weekStart = newWeekStart;
        _loadShiftData();
        _loadLessonsForWeek();
      }
    });
  }
  
  void _showMobileDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentMobileDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ja'),
    );
    if (picked != null) {
      setState(() {
        _mobileSelectedDate = picked;
        final newWeekStart = _getMonday(_currentMobileDate);
        if (newWeekStart != _weekStart) {
          _weekStart = newWeekStart;
          _loadShiftData();
          _loadLessonsForWeek();
        }
      });
    }
  }
  
  Widget _buildMobileDayView() {
    // 選択中の日のdayIndexを計算
    final dayIndex = _currentMobileDate.difference(_weekStart).inDays;
    final isHoliday = _isHoliday(_currentMobileDate);
    final isSunday = _currentMobileDate.weekday == 7;
    
    // 日曜日の場合
    if (isSunday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.weekend, size: 64, color: context.colors.iconMuted),
            const SizedBox(height: 16),
            Text(
              '日曜日は休みです',
              style: TextStyle(
                fontSize: AppTextSize.titleLg,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    
    // 休みの場合
    if (isHoliday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: context.colors.iconMuted),
            const SizedBox(height: 16),
            Text(
              '休み',
              style: TextStyle(
                fontSize: AppTextSize.titleLg,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    
    // dayIndexが範囲外の場合（週をまたいでいる）- データ読み込み待ち表示
    if (dayIndex < 0 || dayIndex > 5) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: context.colors.iconMuted),
            const SizedBox(height: 16),
            Text(
              'データを読み込んでいます...',
              style: TextStyle(
                fontSize: AppTextSize.titleSm,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _weekStart = _getMonday(_currentMobileDate);
                });
                _loadShiftData();
                _loadLessonsForWeek();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _timeSlots.length,
      itemBuilder: (context, slotIndex) {
        return _buildMobileTimeSlot(dayIndex, slotIndex);
      },
    );
  }
  
  Widget _buildMobileTimeSlot(int dayIndex, int slotIndex) {
    final timeSlot = _timeSlots[slotIndex];
    
    // この時間帯のレッスンを取得
    var lessons = _lessons.where((lesson) =>
        lesson['dayIndex'] == dayIndex && lesson['slotIndex'] == slotIndex).toList();
    
    // フィルタリング適用
    if (!_selectedFilters.contains('all')) {
      if (_selectedFilters.isEmpty) {
        lessons = [];
      } else {
        lessons = lessons.where((lesson) {
          final teachers = lesson['teachers'] as List<dynamic>? ?? [];
          if (teachers.contains('全員')) return true;
          for (final teacher in teachers) {
            if (_selectedFilters.contains(teacher)) return true;
          }
          return false;
        }).toList();
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 時間帯ヘッダー
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  timeSlot,
                  style: const TextStyle(
                    fontSize: AppTextSize.bodyMd,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${lessons.length}件',
                style: TextStyle(
                  fontSize: AppTextSize.small,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // レッスンカード
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 16),
            child: Text(
              '予定なし',
              style: TextStyle(
                fontSize: AppTextSize.bodyMd,
                color: context.colors.textTertiary,
              ),
            ),
          )
        else
          ...lessons.map((lesson) => _buildMobileLessonCard(lesson)),
        const SizedBox(height: 8),
      ],
    );
  }
  
  Widget _buildMobileLessonCard(Map<String, dynamic> lesson) {
    final isEvent = lesson['isEvent'] == true;
    final studentName = lesson['studentName'] as String? ?? '';
    final eventTitle = lesson['title'] as String? ?? '';
    final displayName = isEvent ? eventTitle : studentName;
    final teachers = lesson['teachers'] as List<dynamic>? ?? [];
    final room = lesson['room'] as String? ?? '';
    final course = lesson['course'] as String? ?? '通常';
    final courseColor = _courseColors[course] ?? AppColors.primary;
    
    return GestureDetector(
      onTap: () => _showMobileLessonDetail(lesson),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // コース色のバー
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: courseColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 生徒名/イベント名
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      fontWeight: FontWeight.w500,
                      color: isEvent ? const Color(0xFFFF5722) : (course == '感覚統合' ? const Color(0xFF009688) : context.colors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 講師・部屋
                  Row(
                    children: [
                      if (teachers.isNotEmpty) ...[
                        Icon(Icons.person, size: 14, color: context.colors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          teachers.map((t) => t.toString().split(' ').first).join(', '),
                          style: TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (room.isNotEmpty) ...[
                        Icon(Icons.room, size: 14, color: context.colors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          room,
                          style: TextStyle(fontSize: AppTextSize.small, color: context.colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 矢印
            Icon(Icons.chevron_right, color: context.colors.iconMuted),
          ],
        ),
      ),
    );
  }
  
  void _showMobileLessonDetail(Map<String, dynamic> lesson) {
    if (_hoveredStudentName != null) {
      setState(() => _hoveredStudentName = null);
    }
    final isEvent = lesson['isEvent'] == true;
    final isCustomEvent = lesson['isCustomEvent'] == true;
    final studentName = lesson['studentName'] as String? ?? '';
    final eventTitle = lesson['title'] as String? ?? '';
    final displayName = isEvent ? eventTitle : studentName;
    final dayIndex = lesson['dayIndex'] as int;
    final slotIndex = lesson['slotIndex'] as int;
    final date = _weekStart.add(Duration(days: dayIndex));

    // 編集用の状態変数
    List<String> selectedTeachers = List<String>.from(lesson['teachers'] ?? []);
    String selectedRoom = lesson['room'] ?? '';
    String selectedCourse = lesson['course'] ?? '通常';

    // カスタムイベント名編集用
    final mobileTitleController = TextEditingController(text: studentName);
    bool isMobileEditingTitle = false;

    // 生徒メモ用コントローラー
    final therapyController = TextEditingController();
    final schoolVisitController = TextEditingController();
    final consultationController = TextEditingController();
    final moveRequestController = TextEditingController();

    // タスク用
    List<Map<String, dynamic>> studentTasks = [];
    final newTaskController = TextEditingController();
    DateTime? newTaskDueDate = date;

    bool isLoading = true;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            // 初回のみデータ読み込み
            if (isLoading && !isCustomEvent && studentName.isNotEmpty) {
              isLoading = false;
              _loadStudentNotes(studentName).then((notes) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    therapyController.text = notes['therapyPlan'] ?? '';
                    schoolVisitController.text = notes['schoolVisit'] ?? '';
                    consultationController.text = notes['schoolConsultation'] ?? '';
                    moveRequestController.text = notes['moveRequest'] ?? '';
                    studentTasks = _getTasksForStudent(studentName);
                  });
                }
              });
            }

            final currentColor = _courseColors[selectedCourse] ?? AppColors.primary;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ハンドル
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.colors.borderMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // ヘッダー
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 40,
                          decoration: BoxDecoration(
                            color: currentColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isCustomEvent && isMobileEditingTitle)
                                TextField(
                                  controller: mobileTitleController,
                                  autofocus: true,
                                  style: const TextStyle(
                                    fontSize: AppTextSize.xl,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: InputDecoration(
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(color: context.colors.borderMedium),
                                    ),
                                    focusedBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                                    ),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: 'イベント名を入力',
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.check, size: 18),
                                      color: AppColors.primary,
                                      onPressed: () => setSheetState(() => isMobileEditingTitle = false),
                                    ),
                                  ),
                                  onSubmitted: (_) => setSheetState(() => isMobileEditingTitle = false),
                                )
                              else if (isCustomEvent)
                                GestureDetector(
                                  onTap: () => setSheetState(() => isMobileEditingTitle = true),
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          mobileTitleController.text.isEmpty ? 'イベント名を入力' : mobileTitleController.text,
                                          style: TextStyle(
                                            fontSize: AppTextSize.xl,
                                            fontWeight: FontWeight.bold,
                                            color: mobileTitleController.text.isEmpty ? context.colors.textSecondary : null,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(Icons.edit, size: 16, color: context.colors.textSecondary),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  studentName,
                                  style: const TextStyle(
                                    fontSize: AppTextSize.xl,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Text(
                                '${DateFormat('M月d日 (E)', 'ja').format(date)}　${_timeSlots[slotIndex]}',
                                style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _showDeleteConfirmDialog(lesson);
                          },
                          tooltip: '削除',
                          color: context.colors.textSecondary,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: context.colors.borderLight),
                  // 編集コンテンツ
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 講師選択
                          InkWell(
                            onTap: () => _showMultiTeacherSelectionDialog(
                              selectedTeachers,
                              (newSelection) => setSheetState(() => selectedTeachers = newSelection),
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
                                      selectedTeachers.isEmpty
                                          ? '講師を選択'
                                          : selectedTeachers.contains('全員')
                                              ? '全員'
                                              : selectedTeachers.join('、'),
                                      style: TextStyle(
                                        fontSize: AppTextSize.bodyLarge,
                                        color: selectedTeachers.isEmpty ? context.colors.textSecondary : context.colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (selectedTeachers.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => setSheetState(() => selectedTeachers = []),
                                      child: Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
                                      ),
                                    ),
                                  Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 部屋選択
                          InkWell(
                            onTap: () => _showRoomSelectionDialog(
                              selectedRoom,
                              (newRoom) => setSheetState(() => selectedRoom = newRoom),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.colors.borderMedium),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.meeting_room, size: 20, color: context.colors.textSecondary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedRoom.isEmpty ? '部屋を選択' : selectedRoom,
                                      style: TextStyle(
                                        fontSize: AppTextSize.bodyLarge,
                                        color: selectedRoom.isEmpty ? context.colors.textSecondary : context.colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (selectedRoom.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => setSheetState(() => selectedRoom = ''),
                                      child: Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
                                      ),
                                    ),
                                  Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // コース選択
                          InkWell(
                            onTap: () => _showCourseSelectionDialog(
                              selectedCourse,
                              (newCourse) => setSheetState(() => selectedCourse = newCourse),
                              studentName: studentName,
                              absenceDate: date,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.colors.borderMedium),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12, height: 12,
                                    decoration: BoxDecoration(
                                      color: currentColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(selectedCourse, style: const TextStyle(fontSize: AppTextSize.bodyLarge))),
                                  Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                                ],
                              ),
                            ),
                          ),

                          // 生徒情報セクション
                          if (!isCustomEvent && studentName.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Divider(height: 1, color: context.colors.borderLight),
                            const SizedBox(height: 20),

                            // タスクセクション
                            Row(
                              children: [
                                const Icon(Icons.task_alt, size: 18, color: AppColors.accent),
                                const SizedBox(width: 8),
                                const Text('タスク', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (studentTasks.isNotEmpty) ...[
                              ...studentTasks.map((task) => GestureDetector(
                                onTap: () => _showEditTaskDialog(
                                  sheetContext,
                                  task,
                                  () => setSheetState(() {
                                    studentTasks = _getTasksForStudent(studentName);
                                  }),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: _taskDecoration(),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(task['title'] ?? '', style: const TextStyle(fontSize: AppTextSize.body)),
                                            if (task['dueDate'] != null)
                                              Text(
                                                '期限: ${DateFormat('M/d').format((task['dueDate'] as Timestamp).toDate())}',
                                                style: TextStyle(fontSize: AppTextSize.caption, color: context.colors.textSecondary),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          await _completeTask(task['id']);
                                          setSheetState(() {
                                            studentTasks = _getTasksForStudent(studentName);
                                          });
                                        },
                                        icon: const Icon(Icons.check_circle_outline, size: 20),
                                        color: Color(0xFF4CAF50),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: '完了',
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                            ],
                            // 新規タスク入力
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newTaskController,
                                    decoration: InputDecoration(
                                      hintText: '新しいタスク',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      isDense: true,
                                    ),
                                    style: const TextStyle(fontSize: AppTextSize.body),
                                    onChanged: (_) => setSheetState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: sheetContext,
                                      initialDate: newTaskDueDate ?? DateTime.now(),
                                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (picked != null) {
                                      setSheetState(() => newTaskDueDate = picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: context.colors.borderMedium),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today, size: 16, color: newTaskDueDate != null ? AppColors.primary : context.colors.textSecondary),
                                        if (newTaskDueDate != null) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            DateFormat('M/d').format(newTaskDueDate!),
                                            style: const TextStyle(fontSize: AppTextSize.small),
                                          ),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => setSheetState(() => newTaskDueDate = null),
                                            child: Icon(Icons.close, size: 14, color: context.colors.textSecondary),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () async {
                                  final taskText = newTaskController.text.trim();
                                  if (taskText.isEmpty) return;
                                  final newTask = await _addTaskForStudent(
                                    studentName,
                                    taskText,
                                    newTaskDueDate,
                                  );
                                  newTaskController.clear();
                                  setSheetState(() {
                                    newTaskDueDate = date;
                                    if (newTask != null) {
                                      studentTasks = [...studentTasks, newTask];
                                    }
                                  });
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: newTaskController.text.trim().isEmpty
                                        ? context.colors.borderMedium
                                        : AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 療育プラン
                            Row(
                              children: [
                                const Icon(Icons.psychology, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                const Text('療育プラン', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: therapyController,
                              decoration: InputDecoration(
                                hintText: '療育の目標や方針を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: AppTextSize.body),
                            ),
                            const SizedBox(height: 16),
                            // 園訪問
                            Row(
                              children: [
                                Icon(Icons.school, size: 18, color: const Color(0xFF00897B)),
                                const SizedBox(width: 8),
                                const Text('園訪問', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: schoolVisitController,
                              decoration: InputDecoration(
                                hintText: '園訪問の記録や予定を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: AppTextSize.body),
                            ),
                            const SizedBox(height: 16),
                            // 就学相談
                            Row(
                              children: [
                                Icon(Icons.celebration, size: 18, color: const Color(0xFF3949AB)),
                                const SizedBox(width: 8),
                                const Text('就学相談', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: consultationController,
                              decoration: InputDecoration(
                                hintText: '就学相談の記録や予定を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: AppTextSize.body),
                            ),
                            const SizedBox(height: 16),
                            // 移動希望
                            Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 18, color: const Color(0xFF8E24AA)),
                                const SizedBox(width: 8),
                                const Text('移動希望', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: moveRequestController,
                              decoration: InputDecoration(
                                hintText: '曜日や時間の変更希望を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: AppTextSize.body),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // 保存ボタン
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    decoration: BoxDecoration(
                      color: context.colors.cardBg,
                      border: Border(top: BorderSide(color: context.colors.borderLight)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final lessonId = lesson['id'] as String?;
                            if (lessonId == null) {
                              Navigator.pop(sheetContext);
                              return;
                            }


                            try {
                              // タスクを追加（入力欄にテキストがある場合）
                              final taskText = newTaskController.text.trim();
                              if (taskText.isNotEmpty && studentName.isNotEmpty) {
                                await _addTaskForStudent(
                                  studentName,
                                  taskText,
                                  newTaskDueDate,
                                );
                              }

                              // レッスン情報を保存
                              final mobileUpdateData = <String, dynamic>{
                                'teachers': selectedTeachers,
                                'room': selectedRoom,
                                'course': selectedCourse,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              // カスタムイベントの場合はタイトルも更新
                              if (isCustomEvent) {
                                mobileUpdateData['studentName'] = mobileTitleController.text.trim();
                              }
                              await FirebaseFirestore.instance
                                  .collection('plus_lessons')
                                  .doc(lessonId)
                                  .update(mobileUpdateData);

                              // HUG連携（欠席系の場合）
                              final pending = _pendingAbsenceData;
                              if (pending != null && pending['studentName'] == studentName) {
                                _sendAbsenceToHug(
                                  studentName: studentName,
                                  absenceDate: pending['absenceDate'] as DateTime,
                                  category: pending['category'] as String,
                                  content: pending['content'] as String,
                                );
                                _pendingAbsenceData = null;
                              }

                              // 生徒メモを保存
                              if (!isCustomEvent && studentName.isNotEmpty) {
                                await _saveStudentNotes(studentName, {
                                  'therapyPlan': therapyController.text,
                                  'schoolVisit': schoolVisitController.text,
                                  'schoolConsultation': consultationController.text,
                                  'moveRequest': moveRequestController.text,
                                });
                              }

                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              await _loadLessonsForWeek(showLoading: false);

                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(content: Text('保存しました')),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error updating lesson: $e');
                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(content: Text('エラー: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: context.colors.textOnPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('保存', style: TextStyle(fontSize: AppTextSize.titleSm)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildMobileDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.small,
                  color: context.colors.textTertiary,
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: AppTextSize.bodyMd),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
