import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

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

  // 自分の入力
  // _myNgDays: 通常の休み希望
  // _myNgStrongDays: どうしても休みたい（強い希望）
  // ※ _myNgStrongDays ⊆ _myNgDays の関係を保つ
  final Set<int> _myNgDays = <int>{};
  final Set<int> _myNgStrongDays = <int>{};

  String get _monthKey => DateFormat('yyyy-MM').format(widget.targetMonth);
  int get _daysInMonth =>
      DateTime(widget.targetMonth.year, widget.targetMonth.month + 1, 0).day;

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

      // 2. 自分の既存エントリを読む
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
            final ngDays = (mine['ngDays'] as List?) ?? [];
            _myNgDays.addAll(ngDays.map((e) => (e as num).toInt()));
            final ngStrong = (mine['ngDaysStrong'] as List?) ?? [];
            _myNgStrongDays.addAll(ngStrong.map((e) => (e as num).toInt()));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインユーザーが確認できませんでした')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('plus_shift_requests')
          .doc(_monthKey);
      final snapshot = await docRef.get();

      final ngList = _myNgDays.toList()..sort();
      // 強希望は通常希望の部分集合として保存
      final ngStrongList =
          _myNgStrongDays.where(_myNgDays.contains).toList()..sort();
      final myEntry = <String, dynamic>{
        'staffName': _myStaffName ?? '',
        'ngDays': ngList,
        'ngDaysStrong': ngStrongList,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (snapshot.exists) {
        final data = snapshot.data() ?? {};
        final existingStaffs =
            Map<String, dynamic>.from(data['staffs'] ?? {});
        // 既存エントリがあれば submittedAt は保持、無ければ新規作成扱い
        if (existingStaffs.containsKey(_myStaffId)) {
          final prev =
              Map<String, dynamic>.from(existingStaffs[_myStaffId] as Map);
          myEntry['submittedAt'] = prev['submittedAt'] ?? FieldValue.serverTimestamp();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シフト希望を保存しました')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('シフト希望の保存失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildDeadlineBadge() {
    final days = _daysUntilDeadline;
    late final Color bg;
    late final Color fg;
    late final String label;
    if (days < 0) {
      bg = Colors.red.shade700;
      fg = Colors.white;
      label = '締切超過 ${-days}日';
    } else if (days <= 3) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      label = '締切まであと$days日';
    } else {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
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
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
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
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildCalendar() {
    final firstDay =
        DateTime(widget.targetMonth.year, widget.targetMonth.month, 1);
    final startWeekday = firstDay.weekday % 7; // 日=0, 月=1, ...
    final totalCells = startWeekday + _daysInMonth;
    final rows = (totalCells / 7).ceil();

    const weekLabels = ['日', '月', '火', '水', '木', '金', '土'];

    return Column(
      children: [
        // 曜日ヘッダ
        Row(
          children: List.generate(7, (i) {
            final isSun = i == 0;
            final isSat = i == 6;
            return Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    weekLabels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSun
                          ? Colors.red
                          : isSat
                              ? Colors.blue
                              : Colors.black87,
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
              final day = cellIndex - startWeekday + 1;
              if (day < 1 || day > _daysInMonth) {
                return const Expanded(child: SizedBox(height: 44));
              }
              final isNg = _myNgDays.contains(day);
              final isStrong = _myNgStrongDays.contains(day);
              final dow = DateTime(
                widget.targetMonth.year,
                widget.targetMonth.month,
                day,
              ).weekday; // 月=1, ..., 日=7
              final dayColor = dow == 7
                  ? Colors.red
                  : dow == 6
                      ? Colors.blue
                      : Colors.black87;
              // 3状態: なし → 休 → 絶対休 → なし
              final Color bgColor;
              if (isStrong) {
                bgColor = Colors.red.shade800;
              } else if (isNg) {
                bgColor = Colors.red.shade400;
              } else {
                bgColor = Colors.grey.shade50;
              }
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          // なし → 休 → 絶対休 → なし の順に循環
                          if (!isNg) {
                            _myNgDays.add(day);
                          } else if (!isStrong) {
                            _myNgStrongDays.add(day);
                          } else {
                            _myNgDays.remove(day);
                            _myNgStrongDays.remove(day);
                          }
                        });
                      },
                      child: SizedBox(
                        height: 48,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isNg ? Colors.white : dayColor,
                              ),
                            ),
                            if (isStrong)
                              const Text(
                                '絶対休',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            else if (isNg)
                              const Text(
                                '休',
                                style: TextStyle(
                                  fontSize: 10,
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
      backgroundColor: Colors.white,
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
                            color: Colors.orange, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.targetMonth.year}年${widget.targetMonth.month}月のシフト希望',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '締切: ${DateFormat('M/d', 'ja').format(_deadline)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSub),
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16,
                                    color: Colors.orange.shade800),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    '日付をタップ: 1回目「休み希望」→ 2回目「絶対休」→ 3回目 解除',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // カレンダー
                          _buildCalendar(),
                          const SizedBox(height: 8),
                          // 凡例
                          Row(
                            children: [
                              _stateLegend(Colors.red.shade400, '休み希望'),
                              const SizedBox(width: 12),
                              _stateLegend(Colors.red.shade800, '絶対休'),
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
                            backgroundColor: Colors.orange,
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

  // 提出データ（希望） staffId → Set<int days>
  final Map<String, Set<int>> _requestedOffDays = {};
  // 提出データ（強希望: 絶対休） staffId → Set<int days>
  final Map<String, Set<int>> _requestedStrongOffDays = {};

  // 現在の決定状態: day(int) → Set<staffId>
  // 初期値: 希望データ + 既存 plus_shifts の isWorking:false を統合
  final Map<int, Set<String>> _offDays = {};

  // 保存前に上書きするために、元の plus_shifts.days をそのまま持っておく
  Map<String, dynamic> _originalDays = {};
  bool _originalExists = false;

  String get _monthKey => DateFormat('yyyy-MM').format(widget.targetMonth);
  int get _daysInMonth =>
      DateTime(widget.targetMonth.year, widget.targetMonth.month + 1, 0).day;

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

      // 2. 希望データ
      final reqDoc = await FirebaseFirestore.instance
          .collection('plus_shift_requests')
          .doc(_monthKey)
          .get();
      if (reqDoc.exists) {
        final staffs =
            Map<String, dynamic>.from(reqDoc.data()?['staffs'] ?? {});
        staffs.forEach((staffId, v) {
          if (v is Map) {
            final entry = Map<String, dynamic>.from(v);
            final days = ((entry['ngDays'] as List?) ?? [])
                .map((e) => (e as num).toInt())
                .toSet();
            _requestedOffDays[staffId] = days;
            final strongDays = ((entry['ngDaysStrong'] as List?) ?? [])
                .map((e) => (e as num).toInt())
                .toSet();
            _requestedStrongOffDays[staffId] = strongDays;
            for (final d in days) {
              _offDays.putIfAbsent(d, () => <String>{}).add(staffId);
            }
          }
        });
      }

      // 3. 既存 plus_shifts
      final shiftDoc = await FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(_monthKey)
          .get();
      if (shiftDoc.exists) {
        _originalExists = true;
        _originalDays =
            Map<String, dynamic>.from(shiftDoc.data()?['days'] ?? {});
        _originalDays.forEach((dayKey, slots) {
          final day = int.tryParse(dayKey);
          if (day == null || slots is! List) return;
          for (final slot in slots) {
            if (slot is Map && slot['isWorking'] == false) {
              final staffId = slot['staffId'] as String?;
              if (staffId != null) {
                _offDays.putIfAbsent(day, () => <String>{}).add(staffId);
              }
            }
          }
        });
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
      // 新しい days マップを組み立てる（既存を基準に差分反映）
      final newDays = <String, dynamic>{};
      _originalDays.forEach((k, v) {
        if (v is List) {
          newDays[k] = v.map((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            return e;
          }).toList();
        } else {
          newDays[k] = v;
        }
      });

      // 対象月の全日をイテレート
      for (int day = 1; day <= _daysInMonth; day++) {
        final dayKey = day.toString();
        final offSet = _offDays[day] ?? <String>{};

        final existingSlots = (newDays[dayKey] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[];

        // A) 休み指定すべき staffId を isWorking:false で upsert
        for (final staffId in offSet) {
          final idx = existingSlots
              .indexWhere((s) => s['staffId'] == staffId);
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

      final docRef = FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(_monthKey);
      if (_originalExists) {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シフトを実予定に反映しました')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('シフト反映失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('反映に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDayEditPopup(int day) async {
    final currentOff = Set<String>.from(_offDays[day] ?? {});
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final localOff = Set<String>.from(currentOff);
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final date = DateTime(widget.targetMonth.year,
                widget.targetMonth.month, day);
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
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if ((_requestedStrongOffDays[staff['id']] ?? {})
                                .contains(day))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade800,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '絶対休',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if ((_requestedOffDays[staff['id']] ?? {})
                                .contains(day))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '希望',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade900,
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
          _offDays.remove(day);
        } else {
          _offDays[day] = result;
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
        .where((s) => _requestedOffDays.containsKey(s['id']))
        .length;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ヘッダ
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_calendar,
                            color: Colors.orange, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.targetMonth.year}年${widget.targetMonth.month}月 シフト決定',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '希望提出: $submittedCount/${_plusStaffs.length}人',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSub),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.download_done, size: 18),
                          label: const Text('シフトに反映'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
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
                    ),
                  ),
                  // 説明
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 14,
                              color: Colors.orange.shade800),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              '日付をタップして休みスタッフを決定。オレンジの「希望」バッジ付きはスタッフから提出された希望です。',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                        _legendSwatch(Colors.red.shade400, '休み確定'),
                        const SizedBox(width: 12),
                        _legendSwatch(
                            Colors.orange.shade100, '希望（未確定）',
                            borderColor: Colors.orange.shade400),
                        const SizedBox(width: 12),
                        _legendSwatch(Colors.red.shade800, '絶対休'),
                        const Spacer(),
                        Text(
                          '※「シフトに反映」を押すと実シフトに書き込まれます',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600),
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
    final firstDay =
        DateTime(widget.targetMonth.year, widget.targetMonth.month, 1);
    // weekday: 月=1 → 列0, 火=2 → 1, ..., 土=6 → 5, 日=7 → 6
    final startOffset = (firstDay.weekday - 1) % 7;

    const labels7 = ['月', '火', '水', '木', '金', '土', '日'];
    final totalCells = startOffset + _daysInMonth;
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
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSun
                        ? Colors.red.shade50
                        : Colors.grey.shade100,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade300),
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                      left: i == 0
                          ? BorderSide(color: Colors.grey.shade300)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    labels7[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSun
                          ? Colors.red
                          : isSat
                              ? Colors.blue
                              : Colors.black87,
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
                      final day = cellIndex - startOffset + 1;
                      final isInMonth =
                          day >= 1 && day <= _daysInMonth;
                      return Expanded(
                        child: _buildDayCell(
                          day: isInMonth ? day : null,
                          columnIndex: c,
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

  Widget _buildDayCell({required int? day, required int columnIndex}) {
    final isSun = columnIndex == 6;
    final isSat = columnIndex == 5;
    final numberColor = isSun
        ? Colors.red
        : isSat
            ? Colors.blue
            : Colors.black87;

    // 日曜は定休表示
    if (isSun) {
      return Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (day != null)
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade300,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              '定休',
              style: TextStyle(
                fontSize: 9,
                color: Colors.red.shade300,
              ),
            ),
          ],
        ),
      );
    }

    if (day == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
        ),
      );
    }

    final offStaffIds = _offDays[day] ?? <String>{};
    final chips = <Widget>[];
    for (final staffId in offStaffIds) {
      final staff = _plusStaffs.firstWhere(
        (s) => s['id'] == staffId,
        orElse: () => <String, dynamic>{'name': '?'},
      );
      final isRequested =
          (_requestedOffDays[staffId] ?? {}).contains(day);
      final isStrong =
          (_requestedStrongOffDays[staffId] ?? {}).contains(day);
      final Color chipBg;
      final Color chipFg;
      Border? chipBorder;
      if (isStrong) {
        chipBg = Colors.red.shade800;
        chipFg = Colors.white;
      } else if (isRequested) {
        chipBg = Colors.orange.shade100;
        chipFg = Colors.orange.shade900;
        chipBorder = Border.all(color: Colors.orange.shade400);
      } else {
        chipBg = Colors.red.shade400;
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
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Text(
                staff['name'] as String,
                style: TextStyle(
                  fontSize: 10,
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
      onTap: () => _showDayEditPopup(day),
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12,
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
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${offStaffIds.length}',
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.bold),
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
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
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
