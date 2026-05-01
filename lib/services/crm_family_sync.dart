import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// families.children[].birthDate は 'YYYY/MM/DD' 文字列スキーマ。
/// crm_leads は Timestamp で保存されているため、変換が必要。
String? _normalizeBirthDate(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  if (v is Timestamp) return DateFormat('yyyy/MM/dd').format(v.toDate());
  if (v is DateTime) return DateFormat('yyyy/MM/dd').format(v);
  return null;
}

/// CRMリード（crm_leads）の保存内容を families.children[] に upsert するサービス。
///
/// CRM一体化の方針:
/// - crm_leads はトランジション期間の互換ストレージ
/// - families.children[] が真実の源
/// - リード保存時、入会処理時に families 側へ即時反映
///
/// 冪等: 同じ leadId / leadData で再実行しても重複や破壊は起こらない。
class CrmFamilySync {
  static String _stageToStatus(String stage) {
    switch (stage) {
      case 'considering':
        return '検討中';
      case 'onboarding':
        return '入会手続中';
      case 'won':
        return '入会';
      case 'lost':
        return '失注';
      case 'withdrawn':
        return '退会';
      default:
        return '検討中';
    }
  }

  static Map<String, dynamic> _leadToChildFields(
      String leadId, Map<String, dynamic> lead) {
    final fields = <String, dynamic>{
      'firstName': (lead['childFirstName'] ?? '').toString(),
      'lastName': (lead['childLastName'] ?? '').toString(),
      'firstNameKana': (lead['childKana'] ?? '').toString(),
      'gender': lead['childGender'],
      'birthDate': _normalizeBirthDate(lead['childBirthDate']),
      'kindergarten': lead['kindergarten'],
      'mainConcern': lead['mainConcern'],
      'likes': lead['likes'],
      'dislikes': lead['dislikes'],
      'status': _stageToStatus((lead['stage'] ?? 'considering').toString()),
      // CRM項目
      'stage': lead['stage'],
      'confidence': lead['confidence'],
      'source': lead['source'],
      'sourceDetail': lead['sourceDetail'],
      'preferredChannel': lead['preferredChannel'],
      'preferredDays': lead['preferredDays'],
      'preferredTimeSlots': lead['preferredTimeSlots'],
      'preferredStart': lead['preferredStart'],
      'permitStatus': lead['permitStatus'],
      'trialNotes': lead['trialNotes'],
      'inquiredAt': lead['inquiredAt'],
      'firstContactedAt': lead['firstContactedAt'],
      'trialAt': lead['trialAt'],
      'enrolledAt': lead['enrolledAt'],
      'lostAt': lead['lostAt'],
      'withdrawnAt': lead['withdrawnAt'],
      'lastActivityAt': lead['lastActivityAt'],
      'lossReason': lead['lossReason'],
      'lossDetail': lead['lossDetail'],
      'reapproachOk': lead['reapproachOk'],
      'withdrawReason': lead['withdrawReason'],
      'withdrawDetail': lead['withdrawDetail'],
      'memo': lead['memo'],
      'sourceLeadId': leadId,
    };
    fields.removeWhere((k, v) => v == null);
    return fields;
  }

  static bool _familyMatchesLead(
      Map<String, dynamic> fam, Map<String, dynamic> lead) {
    final famTel = (fam['phone'] ?? fam['tel'] ?? '').toString().trim();
    final famEmail = (fam['email'] ?? '').toString().trim();
    final leadTel = (lead['parentTel'] ?? '').toString().trim();
    final leadEmail = (lead['parentEmail'] ?? '').toString().trim();
    if (leadTel.isNotEmpty && famTel == leadTel) return true;
    if (leadEmail.isNotEmpty && famEmail == leadEmail) return true;
    final famPName =
        '${(fam['lastName'] ?? '').toString().trim()}${(fam['firstName'] ?? '').toString().trim()}';
    final leadPName =
        '${(lead['parentLastName'] ?? '').toString().trim()}${(lead['parentFirstName'] ?? '').toString().trim()}';
    if (famPName.isNotEmpty && famPName == leadPName) return true;
    return false;
  }

  static int _findChildIndex(
      List<Map<String, dynamic>> children, String leadId, Map<String, dynamic> lead) {
    // 1. sourceLeadId 完全一致を最優先
    for (var i = 0; i < children.length; i++) {
      if (children[i]['sourceLeadId'] == leadId) return i;
    }
    // 2. 児童名一致
    final lFirst = (lead['childFirstName'] ?? '').toString().trim();
    final lLast = (lead['childLastName'] ?? '').toString().trim();
    if (lFirst.isEmpty) return -1;
    for (var i = 0; i < children.length; i++) {
      final cFirst = (children[i]['firstName'] ?? '').toString().trim();
      final cLast = (children[i]['lastName'] ?? '').toString().trim();
      if (cFirst != lFirst) continue;
      if (cLast.isNotEmpty && lLast.isNotEmpty && cLast != lLast) continue;
      return i;
    }
    return -1;
  }

  /// リードを families に upsert。convertedFamilyId が呼び出し側で既知ならそれを優先。
  /// 戻り値: 対応する family のドキュメントID。
  static Future<String> upsertLead({
    required String leadId,
    required Map<String, dynamic> leadData,
    String? convertedFamilyId,
  }) async {
    final fs = FirebaseFirestore.instance;

    // ターゲットfamily特定
    DocumentReference<Map<String, dynamic>>? targetRef;
    Map<String, dynamic>? targetData;

    if (convertedFamilyId != null && convertedFamilyId.isNotEmpty) {
      final snap = await fs.collection('families').doc(convertedFamilyId).get();
      if (snap.exists) {
        targetRef = snap.reference;
        targetData = snap.data();
      }
    }

    if (targetRef == null) {
      // 親電話/メール/氏名で照合（O(N) but families <= 数百件で十分）
      final famSnap = await fs.collection('families').get();
      for (final d in famSnap.docs) {
        final data = d.data();
        // 既に sourceLeadId が一致する child を持つfamilyを優先
        final children = (data['children'] as List? ?? []);
        final hasLead =
            children.any((c) => (c as Map)['sourceLeadId'] == leadId);
        if (hasLead) {
          targetRef = d.reference;
          targetData = data;
          break;
        }
      }
      if (targetRef == null) {
        for (final d in famSnap.docs) {
          if (_familyMatchesLead(d.data(), leadData)) {
            targetRef = d.reference;
            targetData = d.data();
            break;
          }
        }
      }
    }

    final childFields = _leadToChildFields(leadId, leadData);

    if (targetRef != null && targetData != null) {
      final children = List<Map<String, dynamic>>.from(
          (targetData['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      final idx = _findChildIndex(children, leadId, leadData);
      if (idx >= 0) {
        // 既存childを上書き更新（hugChildIdなどfamily側で持つ値は保持）
        final existing = children[idx];
        final preserved = <String, dynamic>{
          if (existing['hugChildId'] != null) 'hugChildId': existing['hugChildId'],
          if (existing['classrooms'] != null) 'classrooms': existing['classrooms'],
          if (existing['course'] != null) 'course': existing['course'],
          if (existing['allergy'] != null) 'allergy': existing['allergy'],
          if (existing['profileUrl'] != null) 'profileUrl': existing['profileUrl'],
          if (existing['meetingUrls'] != null) 'meetingUrls': existing['meetingUrls'],
          if (existing['activities'] != null) 'activities': existing['activities'],
        };
        children[idx] = {...childFields, ...preserved};
      } else {
        children.add({
          ...childFields,
          'classrooms': ['ビースマイリープラス湘南藤沢'],
        });
      }
      await targetRef.update({'children': children});
      return targetRef.id;
    } else {
      // 新規family作成
      final familyData = <String, dynamic>{
        'uid': '',
        'lastName': leadData['parentLastName'] ?? '',
        'firstName': leadData['parentFirstName'] ?? '',
        'lastNameKana': leadData['parentKana'] ?? '',
        'firstNameKana': '',
        'phone': leadData['parentTel'] ?? '',
        'email': leadData['parentEmail'] ?? '',
        'address': leadData['address'] ?? '',
        'lineId': leadData['parentLine'] ?? '',
        'children': [
          {
            ...childFields,
            'classrooms': ['ビースマイリープラス湘南藤沢'],
          },
        ],
        'sourceLeadId': leadId,
        'createdAt': leadData['createdAt'] ?? FieldValue.serverTimestamp(),
        'createdBy': leadData['createdBy'] ?? '',
      };
      final ref = await fs.collection('families').add(familyData);
      return ref.id;
    }
  }

  /// 入会処理: 対応する family child の status を「入会」に更新する。
  /// 新規family作成は行わない（既に upsertLead 経由で families に存在する前提）。
  /// 万一 family が無ければ upsertLead を呼んで作成する。
  static Future<String> markAsEnrolled({
    required String leadId,
    required Map<String, dynamic> leadData,
    String? convertedFamilyId,
    DateTime? enrolledAt,
  }) async {
    // upsertLead は status='入会' を leadData.stage='won' から自動派生する
    final updatedLead = Map<String, dynamic>.from(leadData);
    updatedLead['stage'] = 'won';
    if (enrolledAt != null) {
      updatedLead['enrolledAt'] = Timestamp.fromDate(enrolledAt);
    }
    return upsertLead(
      leadId: leadId,
      leadData: updatedLead,
      convertedFamilyId: convertedFamilyId,
    );
  }
}
