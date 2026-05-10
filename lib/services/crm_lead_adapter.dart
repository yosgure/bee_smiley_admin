import 'package:cloud_firestore/cloud_firestore.dart';

/// CRMリードを plus_families.children[] から読み出すためのアダプタ。
///
/// 既存CRM画面は `crm_leads` 由来の `QueryDocumentSnapshot` を扱う前提で作られていたが、
/// データソースが plus_families に移行したため、この LeadView を介して
/// 「リードに見えるオブジェクト」として views に渡す。
///
/// LeadView の API は最低限 QueryDocumentSnapshot と互換:
///   - `.data()` → Map（リード形式にフラット化済）
///   - `.id` → 'familyId#childIndex'
///   - `.reference.update(...)`, `.reference.delete()` → plus_families.children[index] を更新/削除
class LeadView {
  final String familyDocId;
  final int childIndex;
  final Map<String, dynamic> _flatData;
  final DocumentReference<Map<String, dynamic>> _familyRef;

  LeadView({
    required this.familyDocId,
    required this.childIndex,
    required Map<String, dynamic> flatData,
    required DocumentReference<Map<String, dynamic>> familyRef,
  })  : _flatData = flatData,
        _familyRef = familyRef;

  String get id => '$familyDocId#$childIndex';
  Map<String, dynamic> data() => _flatData;
  DocumentReference<Map<String, dynamic>> get familyRef => _familyRef;
  LeadViewReference get reference => LeadViewReference(this);

  /// フラットなリード形式の更新を、children[childIndex] と family レベルに振り分けて適用する。
  ///
  /// 入力例: `{ 'childFirstName': 'たろう', 'parentTel': '090...', 'stage': 'won', 'memo': '...' }`
  ///   - `child*` プレフィックスや既知の児童キーは children[childIndex] へ
  ///   - `parent*` プレフィックスや住所など family レベルキーは family ドキュメント直下へ
  ///   - それ以外のCRM項目（stage / source / activities / 各種日付 etc）は children[childIndex] へ
  ///
  /// FieldValue sentinel は配列内では直接使えないため、トランザクション内で展開:
  ///   - serverTimestamp → Timestamp.now()
  ///   - delete → キー除去
  ///   - arrayUnion / arrayRemove → 既存配列を読んで新しい配列を計算
  Future<void> update(Map<String, dynamic> updates) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_familyRef);
      final famData = Map<String, dynamic>.from(snap.data() ?? {});
      final children = List<Map<String, dynamic>>.from(
          (famData['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      if (childIndex < 0 || childIndex >= children.length) return;

      final familyUpdates = <String, dynamic>{};
      final child = children[childIndex];

      updates.forEach((flatKey, raw) {
        final mapping = _flatKeyMapping[flatKey];
        // mapping が null なら children[childIndex] にそのキーで書き込む
        final isFamily = mapping != null && mapping.target == _Target.family;
        final actualKey = mapping?.actualKey ?? flatKey;
        final target = isFamily ? familyUpdates : child;

        // 「未入力フィールドが既存値を上書きしないようにする」セーフガード:
        // 空文字列を書き込もうとして既存値が非空ならスキップ（保護者氏名や電話などの誤クリア防止）。
        if (raw is String && raw.isEmpty) {
          final existing = isFamily ? famData[actualKey] : child[actualKey];
          if (existing is String && existing.isNotEmpty) {
            return; // skip overwrite
          }
        }

        // birthDate は families スキーマでは 'YYYY/MM/DD' 文字列。Timestamp で来たら変換。
        if (actualKey == 'birthDate' && raw is Timestamp) {
          final dt = raw.toDate();
          final s =
              '${dt.year.toString().padLeft(4, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
          target[actualKey] = s;
          return;
        }

        if (raw is FieldValue) {
          final s = raw.toString();
          if (s.contains('delete')) {
            target.remove(actualKey);
          } else if (s.contains('serverTimestamp')) {
            target[actualKey] = Timestamp.now();
          } else if (s.contains('arrayUnion')) {
            // FieldValue.arrayUnion の中身は取り出せないので、呼び出し側で
            // 配列形式で渡してもらう前提とする。フォールバックでそのまま代入。
            target[actualKey] = raw;
          } else if (s.contains('arrayRemove')) {
            target[actualKey] = raw;
          } else {
            target[actualKey] = raw;
          }
        } else {
          target[actualKey] = raw;
        }
      });

      children[childIndex] = child;
      // 一度に書き込み（トランザクション内）
      final write = <String, dynamic>{
        'children': children,
        ...familyUpdates,
      };
      tx.update(_familyRef, write);
    });
  }

  Future<void> delete() async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_familyRef);
      final children = List<Map<String, dynamic>>.from(
          (snap.data()?['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      if (childIndex < 0 || childIndex >= children.length) return;
      children.removeAt(childIndex);
      if (children.isEmpty) {
        tx.delete(_familyRef);
      } else {
        tx.update(_familyRef, {'children': children});
      }
    });
  }

  /// このリードを既読化する。children[childIndex].notifyUnread = false にし、
  /// 同 family の他 child にも未読が無ければ family.notifyUnread も false に更新（ロールアップ）。
  /// すでに既読の場合は何もしない（書き込み回避）。
  Future<void> markRead() async {
    if (_flatData['notifyUnread'] != true) return;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_familyRef);
      final data = snap.data() ?? <String, dynamic>{};
      final children = List<Map<String, dynamic>>.from(
          (data['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      if (childIndex < 0 || childIndex >= children.length) return;
      final child = children[childIndex];
      if (child['notifyUnread'] != true) return; // 既に既読
      child['notifyUnread'] = false;
      child.remove('notifyUnreadAt');
      children[childIndex] = child;

      final anyUnread = children.any((c) => c['notifyUnread'] == true);
      final update = <String, dynamic>{
        'children': children,
        'notifyUnread': anyUnread,
      };
      if (!anyUnread) {
        update['notifyUnreadAt'] = FieldValue.delete();
      }
      tx.update(_familyRef, update);
    });
  }
}

/// `LeadView.reference.update(...)` / `.delete()` のためのシム。
class LeadViewReference {
  final LeadView _lv;
  LeadViewReference(this._lv);
  Future<void> update(Map<String, dynamic> data) => _lv.update(data);
  Future<void> delete() => _lv.delete();
  Future<void> markRead() => _lv.markRead();
  String get id => _lv.id;
}

enum _Target { child, family }

class _KeyMap {
  final _Target target;
  final String actualKey;
  const _KeyMap(this.target, this.actualKey);
}

/// crm_leads 由来のフラットキー → plus_families 内のキー位置マッピング。
/// ここに無いキーは全て children[childIndex] にそのキー名で書き込まれる。
const Map<String, _KeyMap> _flatKeyMapping = {
  'childLastName': _KeyMap(_Target.child, 'lastName'),
  'childFirstName': _KeyMap(_Target.child, 'firstName'),
  'childKana': _KeyMap(_Target.child, 'firstNameKana'),
  'childGender': _KeyMap(_Target.child, 'gender'),
  'childBirthDate': _KeyMap(_Target.child, 'birthDate'),
  'parentLastName': _KeyMap(_Target.family, 'lastName'),
  'parentFirstName': _KeyMap(_Target.family, 'firstName'),
  'parentKana': _KeyMap(_Target.family, 'lastNameKana'),
  'parentTel': _KeyMap(_Target.family, 'phone'),
  'parentEmail': _KeyMap(_Target.family, 'email'),
  'parentLine': _KeyMap(_Target.family, 'lineId'),
  'address': _KeyMap(_Target.family, 'address'),
  // 住所（HUG連携用に分割）
  'postalCode': _KeyMap(_Target.family, 'postalCode'),
  'prefecture': _KeyMap(_Target.family, 'prefecture'),
  'city': _KeyMap(_Target.family, 'city'),
  // family レベルの更新メタ
  'updatedAt': _KeyMap(_Target.family, 'updatedAt'),
  'updatedBy': _KeyMap(_Target.family, 'updatedBy'),
  'createdAt': _KeyMap(_Target.family, 'createdAt'),
  'createdBy': _KeyMap(_Target.family, 'createdBy'),
};

/// 与えられた値リストから最初の非空文字列を返す。?? 演算子は空文字列で fall through
/// しないため、空文字列を「未設定」とみなす場合に使う。
String _firstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    if (v == null) continue;
    final s = v.toString();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// 'YYYY/MM/DD' 形式の文字列を Timestamp に変換。families は文字列スキーマ、
/// crm_leads は Timestamp スキーマだったため、フラット化時に変換が必要。
Timestamp? _birthDateToTimestamp(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v;
  if (v is DateTime) return Timestamp.fromDate(v);
  if (v is String && v.isNotEmpty) {
    final m = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch(v.trim());
    if (m != null) {
      final y = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final d = int.parse(m.group(3)!);
      return Timestamp.fromDate(DateTime(y, mo, d));
    }
  }
  return null;
}

/// plus_families.children[] を CRM互換のフラットマップに変換する。
/// 既存 crm_leads 形式と同じキーを返すので views は無改修で動く。
Map<String, dynamic> flattenChildToLeadShape(
    String familyId, Map<String, dynamic> family, Map<String, dynamic> child) {
  final flat = <String, dynamic>{
    // 児童
    'childLastName': child['lastName'] ?? '',
    'childFirstName': child['firstName'] ?? '',
    'childKana': _firstNonEmpty([child['firstNameKana'], child['kana']]),
    'childGender': child['gender'],
    'childBirthDate': _birthDateToTimestamp(child['birthDate']),
    // 保護者（family レベル）
    'parentLastName': family['lastName'] ?? '',
    'parentFirstName': family['firstName'] ?? '',
    'parentKana': family['lastNameKana'] ?? '',
    'parentTel': family['phone'] ?? family['tel'] ?? '',
    'parentEmail': family['email'] ?? '',
    'parentLine': family['lineId'] ?? '',
    'address': family['address'] ?? '',
    'postalCode': family['postalCode'] ?? '',
    'prefecture': family['prefecture'] ?? '',
    'city': family['city'] ?? '',
    // 児童側 HUG必須項目（recipientCertificate はネスト）
    'allergy': child['allergy'] ?? '',
    'recipientCertificate': child['recipientCertificate'],
    'hugChildId': child['hugChildId'],
    // 児童側に持つCRM項目
    'stage': child['stage'],
    'status': child['status'],
    'confidence': child['confidence'],
    'source': child['source'],
    'sourceDetail': child['sourceDetail'],
    // F2: Campaign 紐付け（任意）。null = 媒体（source）のみで管理。
    'sourceCampaignId': child['sourceCampaignId'],
    'preferredChannel': child['preferredChannel'],
    'preferredDays': child['preferredDays'],
    'preferredTimeSlots': child['preferredTimeSlots'],
    'preferredStart': child['preferredStart'],
    'kindergarten': child['kindergarten'],
    'permitStatus': child['permitStatus'],
    'mainConcern': child['mainConcern'],
    'likes': child['likes'],
    'dislikes': child['dislikes'],
    'trialNotes': child['trialNotes'],
    'inquiredAt': child['inquiredAt'],
    'firstContactedAt': child['firstContactedAt'],
    'trialAt': child['trialAt'],
    'trialActualDate': child['trialActualDate'],
    'enrolledAt': child['enrolledAt'],
    'lostAt': child['lostAt'],
    'withdrawnAt': child['withdrawnAt'],
    'lastActivityAt': child['lastActivityAt'],
    'nextActionAt': child['nextActionAt'],
    'nextActionNote': child['nextActionNote'],
    'lossReason': child['lossReason'],
    'lossDetail': child['lossDetail'],
    'reapproachOk': child['reapproachOk'],
    'withdrawReason': child['withdrawReason'],
    'withdrawDetail': child['withdrawDetail'],
    'memo': child['memo'],
    'activities': child['activities'] ?? <Map<String, dynamic>>[],
    // F_lead_detail_refactor v2: 進捗チェックリスト + 待ち状態
    // v4: enrollmentChecklist は読み取り互換のため残置、書き込みは checklistDates へ
    'enrollmentChecklist': child['enrollmentChecklist'],
    'checklistDates': child['checklistDates'],
    'checklistNotes': child['checklistNotes'],
    'createdAt': child['createdAt'] ?? family['createdAt'],
    'createdBy': child['createdBy'] ?? family['createdBy'],
    'updatedAt': child['updatedAt'] ?? family['updatedAt'],
    'updatedBy': child['updatedBy'] ?? family['updatedBy'],
    'sourceLeadId': child['sourceLeadId'],
    // 自分自身が family なので convertedFamilyId = familyId（互換のため）
    'convertedFamilyId': familyId,
    // フォーム自動取り込みの未読フラグ（リードカード NEW バッジ用）
    'notifyUnread': child['notifyUnread'] == true,
    'notifyUnreadAt': child['notifyUnreadAt'],
  };
  // pre-existing 入会児童で stage が無い場合は status から派生
  if (flat['stage'] == null) {
    flat['stage'] = _stageFromStatus(child['status']);
  }
  return flat;
}

String _stageFromStatus(dynamic status) {
  if (status == null) return 'won'; // 旧データの入会済み
  switch (status.toString()) {
    case '検討中':
      return 'considering';
    case '入会手続中':
      return 'onboarding';
    case '入会':
      return 'won';
    case '失注':
      return 'lost';
    case '退会':
      return 'withdrawn';
    default:
      return 'considering';
  }
}

/// plus_families コレクションを購読し、children[] をフラット化した LeadView 一覧を流す。
Stream<List<LeadView>> watchLeadsFromPlusFamilies() {
  return FirebaseFirestore.instance
      .collection('plus_families')
      .snapshots()
      .map((snap) {
    final leads = <LeadView>[];
    for (final famDoc in snap.docs) {
      final family = famDoc.data();
      final children = List<Map<String, dynamic>>.from(
          (family['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      for (var i = 0; i < children.length; i++) {
        leads.add(LeadView(
          familyDocId: famDoc.id,
          childIndex: i,
          flatData: flattenChildToLeadShape(famDoc.id, family, children[i]),
          familyRef: famDoc.reference,
        ));
      }
    }
    // inquiredAt 降順（既存 crm_leads ストリームと同じ並び）
    leads.sort((a, b) {
      final ta = a.data()['inquiredAt'];
      final tb = b.data()['inquiredAt'];
      DateTime? da;
      DateTime? db;
      if (ta is Timestamp) da = ta.toDate();
      if (tb is Timestamp) db = tb.toDate();
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return leads;
  });
}
