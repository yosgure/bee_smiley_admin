import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'plus_dashboard_screen.dart';

/// プラス予定のコンテンツウィジェット（埋め込み用）
class PlusScheduleContent extends StatefulWidget {
  final VoidCallback? onBack;
  
  const PlusScheduleContent({super.key, this.onBack});

  @override
  State<PlusScheduleContent> createState() => _PlusScheduleContentState();
}

class _PlusScheduleContentState extends State<PlusScheduleContent> {
  late DateTime _weekStart;
  
  // 表示モード: 0=カレンダー, 1=ダッシュボード
  int _viewMode = 0;

  final List<String> _timeSlots = ['9:30〜', '11:00〜', '14:00〜', '15:30〜'];

  // シフトデータ（月単位でキャッシュ）
  Map<String, List<Map<String, dynamic>>> _shiftData = {};
  String _loadedShiftMonth = '';
  
  // 休み設定（日付のセット）
  Set<String> _holidays = {};
  
  // 週単位コピー用のシフトデータ
  Map<int, List<Map<String, dynamic>>>? _copiedWeekShifts;
  // 週単位コピー用のレッスンデータ
  List<Map<String, dynamic>>? _copiedWeekLessons;
  String _copiedWeekLabel = '';

  // コース（内容）の定義と色
  static const Map<String, Color> _courseColors = {
    '通常': Colors.blue,
    'モンテッソーリ': Colors.lightBlue,
    '感覚統合': Colors.teal,
    '言語': Colors.purple,
    '就学支援': Colors.indigo,
    '契約': Colors.orange,
    '体験': Colors.green,
    '欠席': Colors.red,
  };

  final List<String> _courseList = ['通常', 'モンテッソーリ', '感覚統合', '言語', '就学支援', '契約', '体験', '欠席'];

  // レッスンデータ（Firestoreから取得）
  List<Map<String, dynamic>> _lessons = [];
  bool _isLoadingLessons = true;
  
  // 生徒リスト（familiesから取得）
  List<Map<String, dynamic>> _allStudents = [];

  // 部屋リスト
  final List<String> _roomList = ['つき', 'ほし', 'にじ', 'そら', '訪問'];

  // スタッフリスト（シフト編集用）
  List<Map<String, dynamic>> _staffList = [];
  
  // ドラッグ中のレッスン（行間インジケーター表示用）
  Map<String, dynamic>? _draggingLesson;
  
  // 生徒メモ（療育プラン、園訪問、就学相談、移動希望）のキャッシュ
  final Map<String, Map<String, dynamic>> _studentNotes = {};
  
  // 全タスクリスト
  List<Map<String, dynamic>> _allTasks = [];
  
  // 期限日ごとのタスク（カレンダー表示用）
  Map<String, List<Map<String, dynamic>>> _tasksByDueDate = {};
  
  // ホバーポップアップ用のオーバーレイエントリ（グローバル管理）
  OverlayEntry? _currentOverlay;
  
  // サイドメニュー関連
  bool _isSideMenuOpen = false;
  DateTime _sideMenuMonth = DateTime.now();
  Set<String> _selectedFilters = {'all'}; // 'all', 'mySchedule', 'event', または講師名

  @override
  void initState() {
    super.initState();
    _weekStart = _getMonday(DateTime.now());
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _hideCurrentOverlay();
    super.dispose();
  }
  
  void _hideCurrentOverlay() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadStaffList(),
      _loadShiftData(),
      _loadLessonsForWeek(),
      _loadStudentsFromFirestore(),
      _loadAllTasks(),
    ]);
  }
  
  // 全タスクを読み込み
  Future<void> _loadAllTasks() async {
    try {
      debugPrint('Loading all tasks...');
      // インデックス不要なクエリに変更
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_tasks')
          .where('completed', isEqualTo: false)
          .get();
      
      debugPrint('Found ${snapshot.docs.length} tasks');
      
      final tasks = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? '',
          'comment': data['comment'] ?? '', // dashboardと同期
          'studentName': data['studentName'],
          'dueDate': data['dueDate'],
          'isCustom': data['isCustom'] ?? (data['studentName'] == null), // dashboardと同期
          'completed': data['completed'] ?? false,
          'createdAt': data['createdAt'],
        };
      }).toList();
      
      // クライアント側でソート
      tasks.sort((a, b) {
        final dateA = a['dueDate'] as Timestamp?;
        final dateB = b['dueDate'] as Timestamp?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.toDate().compareTo(dateB.toDate());
      });
      
      // 期限日ごとにグループ化
      final tasksByDate = <String, List<Map<String, dynamic>>>{};
      for (var task in tasks) {
        final dueDate = task['dueDate'] as Timestamp?;
        if (dueDate != null) {
          final dateKey = DateFormat('yyyy-MM-dd').format(dueDate.toDate());
          tasksByDate.putIfAbsent(dateKey, () => []);
          tasksByDate[dateKey]!.add(task);
        }
      }
      
      if (mounted) {
        setState(() {
          _allTasks = tasks;
          _tasksByDueDate = tasksByDate;
        });
      }
      debugPrint('Tasks loaded: ${_allTasks.length}');
    } catch (e, stackTrace) {
      debugPrint('Error loading tasks: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  // 生徒メモを読み込み（キャッシュがあればそれを返す）
  Future<Map<String, dynamic>> _loadStudentNotes(String studentName) async {
    if (_studentNotes.containsKey(studentName)) {
      return _studentNotes[studentName]!;
    }
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('plus_student_notes')
          .doc(studentName)
          .get();
      
      final data = doc.exists ? doc.data() ?? {} : {};
      final notes = {
        'therapyPlan': data['therapyPlan'] ?? '',
        'schoolVisit': data['schoolVisit'] ?? '',
        'schoolConsultation': data['schoolConsultation'] ?? '',
        'moveRequest': data['moveRequest'] ?? '',
      };
      
      _studentNotes[studentName] = notes;
      return notes;
    } catch (e) {
      debugPrint('Error loading student notes: $e');
      return {'therapyPlan': '', 'schoolVisit': '', 'schoolConsultation': '', 'moveRequest': ''};
    }
  }
  
  // 生徒メモを保存
  Future<void> _saveStudentNotes(String studentName, Map<String, dynamic> notes) async {
    try {
      await FirebaseFirestore.instance
          .collection('plus_student_notes')
          .doc(studentName)
          .set({
        ...notes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      _studentNotes[studentName] = notes;
    } catch (e) {
      debugPrint('Error saving student notes: $e');
    }
  }
  
  // タスクを追加
  Future<Map<String, dynamic>?> _addTaskForStudent(String? studentName, String title, DateTime? dueDate) async {
    try {
      debugPrint('Adding task: studentName=$studentName, title=$title, dueDate=$dueDate');
      
      // dashboardと同じ構造で保存
      final taskData = {
        'title': title,
        'comment': '', // dashboardと同期
        'studentName': studentName,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
        'isCustom': studentName == null, // dashboardと同期
        'completed': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      final docRef = await FirebaseFirestore.instance.collection('plus_tasks').add(taskData);
      debugPrint('Task added with id: ${docRef.id}');
      
      // 新しいタスクを返す
      final newTask = {
        'id': docRef.id,
        'title': title,
        'comment': '',
        'studentName': studentName,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
        'isCustom': studentName == null,
        'completed': false,
      };
      
      // _allTasksにも追加
      if (mounted) {
        setState(() {
          _allTasks.add(newTask);
          if (dueDate != null) {
            final dateKey = DateFormat('yyyy-MM-dd').format(dueDate);
            _tasksByDueDate.putIfAbsent(dateKey, () => []);
            _tasksByDueDate[dateKey]!.add(newTask);
          }
        });
      }
      
      return newTask;
    } catch (e, stackTrace) {
      debugPrint('Error adding task: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // エラーメッセージを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('タスクの追加に失敗しました: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      return null;
    }
  }
  
  // タスクを完了（削除）
  Future<void> _completeTask(String taskId) async {
    try {
      await FirebaseFirestore.instance.collection('plus_tasks').doc(taskId).delete();
      await _loadAllTasks();
    } catch (e) {
      debugPrint('Error completing task: $e');
    }
  }
  
  // タスク編集ダイアログ
  void _showEditTaskDialog(BuildContext parentContext, Map<String, dynamic> task, VoidCallback onUpdate) {
    final titleController = TextEditingController(text: task['title'] ?? '');
    DateTime? dueDate = task['dueDate'] != null 
        ? (task['dueDate'] as Timestamp).toDate() 
        : null;
    
    showDialog(
      context: parentContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.edit, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                const Text('タスクを編集', style: TextStyle(fontSize: 16)),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: dialogContext,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: const Text('タスクを削除'),
                        content: const Text('このタスクを削除しますか？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('削除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _completeTask(task['id']);
                      onUpdate();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: '削除',
                ),
              ],
            ),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'タスク内容',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('期限日:', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: dueDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: dueDate != null ? AppColors.primary : AppColors.textSub),
                              const SizedBox(width: 8),
                              Text(
                                dueDate != null ? DateFormat('M月d日').format(dueDate!) : '未設定',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: dueDate != null ? AppColors.textMain : AppColors.textSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (dueDate != null)
                        IconButton(
                          onPressed: () => setDialogState(() => dueDate = null),
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'クリア',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newTitle = titleController.text.trim();
                  if (newTitle.isEmpty) return;
                  
                  try {
                    await FirebaseFirestore.instance
                        .collection('plus_tasks')
                        .doc(task['id'])
                        .update({
                      'title': newTitle,
                      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
                    });
                    await _loadAllTasks();
                    onUpdate();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    debugPrint('Error updating task: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  // 生徒のタスクを取得
  List<Map<String, dynamic>> _getTasksForStudent(String studentName) {
    return _allTasks.where((t) => t['studentName'] == studentName).toList();
  }
  
  // 生徒メモを先読み（非同期でバックグラウンド読み込み）
  Future<void> _preloadStudentNotes(List<Map<String, dynamic>> lessons) async {
    final studentNames = lessons
        .map((l) => l['studentName'] as String?)
        .where((name) => name != null && name.isNotEmpty)
        .toSet();
    
    for (var name in studentNames) {
      if (name != null && !_studentNotes.containsKey(name)) {
        await _loadStudentNotes(name);
      }
    }
    
    // 読み込み完了後に再描画
    if (mounted) {
      setState(() {});
    }
  }
  
  // 生徒の全情報があるかチェック（ホバー表示用）
  bool _hasStudentInfo(String studentName) {
    final notes = _studentNotes[studentName];
    final tasks = _getTasksForStudent(studentName);
    
    if (notes != null) {
      if ((notes['therapyPlan'] ?? '').isNotEmpty) return true;
      if ((notes['schoolVisit'] ?? '').isNotEmpty) return true;
      if ((notes['schoolConsultation'] ?? '').isNotEmpty) return true;
      if ((notes['moveRequest'] ?? '').isNotEmpty) return true;
    }
    if (tasks.isNotEmpty) return true;
    
    return false;
  }

  // familiesコレクションから全児童リストを取得（プラスのみ）
  Future<void> _loadStudentsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('families')
          .get();

      final students = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lastName = data['lastName'] as String? ?? '';
        final lastNameKana = data['lastNameKana'] as String? ?? '';
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
        
        for (var child in children) {
          final firstName = child['firstName'] as String? ?? '';
          final classroom = child['classroom'] as String? ?? '';
          
          // プラスの教室のみ
          if (firstName.isNotEmpty && classroom.contains('プラス')) {
            students.add({
              'name': '$lastName $firstName'.trim(),
              'firstName': firstName,
              'lastName': lastName,
              'lastNameKana': lastNameKana,
              'classroom': classroom,
              'course': child['course'] ?? '',
            });
          }
        }
      }
      
      // ふりがな順でソート
      students.sort((a, b) {
        final kanaA = (a['lastNameKana'] as String?) ?? '';
        final kanaB = (b['lastNameKana'] as String?) ?? '';
        return kanaA.compareTo(kanaB);
      });
      
      if (mounted) {
        setState(() {
          _allStudents = students;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
    }
  }

  // Firestoreから週のレッスンデータを読み込み
  Future<void> _loadLessonsForWeek() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingLessons = true;
    });
    
    try {
      // 週の開始日（月曜日）と終了日（土曜日）を日付のみで計算
      final weekStartDate = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
      final saturdayDate = weekStartDate.add(const Duration(days: 5));
      final weekEndDate = DateTime(saturdayDate.year, saturdayDate.month, saturdayDate.day, 23, 59, 59);
      
      // 開始日以降のデータを取得（クライアント側で終了日フィルタリング）
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStartDate))
          .orderBy('date')
          .get();
      
      if (!mounted) return;
      
      final lessons = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // dateがnullまたは不正な場合はスキップ
        final dateField = data['date'];
        if (dateField == null || dateField is! Timestamp) continue;
        
        final date = dateField.toDate();
        
        // 週の終了日より後ならスキップ
        if (date.isAfter(weekEndDate)) continue;
        
        // 日付のみで比較（時刻を無視）
        final dateOnly = DateTime(date.year, date.month, date.day);
        final weekStartOnly = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
        final dayIndex = dateOnly.difference(weekStartOnly).inDays;
        
        // 週の範囲外はスキップ
        if (dayIndex < 0 || dayIndex > 5) continue;
        
        lessons.add({
          'id': doc.id,
          'dayIndex': dayIndex,
          'slotIndex': data['slotIndex'] ?? 0,
          'studentName': data['studentName'] ?? '',
          'teachers': List<String>.from(data['teachers'] ?? []),
          'room': data['room'] ?? '',
          'course': data['course'] ?? '通常',
          'note': data['note'] ?? '',
          'link': data['link'] ?? '',
          'date': date,
          'order': data['order'] ?? (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
        });
      }
      
      if (mounted) {
        // 同じセル内の順序を order（作成順）でソート
        lessons.sort((a, b) {
          final dayCompare = (a['dayIndex'] as int).compareTo(b['dayIndex'] as int);
          if (dayCompare != 0) return dayCompare;
          final slotCompare = (a['slotIndex'] as int).compareTo(b['slotIndex'] as int);
          if (slotCompare != 0) return slotCompare;
          return (a['order'] as int).compareTo(b['order'] as int);
        });
        
        setState(() {
          _lessons = lessons;
          _isLoadingLessons = false;
        });
        
        // 生徒メモを先読み（UIをブロックしない）
        _preloadStudentNotes(lessons);
      }
    } catch (e) {
      debugPrint('Error loading lessons: $e');
      if (mounted) {
        setState(() {
          _isLoadingLessons = false;
        });
      }
    }
  }

  DateTime _getMonday(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    // 時刻を00:00:00にリセット（日付計算の精度を確保）
    return DateTime(monday.year, monday.month, monday.day);
  }

  void _previousWeek() {
    _hideCurrentOverlay();
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
    });
    _loadShiftData();
    _loadLessonsForWeek();
    _loadAllTasks(); // タスクも再読み込み
  }

  void _nextWeek() {
    _hideCurrentOverlay();
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
    });
    _loadShiftData();
    _loadLessonsForWeek();
    _loadAllTasks(); // タスクも再読み込み
  }

  void _goToThisWeek() {
    _hideCurrentOverlay();
    setState(() {
      _weekStart = _getMonday(DateTime.now());
    });
    _loadShiftData();
    _loadLessonsForWeek();
    _loadAllTasks(); // タスクも再読み込み
  }

  Future<void> _loadStaffList() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staffs')
          .get();
      
      if (mounted) {
        setState(() {
          _staffList = snapshot.docs.where((doc) {
            final data = doc.data();
            final classrooms = List<String>.from(data['classrooms'] ?? []);
            // プラスの教室を担当しているスタッフのみ
            return classrooms.any((c) => c.contains('プラス'));
          }).map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'name': data['name'] ?? '',
              'uid': data['uid'] ?? '',
              'isPlus': true, // プラス担当フラグを追加
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading staff list: $e');
    }
  }

  Future<void> _loadShiftData() async {
    final monthKey = DateFormat('yyyy-MM').format(_weekStart);
    
    // 既にロード済みならスキップ
    if (_loadedShiftMonth == monthKey) return;
    
    try {
      final docRef = FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(monthKey);
      
      final doc = await docRef.get();
      
      if (mounted) {
        setState(() {
          if (doc.exists) {
            final data = doc.data()!;
            final days = data['days'] as Map<String, dynamic>? ?? {};
            _shiftData = days.map((key, value) {
              return MapEntry(key, List<Map<String, dynamic>>.from(
                (value as List).map((e) => Map<String, dynamic>.from(e))
              ));
            });
            // 休み情報を読み込み
            final holidays = data['holidays'] as List<dynamic>? ?? [];
            _holidays = holidays.map((e) => e.toString()).toSet();
          } else {
            _shiftData = {};
            _holidays = {};
          }
          _loadedShiftMonth = monthKey;
        });
      }
    } catch (e) {
      debugPrint('Error loading shift data: $e');
    }
  }

  // 指定日が休みかどうか判定（月曜日 or 手動設定）
  bool _isHoliday(DateTime date) {
    // 月曜日は自動的に休み
    if (date.weekday == DateTime.monday) return true;
    
    // 手動設定の休み
    final dayKey = date.day.toString();
    return _holidays.contains(dayKey);
  }

  List<Map<String, dynamic>> _getShiftsForDate(DateTime date) {
    final dayKey = date.day.toString();
    return _shiftData[dayKey] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // スマホ（600px未満）の場合は閲覧専用UIを表示
    if (screenWidth < 600) {
      return _buildMobileUI();
    }
    
    // Web/タブレット版
    return Column(
      children: [
        // トップバー（常に表示）
        _buildHeader(),
        // サイドメニュー + メインコンテンツ
        Expanded(
          child: Row(
            children: [
              // サイドメニュー（アニメーションで開閉）- スケジュールモードのみ
              if (_viewMode == 0)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: _isSideMenuOpen ? 280 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 280,
                      maxWidth: 280,
                      child: _buildSideMenu(),
                    ),
                  ),
                ),
              // メインコンテンツ
              Expanded(
                child: _viewMode == 0
                    ? (_isLoadingLessons
                        ? const Center(child: CircularProgressIndicator())
                        : _buildScheduleTable())
                    : const PlusDashboardContent(),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // ========================================
  // スマホ用閲覧専用UI
  // ========================================
  
  // スマホ用の選択中の日付
  DateTime? _mobileSelectedDate;
  
  // スマホ用サイドメニュー
  bool _isMobileSideMenuOpen = false;
  
  DateTime get _currentMobileDate {
    if (_mobileSelectedDate != null) {
      return _mobileSelectedDate!;
    }
    // 初期値: 今日が日曜日なら翌月曜日、そうでなければ今日
    final now = DateTime.now();
    if (now.weekday == 7) {
      return now.add(const Duration(days: 1)); // 翌月曜日
    }
    return now;
  }
  
  Widget _buildMobileUI() {
    // 選択中の日付の週が現在読み込み中の週と異なる場合、再読み込み
    final currentDateWeekStart = _getMonday(_currentMobileDate);
    if (currentDateWeekStart != _weekStart && !_isLoadingLessons) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _weekStart = currentDateWeekStart;
            _isLoadingLessons = true;
          });
          _loadShiftData();
          _loadLessonsForWeek();
        }
      });
    }
    
    return SafeArea(
      child: Stack(
        children: [
          // メインコンテンツ
          Column(
            children: [
              _buildMobileHeader(),
              Expanded(
                child: _isLoadingLessons
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity == null) return;
                          // 左スワイプ → 翌日
                          if (details.primaryVelocity! < -100) {
                            _goToNextDay();
                          }
                          // 右スワイプ → 前日
                          else if (details.primaryVelocity! > 100) {
                            _goToPreviousDay();
                          }
                        },
                        child: _buildMobileDayView(),
                      ),
              ),
            ],
          ),
          // オーバーレイ（サイドメニュー表示時）
          if (_isMobileSideMenuOpen)
            GestureDetector(
              onTap: () => setState(() => _isMobileSideMenuOpen = false),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          // サイドメニュー
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            left: _isMobileSideMenuOpen ? 0 : -280,
            top: 0,
            bottom: 0,
            width: 280,
            child: _buildMobileSideMenu(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMobileSideMenu() {
    final plusStaff = _staffList.where((s) => s['isPlus'] == true).toList();
    final staffColors = [
      Colors.blue,
      Colors.teal,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
      Colors.green,
      Colors.red,
      Colors.cyan,
      Colors.amber,
    ];
    
    return Material(
      elevation: 16,
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.filter_list, color: AppColors.primary),
                  SizedBox(width: 12),
                  Text(
                    '講師フィルター',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain,
                    ),
                  ),
                ],
              ),
            ),
            // フィルターリスト
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // 全て
                  _buildMobileFilterItem('all', '全て', AppColors.primary, isSpecial: true),
                  const Divider(height: 16),
                  // スタッフリスト
                  ...plusStaff.asMap().entries.map((entry) {
                    final index = entry.key;
                    final staff = entry.value;
                    final name = staff['name'] as String? ?? '';
                    final color = staffColors[index % staffColors.length];
                    return _buildMobileFilterItem(name, name, color);
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMobileFilterItem(String key, String label, Color color, {bool isSpecial = false}) {
    final isSelected = _selectedFilters.contains(key) || 
                      (_selectedFilters.contains('all') && key != 'all');
    
    return InkWell(
      onTap: () {
        setState(() {
          if (key == 'all') {
            _selectedFilters = {'all'};
          } else {
            _selectedFilters.remove('all');
            if (_selectedFilters.contains(key)) {
              _selectedFilters.remove(key);
              if (_selectedFilters.isEmpty) {
                _selectedFilters = {'all'};
              }
            } else {
              _selectedFilters.add(key);
            }
            // 全て選択されたら「全て」に戻す
            final plusStaff = _staffList.where((s) => s['isPlus'] == true).toList();
            final allStaffNames = plusStaff.map((s) => s['name'] as String).toSet();
            if (_selectedFilters.containsAll(allStaffNames)) {
              _selectedFilters = {'all'};
            }
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                border: Border.all(color: isSelected ? color : Colors.grey.shade400, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSpecial ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMobileHeader() {
    final dateStr = DateFormat('M月d日 (E)', 'ja').format(_currentMobileDate);
    
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左側: ハンバーガーメニュー
          IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textMain),
            tooltip: 'メニュー',
            onPressed: () => setState(() => _isMobileSideMenuOpen = true),
          ),
          // 中央部分: 前日 + 日付 + 翌日
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 前日
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppColors.textSub),
                  onPressed: _goToPreviousDay,
                ),
                // 日付
                GestureDetector(
                  onTap: () => _showMobileDatePicker(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ),
                // 翌日
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppColors.textSub),
                  onPressed: _goToNextDay,
                ),
              ],
            ),
          ),
          // 右側: 今日ボタン
          TextButton(
            onPressed: _goToToday,
            child: const Text('今日'),
          ),
        ],
      ),
    );
  }
  
  void _goToPreviousDay() {
    setState(() {
      _mobileSelectedDate = _currentMobileDate.subtract(const Duration(days: 1));
      final newWeekStart = _getMonday(_currentMobileDate);
      if (newWeekStart != _weekStart) {
        _weekStart = newWeekStart;
        _loadShiftData();
        _loadLessonsForWeek();
      }
    });
  }
  
  void _goToNextDay() {
    setState(() {
      _mobileSelectedDate = _currentMobileDate.add(const Duration(days: 1));
      final newWeekStart = _getMonday(_currentMobileDate);
      if (newWeekStart != _weekStart) {
        _weekStart = newWeekStart;
        _loadShiftData();
        _loadLessonsForWeek();
      }
    });
  }
  
  void _goToToday() {
    setState(() {
      _mobileSelectedDate = DateTime.now();
      final newWeekStart = _getMonday(_currentMobileDate);
      if (newWeekStart != _weekStart) {
        _weekStart = newWeekStart;
        _loadShiftData();
        _loadLessonsForWeek();
      }
    });
  }
  
  void _showMobileDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentMobileDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ja'),
    );
    if (picked != null) {
      setState(() {
        _mobileSelectedDate = picked;
        final newWeekStart = _getMonday(_currentMobileDate);
        if (newWeekStart != _weekStart) {
          _weekStart = newWeekStart;
          _loadShiftData();
          _loadLessonsForWeek();
        }
      });
    }
  }
  
  Widget _buildMobileDayView() {
    // 選択中の日のdayIndexを計算
    final dayIndex = _currentMobileDate.difference(_weekStart).inDays;
    final isHoliday = _isHoliday(_currentMobileDate);
    final isSunday = _currentMobileDate.weekday == 7;
    
    // 日曜日の場合
    if (isSunday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.weekend, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '日曜日は休みです',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    
    // 休みの場合
    if (isHoliday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '休み',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    
    // dayIndexが範囲外の場合（週をまたいでいる）- データ読み込み待ち表示
    if (dayIndex < 0 || dayIndex > 5) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'データを読み込んでいます...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _weekStart = _getMonday(_currentMobileDate);
                });
                _loadShiftData();
                _loadLessonsForWeek();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _timeSlots.length,
      itemBuilder: (context, slotIndex) {
        return _buildMobileTimeSlot(dayIndex, slotIndex);
      },
    );
  }
  
  Widget _buildMobileTimeSlot(int dayIndex, int slotIndex) {
    final timeSlot = _timeSlots[slotIndex];
    
    // この時間帯のレッスンを取得
    var lessons = _lessons.where((lesson) =>
        lesson['dayIndex'] == dayIndex && lesson['slotIndex'] == slotIndex).toList();
    
    // フィルタリング適用
    if (!_selectedFilters.contains('all')) {
      if (_selectedFilters.isEmpty) {
        lessons = [];
      } else {
        lessons = lessons.where((lesson) {
          final teachers = lesson['teachers'] as List<dynamic>? ?? [];
          if (teachers.contains('全員')) return true;
          for (final teacher in teachers) {
            if (_selectedFilters.contains(teacher)) return true;
          }
          return false;
        }).toList();
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 時間帯ヘッダー
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  timeSlot,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${lessons.length}件',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        // レッスンカード
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 16),
            child: Text(
              '予定なし',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          )
        else
          ...lessons.map((lesson) => _buildMobileLessonCard(lesson)),
        const SizedBox(height: 8),
      ],
    );
  }
  
  Widget _buildMobileLessonCard(Map<String, dynamic> lesson) {
    final isEvent = lesson['isEvent'] == true;
    final studentName = lesson['studentName'] as String? ?? '';
    final eventTitle = lesson['title'] as String? ?? '';
    final displayName = isEvent ? eventTitle : studentName;
    final teachers = lesson['teachers'] as List<dynamic>? ?? [];
    final room = lesson['room'] as String? ?? '';
    final course = lesson['course'] as String? ?? '通常';
    final courseColor = _courseColors[course] ?? Colors.blue;
    
    return GestureDetector(
      onTap: () => _showMobileLessonDetail(lesson),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // コース色のバー
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: courseColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 生徒名/イベント名
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isEvent ? Colors.deepOrange : (course == '感覚統合' ? Colors.teal : AppColors.textMain),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 講師・部屋
                  Row(
                    children: [
                      if (teachers.isNotEmpty) ...[
                        Icon(Icons.person, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          teachers.map((t) => t.toString().split(' ').first).join(', '),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (room.isNotEmpty) ...[
                        Icon(Icons.room, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          room,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 矢印
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
  
  void _showMobileLessonDetail(Map<String, dynamic> lesson) {
    final isEvent = lesson['isEvent'] == true;
    final studentName = lesson['studentName'] as String? ?? '';
    final eventTitle = lesson['title'] as String? ?? '';
    final displayName = isEvent ? eventTitle : studentName;
    final teachers = lesson['teachers'] as List<dynamic>? ?? [];
    final room = lesson['room'] as String? ?? '';
    final course = lesson['course'] as String? ?? '通常';
    final courseColor = _courseColors[course] ?? Colors.blue;
    final note = lesson['note'] as String? ?? '';
    
    // 生徒の場合はメモを取得
    Map<String, dynamic>? studentNote;
    if (!isEvent && studentName.isNotEmpty) {
      studentNote = _studentNotes[studentName];
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ハンドル
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ヘッダー
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 40,
                      decoration: BoxDecoration(
                        color: courseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!isEvent)
                            Text(
                              course,
                              style: TextStyle(
                                fontSize: 14,
                                color: courseColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 内容
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 講師
                      if (teachers.isNotEmpty) ...[
                        _buildMobileDetailRow(Icons.person, '講師', teachers.join(', ')),
                        const SizedBox(height: 12),
                      ],
                      // 部屋
                      if (room.isNotEmpty) ...[
                        _buildMobileDetailRow(Icons.room, '部屋', room),
                        const SizedBox(height: 12),
                      ],
                      // メモ
                      if (note.isNotEmpty) ...[
                        _buildMobileDetailRow(Icons.note, 'メモ', note),
                        const SizedBox(height: 12),
                      ],
                      // 生徒情報
                      if (!isEvent && studentNote != null) ...[
                        const Divider(),
                        const SizedBox(height: 12),
                        const Text(
                          '生徒情報',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if ((studentNote['therapyPlan'] ?? '').toString().isNotEmpty)
                          _buildMobileDetailRow(Icons.psychology, '療育プラン', studentNote['therapyPlan']),
                        if ((studentNote['schoolVisit'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildMobileDetailRow(Icons.school, '園訪問', studentNote['schoolVisit']),
                        ],
                        if ((studentNote['schoolConsultation'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildMobileDetailRow(Icons.psychology_alt, '就学相談', studentNote['schoolConsultation']),
                        ],
                        if ((studentNote['moveRequest'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildMobileDetailRow(Icons.swap_horiz, '移動希望', studentNote['moveRequest']),
                        ],
                      ],
                      const SizedBox(height: 24),
                      // 編集はPCで
                      Center(
                        child: Text(
                          '編集はPC版で行ってください',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildMobileDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // ========================================
  // Web/タブレット用サイドメニュー
  // ========================================
  
  // サイドメニュー
  Widget _buildSideMenu() {
    // ダッシュボードモードの場合はサイドメニュー不要（Web版ではNavigationRailがある）
    if (_viewMode == 1) {
      return const SizedBox.shrink();
    }
    
    // スケジュールモードの場合は完全なメニュー
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          // 月カレンダー
          _buildSideMenuCalendar(),
          const Divider(height: 1),
          // フィルターリスト
          Expanded(
            child: _buildSideMenuFilters(),
          ),
          const Divider(height: 1),
          // 下部メニュー
          _buildSideMenuBottom(),
        ],
      ),
    );
  }
  
  // サイドメニュー：月カレンダー
  Widget _buildSideMenuCalendar() {
    final year = _sideMenuMonth.year;
    final month = _sideMenuMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // 日曜=0
    final daysInMonth = lastDay.day;
    final today = DateTime.now();
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 年月とナビゲーション
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$year年 $month月',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: () {
                      setState(() {
                        _sideMenuMonth = DateTime(year, month - 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: () {
                      setState(() {
                        _sideMenuMonth = DateTime(year, month + 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 曜日ヘッダー
          Row(
            children: ['日', '月', '火', '水', '木', '金', '土'].map((day) {
              final isSunday = day == '日';
              final isSaturday = day == '土';
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSunday ? Colors.red : (isSaturday ? Colors.blue : Colors.grey),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          // 日付グリッド
          ...List.generate(6, (weekIndex) {
            return Row(
              children: List.generate(7, (dayIndex) {
                final dayNumber = weekIndex * 7 + dayIndex - startWeekday + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 32));
                }
                final date = DateTime(year, month, dayNumber);
                final isToday = date.year == today.year && 
                               date.month == today.month && 
                               date.day == today.day;
                final isSelected = date.year == _weekStart.year &&
                                  date.month == _weekStart.month &&
                                  date.day >= _weekStart.day &&
                                  date.day <= _weekStart.day + 5;
                final isSunday = dayIndex == 0;
                final isSaturday = dayIndex == 6;
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _weekStart = _getMonday(date);
                      });
                      _loadShiftData();
                      _loadLessonsForWeek();
                    },
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
                        shape: isToday ? BoxShape.circle : BoxShape.rectangle,
                        border: isToday ? Border.all(color: AppColors.primary, width: 2) : null,
                      ),
                      child: Center(
                        child: Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 13,
                            color: isToday ? AppColors.primary : (isSunday ? Colors.red : (isSaturday ? Colors.blue : Colors.black87)),
                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }
  
  // サイドメニュー：フィルターリスト
  Widget _buildSideMenuFilters() {
    // プラス担当のスタッフを取得
    final plusStaff = _staffList.where((s) => s['isPlus'] == true).toList();
    
    // スタッフごとの色を設定
    final staffColors = [
      Colors.blue,
      Colors.teal,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
      Colors.green,
      Colors.red,
      Colors.cyan,
      Colors.amber,
    ];
    
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 全て
        _buildFilterItem('all', '全て', AppColors.primary, isSpecial: true),
        const Divider(height: 16),
        // スタッフリスト
        ...plusStaff.asMap().entries.map((entry) {
          final index = entry.key;
          final staff = entry.value;
          final name = staff['name'] as String? ?? '';
          final color = staffColors[index % staffColors.length];
          return _buildFilterItem(name, name, color);
        }),
      ],
    );
  }
  
  Widget _buildFilterItem(String key, String label, Color color, {bool isSpecial = false}) {
    final isSelected = _selectedFilters.contains(key) || 
                      (_selectedFilters.contains('all') && key != 'all');
    
    return InkWell(
      onTap: () {
        setState(() {
          if (key == 'all') {
            // 「全て」を選択したら全フィルターを選択状態に
            _selectedFilters = {'all'};
          } else {
            // 個別フィルターを選択/解除
            _selectedFilters.remove('all');
            if (_selectedFilters.contains(key)) {
              _selectedFilters.remove(key);
            } else {
              _selectedFilters.add(key);
            }
            // 全て選択されたら「全て」に戻す
            final plusStaff = _staffList.where((s) => s['isPlus'] == true).toList();
            final allStaffNames = plusStaff.map((s) => s['name'] as String).toSet();
            if (_selectedFilters.containsAll(allStaffNames)) {
              _selectedFilters = {'all'};
            }
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.transparent,
                border: Border.all(color: isSelected ? color : Colors.grey.shade400, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSpecial ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // サイドメニュー：下部メニュー
  Widget _buildSideMenuBottom() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (_viewMode == 0)
            ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.textSub),
              title: const Text('スケジュール管理'),
              onTap: () {
                _showShiftManagementDialog();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Row(
        children: [
          // ハンバーガーメニュー（モードによって動作が異なる）
          if (_viewMode == 0)
            // スケジュールモード：サイドメニューを開く
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.textMain),
              tooltip: 'メニュー',
              onPressed: () => setState(() => _isSideMenuOpen = !_isSideMenuOpen),
            ),
          // カレンダーモードの時だけ表示
          if (_viewMode == 0) ...[
            const Icon(Icons.calendar_today, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'スケジュール',
              style: TextStyle(
                color: AppColors.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: _goToThisWeek,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  foregroundColor: AppColors.textMain,
                ),
                child: const Text('今週'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppColors.textSub),
              onPressed: _previousWeek,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppColors.textSub),
              onPressed: _nextWeek,
            ),
            const SizedBox(width: 8),
            Text(
              _formatWeekRange(),
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            // ダッシュボードモードの時
            const Icon(Icons.dashboard_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'ダッシュボード',
              style: TextStyle(
                color: AppColors.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          // タブ切り替え
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildViewModeTab(0, Icons.calendar_today, 'カレンダー'),
                _buildViewModeTab(1, Icons.dashboard_outlined, 'ダッシュボード'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeTab(int mode, IconData icon, String label) {
    final isSelected = _viewMode == mode;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: () {
          if (_viewMode != mode) {
            _hideCurrentOverlay();
            setState(() {
              _viewMode = mode;
              // ダッシュボードモードに切り替え時はサイドメニューを閉じる
              if (mode == 1) {
                _isSideMenuOpen = false;
              }
            });
            // カレンダーモードに切り替えた時はタスクを再読み込み
            if (mode == 0) {
              _loadAllTasks();
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? AppColors.primary : AppColors.textSub,
          ),
        ),
      ),
    );
  }

  String _formatWeekRange() {
    final weekEnd = _weekStart.add(const Duration(days: 5));
    final year = DateFormat('yyyy年', 'ja').format(_weekStart);
    final startMonth = DateFormat('M月', 'ja').format(_weekStart);
    final startDay = DateFormat('d日', 'ja').format(_weekStart);
    final endDay = DateFormat('d日', 'ja').format(weekEnd);

    if (_weekStart.month == weekEnd.month) {
      return '$year$startMonth$startDay 〜 $endDay';
    } else {
      return '$year$startMonth$startDay 〜 ${DateFormat('M月d日', 'ja').format(weekEnd)}';
    }
  }

  Widget _buildScheduleTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const timeColumnWidth = 60.0;
        final cellWidth = (constraints.maxWidth - timeColumnWidth) / 6;
        const headerHeight = 95.0;
        final cellHeight = (constraints.maxHeight - headerHeight) / 4;

        return Column(
          children: [
            _buildDayHeader(cellWidth, timeColumnWidth, headerHeight),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeColumn(timeColumnWidth, cellHeight),
                  ...List.generate(6, (dayIndex) => _buildDayColumn(dayIndex, cellWidth, cellHeight)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayHeader(double cellWidth, double timeColumnWidth, double headerHeight) {
    final days = ['月', '火', '水', '木', '金', '土'];
    final today = DateTime.now();

    return Container(
      height: headerHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
      ),
      child: Row(
        children: [
          SizedBox(width: timeColumnWidth),
          ...List.generate(6, (index) {
            final date = _weekStart.add(Duration(days: index));
            final isToday = date.year == today.year && 
                           date.month == today.month && 
                           date.day == today.day;
            final isSaturday = index == 5;
            
            // その日のタスク件数を取得
            final dateKey = DateFormat('yyyy-MM-dd').format(date);
            final tasksForDay = _tasksByDueDate[dateKey] ?? [];
            final taskCount = tasksForDay.length;

            return SizedBox(
              width: cellWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    days[index],
                    style: TextStyle(
                      color: isSaturday ? Colors.blue : AppColors.textSub,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _showShiftDialog(date),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isToday ? AppColors.primary : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            color: isToday ? Colors.white : (isSaturday ? Colors.blue : AppColors.textMain),
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // タスク件数表示
                  SizedBox(
                    height: 22,
                    child: taskCount > 0
                        ? GestureDetector(
                            onTap: () => _showTasksForDateDialog(date, tasksForDay),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isToday ? AppColors.primary : Colors.grey.shade400,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$taskCount件のタスク',
                                style: TextStyle(
                                  color: isToday ? AppColors.primary : Colors.grey.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
  
  // その日のタスク一覧ダイアログ
  void _showTasksForDateDialog(DateTime date, List<Map<String, dynamic>> tasks) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.task_alt, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('M月d日 (E)', 'ja').format(date)} のタスク',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: tasks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('タスクはありません', style: TextStyle(color: Colors.grey)),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: tasks.map((task) {
                        final studentName = task['studentName'] as String?;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (studentName != null && studentName.isNotEmpty)
                                      Text(
                                        studentName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    Text(
                                      task['title'] ?? '',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: studentName != null ? AppColors.textSub : AppColors.textMain,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 完了ボタン
                              IconButton(
                                onPressed: () async {
                                  await _completeTask(task['id']);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(content: Text('タスクを完了しました')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                color: Colors.green,
                                tooltip: '完了',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimeColumn(double width, double cellHeight) {
    return SizedBox(
      width: width,
      child: Column(
        children: List.generate(_timeSlots.length, (index) {
          return Container(
            height: cellHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                top: index == 0 ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Text(
              _timeSlots[index],
              style: const TextStyle(
                color: AppColors.textSub,
                fontSize: 11,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayColumn(int dayIndex, double cellWidth, double cellHeight) {
    return SizedBox(
      width: cellWidth,
      child: Column(
        children: List.generate(_timeSlots.length, (slotIndex) {
          return _buildCell(dayIndex, slotIndex, cellWidth, cellHeight);
        }),
      ),
    );
  }

  Widget _buildCell(int dayIndex, int slotIndex, double cellWidth, double cellHeight) {
    final date = _weekStart.add(Duration(days: dayIndex));
    final isHoliday = _isHoliday(date);
    
    // レッスンを取得してフィルタリング
    var lessons = _lessons.where((lesson) =>
        lesson['dayIndex'] == dayIndex && lesson['slotIndex'] == slotIndex).toList();
    
    // フィルタリング適用
    if (!_selectedFilters.contains('all')) {
      // フィルターが空の場合は何も表示しない
      if (_selectedFilters.isEmpty) {
        lessons = [];
      } else {
        lessons = lessons.where((lesson) {
          final teachers = lesson['teachers'] as List<dynamic>? ?? [];
          
          // 講師に「全員」が含まれている場合は常に表示
          if (teachers.contains('全員')) {
            return true;
          }
          
          // 講師でフィルタリング
          for (final teacher in teachers) {
            if (_selectedFilters.contains(teacher)) {
              return true;
            }
          }
          return false;
        }).toList();
      }
    }

    // セル全体のDragTarget（別セルからの移動用）
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        // 休みの日には移動不可
        if (isHoliday) return false;
        // 同じセルには移動不可（セル内の並び替えは別で処理）
        final lesson = details.data;
        if (lesson['dayIndex'] == dayIndex && lesson['slotIndex'] == slotIndex) {
          return false;
        }
        return true;
      },
      onAcceptWithDetails: (details) async {
        final lesson = details.data;
        await _moveLessonToCell(lesson, dayIndex, slotIndex);
      },
      builder: (context, candidateData, rejectedData) {
        return GestureDetector(
          onTap: () {
            // セル全体（空白部分）をタップしたらレッスン追加
            if (!isHoliday) {
              _showAddLessonDialog(dayIndex: dayIndex, slotIndex: slotIndex);
            }
          },
          child: Container(
            width: cellWidth,
            height: cellHeight,
            decoration: BoxDecoration(
              color: isHoliday ? Colors.grey.shade200 : Colors.white,
              border: Border(
                top: slotIndex == 0 ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
                bottom: BorderSide(color: Colors.grey.shade300),
                left: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            padding: const EdgeInsets.all(6),
            child: isHoliday && lessons.isEmpty
                ? null
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildLessonListWithDropIndicators(lessons, dayIndex, slotIndex),
                    ),
                  ),
          ),
        );
      },
    );
  }

  // レッスンリストを行間ドロップインジケーター付きで構築
  List<Widget> _buildLessonListWithDropIndicators(List<Map<String, dynamic>> lessons, int dayIndex, int slotIndex) {
    // ドラッグ中でない場合は通常のリストを返す
    final isDraggingInSameCell = _draggingLesson != null &&
        _draggingLesson!['dayIndex'] == dayIndex &&
        _draggingLesson!['slotIndex'] == slotIndex;
    
    if (!isDraggingInSameCell) {
      return lessons.map((lesson) => _buildLessonItem(lesson)).toList();
    }
    
    // ドラッグ中のレッスンの現在位置
    final currentIndex = lessons.indexWhere((l) => l['id'] == _draggingLesson!['id']);
    
    final List<Widget> widgets = [];
    for (int i = 0; i <= lessons.length; i++) {
      // 自分の位置と直後の位置以外にドロップインジケーターを配置
      if (i != currentIndex && i != currentIndex + 1) {
        widgets.add(_buildDropIndicator(dayIndex, slotIndex, i, lessons));
      }
      
      // レッスンアイテム
      if (i < lessons.length) {
        widgets.add(_buildLessonItem(lessons[i]));
      }
    }
    
    return widgets;
  }

  // 行間ドロップインジケーター
  Widget _buildDropIndicator(int dayIndex, int slotIndex, int insertIndex, List<Map<String, dynamic>> lessons) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        final draggedLesson = details.data;
        return draggedLesson['dayIndex'] == dayIndex && draggedLesson['slotIndex'] == slotIndex;
      },
      onAcceptWithDetails: (details) {
        _reorderLessonToIndex(details.data, dayIndex, slotIndex, insertIndex, lessons);
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return Container(
          height: isActive ? 2 : 0,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
          ),
        );
      },
    );
  }

  // レッスンを別のセルに移動
  Future<void> _moveLessonToCell(Map<String, dynamic> lesson, int newDayIndex, int newSlotIndex) async {
    final lessonId = lesson['id'] as String?;
    if (lessonId == null) return;
    
    try {
      final newDate = _weekStart.add(Duration(days: newDayIndex));
      final saveDate = DateTime(newDate.year, newDate.month, newDate.day, 12, 0, 0);
      
      // 移動先セルの最大orderを取得して、その後ろに追加
      final targetCellLessons = _lessons.where((l) => 
          l['dayIndex'] == newDayIndex && l['slotIndex'] == newSlotIndex).toList();
      int newOrder = DateTime.now().millisecondsSinceEpoch;
      if (targetCellLessons.isNotEmpty) {
        final maxOrder = targetCellLessons.map((l) => l['order'] as int).reduce((a, b) => a > b ? a : b);
        newOrder = maxOrder + 1;
      }
      
      // まずローカルの状態を更新（画面が真っ白にならないように）
      setState(() {
        final index = _lessons.indexWhere((l) => l['id'] == lessonId);
        if (index != -1) {
          _lessons[index]['dayIndex'] = newDayIndex;
          _lessons[index]['slotIndex'] = newSlotIndex;
          _lessons[index]['date'] = saveDate;
          _lessons[index]['order'] = newOrder;
          // 再ソート
          _lessons.sort((a, b) {
            final dayCompare = (a['dayIndex'] as int).compareTo(b['dayIndex'] as int);
            if (dayCompare != 0) return dayCompare;
            final slotCompare = (a['slotIndex'] as int).compareTo(b['slotIndex'] as int);
            if (slotCompare != 0) return slotCompare;
            return (a['order'] as int).compareTo(b['order'] as int);
          });
        }
      });
      
      // Firestoreを更新
      await FirebaseFirestore.instance
          .collection('plus_lessons')
          .doc(lessonId)
          .update({
        'date': Timestamp.fromDate(saveDate),
        'slotIndex': newSlotIndex,
        'order': newOrder,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error moving lesson: $e');
      // エラー時はデータを再読み込み
      await _loadLessonsForWeek();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移動に失敗しました: $e')),
        );
      }
    }
  }

  Widget _buildLessonItem(Map<String, dynamic> lesson) {
    final course = lesson['course'] as String? ?? '通常';
    final color = _courseColors[course] ?? Colors.blue;
    final teachers = lesson['teachers'] as List<dynamic>? ?? [];
    final note = lesson['note'] as String? ?? '';
    final hasNote = note.isNotEmpty;
    
    // 文字色（通常の場合は黒）
    final textColor = course == '通常' ? Colors.black87 : color;
    
    // 頭文字を取得（通常の場合は空文字）
    final courseInitial = course != '通常' && course.isNotEmpty 
        ? '(${course.substring(0, 1)})' 
        : '';
    
    // 講師名を苗字のみに変換（空要素を除外）
    final teacherLastNames = teachers
        .where((name) => name != null && name.toString().isNotEmpty)
        .map((name) {
          final parts = name.toString().split(' ');
          return parts.first;
        })
        .where((name) => name.isNotEmpty)
        .toList();

    Widget lessonContent = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        lesson['studentName'],
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (courseInitial.isNotEmpty)
                      Text(
                        courseInitial,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 複数講師対応（苗字のみ表示）
              Text(
                teacherLastNames.join('・'),
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                lesson['room'],
                style: const TextStyle(
                  color: AppColors.textSub,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        // 右上の三角マーク（メモまたは生徒情報あり）- セル右端に引っ付ける
        if (hasNote || _hasStudentInfo(lesson['studentName'] ?? ''))
          Positioned(
            top: 0,
            right: -6, // paddingの分を打ち消して罫線に引っ付ける
            child: CustomPaint(
              size: const Size(8, 8),
              painter: _NoteTrianglePainter(color: Colors.black87),
            ),
          ),
      ],
    );

    // ドラッグ中の見た目
    Widget dragFeedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primary, width: 2),
        ),
        child: Text(
          lesson['studentName'],
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Draggable<Map<String, dynamic>>(
        data: lesson,
        feedback: dragFeedback,
        onDragStarted: () {
          setState(() {
            _draggingLesson = lesson;
          });
        },
        onDragEnd: (_) {
          setState(() {
            _draggingLesson = null;
          });
        },
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: lessonContent,
        ),
        child: Material(
          color: Colors.transparent,
          child: _buildLessonWithHover(lesson, lessonContent, note),
        ),
      ),
    );
  }
  
  // ホバー時のリッチなポップアップを表示
  Widget _buildLessonWithHover(Map<String, dynamic> lesson, Widget lessonContent, String note) {
    final studentName = lesson['studentName'] as String? ?? '';
    final notes = _studentNotes[studentName];
    final tasks = _getTasksForStudent(studentName);
    final dayIndex = lesson['dayIndex'] as int? ?? 0;
    
    // ポップアップに表示する情報を構築
    final therapyPlan = notes?['therapyPlan'] as String? ?? '';
    final schoolVisit = notes?['schoolVisit'] as String? ?? '';
    final schoolConsultation = notes?['schoolConsultation'] as String? ?? '';
    final moveRequest = notes?['moveRequest'] as String? ?? '';
    
    // 何か情報があるかチェック
    final hasInfo = note.isNotEmpty || 
        therapyPlan.isNotEmpty || 
        schoolVisit.isNotEmpty || 
        schoolConsultation.isNotEmpty || 
        moveRequest.isNotEmpty ||
        tasks.isNotEmpty;
    
    if (!hasInfo) {
      return InkWell(
        onTap: () => _showEditLessonDialog(lesson),
        hoverColor: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        child: lessonContent,
      );
    }
    
    // 金曜日（dayIndex == 4）または土曜日（dayIndex == 5）は左に表示
    final showOnLeft = dayIndex >= 4;
    
    // ホバー情報を構築（カスタムオーバーレイ）
    final key = GlobalKey();
    const popupWidth = 180.0;
    
    void showOverlay() {
      // 既存のオーバーレイを先に削除
      _hideCurrentOverlay();
      
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final overlay = Overlay.of(context);
      final offset = renderBox.localToGlobal(Offset.zero);
      
      // ポップアップ内容
      final popupContent = Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: Container(
          width: popupWidth,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildHoverContent(note, therapyPlan, schoolVisit, schoolConsultation, moveRequest, tasks),
          ),
        ),
      );
      
      _currentOverlay = OverlayEntry(
        builder: (ctx) {
          double left;
          
          if (showOnLeft) {
            // 左に表示: カードの左端からポップアップ幅分左にずらす
            left = offset.dx - popupWidth - 4;
          } else {
            // 右に表示: カードの右端 + マージン
            left = offset.dx + renderBox.size.width + 4;
          }
          
          return Positioned(
            top: offset.dy,
            left: left,
            child: popupContent,
          );
        },
      );
      
      overlay.insert(_currentOverlay!);
    }
    
    return MouseRegion(
      key: key,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => showOverlay(),
      onExit: (_) => _hideCurrentOverlay(),
      child: GestureDetector(
        onTap: () {
          _hideCurrentOverlay();
          _showEditLessonDialog(lesson);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: lessonContent,
        ),
      ),
    );
  }
  
  // ホバーポップアップの内容を構築
  List<Widget> _buildHoverContent(
    String note, 
    String therapyPlan, 
    String schoolVisit, 
    String schoolConsultation, 
    String moveRequest,
    List<Map<String, dynamic>> tasks
  ) {
    final widgets = <Widget>[];
    
    // 療育プラン
    if (therapyPlan.isNotEmpty) {
      widgets.add(const Text(
        '【療育プラン】',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ));
      widgets.add(Text(therapyPlan, style: const TextStyle(fontSize: 12)));
      widgets.add(const SizedBox(height: 8));
    }
    
    // 園訪問
    if (schoolVisit.isNotEmpty) {
      widgets.add(const Text(
        '【園訪問】',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ));
      widgets.add(Text(schoolVisit, style: const TextStyle(fontSize: 12)));
      widgets.add(const SizedBox(height: 8));
    }
    
    // 就学相談
    if (schoolConsultation.isNotEmpty) {
      widgets.add(const Text(
        '【就学相談】',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ));
      widgets.add(Text(schoolConsultation, style: const TextStyle(fontSize: 12)));
      widgets.add(const SizedBox(height: 8));
    }
    
    // 移動希望
    if (moveRequest.isNotEmpty) {
      widgets.add(const Text(
        '【移動希望】',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ));
      widgets.add(Text(moveRequest, style: const TextStyle(fontSize: 12)));
      widgets.add(const SizedBox(height: 8));
    }
    
    // タスク
    if (tasks.isNotEmpty) {
      widgets.add(const Text(
        '【タスク】',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ));
      for (var task in tasks) {
        final dueDate = task['dueDate'] as Timestamp?;
        final dueDateStr = dueDate != null 
            ? '(${DateFormat('M/d').format(dueDate.toDate())})' 
            : '';
        widgets.add(Text(
          '• ${task['title']} $dueDateStr',
          style: const TextStyle(fontSize: 12),
        ));
      }
      widgets.add(const SizedBox(height: 8));
    }
    
    // メモ
    if (note.isNotEmpty) {
      widgets.add(const Text(
        '【メモ】',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ));
      widgets.add(Text(note, style: const TextStyle(fontSize: 12)));
    }
    
    // 最後の余白を削除
    if (widgets.isNotEmpty && widgets.last is SizedBox) {
      widgets.removeLast();
    }
    
    return widgets;
  }

  // レッスンを指定インデックスに移動（並び替え）
  Future<void> _reorderLessonToIndex(
    Map<String, dynamic> draggedLesson, 
    int dayIndex, 
    int slotIndex, 
    int insertIndex,
    List<Map<String, dynamic>> cellLessons,
  ) async {
    final draggedId = draggedLesson['id'] as String?;
    if (draggedId == null) return;

    // 新しいorder値を計算
    int newOrder;
    if (cellLessons.isEmpty) {
      newOrder = DateTime.now().millisecondsSinceEpoch;
    } else if (insertIndex == 0) {
      // 先頭に挿入
      newOrder = (cellLessons.first['order'] as int) - 1000;
    } else if (insertIndex >= cellLessons.length) {
      // 末尾に挿入
      newOrder = (cellLessons.last['order'] as int) + 1000;
    } else {
      // 中間に挿入（前後の平均）
      final prevOrder = cellLessons[insertIndex - 1]['order'] as int;
      final nextOrder = cellLessons[insertIndex]['order'] as int;
      newOrder = ((prevOrder + nextOrder) / 2).round();
    }
    
    // ローカルの状態を更新
    setState(() {
      final lessonIndex = _lessons.indexWhere((l) => l['id'] == draggedId);
      if (lessonIndex != -1) {
        _lessons[lessonIndex]['dayIndex'] = dayIndex;
        _lessons[lessonIndex]['slotIndex'] = slotIndex;
        _lessons[lessonIndex]['order'] = newOrder;
        
        // 再ソート
        _lessons.sort((a, b) {
          final dayCompare = (a['dayIndex'] as int).compareTo(b['dayIndex'] as int);
          if (dayCompare != 0) return dayCompare;
          final slotCompare = (a['slotIndex'] as int).compareTo(b['slotIndex'] as int);
          if (slotCompare != 0) return slotCompare;
          return (a['order'] as int).compareTo(b['order'] as int);
        });
      }
    });
    
    // Firestoreを更新
    try {
      final newDate = _weekStart.add(Duration(days: dayIndex));
      final saveDate = DateTime(newDate.year, newDate.month, newDate.day, 12, 0, 0);
      
      await FirebaseFirestore.instance
          .collection('plus_lessons')
          .doc(draggedId)
          .update({
        'date': Timestamp.fromDate(saveDate),
        'slotIndex': slotIndex,
        'order': newOrder,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error reordering lesson: $e');
      await _loadLessonsForWeek();
    }
  }

  void _showShiftDialog(DateTime date) {
    final shifts = _getShiftsForDate(date);
    final isHoliday = _isHoliday(date);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              DateFormat('M月d日 (E)', 'ja').format(date),
              style: const TextStyle(fontSize: 18),
            ),
            if (isHoliday) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '休み',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit, size: 20, color: AppColors.textSub),
              onPressed: () {
                Navigator.pop(dialogContext);
                _showEditShiftDialog(date);
              },
              tooltip: '編集',
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'シフト',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSub,
                ),
              ),
              const SizedBox(height: 12),
              if (shifts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'シフトが登録されていません',
                    style: TextStyle(color: AppColors.textSub),
                  ),
                )
              else
                ...shifts.map((shift) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          shift['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${shift['start'] ?? ''} - ${shift['end'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textSub,
                        ),
                      ),
                      if (shift['note'] != null && shift['note'].toString().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            shift['note'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditShiftDialog(DateTime date) {
    final dayKey = date.day.toString();
    final monthKey = DateFormat('yyyy-MM').format(date);
    final isMonday = date.weekday == DateTime.monday;
    
    // 現在のシフトをコピー
    List<Map<String, dynamic>> editingShifts = List.from(
      _shiftData[dayKey]?.map((e) => Map<String, dynamic>.from(e)) ?? []
    );
    
    // 休み状態
    bool isHolidayLocal = _holidays.contains(dayKey);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.edit, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat('M月d日 (E)', 'ja').format(date)} のシフト',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 休み設定
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isMonday || isHolidayLocal) ? Colors.grey.shade100 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (isMonday || isHolidayLocal) ? Icons.event_busy : Icons.event_available,
                            size: 20,
                            color: (isMonday || isHolidayLocal) ? Colors.grey : AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '休み設定',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                                if (isMonday)
                                  Text(
                                    '月曜日は定休日です',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                          Switch(
                            value: isMonday ? true : isHolidayLocal,
                            onChanged: isMonday
                                ? null  // 月曜日は変更不可
                                : (value) {
                                    setDialogState(() {
                                      isHolidayLocal = value;
                                    });
                                  },
                            activeTrackColor: Colors.grey.shade400,
                            thumbColor: WidgetStateProperty.all(Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // シフト一覧
                    ...editingShifts.asMap().entries.map((entry) {
                      final index = entry.key;
                      final shift = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            // 1行目: スタッフ選択と削除ボタン
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: shift['staffId'],
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    items: _staffList.map((staff) {
                                      return DropdownMenuItem(
                                        value: staff['id'] as String,
                                        child: Text(staff['name'] as String, style: const TextStyle(fontSize: 14)),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      final staff = _staffList.firstWhere((s) => s['id'] == value);
                                      setDialogState(() {
                                        editingShifts[index]['staffId'] = value;
                                        editingShifts[index]['name'] = staff['name'];
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 22),
                                  onPressed: () {
                                    setDialogState(() {
                                    editingShifts.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // 2行目: 時間
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: shift['start'] ?? '9:00',
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    hintText: '開始',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  onChanged: (value) {
                                    editingShifts[index]['start'] = value;
                                  },
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('-', style: TextStyle(fontSize: 16)),
                              ),
                              Expanded(
                                child: TextFormField(
                                  initialValue: shift['end'] ?? '18:00',
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    hintText: '終了',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  onChanged: (value) {
                                    editingShifts[index]['end'] = value;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // 3行目: 備考
                          TextFormField(
                            initialValue: shift['note'] ?? '',
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              hintText: '備考',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (value) {
                              editingShifts[index]['note'] = value;
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  // 追加ボタン
                  TextButton.icon(
                    onPressed: () {
                      setDialogState(() {
                        editingShifts.add({
                          'staffId': _staffList.isNotEmpty ? _staffList.first['id'] : '',
                          'name': _staffList.isNotEmpty ? _staffList.first['name'] : '',
                          'start': '9:00',
                          'end': '18:00',
                          'note': '',
                        });
                      });
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('スタッフを追加'),
                  ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _saveShiftsAndHoliday(monthKey, dayKey, editingShifts, isHolidayLocal);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveShiftsAndHoliday(String monthKey, String dayKey, List<Map<String, dynamic>> shifts, bool isHoliday) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(monthKey);
      
      // 既存データを取得
      final doc = await docRef.get();
      Map<String, dynamic> allDays = {};
      List<String> holidays = [];
      
      if (doc.exists) {
        allDays = Map<String, dynamic>.from(doc.data()?['days'] ?? {});
        holidays = List<String>.from(doc.data()?['holidays'] ?? []);
      }
      
      // この日のシフトを更新
      allDays[dayKey] = shifts;
      
      // 休み設定を更新
      if (isHoliday) {
        if (!holidays.contains(dayKey)) {
          holidays.add(dayKey);
        }
      } else {
        holidays.remove(dayKey);
      }
      
      // 保存
      await docRef.set({
        'classroom': 'ビースマイリープラス湘南藤沢',
        'days': allDays,
        'holidays': holidays,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // ローカルデータを更新
      setState(() {
        _shiftData[dayKey] = shifts;
        _holidays = holidays.toSet();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シフトを保存しました')),
        );
      }
    } catch (e) {
      debugPrint('Error saving shifts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存に失敗しました')),
        );
      }
    }
  }

  void _showShiftManagementDialog() {
    final currentMonth = DateFormat('yyyy-MM').format(_weekStart);
    final previousMonth = DateFormat('yyyy-MM').format(
      DateTime(_weekStart.year, _weekStart.month - 1, 1)
    );
    final weekLabel = '${DateFormat('M/d', 'ja').format(_weekStart)}〜${DateFormat('M/d', 'ja').format(_weekStart.add(const Duration(days: 5)))}';
    final previousWeekStart = _weekStart.subtract(const Duration(days: 7));
    final previousWeekLabel = '${DateFormat('M/d', 'ja').format(previousWeekStart)}〜${DateFormat('M/d', 'ja').format(previousWeekStart.add(const Duration(days: 5)))}';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.settings, color: AppColors.primary),
                SizedBox(width: 8),
                Text('スケジュール管理', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 週単位コピー
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.date_range, size: 18, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text(
                              '週単位コピー',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '現在の週: $weekLabel',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _copyFromPreviousWeek();
                            },
                            icon: const Icon(Icons.content_copy, size: 18),
                            label: Text('$previousWeekLabelのスケジュールをコピー'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '※先週のシフトとレッスンを今週にコピーします',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 月単位コピー
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.calendar_month, size: 18, color: AppColors.textSub),
                            SizedBox(width: 8),
                            Text(
                              '月単位コピー',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '現在の月: ${DateFormat('yyyy年M月', 'ja').format(_weekStart)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _copyFromPreviousMonth(previousMonth, currentMonth);
                            },
                            icon: const Icon(Icons.content_copy, size: 18),
                            label: Text('${DateFormat('M月', 'ja').format(DateTime(_weekStart.year, _weekStart.month - 1, 1))}のシフトをコピー'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '※前月のシフトデータを今月にコピーします',
                          style: TextStyle(fontSize: 11, color: AppColors.textSub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 先週のスケジュールを今週にコピー
  Future<void> _copyFromPreviousWeek() async {
    final previousWeekStart = _weekStart.subtract(const Duration(days: 7));
    final previousMonthKey = DateFormat('yyyy-MM').format(previousWeekStart);
    final currentMonthKey = DateFormat('yyyy-MM').format(_weekStart);
    
    try {
      // 1. 先週のシフトを取得
      final previousShiftDoc = await FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(previousMonthKey)
          .get();
      
      final previousShiftData = previousShiftDoc.exists 
          ? Map<String, dynamic>.from(previousShiftDoc.data()?['days'] ?? {})
          : <String, dynamic>{};
      
      // 2. 先週のレッスンを取得（dateフィールドで週をフィルタリング）
      final previousWeekStartDate = DateTime(previousWeekStart.year, previousWeekStart.month, previousWeekStart.day);
      final previousWeekEndDate = previousWeekStartDate.add(const Duration(days: 5, hours: 23, minutes: 59, seconds: 59));
      
      final previousLessonsSnapshot = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(previousWeekStartDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(previousWeekEndDate))
          .get();
      
      debugPrint('先週のレッスン数: ${previousLessonsSnapshot.docs.length}');
      
      // 3. 先週のシフトを今週にコピー
      final shiftUpdates = <String, List<Map<String, dynamic>>>{};
      for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
        final previousDate = previousWeekStart.add(Duration(days: dayIndex));
        final currentDate = _weekStart.add(Duration(days: dayIndex));
        final previousDayKey = previousDate.day.toString();
        final currentDayKey = currentDate.day.toString();
        
        if (previousShiftData.containsKey(previousDayKey)) {
          final shifts = previousShiftData[previousDayKey];
          if (shifts is List) {
            shiftUpdates[currentDayKey] = shifts.map((s) => Map<String, dynamic>.from(s)).toList();
          }
        }
      }
      
      // シフトをFirestoreに保存
      if (shiftUpdates.isNotEmpty) {
        final shiftDocRef = FirebaseFirestore.instance
            .collection('plus_shifts')
            .doc(currentMonthKey);
        
        final shiftDoc = await shiftDocRef.get();
        
        if (shiftDoc.exists) {
          final existingDays = Map<String, dynamic>.from(shiftDoc.data()?['days'] ?? {});
          shiftUpdates.forEach((key, value) {
            existingDays[key] = value;
          });
          
          await shiftDocRef.update({
            'days': existingDays,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await shiftDocRef.set({
            'classroom': 'ビースマイリープラス湘南藤沢',
            'days': shiftUpdates,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        // ローカルデータを更新
        setState(() {
          shiftUpdates.forEach((key, value) {
            _shiftData[key] = value;
          });
        });
      }
      
      // 4. 今週の既存レッスンを削除
      final currentWeekStartDate = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
      final currentWeekEndDate = currentWeekStartDate.add(const Duration(days: 5, hours: 23, minutes: 59, seconds: 59));
      
      final existingLessonsSnapshot = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(currentWeekStartDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(currentWeekEndDate))
          .get();
      
      // バッチで既存レッスンを削除
      final deleteBatch = FirebaseFirestore.instance.batch();
      for (final doc in existingLessonsSnapshot.docs) {
        deleteBatch.delete(doc.reference);
      }
      await deleteBatch.commit();
      
      // 5. 先週のレッスンを今週にコピー（日付を+7日）
      if (previousLessonsSnapshot.docs.isNotEmpty) {
        final addBatch = FirebaseFirestore.instance.batch();
        
        for (final doc in previousLessonsSnapshot.docs) {
          final data = doc.data();
          final previousDate = (data['date'] as Timestamp).toDate();
          final newDate = previousDate.add(const Duration(days: 7));
          
          final newRef = FirebaseFirestore.instance.collection('plus_lessons').doc();
          addBatch.set(newRef, {
            ...data,
            'date': Timestamp.fromDate(newDate),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        await addBatch.commit();
        debugPrint('今週にコピーしたレッスン数: ${previousLessonsSnapshot.docs.length}');
      }
      
      // レッスンデータを再読み込み
      await _loadLessonsForWeek();
      await _loadShiftData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先週のスケジュールをコピーしました')),
        );
      }
    } catch (e) {
      debugPrint('Error copying from previous week: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  // 現在の週のシフトとレッスンをコピー
  void _copyCurrentWeekShifts() {
    final copiedShifts = <int, List<Map<String, dynamic>>>{};
    
    for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
      final date = _weekStart.add(Duration(days: dayIndex));
      final dayKey = date.day.toString();
      final shifts = _shiftData[dayKey] ?? [];
      
      if (shifts.isNotEmpty) {
        copiedShifts[dayIndex] = shifts.map((s) => Map<String, dynamic>.from(s)).toList();
      }
    }
    
    // レッスンもコピー（docIdを除外）
    final copiedLessons = _lessons.map((lesson) {
      final copy = Map<String, dynamic>.from(lesson);
      copy.remove('docId'); // 新規作成時に新しいIDが付与されるように
      return copy;
    }).toList();
    
    setState(() {
      _copiedWeekShifts = copiedShifts;
      _copiedWeekLessons = copiedLessons;
      _copiedWeekLabel = '${DateFormat('M/d', 'ja').format(_weekStart)}〜${DateFormat('M/d', 'ja').format(_weekStart.add(const Duration(days: 5)))}';
    });
  }

  // コピーしたシフトとレッスンを現在の週に貼り付け
  Future<void> _pasteWeekShifts() async {
    if (_copiedWeekShifts == null && _copiedWeekLessons == null) return;
    
    try {
      final monthKey = DateFormat('yyyy-MM').format(_weekStart);
      final weekKey = DateFormat('yyyy-MM-dd').format(_weekStart);
      
      // シフトの貼り付け
      if (_copiedWeekShifts != null) {
        final updates = <String, List<Map<String, dynamic>>>{};
        
        for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
          final date = _weekStart.add(Duration(days: dayIndex));
          final dayKey = date.day.toString();
          
          if (_copiedWeekShifts!.containsKey(dayIndex)) {
            updates[dayKey] = _copiedWeekShifts![dayIndex]!;
          }
        }
        
        // Firestoreに保存
        final docRef = FirebaseFirestore.instance
            .collection('plus_shifts')
            .doc(monthKey);
        
        final doc = await docRef.get();
        
        if (doc.exists) {
          final existingDays = Map<String, dynamic>.from(doc.data()?['days'] ?? {});
          updates.forEach((key, value) {
            existingDays[key] = value;
          });
          
          await docRef.update({
            'days': existingDays,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await docRef.set({
            'classroom': 'ビースマイリープラス湘南藤沢',
            'days': updates,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        // ローカルデータを更新
        setState(() {
          updates.forEach((key, value) {
            _shiftData[key] = value;
          });
        });
      }
      
      // レッスンの貼り付け
      if (_copiedWeekLessons != null && _copiedWeekLessons!.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        final lessonsRef = FirebaseFirestore.instance
            .collection('plus_lessons')
            .doc(weekKey)
            .collection('items');
        
        // 既存のレッスンを削除
        final existingLessons = await lessonsRef.get();
        for (final doc in existingLessons.docs) {
          batch.delete(doc.reference);
        }
        
        // 新しいレッスンを追加
        for (final lesson in _copiedWeekLessons!) {
          final newRef = lessonsRef.doc();
          batch.set(newRef, {
            ...lesson,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        await batch.commit();
        
        // ローカルデータを更新
        await _loadLessonsForWeek();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('スケジュールを貼り付けました')),
        );
      }
    } catch (e) {
      debugPrint('Error pasting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  Future<void> _copyFromPreviousMonth(String fromMonth, String toMonth) async {
    try {
      // 前月のデータを取得
      final fromDoc = await FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(fromMonth)
          .get();
      
      if (!fromDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('前月のシフトデータがありません')),
          );
        }
        return;
      }
      
      final fromData = fromDoc.data()!;
      final fromDays = fromData['days'] as Map<String, dynamic>? ?? {};
      
      // 今月のドキュメントに保存
      await FirebaseFirestore.instance
          .collection('plus_shifts')
          .doc(toMonth)
          .set({
            'classroom': fromData['classroom'] ?? 'ビースマイリープラス湘南藤沢',
            'days': fromDays,
            'copiedFrom': fromMonth,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      // ローカルデータを更新
      setState(() {
        _shiftData = fromDays.map((key, value) {
          return MapEntry(key, List<Map<String, dynamic>>.from(
            (value as List).map((e) => Map<String, dynamic>.from(e))
          ));
        });
        _loadedShiftMonth = toMonth;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('前月のスケジュールをコピーしました')),
        );
      }
    } catch (e) {
      debugPrint('Error copying shifts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('シフトのコピーに失敗しました')),
        );
      }
    }
  }

  void _showAddLessonDialog({int? dayIndex, int? slotIndex}) {
    if (dayIndex == null || slotIndex == null) return;
    
    // 入力モード: 'student'=生徒選択, 'custom'=イベント
    String inputMode = 'student';
    Map<String, dynamic>? selectedStudent;
    final customTitleController = TextEditingController();
    List<String> selectedTeachers = [];
    String selectedRoom = '';
    String selectedCourse = '通常';
    
    // 生徒メモ用コントローラー
    final therapyController = TextEditingController();
    final schoolVisitController = TextEditingController();
    final consultationController = TextEditingController();
    final moveRequestController = TextEditingController();
    
    // タスク用
    List<Map<String, dynamic>> studentTasks = [];
    final newTaskController = TextEditingController();
    DateTime? newTaskDueDate;
    
    // 生徒選択時にデータをロード
    String? lastLoadedStudent;
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final currentColor = _courseColors[selectedCourse] ?? Colors.blue;
          final date = _weekStart.add(Duration(days: dayIndex));
          
          // 初回のみ期限日をイベント当日に設定
          newTaskDueDate ??= date;
          
          // タイトル（生徒名またはイベント）
          final String title;
          if (inputMode == 'student') {
            title = selectedStudent?['name'] as String? ?? '';
          } else {
            title = customTitleController.text;
          }
          
          // 生徒が選択されたらデータをロード
          if (inputMode == 'student' && title.isNotEmpty && title != lastLoadedStudent) {
            lastLoadedStudent = title;
            _loadStudentNotes(title).then((notes) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  therapyController.text = notes['therapyPlan'] ?? '';
                  schoolVisitController.text = notes['schoolVisit'] ?? '';
                  consultationController.text = notes['schoolConsultation'] ?? '';
                  moveRequestController.text = notes['moveRequest'] ?? '';
                  studentTasks = _getTasksForStudent(title);
                });
              }
            });
          }
          
          // 保存可能かチェック
final bool canSave = title.isNotEmpty;
          
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              width: 500,
              constraints: const BoxConstraints(maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${['月', '火', '水', '木', '金', '土'][dayIndex]}曜日 ${_timeSlots[slotIndex]} に追加',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                          color: AppColors.textSub,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      DateFormat('M月d日 (E)', 'ja').format(date),
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 入力モード切り替えタブ
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => inputMode = 'student'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: inputMode == 'student' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: inputMode == 'student' ? [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2),
                                  ] : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person, size: 16, 
                                      color: inputMode == 'student' ? AppColors.primary : AppColors.textSub),
                                    const SizedBox(width: 6),
                                    Text('生徒選択', style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: inputMode == 'student' ? FontWeight.bold : FontWeight.normal,
                                      color: inputMode == 'student' ? AppColors.primary : AppColors.textSub,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => inputMode = 'custom'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: inputMode == 'custom' ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: inputMode == 'custom' ? [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2),
                                  ] : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_note, size: 16,
                                      color: inputMode == 'custom' ? AppColors.primary : AppColors.textSub),
                                    const SizedBox(width: 6),
                                    Text('イベント', style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: inputMode == 'custom' ? FontWeight.bold : FontWeight.normal,
                                      color: inputMode == 'custom' ? AppColors.primary : AppColors.textSub,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // メインコンテンツ（スクロール可能）
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 生徒選択モード
                          if (inputMode == 'student') ...[
                            // 生徒選択（プルダウン形式）
                            InkWell(
                              onTap: () => _showStudentSelectionDialog(
                                selectedStudent,
                                (student) => setDialogState(() => selectedStudent = student),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person, size: 20, color: AppColors.textSub),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        selectedStudent == null
                                            ? '生徒を選択'
                                            : selectedStudent!['name'] as String,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: selectedStudent == null ? AppColors.textSub : AppColors.textMain,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          
                          // イベントモード
                          if (inputMode == 'custom') ...[
                            TextField(
                              controller: customTitleController,
                              decoration: InputDecoration(
                                hintText: 'タイトルを入力',
                                prefixIcon: const Icon(Icons.title, size: 20, color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 12),
                          ],
                          
                          // 共通入力フォーム
                          // 講師選択
                          InkWell(
                            onTap: () => _showMultiTeacherSelectionDialog(
                              selectedTeachers,
                              (newSelection) => setDialogState(() => selectedTeachers = newSelection),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person, size: 20, color: AppColors.textSub),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedTeachers.isEmpty
                                          ? '講師を選択'
                                          : selectedTeachers.contains('全員')
                                              ? '全員'
                                              : selectedTeachers.join('、'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: selectedTeachers.isEmpty ? AppColors.textSub : AppColors.textMain,
                                      ),
                                    ),
                                  ),
                                  if (selectedTeachers.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => setDialogState(() => selectedTeachers = []),
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.close, size: 18, color: AppColors.textSub),
                                      ),
                                    ),
                                  const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 部屋選択
                          InkWell(
                            onTap: () => _showRoomSelectionDialog(
                              selectedRoom,
                              (newRoom) => setDialogState(() => selectedRoom = newRoom),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.meeting_room, size: 20, color: AppColors.textSub),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedRoom.isEmpty ? '部屋を選択' : selectedRoom,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: selectedRoom.isEmpty ? AppColors.textSub : AppColors.textMain,
                                      ),
                                    ),
                                  ),
                                  if (selectedRoom.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => setDialogState(() => selectedRoom = ''),
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.close, size: 18, color: AppColors.textSub),
                                      ),
                                    ),
                                  const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // コース選択
                          InkWell(
                            onTap: () => _showCourseSelectionDialog(
                              selectedCourse,
                              (newCourse) => setDialogState(() => selectedCourse = newCourse),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12, height: 12,
                                    decoration: BoxDecoration(
                                      color: currentColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(selectedCourse, style: const TextStyle(fontSize: 15))),
                                  const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                ],
                              ),
                            ),
                          ),
                          
                          // === 生徒情報セクション（生徒モードで生徒選択済みの場合のみ） ===
                          if (inputMode == 'student' && title.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Divider(height: 1, color: Colors.grey.shade200),
                            const SizedBox(height: 20),
                            
                            // タスクセクション
                            Row(
                              children: [
                                const Icon(Icons.task_alt, size: 18, color: Colors.orange),
                                const SizedBox(width: 8),
                                const Text('タスク', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 既存タスク一覧
                            if (studentTasks.isNotEmpty) ...[
                              ...studentTasks.map((task) => GestureDetector(
                                onTap: () => _showEditTaskDialog(
                                  dialogContext, 
                                  task, 
                                  () => setDialogState(() {
                                    studentTasks = _getTasksForStudent(title);
                                  }),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(task['title'] ?? '', style: const TextStyle(fontSize: 13)),
                                            if (task['dueDate'] != null)
                                              Text(
                                                '期限: ${DateFormat('M/d').format((task['dueDate'] as Timestamp).toDate())}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          await _completeTask(task['id']);
                                          setDialogState(() {
                                            studentTasks = _getTasksForStudent(title);
                                          });
                                        },
                                        icon: const Icon(Icons.check_circle_outline, size: 20),
                                        color: Colors.green,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: '完了',
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                            ],
                            // 新規タスク入力
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newTaskController,
                                    decoration: InputDecoration(
                                      hintText: '新しいタスク',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      isDense: true,
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                    onChanged: (_) => setDialogState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 期限選択
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: dialogContext,
                                      initialDate: newTaskDueDate ?? DateTime.now(),
                                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (picked != null) {
                                      setDialogState(() => newTaskDueDate = picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today, size: 16, color: newTaskDueDate != null ? AppColors.primary : AppColors.textSub),
                                        if (newTaskDueDate != null) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            DateFormat('M/d').format(newTaskDueDate!),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 8),
                            // タスク追加ボタン（左寄せ）
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () async {
                                  final taskText = newTaskController.text.trim();
                                  if (taskText.isEmpty) return;
                                  final newTask = await _addTaskForStudent(
                                    title,
                                    taskText,
                                    newTaskDueDate,
                                  );
                                  newTaskController.clear();
                                  setDialogState(() {
                                    newTaskDueDate = date;
                                    if (newTask != null) {
                                      studentTasks = [...studentTasks, newTask];
                                    }
                                  });
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: newTaskController.text.trim().isEmpty 
                                        ? Colors.grey.shade300 
                                        : AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 療育プラン
                            Row(
                              children: [
                                const Icon(Icons.psychology, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                const Text('療育プラン', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: therapyController,
                              decoration: InputDecoration(
                                hintText: '療育の目標や方針を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                            
                            const SizedBox(height: 16),
                            // 園訪問
                            Row(
                              children: [
                                Icon(Icons.school, size: 18, color: Colors.teal.shade600),
                                const SizedBox(width: 8),
                                const Text('園訪問', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: schoolVisitController,
                              decoration: InputDecoration(
                                hintText: '園訪問の記録や予定を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                            
                            const SizedBox(height: 16),
                            // 就学相談
                            Row(
                              children: [
                                Icon(Icons.celebration, size: 18, color: Colors.indigo.shade600),
                                const SizedBox(width: 8),
                                const Text('就学相談', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: consultationController,
                              decoration: InputDecoration(
                                hintText: '就学相談の記録や予定を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                            
                            const SizedBox(height: 16),
                            // 移動希望
                            Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 18, color: Colors.purple.shade600),
                                const SizedBox(width: 8),
                                const Text('移動希望', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: moveRequestController,
                              decoration: InputDecoration(
                                hintText: '曜日や時間の変更希望を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  
                  // ボタン
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canSave
                            ? () async {
                                final saveDate = DateTime(date.year, date.month, date.day, 12, 0, 0);
                                final lessonData = {
                                  'date': Timestamp.fromDate(saveDate),
                                  'slotIndex': slotIndex,
                                  'studentName': title,
                                  'teachers': selectedTeachers,
                                  'room': selectedRoom,
                                  'course': selectedCourse,
                                  'note': '',
                                  'link': '',
                                  'isCustomEvent': inputMode == 'custom',
                                  'order': DateTime.now().millisecondsSinceEpoch,
                                  'createdAt': FieldValue.serverTimestamp(),
                                };
                                
                                try {
                                  // タスクを追加（入力欄にテキストがある場合）
                                  final taskText = newTaskController.text.trim();
                                  if (taskText.isNotEmpty && inputMode == 'student' && title.isNotEmpty) {
                                    await _addTaskForStudent(
                                      title, // 生徒名
                                      taskText,
                                      newTaskDueDate,
                                    );
                                  }
                                  
                                  await FirebaseFirestore.instance.collection('plus_lessons').add(lessonData);
                                  
                                  // 生徒メモを保存（生徒モードの場合のみ）
                                  if (inputMode == 'student' && title.isNotEmpty) {
                                    await _saveStudentNotes(title, {
                                      'therapyPlan': therapyController.text,
                                      'schoolVisit': schoolVisitController.text,
                                      'schoolConsultation': consultationController.text,
                                      'moveRequest': moveRequestController.text,
                                    });
                                  }
                                  
                                  if (!dialogContext.mounted) return;
                                  Navigator.pop(dialogContext);
                                  await _loadLessonsForWeek();
                                  if (mounted) {
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(content: Text('追加しました')),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint('Error adding lesson: $e');
                                  if (mounted) {
                                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('エラー: $e')));
                                  }
                                }
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
  title.isEmpty
      ? (inputMode == 'student' ? '生徒を選択してください' : 'タイトルを入力してください')
      : '$titleを追加',
  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 生徒選択ダイアログ
  void _showStudentSelectionDialog(Map<String, dynamic>? currentStudent, Function(Map<String, dynamic>?) onConfirm) {
    String searchText = '';
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // 検索フィルタリング
          final filteredStudents = searchText.isEmpty
              ? _allStudents
              : _allStudents.where((s) {
                  final name = (s['name'] as String).toLowerCase();
                  return name.contains(searchText.toLowerCase());
                }).toList();
          
          // あいうえお順でグループ分け
          final groupedStudents = <String, List<Map<String, dynamic>>>{};
          for (var student in filteredStudents) {
            final kana = student['lastNameKana'] as String? ?? '';
            final group = _getKanaGroup(kana);
            groupedStudents.putIfAbsent(group, () => []);
            groupedStudents[group]!.add(student);
          }
          final sortedGroups = groupedStudents.keys.toList()..sort();
          
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('生徒を選択', style: TextStyle(fontSize: 18)),
            content: SizedBox(
              width: 350,
              height: 400,
              child: Column(
                children: [
                  // 検索フィールド
                  TextField(
                    decoration: InputDecoration(
                      hintText: '名前で検索...',
                      prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(() => searchText = value),
                  ),
                  const SizedBox(height: 12),
                  // 生徒リスト
                  Expanded(
                    child: filteredStudents.isEmpty
                        ? const Center(child: Text('生徒が見つかりません', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: sortedGroups.length,
                            itemBuilder: (listContext, groupIndex) {
                              final group = sortedGroups[groupIndex];
                              final studentsInGroup = groupedStudents[group]!;
                              
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    color: Colors.grey.shade100,
                                    child: Text(group, style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700,
                                    )),
                                  ),
                                  ...studentsInGroup.map((student) {
                                    final isSelected = currentStudent?['name'] == student['name'];
                                    return ListTile(
                                      dense: true,
                                      title: Text(student['name'], style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? AppColors.primary : null,
                                      )),
                                      onTap: () {
                                        Navigator.pop(dialogContext);
                                        onConfirm(student);
                                      },
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 講師複数選択ダイアログ
  void _showMultiTeacherSelectionDialog(List<String> currentSelection, Function(List<String>) onConfirm) {
    List<String> tempSelection = List.from(currentSelection);
    bool isAllSelected = tempSelection.contains('全員');
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('講師を選択', style: TextStyle(fontSize: 18)),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 個別スタッフ（先に表示）
                    ..._staffList.map((staff) {
                      final name = staff['name'] as String;
                      final isSelected = tempSelection.contains(name);
                      return CheckboxListTile(
                        title: Text(name),
                        value: isSelected,
                        onChanged: isAllSelected ? null : (value) {
                          setDialogState(() {
                            if (value == true) {
                              tempSelection.add(name);
                            } else {
                              tempSelection.remove(name);
                            }
                          });
                        },
                        activeColor: Colors.grey.shade500,
                        checkColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade400),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                    const Divider(),
                    // 「全員」オプション（最下部）
                    CheckboxListTile(
                      title: const Text('全員'),
                      value: isAllSelected,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            tempSelection = ['全員'];
                            isAllSelected = true;
                          } else {
                            tempSelection.remove('全員');
                            isAllSelected = false;
                          }
                        });
                      },
                      activeColor: Colors.grey.shade500,
                      checkColor: Colors.white,
                      side: BorderSide(color: Colors.grey.shade400),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  onConfirm(tempSelection);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('確定'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 部屋選択ダイアログ
  void _showRoomSelectionDialog(String currentRoom, Function(String) onConfirm) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('部屋を選択', style: TextStyle(fontSize: 18)),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _roomList.map((room) {
                  final isSelected = currentRoom == room;
                  return ListTile(
                    title: Text(room, style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.primary : null,
                    )),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      onConfirm(room);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  // ひらがな/カタカナの行を取得
  String _getKanaGroup(String kana) {
    if (kana.isEmpty) return 'その他';
    final firstChar = kana[0];
    
    if ('あいうえおアイウエオ'.contains(firstChar)) return 'あ';
    if ('かきくけこがぎぐげごカキクケコガギグゲゴ'.contains(firstChar)) return 'か';
    if ('さしすせそざじずぜぞサシスセソザジズゼゾ'.contains(firstChar)) return 'さ';
    if ('たちつてとだぢづでどタチツテトダヂヅデド'.contains(firstChar)) return 'た';
    if ('なにぬねのナニヌネノ'.contains(firstChar)) return 'な';
    if ('はひふへほばびぶべぼぱぴぷぺぽハヒフヘホバビブベボパピプペポ'.contains(firstChar)) return 'は';
    if ('まみむめもマミムメモ'.contains(firstChar)) return 'ま';
    if ('やゆよヤユヨ'.contains(firstChar)) return 'や';
    if ('らりるれろラリルレロ'.contains(firstChar)) return 'ら';
    if ('わをんワヲン'.contains(firstChar)) return 'わ';
    
    return 'その他';
  }


  void _showEditLessonDialog(Map<String, dynamic> lesson) {
    final dayIndex = lesson['dayIndex'] as int;
    final slotIndex = lesson['slotIndex'] as int;
    final date = _weekStart.add(Duration(days: dayIndex));
    final studentName = lesson['studentName'] as String? ?? '';
    final isCustomEvent = lesson['isCustomEvent'] == true;
    
    // 編集用の状態変数
    List<String> selectedTeachers = List<String>.from(lesson['teachers'] ?? []);
    String selectedRoom = lesson['room'] ?? 'つき';
    String selectedCourse = lesson['course'] ?? '通常';
    
    // 生徒メモ用コントローラー
    final therapyController = TextEditingController();
    final schoolVisitController = TextEditingController();
    final consultationController = TextEditingController();
    final moveRequestController = TextEditingController();
    
    // タスク用
    List<Map<String, dynamic>> studentTasks = [];
    final newTaskController = TextEditingController();
    DateTime? newTaskDueDate = date; // デフォルトでイベント当日
    
    // 初期データ読み込み
    bool isLoading = true;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // 初回のみデータ読み込み（生徒選択モードの場合のみ）
          if (isLoading && !isCustomEvent && studentName.isNotEmpty) {
            isLoading = false;
            _loadStudentNotes(studentName).then((notes) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  therapyController.text = notes['therapyPlan'] ?? '';
                  schoolVisitController.text = notes['schoolVisit'] ?? '';
                  consultationController.text = notes['schoolConsultation'] ?? '';
                  moveRequestController.text = notes['moveRequest'] ?? '';
                  studentTasks = _getTasksForStudent(studentName);
                });
              }
            });
          }
          
          final currentColor = _courseColors[selectedCourse] ?? Colors.blue;
          
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              width: 500,
              constraints: const BoxConstraints(maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー（ゴミ箱と閉じるボタン）
                  Container(
                    padding: const EdgeInsets.only(right: 4, top: 4),
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _showDeleteConfirmDialog(lesson);
                          },
                          tooltip: '削除',
                          color: AppColors.textSub,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                          color: AppColors.textSub,
                        ),
                      ],
                    ),
                  ),
                  // 生徒名
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: currentColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            studentName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 日時
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '${DateFormat('M月d日 (E)', 'ja').format(date)}　${_timeSlots[slotIndex]}',
                      style: const TextStyle(fontSize: 14, color: AppColors.textSub),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: Colors.grey.shade200),
                  // メインコンテンツ
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // === レッスン情報 ===
                          // 講師選択
                          InkWell(
                            onTap: () => _showMultiTeacherSelectionDialog(
                              selectedTeachers,
                              (newSelection) => setDialogState(() => selectedTeachers = newSelection),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person, size: 20, color: AppColors.textSub),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedTeachers.isEmpty
                                          ? '講師を選択'
                                          : selectedTeachers.contains('全員')
                                              ? '全員'
                                              : selectedTeachers.join('、'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: selectedTeachers.isEmpty ? AppColors.textSub : AppColors.textMain,
                                      ),
                                    ),
                                  ),
                                  if (selectedTeachers.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => setDialogState(() => selectedTeachers = []),
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.close, size: 18, color: AppColors.textSub),
                                      ),
                                    ),
                                  const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 部屋選択
                          InkWell(
                            onTap: () => _showRoomSelectionDialog(
                              selectedRoom,
                              (newRoom) => setDialogState(() => selectedRoom = newRoom),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.meeting_room, size: 20, color: AppColors.textSub),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedRoom.isEmpty ? '部屋を選択' : selectedRoom,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: selectedRoom.isEmpty ? AppColors.textSub : AppColors.textMain,
                                      ),
                                    ),
                                  ),
                                  if (selectedRoom.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => setDialogState(() => selectedRoom = ''),
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.close, size: 18, color: AppColors.textSub),
                                      ),
                                    ),
                                  const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // コース選択
                          InkWell(
                            onTap: () => _showCourseSelectionDialog(
                              selectedCourse,
                              (newCourse) => setDialogState(() => selectedCourse = newCourse),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12, height: 12,
                                    decoration: BoxDecoration(
                                      color: currentColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(selectedCourse, style: const TextStyle(fontSize: 15))),
                                  const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                                ],
                              ),
                            ),
                          ),
                          
                          // === 生徒情報セクション（イベントモードでない場合のみ表示） ===
                          if (!isCustomEvent && studentName.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Divider(height: 1, color: Colors.grey.shade200),
                            const SizedBox(height: 20),
                            
                            // タスクセクション
                            Row(
                              children: [
                                const Icon(Icons.task_alt, size: 18, color: Colors.orange),
                                const SizedBox(width: 8),
                                const Text('タスク', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 既存タスク一覧
                            if (studentTasks.isNotEmpty) ...[
                              ...studentTasks.map((task) => GestureDetector(
                                onTap: () => _showEditTaskDialog(
                                  dialogContext, 
                                  task, 
                                  () => setDialogState(() {
                                    studentTasks = _getTasksForStudent(studentName);
                                  }),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(task['title'] ?? '', style: const TextStyle(fontSize: 13)),
                                            if (task['dueDate'] != null)
                                              Text(
                                                '期限: ${DateFormat('M/d').format((task['dueDate'] as Timestamp).toDate())}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          await _completeTask(task['id']);
                                          setDialogState(() {
                                            studentTasks = _getTasksForStudent(studentName);
                                          });
                                        },
                                        icon: const Icon(Icons.check_circle_outline, size: 20),
                                        color: Colors.green,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: '完了',
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                            ],
                            // 新規タスク入力
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newTaskController,
                                    decoration: InputDecoration(
                                      hintText: '新しいタスク',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      isDense: true,
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                    onChanged: (_) => setDialogState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 期限選択
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: dialogContext,
                                      initialDate: newTaskDueDate ?? DateTime.now(),
                                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (picked != null) {
                                      setDialogState(() => newTaskDueDate = picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.calendar_today, size: 16, color: newTaskDueDate != null ? AppColors.primary : AppColors.textSub),
                                        if (newTaskDueDate != null) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            DateFormat('M/d').format(newTaskDueDate!),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 8),
                            // タスク追加ボタン（左寄せ）
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () async {
                                  final taskText = newTaskController.text.trim();
                                  if (taskText.isEmpty) return;
                                  final newTask = await _addTaskForStudent(
                                    studentName,
                                    taskText,
                                    newTaskDueDate,
                                  );
                                  newTaskController.clear();
                                  setDialogState(() {
                                    newTaskDueDate = date;
                                    if (newTask != null) {
                                      studentTasks = [...studentTasks, newTask];
                                    }
                                  });
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: newTaskController.text.trim().isEmpty 
                                        ? Colors.grey.shade300 
                                        : AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 療育プラン
                            Row(
                              children: [
                                const Icon(Icons.psychology, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                const Text('療育プラン', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: therapyController,
                              decoration: InputDecoration(
                                hintText: '療育の目標や方針を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                            
                            const SizedBox(height: 16),
                            // 園訪問
                            Row(
                              children: [
                                Icon(Icons.school, size: 18, color: Colors.teal.shade600),
                                const SizedBox(width: 8),
                                const Text('園訪問', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: schoolVisitController,
                              decoration: InputDecoration(
                                hintText: '園訪問の記録や予定を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                            
                            const SizedBox(height: 16),
                            // 就学相談
                            Row(
                              children: [
                                Icon(Icons.celebration, size: 18, color: Colors.indigo.shade600),
                                const SizedBox(width: 8),
                                const Text('就学相談', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: consultationController,
                              decoration: InputDecoration(
                                hintText: '就学相談の記録や予定を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                            
                            const SizedBox(height: 16),
                            // 移動希望
                            Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 18, color: Colors.purple.shade600),
                                const SizedBox(width: 8),
                                const Text('移動希望', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: moveRequestController,
                              decoration: InputDecoration(
                                hintText: '曜日や時間の変更希望を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              maxLines: 3,
                              minLines: 2,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // 保存ボタン
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('キャンセル'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final lessonId = lesson['id'] as String?;
                            if (lessonId == null) {
                              Navigator.pop(dialogContext);
                              return;
                            }
                            
                            try {
                              // タスクを追加（入力欄にテキストがある場合）
                              final taskText = newTaskController.text.trim();
                              if (taskText.isNotEmpty && studentName.isNotEmpty) {
                                await _addTaskForStudent(
                                  studentName,
                                  taskText,
                                  newTaskDueDate,
                                );
                              }
                              
                              // レッスン情報を保存
                              await FirebaseFirestore.instance
                                  .collection('plus_lessons')
                                  .doc(lessonId)
                                  .update({
                                'teachers': selectedTeachers,
                                'room': selectedRoom,
                                'course': selectedCourse,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                              
                              // 生徒メモを保存（生徒モードの場合のみ）
                              if (!isCustomEvent && studentName.isNotEmpty) {
                                await _saveStudentNotes(studentName, {
                                  'therapyPlan': therapyController.text,
                                  'schoolVisit': schoolVisitController.text,
                                  'schoolConsultation': consultationController.text,
                                  'moveRequest': moveRequestController.text,
                                });
                              }
                              
                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext);
                              await _loadLessonsForWeek();
                              
                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(content: Text('保存しました')),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error updating lesson: $e');
                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(content: Text('エラー: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCourseSelectionDialog(String currentCourse, Function(String) onSelect) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('内容を選択', style: TextStyle(fontSize: 18)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _courseList.map((course) {
              final color = _courseColors[course] ?? Colors.blue;
              return ListTile(
                leading: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(course),
                trailing: currentCourse == course
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(dialogContext);
                  onSelect(course);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(Map<String, dynamic> lesson) {
    // 親のScaffoldMessengerを事前に取得
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('レッスンを削除'),
        content: Text('${lesson['studentName']} のレッスンを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              final lessonId = lesson['id'] as String?;
              if (lessonId == null) {
                Navigator.pop(dialogContext);
                return;
              }
              
              // 先にダイアログを閉じる
              Navigator.pop(dialogContext);
              
              try {
                await FirebaseFirestore.instance
                    .collection('plus_lessons')
                    .doc(lessonId)
                    .delete();
                
                if (!mounted) return;
                await _loadLessonsForWeek();
                
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('削除しました')),
                  );
                }
              } catch (e) {
                debugPrint('Error deleting lesson: $e');
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('エラー: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }
}

/// 単独画面として使う場合（スマホ版など）
class PlusScheduleScreen extends StatelessWidget {
  const PlusScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PlusScheduleContent(
        onBack: () => Navigator.pop(context),
      ),
    );
  }
}

/// 右上三角マーク用のカスタムペインター
class _NoteTrianglePainter extends CustomPainter {
  final Color color;
  
  _NoteTrianglePainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}