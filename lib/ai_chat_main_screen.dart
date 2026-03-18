import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'ai_chat_screen.dart';
import 'ai_chat_history_screen.dart';

class AiChatMainScreen extends StatefulWidget {
  const AiChatMainScreen({super.key});

  @override
  State<AiChatMainScreen> createState() => _AiChatMainScreenState();
}

class _AiChatMainScreenState extends State<AiChatMainScreen> {
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('families')
          .get();

      final students = <Map<String, dynamic>>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final familyUid = data['uid'] as String? ?? doc.id;
        final lastName = data['lastName'] as String? ?? '';
        final lastNameKana = data['lastNameKana'] as String? ?? '';
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

        for (var child in children) {
          final firstName = child['firstName'] as String? ?? '';
          final classroom = child['classroom'] as String? ?? '';

          if (firstName.isNotEmpty && classroom.contains('プラス')) {
            final studentId = child['studentId'] ?? '${familyUid}_$firstName';
            students.add({
              'name': '$lastName $firstName'.trim(),
              'firstName': firstName,
              'lastName': lastName,
              'lastNameKana': lastNameKana,
              'classroom': classroom,
              'course': child['course'] ?? '',
              'profileUrl': child['profileUrl'] ?? '',
              'familyUid': familyUid,
              'studentId': studentId,
            });
          }
        }
      }

      students.sort((a, b) {
        final kanaA = (a['lastNameKana'] as String?) ?? '';
        final kanaB = (b['lastNameKana'] as String?) ?? '';
        return kanaA.compareTo(kanaB);
      });

      if (mounted) {
        setState(() {
          _students = students;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    final q = _searchQuery.toLowerCase();
    return _students.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final kana = (s['lastNameKana'] as String? ?? '').toLowerCase();
      return name.contains(q) || kana.contains(q);
    }).toList();
  }

  void _openChat(Map<String, dynamic> student) {
    final studentInfo = {
      'firstName': student['firstName'],
      'lastName': student['lastName'],
      'age': '',
      'gender': '',
      'classroom': student['classroom'] ?? 'プラス',
      'diagnosis': '',
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatScreen(
          studentId: student['studentId'],
          studentName: student['name'],
          studentInfo: studentInfo,
        ),
      ),
    );
  }

  void _openHistory(Map<String, dynamic> student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatHistoryScreen(
          studentId: student['studentId'],
          studentName: student['name'],
        ),
      ),
    );
  }

  void _openFreeChat() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatScreen(
          studentId: 'free_chat_$uid',
          studentName: 'フリー相談',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('AI相談'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // フリー相談ボタン
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openFreeChat,
                      icon: const Icon(Icons.smart_toy, size: 20),
                      label: const Text('フリー相談（生徒を指定しない）'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                // 検索バー
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '生徒を検索...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(height: 8),
                // 生徒一覧
                Expanded(
                  child: _filteredStudents.isEmpty
                      ? const Center(child: Text('生徒が見つかりません'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _filteredStudents.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 0),
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            return _StudentChatTile(
                              student: student,
                              onChat: () => _openChat(student),
                              onHistory: () => _openHistory(student),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _StudentChatTile extends StatelessWidget {
  final Map<String, dynamic> student;
  final VoidCallback onChat;
  final VoidCallback onHistory;

  const _StudentChatTile({
    required this.student,
    required this.onChat,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final name = student['name'] as String? ?? '';
    final classroom = student['classroom'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade100,
          child: Text(
            name.isNotEmpty ? name[0] : '?',
            style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(classroom, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.history, color: Colors.grey),
              tooltip: '相談履歴',
              onPressed: onHistory,
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.smart_toy, size: 16),
              label: const Text('相談'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
