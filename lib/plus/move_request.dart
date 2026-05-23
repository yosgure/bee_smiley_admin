// 移動希望（structured）のモデル。
//
// Firestore 上の保存形式（plus_student_notes/{name}.moveRequest）:
// {
//   status: 'active' | 'fulfilled' | 'cancelled',
//   candidates: [ { weekday: 1-6, startTime: 'HH:mm', priority: int } ],
//   expiresAt: Timestamp?,
//   note: string,
//   updatedAt: Timestamp?,
// }
//
// 旧形式（自由文 String）も読めるよう fromRaw() で後方互換を担保する。
import 'package:cloud_firestore/cloud_firestore.dart';

class MoveRequestCandidate {
  /// 希望曜日リスト（1=月..6=土）。空配列 = どの曜日でもOK
  final List<int> weekdays;

  /// 希望時間リスト ('HH:mm')。空配列 = どの時間でもOK
  final List<String> startTimes;

  /// 優先順位（1=第一希望）
  final int priority;

  const MoveRequestCandidate({
    this.weekdays = const [],
    this.startTimes = const [],
    this.priority = 1,
  });

  Map<String, dynamic> toMap() => {
        'weekdays': weekdays,
        'startTimes': startTimes,
        'priority': priority,
      };

  /// 旧形式（weekday/startTime 単数）も読める。
  /// - 旧: { weekday: 3, startTime: '15:30', priority: 1 }
  /// - 新: { weekdays: [3,5], startTimes: ['15:30'], priority: 1 }
  static MoveRequestCandidate? fromMap(dynamic raw) {
    if (raw is! Map) return null;

    // weekdays（複数 / 単数互換）
    final weekdays = <int>[];
    final wdsRaw = raw['weekdays'];
    if (wdsRaw is List) {
      for (final v in wdsRaw) {
        if (v is int && v >= 1 && v <= 6) weekdays.add(v);
      }
    } else if (raw['weekday'] is int) {
      final wd = raw['weekday'] as int;
      if (wd >= 1 && wd <= 6) weekdays.add(wd);
    }

    // startTimes（複数 / 単数互換）
    final startTimes = <String>[];
    final stsRaw = raw['startTimes'];
    if (stsRaw is List) {
      for (final v in stsRaw) {
        if (v is String && v.isNotEmpty) startTimes.add(v);
      }
    } else if (raw['startTime'] is String &&
        (raw['startTime'] as String).isNotEmpty) {
      startTimes.add(raw['startTime'] as String);
    }

    // 完全に空の候補（旧形式パース失敗）は捨てる
    if (weekdays.isEmpty && startTimes.isEmpty) return null;

    return MoveRequestCandidate(
      weekdays: weekdays,
      startTimes: startTimes,
      priority: raw['priority'] is int ? raw['priority'] as int : 1,
    );
  }

  static const _weekdayLabels = ['', '月', '火', '水', '木', '金', '土'];

  /// 曜日ラベル（複数 → 連結、空 → 「どの曜日でも」）
  String get weekdayLabel {
    if (weekdays.isEmpty) return 'どの曜日でも';
    final sorted = [...weekdays]..sort();
    return sorted.map((w) => _weekdayLabels[w]).join('');
  }

  /// 時間ラベル（複数 → スラッシュ区切り、空 → 「どの時間でも」）
  String get startTimeLabel {
    if (startTimes.isEmpty) return 'どの時間でも';
    return startTimes.join('/');
  }

  /// 表示用ラベル: 「月金 × 15:30」「15:30（どの曜日でも）」など
  String get displayLabel {
    if (weekdays.isEmpty && startTimes.isEmpty) return 'どの枠でも';
    if (weekdays.isEmpty) return '$startTimeLabel（曜日問わず）';
    if (startTimes.isEmpty) return '$weekdayLabel（時間問わず）';
    return '$weekdayLabel $startTimeLabel';
  }

  /// 指定された曜日・時間がこの候補にマッチするか
  /// （将来の欠スロット突合用 — 空配列は「どれでも」扱い）
  bool matches({required int weekday, required String startTime}) {
    final wdOk = weekdays.isEmpty || weekdays.contains(weekday);
    final stOk = startTimes.isEmpty || startTimes.contains(startTime);
    return wdOk && stOk;
  }
}

class MoveRequest {
  final String status; // 'active' | 'fulfilled' | 'cancelled'
  final List<MoveRequestCandidate> candidates;
  final DateTime? expiresAt;
  final String note;

  const MoveRequest({
    this.status = 'active',
    this.candidates = const [],
    this.expiresAt,
    this.note = '',
  });

  /// 空の移動希望
  static const empty = MoveRequest();

  /// 何らかの内容を持っているか（候補 or メモ）
  bool get hasContent => candidates.isNotEmpty || note.isNotEmpty;

  /// 期限切れか（expiresAt がセットされていて今日より前）
  bool get isExpired {
    final e = expiresAt;
    if (e == null) return false;
    final today = DateTime.now();
    final endOfDay = DateTime(e.year, e.month, e.day, 23, 59, 59);
    return endOfDay.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// 表示対象か（コンテンツがあり、期限切れでなく、active のみ）
  bool get isVisible => hasContent && !isExpired && status == 'active';

  /// 優先度順にソートした候補
  List<MoveRequestCandidate> get sortedCandidates {
    final list = [...candidates];
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  Map<String, dynamic> toMap() => {
        'status': status,
        'candidates': candidates.map((c) => c.toMap()).toList(),
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
        'note': note,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Firestore から読み込み。新旧両方の形式に対応:
  /// - String（レガシー） → note として読み込み
  /// - Map（新形式） → 構造化パース
  /// - null/その他 → empty
  static MoveRequest fromRaw(dynamic raw) {
    if (raw == null) return empty;
    if (raw is String) {
      return MoveRequest(note: raw, status: 'active');
    }
    if (raw is Map) {
      final candidatesRaw = raw['candidates'];
      final candidates = <MoveRequestCandidate>[];
      if (candidatesRaw is List) {
        for (final c in candidatesRaw) {
          final parsed = MoveRequestCandidate.fromMap(c);
          if (parsed != null) candidates.add(parsed);
        }
      }
      DateTime? expiresAt;
      final ex = raw['expiresAt'];
      if (ex is Timestamp) {
        expiresAt = ex.toDate();
      } else if (ex is DateTime) {
        expiresAt = ex;
      }
      return MoveRequest(
        status: (raw['status'] as String?) ?? 'active',
        candidates: candidates,
        expiresAt: expiresAt,
        note: (raw['note'] as String?) ?? '',
      );
    }
    return empty;
  }

  MoveRequest copyWith({
    String? status,
    List<MoveRequestCandidate>? candidates,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    String? note,
  }) {
    return MoveRequest(
      status: status ?? this.status,
      candidates: candidates ?? this.candidates,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      note: note ?? this.note,
    );
  }
}
