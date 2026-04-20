import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';

/// ai_student_profiles/{studentId} の HUG情報と AIプロファイルを表示するダイアログ。
/// AI相談画面とプラスのスケジュール画面（策定会議ボタン）から共通で利用される。
Future<void> showStudentProfileDialog(BuildContext context, {
  required String studentId,
  required String studentName,
}) async {
  await showDialog(
    context: context,
    builder: (ctx) => _StudentProfileDialog(studentId: studentId, studentName: studentName),
  );
}

class _StudentProfileDialog extends StatefulWidget {
  final String studentId;
  final String studentName;
  const _StudentProfileDialog({required this.studentId, required this.studentName});

  @override
  State<_StudentProfileDialog> createState() => _StudentProfileDialogState();
}

class _StudentProfileDialogState extends State<_StudentProfileDialog> {
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  String? _expandedType; // 今開いているドキュメント種類

  static const Map<String, String> _docLabels = {
    'assessment': 'アセスメント',
    'carePlanDraft': '個別支援計画書(原案)',
    'beforeMeeting': 'サービス担当者会議の議事録',
    'carePlanMain': '個別支援計画書',
    'monitoring': 'モニタリング',
  };

  Future<void> _sync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final callable = _functions.httpsCallable('syncHugDocs');
      final result = await callable.call({'studentId': widget.studentId});
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final data = (result.data as Map?) ?? {};
      final synced = data['synced'] ?? 0;
      final unmapped = data['skippedUnmapped'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(synced == 1 ? 'HUG情報を更新しました' : '同期: $synced件 / 未マッピング: $unmapped件')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HUG同期に失敗: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.scaffoldBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ヘッダ
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.aiAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.psychology_outlined, color: c.aiAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.studentName,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        Text('児童プロファイル',
                            style: TextStyle(fontSize: 11, color: c.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: c.textTertiary),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.borderLight),

            // 本文
            Flexible(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('ai_student_profiles')
                    .doc(widget.studentId)
                    .snapshots(),
                builder: (ctx, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  final hugDocs = (data?['hugDocs'] as Map?)?.cast<String, dynamic>() ?? {};
                  final aiProfile = (data?['aiProfile'] as Map?)?.cast<String, dynamic>() ?? {};
                  final lastSynced = data?['lastSyncedAt'];
                  final lastSyncedText = lastSynced is Timestamp
                      ? DateFormat('yyyy/MM/dd HH:mm').format(lastSynced.toDate())
                      : '未同期';

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sync, size: 14, color: c.textSecondary),
                            const SizedBox(width: 6),
                            Text('HUG最終同期: $lastSyncedText',
                                style: TextStyle(fontSize: 12, color: c.textSecondary)),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('今すぐ同期', style: TextStyle(fontSize: 12)),
                              onPressed: _sync,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('HUG情報（自動取得）',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        const SizedBox(height: 8),
                        ..._docLabels.entries.map((e) => _buildDocCard(e.key, e.value, hugDocs)),
                        const SizedBox(height: 20),
                        Text('AIが蓄積した知見',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        const SizedBox(height: 8),
                        if (aiProfile.isEmpty)
                          Text('まだ蓄積されたプロファイルはありません。AI相談を重ねると自動的に学習します。',
                              style: TextStyle(fontSize: 12, color: c.textSecondary))
                        else
                          ..._buildAiProfileSections(aiProfile),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocCard(String type, String label, Map<String, dynamic> hugDocs) {
    final c = context.colors;
    final d = (hugDocs[type] as Map?)?.cast<String, dynamic>() ?? {};
    final status = d['status'] as String?;
    final rawText = d['rawText'] as String? ?? '';
    final url = d['url'] as String? ?? '';
    final isOk = status == 'ok' && rawText.isNotEmpty;
    final isExpanded = _expandedType == type;

    IconData statusIcon;
    Color statusColor;
    String statusText;
    switch (status) {
      case 'ok':
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        statusText = '取得済';
        break;
      case 'not-created':
        statusIcon = Icons.remove_circle_outline;
        statusColor = c.textTertiary;
        statusText = '未作成';
        break;
      case 'error':
        statusIcon = Icons.error_outline;
        statusColor = Colors.red;
        statusText = 'エラー';
        break;
      default:
        statusIcon = Icons.help_outline;
        statusColor = c.textTertiary;
        statusText = '未取得';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.tagBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight, width: 0.5),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isOk
                ? () => setState(() => _expandedType = isExpanded ? null : type)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(fontSize: 13, color: c.textPrimary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(
                          isOk ? '$statusText (${rawText.length}文字)' : statusText,
                          style: TextStyle(fontSize: 11, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (url.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      color: c.textSecondary,
                      tooltip: 'HUGで開く',
                      onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    ),
                  if (isOk)
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: c.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (isExpanded && isOk)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.scaffoldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.borderLight, width: 0.5),
                ),
                child: SelectableText(
                  rawText,
                  style: TextStyle(fontSize: 12, color: c.textPrimary, height: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildAiProfileSections(Map<String, dynamic> aiProfile) {
    const labels = {
      'strengths': '得意・好きなこと',
      'challenges': '課題・苦手なこと',
      'triggers': '不安・混乱のきっかけ',
      'effectiveApproaches': '効果のあった支援方法',
      'currentGoals': '現在の目標',
      'recentWins': '最近の成功体験',
      'familyContext': '家族関係',
      'staffNotes': '担当者メモ',
    };
    final c = context.colors;
    final widgets = <Widget>[];
    for (final entry in labels.entries) {
      final v = aiProfile[entry.key];
      if (v == null) continue;
      String content;
      if (v is List) {
        if (v.isEmpty) continue;
        content = v.map((x) => '・$x').join('\n');
      } else if (v is String) {
        if (v.trim().isEmpty) continue;
        content = v.trim();
      } else {
        continue;
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
            const SizedBox(height: 4),
            Text(content, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.6)),
          ],
        ),
      ));
    }
    return widgets;
  }
}
