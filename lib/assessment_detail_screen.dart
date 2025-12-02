import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart';
import 'app_theme.dart';

class AssessmentDetailScreen extends StatefulWidget {
  final DocumentSnapshot doc;

  const AssessmentDetailScreen({super.key, required this.doc});

  @override
  State<AssessmentDetailScreen> createState() => _AssessmentDetailScreenState();
}

class _AssessmentDetailScreenState extends State<AssessmentDetailScreen> {
  bool _isPublishing = false;
  late Map<String, dynamic> _data;

  @override
  void initState() {
    super.initState();
    _data = widget.doc.data() as Map<String, dynamic>;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('公開しました'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isWeekly ? '週次アセスメント詳細' : '月次サマリ詳細'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 下書きの場合は「公開」ボタンを表示
          if (!isPublished)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              child: ElevatedButton(
                onPressed: _isPublishing ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isPublishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('公開', style: TextStyle(fontSize: 13, color: Colors.white)),
              ),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AssessmentEditScreen(
                    studentId: _data['studentId'] ?? '',
                    studentName: studentName,
                    type: type,
                    docId: widget.doc.id,
                    initialData: _data,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.edit, size: 18, color: AppColors.primary),
            label: const Text('編集', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ステータスバッジ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPublished ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isPublished ? Colors.green : Colors.orange,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        isPublished ? '公開中' : '下書き',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isPublished ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        studentName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (classroom.isNotEmpty)
                  Text('クラス: $classroom', style: const TextStyle(color: Colors.grey)),
                
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
      return const Center(child: Text('記録がありません', style: TextStyle(color: Colors.grey)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        final task = entry['task'] as String? ?? '';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppStyles.radius,
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 教具名
              Row(
                children: [
                  const Icon(Icons.extension, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry['tool'] ?? '教具未選択',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              // ★追加: 発達課題（task）を薄いグレーで表示
              if (task.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(
                    task,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 評価と時間
              Row(
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: Text('評価: ${entry['rating'] ?? '-'}', style: const TextStyle(fontSize: 12))),
                ],
              ),
              const SizedBox(height: 16),

              // コメント
              if ((entry['comment'] ?? '').isNotEmpty) ...[
                const Text('コメント', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry['comment'],
                    style: const TextStyle(height: 1.5, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 写真（サイズ調整）
              if (entry['photoUrl'] != null && (entry['photoUrl'] as String).isNotEmpty) ...[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 400,
                      maxHeight: 300,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        entry['photoUrl'],
                        fit: BoxFit.contain,
                        errorBuilder: (c, o, s) => const SizedBox(
                          height: 100, 
                          child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
            iconColor: Colors.orange,
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
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${e['category'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMain)),
                            const TextSpan(text: ' : '),
                            TextSpan(text: e['skill'] ?? '', style: const TextStyle(color: AppColors.textSub)),
                          ],
                        ),
                        style: const TextStyle(fontSize: 14, height: 1.4),
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
            iconColor: Colors.green,
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
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(period, style: const TextStyle(fontSize: 14, color: AppColors.textMain)),
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
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(period, style: const TextStyle(fontSize: 14, color: AppColors.textMain)),
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
                    style: const TextStyle(height: 1.5, fontSize: 14, color: AppColors.textSub),
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
            style: const TextStyle(height: 1.6, fontSize: 14, color: AppColors.textMain),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                  fontSize: 15,
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
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}