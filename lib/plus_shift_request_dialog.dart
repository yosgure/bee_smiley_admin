import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

/// 新ルール（月末を含む週の土曜まで）を初適用する月。
/// この月以前は旧ルール（月初〜月末）として扱う。
final DateTime kShiftRangeRolloutMonth = DateTime(2026, 6, 1);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 対象月の希望入力範囲の終了日。
/// 新ルール: 月末を含む週（日曜始まり）の土曜日。
/// 旧ルール: 月末。
DateTime shiftRangeEnd(DateTime targetMonth) {
  final last =
      DateTime(targetMonth.year, targetMonth.month + 1, 0); // 月末
  final rollout = _dateOnly(kShiftRangeRolloutMonth);
  final tgt = DateTime(targetMonth.year, targetMonth.month, 1);
  if (tgt.isBefore(rollout)) return last;
  final daysToSat = 6 - (last.weekday % 7); // Sun=0 ... Sat=6
  return last.add(Duration(days: daysToSat));
}

/// 対象月の希望入力範囲の開始日。
/// 新ルール（ロールアウト後）: 前月の新ルール終了日の翌日。
/// ロールアウト月本体: 月初。
DateTime shiftRangeStart(DateTime targetMonth) {
  final first = DateTime(targetMonth.year, targetMonth.month, 1);
  final rollout = _dateOnly(kShiftRangeRolloutMonth);
  if (!first.isAfter(rollout)) return first;
  final prev = DateTime(targetMonth.year, targetMonth.month - 1, 1);
  return shiftRangeEnd(prev).add(const Duration(days: 1));
}

/// 翌月シフト希望を入力するダイアログ。
///
/// - `targetMonth`: 対象月の1日を渡す（例: 2026-05-01）
/// - `plus_shift_requests/{yyyy-MM}` に staffs.{staffId} の形で保存する
/// - 閲覧は全員分、編集は自分のみ（UIで制御）
class PlusShiftRequestDialog extends StatefulWidget {
  final DateTime targetMonth;

  const PlusShiftRequestDialog({super.key, required this.targetMonth});

  @override
  State<PlusShiftRequestDialog> createState() => _PlusShiftRequestDialogState();
}

class _PlusShiftRequestDialogState extends State<PlusShiftRequestDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _myStaffId;
  String? _myStaffName;

  // 自分の入力（DateTime キー）
  // 5 状態: なし / 休み希望 / 絶対休 / 午前休 / 午後休 を排他的に表現する。
  //   - 休み希望: _myNgDates のみ
  //   - 絶対休: _myNgDates + _myNgStrongDates（ngStrong ⊆ ng）
  //   - 午前休: _myHalfAmDates のみ
  //   - 午後休: _myHalfPmDates のみ
  final Set<DateTime> _myNgDates = <DateTime>{};
  final Set<DateTime> _myNgStrongDates = <DateTime>{};
  final Set<DateTime> _myHalfAmDates = <DateTime>{};
  final Set<DateTime> _myHalfPmDates = <DateTime>{};

  String get _monthKey => DateFormat('yyyy-MM').format(widget.targetMonth);

  DateTime get _rangeStart => _dateOnly(shiftRangeStart(widget.targetMonth));
  DateTime get _rangeEnd => _dateOnly(shiftRangeEnd(widget.targetMonth));

  /// 締切 = 対象月の前月10日
  DateTime get _deadline => DateTime(
        widget.targetMonth.year,
        widget.targetMonth.month - 1,
        10,
      );

  int get _daysUntilDeadline {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final d = DateTime(_deadline.year, _deadline.month, _deadline.day);
    return d.difference(t).inDays;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. 現在ログイン中のスタッフを特定
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('staffs')
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          _myStaffId = snap.docs.first.id;
          _myStaffName = (snap.docs.first.data()['name'] ?? '') as String;
        }
      }

      // 2. 自分の既存エントリを対象月ドキュメントから読む。
      //    新形式: ngDates/ngDaysStrongDates/halfDates（ISO 日付文字列）
      //    旧形式: ngDays/ngDaysStrong（対象月の day-int）
      if (_myStaffId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('plus_shift_requests')
            .doc(_monthKey)
            .get();
        if (doc.exists) {
          final staffs =
              Map<String, dynamic>.from(doc.data()?['staffs'] ?? {});
          if (staffs[_myStaffId] is Map) {
            final mine = Map<String, dynamic>.from(staffs[_myStaffId] as Map);
            void collectDates(String field, Set<DateTime> target) {
              final list = (mine[field] as List?) ?? const [];
              for (final v in list) {
                final d = DateTime.tryParse(v as String);
                if (d == null) continue;
                final dd = _dateOnly(d);
                if (!dd.isBefore(_rangeStart) && !dd.isAfter(_rangeEnd)) {
                  target.add(dd);
                }
              }
            }

            // 新形式優先
            if (mine['ngDates'] is List ||
                mine['ngStrongDates'] is List ||
                mine['halfDates'] is List ||
                mine['halfAmDates'] is List ||
                mine['halfPmDates'] is List) {
              collectDates('ngDates', _myNgDates);
              collectDates('ngStrongDates', _myNgStrongDates);
              if (mine['halfAmDates'] is List ||
                  mine['halfPmDates'] is List) {
                collectDates('halfAmDates', _myHalfAmDates);
                collectDates('halfPmDates', _myHalfPmDates);
              } else {
                // 旧 halfDates のみ存在 → 全て午前休として復元
                collectDates('halfDates', _myHalfAmDates);
              }
            } else {
              // 旧形式（対象月の day-int）
              void collectDays(String field, Set<DateTime> target) {
                final list = (mine[field] as List?) ?? const [];
                for (final v in list) {
                  final day = (v as num).toInt();
                  target.add(DateTime(widget.targetMonth.year,
                      widget.targetMonth.month, day));
                }
              }

              collectDays('ngDays', _myNgDates);
              collectDays('ngDaysStrong', _myNgStrongDates);
            }
            // 半休は ng/strong と排他
            _myNgDates.removeAll(_myHalfAmDates);
            _myNgDates.removeAll(_myHalfPmDates);
            _myNgStrongDates.removeAll(_myHalfAmDates);
            _myNgStrongDates.removeAll(_myHalfPmDates);
            // 午前/午後の重複も排他
            _myHalfPmDates.removeAll(_myHalfAmDates);
          }
        }
      }
    } catch (e) {
      debugPrint('シフト希望の読み込み失敗: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_myStaffId == null) {
      AppFeedback.info(context, 'ログインユーザーが確認できませんでした');
      return;
    }
    setState(() => _saving = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('plus_shift_requests')
          .doc(_monthKey);
      final snapshot = await docRef.get();

      String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
      final ngDates = (_myNgDates.toList()..sort()).map(iso).toList();
      final strongDates = (_myNgStrongDates
              .where(_myNgDates.contains)
              .toList()
            ..sort())
          .map(iso)
          .toList();
      final halfAmDates = (_myHalfAmDates.toList()..sort()).map(iso).toList();
      final halfPmDates = (_myHalfPmDates.toList()..sort()).map(iso).toList();
      // 旧形式互換: 全半休の合算
      final halfAll = <DateTime>{..._myHalfAmDates, ..._myHalfPmDates}.toList()
        ..sort();
      final halfDates = halfAll.map(iso).toList();

      // 下位互換: 対象月（yyyy-MM）に属する日の day-int も書いておく。
      // 既存の集計・読み取りコードが ngDays を直接見ている場合に備える。
      List<int> daysOfTargetMonth(Set<DateTime> src) => (src
              .where((d) =>
                  d.year == widget.targetMonth.year &&
                  d.month == widget.targetMonth.month)
              .map((d) => d.day)
              .toList()
            ..sort());

      final legacyNgDays = daysOfTargetMonth(_myNgDates);
      final legacyStrong =
          daysOfTargetMonth(_myNgStrongDates).where(legacyNgDays.contains).toList();

      final myEntry = <String, dynamic>{
        'staffName': _myStaffName ?? '',
        'ngDates': ngDates,
        'ngStrongDates': strongDates,
        'halfAmDates': halfAmDates,
        'halfPmDates': halfPmDates,
        'halfDates': halfDates,
        'ngDays': legacyNgDays,
        'ngDaysStrong': legacyStrong,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (snapshot.exists) {
        final data = snapshot.data() ?? {};
        final existingStaffs =
            Map<String, dynamic>.from(data['staffs'] ?? {});
        if (existingStaffs.containsKey(_myStaffId)) {
          final prev =
              Map<String, dynamic>.from(existingStaffs[_myStaffId] as Map);
          myEntry['submittedAt'] =
              prev['submittedAt'] ?? FieldValue.serverTimestamp();
        } else {
          myEntry['submittedAt'] = FieldValue.serverTimestamp();
        }
        existingStaffs[_myStaffId!] = myEntry;
        await docRef.update({
          'staffs': existingStaffs,
          'month': _monthKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        myEntry['submittedAt'] = FieldValue.serverTimestamp();
        await docRef.set({
          'month': _monthKey,
          'staffs': {_myStaffId!: myEntry},
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        AppFeedback.info(context, 'シフト希望を保存しました');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('シフト希望の保存失敗: $e');
      if (mounted) {
        AppFeedback.info(context, '保存に失敗しました: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDeadlineBadge() {
    final days = _daysUntilDeadline;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    late final Color bg;
    late final Color fg;
    late final String label;
    if (days < 0) {
      bg = AppColors.error;
      fg = Colors.white;
      label = '締切超過 ${-days}日';
    } else if (days <= 3) {
      bg = isDark ? AppColors.errorDark.withValues(alpha: 0.4) : AppColors.errorBg;
      fg = isDark ? AppColors.errorBg : AppColors.errorDark;
      label = '締切まであと$days日';
    } else {
      bg = isDark ? AppColors.warningDark.withValues(alpha: 0.4) : AppColors.warningBg;
      fg = isDark ? AppColors.warningBg : AppColors.warningDark;
      label = '締切まであと$days日';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTextSize.small,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  /// 日付セル長押し/タップ位置にポップアップメニューを開いて状態を切替える。
  Future<void> _showStatePicker(DateTime date, Offset globalPos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final isNg = _myNgDates.contains(date);
    final isStrong = _myNgStrongDates.contains(date);
    final isHalfAm = _myHalfAmDates.contains(date);
    final isHalfPm = _myHalfPmDates.contains(date);
    final hasAny = isNg || isStrong || isHalfAm || isHalfPm;

    Widget itemRow(Color color, String label, bool selected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500)),
          if (selected) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check, size: 14),
          ],
        ],
      );
    }

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        overlay.size.width - globalPos.dx,
        overlay.size.height - globalPos.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'ng',
          child:
              itemRow(AppColors.errorBorder, '休み希望', isNg && !isStrong),
        ),
        PopupMenuItem<String>(
          value: 'strong',
          child: itemRow(AppColors.errorDark, '絶対休み', isStrong),
        ),
        PopupMenuItem<String>(
          value: 'halfAm',
          child: itemRow(AppColors.warning, '午前休', isHalfAm),
        ),
        PopupMenuItem<String>(
          value: 'halfPm',
          child: itemRow(AppColors.primaryDark, '午後休', isHalfPm),
        ),
        if (hasAny) const PopupMenuDivider(),
        if (hasAny)
          const PopupMenuItem<String>(
            value: 'clear',
            child: Row(
              children: [
                Icon(Icons.clear, size: 14),
                SizedBox(width: 8),
                Text('解除', style: TextStyle(fontSize: AppTextSize.body)),
              ],
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      // すべての集合からこの日付を抜いてから、選択状態を立てる
      _myNgDates.remove(date);
      _myNgStrongDates.remove(date);
      _myHalfAmDates.remove(date);
      _myHalfPmDates.remove(date);
      switch (selected) {
        case 'ng':
          _myNgDates.add(date);
          break;
        case 'strong':
          _myNgDates.add(date);
          _myNgStrongDates.add(date);
          break;
        case 'halfAm':
          _myHalfAmDates.add(date);
          break;
        case 'halfPm':
          _myHalfPmDates.add(date);
          break;
        case 'clear':
          // 既に全部削除済み
          break;
      }
    });
  }

  Widget _stateLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: AppTextSize.caption)),
      ],
    );
  }

  Widget _buildCalendar() {
    // 月曜始まりで、範囲開始日の週頭〜範囲終了日の週末までを描画する。
    final rangeStart = _rangeStart;
    final rangeEnd = _rangeEnd;
    // Mon=1...Sun=7。月曜まで戻す。
    final gridStart =
        rangeStart.subtract(Duration(days: (rangeStart.weekday - 1) % 7));
    // 日曜まで進める。
    final gridEnd =
        rangeEnd.add(Duration(days: (7 - rangeEnd.weekday) % 7));
    final totalCells = gridEnd.difference(gridStart).inDays + 1;
    final rows = (totalCells / 7).ceil();

    const weekLabels = ['月', '火', '水', '木', '金', '土', '日'];

    return Column(
      children: [
        // 曜日ヘッダ
        Row(
          children: List.generate(7, (i) {
            final isSat = i == 5;
            final isSun = i == 6;
            return Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    weekLabels[i],
                    style: TextStyle(
                      fontSize: AppTextSize.small,
                      fontWeight: FontWeight.bold,
                      color: isSun
                          ? AppColors.error
                          : isSat
                              ? AppColors.info
                              : context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        // 日付グリッド
        for (int r = 0; r < rows; r++)
          Row(
            children: List.generate(7, (c) {
              final cellIndex = r * 7 + c;
              final date = gridStart.add(Duration(days: cellIndex));
              final inRange =
                  !date.isBefore(rangeStart) && !date.isAfter(rangeEnd);
              if (!inRange) {
                // 範囲外でも日付は表示（薄く・操作不可）
                final dow = date.weekday;
                final outColor = dow == 7
                    ? AppColors.error.withValues(alpha: 0.35)
                    : dow == 6
                        ? AppColors.info.withValues(alpha: 0.35)
                        : context.colors.textTertiary;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Text(
                          '${date.month}/${date.day}',
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            fontWeight: FontWeight.w500,
                            color: outColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              final isNg = _myNgDates.contains(date);
              final isStrong = _myNgStrongDates.contains(date);
              final isHalfAm = _myHalfAmDates.contains(date);
              final isHalfPm = _myHalfPmDates.contains(date);
              final dow = date.weekday; // 月=1, ..., 日=7
              final dayColor = dow == 7
                  ? AppColors.error
                  : dow == 6
                      ? AppColors.info
                      : context.colors.textPrimary;
              final Color bgColor;
              final String? badgeLabel;
              if (isHalfAm) {
                bgColor = AppColors.warning;
                badgeLabel = '午前休';
              } else if (isHalfPm) {
                bgColor = AppColors.primaryDark;
                badgeLabel = '午後休';
              } else if (isStrong) {
                bgColor = AppColors.errorDark;
                badgeLabel = '絶対休';
              } else if (isNg) {
                bgColor = AppColors.errorBorder;
                badgeLabel = '休';
              } else {
                bgColor = context.colors.tagBg;
                badgeLabel = null;
              }
              final isOtherMonth = date.month != widget.targetMonth.month;
              final dayLabel =
                  isOtherMonth ? '${date.month}/${date.day}' : '${date.day}';
              final labelFontSize = isOtherMonth ? 11.0 : 14.0;
              final markedFg = isNg || isStrong || isHalfAm || isHalfPm;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTapDown: (details) =>
                          _showStatePicker(date, details.globalPosition),
                      onTap: () {}, // onTapDown を使うため空
                      child: SizedBox(
                        height: 48,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: labelFontSize,
                                fontWeight: FontWeight.bold,
                                color: markedFg ? Colors.white : dayColor,
                              ),
                            ),
                            if (badgeLabel != null)
                              Text(
                                badgeLabel,
                                style: const TextStyle(
                                  fontSize: AppTextSize.xxs,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 600 ? screenWidth - 32 : 460.0;

    return Dialog(
      backgroundColor: context.colors.dialogBg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ヘッダ
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.how_to_vote,
                            color: AppColors.warning, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.targetMonth.year}年${widget.targetMonth.month}月のシフト希望',
                            style: TextStyle(
                                fontSize: AppTextSize.titleSm, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: '閉じる',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _buildDeadlineBadge(),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '締切: ${DateFormat('M/d', 'ja').format(_deadline)}',
                            style: TextStyle(
                                fontSize: AppTextSize.small, color: context.colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 案内
                          Builder(builder: (ctx) {
                            final isDark = Theme.of(ctx).brightness == Brightness.dark;
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.warningDark.withValues(alpha: 0.25)
                                    : AppColors.warningBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.warning.withValues(alpha: 0.4)
                                      : AppColors.warningBg,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16,
                                      color: isDark ? AppColors.warningBg : AppColors.warningDark),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '日付をタップしてメニューから「休み希望 / 絶対休み / 午前休 / 午後休 / 解除」を選択',
                                      style: TextStyle(fontSize: AppTextSize.small, color: ctx.colors.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          // カレンダー
                          _buildCalendar(),
                          const SizedBox(height: 8),
                          // 凡例
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              _stateLegend(AppColors.errorBorder, '休み希望'),
                              _stateLegend(AppColors.errorDark, '絶対休み'),
                              _stateLegend(AppColors.warning, '午前休'),
                              _stateLegend(AppColors.primaryDark, '午後休'),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('キャンセル'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.save, size: 18),
                          label: const Text('保存'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// シフト希望ダイアログを開くためのヘルパー
Future<bool?> showPlusShiftRequestDialog(
  BuildContext context,
  DateTime targetMonth,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => PlusShiftRequestDialog(targetMonth: targetMonth),
  );
}

/// シフト決定ビューを開くためのヘルパー（旧: マトリクスビュー）
Future<bool?> showPlusShiftDecisionDialog(
  BuildContext context,
  DateTime targetMonth,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => PlusShiftDecisionDialog(targetMonth: targetMonth),
  );
}

/// 下位互換: 旧名でも呼び出せるように残す
Future<bool?> showPlusShiftRequestMatrixDialog(
  BuildContext context,
  DateTime targetMonth,
) =>
    showPlusShiftDecisionDialog(context, targetMonth);

/// シフト作成者向け: カレンダー上で全スタッフの希望を確認し、
/// そのまま休みを決定して実シフトに反映できるダイアログ。
class PlusShiftDecisionDialog extends StatefulWidget {
  final DateTime targetMonth;

  const PlusShiftDecisionDialog({super.key, required this.targetMonth});

  @override
  State<PlusShiftDecisionDialog> createState() =>
      _PlusShiftDecisionDialogState();
}

class _PlusShiftDecisionDialogState extends State<PlusShiftDecisionDialog> {
  bool _loading = true;
  bool _saving = false;

  // プラスのスタッフ一覧 {id, name, furigana}
  final List<Map<String, dynamic>> _plusStaffs = [];

  // 提出データ（希望） staffId → Set<DateTime>
  final Map<String, Set<DateTime>> _requestedOffDates = {};
  // 提出データ（強希望: 絶対休） staffId → Set<DateTime>
  final Map<String, Set<DateTime>> _requestedStrongOffDates = {};
  // 提出データ（午前休） staffId → Set<DateTime>
  final Map<String, Set<DateTime>> _requestedHalfAmDates = {};
  // 提出データ（午後休） staffId → Set<DateTime>
  final Map<String, Set<DateTime>> _requestedHalfPmDates = {};

  // 現在の決定状態: date → Set<staffId>
  final Map<DateTime, Set<String>> _offDates = {};

  // 保存前に上書きするために、元の plus_shifts.days をそのまま月キーごとに保持
  // monthKey(yyyy-MM) → { dayKey(int as str) → slots-list }
  final Map<String, Map<String, dynamic>> _originalDaysByMonth = {};
  final Set<String> _existingShiftDocs = <String>{};

  String get _monthKey => DateFormat('yyyy-MM').format(widget.targetMonth);

  DateTime get _rangeStart => _dateOnly(shiftRangeStart(widget.targetMonth));
  DateTime get _rangeEnd => _dateOnly(shiftRangeEnd(widget.targetMonth));

  /// 範囲に跨る月キー一覧（plus_shifts の読み書き対象）
  List<String> get _involvedMonthKeys {
    final set = <String>{};
    for (var d = _rangeStart;
        !d.isAfter(_rangeEnd);
        d = d.add(const Duration(days: 1))) {
      set.add(DateFormat('yyyy-MM').format(d));
    }
    return set.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. プラスのスタッフ一覧
      final staffSnap =
          await FirebaseFirestore.instance.collection('staffs').get();
      for (final d in staffSnap.docs) {
        final data = d.data();
        final classrooms = (data['classrooms'] as List?) ?? [];
        if (classrooms.any((c) => c.toString().contains('プラス'))) {
          _plusStaffs.add({
            'id': d.id,
            'name': (data['name'] ?? '') as String,
            'furigana': (data['furigana'] ?? '') as String,
          });
        }
      }
      _plusStaffs.sort((a, b) =>
          (a['furigana'] as String).compareTo(b['furigana'] as String));

      // 2. 希望データ（対象月ドキュメント）
      final reqDoc = await FirebaseFirestore.instance
          .collection('plus_shift_requests')
          .doc(_monthKey)
          .get();
      if (reqDoc.exists) {
        final staffs =
            Map<String, dynamic>.from(reqDoc.data()?['staffs'] ?? {});
        staffs.forEach((staffId, v) {
          if (v is! Map) return;
          final entry = Map<String, dynamic>.from(v);
          Set<DateTime> parseDates(String field) {
            final out = <DateTime>{};
            final list = (entry[field] as List?) ?? const [];
            for (final x in list) {
              final d = DateTime.tryParse(x as String);
              if (d == null) continue;
              final dd = _dateOnly(d);
              if (!dd.isBefore(_rangeStart) && !dd.isAfter(_rangeEnd)) {
                out.add(dd);
              }
            }
            return out;
          }

          final hasNewFields = entry['ngDates'] is List ||
              entry['ngStrongDates'] is List ||
              entry['halfDates'] is List ||
              entry['halfAmDates'] is List ||
              entry['halfPmDates'] is List;
          Set<DateTime> ng;
          Set<DateTime> strong;
          Set<DateTime> halfAm;
          Set<DateTime> halfPm;
          if (hasNewFields) {
            ng = parseDates('ngDates');
            strong = parseDates('ngStrongDates');
            if (entry['halfAmDates'] is List ||
                entry['halfPmDates'] is List) {
              halfAm = parseDates('halfAmDates');
              halfPm = parseDates('halfPmDates');
            } else {
              // 旧 halfDates のみ → 全て午前休として扱う
              halfAm = parseDates('halfDates');
              halfPm = <DateTime>{};
            }
          } else {
            // 旧形式 day-int（対象月）
            Set<DateTime> parseDays(String field) {
              final out = <DateTime>{};
              for (final n in (entry[field] as List?) ?? const []) {
                final day = (n as num).toInt();
                final d = DateTime(widget.targetMonth.year,
                    widget.targetMonth.month, day);
                if (!d.isBefore(_rangeStart) && !d.isAfter(_rangeEnd)) {
                  out.add(d);
                }
              }
              return out;
            }

            ng = parseDays('ngDays');
            strong = parseDays('ngDaysStrong');
            halfAm = <DateTime>{};
            halfPm = <DateTime>{};
          }
          _requestedOffDates[staffId] = ng;
          _requestedStrongOffDates[staffId] = strong;
          _requestedHalfAmDates[staffId] = halfAm;
          _requestedHalfPmDates[staffId] = halfPm;
          for (final d in ng) {
            _offDates.putIfAbsent(d, () => <String>{}).add(staffId);
          }
        });
      }

      // 3. 既存 plus_shifts は「保存時に他フィールドを温存するため」読み込むが、
      //    決定ビューの表示 (_offDates) には反映しない。
      //    過去の確定済みシフトを含めると、希望に出していない staff が
      //    決定画面に紛れる原因になる（実機バグ報告あり）。
      //    希望ベースのみで決定画面を作る。
      for (final mk in _involvedMonthKeys) {
        final shiftDoc = await FirebaseFirestore.instance
            .collection('plus_shifts')
            .doc(mk)
            .get();
        if (!shiftDoc.exists) continue;
        _existingShiftDocs.add(mk);
        final days = Map<String, dynamic>.from(shiftDoc.data()?['days'] ?? {});
        _originalDaysByMonth[mk] = days;
        // 旧実装: ここで days.slots[].isWorking==false を _offDates に追加していたが廃止。
      }
    } catch (e) {
      debugPrint('シフト決定ビューの読み込み失敗: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // 範囲は複数のカレンダー月に跨る可能性があるので、月ごとの plus_shifts doc を更新する。
      for (final mk in _involvedMonthKeys) {
        final parts = mk.split('-');
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final monthFirst = DateTime(y, m, 1);
        final monthLast = DateTime(y, m + 1, 0);
        final overlapStart =
            _rangeStart.isAfter(monthFirst) ? _rangeStart : monthFirst;
        final overlapEnd =
            _rangeEnd.isBefore(monthLast) ? _rangeEnd : monthLast;

        final original = _originalDaysByMonth[mk] ?? <String, dynamic>{};
        final newDays = <String, dynamic>{};
        original.forEach((k, v) {
          if (v is List) {
            newDays[k] = v.map((e) {
              if (e is Map) return Map<String, dynamic>.from(e);
              return e;
            }).toList();
          } else {
            newDays[k] = v;
          }
        });

        // overlap 範囲の日だけを反映する（他月分や範囲外の日は既存値を尊重）
        for (var day = overlapStart.day;
            !DateTime(y, m, day).isAfter(overlapEnd);
            day++) {
          final date = DateTime(y, m, day);
          final dayKey = day.toString();
          final offSet = _offDates[date] ?? <String>{};

          final existingSlots = (newDays[dayKey] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              <Map<String, dynamic>>[];

          // A) 休み指定 staffId を isWorking:false で upsert
          for (final staffId in offSet) {
            final idx =
                existingSlots.indexWhere((s) => s['staffId'] == staffId);
            if (idx >= 0) {
              existingSlots[idx] = {
                ...existingSlots[idx],
                'isWorking': false,
              };
            } else {
              final staff = _plusStaffs.firstWhere(
                (s) => s['id'] == staffId,
                orElse: () => <String, dynamic>{'name': ''},
              );
              existingSlots.add({
                'staffId': staffId,
                'name': staff['name'] ?? '',
                'isWorking': false,
              });
            }
          }

          // B) 休み指定されていないが isWorking:false のものは出勤に戻す
          for (int i = 0; i < existingSlots.length; i++) {
            final slot = existingSlots[i];
            final sid = slot['staffId'];
            if (sid is String &&
                slot['isWorking'] == false &&
                !offSet.contains(sid)) {
              existingSlots[i] = {
                ...slot,
                'isWorking': true,
              };
            }
          }

          if (existingSlots.isNotEmpty) {
            newDays[dayKey] = existingSlots;
          } else {
            newDays.remove(dayKey);
          }
        }

        final docRef =
            FirebaseFirestore.instance.collection('plus_shifts').doc(mk);
        if (_existingShiftDocs.contains(mk)) {
          await docRef.update({
            'days': newDays,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await docRef.set({
            'classroom': 'ビースマイリープラス湘南藤沢',
            'days': newDays,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (mounted) {
        AppFeedback.info(context, 'シフトを実予定に反映しました');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('シフト反映失敗: $e');
      if (mounted) {
        AppFeedback.info(context, '反映に失敗しました: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDayEditPopup(DateTime date) async {
    final currentOff = Set<String>.from(_offDates[date] ?? {});
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final localOff = Set<String>.from(currentOff);
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                  '${DateFormat('M/d(E)', 'ja').format(date)} の休みを決定'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final staff in _plusStaffs)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity:
                            ListTileControlAffinity.leading,
                        value: localOff.contains(staff['id']),
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              localOff.add(staff['id'] as String);
                            } else {
                              localOff.remove(staff['id']);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                staff['name'] as String,
                                style: TextStyle(fontSize: AppTextSize.body),
                              ),
                            ),
                            if ((_requestedHalfAmDates[staff['id']] ?? {})
                                .contains(date))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '午前休',
                                  style: TextStyle(
                                    fontSize: AppTextSize.xs,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if ((_requestedHalfPmDates[staff['id']] ?? {})
                                .contains(date))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryDark,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '午後休',
                                  style: TextStyle(
                                    fontSize: AppTextSize.xs,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if ((_requestedStrongOffDates[staff['id']] ?? {})
                                .contains(date))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.errorDark,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '絶対休',
                                  style: TextStyle(
                                    fontSize: AppTextSize.xs,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if ((_requestedOffDates[staff['id']] ?? {})
                                .contains(date))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '希望',
                                  style: TextStyle(
                                    fontSize: AppTextSize.xs,
                                    color: AppColors.warningDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, localOff),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        if (result.isEmpty) {
          _offDates.remove(date);
        } else {
          _offDates[date] = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.92;
    final dialogHeight = screenSize.height * 0.88;

    final submittedCount = _plusStaffs
        .where((s) => _requestedOffDates.containsKey(s['id']))
        .length;

    return Dialog(
      backgroundColor: context.colors.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ヘッダ（狭幅では2段組）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: LayoutBuilder(builder: (ctx, c) {
                      final compact = c.maxWidth < 560;
                      final titleRow = Row(
                        children: [
                          const Icon(Icons.edit_calendar,
                              color: AppColors.warning, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.targetMonth.year}年${widget.targetMonth.month}月 シフト決定',
                              style: const TextStyle(
                                  fontSize: AppTextSize.title, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                            tooltip: '閉じる',
                          ),
                        ],
                      );
                      final actionsRow = Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              '希望提出: $submittedCount/${_plusStaffs.length}人',
                              style: TextStyle(
                                  fontSize: AppTextSize.small,
                                  color: context.colors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.download_done, size: 18),
                            label: const Text('シフトに反映'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            titleRow,
                            const SizedBox(height: 4),
                            actionsRow,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          const Icon(Icons.edit_calendar,
                              color: AppColors.warning, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.targetMonth.year}年${widget.targetMonth.month}月 シフト決定',
                              style: const TextStyle(
                                  fontSize: AppTextSize.title, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            '希望提出: $submittedCount/${_plusStaffs.length}人',
                            style: TextStyle(
                                fontSize: AppTextSize.small,
                                color: context.colors.textSecondary),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.download_done, size: 18),
                            label: const Text('シフトに反映'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                            tooltip: '閉じる',
                          ),
                        ],
                      );
                    }),
                  ),
                  // 説明
                  Builder(builder: (ctx) {
                    final isDark = Theme.of(ctx).brightness == Brightness.dark;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.warningDark.withValues(alpha: 0.25)
                              : AppColors.warningBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? AppColors.warning.withValues(alpha: 0.4)
                                : AppColors.warningBg,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14,
                                color: isDark ? AppColors.warningBg : AppColors.warningDark),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '日付をタップして休みスタッフを決定。オレンジの「希望」バッジ付きはスタッフから提出された希望です。',
                                style: TextStyle(fontSize: AppTextSize.caption, color: ctx.colors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 1),
                  // カレンダー本体
                  Expanded(
                    child: _buildCalendar(),
                  ),
                  const Divider(height: 1),
                  // 凡例
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _legendSwatch(AppColors.errorBorder, '休み確定'),
                        const SizedBox(width: 12),
                        _legendSwatch(
                            AppColors.warningBg, '希望（未確定）',
                            borderColor: AppColors.warningBorder),
                        const SizedBox(width: 12),
                        _legendSwatch(AppColors.errorDark, '絶対休み'),
                        const SizedBox(width: 12),
                        _legendSwatch(AppColors.warning, '午前休'),
                        const SizedBox(width: 12),
                        _legendSwatch(AppColors.primaryDark, '午後休'),
                        const Spacer(),
                        Text(
                          '※「シフトに反映」を押すと実シフトに書き込まれます',
                          style: TextStyle(
                              fontSize: AppTextSize.caption,
                              color: context.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCalendar() {
    // 月曜始まり 7列表示。日曜列は定休日としてグレーアウト。
    // 範囲（_rangeStart 〜 _rangeEnd）を包む週単位で描画する。
    final rangeStart = _rangeStart;
    final rangeEnd = _rangeEnd;
    // グリッド開始 = rangeStart を含む週の月曜
    final gridStart =
        rangeStart.subtract(Duration(days: (rangeStart.weekday - 1) % 7));
    // グリッド終端 = rangeEnd を含む週の日曜
    final gridEnd = rangeEnd.add(Duration(days: (7 - rangeEnd.weekday) % 7));

    const labels7 = ['月', '火', '水', '木', '金', '土', '日'];
    final totalCells = gridEnd.difference(gridStart).inDays + 1;
    final rows = (totalCells / 7).ceil();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 曜日ヘッダ
          Row(
            children: List.generate(7, (i) {
              final isSun = i == 6;
              final isSat = i == 5;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSun
                        ? (isDark ? AppColors.errorDark.withValues(alpha: 0.2) : AppColors.errorBg)
                        : context.colors.chipBg,
                    border: Border(
                      right: BorderSide(color: context.colors.borderMedium),
                      top: BorderSide(color: context.colors.borderMedium),
                      bottom: BorderSide(color: context.colors.borderMedium),
                      left: i == 0
                          ? BorderSide(color: context.colors.borderMedium)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    labels7[i],
                    style: TextStyle(
                      fontSize: AppTextSize.small,
                      fontWeight: FontWeight.bold,
                      color: isSun
                          ? AppColors.errorBorder
                          : isSat
                              ? AppColors.infoBorder
                              : context.colors.textPrimary,
                    ),
                  ),
                ),
              );
            }),
          ),
          // グリッド（縦スクロール可）
          Expanded(
            child: ListView.builder(
              itemCount: rows,
              itemBuilder: (ctx, r) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(7, (c) {
                      final cellIndex = r * 7 + c;
                      final date =
                          gridStart.add(Duration(days: cellIndex));
                      final inRange = !date.isBefore(rangeStart) &&
                          !date.isAfter(rangeEnd);
                      return Expanded(
                        child: _buildDayCell(
                          date: date,
                          columnIndex: c,
                          outOfRange: !inRange,
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell({required DateTime? date, required int columnIndex, bool outOfRange = false}) {
    final isSun = columnIndex == 6;
    final isSat = columnIndex == 5;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final numberColor = isSun
        ? AppColors.errorBorder
        : isSat
            ? AppColors.infoBorder
            : context.colors.textPrimary;
    final isOtherMonth =
        date != null && date.month != widget.targetMonth.month;
    final dayLabel = date == null
        ? ''
        : isOtherMonth
            ? '${date.month}/${date.day}'
            : '${date.day}';

    // 日曜は定休表示
    if (isSun) {
      return Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: isDark ? AppColors.errorDark.withValues(alpha: 0.15) : AppColors.errorBg,
          border: Border.all(color: context.colors.borderMedium),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date != null)
              Text(
                dayLabel,
                style: TextStyle(
                  fontSize: AppTextSize.small,
                  color: (isDark ? AppColors.errorBorder : AppColors.errorBorder)
                      .withValues(alpha: outOfRange ? 0.4 : 1.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              '定休',
              style: TextStyle(
                fontSize: AppTextSize.xxs,
                color: (isDark ? AppColors.errorBorder : AppColors.errorBorder)
                    .withValues(alpha: outOfRange ? 0.4 : 1.0),
              ),
            ),
          ],
        ),
      );
    }

    if (date == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: context.colors.tagBg,
          border: Border.all(color: context.colors.borderMedium),
        ),
      );
    }

    if (outOfRange) {
      return Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: context.colors.tagBg.withValues(alpha: 0.4),
          border: Border.all(color: context.colors.borderMedium),
        ),
        padding: const EdgeInsets.all(4),
        child: Text(
          dayLabel,
          style: TextStyle(
            fontSize: AppTextSize.small,
            color: numberColor.withValues(alpha: 0.4),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final offStaffIds = _offDates[date] ?? <String>{};
    // 半休希望（休みではないので _offDates には含まれない）
    final halfAmStaffIds = <String>{};
    final halfPmStaffIds = <String>{};
    _requestedHalfAmDates.forEach((sid, dates) {
      if (dates.contains(date) && !offStaffIds.contains(sid)) {
        halfAmStaffIds.add(sid);
      }
    });
    _requestedHalfPmDates.forEach((sid, dates) {
      if (dates.contains(date) && !offStaffIds.contains(sid)) {
        halfPmStaffIds.add(sid);
      }
    });
    final chips = <Widget>[];

    Widget halfChip(Color color, String tag, String name) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tag,
                  style: const TextStyle(
                      fontSize: AppTextSize.xs,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 2),
              Text(name,
                  style: const TextStyle(
                      fontSize: AppTextSize.xs,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        );

    for (final staffId in halfAmStaffIds) {
      final staff = _plusStaffs.firstWhere(
        (s) => s['id'] == staffId,
        orElse: () => <String, dynamic>{'name': '?'},
      );
      chips.add(halfChip(
          AppColors.warning, '前', staff['name'] as String));
    }
    for (final staffId in halfPmStaffIds) {
      final staff = _plusStaffs.firstWhere(
        (s) => s['id'] == staffId,
        orElse: () => <String, dynamic>{'name': '?'},
      );
      chips.add(halfChip(
          AppColors.primaryDark, '後', staff['name'] as String));
    }
    for (final staffId in offStaffIds) {
      final staff = _plusStaffs.firstWhere(
        (s) => s['id'] == staffId,
        orElse: () => <String, dynamic>{'name': '?'},
      );
      final isRequested =
          (_requestedOffDates[staffId] ?? {}).contains(date);
      final isStrong =
          (_requestedStrongOffDates[staffId] ?? {}).contains(date);
      final Color chipBg;
      final Color chipFg;
      Border? chipBorder;
      if (isStrong) {
        chipBg = AppColors.errorDark;
        chipFg = Colors.white;
      } else if (isRequested) {
        chipBg = isDark ? AppColors.warningDark.withValues(alpha: 0.4) : AppColors.warningBg;
        chipFg = isDark ? AppColors.warningBg : AppColors.warningDark;
        chipBorder = Border.all(color: AppColors.warningBorder);
      } else {
        chipBg = AppColors.errorBorder;
        chipFg = Colors.white;
      }
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(4),
            border: chipBorder,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isStrong) ...[
                const Text(
                  '!',
                  style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Text(
                staff['name'] as String,
                style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: chipFg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _showDayEditPopup(date),
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          border: Border.all(color: context.colors.borderMedium),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  dayLabel,
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    fontWeight: FontWeight.bold,
                    color: numberColor,
                  ),
                ),
                if (offStaffIds.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: context.colors.borderLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${offStaffIds.length}',
                      style: TextStyle(
                          fontSize: AppTextSize.xxs, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: chips,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendSwatch(Color color, String label, {Color? borderColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: context.colors.iconMuted),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: AppTextSize.small)),
      ],
    );
  }

}

/// 今日の日付から対象月を決定する共通ロジック。
/// 締切は前月10日。10日までは翌月、11日以降は翌々月が対象。
/// - 例: 4/8 → 5月（締切 4/10）
/// - 例: 4/11 → 6月（締切 5/10）
/// - 例: 4/30 → 6月（締切 5/10）
DateTime resolveShiftRequestTargetMonth([DateTime? now]) {
  final n = now ?? DateTime.now();
  if (n.day <= 10) {
    return DateTime(n.year, n.month + 1, 1);
  }
  return DateTime(n.year, n.month + 2, 1);
}
