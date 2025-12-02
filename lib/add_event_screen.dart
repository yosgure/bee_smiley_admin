import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';

class AddEventDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DocumentSnapshot? appointment;
  final DocumentSnapshot? taskDoc;

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
  bool _isAllDay = false;
  late TextEditingController _subjectController;
  late TextEditingController _notesController;
  late TextEditingController _locationController;
  
  bool _isLoading = false;
  bool _isEditing = false;
  bool _showDetailOptions = false;

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
        setState(() => _selectedClassroom = _classroomList.first);
      }
    });
  }

  void _initializeEventData(Map<String, dynamic> data) {
    _subjectController.text = data['subject'] ?? '';
    _notesController.text = data['notes'] ?? '';
    _startDate = (data['startTime'] as Timestamp).toDate();
    _endDate = (data['endTime'] as Timestamp).toDate();
    _selectedCategory = data['category'] ?? 'レッスン';
    _isAllDay = data['isAllDay'] ?? false;

    final location = data['classroom'] as String?;
    if (location != null && location.isNotEmpty) {
      if (_classroomList.contains(location)) {
        _selectedClassroom = location;
        _isManualLocation = false;
      } else {
        _locationController.text = location;
        _isManualLocation = true;
        _selectedClassroom = null;
      }
    }

    final rrule = data['recurrenceRule'] as String?;
    if (rrule != null) {
      if (rrule.contains('FREQ=DAILY')) _recurrenceType = '毎日';
      else if (rrule.contains('FREQ=WEEKLY')) _recurrenceType = '毎週';
      else if (rrule.contains('FREQ=YEARLY')) _recurrenceType = '毎年';
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
    _absentStudentIds.addAll(List<String>.from(data['absentStudentIds'] ?? []));
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
      if (mounted) setState(() => _classroomList = list);
    } catch (e) {}
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  String? get _locationValue {
    if (_isManualLocation) {
      return _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
    }
    return _selectedClassroom;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      if (_isTaskMode) await _saveTask();
      else await _saveEvent();
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

    DateTime startToSave = _startDate;
    DateTime endToSave = _endDate;
    if (_isAllDay) {
      startToSave = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0);
      endToSave = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59);
    }

    final eventData = {
      'subject': _subjectController.text,
      'startTime': startToSave,
      'endTime': endToSave,
      'isAllDay': _isAllDay,
      'color': colorValue,
      'notes': _notesController.text,
      'category': _selectedCategory,
      'classroom': _locationValue,
      'recurrenceRule': rrule,
      'studentIds': _selectedStudentIds.toList(),
      'staffIds': _selectedStaffIds.toList(),
      'studentNames': _selectedStudentIds.map((id) => _studentNamesMap[id] ?? '').where((s) => s.isNotEmpty).toList(),
      'staffNames': _selectedStaffIds.map((id) => _staffNamesMap[id] ?? '').where((s) => s.isNotEmpty).toList(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル', style: TextStyle(color: AppColors.primary, fontSize: 16))),
                    TextButton(
                      onPressed: _isLoading ? null : _save,
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('保存', style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 8, 16, 8),
                        child: TextFormField(
                          controller: _subjectController,
                          style: const TextStyle(fontSize: 24, color: AppColors.textMain),
                          decoration: const InputDecoration(
                            hintText: 'タイトルを追加',
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 24),
                            border: InputBorder.none,
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (v) => v == null || v.isEmpty ? '入力してください' : null,
                        ),
                      ),
                      if (!_isEditing)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                          child: Row(children: [
                            _buildModeChip('予定', !_isTaskMode, () => setState(() => _isTaskMode = false)),
                            const SizedBox(width: 8),
                            _buildModeChip('タスク', _isTaskMode, () => setState(() => _isTaskMode = true)),
                          ]),
                        ),
                      const Divider(height: 1),
                      if (_isTaskMode) _buildTaskContent() else _buildEventContent(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade400),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildTaskContent() {
    return Column(children: [
      _buildListTile(icon: Icons.access_time, child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(context: context, initialDate: _taskDate, firstDate: DateTime(2020), lastDate: DateTime(2030), locale: const Locale('ja'));
          if (picked != null) setState(() => _taskDate = picked);
        },
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(DateFormat('M月d日 (E)', 'ja').format(_taskDate), style: const TextStyle(fontSize: 16, color: AppColors.textMain))),
      )),
      const Divider(height: 1),
      _buildListTile(icon: Icons.notes, child: TextFormField(
        controller: _notesController,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: 'メモを追加',
          hintStyle: TextStyle(color: Colors.grey),
          border: InputBorder.none,
          filled: true,
          fillColor: Colors.white,
        ),
      )),
    ]);
  }

  Widget _buildEventContent() {
    final bool allowFreeLocation = _selectedCategory == 'イベント' || _selectedCategory == 'その他';
    
    return Column(children: [
      _buildListTile(icon: Icons.access_time, child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('終日', style: TextStyle(fontSize: 16, color: AppColors.textMain)),
          Switch(value: _isAllDay, onChanged: (v) => setState(() => _isAllDay = v), activeColor: AppColors.primary),
        ]),
        InkWell(onTap: () => _pickDateTime(isStart: true), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(DateFormat('M月d日 (E)', 'ja').format(_startDate), style: const TextStyle(fontSize: 16, color: AppColors.textMain)),
          if (!_isAllDay) Text(DateFormat('H:mm').format(_startDate), style: const TextStyle(fontSize: 16, color: AppColors.textMain)),
        ]))),
        InkWell(onTap: () => _pickDateTime(isStart: false), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(DateFormat('M月d日 (E)', 'ja').format(_endDate), style: const TextStyle(fontSize: 16, color: AppColors.textMain)),
          if (!_isAllDay) Text(DateFormat('H:mm').format(_endDate), style: const TextStyle(fontSize: 16, color: AppColors.textMain)),
        ]))),
        InkWell(onTap: () => setState(() => _showDetailOptions = !_showDetailOptions), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
          Text('詳細オプション', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          Icon(_showDetailOptions ? Icons.expand_less : Icons.expand_more, color: Colors.grey.shade600),
        ]))),
        if (_showDetailOptions) InkWell(onTap: _showRecurrenceDialog, child: Padding(padding: const EdgeInsets.only(left: 16, top: 8, bottom: 16), child: Row(children: [
          const Icon(Icons.repeat, size: 20, color: Colors.grey), const SizedBox(width: 16),
          Text(_recurrenceType == 'なし' ? '繰り返しなし' : _recurrenceType, style: const TextStyle(fontSize: 14, color: AppColors.textMain)),
        ]))),
      ])),
      const Divider(height: 1),
      
      _buildListTile(icon: Icons.category, child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Wrap(spacing: 8, children: _categories.map((cat) {
        final isSelected = _selectedCategory == cat['label'];
        return GestureDetector(onTap: () => setState(() {
          _selectedCategory = cat['label'];
          if (cat['label'] == 'レッスン') {
            _isManualLocation = false;
          }
        }), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: isSelected ? Color(cat['color']) : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? Color(cat['color']) : Colors.grey.shade400)),
          child: Text(cat['label'], style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade600, fontSize: 13)),
        ));
      }).toList()))),
      const Divider(height: 1),
      
      if (allowFreeLocation)
        _buildListTile(icon: Icons.location_on_outlined, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Row(children: [
                _buildLocationTab('教室から選択', !_isManualLocation, () => setState(() => _isManualLocation = false)),
                const SizedBox(width: 8),
                _buildLocationTab('自由入力', _isManualLocation, () => setState(() => _isManualLocation = true)),
              ]),
            ),
            if (_isManualLocation)
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  hintText: '場所を入力',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Colors.white,
                ),
              )
            else
              InkWell(
                onTap: _showClassroomDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_selectedClassroom ?? '教室を選択', style: TextStyle(fontSize: 16, color: _selectedClassroom == null ? Colors.grey : AppColors.textMain)),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ]),
                ),
              ),
          ],
        ))
      else
        _buildListTile(icon: Icons.location_on_outlined, child: InkWell(onTap: _showClassroomDialog, child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_selectedClassroom ?? '教室を選択', style: TextStyle(fontSize: 16, color: _selectedClassroom == null ? Colors.grey : AppColors.textMain)),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ])))),
      const Divider(height: 1),
      
      _buildListTile(icon: Icons.person_outline, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(onTap: _showStaffSelectSheet, child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_selectedStaffIds.isEmpty ? '担当者を追加' : '${_selectedStaffIds.length}名選択中', style: TextStyle(fontSize: 16, color: _selectedStaffIds.isEmpty ? Colors.grey : AppColors.textMain)),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]))),
        if (_selectedStaffIds.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 8, runSpacing: 8, children: _selectedStaffIds.map((id) => Chip(
          label: Text(_staffNamesMap[id] ?? '不明', style: const TextStyle(fontSize: 12)),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() => _selectedStaffIds.remove(id)),
          backgroundColor: Colors.grey.shade100, side: BorderSide.none,
        )).toList())),
      ])),
      const Divider(height: 1),
      
      if (_selectedCategory != 'その他') ...[
        _buildListTile(icon: Icons.face_outlined, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(onTap: (_selectedClassroom == null && !_isManualLocation) ? null : _showStudentSelectSheet, child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(_selectedStudentIds.isEmpty ? ((_selectedClassroom == null && !_isManualLocation) ? '先に教室を選択' : '生徒を追加') : '${_selectedStudentIds.length}名選択中', style: TextStyle(fontSize: 16, color: (_selectedClassroom == null && !_isManualLocation) ? Colors.grey.shade300 : (_selectedStudentIds.isEmpty ? Colors.grey : AppColors.textMain))),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ]))),
          if (_selectedStudentIds.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 8, runSpacing: 8, children: _selectedStudentIds.map((id) {
            final name = _studentNamesMap[id] ?? '不明';
            final isAbsent = _absentStudentIds.contains(id);
            return GestureDetector(onTap: () => _showStudentActionSheet(id), child: Chip(
              label: Text(name, style: TextStyle(fontSize: 12, decoration: isAbsent ? TextDecoration.lineThrough : null)),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => setState(() { _selectedStudentIds.remove(id); _studentTransferDates.remove(id); _absentStudentIds.remove(id); }),
              backgroundColor: isAbsent ? Colors.grey.shade200 : Colors.grey.shade100, side: BorderSide.none,
            ));
          }).toList())),
        ])),
        const Divider(height: 1),
      ],
      
      _buildListTile(icon: Icons.notes, child: TextFormField(
        controller: _notesController,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'メモを追加',
          hintStyle: TextStyle(color: Colors.grey),
          border: InputBorder.none,
          filled: true,
          fillColor: Colors.white,
        ),
      )),
      const SizedBox(height: 40),
    ]);
  }

  Widget _buildLocationTab(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade400),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? AppColors.primary : Colors.grey.shade600, fontSize: 12)),
      ),
    );
  }

  Widget _buildListTile({required IconData icon, required Widget child}) {
    return Padding(padding: const EdgeInsets.only(left: 16, right: 16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 16), child: Icon(icon, color: Colors.grey.shade600, size: 24)),
      const SizedBox(width: 16),
      Expanded(child: child),
    ]));
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initialDate = isStart ? _startDate : _endDate;
    final date = await showDatePicker(context: context, initialDate: initialDate, firstDate: DateTime(2020), lastDate: DateTime(2030), locale: const Locale('ja'));
    if (date != null && mounted) {
      if (_isAllDay) {
        setState(() { if (isStart) { _startDate = DateTime(date.year, date.month, date.day); if (_endDate.isBefore(_startDate)) _endDate = _startDate; } else { _endDate = DateTime(date.year, date.month, date.day); } });
      } else {
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate));
        if (time != null) setState(() { if (isStart) { _startDate = DateTime(date.year, date.month, date.day, time.hour, time.minute); if (_endDate.isBefore(_startDate)) _endDate = _startDate.add(const Duration(hours: 1)); } else { _endDate = DateTime(date.year, date.month, date.day, time.hour, time.minute); } });
      }
    }
  }

  void _showRecurrenceDialog() {
    showDialog(context: context, builder: (ctx) => SimpleDialog(title: const Text('繰り返し'), children: _recurrenceOptions.map((opt) => SimpleDialogOption(onPressed: () { setState(() => _recurrenceType = opt); Navigator.pop(ctx); }, child: Row(children: [if (_recurrenceType == opt) const Icon(Icons.check, color: AppColors.primary, size: 20) else const SizedBox(width: 20), const SizedBox(width: 12), Text(opt)]))).toList()));
  }

  // ★修正: PC版は中央モーダル、スマホ版はボトムシート
  void _showClassroomDialog() {
    final bool isPC = MediaQuery.of(context).size.width >= 800;
    
    if (isPC) {
      // PC版: 中央モーダル
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('教室を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ..._classroomList.map((room) => ListTile(
                  leading: _selectedClassroom == room 
                    ? const Icon(Icons.check, color: AppColors.primary) 
                    : const SizedBox(width: 24),
                  title: Text(room),
                  onTap: () {
                    setState(() {
                      _selectedClassroom = room;
                      if (!_isEditing) {
                        _selectedStudentIds.clear();
                        _studentNamesMap.clear();
                      }
                    });
                    Navigator.pop(ctx);
                  },
                )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    } else {
      // スマホ版: 従来のボトムシート
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('教室を選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ..._classroomList.map((room) => ListTile(
                leading: _selectedClassroom == room 
                  ? const Icon(Icons.check, color: AppColors.primary) 
                  : const SizedBox(width: 24),
                title: Text(room),
                onTap: () {
                  setState(() {
                    _selectedClassroom = room;
                    if (!_isEditing) {
                      _selectedStudentIds.clear();
                      _studentNamesMap.clear();
                    }
                  });
                  Navigator.pop(ctx);
                },
              )),
            ],
          ),
        ),
      );
    }
  }

  void _showStudentActionSheet(String studentId) {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.event_busy), title: Text(_absentStudentIds.contains(studentId) ? '欠席を取り消す' : '欠席にする'), onTap: () { Navigator.pop(ctx); setState(() { if (_absentStudentIds.contains(studentId)) _absentStudentIds.remove(studentId); else { _absentStudentIds.add(studentId); _studentTransferDates.remove(studentId); } }); }),
      ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('振替元の日付を設定'), onTap: () async { Navigator.pop(ctx); final picked = await showDatePicker(context: context, initialDate: _studentTransferDates[studentId] ?? DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(2030)); if (picked != null) setState(() { _studentTransferDates[studentId] = picked; _absentStudentIds.remove(studentId); }); }),
      ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('削除', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(ctx); setState(() { _selectedStudentIds.remove(studentId); _studentTransferDates.remove(studentId); _absentStudentIds.remove(studentId); }); }),
    ])));
  }

  // ★修正: PC版は中央モーダル、スマホ版はボトムシート
  void _showStudentSelectSheet() {
    final bool isPC = MediaQuery.of(context).size.width >= 800;
    
    if (isPC) {
      // PC版: 中央モーダル
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 500,
            height: MediaQuery.of(context).size.height * 0.8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _PersonSelectSheet(
                title: '生徒を選択',
                type: 'student',
                filterKey: _isManualLocation ? null : _selectedClassroom,
                initialSelectedIds: _selectedStudentIds,
                onConfirmed: (items) {
                  setState(() {
                    _selectedStudentIds.clear();
                    _selectedStudentIds.addAll(items.keys);
                    _studentNamesMap.addAll(items);
                  });
                },
              ),
            ),
          ),
        ),
      );
    } else {
      // スマホ版: 従来のボトムシート
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PersonSelectSheet(
          title: '生徒を選択',
          type: 'student',
          filterKey: _isManualLocation ? null : _selectedClassroom,
          initialSelectedIds: _selectedStudentIds,
          onConfirmed: (items) {
            setState(() {
              _selectedStudentIds.clear();
              _selectedStudentIds.addAll(items.keys);
              _studentNamesMap.addAll(items);
            });
          },
        ),
      );
    }
  }

  // ★修正: PC版は中央モーダル、スマホ版はボトムシート
  void _showStaffSelectSheet() {
    final bool isPC = MediaQuery.of(context).size.width >= 800;
    
    if (isPC) {
      // PC版: 中央モーダル
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 500,
            height: MediaQuery.of(context).size.height * 0.8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _PersonSelectSheet(
                title: '担当者を選択',
                type: 'staff',
                initialSelectedIds: _selectedStaffIds,
                onConfirmed: (items) {
                  setState(() {
                    _selectedStaffIds.clear();
                    _selectedStaffIds.addAll(items.keys);
                    _staffNamesMap.addAll(items);
                  });
                },
              ),
            ),
          ),
        ),
      );
    } else {
      // スマホ版: 従来のボトムシート
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PersonSelectSheet(
          title: '担当者を選択',
          type: 'staff',
          initialSelectedIds: _selectedStaffIds,
          onConfirmed: (items) {
            setState(() {
              _selectedStaffIds.clear();
              _selectedStaffIds.addAll(items.keys);
              _staffNamesMap.addAll(items);
            });
          },
        ),
      );
    }
  }
}

class _PersonSelectSheet extends StatefulWidget {
  final String title;
  final String type;
  final String? filterKey;
  final Set<String> initialSelectedIds;
  final Function(Map<String, String>) onConfirmed;
  
  const _PersonSelectSheet({
    required this.title,
    required this.type,
    this.filterKey,
    required this.initialSelectedIds,
    required this.onConfirmed,
  });
  
  @override
  State<_PersonSelectSheet> createState() => _PersonSelectSheetState();
}

class _PersonSelectSheetState extends State<_PersonSelectSheet> {
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _filteredPeople = [];
  final Map<String, String> _selectedMap = {};
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  // あいうえお行のマッピング
  static const Map<String, String> _kanaToGroup = {
    'あ': 'あ', 'い': 'あ', 'う': 'あ', 'え': 'あ', 'お': 'あ',
    'ア': 'あ', 'イ': 'あ', 'ウ': 'あ', 'エ': 'あ', 'オ': 'あ',
    'か': 'か', 'き': 'か', 'く': 'か', 'け': 'か', 'こ': 'か',
    'カ': 'か', 'キ': 'か', 'ク': 'か', 'ケ': 'か', 'コ': 'か',
    'が': 'か', 'ぎ': 'か', 'ぐ': 'か', 'げ': 'か', 'ご': 'か',
    'ガ': 'か', 'ギ': 'か', 'グ': 'か', 'ゲ': 'か', 'ゴ': 'か',
    'さ': 'さ', 'し': 'さ', 'す': 'さ', 'せ': 'さ', 'そ': 'さ',
    'サ': 'さ', 'シ': 'さ', 'ス': 'さ', 'セ': 'さ', 'ソ': 'さ',
    'ざ': 'さ', 'じ': 'さ', 'ず': 'さ', 'ぜ': 'さ', 'ぞ': 'さ',
    'ザ': 'さ', 'ジ': 'さ', 'ズ': 'さ', 'ゼ': 'さ', 'ゾ': 'さ',
    'た': 'た', 'ち': 'た', 'つ': 'た', 'て': 'た', 'と': 'た',
    'タ': 'た', 'チ': 'た', 'ツ': 'た', 'テ': 'た', 'ト': 'た',
    'だ': 'た', 'ぢ': 'た', 'づ': 'た', 'で': 'た', 'ど': 'た',
    'ダ': 'た', 'ヂ': 'た', 'ヅ': 'た', 'デ': 'た', 'ド': 'た',
    'な': 'な', 'に': 'な', 'ぬ': 'な', 'ね': 'な', 'の': 'な',
    'ナ': 'な', 'ニ': 'な', 'ヌ': 'な', 'ネ': 'な', 'ノ': 'な',
    'は': 'は', 'ひ': 'は', 'ふ': 'は', 'へ': 'は', 'ほ': 'は',
    'ハ': 'は', 'ヒ': 'は', 'フ': 'は', 'ヘ': 'は', 'ホ': 'は',
    'ば': 'は', 'び': 'は', 'ぶ': 'は', 'べ': 'は', 'ぼ': 'は',
    'バ': 'は', 'ビ': 'は', 'ブ': 'は', 'ベ': 'は', 'ボ': 'は',
    'ぱ': 'は', 'ぴ': 'は', 'ぷ': 'は', 'ぺ': 'は', 'ぽ': 'は',
    'パ': 'は', 'ピ': 'は', 'プ': 'は', 'ペ': 'は', 'ポ': 'は',
    'ま': 'ま', 'み': 'ま', 'む': 'ま', 'め': 'ま', 'も': 'ま',
    'マ': 'ま', 'ミ': 'ま', 'ム': 'ま', 'メ': 'ま', 'モ': 'ま',
    'や': 'や', 'ゆ': 'や', 'よ': 'や',
    'ヤ': 'や', 'ユ': 'や', 'ヨ': 'や',
    'ら': 'ら', 'り': 'ら', 'る': 'ら', 'れ': 'ら', 'ろ': 'ら',
    'ラ': 'ら', 'リ': 'ら', 'ル': 'ら', 'レ': 'ら', 'ロ': 'ら',
    'わ': 'わ', 'を': 'わ', 'ん': 'わ',
    'ワ': 'わ', 'ヲ': 'わ', 'ン': 'わ',
  };

  String _getGroup(String kana) {
    if (kana.isEmpty) return '他';
    final firstChar = kana[0];
    return _kanaToGroup[firstChar] ?? '他';
  }

  @override
  void initState() {
    super.initState();
    for (var id in widget.initialSelectedIds) _selectedMap[id] = '';
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
          final parentLastNameKana = data['lastNameKana'] ?? parentLastName;
          final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
          for (var child in children) {
            if (widget.filterKey != null && child['classroom'] != widget.filterKey) continue;
            final childName = child['firstName'] ?? '';
            final fullName = '$parentLastName $childName';
            final uniqueId = '${data['uid']}_$childName';
            // ふりがなは姓のかなを使用
            final kana = parentLastNameKana;
            loaded.add({'id': uniqueId, 'name': fullName, 'kana': kana, 'group': _getGroup(kana)});
            if (_selectedMap.containsKey(uniqueId)) _selectedMap[uniqueId] = fullName;
          }
        }
      } else {
        final snapshot = await FirebaseFirestore.instance.collection('staffs').get();
        for (var doc in snapshot.docs) {
          final data = doc.data();
          String name = data['name'] ?? '${data['lastName'] ?? ''} ${data['firstName'] ?? ''}';
          final uid = data['uid'] ?? doc.id;
          final kana = data['furigana'] ?? data['lastNameKana'] ?? name;
          loaded.add({'id': uid, 'name': name, 'kana': kana, 'group': _getGroup(kana)});
          if (_selectedMap.containsKey(uid)) _selectedMap[uid] = name;
        }
      }
      // あいうえお順でソート
      loaded.sort((a, b) => (a['kana'] as String).compareTo(b['kana'] as String));
      setState(() { _people = loaded; _filteredPeople = loaded; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  // グループ化されたリストを構築
  List<dynamic> _buildGroupedList() {
    final List<dynamic> result = [];
    String? currentGroup;
    
    for (var person in _filteredPeople) {
      final group = person['group'] as String;
      if (group != currentGroup) {
        currentGroup = group;
        result.add({'type': 'header', 'group': group});
      }
      result.add({'type': 'person', 'data': person});
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final groupedList = _buildGroupedList();
    final bool isPC = MediaQuery.of(context).size.width >= 800;
    
    return Container(
      // PC版では高さを親に任せる、スマホ版では85%
      height: isPC ? null : MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: isPC 
          ? BorderRadius.circular(16)
          : const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // スマホ版のみドラッグハンドルを表示
        if (!isPC)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(isPC ? 20 : 16),
          child: Column(children: [
            // PC版ではタイトル行に閉じるボタンを追加
            if (isPC)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              )
            else
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '名前で検索...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (q) => setState(() => _filteredPeople = q.isEmpty ? _people : _people.where((p) => p['name'].contains(q) || p['kana'].contains(q)).toList()),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredPeople.isEmpty
                  ? const Center(child: Text('該当者がいません'))
                  : ListView.builder(
                      itemCount: groupedList.length,
                      itemBuilder: (context, index) {
                        final item = groupedList[index];
                        
                        if (item['type'] == 'header') {
                          // グループヘッダー（あ、か、さ...）
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.grey.shade100,
                            child: Text(
                              item['group'],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          );
                        } else {
                          // 人のリストアイテム
                          final person = item['data'];
                          return CheckboxListTile(
                            value: _selectedMap.containsKey(person['id']),
                            activeColor: AppColors.primary,
                            title: Text(person['name']),
                            // スマホ版のみふりがなを表示
                            subtitle: isPC ? null : Text(person['kana'], style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            onChanged: (val) => setState(() {
                              if (val == true) _selectedMap[person['id']] = person['name'];
                              else _selectedMap.remove(person['id']);
                            }),
                          );
                        }
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('${_selectedMap.length}名を選択して完了', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}