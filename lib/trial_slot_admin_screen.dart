// 体験予約枠の管理画面（スタッフ用）。
// 予約系サービス（STORES予約/Airリザーブ/Square/Calendly等）で一般的な
// 「月カレンダー一覧 → 日を選んで時間枠を個別にON/OFF」型。
//
// 標準時間帯(trial_config/default)を編集し、各日の時間枠を公開/非公開できる。
// trial_slots/{date_HHMM} = { date, start, end, classroom, status: open|booked }。
// 予約が入った枠(booked)は残り、非公開操作では消えない。

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
  Map<String, dynamic> toMap() => {'start': start, 'end': end};
}

class _TrialSlotAdminScreenState extends State<TrialSlotAdminScreen> {
  static const _defaultSlots = [
    _TimeSlot('09:30', '10:30'),
    _TimeSlot('11:00', '12:00'),
    _TimeSlot('14:00', '15:00'),
  ];
  static const _weekHeaders = ['日', '月', '火', '水', '木', '金', '土'];

  final _db = FirebaseFirestore.instance;
  List<_TimeSlot> _timeSlots = [];
  bool _configLoaded = false;

  late DateTime _month; // 表示中の月（1日）
  late DateTime _selected; // 選択中の日

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selected = DateTime(now.year, now.month, now.day);
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final ref = _db.collection('trial_config').doc('default');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'timeSlots': _defaultSlots.map((s) => s.toMap()).toList(),
        'classroom': '湘南藤沢教室',
      });
      _timeSlots = List.of(_defaultSlots);
    } else {
      final list = (snap.data()?['timeSlots'] as List?) ?? [];
      _timeSlots = list
          .map((e) => _TimeSlot(
              (e['start'] as String?) ?? '', (e['end'] as String?) ?? ''))
          .where((s) => s.start.isNotEmpty)
          .toList();
      if (_timeSlots.isEmpty) _timeSlots = List.of(_defaultSlots);
    }
    if (mounted) setState(() => _configLoaded = true);
  }

  Future<void> _saveConfig() async {
    await _db.collection('trial_config').doc('default').set({
      'timeSlots': _timeSlots.map((s) => s.toMap()).toList(),
      'classroom': '湘南藤沢教室',
    }, SetOptions(merge: true));
  }

  String _slotId(String date, String start) =>
      '${date}_${start.replaceAll(':', '')}';
  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // ─── 枠の公開/非公開 ───

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

  Future<void> _setAllForDay(String date, bool open,
      Map<String, DocumentSnapshot> dayBySlot) async {
    final batch = _db.batch();
    for (final t in _timeSlots) {
      final ref = _db.collection('trial_slots').doc(_slotId(date, t.start));
      final existing = dayBySlot[t.start];
      final booked = existing != null &&
          (existing.data() as Map?)?['status'] == 'booked';
      if (booked) continue; // 予約済みは触らない
      if (open) {
        batch.set(ref, {
          'date': date,
          'start': t.start,
          'end': t.end,
          'classroom': '湘南藤沢教室',
          'status': 'open',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (existing != null) {
        batch.delete(ref);
      }
    }
    await batch.commit();
  }

  // ─── 時刻選択（ドロップダウン式・アナログ時計は使わない）───

  Future<String?> _pickTime(String title, String initial) async {
    final parts = initial.split(':');
    int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
    int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    if (![0, 15, 30, 45].contains(minute)) minute = 0;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final c = ctx.colors;
        Widget dd<T>(T value, List<T> items, String Function(T) label,
                ValueChanged<T?> onChanged) =>
            DropdownButton<T>(
              value: value,
              underline: const SizedBox.shrink(),
              items: items
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text(label(e))))
                  .toList(),
              onChanged: onChanged,
            );
        return AlertDialog(
          title: Text(title),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              dd<int>(hour, [for (int h = 7; h <= 21; h++) h],
                  (h) => '$h', (v) => setS(() => hour = v ?? hour)),
              Text('時',
                  style: TextStyle(
                      fontSize: AppTextSize.body, color: c.textSecondary)),
              const SizedBox(width: 16),
              dd<int>(minute, const [0, 15, 30, 45],
                  (m) => m.toString().padLeft(2, '0'),
                  (v) => setS(() => minute = v ?? minute)),
              Text('分',
                  style: TextStyle(
                      fontSize: AppTextSize.body, color: c.textSecondary)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx,
                  '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'),
              child: const Text('OK'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _editTimeSlots() async {
    final working = List<_TimeSlot>.of(_timeSlots);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final c = ctx.colors;
        Future<void> addSlot() async {
          final start = await _pickTime('開始時刻', '09:30');
          if (start == null) return;
          final end = await _pickTime('終了時刻', '10:30');
          if (end == null) return;
          setS(() {
            working.add(_TimeSlot(start, end));
            working.sort((a, b) => a.start.compareTo(b.start));
          });
        }

        return AlertDialog(
          title: const Text('標準時間帯の編集'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (working.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('時間帯がありません',
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: c.textTertiary)),
                  ),
                for (int i = 0; i < working.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${working[i].start}〜${working[i].end}',
                        style: const TextStyle(fontSize: AppTextSize.body)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: ctx.alerts.urgent.icon),
                      onPressed: () => setS(() => working.removeAt(i)),
                    ),
                  ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: addSlot,
                    icon: const Icon(Icons.add),
                    label: const Text('時間帯を追加'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                setState(() => _timeSlots = working);
                _saveConfig();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      }),
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
      body: !_configLoaded
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('trial_slots')
          .where('date', isGreaterThanOrEqualTo: _ymd(_month))
          .where('date', isLessThanOrEqualTo: _ymd(monthEnd))
          .snapshots(),
      builder: (context, snap) {
        // date -> (start -> doc)
        final byDate = <String, Map<String, DocumentSnapshot>>{};
        for (final d in (snap.data?.docs ?? [])) {
          final m = d.data() as Map;
          final date = m['date'] as String;
          (byDate[date] ??= {})[m['start'] as String] = d;
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _timeSlotBar(),
              _monthNav(),
              _calendar(byDate),
              const SizedBox(height: 8),
              _dayDetail(byDate[_ymd(_selected)] ?? const {}),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _timeSlotBar() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: c.cardBg,
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: c.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in _timeSlots)
                  Chip(
                    label: Text('${t.start}〜${t.end}',
                        style: const TextStyle(fontSize: AppTextSize.caption)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
          TextButton(onPressed: _editTimeSlots, child: const Text('標準時間帯を編集')),
        ],
      ),
    );
  }

  Widget _monthNav() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() =>
                _month = DateTime(_month.year, _month.month - 1, 1)),
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
            onPressed: () => setState(() =>
                _month = DateTime(_month.year, _month.month + 1, 1)),
          ),
        ],
      ),
    );
  }

  Widget _calendar(Map<String, Map<String, DocumentSnapshot>> byDate) {
    final c = context.colors;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = _month.weekday % 7; // 日曜始まり
    final cells = <DateTime?>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(null);
    }
    for (int d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(_month.year, _month.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(_weekHeaders[i],
                        style: TextStyle(
                            fontSize: AppTextSize.caption,
                            fontWeight: FontWeight.bold,
                            color: i == 0
                                ? AppColors.error
                                : i == 6
                                    ? AppColors.secondary
                                    : c.textSecondary)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.0,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final date in cells)
                date == null
                    ? const SizedBox.shrink()
                    : _dayCell(date, today0, byDate[_ymd(date)] ?? const {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date, DateTime today0,
      Map<String, DocumentSnapshot> dayBySlot) {
    final c = context.colors;
    final isPast = date.isBefore(today0);
    final isSelected = date == _selected;
    int openCount = 0, bookedCount = 0;
    for (final d in dayBySlot.values) {
      final st = (d.data() as Map?)?['status'];
      if (st == 'booked') {
        bookedCount++;
      } else if (st == 'open') {
        openCount++;
      }
    }
    final wd = date.weekday; // Mon=1..Sun=7
    final numColor = isPast
        ? c.textTertiary
        : wd == 7
            ? AppColors.error
            : wd == 6
                ? AppColors.secondary
                : c.textPrimary;

    return InkWell(
      onTap: isPast ? null : () => setState(() => _selected = date),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.14)
              : (openCount > 0 || bookedCount > 0)
                  ? c.cardBg
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : c.borderLight,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${date.day}',
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.bold,
                    color: numColor)),
            const SizedBox(height: 2),
            if (bookedCount > 0)
              _badge('予約$bookedCount', AppColors.primary, Colors.white)
            else if (openCount > 0)
              _badge('公開$openCount', AppColors.success.withValues(alpha: 0.18),
                  AppColors.success)
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: AppTextSize.xs, color: fg, fontWeight: FontWeight.bold)),
    );
  }

  Widget _dayDetail(Map<String, DocumentSnapshot> dayBySlot) {
    final c = context.colors;
    final dateStr = _ymd(_selected);
    final wd = _weekHeaders[_selected.weekday % 7];
    final anyOpen = _timeSlots.any((t) {
      final d = dayBySlot[t.start];
      return d != null && (d.data() as Map?)?['status'] == 'open';
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${_selected.month}月${_selected.day}日（$wd）',
                  style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary)),
              const Spacer(),
              TextButton(
                onPressed: () => _setAllForDay(dateStr, !anyOpen, dayBySlot),
                child: Text(anyOpen ? 'すべて非公開' : 'すべて公開'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final t in _timeSlots) _slotRow(dateStr, t, dayBySlot[t.start]),
        ],
      ),
    );
  }

  Widget _slotRow(String date, _TimeSlot t, DocumentSnapshot? doc) {
    final c = context.colors;
    final status = doc == null ? 'none' : (doc.data() as Map?)?['status'];
    final isBooked = status == 'booked';
    final isOpen = status == 'open';
    final bookedName = isBooked
        ? ((doc!.data() as Map?)?['childName'] ??
            (doc.data() as Map?)?['parentName'] ??
            '予約あり')
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text('${t.start}〜${t.end}',
                style: TextStyle(
                    fontSize: AppTextSize.body, color: c.textPrimary)),
          ),
          Expanded(
            child: isBooked
                ? Row(
                    children: [
                      Icon(Icons.event_available,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('予約済み：$bookedName',
                            style: TextStyle(
                                fontSize: AppTextSize.caption,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
                : Text(isOpen ? '公開中' : '非公開',
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: isOpen ? AppColors.success : c.textTertiary)),
          ),
          if (isBooked)
            Icon(Icons.lock_outline, size: 18, color: c.textTertiary)
          else
            Switch(
              value: isOpen,
              onChanged: (v) =>
                  v ? _openSlot(date, t) : _closeSlot(date, t),
            ),
        ],
      ),
    );
  }
}
