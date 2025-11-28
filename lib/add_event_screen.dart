import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart'; // テーマ定義をインポート

class AddEventDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DocumentSnapshot? appointment; // 編集用 (予定)
  final DocumentSnapshot? taskDoc;     // 編集用 (タスク)

  const AddEventDialog({
    super.key,
    this.initialStartDate,
    this.appointment,
    this.taskDoc,
  });

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isTaskMode = false;

  late TextEditingController _subjectController;
  late TextEditingController _notesController;
  late TextEditingController _locationController;
  
  bool _isLoading = false;
  bool _isEditing = false;

  // --- 予定用データ ---
  late DateTime _startDate;
  late DateTime _endDate;
  
  String _selectedCategory = 'レッスン'; 
  final List<Map<String, dynamic>> _categories = [
    {'label': 'レッスン', 'color': 0xFF039BE5},
    {'label': 'イベント', 'color': 0xFF33B679},
    {'label': 'その他', 'color': 0xFF8E24AA},
  ];
  
  String _recurrenceType = 'なし';
  final List<String> _recurrenceOptions = ['なし', '毎日', '毎週', '第1・2・3週(月次)', '毎年'];
  
  String? _selectedClassroom;
  List<String> _classroomList = [];
  bool _isManualLocation = false;
  
  final Set<String> _selectedStudentIds = {}; 
  final Set<String> _selectedStaffIds = {};
  final Map<String, String> _studentNamesMap = {};
  final Map<String, String> _staffNamesMap = {};
  final Map<String, DateTime> _studentTransferDates = {};
  final Set<String> _absentStudentIds = {};
  static const String _manualInputKey = '__MANUAL_INPUT__';

  // --- タスク用データ ---
  late DateTime _taskDate;

  @override
  void initState() {
    super.initState();
    
    _subjectController = TextEditingController();
    _notesController = TextEditingController();
    _locationController = TextEditingController();

    if (widget.taskDoc != null) {
      _isEditing = true;
      _isTaskMode = true;
      _initializeTaskData(widget.taskDoc!.data() as Map<String, dynamic>);
    } else if (widget.appointment != null) {
      _isEditing = true;
      _isTaskMode = false;
      _initializeEventData(widget.appointment!.data() as Map<String, dynamic>);
    } else {
      _isEditing = false;
      final now = DateTime.now();
      final initial = widget.initialStartDate ?? now;
      final roundedMinute = initial.minute >= 30 ? 30 : 0;
      _startDate = DateTime(initial.year, initial.month, initial.day, initial.hour, roundedMinute);
      _endDate = _startDate.add(const Duration(hours: 1));
      _taskDate = DateTime(initial.year, initial.month, initial.day);
    }

    _fetchClassrooms().then((_) {
      if (!_isEditing && !_isTaskMode && mounted && _classroomList.isNotEmpty) {
        setState(() {
          _selectedClassroom = _classroomList.first;
        });
      }
    });
  }

  void _initializeEventData(Map<String, dynamic> data) {
    _subjectController.text = data['subject'] ?? '';
    _notesController.text = data['notes'] ?? '';
    _startDate = (data['startTime'] as Timestamp).toDate();
    _endDate = (data['endTime'] as Timestamp).toDate();
    _selectedCategory = data['category'] ?? 'レッスン';

    final location = data['classroom'] as String?;
    if (location != null && location.isNotEmpty) {
      _selectedClassroom = location; 
      _isManualLocation = false; 
    }

    final rrule = data['recurrenceRule'] as String?;
    if (rrule != null) {
      if (rrule.contains('FREQ=DAILY')) _recurrenceType = '毎日';
      else if (rrule.contains('FREQ=WEEKLY')) _recurrenceType = '毎週';
      else if (rrule.contains('FREQ=YEARLY')) _recurrenceType = '毎年';
      else if (rrule.contains('BYDAY=1') && rrule.contains('BYDAY=2')) _recurrenceType = '第1・2・3週(月次)';
      else _recurrenceType = 'なし';
    }

    final sIds = List<String>.from(data['studentIds'] ?? []);
    final sNames = List<String>.from(data['studentNames'] ?? []);
    for (int i = 0; i < sIds.length; i++) {
      if (i < sNames.length) {
        _selectedStudentIds.add(sIds[i]);
        _studentNamesMap[sIds[i]] = sNames[i];
      }
    }
    final stIds = List<String>.from(data['staffIds'] ?? []);
    final stNames = List<String>.from(data['staffNames'] ?? []);
    for (int i = 0; i < stIds.length; i++) {
      if (i < stNames.length) {
        _selectedStaffIds.add(stIds[i]);
        _staffNamesMap[stIds[i]] = stNames[i];
      }
    }
    
    final transferMap = data['studentTransferDates'] as Map<String, dynamic>? ?? {};
    transferMap.forEach((key, value) {
      if (value is Timestamp) _studentTransferDates[key] = value.toDate();
    });
    final absentList = List<String>.from(data['absentStudentIds'] ?? []);
    _absentStudentIds.addAll(absentList);
  }

  void _initializeTaskData(Map<String, dynamic> data) {
    _subjectController.text = data['title'] ?? '';
    _notesController.text = data['notes'] ?? '';
    if (data['date'] is Timestamp) {
      _taskDate = (data['date'] as Timestamp).toDate();
    }
  }

  Future<void> _fetchClassrooms() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('classrooms').get();
      final list = snapshot.docs.map((d) => d['name'] as String).toList();
      if (mounted) {
        setState(() {
          _classroomList = list;
          if (_isEditing && !_isTaskMode && _selectedClassroom != null) {
             if (!_classroomList.contains(_selectedClassroom)) {
               _locationController.text = _selectedClassroom!;
               _selectedClassroom = _manualInputKey;
               _isManualLocation = true;
             }
          }
        });
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isTaskMode) {
        await _saveTask();
      } else {
        await _saveEvent();
      }
      
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTask() async {
    final user = FirebaseAuth.instance.currentUser;
    
    final taskData = {
      'userId': user?.uid,
      'title': _subjectController.text.trim(),
      'date': Timestamp.fromDate(DateTime(_taskDate.year, _taskDate.month, _taskDate.day)),
      'notes': _notesController.text.trim(),
      'isCompleted': widget.taskDoc?['isCompleted'] ?? false, 
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (_isEditing && widget.taskDoc != null) {
      await widget.taskDoc!.reference.update(taskData);
    } else {
      taskData['createdAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('tasks').add(taskData);
    }
  }

  Future<void> _saveEvent() async {
    final colorValue = _categories.firstWhere((c) => c['label'] == _selectedCategory)['color'] as int;
    
    String? rrule;
    if (_recurrenceType == '毎日') rrule = 'FREQ=DAILY;INTERVAL=1';
    else if (_recurrenceType == '毎週') rrule = 'FREQ=WEEKLY;INTERVAL=1';
    else if (_recurrenceType == '毎年') rrule = 'FREQ=YEARLY;INTERVAL=1';
    else if (_recurrenceType == '第1・2・3週(月次)') {
      const weekDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
      final dayStr = weekDays[_startDate.weekday - 1];
      rrule = 'FREQ=MONTHLY;INTERVAL=1;BYDAY=1$dayStr,2$dayStr,3$dayStr';
    }

    String? locationToSave;
    if (_isManualLocation) {
      locationToSave = _locationController.text.trim();
    } else {
      if (_selectedClassroom != _manualInputKey) {
        locationToSave = _selectedClassroom;
      }
    }

    final List<String> studentNames = _selectedStudentIds
        .map((id) => _studentNamesMap[id] ?? '')
        .where((s) => s.isNotEmpty).toList();
        
    final List<String> staffNames = _selectedStaffIds
        .map((id) => _staffNamesMap[id] ?? '')
        .where((s) => s.isNotEmpty).toList();

    final eventData = {
      'subject': _subjectController.text,
      'startTime': _startDate,
      'endTime': _endDate,
      'color': colorValue,
      'notes': _notesController.text,
      'category': _selectedCategory,
      'classroom': locationToSave,
      'recurrenceRule': rrule,
      'studentIds': _selectedStudentIds.toList(),
      'staffIds': _selectedStaffIds.toList(),
      'studentNames': studentNames,
      'staffNames': staffNames,
      'studentTransferDates': _studentTransferDates,
      'absentStudentIds': _absentStudentIds.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (_isEditing && widget.appointment != null) {
      await widget.appointment!.reference.update(eventData);
    } else {
      eventData['createdAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('calendar_events').add(eventData);
    }
  }

  // --- UIパーツ ---

  Widget _buildTaskDatePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _taskDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          locale: const Locale('ja'),
        );
        if (picked != null) {
          setState(() => _taskDate = picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: AppStyles.radiusSmall,
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DateFormat('yyyy年MM月dd日 (E)', 'ja').format(_taskDate),
                style: const TextStyle(fontSize: 15, color: AppColors.textMain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = _isEditing ? '編集' : '追加';
    if (_isTaskMode) title = 'タスクを$title';
    else title = '予定を$title';

    return AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 500,
        height: 600, 
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isEditing) 
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(value: false, label: Text('予定'), icon: Icon(Icons.event)),
                        ButtonSegment<bool>(value: true, label: Text('タスク'), icon: Icon(Icons.check_circle_outline)),
                      ],
                      selected: {_isTaskMode},
                      onSelectionChanged: (Set<bool> newSelection) {
                        setState(() {
                          _isTaskMode = newSelection.first;
                        });
                      },
                      style: ButtonStyle(
                        side: WidgetStateProperty.all(BorderSide(color: AppColors.primary.withOpacity(0.5))),
                        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.selected)) return AppColors.primary.withOpacity(0.2);
                          return null;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.selected)) return AppColors.primary;
                          return Colors.grey.shade700;
                        }),
                      ),
                    ),
                  ),

                // タイトル入力 (枠線なし・背景色あり)
                TextFormField(
                  controller: _subjectController,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: _isTaskMode ? 'タスクを追加' : 'タイトルを追加',
                    // Themeで設定した inputDecorationTheme が適用されるため、個別の枠線指定は削除
                  ),
                  validator: (value) => value == null || value.isEmpty ? '入力してください' : null,
                ),
                const SizedBox(height: 24),

                if (_isTaskMode) ...[
                  // --- タスクモード ---
                  _buildTaskDatePicker(),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 8, 
                    decoration: const InputDecoration(
                      hintText: '詳細・メモを追加',
                    ),
                  ),
                ] 
                else ...[
                  // --- 予定モード ---
                  Row(
                    children: [
                      _buildDateTimePicker('開始', _startDate, (dt) {
                        setState(() {
                          _startDate = dt;
                          if (_endDate.isBefore(_startDate)) {
                            _endDate = _startDate.add(const Duration(hours: 1));
                          }
                        });
                      }),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, color: Colors.grey, size: 20),
                      ),
                      _buildDateTimePicker('終了', _endDate, (dt) {
                        setState(() => _endDate = dt);
                      }),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // カテゴリ選択チップ
                  Wrap(
                    spacing: 8,
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat['label'];
                      return ChoiceChip(
                        label: Text(cat['label']),
                        selected: isSelected,
                        showCheckmark: false,
                        selectedColor: Color(cat['color']),
                        backgroundColor: AppColors.inputFill,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textMain,
                          fontWeight: FontWeight.bold,
                        ),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        onSelected: (val) => setState(() {
                          _selectedCategory = cat['label'];
                          if (_selectedCategory == 'レッスン') {
                             _isManualLocation = false;
                             if (_selectedClassroom == _manualInputKey && _classroomList.isNotEmpty) {
                               _selectedClassroom = _classroomList.first;
                             }
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // ★修正: 繰り返しと場所を縦に並べる (狭いので)
                  DropdownButtonFormField<String>(
                    value: _recurrenceType,
                    decoration: const InputDecoration(
                      labelText: '繰り返し',
                    ),
                    items: _recurrenceOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) => setState(() => _recurrenceType = val!),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedClassroom,
                        decoration: const InputDecoration(
                          labelText: '場所',
                        ),
                        isExpanded: true,
                        items: [
                          ..._classroomList.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))),
                          if (_selectedCategory != 'レッスン')
                            const DropdownMenuItem(
                              value: _manualInputKey, 
                              child: Text('その他（直接入力）', style: TextStyle(color: AppColors.primary)),
                            ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedClassroom = val;
                            _isManualLocation = (val == _manualInputKey);
                            if (!_isEditing) {
                              _selectedStudentIds.clear();
                              _studentNamesMap.clear();
                            }
                          });
                        },
                      ),
                      if (_isManualLocation)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextFormField(
                            controller: _locationController,
                            decoration: const InputDecoration(
                              hintText: '場所名を入力',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader(
                    (_selectedCategory == 'イベント') ? '担当スタッフ' : (_selectedCategory == 'その他') ? '参加者' : '担当講師', 
                    Icons.badge
                  ),
                  _buildPersonList(
                    ids: _selectedStaffIds,
                    namesMap: _staffNamesMap,
                    onAdd: _showStaffSelectDialog,
                  ),
                  const SizedBox(height: 24),

                  if (_selectedCategory != 'その他') ...[
                    _buildSectionHeader('参加生徒', Icons.face),
                    _buildStudentList(),
                    const SizedBox(height: 24),
                  ],

                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '詳細・メモを追加',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isTaskMode ? AppColors.secondary : AppColors.primary, 
          ),
          child: _isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
              : Text(_isEditing ? '更新' : '保存', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildDateTimePicker(String label, DateTime dateTime, Function(DateTime) onChanged) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: dateTime,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
            locale: const Locale('ja'),
          );
          if (date != null && mounted) {
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(dateTime),
            );
            if (time != null) {
              onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: AppStyles.radiusSmall,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                DateFormat('M/d HH:mm', 'ja').format(dateTime),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedStudentIds.isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppStyles.radiusSmall,
              border: Border.all(color: Colors.grey.shade200), // 枠線は薄く
            ),
            child: Column(
              children: _selectedStudentIds.map((id) {
                final name = _studentNamesMap[id] ?? '不明';
                final isAbsent = _absentStudentIds.contains(id);
                final transferDate = _studentTransferDates[id];
                
                return Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 14,
                                color: isAbsent ? Colors.grey : AppColors.textMain,
                                decoration: isAbsent ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            if (transferDate != null)
                              Text(
                                '${DateFormat('M/d').format(transferDate)}振替分',
                                style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(isAbsent ? Icons.close : Icons.event_busy, size: 20, color: isAbsent ? AppColors.error : Colors.grey),
                            tooltip: isAbsent ? '欠席取消' : '欠席にする',
                            onPressed: () => _toggleAbsent(id),
                          ),
                          IconButton(
                            icon: Icon(Icons.swap_horiz, size: 20, color: transferDate != null ? AppColors.primary : Colors.grey),
                            tooltip: '振替元の日付を設定',
                            onPressed: () => _pickTransferDate(id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey),
                            tooltip: 'リストから削除',
                            onPressed: () {
                              setState(() {
                                _selectedStudentIds.remove(id);
                                _studentTransferDates.remove(id);
                                _absentStudentIds.remove(id);
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        
        if (!_isManualLocation && _selectedClassroom == null)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 8),
            child: Text('※先に教室を選択してください', style: TextStyle(color: AppColors.error, fontSize: 12)),
          ),

        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: (!_isManualLocation && _selectedClassroom == null) 
              ? null 
              : _showStudentSelectDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('追加'),
          style: OutlinedButton.styleFrom(
            // テーマ対応
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonList({
    required Set<String> ids,
    required Map<String, String> namesMap,
    required VoidCallback? onAdd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ids.isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppStyles.radiusSmall,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: ids.map((id) {
                final name = namesMap[id] ?? '不明';
                return Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 12, right: 4),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          ids.remove(id);
                        });
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('追加'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }

  // 既存の _pickTransferDate, _toggleAbsent, _showStudentSelectDialog, _showStaffSelectDialog, _PersonSelectDialog
  // これらはロジックなので変更なし（省略せず記述）
  Future<void> _pickTransferDate(String studentId) async {
    final initial = _studentTransferDates[studentId] ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      helpText: '振替元の日付を選択',
    );
    
    if (picked != null) {
      setState(() {
        _studentTransferDates[studentId] = picked;
        _absentStudentIds.remove(studentId);
      });
    }
  }

  void _toggleAbsent(String studentId) {
    setState(() {
      if (_absentStudentIds.contains(studentId)) {
        _absentStudentIds.remove(studentId);
      } else {
        _absentStudentIds.add(studentId);
        _studentTransferDates.remove(studentId);
      }
    });
  }

  void _showStudentSelectDialog() {
    final filter = _isManualLocation ? null : _selectedClassroom;
    showDialog(
      context: context,
      builder: (ctx) => _PersonSelectDialog(
        title: '生徒を選択',
        type: 'student',
        filterKey: filter, 
        initialSelectedIds: _selectedStudentIds,
        onConfirmed: (selectedItems) {
          setState(() {
            _selectedStudentIds.clear();
            _selectedStudentIds.addAll(selectedItems.keys);
            _studentNamesMap.addAll(selectedItems);
          });
        },
      ),
    );
  }

  void _showStaffSelectDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PersonSelectDialog(
        title: '講師を選択',
        type: 'staff',
        initialSelectedIds: _selectedStaffIds,
        onConfirmed: (selectedItems) {
          setState(() {
            _selectedStaffIds.clear();
            _selectedStaffIds.addAll(selectedItems.keys);
            _staffNamesMap.addAll(selectedItems);
          });
        },
      ),
    );
  }
}

class _PersonSelectDialog extends StatefulWidget {
  final String title;
  final String type; 
  final String? filterKey; 
  final Set<String> initialSelectedIds;
  final Function(Map<String, String>) onConfirmed; 

  const _PersonSelectDialog({
    required this.title,
    required this.type,
    this.filterKey,
    required this.initialSelectedIds,
    required this.onConfirmed,
  });

  @override
  State<_PersonSelectDialog> createState() => _PersonSelectDialogState();
}

class _PersonSelectDialogState extends State<_PersonSelectDialog> {
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _filteredPeople = [];
  final Map<String, String> _selectedMap = {};
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    for (var id in widget.initialSelectedIds) {
      _selectedMap[id] = ''; 
    }
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final List<Map<String, dynamic>> loaded = [];

      if (widget.type == 'student') {
        final snapshot = await FirebaseFirestore.instance.collection('families').get();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final parentLastName = data['lastName'] ?? '';
          final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
          
          for (var child in children) {
            if (widget.filterKey != null && child['classroom'] != widget.filterKey) {
              continue;
            }
            
            final childName = child['firstName'] ?? '';
            final childNameKana = child['firstNameKana'] ?? childName;
            final fullName = '$parentLastName $childName';
            final uniqueId = '${data['uid']}_$childName';

            loaded.add({
              'id': uniqueId,
              'name': fullName,
              'kana': childNameKana,
            });
            
            if (_selectedMap.containsKey(uniqueId)) {
              _selectedMap[uniqueId] = fullName;
            }
          }
        }
      } else {
        final snapshot = await FirebaseFirestore.instance.collection('staffs').get();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          String name = data['name'] ?? '';
          if (name.isEmpty) {
            name = '${data['lastName']??''} ${data['firstName']??''}';
          }
          String kana = data['furigana'] ?? '';
          if (kana.isEmpty) kana = name;

          final uid = data['uid'] ?? doc.id;

          loaded.add({
            'id': uid,
            'name': name,
            'kana': kana,
          });

          if (_selectedMap.containsKey(uid)) {
            _selectedMap[uid] = name;
          }
        }
      }

      loaded.sort((a, b) => (a['kana'] as String).compareTo(b['kana'] as String));

      setState(() {
        _people = loaded;
        _filteredPeople = loaded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredPeople = _people;
      } else {
        _filteredPeople = _people.where((p) => 
          p['name'].contains(query) || p['kana'].contains(query)
        ).toList();
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
      backgroundColor: AppColors.surface, // テーマ色
      surfaceTintColor: AppColors.surface,
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
                  Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: '名前で検索...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _onSearch,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.grey),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredPeople.isEmpty
                      ? const Center(child: Text('該当者がいません', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _filteredPeople.length,
                          itemBuilder: (context, index) {
                            final person = _filteredPeople[index];
                            final header = _getIndexHeader(person['kana']);
                            bool showHeader = true;
                            if (index > 0) {
                              final prevHeader = _getIndexHeader(_filteredPeople[index - 1]['kana']);
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
                                CheckboxListTile(
                                  value: _selectedMap.containsKey(person['id']),
                                  activeColor: AppColors.primary,
                                  title: Text(person['name']),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedMap[person['id']] = person['name'];
                                      } else {
                                        _selectedMap.remove(person['id']);
                                      }
                                    });
                                  },
                                ),
                              ],
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onConfirmed(_selectedMap);
                    Navigator.pop(context);
                  },
                  // テーマでスタイルは適用済み
                  child: Text('${_selectedMap.length}名を選択して完了', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}