import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart';
import 'assessment_detail_screen.dart';
import 'app_theme.dart';
import 'ai_chat_screen.dart';
import 'main.dart';
import 'classroom_utils.dart';

class StudentDetailScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final VoidCallback? onClose;

  const StudentDetailScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.onClose,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 生徒情報
  String _gender = '';
  String _birthDateStr = '';
  String _ageStr = '';
  String _classroom = '';
  String _diagnosis = '';
  bool _isLoadingInfo = true;

  // 支援計画データ（AI相談用）
  Map<String, dynamic>? _supportPlan;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {}); 
    });
    _fetchStudentInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchStudentInfo() async {
    try {
      final parts = widget.studentId.split('_');
      if (parts.length < 2) {
        setState(() => _isLoadingInfo = false);
        return;
      }
      final parentUid = parts[0];
      final childName = parts.sublist(1).join('_');

      final snapshot = await FirebaseFirestore.instance
          .collection('families')
          .where('uid', isEqualTo: parentUid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

        final child = children.firstWhere(
          (c) => (c['firstName'] ?? '') == childName,
          orElse: () => {},
        );

        if (child.isNotEmpty) {
          final birthDate = child['birthDate'] ?? '';
          if (mounted) {
            setState(() {
              _gender = child['gender'] ?? '';
              _birthDateStr = birthDate;
              _ageStr = _calculateAge(birthDate);
              _classroom = classroomsDisplayText(child);
              _diagnosis = child['diagnosis'] ?? '';
              _isLoadingInfo = false;
            });
          }
        }
      }

      // 支援計画を取得
      _fetchSupportPlan();
    } catch (e) {
      if (mounted) setState(() => _isLoadingInfo = false);
    }
  }

  Future<void> _fetchSupportPlan() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('support_plans')
          .where('studentId', isEqualTo: widget.studentId)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty && mounted) {
        setState(() {
          _supportPlan = snap.docs.first.data();
        });
      }
    } catch (e) {
      debugPrint('Error fetching support plan: $e');
    }
  }

  void _openAiChat() {
    // 生徒情報をまとめる
    final studentInfo = {
      'firstName': widget.studentName.split(' ').length > 1
          ? widget.studentName.split(' ').last
          : widget.studentName,
      'lastName': widget.studentName.split(' ').length > 1
          ? widget.studentName.split(' ').first
          : '',
      'age': _ageStr,
      'gender': _gender,
      'classroom': _classroom,
      'diagnosis': _diagnosis.isNotEmpty ? _diagnosis : _supportPlan?['diagnosis'],
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatScreen(
          studentId: widget.studentId,
          studentName: widget.studentName,
          studentInfo: studentInfo,
          supportPlan: _supportPlan,
        ),
      ),
    );
  }

  String _calculateAge(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final parts = dateStr.split('/');
      if (parts.length != 3) return '';
      final birth = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final now = DateTime.now();
      int years = now.year - birth.year;
      int months = now.month - birth.month;
      if (now.day < birth.day) months--;
      if (months < 0) {
        years--;
        months += 12;
      }
      return '${years}歳${months}ヶ月';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBgAlt,
      appBar: AppBar(
        title: Text(widget.studentName),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: context.colors.textSecondary),
          onPressed: () {
            if (widget.onClose != null) {
              AdminShell.hideOverlay(context);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.colors.borderMedium, height: 1),
        ),
      ),
      body: Column(
        children: [
          _buildStudentHeader(),
          Container(
            color: context.colors.cardBg,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: context.colors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: '週次アセスメント'),
                Tab(text: '月次サマリ'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAssessmentList(type: 'weekly'),
                _buildAssessmentList(type: 'monthly'),
              ],
            ),
          ),
        ],
      ),
      
      floatingActionButton: FloatingActionButton.extended(heroTag: null, 
        onPressed: () {
          final type = _tabController.index == 0 ? 'weekly' : 'monthly';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AssessmentEditScreen(
                studentId: widget.studentId,
                studentName: widget.studentName,
                type: type,
              ),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.edit, color: Colors.white),
        label: Text(
          _tabController.index == 0 ? '週次アセスメント作成' : '月次サマリ作成',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStudentHeader() {
    return Container(
      color: context.colors.cardBg,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.person, size: 36, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.studentName, style: const TextStyle(fontSize: AppTextSize.xl, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (_isLoadingInfo)
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Row(
                    children: [
                      _buildInfoTag(Icons.cake, _ageStr),
                      const SizedBox(width: 8),
                      _buildInfoTag(Icons.wc, _gender),
                      const SizedBox(width: 8),
                      Text(_birthDateStr, style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.small)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTag(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: context.colors.chipBg, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Icon(icon, size: 12, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildAssessmentList({required String type}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assessments')
          .where('studentId', isEqualTo: widget.studentId)
          .where('type', isEqualTo: type)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                'エラーが発生しました。\nFirestoreのインデックスが必要です。以下のURLから作成してください:\n\n${snapshot.error}',
                style: const TextStyle(color: AppColors.error, fontSize: AppTextSize.small),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              type == 'weekly' ? '週次アセスメントはまだありません' : '月次サマリはまだありません',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                
                final date = (data['date'] as Timestamp).toDate();
                String dateStr;
                if (type == 'weekly') {
                  dateStr = DateFormat('yyyy/MM/dd (E)', 'ja').format(date);
                } else {
                  dateStr = DateFormat('yyyy年 M月度').format(date);
                }

                // 週次: 教具名を表示
                String subtitle = '';
                if (type == 'weekly') {
                  final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
                  subtitle = entries.map((e) => e['tool'] as String? ?? '').where((t) => t.isNotEmpty).join('、');
                } else {
                  subtitle = data['summary'] ?? '';
                }

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.colors.borderLight),
                  ),
                  child: InkWell(
                    onTap: () {
                      // ★修正: AssessmentDetailScreenに遷移（記録タブと同じ）
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AssessmentDetailScreen(doc: doc),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dateStr,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm),
                              ),
                              Icon(Icons.chevron_right, color: context.colors.textSecondary),
                            ],
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.colors.textPrimary, fontSize: AppTextSize.bodyMd),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}