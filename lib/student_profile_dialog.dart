import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

/// ai_student_profiles/{studentId} の HUG情報と AIプロファイルを表示するダイアログ。
/// AI相談画面とプラスのスケジュール画面（プロファイルボタン）から共通で利用される。
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

  String _formatPlanDate(int yyyymmdd) {
    final y = yyyymmdd ~/ 10000;
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    if (y < 2000 || m < 1 || m > 12 || d < 1 || d > 31) return yyyymmdd.toString();
    return '$y/$m/$d';
  }

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
      AppFeedback.info(context, synced == 1 ? 'HUG情報を更新しました' : '同期: $synced件 / 未マッピング: $unmapped件');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      AppFeedback.info(context, 'HUG同期に失敗: $e');
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
        // 高さを固定して、中身の展開/折りたたみで全体サイズが変わらないようにする
        constraints: BoxConstraints(
          maxWidth: 680,
          minHeight: MediaQuery.of(context).size.height - 80,
          maxHeight: MediaQuery.of(context).size.height - 80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ヘッダ
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.studentName,
                      style: TextStyle(fontSize: AppTextSize.title, fontWeight: FontWeight.w600, color: c.textPrimary),
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
                  final latestPlanDate = (data?['latestPlanDate'] is num)
                      ? (data!['latestPlanDate'] as num).toInt()
                      : 0;
                  final aiProfile = (data?['aiProfile'] as Map?)?.cast<String, dynamic>() ?? {};
                  final careRecords =
                      (data?['hugCareRecords'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                  final careRange = (data?['hugCareRecordsRange'] as Map?)?.cast<String, dynamic>();
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
                                style: TextStyle(fontSize: AppTextSize.small, color: c.textSecondary)),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('今すぐ同期', style: TextStyle(fontSize: AppTextSize.small)),
                              onPressed: _sync,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('HUG情報（自動取得）',
                            style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        const SizedBox(height: 8),
                        ..._docLabels.entries.map((e) => _buildDocCard(e.key, e.value, hugDocs, latestPlanDate)),
                        _buildCareRecordsSection(careRecords, careRange),
                        const SizedBox(height: 20),
                        Text('AIが蓄積した知見',
                            style: TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        const SizedBox(height: 8),
                        if (aiProfile.isEmpty)
                          Text('まだ蓄積されたプロファイルはありません。AI相談を重ねると自動的に学習します。',
                              style: TextStyle(fontSize: AppTextSize.small, color: c.textSecondary))
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

  Widget _buildDocCard(String type, String label, Map<String, dynamic> hugDocs, int latestPlanDate) {
    final c = context.colors;
    final d = (hugDocs[type] as Map?)?.cast<String, dynamic>() ?? {};
    final status = d['status'] as String?;
    final rawText = d['rawText'] as String? ?? '';
    final url = d['url'] as String? ?? '';
    final planDate = (d['planDate'] is num) ? (d['planDate'] as num).toInt() : 0;
    final isOk = status == 'ok' && rawText.isNotEmpty;
    final isOutdated = isOk && planDate > 0 && latestPlanDate > 0 && planDate < latestPlanDate;
    final isExpanded = _expandedType == type;

    IconData statusIcon;
    Color statusColor;
    String statusText;
    switch (status) {
      case 'ok':
        statusIcon = Icons.check_circle;
        statusColor = isOutdated ? AppColors.info : AppColors.success;
        statusText = planDate > 0 ? '作成日: ${_formatPlanDate(planDate)}' : '取得済';
        break;
      case 'not-created':
        statusIcon = Icons.remove_circle_outline;
        statusColor = c.textTertiary;
        statusText = '未作成';
        break;
      case 'error':
        statusIcon = Icons.error_outline;
        statusColor = AppColors.error;
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
                        Text(label, style: TextStyle(fontSize: AppTextSize.body, color: c.textPrimary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(
                          statusText,
                          style: TextStyle(fontSize: AppTextSize.caption, color: c.textSecondary),
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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.scaffoldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.borderLight, width: 0.5),
                ),
                child: _buildStructuredText(rawText),
              ),
            ),
        ],
      ),
    );
  }

  /// HUGから抽出した rawText を読みやすい構造で表示する。
  /// - "## タイトル" → 見出し
  /// - "ラベル: 値" → ラベル小文字 + 値（値に " / " や " ・" があれば箇条書き）
  /// - その他 → パラグラフ
  Widget _buildStructuredText(String raw) {
    final c = context.colors;
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final widgets = <Widget>[];

    List<Widget> renderValue(String value) {
      String v = value.trim();
      // 値内に ・区切りの項目が2つ以上
      final bulletSplit = v.split(RegExp(r'\s*・\s*')).where((p) => p.trim().isNotEmpty).toList();
      if (v.startsWith('・') || (bulletSplit.length >= 2 && RegExp(r'・').hasMatch(v))) {
        return bulletSplit.map((p) => Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 3),
          child: Text('・${p.trim()}',
              style: TextStyle(fontSize: AppTextSize.body, color: c.textPrimary, height: 1.7)),
        )).toList();
      }
      // " / " で複数値を連結している場合も箇条書きにする（ただし日付などのスラッシュは除外する目安で3つ以上）
      final slashParts = v.split(' / ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (slashParts.length >= 3) {
        return slashParts.map((p) => Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 3),
          child: Text('・$p',
              style: TextStyle(fontSize: AppTextSize.body, color: c.textPrimary, height: 1.7)),
        )).toList();
      }
      return [
        SelectableText(v, style: TextStyle(fontSize: AppTextSize.body, color: c.textPrimary, height: 1.7)),
      ];
    }

    for (final line in lines) {
      if (line.startsWith('## ')) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            line.substring(3).trim(),
            style: TextStyle(
              fontSize: AppTextSize.bodyLarge,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              height: 1.4,
            ),
          ),
        ));
        continue;
      }
      final colonIdx = line.indexOf(': ');
      if (colonIdx > 0 && colonIdx < 40) {
        final label = line.substring(0, colonIdx).trim();
        final value = line.substring(colonIdx + 2).trim();
        if (value.isEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(label,
                style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
          ));
        } else {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                ...renderValue(value),
              ],
            ),
          ));
        }
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(
            line,
            style: TextStyle(fontSize: AppTextSize.body, color: c.textPrimary, height: 1.7),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildCareRecordsSection(
      List<Map<String, dynamic>> records, Map<String, dynamic>? range) {
    final c = context.colors;
    final hasRecords = records.isNotEmpty;
    final latestDate = hasRecords ? (records.first['date'] as String? ?? '') : '';
    final statusText = !hasRecords
        ? 'ケア記録はありません'
        : latestDate.isNotEmpty
            ? '作成日: $latestDate'
            : '${records.length}件';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.tagBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: hasRecords ? () => _showCareRecordsDialog(records, range) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                hasRecords ? Icons.check_circle : Icons.remove_circle_outline,
                size: 16,
                color: hasRecords ? AppColors.success : c.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ケア記録',
                        style: TextStyle(
                            fontSize: AppTextSize.body,
                            color: c.textPrimary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(statusText,
                        style: TextStyle(fontSize: AppTextSize.caption, color: c.textSecondary)),
                  ],
                ),
              ),
              if (hasRecords)
                IconButton(
                  icon: const Icon(Icons.list_alt, size: 18),
                  color: c.textSecondary,
                  tooltip: '過去のケア記録',
                  onPressed: () => _showCareRecordsDialog(records, range),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCareRecordsDialog(
      List<Map<String, dynamic>> records, Map<String, dynamic>? range) {
    final c = context.colors;
    final rangeText = range == null ? '' : '（${range['from']} 〜 ${range['to']}）';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.scaffoldBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.of(context).size.height - 120,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ケア記録',
                              style: TextStyle(
                                  fontSize: AppTextSize.titleSm,
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary)),
                          if (rangeText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('${records.length}件 $rangeText',
                                  style: TextStyle(
                                      fontSize: AppTextSize.caption, color: c.textSecondary)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: c.textTertiary),
                      onPressed: () => Navigator.pop(ctx),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.borderLight),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: records.map((r) => _CareRecordTile(record: r)).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
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
            Text(entry.value, style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: c.textPrimary)),
            const SizedBox(height: 4),
            Text(content, style: TextStyle(fontSize: AppTextSize.small, color: c.textSecondary, height: 1.6)),
          ],
        ),
      ));
    }
    return widgets;
  }
}

/// ケア記録の1行。本文が未取得なら展開時にサーバから遅延取得する。
class _CareRecordTile extends StatefulWidget {
  final Map<String, dynamic> record;
  const _CareRecordTile({required this.record});

  @override
  State<_CareRecordTile> createState() => _CareRecordTileState();
}

class _CareRecordTileState extends State<_CareRecordTile> {
  bool _expanded = false;
  bool _loading = false;
  String? _lazyBody;
  String? _lazyError;

  Future<void> _toggle() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (!next) return;
    final existing = (widget.record['body'] as String?) ?? _lazyBody;
    if (existing != null && existing.isNotEmpty) return;
    final bookId = widget.record['bookId'];
    if (bookId == null) return;
    setState(() {
      _loading = true;
      _lazyError = null;
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast1')
          .httpsCallable('fetchHugCareRecordBody');
      final result = await callable.call({
        'bookId': bookId,
        if (widget.record['cId'] != null) 'cId': widget.record['cId'],
        if (widget.record['sId'] != null) 'sId': widget.record['sId'],
      });
      final body = (result.data as Map?)?['body'] as String? ?? '';
      if (!mounted) return;
      setState(() {
        _lazyBody = body;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lazyError = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.record;
    final date = r['date'] as String? ?? '';
    final activity = r['activity'] as String? ?? '';
    final attendance = r['attendance'] as String? ?? '';
    final recorder = r['recorder'] as String? ?? '';
    final bookId = r['bookId'];
    final body = (r['body'] as String?) ?? _lazyBody ?? '';

    final subtitleParts = <String>[];
    if (activity.isNotEmpty) subtitleParts.add(activity);
    if (attendance.isNotEmpty) subtitleParts.add(attendance);
    if (recorder.isNotEmpty) subtitleParts.add(recorder);
    final subtitle = subtitleParts.join(' ・ ');

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
            onTap: bookId == null ? null : _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(date,
                            style: TextStyle(
                                fontSize: AppTextSize.body,
                                fontWeight: FontWeight.w500,
                                color: c.textPrimary)),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: TextStyle(
                                  fontSize: AppTextSize.caption, color: c.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  if (bookId != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      color: c.textSecondary,
                      tooltip: 'HUGで開く',
                      onPressed: () {
                        final cId = r['cId'];
                        final sId = r['sId'];
                        final params = <String, String>{
                          'mode': 'preview',
                          'id': '$bookId',
                          if (cId != null) 'c_id': '$cId',
                          if (sId != null) 's_id': '$sId',
                        };
                        final url = Uri.parse(
                            'https://www.hug-beesmiley.link/hug/wm/contact_book.php')
                            .replace(queryParameters: params);
                        launchUrl(url, mode: LaunchMode.externalApplication);
                      },
                    ),
                  if (bookId != null)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: c.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.scaffoldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.borderLight, width: 0.5),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 32,
                        child: Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))))
                    : _lazyError != null
                        ? Text('取得失敗: $_lazyError',
                            style: TextStyle(fontSize: AppTextSize.caption, color: AppColors.errorBorder))
                        : body.isEmpty
                            ? Text('本文はありません。',
                                style: TextStyle(
                                    fontSize: AppTextSize.small, color: c.textSecondary))
                            : SelectableText(body,
                                style: TextStyle(
                                    fontSize: AppTextSize.small,
                                    height: 1.6,
                                    color: c.textPrimary)),
              ),
            ),
        ],
      ),
    );
  }

}

