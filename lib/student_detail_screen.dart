import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart'; 

class StudentDetailScreen extends StatefulWidget {
  final String studentId; // format: "parentUid_childName"
  final String studentName;

  const StudentDetailScreen({
    super.key,
    required this.studentId,
    required this.studentName,
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
  bool _isLoadingInfo = true;

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
              _isLoadingInfo = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingInfo = false);
    }
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
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('アセスメント詳細', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
      ),
      body: Column(
        children: [
          _buildStudentHeader(),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.orange,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.orange,
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
      
      floatingActionButton: FloatingActionButton.extended(
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
        backgroundColor: Colors.orange,
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
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
            child: const Icon(Icons.person, size: 36, color: Colors.orange),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.studentName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                      Text(_birthDateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Icon(icon, size: 12, color: Colors.black54),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
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
        // ★修正: インデックスエラーを表示
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                'エラーが発生しました。\nFirestoreのインデックスが必要です。以下のURLから作成してください:\n\n${snapshot.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
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
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final docId = docs[index].id;
            
            final date = (data['date'] as Timestamp).toDate();
            String dateStr;
            if (type == 'weekly') {
              // ★修正: 週次も特定の日付として表示
              dateStr = DateFormat('yyyy/MM/dd (E)', 'ja').format(date);
            } else {
              dateStr = DateFormat('yyyy年 M月度').format(date);
            }

            final staffName = data['staffName'] ?? '不明';
            final content = data['content'] ?? data['summary'] ?? '';
            final skills = List<String>.from(data['skills'] ?? []);

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssessmentEditScreen(
                        studentId: widget.studentId,
                        studentName: widget.studentName,
                        type: type,
                        docId: docId,
                        initialData: data,
                      ),
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
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: type == 'weekly' ? Colors.blue.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              type == 'weekly' ? '週次' : '月次',
                              style: TextStyle(
                                fontSize: 11,
                                color: type == 'weekly' ? Colors.blue.shade800 : Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('記入: $staffName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text(
                        content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: skills.map((skill) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('#$skill', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}