import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

/// families コレクションをプラス用と通常用に分離するマイグレーション。
///
/// 判定: children[] のいずれかが下記のどれかを満たすと「プラス児童」とみなす:
///   1. classrooms に「プラス」を含む
///   2. hugChildId が設定されている
///   3. sourceLeadId が設定されている（CRM由来）
///
/// 注: status は P1 マイグレで全児童に付与されたため判定基準に使えない。
///
/// 処理:
///   - 全 children がプラス → family ごと plus_families へ移動（families から削除）
///   - 全 children が通常 → families に残す（プラス系フィールドの除去は B-clean で行う）
///   - 混在 → split: plus_families に新family作成（プラス児童のみ）、families の元familyは通常児童のみに更新
///
/// 冪等: 既に plus_families に sourceFamilyId 一致のドキュメントがあれば重複作成しない。
/// 既存 families ドキュメントID / loginId / uid は破壊しない（プラス側にもコピーするが元はそのまま）。
class PlusFamiliesSplitScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PlusFamiliesSplitScreen({super.key, this.onBack});

  @override
  State<PlusFamiliesSplitScreen> createState() =>
      _PlusFamiliesSplitScreenState();
}

class _PlusFamiliesSplitScreenState extends State<PlusFamiliesSplitScreen> {
  bool _running = false;
  final List<String> _log = [];
  _SplitResult? _result;

  void _appendLog(String msg) => setState(() => _log.add(msg));

  Future<void> _run({required bool dryRun}) async {
    final ok = await AppFeedback.confirm(
      context,
      title: dryRun ? 'ドライラン実行' : 'split マイグレーション実行',
      message: dryRun
          ? '実際にはデータを書き換えず、何件処理されるかだけ計算します。'
          : 'families コレクションをプラス用/通常用に分離します。\n'
              '・プラス児童のみの家族 → plus_families へ移動（families から削除）\n'
              '・通常児童のみの家族 → families にそのまま残す\n'
              '・混在家族 → 分割（保護者情報を複製、プラス児童は plus_families へ）\n\n'
              '事前にバックアップを取得してください。',
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
      final result = await _runSplit(dryRun: dryRun, onLog: _appendLog);
      setState(() => _result = result);
      if (mounted) {
        AppFeedback.success(
          context,
          dryRun ? 'ドライラン完了' : 'split 完了',
        );
      }
    } catch (e, st) {
      _appendLog('エラー: $e');
      _appendLog(st.toString());
      if (mounted) AppFeedback.error(context, 'split 失敗: $e');
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
        title: const Text('families → plus_families 分離'),
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
                      Text('families コレクション分離マイグレーション',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.alerts.warning.text)),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        '判定: children[] の以下のどれかでプラス児童扱い\n'
                        '  1. classrooms に「プラス」を含む\n'
                        '  2. hugChildId が設定されている\n'
                        '  3. sourceLeadId が設定されている\n\n'
                        '全プラス → family ごと plus_families へ移動\n'
                        '全通常 → families にそのまま残す\n'
                        '混在 → 分割（保護者情報を複製）\n\n'
                        '完了後、families.children[] から CRM系フィールド'
                        '（status / stage / sourceLeadId / hugChildId / 各種CRM項目）を除去します。\n\n'
                        '冪等。再実行しても重複・破壊なし。\n'
                        '事前にFirestoreバックアップ取得済みであることを確認してください。'),
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

  Widget _buildResultCard(_SplitResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.dryRun ? 'ドライラン結果' : '実行結果',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('families 全件: ${r.totalFamilies}'),
            Text('全プラス家族 → plus_families へ移動: ${r.movedToPlus}'),
            Text('混在家族 → split: ${r.split}'),
            Text('全通常家族 → そのまま families: ${r.regularKept}'),
            Text('スキップ（既に plus_families に存在）: ${r.skipped}'),
            Text('families クリーンアップ: ${r.cleanedFamilies}家族 / ${r.cleanedChildren}児童'),
          ],
        ),
      ),
    );
  }
}

class _SplitResult {
  final bool dryRun;
  int totalFamilies = 0;
  int movedToPlus = 0;
  int split = 0;
  int regularKept = 0;
  int skipped = 0;
  int cleanedFamilies = 0;
  int cleanedChildren = 0;
  _SplitResult({required this.dryRun});
}

bool _isPlusChild(Map<String, dynamic> child) {
  // 1. classrooms に「プラス」を含む
  final classrooms = (child['classrooms'] as List? ?? []);
  if (classrooms.any((c) => c.toString().contains('プラス'))) return true;
  // 2. hugChildId 設定
  final hug = child['hugChildId'];
  if (hug != null && hug.toString().isNotEmpty) return true;
  // 3. sourceLeadId 設定
  final src = child['sourceLeadId'];
  if (src != null && src.toString().isNotEmpty) return true;
  // 注: status は P1 マイグレで全児童に付与されているため判定に使えない
  return false;
}

Future<_SplitResult> _runSplit({
  required bool dryRun,
  required void Function(String) onLog,
}) async {
  final result = _SplitResult(dryRun: dryRun);
  final fs = FirebaseFirestore.instance;

  onLog('--- families 分離開始 ---');
  final famSnap = await fs.collection('families').get();
  result.totalFamilies = famSnap.docs.length;
  onLog('families 全件: ${result.totalFamilies}');

  // 既存 plus_families の sourceFamilyId 集合（冪等性確保）
  final plusSnap = await fs.collection('plus_families').get();
  final existingPlusSourceIds = <String>{};
  for (final d in plusSnap.docs) {
    final src = (d.data() as Map<String, dynamic>?)?['sourceFamilyId'];
    if (src != null && src.toString().isNotEmpty) {
      existingPlusSourceIds.add(src.toString());
    }
  }
  onLog('既存 plus_families: ${plusSnap.docs.length} 件 '
      '(sourceFamilyId 持ち: ${existingPlusSourceIds.length})');

  for (final famDoc in famSnap.docs) {
    final data = Map<String, dynamic>.from(famDoc.data() as Map);
    final children = List<Map<String, dynamic>>.from(
        (data['children'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map)));

    final plusChildren = <Map<String, dynamic>>[];
    final regularChildren = <Map<String, dynamic>>[];
    for (final c in children) {
      if (_isPlusChild(c)) {
        plusChildren.add(c);
      } else {
        regularChildren.add(c);
      }
    }

    if (plusChildren.isEmpty) {
      // 全部通常 → そのまま
      result.regularKept++;
      continue;
    }

    if (existingPlusSourceIds.contains(famDoc.id)) {
      // 既に分離済み → スキップ
      result.skipped++;
      continue;
    }

    if (regularChildren.isEmpty) {
      // 全部プラス → plus_families へ移動
      final plusData = Map<String, dynamic>.from(data);
      plusData['sourceFamilyId'] = famDoc.id;
      if (!dryRun) {
        await fs.collection('plus_families').add(plusData);
        await famDoc.reference.delete();
      }
      result.movedToPlus++;
    } else {
      // 混在 → split
      final plusData = Map<String, dynamic>.from(data);
      plusData.remove('uid'); // 通常側にuid残す（認証維持）
      plusData['children'] = plusChildren;
      plusData['sourceFamilyId'] = famDoc.id;
      if (!dryRun) {
        await fs.collection('plus_families').add(plusData);
        await famDoc.reference.update({'children': regularChildren});
      }
      result.split++;
    }
  }

  onLog('moved=${result.movedToPlus} '
      'split=${result.split} '
      'regularKept=${result.regularKept} '
      'skipped=${result.skipped}');

  // ===== B-clean: families.children[] から CRM系フィールド除去 =====
  onLog('--- families クリーンアップ: CRM系フィールド除去 ---');
  const fieldsToStrip = <String>[
    'status', 'stage', 'confidence',
    'source', 'sourceDetail', 'sourceLeadId',
    'preferredChannel', 'preferredDays', 'preferredTimeSlots', 'preferredStart',
    'kindergarten', 'permitStatus',
    'mainConcern', 'likes', 'dislikes', 'trialNotes',
    'inquiredAt', 'firstContactedAt', 'trialAt', 'enrolledAt',
    'lostAt', 'withdrawnAt', 'lastActivityAt',
    'lossReason', 'lossDetail', 'reapproachOk',
    'withdrawReason', 'withdrawDetail',
    'memo', 'activities', 'hugChildId',
  ];
  final famSnap2 =
      dryRun ? famSnap : await fs.collection('families').get();
  int childrenCleaned = 0;
  int familiesUpdated = 0;
  for (final famDoc in famSnap2.docs) {
    final data = famDoc.data() as Map<String, dynamic>?;
    if (data == null) continue;
    final children = List<Map<String, dynamic>>.from(
        (data['children'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map)));
    bool changed = false;
    for (var i = 0; i < children.length; i++) {
      bool childChanged = false;
      for (final k in fieldsToStrip) {
        if (children[i].containsKey(k)) {
          children[i].remove(k);
          childChanged = true;
        }
      }
      if (childChanged) {
        childrenCleaned++;
        changed = true;
      }
    }
    // family レベルの sourceLeadId / sourceFamilyId も除去
    final famUpdate = <String, dynamic>{};
    if (data.containsKey('sourceLeadId')) {
      famUpdate['sourceLeadId'] = FieldValue.delete();
      changed = true;
    }
    if (changed) {
      familiesUpdated++;
      if (!dryRun) {
        await famDoc.reference
            .update({'children': children, ...famUpdate});
      }
    }
  }
  result.cleanedFamilies = familiesUpdated;
  result.cleanedChildren = childrenCleaned;
  onLog('families クリーンアップ: $familiesUpdated家族 / $childrenCleaned児童');

  onLog('--- 完了 ---');
  return result;
}
