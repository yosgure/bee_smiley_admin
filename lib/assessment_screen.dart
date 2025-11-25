import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'student_detail_screen.dart'; // 詳細画面へ遷移用

class AssessmentScreen extends StatefulWidget {
  // main.dart から const AssessmentScreen() で呼び出せるように引数なしにする
  const AssessmentScreen({super.key});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  // 状態管理
  String? _selectedClassroom;
  List<String> _myClassrooms = [];
  bool _isLoadingStaffInfo = true;
  String _searchText = '';
  
  // 児童データ
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];

  @override
  void initState() {
    super.initState();
    _fetchStaffInfo();
  }

  // 1. ログインスタッフの担当教室を取得
  Future<void> _fetchStaffInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final classrooms = List<String>.from(data['classrooms'] ?? []);
        
        if (mounted) {
          setState(() {
            _myClassrooms = classrooms;
            if (_myClassrooms.isNotEmpty) {
              _selectedClassroom = _myClassrooms.first; // 初期選択
            }
            _isLoadingStaffInfo = false;
          });
        }
        
        // 教室取得後に生徒データを読み込む
        _fetchStudents();
      } else {
        if (mounted) setState(() => _isLoadingStaffInfo = false);
      }
    } catch (e) {
      debugPrint('Error fetching staff info: $e');
      if (mounted) setState(() => _isLoadingStaffInfo = false);
    }
  }

  // 2. 全児童データを取得して整形
  Future<void> _fetchStudents() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('families').get();
      final List<Map<String, dynamic>> loadedStudents = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        // 保護者情報
        final parentLastName = data['lastName'] ?? '';
        final parentLastNameKana = data['lastNameKana'] ?? ''; 
        
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
        
        for (var child in children) {
          final childName = child['firstName'] ?? '';
          final childNameKana = child['firstNameKana'] ?? '';
          final classroom = child['classroom'] ?? '';
          
          // フルネーム作成
          final fullName = '$parentLastName $childName';
          final fullKana = '$parentLastNameKana $childNameKana';

          // ユニークID
          final uniqueId = '${data['uid']}_$childName';

          loadedStudents.add({
            'id': uniqueId,
            'name': fullName,
            'kana': fullKana, 
            'classroom': classroom,
            'gender': child['gender'] ?? '',
            'birthDate': child['birthDate'] ?? '',
          });
        }
      }

      // あいうえお順にソート
      loadedStudents.sort((a, b) => (a['kana'] as String).compareTo(b['kana'] as String));

      if (mounted) {
        setState(() {
          _allStudents = loadedStudents;
          _applyFilter(); // 初期フィルタ適用
        });
      }
    } catch (e) {
      debugPrint('Error fetching students: $e');
    }
  }

  // 3. 教室選択と検索ワードでフィルタリング
  void _applyFilter() {
    setState(() {
      _filteredStudents = _allStudents.where((s) {
        // 教室フィルタ
        if (_selectedClassroom != null && s['classroom'] != _selectedClassroom) {
          return false;
        }
        // 検索ワードフィルタ
        if (_searchText.isNotEmpty) {
          final name = s['name'].toString();
          final kana = s['kana'].toString();
          if (!name.contains(_searchText) && !kana.contains(_searchText)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  // あいうえお順ヘッダー判定
  String _getIndexHeader(String kana) {
    if (kana.isEmpty) return '他';
    final firstChar = kana.substring(0, 1);
    if (firstChar.compareTo('あ') >= 0 && firstChar.compareTo('お') <= 0) return 'あ';
    if (firstChar.compareTo('か') >= 0 && firstChar.compareTo('こ') <= 0) return 'か';
    if (firstChar.compareTo('さ') >= 0 && firstChar.compareTo('そ') <= 0) return 'さ';
    if (firstChar.compareTo('た') >= 0 && firstChar.compareTo('と') <= 0) return 'た';
    if (firstChar.compareTo('な') >= 0 && firstChar.compareTo('の') <= 0) return 'な';
    if (firstChar.compareTo('は') >= 0 && firstChar.compareTo('ほ') <= 0) return 'は';
    if (firstChar.compareTo('ま') >= 0 && firstChar.compareTo('も') <= 0) return 'ま';
    if (firstChar.compareTo('や') >= 0 && firstChar.compareTo('よ') <= 0) return 'や';
    if (firstChar.compareTo('ら') >= 0 && firstChar.compareTo('ろ') <= 0) return 'ら';
    if (firstChar.compareTo('わ') >= 0 && firstChar.compareTo('ん') <= 0) return 'わ';
    return '他';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('アセスメント'),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
      body: _isLoadingStaffInfo
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // --- コントロールエリア ---
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 教室選択
                      if (_myClassrooms.isEmpty)
                        const SizedBox(
                          width: double.infinity,
                          child: Text('担当教室が登録されていません', style: TextStyle(color: Colors.red)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedClassroom,
                              isExpanded: true,
                              hint: const Text('教室を選択'),
                              items: _myClassrooms.map((room) {
                                return DropdownMenuItem(
                                  value: room,
                                  child: Text(room, style: const TextStyle(fontWeight: FontWeight.bold)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedClassroom = val;
                                  _applyFilter();
                                });
                              },
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 12),
                      
                      // 検索バー
                      TextField(
                        decoration: InputDecoration(
                          hintText: '児童名で検索...',
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchText = val;
                            _applyFilter();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                
                // --- 児童リスト ---
                Expanded(
                  child: _filteredStudents.isEmpty
                      ? Center(
                          child: Text(
                            _selectedClassroom == null ? '教室を選択してください' : '該当する児童がいません',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            
                            // ヘッダー判定
                            final header = _getIndexHeader(student['kana']);
                            bool showHeader = true;
                            if (index > 0) {
                              final prevHeader = _getIndexHeader(_filteredStudents[index - 1]['kana']);
                              if (prevHeader == header) showHeader = false;
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                                    child: Text(
                                      header,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                
                                Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.orange.shade100,
                                      child: const Icon(Icons.person, color: Colors.orange),
                                    ),
                                    title: Text(
                                      student['name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    subtitle: Text(student['kana'], style: const TextStyle(fontSize: 12)),
                                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => StudentDetailScreen(
                                            studentId: student['id'],
                                            studentName: student['name'],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}