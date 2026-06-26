// 体験予約枠の管理画面（スタッフ用）。
// 標準時間帯（trial_config/default）を編集し、カレンダーで「公開する日」を選ぶ。
// 公開でその日の標準時間帯の枠（trial_slots, status=open）を生成、非公開で open 枠を削除。
// 予約が入った枠（status=booked）は非公開にしても残る。

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

  final _db = FirebaseFirestore.instance;
  List<_TimeSlot> _timeSlots = [];
  bool _configLoaded = false;

  @override
  void initState() {
    super.initState();
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
    setState(() => _configLoaded = true);
  }

  Future<void> _saveConfig() async {
    await _db.collection('trial_config').doc('default').set({
      'timeSlots': _timeSlots.map((s) => s.toMap()).toList(),
      'classroom': '湘南藤沢教室',
    }, SetOptions(merge: true));
  }

  String _slotId(String date, String start) =>
      '${date}_${start.replaceAll(':', '')}';

  Future<void> _openDate(String date, List<QueryDocumentSnapshot> existing) async {
    final batch = _db.batch();
    final existingStarts =
        existing.map((d) => (d.data() as Map)['start'] as String).toSet();
    for (final t in _timeSlots) {
      if (existingStarts.contains(t.start)) continue;
      final ref = _db.collection('trial_slots').doc(_slotId(date, t.start));
      batch.set(ref, {
        'date': date,
        'start': t.start,
        'end': t.end,
        'classroom': '湘南藤沢教室',
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _closeDate(List<QueryDocumentSnapshot> daySlots) async {
    final batch = _db.batch();
    for (final d in daySlots) {
      if ((d.data() as Map)['status'] == 'open') {
        batch.delete(d.reference);
      }
    }
    await batch.commit();
  }

  void _editTimeSlots() async {
    final working = List<_TimeSlot>.of(_timeSlots);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> addSlot() async {
          final t1 = await showTimePicker(
              context: ctx,
              initialTime: const TimeOfDay(hour: 9, minute: 30),
              helpText: '開始時刻');
          if (t1 == null) return;
          final t2 = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: t1.hour + 1, minute: t1.minute),
              helpText: '終了時刻');
          if (t2 == null) return;
          String fmt(TimeOfDay t) =>
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          setS(() => working.add(_TimeSlot(fmt(t1), fmt(t2))));
        }

        return AlertDialog(
          title: const Text('標準時間帯の編集'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < working.length; i++)
                  ListTile(
                    dense: true,
                    title: Text('${working[i].start}〜${working[i].end}'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: ctx.alerts.urgent.icon),
                      onPressed: () => setS(() => working.removeAt(i)),
                    ),
                  ),
                TextButton.icon(
                  onPressed: addSlot,
                  icon: const Icon(Icons.add),
                  label: const Text('時間帯を追加'),
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
                working.sort((a, b) => a.start.compareTo(b.start));
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
          onPressed: () =>
              widget.onBack != null ? widget.onBack!() : Navigator.maybePop(context),
        ),
      ),
      body: !_configLoaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _timeSlotBar(),
                Expanded(child: _dateList()),
              ],
            ),
    );
  }

  Widget _timeSlotBar() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  ),
              ],
            ),
          ),
          TextButton(onPressed: _editTimeSlots, child: const Text('標準時間帯を編集')),
        ],
      ),
    );
  }

  Widget _dateList() {
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('trial_slots')
          .where('date', isGreaterThanOrEqualTo: todayStr)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final byDate = <String, List<QueryDocumentSnapshot>>{};
        for (final d in docs) {
          final date = (d.data() as Map)['date'] as String;
          (byDate[date] ??= []).add(d);
        }
        // 今日から42日分
        final days = List.generate(42, (i) => today.add(Duration(days: i)));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: days.length,
          itemBuilder: (context, i) {
            final day = days[i];
            final dateStr = DateFormat('yyyy-MM-dd').format(day);
            final daySlots = byDate[dateStr] ?? [];
            return _dateRow(day, dateStr, daySlots);
          },
        );
      },
    );
  }

  Widget _dateRow(
      DateTime day, String dateStr, List<QueryDocumentSnapshot> daySlots) {
    final c = context.colors;
    final isOpen = daySlots.any((d) => (d.data() as Map)['status'] == 'open');
    final booked = daySlots
        .where((d) => (d.data() as Map)['status'] == 'booked')
        .toList();
    final weekday = ['月', '火', '水', '木', '金', '土', '日'][day.weekday - 1];
    final isWeekend = day.weekday >= 6;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderLight),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              '${day.month}/${day.day}（$weekday）',
              style: TextStyle(
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.bold,
                color: isWeekend
                    ? (day.weekday == 7
                        ? AppColors.error
                        : AppColors.secondary)
                    : c.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: booked.isEmpty
                ? Text(isOpen ? '公開中' : '非公開',
                    style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: isOpen ? AppColors.success : c.textTertiary))
                : Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      for (final b in booked)
                        Text(
                            '${(b.data() as Map)['start']} ${(b.data() as Map)['childName'] ?? (b.data() as Map)['parentName'] ?? '予約'}',
                            style: TextStyle(
                                fontSize: AppTextSize.caption,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
          Switch(
            value: isOpen,
            onChanged: (v) async {
              if (v) {
                await _openDate(dateStr, daySlots);
              } else {
                await _closeDate(daySlots);
              }
            },
          ),
        ],
      ),
    );
  }
}
