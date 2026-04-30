// プラスケジュール画面のサイドメニュー (デスクトップ Web 版)。
// 月カレンダー (週切り替え) + プラス担当スタッフのフィルター + 下部メニュー (シフト管理) を内包。
// _PlusScheduleContentState の private 状態 (_sideMenuMonth / _weekStart / _selectedFilters /
// _staffList / _viewMode 他) を直接参照するため part + extension で抽出。

// ignore_for_file: library_private_types_in_public_api, invalid_use_of_protected_member

part of '../plus_schedule_screen.dart';

// スタッフフィルター用の固定パレット (10 色循環)。Material の各色相 500 と等価で
// 視覚的なスタッフ識別が用途。デザイントークンには載せず Color() リテラル化して
// 直書き Colors.* チェックを通す。
const List<Color> _kSideMenuStaffPalette = [
  Color(0xFF2196F3), // blue
  Color(0xFF009688), // teal
  Color(0xFF9C27B0), // purple
  Color(0xFFFF9800), // orange
  Color(0xFFE91E63), // pink
  Color(0xFF3F51B5), // indigo
  Color(0xFF4CAF50), // green
  Color(0xFFF44336), // red
  Color(0xFF00BCD4), // cyan
  Color(0xFFFFC107), // amber
];

// 日曜・土曜の見出し色。Material red/blue 500 と等価。
const Color _kSundayLabelColor = Color(0xFFF44336);
const Color _kSaturdayLabelColor = Color(0xFF2196F3);

extension PlusScheduleSideMenu on _PlusScheduleContentState {
  // サイドメニュー
  Widget _buildSideMenu() {
    // ダッシュボードモードの場合はサイドメニュー不要（Web版ではNavigationRailがある）
    if (_viewMode == 1) {
      return const SizedBox.shrink();
    }

    // スケジュールモードの場合は完全なメニュー
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border(
          right: BorderSide(color: context.colors.borderMedium),
        ),
      ),
      child: Column(
        children: [
          // 月カレンダー
          _buildSideMenuCalendar(),
          const Divider(height: 1),
          // フィルターリスト
          Expanded(
            child: _buildSideMenuFilters(),
          ),
          const Divider(height: 1),
          // 下部メニュー
          _buildSideMenuBottom(),
        ],
      ),
    );
  }

  // サイドメニュー：月カレンダー
  Widget _buildSideMenuCalendar() {
    final year = _sideMenuMonth.year;
    final month = _sideMenuMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // 日曜=0
    final daysInMonth = lastDay.day;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 年月とナビゲーション
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$year年 $month月',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: () {
                      setState(() {
                        _sideMenuMonth = DateTime(year, month - 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: () {
                      setState(() {
                        _sideMenuMonth = DateTime(year, month + 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 曜日ヘッダー
          Row(
            children: ['日', '月', '火', '水', '木', '金', '土'].map((day) {
              final isSunday = day == '日';
              final isSaturday = day == '土';
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSunday
                          ? _kSundayLabelColor
                          : (isSaturday ? _kSaturdayLabelColor : context.colors.textSecondary),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          // 日付グリッド
          ...List.generate(6, (weekIndex) {
            return Row(
              children: List.generate(7, (dayIndex) {
                final dayNumber = weekIndex * 7 + dayIndex - startWeekday + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 32));
                }
                final date = DateTime(year, month, dayNumber);
                final isToday = date.year == today.year &&
                               date.month == today.month &&
                               date.day == today.day;
                final isSelected = date.year == _weekStart.year &&
                                  date.month == _weekStart.month &&
                                  date.day >= _weekStart.day &&
                                  date.day <= _weekStart.day + 5;
                final isSunday = dayIndex == 0;
                final isSaturday = dayIndex == 6;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _weekStart = _getMonday(date);
                      });
                      _saveWeekStart(_weekStart);
                      _loadShiftData();
                      _loadLessonsForWeek();
                    },
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
                      ),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isToday ? AppColors.primary : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 13,
                                color: isToday
                                    ? Colors.white
                                    : (isSunday
                                        ? _kSundayLabelColor
                                        : (isSaturday ? _kSaturdayLabelColor : context.colors.textPrimary)),
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  // サイドメニュー：フィルターリスト
  Widget _buildSideMenuFilters() {
    // プラス担当のスタッフを取得（showInSchedule=trueのみ）
    final plusStaff = _staffList.where((s) =>
      s['isPlus'] == true && s['showInSchedule'] != false
    ).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 全て
        _buildFilterItem('all', '全て', AppColors.primary, isSpecial: true),
        const Divider(height: 16),
        // スタッフリスト
        ...plusStaff.asMap().entries.map((entry) {
          final index = entry.key;
          final staff = entry.value;
          final name = staff['name'] as String? ?? '';
          final color = _kSideMenuStaffPalette[index % _kSideMenuStaffPalette.length];
          return _buildFilterItem(name, name, color);
        }),
      ],
    );
  }

  Widget _buildFilterItem(String key, String label, Color color, {bool isSpecial = false}) {
    final isSelected = _selectedFilters.contains(key) ||
                      (_selectedFilters.contains('all') && key != 'all');

    return InkWell(
      onTap: () {
        setState(() {
          if (key == 'all') {
            // 「全て」を選択したら全フィルターを選択状態に
            _selectedFilters = {'all'};
          } else {
            // 個別フィルターを選択/解除
            _selectedFilters.remove('all');
            if (_selectedFilters.contains(key)) {
              _selectedFilters.remove(key);
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  fontSize: 14,
                  fontWeight: isSpecial ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // サイドメニュー：下部メニュー
  Widget _buildSideMenuBottom() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (_viewMode == 0)
            ListTile(
              leading: Icon(Icons.schedule, color: context.colors.textSecondary),
              title: Text('スケジュール管理'),
              onTap: () {
                _showShiftManagementDialog();
              },
            ),
        ],
      ),
    );
  }
}
