import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AssessmentEditScreen extends StatefulWidget {
  final String? preSelectedStudentName;
  final bool isMonthlyMode; // 初期モード指定用

  const AssessmentEditScreen({
    super.key,
    this.preSelectedStudentName,
    this.isMonthlyMode = false,
  });

  @override
  State<AssessmentEditScreen> createState() => _AssessmentEditScreenState();
}

class _AssessmentEditScreenState extends State<AssessmentEditScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedStudentName;
  String _currentClassroom = '';
  
  bool _isMonthlyMode = false;

  List<Map<String, String>> _studentList = [];
  bool _isLoadingStudents = true;

  // --- 週次データ ---
  final List<Map<String, dynamic>> _activities = [
    {
      'title': 'ピンクタワー',
      'duration': '6~10分',
      'evaluation': '◎',
      'comment': '視覚で判断して順番に積み上げることができました。',
      'imageUrl': null,
    },
  ];

  // --- 月間データ用 選択状態管理 ---
  
  // 1. 敏感期（複数選択）
  List<String> _selectedSensitivePeriods = [];
  // Firestoreから取得する敏感期リスト
  List<String> _sensitivePeriodsMaster = []; 

  // 2. 非認知能力（カテゴリと力のペア）
  // 形式: [{'category': '自立心', 'strength': '身支度を自分で行える'}]
  List<Map<String, String>> _selectedStrengths = [];
  
  // 非認知能力マスタ（ご提示いただいたリスト）
  final Map<String, List<String>> _nonCognitiveSkillMaster = {
    '愛着心': ['スムーズに母子分離ができる', '教師や友達を頼ることができる'],
    '自立心': ['身支度を自分で行える', '自分の持ち物の管理ができる'],
    '集中力': ['活動に集中することができる'],
    '社会性': ['教師の話を聞ける', 'お友達の活動を待てる', 'お友達とコミュニケーションを取れる', '自分の意見を伝えることができる', '集団活動に参加することができる'],
    '思いやり': ['お手伝いができる', '他者を気遣うことができる'],
    '責任感': ['片付けができる', '自分の役割を全うできる'],
    'やり抜く力': ['困難を感じても諦めずに取り組める'],
    '自主性': ['積極的に活動に参加できる', '自分で活動を選ぶことができる', '新しい活動に挑戦できる'],
    '自己コントロール': ['ものを丁寧に扱える', '感情をコントロールできる', 'ルールを守ることができる'],
    'ワーキングメモリ': ['工程の長い活動に取り組める', '見通しを持つことができる', '模倣することができる'],
  };

  final TextEditingController _monthlyCommentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isMonthlyMode = widget.isMonthlyMode;

    if (widget.preSelectedStudentName != null) {
      _selectedStudentName = widget.preSelectedStudentName;
      _isLoadingStudents = false;
    } else {
      _fetchStudents();
    }
    _fetchSensitivePeriods(); // 敏感期マスタを取得
  }

  // Firestoreから敏感期マスタを取得
  Future<void> _fetchSensitivePeriods() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('sensitive_periods').get();
      final periods = snapshot.docs.map((doc) => doc['name'] as String).toList();
      if (mounted) {
        setState(() {
          _sensitivePeriodsMaster = periods;
          // マスタが空ならデフォルトを入れる（テスト用）
          if (_sensitivePeriodsMaster.isEmpty) {
            _sensitivePeriodsMaster = ['秩序の敏感期', '運動の敏感期', '言語の敏感期', '感覚の敏感期', '数の敏感期', '模倣の敏感期'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching sensitive periods: $e');
    }
  }

  Future<void> _fetchStudents() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('families').get();
      List<Map<String, String>> loadedStudents = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String lastName = data['lastName'] ?? '';
        final List<dynamic> children = data['children'] ?? [];

        for (var child in children) {
          final String firstName = child['firstName'] ?? '';
          final String classroom = child['classroom'] ?? '';
          final String fullName = '$lastName $firstName'.trim();
          if (fullName.isNotEmpty) {
            loadedStudents.add({'name': fullName, 'classroom': classroom});
          }
        }
      }

      if (mounted) {
        setState(() {
          _studentList = loadedStudents;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  void _onStudentSelected(String? name) {
    if (name == null) return;
    final studentData = _studentList.firstWhere(
      (s) => s['name'] == name,
      orElse: () => {'name': name, 'classroom': ''},
    );
    setState(() {
      _selectedStudentName = name;
      _currentClassroom = studentData['classroom'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = 'アセスメント作成';
    if (_selectedStudentName != null) {
      appBarTitle = '$_selectedStudentName';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 80,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる', style: TextStyle(color: Colors.blue, fontSize: 16)),
        ),
        centerTitle: true,
        title: Text(
          appBarTitle,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: _saveAssessment,
            child: const Text('保存', style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // モード切り替えスイッチ
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      _buildModeButton('週次記録', !_isMonthlyMode),
                      _buildModeButton('月間総括', _isMonthlyMode),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 日付選択 (月間モードなら年月のみ表示)
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      // 月間モードでも内部的には特定の日付を持つが、表示を変える
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.orange, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _isMonthlyMode
                            ? DateFormat('yyyy年 M月').format(_selectedDate) // 月間用
                            : DateFormat('yyyy年 M月 d日').format(_selectedDate), // 週次用
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
                
                if (widget.preSelectedStudentName == null) ...[
                  const Divider(height: 24),
                  if (_isLoadingStudents)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedStudentName,
                      decoration: const InputDecoration(
                        labelText: '対象児童',
                        prefixIcon: Icon(Icons.face),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      hint: const Text('児童を選択してください'),
                      items: _studentList.map((student) {
                        return DropdownMenuItem<String>(
                          value: student['name'],
                          child: Text(student['name']!),
                        );
                      }).toList(),
                      onChanged: _onStudentSelected,
                    ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          if (_isMonthlyMode)
            _buildMonthlyForm()
          else
            _buildWeeklyForm(),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildModeButton(String text, bool isActive) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isMonthlyMode = (text == '月間総括');
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2)] : [],
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.black : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // --- 週次フォーム ---
  Widget _buildWeeklyForm() {
    return Column(
      children: [
        ..._activities.asMap().entries.map((entry) => _buildActivityCard(entry.key, entry.value)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _activities.add({
                  'title': '', 'duration': '0~5分', 'evaluation': '○', 'comment': '', 'imageUrl': null,
                });
              });
            },
            icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
            label: const Text('教具を追加', style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCard(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: TextEditingController(text: item['title']),
            decoration: const InputDecoration(hintText: '教具名', border: InputBorder.none, filled: true, fillColor: Color(0xFFF9F9F9)),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            onChanged: (val) => item['title'] = val,
          ),
          const SizedBox(height: 16),
          _buildSegmentedControl(
            options: ['0~5分', '6~10分', '11~20分', '20分以上'],
            selectedValue: item['duration'],
            onSelected: (val) => setState(() => item['duration'] = val),
          ),
          const SizedBox(height: 12),
          _buildSegmentedControl(
            options: ['◎', '○', '△'],
            selectedValue: item['evaluation'],
            onSelected: (val) => setState(() => item['evaluation'] = val),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: item['comment']),
            maxLines: null,
            decoration: const InputDecoration(hintText: 'コメント', border: InputBorder.none),
            onChanged: (val) => item['comment'] = val,
          ),
        ],
      ),
    );
  }

  // --- 月間フォーム ---
  Widget _buildMonthlyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 敏感期選択エリア
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text('敏感期 (複数選択可)', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _sensitivePeriodsMaster.map((period) {
              final isSelected = _selectedSensitivePeriods.contains(period);
              return FilterChip(
                label: Text(period),
                selected: isSelected,
                onSelected: (bool selected) {
                  setState(() {
                    if (selected) {
                      _selectedSensitivePeriods.add(period);
                    } else {
                      _selectedSensitivePeriods.remove(period);
                    }
                  });
                },
                selectedColor: Colors.purple.shade100,
                checkmarkColor: Colors.purple,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.purple.shade900 : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // 2. 非認知能力選択エリア (アコーディオン)
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text('非認知能力・伸びている力 (複数選択可)', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias, // 角丸からはみ出さないように
          child: Column(
            children: _nonCognitiveSkillMaster.keys.map((category) {
              final strengths = _nonCognitiveSkillMaster[category]!;
              
              // このカテゴリ内で選択されている数
              final selectedCount = _selectedStrengths.where((s) => s['category'] == category).length;

              return ExpansionTile(
                title: Text(
                  category,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selectedCount > 0 ? Colors.orange : Colors.black87,
                  ),
                ),
                trailing: selectedCount > 0 
                    ? CircleAvatar(
                        radius: 12, 
                        backgroundColor: Colors.orange, 
                        child: Text(selectedCount.toString(), style: const TextStyle(fontSize: 12, color: Colors.white)))
                    : const Icon(Icons.keyboard_arrow_down),
                children: strengths.map((strength) {
                  final isChecked = _selectedStrengths.any((s) => s['category'] == category && s['strength'] == strength);
                  
                  return CheckboxListTile(
                    value: isChecked,
                    title: Text(strength, style: const TextStyle(fontSize: 14)),
                    activeColor: Colors.orange,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedStrengths.add({'category': category, 'strength': strength});
                        } else {
                          _selectedStrengths.removeWhere((s) => s['category'] == category && s['strength'] == strength);
                        }
                      });
                    },
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // 3. 総括コメント
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text('総括コメント', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _monthlyCommentController,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '今月の全体的な様子や成長した点などを記述してください...',
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedControl({required List<String> options, required String selectedValue, required Function(String) onSelected}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFEEEEEF), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: options.map((option) {
          final isSelected = option == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(option),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2)] : [],
                ),
                alignment: Alignment.center,
                child: Text(option, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _saveAssessment() async {
    if (_selectedStudentName == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('対象の児童を選択してください')));
      return;
    }

    try {
      final Map<String, dynamic> saveData = {
        'studentName': _selectedStudentName,
        'classroom': _currentClassroom,
        'createdAt': Timestamp.fromDate(_selectedDate),
        'type': _isMonthlyMode ? 'monthly' : 'weekly',
      };

      if (_isMonthlyMode) {
        // 月間データ保存（構造を変更）
        saveData['monthlySummary'] = [{
          'sensitivePeriods': _selectedSensitivePeriods, // 敏感期リスト
          'strengths': _selectedStrengths, // 非認知能力（カテゴリと力のペア）
          'comment': _monthlyCommentController.text,
        }];
      } else {
        // 週次データ保存
        saveData['weeklyRecords'] = _activities.map((act) => {
          'tool': act['title'],
          'time': act['duration'],
          'evaluation': act['evaluation'],
          'comment': act['comment'],
        }).toList();
      }

      await FirebaseFirestore.instance.collection('assessments').add(saveData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }
}