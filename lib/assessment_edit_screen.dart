import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class AssessmentEditScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String type; // 'weekly' or 'monthly'
  final String? docId;
  final Map<String, dynamic>? initialData;

  const AssessmentEditScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.type,
    this.docId,
    this.initialData,
  });

  @override
  State<AssessmentEditScreen> createState() => _AssessmentEditScreenState();
}

class _AssessmentEditScreenState extends State<AssessmentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late Future<void> _initializationFuture;
  
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  // --- 週次用データ ---
  List<Map<String, dynamic>> _weeklyEntries = [];
  List<Map<String, String>> _toolList = [];
  final List<String> _durationOptions = ['0〜5分', '6〜10分', '11〜20分', '20分以上'];

  // --- 月次用データ ---
  final TextEditingController _monthlySummaryController = TextEditingController();
  final Set<String> _selectedSensitivePeriods = {}; 
  
  // 非認知能力と伸びている力のペアリスト
  List<Map<String, String?>> _monthlyEntries = [];

  // マスタデータ
  Map<String, List<String>> _nonCognitiveSkillMap = {};
  List<String> _sensitivePeriodMaster = [];

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _fetchMasters();
    
    if (widget.initialData != null) {
      _initializeEditData();
    } else {
      _initializeNewData();
    }
  }

  Future<void> _fetchMasters() async {
    try {
      if (widget.type == 'weekly') {
        final toolsSnap = await FirebaseFirestore.instance.collection('tools').get();
        _toolList = toolsSnap.docs.map((d) {
          final data = d.data();
          return {
            'name': (data['name'] ?? '') as String,
            'furigana': (data['furigana'] ?? '') as String,
          };
        }).toList();

        if (_toolList.isEmpty) {
          _toolList = [
            {'name': '円柱さし', 'furigana': 'えんちゅうさし'},
            {'name': 'ピンクタワー', 'furigana': 'ぴんくたわー'},
          ];
        }
        
        _toolList.sort((a, b) {
          final ka = a['furigana'] ?? a['name'] ?? '';
          final kb = b['furigana'] ?? b['name'] ?? '';
          return ka.compareTo(kb);
        });

      } else {
        // 月次マスタ取得
        final ncSnap = await FirebaseFirestore.instance.collection('non_cognitive_skills').get();
        final spSnap = await FirebaseFirestore.instance.collection('sensitive_periods').get();

        _nonCognitiveSkillMap = {};
        for (var doc in ncSnap.docs) {
          final data = doc.data();
          final name = data['name'] as String;
          
          // ★修正: あらゆるフィールド名の可能性をチェック
          List<String> skills = List<String>.from(data['strengths'] ?? []);
          if (skills.isEmpty) {
            skills = List<String>.from(data['growing_skills'] ?? []);
          }
          if (skills.isEmpty) {
            skills = List<String>.from(data['growingSkills'] ?? []);
          }
          
          // ★重要修正: データが空でも勝手に文字を追加しない！
          // if (skills.isEmpty) skills.add('$nameに関する力'); // ← これを削除しました
          
          _nonCognitiveSkillMap[name] = skills;
        }
        
        // マスタ自体が空の場合のみ開発用ダミーを入れる（本番では不要なら削除可）
        if (_nonCognitiveSkillMap.isEmpty) {
          _nonCognitiveSkillMap = {
            '協調性': ['貸し借りができる', '順番を待てる'],
            '自律心': ['身支度ができる', '片付けができる'],
          };
        }

        _sensitivePeriodMaster = spSnap.docs.map((d) => d['name'] as String).toList();
        if (_sensitivePeriodMaster.isEmpty) {
          _sensitivePeriodMaster = ['運動', '感覚', '言語', '秩序', '微小', '社会性'];
        }
      }
    } catch (e) {
      debugPrint('Error fetching masters: $e');
    }
  }

  void _initializeNewData() {
    if (widget.type == 'weekly') {
      _addWeeklyEntry();
    } else {
      _addMonthlyEntry();
    }
  }

  void _initializeEditData() {
    final data = widget.initialData!;
    if (data['date'] != null) {
      _selectedDate = (data['date'] as Timestamp).toDate();
    }

    if (widget.type == 'weekly') {
      final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
      for (var entry in entries) {
        _weeklyEntries.add({
          'tool': entry['tool'] ?? '',
          'rating': entry['rating'] ?? '○',
          'duration': entry['duration'],
          'comment': entry['comment'] ?? '',
          'photoUrl': entry['photoUrl'],
          'localPhoto': null,
        });
      }
      if (_weeklyEntries.isEmpty) _addWeeklyEntry();
    } else {
      _monthlySummaryController.text = data['summary'] ?? '';
      _selectedSensitivePeriods.addAll(List<String>.from(data['sensitivePeriods'] ?? []));
      
      final savedEntries = List<Map<String, dynamic>>.from(data['monthlyEntries'] ?? []);
      for (var entry in savedEntries) {
        _monthlyEntries.add({
          'category': entry['category'] as String?,
          'skill': entry['skill'] as String?,
        });
      }
      if (_monthlyEntries.isEmpty) _addMonthlyEntry();
    }
  }

  void _addWeeklyEntry() {
    setState(() {
      _weeklyEntries.add({
        'tool': null,
        'rating': '○',
        'duration': null,
        'comment': '',
        'photoUrl': null,
        'localPhoto': null,
      });
    });
  }

  void _removeWeeklyEntry(int index) {
    setState(() {
      _weeklyEntries.removeAt(index);
    });
  }

  Future<void> _pickImage(int index) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _weeklyEntries[index]['localPhoto'] = image;
      });
    }
  }

  void _addMonthlyEntry() {
    setState(() {
      _monthlyEntries.add({
        'category': null,
        'skill': null,
      });
    });
  }

  void _removeMonthlyEntry(int index) {
    setState(() {
      _monthlyEntries.removeAt(index);
    });
  }

  Future<String?> _uploadImage(XFile file) async {
    try {
      final Uint8List fileBytes = await file.readAsBytes();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child('assessment_photos/$fileName');
      await ref.putData(fileBytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String staffName = '担当スタッフ'; 
      if (user != null) {
         final snap = await FirebaseFirestore.instance.collection('staffs').where('uid', isEqualTo: user.uid).get();
         if (snap.docs.isNotEmpty) staffName = snap.docs.first.data()['name'] ?? '担当スタッフ';
      }

      final Map<String, dynamic> data = {
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'type': widget.type,
        'date': _selectedDate,
        'staffId': user?.uid,
        'staffName': staffName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.type == 'weekly') {
        List<Map<String, dynamic>> savedEntries = [];
        for (var entry in _weeklyEntries) {
          String? photoUrl = entry['photoUrl'];
          if (entry['localPhoto'] != null) {
            final url = await _uploadImage(entry['localPhoto']);
            if (url != null) photoUrl = url;
          }

          savedEntries.add({
            'tool': entry['tool'] ?? '未選択',
            'rating': entry['rating'],
            'duration': entry['duration'],
            'comment': entry['comment'],
            'photoUrl': photoUrl,
          });
        }
        data['entries'] = savedEntries;
        data['dateRange'] = DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate);
        
        if (savedEntries.isNotEmpty) {
          final first = savedEntries.first;
          data['content'] = '${first['tool']} (${first['rating']})... 他${savedEntries.length - 1}件';
        } else {
          data['content'] = '(記録なし)';
        }
      } else {
        data['summary'] = _monthlySummaryController.text;
        data['sensitivePeriods'] = _selectedSensitivePeriods.toList();
        
        data['monthlyEntries'] = _monthlyEntries;
        
        final flatSkills = _monthlyEntries
            .map((e) => e['skill'])
            .where((s) => s != null)
            .cast<String>()
            .toList();
        final flatCategories = _monthlyEntries
            .map((e) => e['category'])
            .where((c) => c != null)
            .cast<String>()
            .toSet()
            .toList();

        data['strengths'] = flatSkills;
        data['skills'] = [
          ...flatCategories,
          ...flatSkills,
          ..._selectedSensitivePeriods
        ];
      }

      if (widget.docId != null) {
        await FirebaseFirestore.instance.collection('assessments').doc(widget.docId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('assessments').add(data);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showToolSelectDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => _ToolSelectDialog(
        tools: _toolList,
        onSelected: (toolName) {
          setState(() {
            _weeklyEntries[index]['tool'] = toolName;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(widget.type == 'weekly' ? '週次アセスメント編集' : '月次サマリ編集'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateSelector(),
                  const SizedBox(height: 24),
                  if (widget.type == 'weekly') _buildWeeklyForm() else _buildMonthlyForm(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateSelector() {
    final isWeekly = widget.type == 'weekly';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isWeekly ? '対象日' : '対象月', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                locale: const Locale('ja'),
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                });
              }
            },
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.orange),
                const SizedBox(width: 12),
                Text(
                  isWeekly 
                      ? DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate)
                      : DateFormat('yyyy年 M月度').format(_selectedDate),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyForm() {
    return Column(
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _weeklyEntries.length,
          itemBuilder: (context, index) {
            final entry = _weeklyEntries[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('教具 ${index + 1}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      if (_weeklyEntries.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                          onPressed: () => _removeWeeklyEntry(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _showToolSelectDialog(index),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry['tool'] ?? '教具を選択',
                            style: TextStyle(
                              color: entry['tool'] == null ? Colors.grey.shade600 : Colors.black87,
                              fontSize: 16,
                              fontWeight: entry['tool'] != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('評価', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      _buildCircleRating(index, '△', Colors.blue),
                      const SizedBox(width: 8),
                      _buildCircleRating(index, '○', Colors.orange),
                      const SizedBox(width: 8),
                      _buildCircleRating(index, '◎', Colors.red),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('所要時間', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _durationOptions.map((option) {
                      final isSelected = entry['duration'] == option;
                      return ChoiceChip(
                        label: Text(option),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            entry['duration'] = val ? option : null;
                          });
                        },
                        backgroundColor: Colors.grey.shade100,
                        selectedColor: Colors.orange.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.orange.shade900 : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.orange : Colors.transparent),
                        ),
                        showCheckmark: false,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: entry['comment'],
                    decoration: const InputDecoration(
                      hintText: 'コメントを入力...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    maxLines: 2,
                    onChanged: (val) => entry['comment'] = val,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => _pickImage(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: entry['localPhoto'] != null
                              ? (kIsWeb 
                                  ? Image.network(entry['localPhoto'].path, fit: BoxFit.cover)
                                  : Image.file(File(entry['localPhoto'].path), fit: BoxFit.cover))
                              : (entry['photoUrl'] != null
                                  ? Image.network(entry['photoUrl'], fit: BoxFit.cover)
                                  : const Icon(Icons.add_a_photo, color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('写真を添付', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        Center(
          child: ElevatedButton.icon(
            onPressed: _addWeeklyEntry,
            icon: const Icon(Icons.add),
            label: const Text('活動を追加'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCircleRating(int index, String label, Color color) {
    final isSelected = _weeklyEntries[index]['rating'] == label;
    return InkWell(
      onTap: () => setState(() => _weeklyEntries[index]['rating'] = label),
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? color : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('非認知能力・伸びている力', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _monthlyEntries.length,
          itemBuilder: (context, index) {
            final entry = _monthlyEntries[index];
            final selectedCategory = entry['category'];
            final skillOptions = selectedCategory != null ? (_nonCognitiveSkillMap[selectedCategory] ?? []) : <String>[];

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('項目 ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                      if (_monthlyEntries.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                          onPressed: () => _removeMonthlyEntry(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  
                  DropdownButtonFormField<String>(
                    value: _nonCognitiveSkillMap.keys.contains(entry['category']) ? entry['category'] : null,
                    decoration: const InputDecoration(
                      labelText: '非認知能力',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    isExpanded: true,
                    items: _nonCognitiveSkillMap.keys.map((key) => DropdownMenuItem(value: key, child: Text(key))).toList(),
                    onChanged: (val) {
                      setState(() {
                        entry['category'] = val;
                        entry['skill'] = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<String>(
                    value: skillOptions.contains(entry['skill']) ? entry['skill'] : null,
                    decoration: InputDecoration(
                      labelText: '伸びている力',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      filled: selectedCategory == null,
                      fillColor: selectedCategory == null ? Colors.grey.shade100 : null,
                    ),
                    isExpanded: true,
                    items: skillOptions.map((skill) => DropdownMenuItem(value: skill, child: Text(skill))).toList(),
                    onChanged: selectedCategory == null ? null : (val) {
                      setState(() => entry['skill'] = val);
                    },
                  ),
                ],
              ),
            );
          },
        ),

        Center(
          child: TextButton.icon(
            onPressed: _addMonthlyEntry,
            icon: const Icon(Icons.add),
            label: const Text('非認知能力を追加'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ),
        const SizedBox(height: 24),

        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('敏感期', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sensitivePeriodMaster.map((tag) {
              final isSelected = _selectedSensitivePeriods.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) _selectedSensitivePeriods.add(tag);
                    else _selectedSensitivePeriods.remove(tag);
                  });
                },
                selectedColor: Colors.green.shade100,
                checkmarkColor: Colors.green,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('月間総評', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextFormField(
            controller: _monthlySummaryController,
            maxLines: 5,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '今月の様子や成長した点などを入力してください...',
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// 教具選択ダイアログ
class _ToolSelectDialog extends StatefulWidget {
  final List<Map<String, String>> tools;
  final Function(String) onSelected;

  const _ToolSelectDialog({required this.tools, required this.onSelected});

  @override
  State<_ToolSelectDialog> createState() => _ToolSelectDialogState();
}

class _ToolSelectDialogState extends State<_ToolSelectDialog> {
  List<Map<String, String>> _filteredTools = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredTools = widget.tools;
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredTools = widget.tools;
      } else {
        _filteredTools = widget.tools.where((tool) {
          return (tool['name']!.contains(query)) || (tool['furigana']!.contains(query));
        }).toList();
      }
    });
  }

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
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 400,
        height: 600,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('教具を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: '教具名で検索...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                    ),
                    onChanged: _onSearch,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.grey),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredTools.length,
                itemBuilder: (context, index) {
                  final tool = _filteredTools[index];
                  final header = _getIndexHeader(tool['furigana']!);
                  bool showHeader = true;
                  if (index > 0) {
                    final prevHeader = _getIndexHeader(_filteredTools[index - 1]['furigana']!);
                    if (prevHeader == header) showHeader = false;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(header, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                        ),
                      ListTile(
                        title: Text(tool['name']!),
                        onTap: () {
                          widget.onSelected(tool['name']!);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}