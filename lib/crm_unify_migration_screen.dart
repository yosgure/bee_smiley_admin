import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

String? _normalizeBirthDate(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  if (v is Timestamp) return DateFormat('yyyy/MM/dd').format(v.toDate());
  if (v is DateTime) return DateFormat('yyyy/MM/dd').format(v);
  return null;
}

/// CRM一体化マイグレーション画面（P1: 一回限り実行用）
///
/// 目的:
/// - 既存 families.children[] に status='入会' を後付け
/// - hug_settings/child_mapping を children[].hugChildId に展開コピー（元データは残す）
/// - crm_leads を families に upsert（電話/メールで照合、未一致は新規作成）
///
/// 冪等: 何度実行してもデータ重複は発生しない（status既設定はスキップ、児童名一致でmerge）。
/// 既存IDは破壊しない: families/loginId/uid/hug_settings は保持。
class CrmUnifyMigrationScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const CrmUnifyMigrationScreen({super.key, this.onBack});

  @override
  State<CrmUnifyMigrationScreen> createState() =>
      _CrmUnifyMigrationScreenState();
}

class _CrmUnifyMigrationScreenState extends State<CrmUnifyMigrationScreen> {
  bool _running = false;
  final List<String> _log = [];
  _MigrationResult? _result;

  void _appendLog(String msg) {
    setState(() => _log.add(msg));
  }

  Future<void> _run({required bool dryRun}) async {
    final ok = await AppFeedback.confirm(
      context,
      title: dryRun ? 'ドライラン実行' : 'マイグレーション実行',
      message: dryRun
          ? '実際にはデータを書き換えず、何件処理されるかだけ計算します。'
          : '実際に families コレクションにステータス・HUG ID・CRM項目を書き込みます。\n'
              '事前にドライランの結果を確認してから実行してください。',
      confirmLabel: dryRun ? 'ドライラン' : '実行',
      destructive: !dryRun,
    );
    if (ok != true) return;

    setState(() {
      _running = true;
      _log.clear();
      _result = null;
    });

    try {
      final result = await _runMigration(dryRun: dryRun, onLog: _appendLog);
      setState(() => _result = result);
      if (mounted) {
        AppFeedback.success(
          context,
          dryRun ? 'ドライラン完了' : 'マイグレーション完了',
        );
      }
    } catch (e, st) {
      _appendLog('エラー: $e');
      _appendLog(st.toString());
      if (mounted) AppFeedback.error(context, 'マイグレーション失敗: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: context.colors.textPrimary),
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
        title: const Text('CRM一体化マイグレーション'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: context.alerts.warning.background,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.warning_amber,
                          color: context.alerts.warning.icon),
                      const SizedBox(width: 8),
                      Text('一回限りのマイグレーション',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.alerts.warning.text)),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        '・families.children[] に status を後付け（未設定のもののみ「入会」）\n'
                        '・hug_settings/child_mapping を children[].hugChildId に展開（元は残す）\n'
                        '・crm_leads を families に upsert（電話/メールで既存family照合）\n'
                        '\n冪等です。何度実行しても重複しません。\n'
                        '既存の families ドキュメントID / loginId / uid / hug_settings は破壊しません。'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('ドライラン'),
                    onPressed: _running ? null : () => _run(dryRun: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('実行'),
                    onPressed: _running ? null : () => _run(dryRun: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_running) const LinearProgressIndicator(),
            if (_result != null) _buildResultCard(_result!),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  border: Border.all(color: context.colors.borderLight),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[i],
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: AppTextSize.small),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(_MigrationResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.dryRun ? 'ドライラン結果' : '実行結果',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('既存familiesにstatus付与: ${r.familiesSeeded} 家族 / ${r.childrenSeeded} 児童'),
            Text('hugChildId 展開: ${r.hugIdsCopied} 件'),
            Text('crm_leads → 既存familyへマージ: ${r.leadsMergedToExisting} 件'),
            Text('crm_leads → 兄弟として追加: ${r.leadsAddedAsSibling} 件'),
            Text('crm_leads → 新規family作成: ${r.leadsCreatedAsFamily} 件'),
            Text('crm_leads スキップ（既反映）: ${r.leadsSkipped} 件'),
            Text('birthDate 型修正: ${r.birthDateFixed} 件'),
          ],
        ),
      ),
    );
  }
}

class _MigrationResult {
  final bool dryRun;
  int familiesSeeded = 0;
  int childrenSeeded = 0;
  int hugIdsCopied = 0;
  int leadsMergedToExisting = 0;
  int leadsAddedAsSibling = 0;
  int leadsCreatedAsFamily = 0;
  int leadsSkipped = 0;
  int birthDateFixed = 0;
  _MigrationResult({required this.dryRun});
}

String _stageToStatus(String stage) {
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

Map<String, dynamic> _leadToChildFields(Map<String, dynamic> lead) {
  final fields = <String, dynamic>{
    'firstName': (lead['childFirstName'] ?? '').toString(),
    'lastName': (lead['childLastName'] ?? '').toString(),
    'firstNameKana': (lead['childKana'] ?? '').toString(),
    'gender': lead['childGender'],
    'birthDate': _normalizeBirthDate(lead['childBirthDate']),
    'classrooms': (lead['classrooms'] is List)
        ? lead['classrooms']
        : ['ビースマイリープラス湘南藤沢'],
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
    'activities': lead['activities'],
  };
  fields.removeWhere((k, v) => v == null);
  return fields;
}

bool _matchChild(Map<String, dynamic> child, Map<String, dynamic> lead) {
  final cFirst = (child['firstName'] ?? '').toString().trim();
  final cLast = (child['lastName'] ?? '').toString().trim();
  final lFirst = (lead['childFirstName'] ?? '').toString().trim();
  final lLast = (lead['childLastName'] ?? '').toString().trim();
  if (lFirst.isEmpty) return false;
  if (cFirst != lFirst) return false;
  // lastNameは family 側の親姓と同じことが多くchildに無い場合がある → firstName一致のみで採用
  if (cLast.isNotEmpty && lLast.isNotEmpty && cLast != lLast) return false;
  return true;
}

bool _familyMatchesLead(
    Map<String, dynamic> fam, Map<String, dynamic> lead) {
  final famTel = (fam['phone'] ?? fam['tel'] ?? '').toString().trim();
  final famEmail = (fam['email'] ?? '').toString().trim();
  final leadTel = (lead['parentTel'] ?? '').toString().trim();
  final leadEmail = (lead['parentEmail'] ?? '').toString().trim();
  if (leadTel.isNotEmpty && famTel == leadTel) return true;
  if (leadEmail.isNotEmpty && famEmail == leadEmail) return true;
  // 最後の手段: 親姓+名 一致
  final famPName =
      '${(fam['lastName'] ?? '').toString().trim()}${(fam['firstName'] ?? '').toString().trim()}';
  final leadPName =
      '${(lead['parentLastName'] ?? '').toString().trim()}${(lead['parentFirstName'] ?? '').toString().trim()}';
  if (famPName.isNotEmpty && famPName == leadPName) return true;
  return false;
}

Future<_MigrationResult> _runMigration({
  required bool dryRun,
  required void Function(String) onLog,
}) async {
  final result = _MigrationResult(dryRun: dryRun);
  final fs = FirebaseFirestore.instance;

  // ===== Step 1: families.children[] に status を付与 =====
  onLog('--- Step 1: 既存familiesにstatus付与 ---');
  final famSnap = await fs.collection('families').get();
  onLog('families: ${famSnap.docs.length} 件');

  for (final famDoc in famSnap.docs) {
    final data = famDoc.data();
    final children = List<Map<String, dynamic>>.from(
        (data['children'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)));
    bool changed = false;
    for (var i = 0; i < children.length; i++) {
      if (children[i]['status'] == null) {
        children[i]['status'] = '入会';
        changed = true;
        result.childrenSeeded++;
      }
    }
    if (changed) {
      result.familiesSeeded++;
      if (!dryRun) {
        await famDoc.reference.update({'children': children});
      }
    }
  }
  onLog('status付与: ${result.familiesSeeded}家族 / ${result.childrenSeeded}児童');

  // ===== Step 2: hug_settings/child_mapping → children[].hugChildId =====
  onLog('--- Step 2: HUG IDをchildren[]に展開 ---');
  final hugDoc =
      await fs.collection('hug_settings').doc('child_mapping').get();
  final hugMap = Map<String, String>.from(
      (hugDoc.data() ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())));
  onLog('hug child_mapping: ${hugMap.length} 件');

  if (hugMap.isNotEmpty) {
    // step1 の更新を反映するため再取得
    final famSnap2 = dryRun ? famSnap : await fs.collection('families').get();
    for (final famDoc in famSnap2.docs) {
      final data = famDoc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final lastName = (data['lastName'] ?? '').toString().trim();
      final children = List<Map<String, dynamic>>.from(
          (data['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      bool changed = false;
      for (var i = 0; i < children.length; i++) {
        if (children[i]['hugChildId'] != null &&
            children[i]['hugChildId'].toString().isNotEmpty) {
          continue;
        }
        final firstName = (children[i]['firstName'] ?? '').toString().trim();
        if (firstName.isEmpty) continue;
        final candidates = <String>[
          '$lastName$firstName',
          '$lastName $firstName',
          '$lastName　$firstName', // 全角スペース
          firstName,
        ];
        for (final key in candidates) {
          if (hugMap.containsKey(key) &&
              hugMap[key]!.toString().isNotEmpty) {
            children[i]['hugChildId'] = hugMap[key];
            changed = true;
            result.hugIdsCopied++;
            break;
          }
        }
      }
      if (changed && !dryRun) {
        await famDoc.reference.update({'children': children});
      }
    }
  }
  onLog('hugChildId 展開: ${result.hugIdsCopied} 件');

  // ===== Step 3: crm_leads を families に upsert =====
  onLog('--- Step 3: crm_leads を families に統合 ---');
  final leadsSnap = await fs.collection('crm_leads').get();
  onLog('crm_leads: ${leadsSnap.docs.length} 件');

  // 最新の families をキャッシュ
  final famSnap3 = dryRun ? famSnap : await fs.collection('families').get();
  final familyCache = <String, Map<String, dynamic>>{};
  for (final d in famSnap3.docs) {
    familyCache[d.id] = Map<String, dynamic>.from(d.data() as Map);
  }

  for (final leadDoc in leadsSnap.docs) {
    final lead = Map<String, dynamic>.from(leadDoc.data());
    final convertedFamilyId = lead['convertedFamilyId'] as String?;

    String? targetFamilyId;
    Map<String, dynamic>? targetFamily;

    if (convertedFamilyId != null &&
        familyCache.containsKey(convertedFamilyId)) {
      targetFamilyId = convertedFamilyId;
      targetFamily = familyCache[convertedFamilyId];
    } else {
      for (final entry in familyCache.entries) {
        if (_familyMatchesLead(entry.value, lead)) {
          targetFamilyId = entry.key;
          targetFamily = entry.value;
          break;
        }
      }
    }

    final childFields = _leadToChildFields(lead);
    childFields['sourceLeadId'] = leadDoc.id;

    if (targetFamily != null && targetFamilyId != null) {
      final children = List<Map<String, dynamic>>.from(
          (targetFamily['children'] as List? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map)));
      int idx = -1;
      for (var i = 0; i < children.length; i++) {
        if (_matchChild(children[i], lead)) {
          idx = i;
          break;
        }
        if (children[i]['sourceLeadId'] == leadDoc.id) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) {
        // 既反映: CRM項目で穴埋め（既存値は保持）
        bool filled = false;
        for (final k in childFields.keys) {
          if (children[idx][k] == null) {
            children[idx][k] = childFields[k];
            filled = true;
          }
        }
        if (filled) {
          result.leadsMergedToExisting++;
        } else {
          result.leadsSkipped++;
        }
      } else {
        children.add(childFields);
        result.leadsAddedAsSibling++;
      }
      targetFamily['children'] = children;
      familyCache[targetFamilyId] = targetFamily;
      if (!dryRun) {
        await fs
            .collection('families')
            .doc(targetFamilyId)
            .update({'children': children});
      }
    } else {
      // 新規family作成
      final familyData = <String, dynamic>{
        'uid': '',
        'lastName': lead['parentLastName'] ?? '',
        'firstName': lead['parentFirstName'] ?? '',
        'lastNameKana': lead['parentKana'] ?? '',
        'firstNameKana': '',
        'phone': lead['parentTel'] ?? '',
        'email': lead['parentEmail'] ?? '',
        'address': lead['address'] ?? '',
        'lineId': lead['parentLine'] ?? '',
        'children': [childFields],
        'sourceLeadId': leadDoc.id,
        'createdAt': lead['createdAt'] ?? FieldValue.serverTimestamp(),
        'createdBy': lead['createdBy'] ?? '',
      };
      result.leadsCreatedAsFamily++;
      if (!dryRun) {
        final ref = await fs.collection('families').add(familyData);
        familyCache[ref.id] = familyData;
      }
    }
  }
  onLog('merged=${result.leadsMergedToExisting} '
      'sibling=${result.leadsAddedAsSibling} '
      'newFamily=${result.leadsCreatedAsFamily} '
      'skipped=${result.leadsSkipped}');

  // ===== Step 4: birthDate 型修正（Timestamp/DateTime → String 'YYYY/MM/DD'） =====
  onLog('--- Step 4: birthDate 型修正 ---');
  final famSnap4 = dryRun ? famSnap : await fs.collection('families').get();
  int birthDateFixed = 0;
  for (final famDoc in famSnap4.docs) {
    final data = famDoc.data() as Map<String, dynamic>?;
    if (data == null) continue;
    final children = List<Map<String, dynamic>>.from(
        (data['children'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map)));
    bool changed = false;
    for (var i = 0; i < children.length; i++) {
      final v = children[i]['birthDate'];
      if (v == null) continue;
      if (v is String) continue;
      final normalized = _normalizeBirthDate(v);
      if (normalized != null) {
        children[i]['birthDate'] = normalized;
        changed = true;
        birthDateFixed++;
      }
    }
    if (changed && !dryRun) {
      await famDoc.reference.update({'children': children});
    }
  }
  result.birthDateFixed = birthDateFixed;
  onLog('birthDate修正: $birthDateFixed 件');

  onLog('--- 完了 ---');

  return result;
}
