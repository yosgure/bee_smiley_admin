import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assessment_edit_screen.dart';
import 'assessment_detail_screen.dart';
import 'app_theme.dart';

class AssessmentScreen extends StatefulWidget {
  // ★追加: カレンダーなど外部から生徒指定で開く場合に使用
  final String? initialStudentId;
  final String? initialStudentName;

  const AssessmentScreen({
    super.key,
    this.initialStudentId,
    this.initialStudentName,
  });

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  List<String> _classrooms = [];
  String? _selectedClassroom;

  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  
  String? _selectedStudentId;
  String _selectedStudentName = '';

  int _currentTabIndex = 0;

  // ★追加: 外部から生徒指定で開いた場合は教室選択を非表示にするフラグ
  bool _isDirectAccess = false;

  @override
  void initState() {
    super.initState();
    _isDirectAccess = widget.initialStudentId != null;
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final classSnap = await FirebaseFirestore.instance.collection('classrooms').get();
      final classList = classSnap.docs.map((d) => d['name'] as String).toList();
      
      final familySnap = await FirebaseFirestore.instance.collection('families').get();
      final List<Map<String, dynamic>> studentList = [];

      for (var doc in familySnap.docs) {
        final data = doc.data();
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
        
        for (var child in children) {
          final uid = data['uid'];
          final firstName = child['firstName'] ?? '';
          final lastName = data['lastName'] ?? '';
          final firstNameKana = child['firstNameKana'] ?? '';
          final lastNameKana = data['lastNameKana'] ?? '';
          
          final fullName = '$lastName $firstName';
          final fullKana = '$lastNameKana $firstNameKana';
          final classroom = child['classroom'] ?? '';
          
          final id = '${uid}_$firstName'; 

          studentList.add({
            'id': id,
            'name': fullName,
            'kana': fullKana, 
            'classroom': classroom,
          });
        }
      }

      studentList.sort((a, b) => (a['kana'] as String).compareTo(b['kana'] as String));

      if (mounted) {
        setState(() {
          _classrooms = classList;
          _allStudents = studentList;
          
          // ★修正: 外部から生徒指定で開いた場合はその生徒を選択
          if (_isDirectAccess && widget.initialStudentId != null) {
            _selectedStudentId = widget.initialStudentId;
            _selectedStudentName = widget.initialStudentName ?? '';
            
            // その生徒の教室を選択状態にする
            final student = _allStudents.firstWhere(
              (s) => s['id'] == widget.initialStudentId,
              orElse: () => {},
            );
            if (student.isNotEmpty) {
              _selectedClassroom = student['classroom'] as String?;
              _selectedStudentName = student['name'] as String;
            }
            _filterStudentsKeepSelection();
          } else {
            if (_classrooms.isNotEmpty) {
              _selectedClassroom = _classrooms.first;
            }
            _filterStudents();
          }
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _filterStudents() {
    setState(() {
      if (_selectedClassroom == null) {
        _filteredStudents = List.from(_allStudents);
      } else {
        _filteredStudents = _allStudents
            .where((s) => s['classroom'] == _selectedClassroom)
            .toList();
      }
      
      if (_filteredStudents.isNotEmpty) {
        _selectedStudentId = _filteredStudents.first['id'] as String;
        _selectedStudentName = _filteredStudents.first['name'] as String;
      } else {
        _selectedStudentId = null;
        _selectedStudentName = '';
      }
    });
  }

  // ★追加: 選択中の生徒を維持したままフィルタ
  void _filterStudentsKeepSelection() {
    setState(() {
      if (_selectedClassroom == null) {
        _filteredStudents = List.from(_allStudents);
      } else {
        _filteredStudents = _allStudents
            .where((s) => s['classroom'] == _selectedClassroom)
            .toList();
      }
    });
  }

  String _getIndexHeader(String kana) {
    if (kana.isEmpty) return '他';
    final c = kana.codeUnitAt(0);
    if (c >= 0x3042 && c <= 0x304A) return 'あ';
    if (c >= 0x304B && c <= 0x3054) return 'か';
    if (c >= 0x3055 && c <= 0x305E) return 'さ';
    if (c >= 0x305F && c <= 0x3069) return 'た';
    if (c >= 0x306A && c <= 0x306E) return 'な';
    if (c >= 0x306F && c <= 0x307D) return 'は';
    if (c >= 0x307E && c <= 0x3082) return 'ま';
    if (c >= 0x3083 && c <= 0x3088) return 'や';
    if (c >= 0x3089 && c <= 0x308D) return 'ら';
    if (c >= 0x308E && c <= 0x3093) return 'わ';
    return '他';
  }

  List<DropdownMenuItem<String>> _buildStudentDropdownItems() {
    List<DropdownMenuItem<String>> items = [];
    String lastHeader = '';

    for (var s in _filteredStudents) {
      final kana = s['kana'] as String? ?? '';
      final header = _getIndexHeader(kana);

      if (header != lastHeader) {
        items.add(DropdownMenuItem<String>(
          value: 'HEADER_$header',
          enabled: false,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
            ),
            child: Text(
              header,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
        ));
        lastHeader = header;
      }

      items.add(DropdownMenuItem<String>(
        value: s['id'] as String,
        child: Text(s['name'] as String),
      ));
    }
    return items;
  }

  void _onAddPressed() {
    if (_selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('児童を選択してください')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AssessmentEditScreen(
          studentId: _selectedStudentId!,
          studentName: _selectedStudentName,
          type: _currentTabIndex == 0 ? 'weekly' : 'monthly',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(_isDirectAccess ? _selectedStudentName : 'アセスメント'),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          // ★修正: 外部から開いた場合は戻るボタンを表示
          leading: _isDirectAccess 
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: AppColors.textMain),
                onPressed: () => Navigator.pop(context),
              )
            : null,
          bottom: TabBar(
            onTap: (index) => setState(() => _currentTabIndex = index),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSub,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: '週次アセスメント'),
              Tab(text: '月次サマリ'),
            ],
          ),
        ),
        body: Column(
          children: [
            // ★修正: 外部から生徒指定で開いた場合はフィルタエリアを非表示
            if (!_isDirectAccess)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('教室', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSub)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.inputFill,
                              borderRadius: AppStyles.radiusSmall,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedClassroom,
                                isExpanded: true,
                                hint: const Text('教室を選択'),
                                items: _classrooms.map((c) {
                                  return DropdownMenuItem(value: c, child: Text(c));
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedClassroom = val;
                                    _filterStudents();
                                  });
                                },
                              ),
                            ),
                          ),

                          const Text('対象児童', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textSub)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.inputFill,
                              borderRadius: AppStyles.radiusSmall,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStudentId,
                                isExpanded: true,
                                hint: const Text('児童を選択してください'),
                                menuMaxHeight: 400,
                                items: _buildStudentDropdownItems(),
                                onChanged: (val) {
                                  if (val != null && val.startsWith('HEADER_')) return;
                                  final name = _filteredStudents.firstWhere((s) => s['id'] == val)['name'] as String;
                                  setState(() {
                                    _selectedStudentId = val;
                                    _selectedStudentName = name;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            if (!_isDirectAccess) const Divider(height: 1),
            
            // リスト本体（中央寄せ・幅制限）
            Expanded(
              child: _selectedStudentId == null
                  ? const Center(child: Text('児童を選択してください', style: TextStyle(color: AppColors.textSub)))
                  : TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildWeeklyList(),
                        _buildMonthlyList(),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null, 
          onPressed: _onAddPressed,
          backgroundColor: AppColors.primary,
          elevation: 4,
          icon: const Icon(Icons.edit, color: Colors.white),
          label: Text(
            _currentTabIndex == 0 ? '週次アセスメント作成' : '月次サマリ作成',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyList() {
    final query = FirebaseFirestore.instance
        .collection('assessments')
        .where('type', isEqualTo: 'weekly')
        .where('studentId', isEqualTo: _selectedStudentId)
        .orderBy('date', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('データがありません', style: TextStyle(color: AppColors.textSub)));
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
                final records = List<Map<String, dynamic>>.from(data['entries'] ?? []);
                
                final toolNames = records.map((r) => r['tool'] as String? ?? '不明').join('、');

                return Card(
                  child: InkWell(
                    onTap: () {
                       Navigator.push(
                         context,
                         MaterialPageRoute(
                           builder: (context) => AssessmentDetailScreen(doc: doc),
                         ),
                       );
                    },
                    borderRadius: AppStyles.radius,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                DateFormat('yyyy/MM/dd (E)', 'ja').format(date),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              // 下書き/公開バッジ
                              _buildStatusBadge(data['isPublished'] == true),
                              const Spacer(),
                              const Icon(Icons.chevron_right, color: AppColors.textSub),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            toolNames.isEmpty ? '記録なし' : toolNames,
                            style: const TextStyle(color: AppColors.textMain, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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

  Widget _buildMonthlyList() {
    final query = FirebaseFirestore.instance
        .collection('assessments')
        .where('type', isEqualTo: 'monthly')
        .where('studentId', isEqualTo: _selectedStudentId)
        .orderBy('date', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('データがありません', style: TextStyle(color: AppColors.textSub)));
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

                return Card(
                  child: InkWell(
                    onTap: () {
                       Navigator.push(
                         context,
                         MaterialPageRoute(
                           builder: (context) => AssessmentDetailScreen(doc: doc),
                         ),
                       );
                    },
                    borderRadius: AppStyles.radius,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                DateFormat('yyyy年 MM月', 'ja').format(date),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              // 下書き/公開バッジ
                              _buildStatusBadge(data['isPublished'] == true),
                              const Spacer(),
                              const Icon(Icons.chevron_right, color: AppColors.textSub),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data['summary'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSub),
                          ),
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

  // ステータスバッジ
  Widget _buildStatusBadge(bool isPublished) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
    );
  }
}