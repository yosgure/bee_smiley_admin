import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'skeleton_loading.dart';

class ParentAssessmentScreen extends StatefulWidget {
  final String? childId;
  final String childName;
  final String? childPhotoUrl;
  final List<Map<String, dynamic>> allChildren;
  final int selectedChildIndex;
  final Function(int)? onChildChanged;

  const ParentAssessmentScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.childPhotoUrl,
    this.allChildren = const [],
    this.selectedChildIndex = 0,
    this.onChildChanged,
  });

  @override
  State<ParentAssessmentScreen> createState() => _ParentAssessmentScreenState();
}

class _ParentAssessmentScreenState extends State<ParentAssessmentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 選択中のアセスメント
  String? _selectedAssessmentId;
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.childId == null) {
      return const Center(
        child: Text('お子さまの情報がありません', style: TextStyle(color: Colors.grey)),
      );
    }

    // 詳細画面
    if (_selectedAssessmentId != null && _selectedType != null) {
      return _buildDetailScreen();
    }

    // 一覧画面
    return Column(
      children: [
        _buildHeader(),
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: '週次記録'),
              Tab(text: '月次サマリ'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDateList(type: 'weekly'),
              _buildDateList(type: 'monthly'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({bool showBack = false}) {
    final hasMultipleChildren = widget.allChildren.length > 1;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (showBack) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              onPressed: () => setState(() {
                _selectedAssessmentId = null;
                _selectedType = null;
              }),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 顔写真
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: widget.childPhotoUrl != null && widget.childPhotoUrl!.isNotEmpty
                      ? NetworkImage(widget.childPhotoUrl!)
                      : null,
                  child: widget.childPhotoUrl == null || widget.childPhotoUrl!.isEmpty
                      ? const Icon(Icons.child_care, size: 20, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: 10),
                
                // 子どもの名前
                if (hasMultipleChildren && !showBack)
                  PopupMenuButton<int>(
                    onSelected: (index) {
                      widget.onChildChanged?.call(index);
                    },
                    offset: const Offset(0, 40),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.childName}のアセスメント',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                    itemBuilder: (context) {
                      return widget.allChildren.asMap().entries.map((entry) {
                        final index = entry.key;
                        final child = entry.value;
                        final firstName = child['firstName'] ?? '';
                        final photoUrl = child['photoUrl'];
                        final isSelected = index == widget.selectedChildIndex;

                        return PopupMenuItem<int>(
                          value: index,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.primary.withOpacity(0.1),
                                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null || photoUrl.isEmpty
                                    ? const Icon(Icons.child_care, size: 14, color: AppColors.primary)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                firstName,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              if (isSelected) ...[
                                const Spacer(),
                                const Icon(Icons.check, color: AppColors.primary, size: 18),
                              ],
                            ],
                          ),
                        );
                      }).toList();
                    },
                  )
                else
                  Text(
                    '${widget.childName}のアセスメント',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
                  ),
              ],
            ),
          ),
          if (showBack) const SizedBox(width: 48), // バランス用
        ],
      ),
    );
  }

  /// 日付一覧
  Widget _buildDateList({required String type}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assessments')
          .where('studentId', isEqualTo: widget.childId)
          .where('type', isEqualTo: type)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'データの取得に失敗しました\n${snapshot.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AssessmentSkeleton();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type == 'weekly' ? Icons.assignment_outlined : Icons.summarize_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  type == 'weekly' ? '週次記録はまだありません' : '月次サマリはまだありません',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildDateCard(doc.id, data, type);
          },
        );
      },
    );
  }

  /// 日付カード
  Widget _buildDateCard(String docId, Map<String, dynamic> data, String type) {
    final date = (data['date'] as Timestamp).toDate();
    String dateStr;
    if (type == 'weekly') {
      dateStr = DateFormat('yyyy年M月d日(E)', 'ja').format(date);
    } else {
      dateStr = DateFormat('yyyy年 M月', 'ja').format(date);
    }

    // サブタイトル
    String subtitle = '';
    if (type == 'weekly') {
      final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
      subtitle = '${entries.length}件の活動';
    } else {
      final monthlyEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);
      final sensitivePeriods = List<String>.from(data['sensitivePeriods'] ?? []);
      subtitle = '${monthlyEntries.length}項目の評価・${sensitivePeriods.length}つの敏感期';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: () => setState(() {
          _selectedAssessmentId = docId;
          _selectedType = type;
        }),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            type == 'weekly' ? Icons.edit_calendar : Icons.assessment,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          dateStr,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }

  /// 詳細画面
  Widget _buildDetailScreen() {
    return Column(
      children: [
        _buildHeader(showBack: true),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('assessments')
                .doc(_selectedAssessmentId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const AssessmentSkeleton();
              }

              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data == null) {
                return const Center(child: Text('データが見つかりません'));
              }

              if (_selectedType == 'weekly') {
                return _buildWeeklyDetail(data);
              } else {
                return _buildMonthlyDetail(data);
              }
            },
          ),
        ),
      ],
    );
  }

  /// 週次詳細
  Widget _buildWeeklyDetail(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp).toDate();
    final dateStr = DateFormat('yyyy年M月d日(E)', 'ja').format(date);
    final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日付ヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // 活動リスト
          ...entries.map((entry) => _buildWeeklyEntryCard(entry)),
          
          if (entries.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('活動記録がありません', style: TextStyle(color: Colors.grey)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeeklyEntryCard(Map<String, dynamic> entry) {
    final tool = entry['tool'] ?? '';
    final rating = entry['rating'] ?? '';
    final duration = entry['duration'] ?? '';
    final comment = entry['comment'] ?? '';
    final photoUrl = entry['photoUrl'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    tool,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 評価と時間
            Row(
              children: [
                _buildTag(Icons.star_outline, '評価: $rating'),
                const SizedBox(width: 12),
                if (duration.isNotEmpty)
                  _buildTag(Icons.timer_outlined, '時間: $duration'),
              ],
            ),
            
            // コメント
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(comment, style: const TextStyle(fontSize: 14, height: 1.5)),
              ),
            ],
            
            // 写真
            if (photoUrl != null && photoUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _showImagePreview(photoUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photoUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      height: 100,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 月次詳細
  Widget _buildMonthlyDetail(Map<String, dynamic> data) {
    final date = (data['date'] as Timestamp).toDate();
    final dateStr = DateFormat('yyyy年 M月', 'ja').format(date);
    final summary = data['summary'] ?? '';
    final sensitivePeriods = List<String>.from(data['sensitivePeriods'] ?? []);
    final monthlyEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月ヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // 非認知能力リスト
          if (monthlyEntries.isNotEmpty) ...[
            const Text(
              '非認知能力・伸びている力',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            ...monthlyEntries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, size: 18, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${e['category'] ?? ''}: ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: e['skill'] ?? ''),
                        ],
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 20),
          ],

          // 敏感期
          if (sensitivePeriods.isNotEmpty) ...[
            const Text(
              '敏感期',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 20),
          ],
          
          // 総評
          const Text(
            '今月の様子・総評',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              summary.isEmpty ? 'なし' : summary,
              style: const TextStyle(height: 1.6, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 画像
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => Container(
                  height: 200,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.broken_image, color: Colors.white, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ボタン
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _downloadImage(url),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('保存'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadImage(String url) async {
    try {
      // Web: 新しいタブで開く
      // ignore: deprecated_member_use
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ダウンロードに失敗しました: $e')),
        );
      }
    }
  }
}