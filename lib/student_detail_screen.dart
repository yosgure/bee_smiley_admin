import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'assessment_edit_screen.dart';

class StudentDetailScreen extends StatefulWidget {
  final String studentName;
  final String assessmentId;

  const StudentDetailScreen({
    super.key,
    required this.studentName,
    required this.assessmentId,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final DocumentReference assessmentDoc =
        FirebaseFirestore.instance.collection('assessments').doc(widget.assessmentId);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.studentName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: assessmentDoc.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('データが見つかりません'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final weeklyData = List<Map<String, dynamic>>.from(data['weeklyRecords'] ?? []);
          final monthlyData = List<Map<String, dynamic>>.from(data['monthlySummary'] ?? []);
          
          final Timestamp? createdAt = data['createdAt'];
          final DateTime date = createdAt?.toDate() ?? DateTime.now();

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1)),
                      ],
                    ),
                    labelColor: Colors.black87,
                    unselectedLabelColor: Colors.grey.shade600,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: '週次記録'),
                      Tab(text: '月間総括'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _WeeklyReportView(records: weeklyData, date: date),
                    _MonthlyReportView(summaries: monthlyData, date: date),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (context) => AssessmentEditScreen(
                preSelectedStudentName: widget.studentName,
              ),
            ),
          );
        },
        backgroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo_beesmileymark.png'),
        ),
      ),
    );
  }
}

// ==========================================
// 1. 週次レポート画面
// ==========================================
class _WeeklyReportView extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final DateTime date;
  const _WeeklyReportView({required this.records, required this.date});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(child: Text('週次記録がありません', style: TextStyle(color: Colors.grey)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            DateFormat('yyyy年 M月 d日').format(date),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        ...records.map((item) {
          final String? imageUrl = item['imageUrl'];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['tool'] ?? '名称なし',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (item['time'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                        child: Text(item['time'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                    if (item['time'] != null) const SizedBox(width: 12),
                    if (item['evaluation'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                        child: Text(item['evaluation'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if ((item['comment'] ?? '').isNotEmpty)
                  Text(item['comment'], style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87)),
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: imageUrl, width: double.infinity, height: 200, fit: BoxFit.cover, placeholder: (context, url) => Container(height: 200, color: Colors.grey.shade100), errorWidget: (context, url, error) => const SizedBox.shrink()),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ==========================================
// 2. 月間総括画面 (★ここを大幅修正)
// ==========================================
class _MonthlyReportView extends StatelessWidget {
  final List<Map<String, dynamic>> summaries;
  final DateTime date;
  
  const _MonthlyReportView({required this.summaries, required this.date});

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const Center(child: Text('月間総括がありません', style: TextStyle(color: Colors.grey)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 年月ヘッダー
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 4),
          child: Text(
            DateFormat('yyyy年 M月').format(date),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
        ),

        ...summaries.map((data) {
          // データの取り出し（新しい構造に対応）
          final sensitivePeriods = List<String>.from(data['sensitivePeriods'] ?? []);
          final strengthsList = List<dynamic>.from(data['strengths'] ?? []);
          final comment = data['comment'] ?? '';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 敏感期セクション
              if (sensitivePeriods.isNotEmpty) ...[
                const _SectionHeader(title: '敏感期', icon: Icons.hourglass_top, color: Colors.purple),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sensitivePeriods.map((period) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.purple.shade100),
                    ),
                    child: Text(
                      period,
                      style: TextStyle(color: Colors.purple.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // 2. 非認知能力セクション
              if (strengthsList.isNotEmpty) ...[
                const _SectionHeader(title: '伸びている力', icon: Icons.psychology, color: Colors.orange),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildStrengthList(strengthsList),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 3. 総括コメント
              if (comment.isNotEmpty) ...[
                const _SectionHeader(title: '総括コメント', icon: Icons.comment, color: Colors.blue),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    comment,
                    style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87),
                  ),
                ),
              ],
              
              const SizedBox(height: 40),
            ],
          );
        }),
      ],
    );
  }

  // 非認知能力をカテゴリごとにまとめて表示
  List<Widget> _buildStrengthList(List<dynamic> list) {
    final Map<String, List<String>> grouped = {};
    for (var item in list) {
      final cat = item['category'] as String? ?? 'その他';
      final str = item['strength'] as String? ?? '';
      if (!grouped.containsKey(cat)) {
        grouped[cat] = [];
      }
      grouped[cat]!.add(str);
    }

    return grouped.entries.map((entry) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.key,
              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          ...entry.value.map((str) => Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(color: Colors.grey)),
                Expanded(child: Text(str, style: const TextStyle(fontSize: 14))),
              ],
            ),
          )),
          const SizedBox(height: 16),
        ],
      );
    }).toList();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({required this.title, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54)),
      ],
    );
  }
}