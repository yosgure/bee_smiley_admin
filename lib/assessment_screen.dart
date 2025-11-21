import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'assessment_edit_screen.dart'; // 作成画面へ遷移用

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  // 選択中のクラスフィルター（'全て' が初期値）
  String _selectedClassroom = '全て';

  // 教室リスト（フィルター用）
  final List<String> _filterOptions = [
    '全て',
    'ビースマイリー湘南藤沢教室',
    'ビースマイリー湘南台教室',
    'ビースマイリープラス湘南藤沢教室',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('アセスメント（児童選択）'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
      // 家族データを取得し、児童単位に分解して表示する
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('families').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }

          final familyDocs = snapshot.data!.docs;

          // 1. 全児童リストを作成（家族データから展開）
          List<Map<String, dynamic>> allChildren = [];
          for (var doc in familyDocs) {
            final familyData = doc.data() as Map<String, dynamic>;
            final String lastName = familyData['lastName'] ?? '';
            final List<dynamic> children = familyData['children'] ?? [];

            for (var child in children) {
              // 児童データに「姓」と「親のID」などを補完してリストに追加
              allChildren.add({
                'fullName': '$lastName ${child['firstName']}', // 表示用フルネーム
                'firstName': child['firstName'],
                'lastName': lastName,
                'classroom': child['classroom'] ?? '未所属',
                'photoUrl': child['photoUrl'],
                'gender': child['gender'],
                'birthDate': child['birthDate'],
              });
            }
          }

          // 2. フィルター適用
          List<Map<String, dynamic>> filteredChildren = allChildren;
          if (_selectedClassroom != '全て') {
            filteredChildren = allChildren
                .where((child) => child['classroom'] == _selectedClassroom)
                .toList();
          }

          // 3. 表示
          return Column(
            children: [
              // フィルターエリア
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filterOptions.map((option) {
                      final isSelected = _selectedClassroom == option;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(option),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() => _selectedClassroom = option);
                            }
                          },
                          selectedColor: Colors.orange.shade100,
                          backgroundColor: Colors.grey.shade100,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.deepOrange : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          side: BorderSide.none,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // 児童リスト
              Expanded(
                child: filteredChildren.isEmpty
                    ? const Center(child: Text('該当する児童がいません', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredChildren.length,
                        itemBuilder: (context, index) {
                          final student = filteredChildren[index];
                          return _buildStudentCard(student);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      
      // 右下のロゴボタン（新規作成用）
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 児童を選択せずに新規作成画面へ
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AssessmentEditScreen()),
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

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange.shade100),
          ),
          child: student['photoUrl'] != null && (student['photoUrl'] as String).isNotEmpty
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: student['photoUrl'],
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.orange),
                  ),
                )
              : const Icon(Icons.person, color: Colors.orange),
        ),
        title: Text(
          student['fullName'],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.school, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    student['classroom'],
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.edit_note, color: Colors.orange),
        onTap: () {
          // タップしたら、その児童が選択された状態で「アセスメント作成画面」へ
          Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (context) => AssessmentEditScreen(
                preSelectedStudentName: student['fullName'],
              ),
            ),
          );
        },
      ),
    );
  }
}