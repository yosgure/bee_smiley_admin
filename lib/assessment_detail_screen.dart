import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart';
import 'app_theme.dart';

class AssessmentDetailScreen extends StatelessWidget {
  final DocumentSnapshot doc;

  const AssessmentDetailScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] as String? ?? 'weekly';
    final isWeekly = type == 'weekly';
    
    final date = (data['date'] as Timestamp).toDate();
    final studentName = data['studentName'] ?? '';
    final classroom = data['classroom'] ?? '';

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
          TextButton.icon(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AssessmentEditScreen(
                    studentId: data['studentId'] ?? '',
                    studentName: studentName,
                    type: type,
                    docId: doc.id,
                    initialData: data,
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
                  _buildWeeklyContent(data)
                else 
                  _buildMonthlyContent(data),
                  
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
              const SizedBox(height: 12),

              // 評価と時間
              Row(
                children: [
                  _buildTag(Icons.star_outline, '評価: ${entry['rating'] ?? '-'}'),
                  const SizedBox(width: 12),
                  _buildTag(Icons.timer_outlined, '時間: ${entry['duration'] ?? '-'}'),
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
    final monthlyEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 非認知能力リスト
        if (monthlyEntries.isNotEmpty) ...[
          const Text('非認知能力・伸びている力', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 8),
          ...monthlyEntries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${e['category'] ?? ''}: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: e['skill'] ?? ''),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 24),
        ],

        // 敏感期
        if (sensitivePeriods.isNotEmpty) ...[
          const Text('敏感期', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sensitivePeriods.map((tag) => Chip(
              label: Text(tag, style: const TextStyle(fontSize: 12, color: Colors.white)),
              backgroundColor: Colors.green,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // 総評
        const Text('今月の様子・総評', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            summary.isEmpty ? 'なし' : summary,
            style: const TextStyle(height: 1.6, fontSize: 15),
          ),
        ),
        const SizedBox(height: 24),

        // 写真（サイズ調整）
        if (photos.isNotEmpty) ...[
          const Text('写真', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: photos.map((url) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            )).toList(),
          ),
        ],
      ],
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