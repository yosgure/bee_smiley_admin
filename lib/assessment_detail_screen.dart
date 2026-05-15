import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'assessment_edit_screen.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'main.dart';

class AssessmentDetailScreen extends StatefulWidget {
  final DocumentSnapshot doc;
  final VoidCallback? onClose;

  const AssessmentDetailScreen({super.key, required this.doc, this.onClose});

  @override
  State<AssessmentDetailScreen> createState() => _AssessmentDetailScreenState();
}

class _AssessmentDetailScreenState extends State<AssessmentDetailScreen> {
  bool _isPublishing = false;
  bool _isDeleting = false;
  late Map<String, dynamic> _data;

  @override
  void initState() {
    super.initState();
    _data = widget.doc.data() as Map<String, dynamic>;
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmAndDelete() async {
    final type = _data['type'] as String? ?? 'weekly';
    final isWeekly = type == 'weekly';
    final confirmed = await AppFeedback.confirm(
      context,
      title: isWeekly ? 'この週次アセスメントを削除しますか？' : 'この月次サマリを削除しますか？',
      message: 'この操作は取り消せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _isDeleting = true);
    // 親のMessengerを事前取得（_close後はcontextが使えない可能性があるため）
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await FirebaseFirestore.instance
          .collection('assessments')
          .doc(widget.doc.id)
          .delete();
      messenger?.showSnackBar(
        const SnackBar(content: Text('削除しました'), backgroundColor: AppColors.success),
      );
      if (mounted) _close();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('削除に失敗: $e'), backgroundColor: AppColors.error),
      );
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _openEdit() {
    final type = _data['type'] as String? ?? 'weekly';
    final studentName = _data['studentName'] ?? '';
    if (widget.onClose != null) {
      AdminShell.showOverlay(
        context,
        AssessmentEditScreen(
          studentId: _data['studentId'] ?? '',
          studentName: studentName,
          type: type,
          docId: widget.doc.id,
          initialData: _data,
          onClose: () => AdminShell.hideOverlay(context),
        ),
        confirmLeave: true,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AssessmentEditScreen(
            studentId: _data['studentId'] ?? '',
            studentName: studentName,
            type: type,
            docId: widget.doc.id,
            initialData: _data,
          ),
        ),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _publish() async {
    setState(() => _isPublishing = true);
    try {
      await FirebaseFirestore.instance
          .collection('assessments')
          .doc(widget.doc.id)
          .update({'isPublished': true});
      
      setState(() {
        _data['isPublished'] = true;
      });
      
      if (mounted) {
        AppFeedback.success(context, '公開しました');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'エラー: $e');
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _data['type'] as String? ?? 'weekly';
    final isWeekly = type == 'weekly';
    final isPublished = _data['isPublished'] == true;
    
    final date = (_data['date'] as Timestamp).toDate();
    final studentName = _data['studentName'] ?? '';
    final classroom = _data['classroom'] ?? '';

    return Scaffold(
      backgroundColor: context.colors.cardBg,
      appBar: AppBar(
        title: Text(isWeekly ? '週次アセスメント詳細' : '月次サマリ詳細'),
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: context.colors.textPrimary),
          onPressed: _close,
        ),
        actions: [
          // 下書きの場合は「公開」ボタンを表示
          if (!isPublished)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              child: ElevatedButton(
                onPressed: _isPublishing ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isPublishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('公開', style: TextStyle(fontSize: AppTextSize.body, color: Colors.white)),
              ),
            ),
          // 編集・削除は三点メニューに統合
          PopupMenuButton<String>(
            tooltip: 'その他',
            icon: Icon(Icons.more_vert, color: context.colors.textSecondary),
            onSelected: (v) {
              if (v == 'edit') _openEdit();
              if (v == 'delete') _confirmAndDelete();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('編集', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                enabled: !_isDeleting,
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                    const SizedBox(width: 10),
                    Text('削除', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー情報
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isWeekly 
                            ? DateFormat('yyyy/MM/dd (E)', 'ja').format(date)
                            : DateFormat('yyyy年 MM月').format(date),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: AppTextSize.titleSm),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ステータスバッジ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPublished ? AppColors.success.withValues(alpha: 0.1) : AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isPublished ? AppColors.success : AppColors.accent,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        isPublished ? '公開中' : '下書き',
                        style: TextStyle(
                          fontSize: AppTextSize.caption,
                          fontWeight: FontWeight.bold,
                          color: isPublished ? AppColors.success : AppColors.accent.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        studentName,
                        style: const TextStyle(fontSize: AppTextSize.xl, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (classroom.isNotEmpty)
                  Text('クラス: $classroom', style: TextStyle(color: context.colors.textSecondary)),
                
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // コンテンツ表示
                if (isWeekly) 
                  _buildWeeklyContent(_data)
                else 
                  _buildMonthlyContent(_data),
                  
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 週次データの表示（教具、評価、時間、コメント、写真）
  Widget _buildWeeklyContent(Map<String, dynamic> data) {
    final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);

    if (entries.isEmpty) {
      return Center(child: Text('記録がありません', style: TextStyle(color: context.colors.textSecondary)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        final task = entry['task'] as String? ?? '';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: AppStyles.radius,
            border: Border.all(color: context.colors.borderLight),
            boxShadow: [BoxShadow(color: context.colors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 教具名
              Text(
                entry['tool'] ?? '教具未選択',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleLg),
              ),
              // ★追加: 発達課題（task）を薄いグレーで表示
              if (task.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(
                    task,
                    style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textTertiary),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 評価と時間
              Row(
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(8)), child: Text('評価: ${entry['rating'] ?? '-'}', style: TextStyle(fontSize: AppTextSize.small))),
                ],
              ),
              const SizedBox(height: 16),

              // コメント
              if ((entry['comment'] ?? '').isNotEmpty) ...[
                Text('コメント', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small, color: context.colors.textSecondary)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.inputFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry['comment'],
                    style: const TextStyle(height: 1.5, fontSize: AppTextSize.bodyMd),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 写真・動画（mediaItems があれば全て、なければ photoUrl 単体にフォールバック）
              ...(() {
                final List<Map<String, dynamic>> mediaItems = [];
                final raw = entry['mediaItems'] as List<dynamic>?;
                if (raw != null && raw.isNotEmpty) {
                  for (final m in raw) {
                    if (m is Map) mediaItems.add({'type': m['type'] ?? 'image', 'url': m['url']});
                  }
                } else if (entry['photoUrl'] != null && (entry['photoUrl'] as String).isNotEmpty) {
                  mediaItems.add({'type': 'image', 'url': entry['photoUrl']});
                }
                if (mediaItems.isEmpty) return <Widget>[];
                return [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: mediaItems.map((m) {
                      final url = m['url'] as String?;
                      if (url == null || url.isEmpty) return const SizedBox.shrink();
                      if (m['type'] == 'video') {
                        return GestureDetector(
                          onTap: () => _launchUrl(url),
                          child: Container(
                            width: 160, height: 120,
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                            alignment: Alignment.center,
                            child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                          ),
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          url,
                          width: 160, height: 120, fit: BoxFit.cover,
                          errorBuilder: (c, o, s) => Container(
                            width: 160, height: 120,
                            color: context.colors.inputFill,
                            child: Icon(Icons.broken_image, color: context.colors.textSecondary),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ];
              })(),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 月次データの表示
  Widget _buildMonthlyContent(Map<String, dynamic> data) {
    final summary = data['summary'] ?? '';
    final photos = List<String>.from(data['photos'] ?? []);
    final sensitivePeriods = List<String>.from(data['sensitivePeriods'] ?? []);
    final sensitivePeriodEntries = List<Map<String, dynamic>>.from(data['sensitivePeriodEntries'] ?? []);
    final sensitivePeriodComment = data['sensitivePeriodComment'] ?? '';
    final monthlyEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 非認知能力リスト
        if (monthlyEntries.isNotEmpty) ...[
          _buildSectionCard(
            title: '非認知能力・伸びている力',
            icon: Icons.psychology,
            iconColor: AppColors.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: monthlyEntries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6, right: 10),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${e['category'] ?? ''}', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
                            const TextSpan(text: ' : '),
                            TextSpan(text: e['skill'] ?? '', style: TextStyle(color: context.colors.textSecondary)),
                          ],
                        ),
                        style: const TextStyle(fontSize: AppTextSize.bodyMd, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 敏感期
        if (sensitivePeriodEntries.isNotEmpty || sensitivePeriods.isNotEmpty) ...[
          _buildSectionCard(
            title: '敏感期',
            icon: Icons.lightbulb_outline,
            iconColor: AppColors.success,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 敏感期リスト
                ...sensitivePeriodEntries.map((e) {
                  final period = e['period'] as String? ?? '';
                  if (period.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(period, style: TextStyle(fontSize: AppTextSize.bodyMd, color: context.colors.textPrimary)),
                      ],
                    ),
                  );
                }),
                // 旧形式の敏感期も表示
                ...sensitivePeriods.map((period) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(period, style: TextStyle(fontSize: AppTextSize.bodyMd, color: context.colors.textPrimary)),
                    ],
                  ),
                )),
                // コメント
                if (sensitivePeriodComment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    sensitivePeriodComment,
                    style: TextStyle(height: 1.5, fontSize: AppTextSize.bodyMd, color: context.colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 総評
        _buildSectionCard(
          title: '今月の様子・総評',
          icon: Icons.edit_note,
          iconColor: AppColors.primary,
          child: Text(
            summary.isEmpty ? 'なし' : summary,
            style: TextStyle(height: 1.6, fontSize: AppTextSize.bodyMd, color: context.colors.textPrimary),
          ),
        ),

        // 写真
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '写真',
            icon: Icons.photo_library,
            iconColor: AppColors.primary,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photos.map((url) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              )).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // セクションカード共通ウィジェット
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.bodyLarge,
                  color: iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        border: Border.all(color: context.colors.borderMedium),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}