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
  final int weekday; // 1=月, 2=火, ..., 6=土
  final String startTime; // 'HH:mm'
  final int priority; // 1=第一希望

  const MoveRequestCandidate({
    required this.weekday,
    required this.startTime,
    this.priority = 1,
  });

  Map<String, dynamic> toMap() => {
        'weekday': weekday,
        'startTime': startTime,
        'priority': priority,
      };

  static MoveRequestCandidate? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final wd = raw['weekday'];
    final st = raw['startTime'];
    if (wd is! int || st is! String || st.isEmpty) return null;
    return MoveRequestCandidate(
      weekday: wd,
      startTime: st,
      priority: raw['priority'] is int ? raw['priority'] as int : 1,
    );
  }

  static const _weekdayLabels = ['', '月', '火', '水', '木', '金', '土'];

  String get weekdayLabel =>
      (weekday >= 1 && weekday <= 6) ? _weekdayLabels[weekday] : '?';

  /// 表示用ラベル: 「水 9:30」
  String get displayLabel => '$weekdayLabel $startTime';
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
