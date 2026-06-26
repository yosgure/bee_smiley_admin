// 体験予約枠の管理画面（スタッフ用）。
// 月カレンダーを1ページに収め、各日のセル内で時間枠ごとに公開/非公開を選択する。
// 標準時間帯は固定4枠。日曜は休みでグレーアウト。月曜始まり。
//
// trial_slots/{date_HHMM} = { date, start, end, classroom, status: open|booked }。
// 予約が入った枠(booked)はロック表示され、操作では消えない。

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';

class TrialSlotAdminScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const TrialSlotAdminScreen({super.key, this.onBack});

  @override
  State<TrialSlotAdminScreen> createState() => _TrialSlotAdminScreenState();
}

class _TimeSlot {
  final String start;
  final String end;
  const _TimeSlot(this.start, this.end);
}

class _TrialSlotAdminScreenState extends State<TrialSlotAdminScreen> {
  // 標準時間帯（固定・基本変更なし）
  static const _timeSlots = [
    _TimeSlot('09:30', '10:30'),
    _TimeSlot('11:00', '12:00'),
    _TimeSlot('14:00', '15:00'),
    _TimeSlot('15:30', '16:30'),
  ];
  // 月曜始まり
  static const _weekHeaders = ['月', '火', '水', '木', '金', '土', '日'];

  final _db = FirebaseFirestore.instance;
  late DateTime _month; // 表示中の月（1日）
  // プラスのスケジュール休業日（表示中の月の日番号）。plus_shifts/{yyyy-MM}.holidays と連動。
  Set<int> _holidayDays = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    final monthKey = DateFormat('yyyy-MM').format(_month);
    final days = <int>{};
    try {
      final doc = await _db.collection('plus_shifts').doc(monthKey).get();
      if (doc.exists) {
        final list = (doc.data()?['holidays'] as List<dynamic>?) ?? [];
        for (final raw in list) {
          final d = int.tryParse(raw.toString()) ?? 0;
          if (d > 0) days.add(d);
        }
      }
    } catch (_) {
      // 読み取り失敗時は休業日なし扱い（日曜のみ休み）
    }
    if (mounted) setState(() => _holidayDays = days);
  }

  void _goMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _loadHolidays();
  }

  String _slotId(String date, String start) =>
      '${date}_${start.replaceAll(':', '')}';
  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _openSlot(String date, _TimeSlot t) async {
    await _db.collection('trial_slots').doc(_slotId(date, t.start)).set({
      'date': date,
      'start': t.start,
      'end': t.end,
      'classroom': '湘南藤沢教室',
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _closeSlot(String date, _TimeSlot t) async {
    await _db.collection('trial_slots').doc(_slotId(date, t.start)).delete();
  }

  void _showBookingInfo(_TimeSlot t, DocumentSnapshot doc) {
    final m = doc.data() as Map? ?? {};
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.start}〜${t.end} の予約'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((m['childName'] ?? '').toString().isNotEmpty)
              Text('お子さま：${m['childName']}'),
            if ((m['parentName'] ?? '').toString().isNotEmpty)
              Text('保護者：${m['parentName']}'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.scaffoldBg,
      appBar: AppBar(
        title: const Text('体験予約枠'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => widget.onBack != null
              ? widget.onBack!()
              : Navigator.maybePop(context),
        ),
      ),
      body: Column(
        children: [
          _monthNav(),
          _weekdayHeader(),
          Expanded(child: _calendar()),
        ],
      ),
    );
  }

  Widget _monthNav() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goMonth(-1),
          ),
          SizedBox(
            width: 140,
            child: Text('${_month.year}年${_month.month}月',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppTextSize.titleSm,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _weekdayHeader() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (int i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(_weekHeaders[i],
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        fontWeight: FontWeight.bold,
                        color: i == 6
                            ? AppColors.error // 日
                            : i == 5
                                ? AppColors.secondary // 土
                                : c.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _calendar() {
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('trial_slots')
          .where('date', isGreaterThanOrEqualTo: _ymd(_month))
          .where('date', isLessThanOrEqualTo: _ymd(monthEnd))
          .snapshots(),
      builder: (context, snap) {
        final byDate = <String, Map<String, DocumentSnapshot>>{};
        for (final d in (snap.data?.docs ?? [])) {
          final m = d.data() as Map;
          (byDate[m['date'] as String] ??= {})[m['start'] as String] = d;
        }

        final daysInMonth = monthEnd.day;
        final leading = (_month.weekday - 1) % 7; // 月曜始まり
        final cells = <DateTime?>[];
        for (int i = 0; i < leading; i++) {
          cells.add(null);
        }
        for (int d = 1; d <= daysInMonth; d++) {
          cells.add(DateTime(_month.year, _month.month, d));
        }
        while (cells.length % 7 != 0) {
          cells.add(null);
        }
        final weeks = cells.length ~/ 7;
        final today = DateTime.now();
        final today0 = DateTime(today.year, today.month, today.day);

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            children: [
              for (int w = 0; w < weeks; w++)
                Expanded(
                  child: Row(
                    children: [
                      for (int i = 0; i < 7; i++)
                        Expanded(
                          child: _cell(cells[w * 7 + i], today0, byDate),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(DateTime? date, DateTime today0,
      Map<String, Map<String, DocumentSnapshot>> byDate) {
    final c = context.colors;
    if (date == null) return const SizedBox.shrink();

    final isSunday = date.weekday == DateTime.sunday;
    // プラスのスケジュールで休業設定された日も休み扱い
    final isHoliday = isSunday || _holidayDays.contains(date.day);
    final isPast = date.isBefore(today0);
    final disabled = isHoliday || isPast;
    final dayBySlot = byDate[_ymd(date)] ?? const {};

    final numColor = disabled
        ? c.textTertiary
        : date.weekday == DateTime.saturday
            ? AppColors.secondary
            : c.textPrimary;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: disabled
            ? c.scaffoldBg.withValues(alpha: 0.4)
            : c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
            child: Row(
              children: [
                Text('${date.day}',
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        fontWeight: FontWeight.bold,
                        color: numColor)),
                if (isHoliday) ...[
                  const SizedBox(width: 4),
                  Text('休',
                      style: TextStyle(
                          fontSize: AppTextSize.xs, color: c.textTertiary)),
                ],
              ],
            ),
          ),
          Expanded(
            child: disabled
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final t in _timeSlots)
                            _slotChip(_ymd(date), t, dayBySlot[t.start]),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _slotChip(String date, _TimeSlot t, DocumentSnapshot? doc) {
    final status = doc == null ? 'none' : (doc.data() as Map?)?['status'];
    final isBooked = status == 'booked';
    final isOpen = status == 'open';

    Color bg, fg, border;
    if (isBooked) {
      bg = AppColors.primary;
      fg = Colors.white;
      border = AppColors.primary;
    } else if (isOpen) {
      bg = AppColors.success;
      fg = Colors.white;
      border = AppColors.success;
    } else {
      bg = Colors.transparent;
      fg = context.colors.textTertiary;
      border = context.colors.borderLight;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          if (isBooked) {
            _showBookingInfo(t, doc!);
          } else if (isOpen) {
            _closeSlot(date, t);
          } else {
            _openSlot(date, t);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBooked) ...[
                const Icon(Icons.lock, size: 11, color: Colors.white),
                const SizedBox(width: 3),
              ],
              Text('${t.start}〜${t.end}',
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: fg,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
