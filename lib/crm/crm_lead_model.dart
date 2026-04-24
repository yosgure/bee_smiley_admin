import 'package:cloud_firestore/cloud_firestore.dart';

/// CRM リードの読み取り専用ラッパー。
/// 既存 `crm_leads` コレクションの Map をそのまま受け取り、型付きで参照できるようにする。
/// Phase 1 ではスキーマ変更をせず、読み取り側のヘルパーのみを提供する。
class CrmLead {
  final String id;
  final DocumentReference<Map<String, dynamic>>? ref;
  final Map<String, dynamic> raw;

  CrmLead({required this.id, required this.raw, this.ref});

  factory CrmLead.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      CrmLead(id: doc.id, raw: doc.data(), ref: doc.reference);

  factory CrmLead.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) =>
      CrmLead(id: snap.id, raw: snap.data() ?? const {}, ref: snap.reference);

  // 児童
  String get childLastName => (raw['childLastName'] as String?) ?? '';
  String get childFirstName => (raw['childFirstName'] as String?) ?? '';
  String get childFullName => '$childLastName $childFirstName'.trim();
  String get childKana => (raw['childKana'] as String?) ?? '';
  DateTime? get childBirthDate =>
      (raw['childBirthDate'] as Timestamp?)?.toDate();

  int? get childAge {
    final bd = childBirthDate;
    if (bd == null) return null;
    final now = DateTime.now();
    var age = now.year - bd.year;
    if (now.month < bd.month || (now.month == bd.month && now.day < bd.day)) {
      age--;
    }
    return age;
  }

  // 保護者
  String get parentLastName => (raw['parentLastName'] as String?) ?? '';
  String get parentFirstName => (raw['parentFirstName'] as String?) ?? '';
  String get parentFullName => '$parentLastName $parentFirstName'.trim();
  String get parentTel => (raw['parentTel'] as String?) ?? '';
  String get parentEmail => (raw['parentEmail'] as String?) ?? '';
  String get parentLine => (raw['parentLine'] as String?) ?? '';
  String get preferredChannel =>
      (raw['preferredChannel'] as String?) ?? 'tel';

  // 案件
  String get stage => (raw['stage'] as String?) ?? 'considering';
  String get confidence => (raw['confidence'] as String?) ?? 'B';
  String get source => (raw['source'] as String?) ?? 'other';
  String get sourceDetail => (raw['sourceDetail'] as String?) ?? '';

  // 次の一手
  DateTime? get nextActionAt =>
      (raw['nextActionAt'] as Timestamp?)?.toDate();
  String get nextActionNote => (raw['nextActionNote'] as String?) ?? '';
  /// 次の一手の種別（Phase 1 新規追加。既存データは null）
  String? get nextActionType => raw['nextActionType'] as String?;
  bool get hasNextAction => nextActionAt != null || nextActionNote.isNotEmpty;

  // ライフサイクル
  DateTime? get inquiredAt => (raw['inquiredAt'] as Timestamp?)?.toDate();
  DateTime? get firstContactedAt =>
      (raw['firstContactedAt'] as Timestamp?)?.toDate();
  DateTime? get trialAt => (raw['trialAt'] as Timestamp?)?.toDate();
  DateTime? get enrolledAt => (raw['enrolledAt'] as Timestamp?)?.toDate();
  DateTime? get lostAt => (raw['lostAt'] as Timestamp?)?.toDate();
  DateTime? get withdrawnAt => (raw['withdrawnAt'] as Timestamp?)?.toDate();

  /// 既存フィールド名は `lastActivityAt`。指示書の `lastContactAt` 相当。
  DateTime? get lastContactAt =>
      (raw['lastActivityAt'] as Timestamp?)?.toDate();

  // 担当者（Phase 1 新規、既存データは null）
  String? get assigneeUid => raw['assigneeUid'] as String?;
  String? get assigneeName => raw['assigneeName'] as String?;

  // 失注・退会
  String? get lossReason => raw['lossReason'] as String?;
  String get lossDetail => (raw['lossDetail'] as String?) ?? '';
  String? get withdrawReason => raw['withdrawReason'] as String?;

  // メモ
  String get memo => (raw['memo'] as String?) ?? '';

  // 対応履歴（配列フィールド。Phase 1 では subcollection 化しない）
  List<CrmActivity> get activities {
    final list = (raw['activities'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => CrmActivity.fromMap(Map<String, dynamic>.from(m)))
        .toList()
      ..sort((a, b) {
        final ta = a.at;
        final tb = b.at;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
  }

  /// 対応終了扱いのステージか（ホームの督促対象外）
  bool get isClosed =>
      stage == 'won' || stage == 'lost' || stage == 'withdrawn';

  /// 最終接触からの経過時間。`lastContactAt` が null なら inquiredAt を起点とする。
  Duration? sinceLastContact([DateTime? now]) {
    final base = lastContactAt ?? inquiredAt;
    if (base == null) return null;
    return (now ?? DateTime.now()).difference(base);
  }
}

/// 対応履歴の1エントリ。既存 `activities` 配列要素のラッパー。
/// Phase 1 では `outcome` / `feeling` を nullable で追加受け入れ。
class CrmActivity {
  final String? id;
  final String type; // 'tel' | 'email' | 'line' | 'visit' | 'memo' | 'task'
  final String body;
  final DateTime? at;
  final String? authorId;
  final String? authorName;

  /// 対応結果（Phase 1 新規）: 'reached' | 'not_reached' | 'completed' | 'pending'
  final String? outcome;

  /// 感触（Phase 1 新規）: 'positive' | 'considering' | 'negative'
  final String? feeling;

  /// 次の一手プリセットID（監査用、Phase 1 新規）
  final String? nextPresetId;

  const CrmActivity({
    this.id,
    required this.type,
    required this.body,
    this.at,
    this.authorId,
    this.authorName,
    this.outcome,
    this.feeling,
    this.nextPresetId,
  });

  factory CrmActivity.fromMap(Map<String, dynamic> m) => CrmActivity(
        id: m['id'] as String?,
        type: (m['type'] as String?) ?? 'memo',
        body: (m['body'] as String?) ?? '',
        at: (m['at'] as Timestamp?)?.toDate(),
        authorId: m['authorId'] as String?,
        authorName: m['authorName'] as String?,
        outcome: m['outcome'] as String?,
        feeling: m['feeling'] as String?,
        nextPresetId: m['nextPresetId'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'type': type,
        'body': body,
        if (at != null) 'at': Timestamp.fromDate(at!),
        if (authorId != null) 'authorId': authorId,
        if (authorName != null) 'authorName': authorName,
        if (outcome != null) 'outcome': outcome,
        if (feeling != null) 'feeling': feeling,
        if (nextPresetId != null) 'nextPresetId': nextPresetId,
      };
}
