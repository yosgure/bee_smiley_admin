import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'app_theme.dart';

class AssessmentEditScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String type;
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

  List<Map<String, dynamic>> _weeklyEntries = [];
  List<Map<String, String>> _toolList = [];
  final List<String> _durationOptions = ['0〜5分', '6〜10分', '11〜20分', '20分以上'];

  final TextEditingController _monthlySummaryController = TextEditingController();
  final Set<String> _selectedSensitivePeriods = {}; 
  List<Map<String, String?>> _monthlyEntries = [];

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
            'task': (data['task'] ?? '') as String,
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
        final ncSnap = await FirebaseFirestore.instance.collection('non_cognitive_skills').get();
        final spSnap = await FirebaseFirestore.instance.collection('sensitive_periods').get();

        _nonCognitiveSkillMap = {};
        for (var doc in ncSnap.docs) {
          final data = doc.data();
          final name = data['name'] as String;
          
          List<String> skills = List<String>.from(data['strengths'] ?? []);
          if (skills.isEmpty) {
            skills = List<String>.from(data['growing_skills'] ?? []);
          }
          if (skills.isEmpty) {
            skills = List<String>.from(data['growingSkills'] ?? []);
          }
          
          _nonCognitiveSkillMap[name] = skills;
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
            'task': _toolList.firstWhere((t) => t['name'] == entry['tool'], orElse: () => {'task': ''})['task'] ?? '',
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.type == 'weekly' ? '週次アセスメント編集' : '月次サマリ編集'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                : const Text('保存'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: FutureBuilder(
            future: _initializationFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('対象児童: ${widget.studentName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textMain)),
                      const SizedBox(height: 16),
                      
                      _buildDateSelector(),
                      const SizedBox(height: 24),
                      if (widget.type == 'weekly') _buildWeeklyForm() else _buildMonthlyForm(),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final isWeekly = widget.type == 'weekly';
    return GestureDetector(
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: AppStyles.radius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isWeekly ? '対象日' : '対象月', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSub, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_month, color: AppColors.primary),
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
          ],
        ),
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
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('教具 ${index + 1}', style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
                      if (_weeklyEntries.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                          onPressed: () => _removeWeeklyEntry(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  InkWell(
                    onTap: () => _showToolSelectDialog(index),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: AppStyles.radiusSmall,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry['tool'] ?? '教具を選択',
                            style: TextStyle(
                              color: entry['tool'] == null ? Colors.grey : AppColors.textMain,
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
                      const Text('評価', style: TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      _buildCircleRating(index, '△', Colors.blue),
                      const SizedBox(width: 8),
                      _buildCircleRating(index, '○', Colors.orange),
                      const SizedBox(width: 8),
                      _buildCircleRating(index, '◎', Colors.red),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    initialValue: entry['comment'],
                    decoration: const InputDecoration(
                      hintText: 'コメントを入力...',
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
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.inputFill,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: entry['localPhoto'] != null
                              ? (kIsWeb 
                                  ? Image.network(entry['localPhoto'].path, fit: BoxFit.cover)
                                  : Image.file(File(entry['localPhoto'].path), fit: BoxFit.cover))
                              : (entry['photoUrl'] != null
                                  ? Image.network(entry['photoUrl'], fit: BoxFit.cover)
                                  : const Center(child: Icon(Icons.add_a_photo, color: Colors.grey))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('写真を添付', style: TextStyle(fontSize: 14, color: AppColors.textSub)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        Center(
          child: OutlinedButton.icon(
            onPressed: _addWeeklyEntry,
            icon: const Icon(Icons.add),
            label: const Text('教具を追加'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              side: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
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
          child: Text('非認知能力・伸びている力', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSub)),
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
                      Text('項目 ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSub, fontSize: 12)),
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
                      filled: selectedCategory == null,
                      fillColor: selectedCategory == null ? Colors.grey.shade100 : AppColors.inputFill,
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
          child: OutlinedButton.icon(
            onPressed: _addMonthlyEntry,
            icon: const Icon(Icons.add),
            label: const Text('項目を追加'),
          ),
        ),
        const SizedBox(height: 24),

        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('敏感期', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSub)),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface, 
            borderRadius: AppStyles.radius,
            border: AppStyles.borderLight,
          ),
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
                    if (val) {
                      _selectedSensitivePeriods.add(tag);
                    } else {
                      _selectedSensitivePeriods.remove(tag);
                    }
                  });
                },
                selectedColor: AppColors.primary.withOpacity(0.2),
                checkmarkColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isSelected ? AppColors.primary : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('月間総評', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSub)),
        ),
        TextField(
          controller: _monthlySummaryController,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '今月の様子や成長した点などを入力してください...',
          ),
        ),
      ],
    );
  }
}

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

  // ひらがなの五十音順でヘッダーを判定（Unicodeコードポイント使用）
  String _getIndexHeader(String kana) {
    if (kana.isEmpty) return '他';
    final c = kana.codeUnitAt(0);
    // あ行: U+3042(あ) - U+304A(お)
    if (c >= 0x3042 && c <= 0x304A) return 'あ';
    // か行: U+304B(か) - U+3054(ご) ※濁音含む
    if (c >= 0x304B && c <= 0x3054) return 'か';
    // さ行: U+3055(さ) - U+305E(ぞ)
    if (c >= 0x3055 && c <= 0x305E) return 'さ';
    // た行: U+305F(た) - U+3069(ど)
    if (c >= 0x305F && c <= 0x3069) return 'た';
    // な行: U+306A(な) - U+306E(の)
    if (c >= 0x306A && c <= 0x306E) return 'な';
    // は行: U+306F(は) - U+307D(ぽ)
    if (c >= 0x306F && c <= 0x307D) return 'は';
    // ま行: U+307E(ま) - U+3082(も)
    if (c >= 0x307E && c <= 0x3082) return 'ま';
    // や行: U+3084(や), U+3086(ゆ), U+3088(よ)
    if (c >= 0x3083 && c <= 0x3088) return 'や';
    // ら行: U+3089(ら) - U+308D(ろ)
    if (c >= 0x3089 && c <= 0x308D) return 'ら';
    // わ行: U+308F(わ) - U+3093(ん)
    if (c >= 0x308E && c <= 0x3093) return 'わ';
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
                  final header = _getIndexHeader(tool['furigana'] ?? '');
                  bool showHeader = true;
                  if (index > 0) {
                    final prevHeader = _getIndexHeader(_filteredTools[index - 1]['furigana'] ?? '');
                    if (prevHeader == header) showHeader = false;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          color: AppColors.inputFill,
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