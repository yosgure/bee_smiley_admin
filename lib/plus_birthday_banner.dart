import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// プラス画面トップに表示する「近日の誕生日」バナー。
///
/// - デフォルトで今日から2週間先までの誕生日を対象
/// - 該当者がいなければ何も表示しない
/// - 1行サマリ表示（最短の1名のみ名前を出す）＋折りたたみ展開で全員表示
/// - 各生徒の「確認済み」状態は LocalStorage (SharedPreferences) に保存
/// - 展開状態も LocalStorage に保存
class PlusBirthdayBanner extends StatefulWidget {
  /// プラス在籍の生徒リスト。`name`, `birthDate` (YYYY/MM/DD) を参照する。
  final List<Map<String, dynamic>> students;

  /// 何日先まで表示するか
  final int daysAhead;

  const PlusBirthdayBanner({
    super.key,
    required this.students,
    this.daysAhead = 14,
  });

  @override
  State<PlusBirthdayBanner> createState() => _PlusBirthdayBannerState();
}

class _PlusBirthdayBannerState extends State<PlusBirthdayBanner> {
  static const _kExpandedKey = 'plus_birthday_banner_expanded';
  static const _kDismissedKeyPrefix = 'plus_birthday_dismissed:';

  bool _expanded = false;
  Set<String> _dismissed = {};
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _expanded = prefs.getBool(_kExpandedKey) ?? false;
      // 今日のキー接頭辞で始まる項目のみロード
      // (古いエントリは自然に無視されるが、アプリ起動時にクリーンアップ)
      final keys = prefs.getKeys();
      final today = DateTime.now();
      final todayKey = _ymd(today);
      _dismissed = keys
          .where((k) => k.startsWith(_kDismissedKeyPrefix))
          .where((k) {
            // 古い確認済みエントリを掃除: 誕生日日付が今日より前のものを削除
            final parts = k.substring(_kDismissedKeyPrefix.length).split('|');
            if (parts.length < 2) {
              prefs.remove(k);
              return false;
            }
            final dateStr = parts[0];
            if (dateStr.compareTo(todayKey) < 0) {
              prefs.remove(k);
              return false;
            }
            return true;
          })
          .map((k) => k.substring(_kDismissedKeyPrefix.length))
          .toSet();
      if (mounted) setState(() => _prefsLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _prefsLoaded = true);
    }
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _setExpanded(bool v) async {
    setState(() => _expanded = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kExpandedKey, v);
    } catch (_) {}
  }

  Future<void> _dismissEntry(String entryKey) async {
    setState(() => _dismissed.add(entryKey));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_kDismissedKeyPrefix$entryKey', true);
    } catch (_) {}
  }

  /// 近日の誕生日を集める。entryKey は "YYYY-MM-DD|生徒名" 形式。
  List<_BirthdayEntry> _computeUpcoming() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <_BirthdayEntry>[];
    for (final s in widget.students) {
      final birthStr = (s['birthDate'] as String?) ?? '';
      if (birthStr.isEmpty) continue;
      final parts = birthStr.split('/');
      if (parts.length != 3) continue;
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) {
        continue;
      }
      // 今年の誕生日を計算（2/29は非閏年では2/28扱い）
      DateTime nextBirthday;
      try {
        nextBirthday = DateTime(today.year, m, d);
      } catch (_) {
        nextBirthday = DateTime(today.year, m, 28);
      }
      // 月末丸め: 例えば閏年以外の2/29は2/28に
      if (nextBirthday.month != m) {
        nextBirthday = DateTime(today.year, m + 1, 0); // その月の末日
      }
      // 今日より前なら次の発生はない（範囲外）。
      // ただし 今日当日はまだ対象に入れる。
      if (nextBirthday.isBefore(today)) continue;
      final diffDays = nextBirthday.difference(today).inDays;
      if (diffDays > widget.daysAhead) continue;
      final name = (s['name'] as String?) ?? '';
      if (name.isEmpty) continue;
      result.add(_BirthdayEntry(
        name: name,
        date: nextBirthday,
        daysUntil: diffDays,
        entryKey: '${_ymd(nextBirthday)}|$name',
      ));
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) return const SizedBox.shrink();
    final all = _computeUpcoming();
    final visible =
        all.where((e) => !_dismissed.contains(e.entryKey)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final first = visible.first;
    final summary = first.daysUntil == 0
        ? '最短: ${first.name} 本日!'
        : '最短: ${first.name} あと${first.daysUntil}日';

    return Material(
      color: Colors.pink.shade50,
      child: InkWell(
        onTap: () => _setExpanded(!_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // サマリ行
              Row(
                children: [
                  const Text('🎂', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    '近日の誕生日 ${visible.length}名',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink.shade900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      summary,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.pink.shade900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _expanded ? '閉じる' : '詳細',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.pink.shade700,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.pink.shade700,
                  ),
                ],
              ),
              // 展開時の一覧
              if (_expanded) ...[
                SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.cardBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.pink.shade200),
                  ),
                  child: Column(
                    children: [
                      for (final e in visible) _buildEntryRow(e),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryRow(_BirthdayEntry e) {
    final dateLabel = '${e.date.month}/${e.date.day}';
    final daysLabel =
        e.daysUntil == 0 ? '本日!' : 'あと${e.daysUntil}日';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              dateLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.pink.shade800,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              daysLabel,
              style: TextStyle(
                fontSize: 11,
                color: e.daysUntil == 0
                    ? Colors.pink.shade700
                    : context.colors.textSecondary,
                fontWeight: e.daysUntil == 0
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.name,
              style: TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colors.pink.shade700,
            ),
            onPressed: () => _dismissEntry(e.entryKey),
            child: const Text('確認済み', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _BirthdayEntry {
  final String name;
  final DateTime date;
  final int daysUntil;
  final String entryKey;

  _BirthdayEntry({
    required this.name,
    required this.date,
    required this.daysUntil,
    required this.entryKey,
  });
}
