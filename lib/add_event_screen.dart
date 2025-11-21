import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore

class AddEventScreen extends StatefulWidget {
  // 編集用データ
  final Appointment? appointment;
  // カレンダーからタップで渡される初期日時（新規作成用）
  final DateTime? initialStartDate;

  const AddEventScreen({
    super.key,
    this.appointment,
    this.initialStartDate,
  });

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  String _selectedCategory = 'レッスン';
  final List<String> _categories = ['レッスン', 'イベント', 'その他'];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _studentsController = TextEditingController();
  final TextEditingController _participantsController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  // プルダウン用の選択値
  String? _selectedRoom;
  String? _selectedTeacher;

  // Firestoreから取得するリスト
  List<String> _classroomList = [];
  List<String> _teacherList = [];
  bool _isLoading = true;

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);

  @override
  void initState() {
    super.initState();
    _fetchMasterData(); // マスタデータを取得
  }

  // Firestoreから教室と講師のリストを取得
  Future<void> _fetchMasterData() async {
    try {
      // 教室リスト取得
      final roomSnapshot = await FirebaseFirestore.instance.collection('classrooms').get();
      final rooms = roomSnapshot.docs.map((doc) => doc['name'] as String).toList();

      // 講師リスト取得
      final staffSnapshot = await FirebaseFirestore.instance.collection('staffs').get();
      final staffs = staffSnapshot.docs.map((doc) => doc['name'] as String).toList();

      if (mounted) {
        setState(() {
          _classroomList = rooms;
          _teacherList = staffs;
          _isLoading = false;
          
          // データ取得後に初期値をセット
          _initializeValues();
        });
      }
    } catch (e) {
      // エラーハンドリング（今回は簡易ログのみ）
      debugPrint('Error fetching master data: $e');
      if (mounted) setState(() => _isLoading = false);
      _initializeValues();
    }
  }

  void _initializeValues() {
    // 1. 編集モードの場合
    if (widget.appointment != null) {
      final appt = widget.appointment!;
      _titleController.text = appt.subject;
      _selectedDate = appt.startTime;
      _startTime = TimeOfDay.fromDateTime(appt.startTime);
      _endTime = TimeOfDay.fromDateTime(appt.endTime);

      // 色判定
      if (appt.color == const Color(0xFFEA4335)) {
        _selectedCategory = 'イベント';
      } else if (appt.color == Colors.orange) {
        _selectedCategory = 'その他';
      } else {
        _selectedCategory = 'レッスン';
      }
      
      _restoreNotes(appt.notes ?? '');
    } 
    // 2. 新規作成の場合
    else if (widget.initialStartDate != null) {
      _selectedDate = widget.initialStartDate!;
      _startTime = TimeOfDay.fromDateTime(widget.initialStartDate!);
      final endDateTime = widget.initialStartDate!.add(const Duration(hours: 1));
      _endTime = TimeOfDay.fromDateTime(endDateTime);
    }
  }

  void _restoreNotes(String notes) {
    if (_selectedCategory == 'その他') {
      _participantsController.text = _extractValue(notes, '参加者');
      _detailsController.text = _extractValue(notes, '詳細');
    } else {
      // 保存された値がマスタにあるか確認し、あればセット。なければnull（選択なし）
      final savedRoom = _extractValue(notes, '教室');
      final savedTeacher = _extractValue(notes, '講師');
      
      if (_classroomList.contains(savedRoom)) _selectedRoom = savedRoom;
      if (_teacherList.contains(savedTeacher)) _selectedTeacher = savedTeacher;
      
      _studentsController.text = _extractValue(notes, '児童');
    }
  }

  String _extractValue(String notes, String key) {
    final RegExp regex = RegExp('$key: (.*)');
    final match = regex.firstMatch(notes);
    if (match != null) {
      return match.group(1) ?? '';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // 背景を薄いグレーに
      appBar: AppBar(
        title: Text(widget.appointment == null ? '予定の追加' : '予定の編集'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saveEvent,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Center(
        // ★横幅を制限して、PC画面でも見やすくする
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // カテゴリ選択
                const Text('カテゴリ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 8.0,
                    alignment: WrapAlignment.start,
                    children: _categories.map((category) {
                      return ChoiceChip(
                        label: Text(category),
                        selected: _selectedCategory == category,
                        onSelected: (bool selected) {
                          if (selected) setState(() => _selectedCategory = category);
                        },
                        selectedColor: Colors.orange.shade100,
                        backgroundColor: Colors.white,
                        checkmarkColor: Colors.deepOrange,
                        labelStyle: TextStyle(
                          color: _selectedCategory == category ? Colors.deepOrange : Colors.black87,
                          fontWeight: _selectedCategory == category ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                
                const SizedBox(height: 24),

                // 日時選択カード
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildDateTimePicker(),
                ),
                
                const SizedBox(height: 24),

                // 入力フォームカード
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      if (_selectedCategory == 'その他') ...[
                        _buildTextField(_titleController, 'タイトル (例: スタッフ会議)', Icons.title),
                        const SizedBox(height: 16),
                        _buildTextField(_participantsController, '参加者', Icons.people),
                        const SizedBox(height: 16),
                        _buildTextField(_detailsController, '詳細・メモ', Icons.notes, maxLines: 3),
                      ] else ...[
                        _buildTextField(_titleController, 'レッスン名 / イベント名', Icons.event),
                        const SizedBox(height: 16),
                        
                        // ★プルダウン (教室)
                        DropdownButtonFormField<String>(
                          value: _selectedRoom,
                          decoration: const InputDecoration(
                            labelText: '教室名',
                            prefixIcon: Icon(Icons.room, color: Colors.grey),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFF9F9F9),
                          ),
                          items: _classroomList.map((room) => DropdownMenuItem(value: room, child: Text(room))).toList(),
                          onChanged: (val) => setState(() => _selectedRoom = val),
                        ),
                        const SizedBox(height: 16),
                        
                        // ★プルダウン (講師)
                        DropdownButtonFormField<String>(
                          value: _selectedTeacher,
                          decoration: const InputDecoration(
                            labelText: '講師名',
                            prefixIcon: Icon(Icons.person, color: Colors.grey),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFF9F9F9),
                          ),
                          items: _teacherList.map((staff) => DropdownMenuItem(value: staff, child: Text(staff))).toList(),
                          onChanged: (val) => setState(() => _selectedTeacher = val),
                        ),
                        
                        const SizedBox(height: 16),
                        _buildTextField(_studentsController, '児童 (例: 山田太郎, 鈴木花子)', Icons.face),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimePicker() {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('日付', style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          onTap: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) setState(() => _selectedDate = picked);
          },
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('開始時間', style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _startTime.format(context),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(context: context, initialTime: _startTime);
            if (picked != null) setState(() => _startTime = picked);
          },
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('終了時間', style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _endTime.format(context),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(context: context, initialTime: _endTime);
            if (picked != null) setState(() => _endTime = picked);
          },
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: const Color(0xFFF9F9F9),
      ),
    );
  }

  void _saveEvent() {
    if (_titleController.text.trim().isEmpty) {
      _showErrorDialog('タイトルを入力してください');
      return;
    }

    final DateTime startTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _startTime.hour, _startTime.minute,
    );
    final DateTime endTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _endTime.hour, _endTime.minute,
    );

    if (endTime.isBefore(startTime)) {
      _showErrorDialog('終了時間は開始時間よりあとに設定してください');
      return;
    }

    // 色の決定ロジック
    // 本来は「教室マスタ」から色を引くのがベストですが、今回はカテゴリ分けを維持します。
    // もし教室の色を反映させたい場合は、_classroomListと一緒のMapで色も持ってくる必要があります。
    Color eventColor = const Color(0xFF4285F4);
    if (_selectedCategory == 'イベント') eventColor = const Color(0xFFEA4335);
    if (_selectedCategory == 'その他') eventColor = Colors.orange;

    String notes = '';
    if (_selectedCategory == 'その他') {
      notes = '参加者: ${_participantsController.text}\n詳細: ${_detailsController.text}';
    } else {
      // プルダウンの値を保存
      notes = '教室: ${_selectedRoom ?? ""}\n講師: ${_selectedTeacher ?? ""}\n児童: ${_studentsController.text}';
    }

    final Appointment newEvent = Appointment(
      startTime: startTime,
      endTime: endTime,
      subject: _titleController.text,
      color: eventColor,
      notes: notes,
    );

    Navigator.of(context).pop(newEvent);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('入力エラー', style: TextStyle(color: Colors.red)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}