import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'plus_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/gestures.dart';
import 'ai_chat_screen.dart';

/// プラス予定のコンテンツウィジェット（埋め込み用）
class PlusScheduleContent extends StatefulWidget {
  final VoidCallback? onBack;
  
  const PlusScheduleContent({super.key, this.onBack});

  @override
  State<PlusScheduleContent> createState() => _PlusScheduleContentState();
}

class _PlusScheduleContentState extends State<PlusScheduleContent> with AutomaticKeepAliveClientMixin {
  // AutomaticKeepAliveClientMixinを追加して、タブ切り替え時に状態を保持
  @override
  bool get wantKeepAlive => true;
  late DateTime _weekStart;
  
// 表示モード: 0=週カレンダー, 1=ダッシュボード, 2=月カレンダー
  int _viewMode = 0;
  
  // 月カレンダー用の表示月
  late DateTime _monthViewDate;
  
  // 月カレンダー用のレッスンデータ
  List<Map<String, dynamic>> _monthLessons = [];
  bool _isLoadingMonthLessons = false;

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

  // コース（内容）の定義と色（カスタマイズ可能）
  static const Map<String, Color> _defaultCourseColors = {
    '通常': Colors.blue,
    'モンテッソーリ': Colors.lightBlue,
    '感覚統合': Colors.teal,
    '言語': Colors.purple,
    '就学支援': Colors.indigo,
    '契約': Colors.orange,
    '体験': Colors.green,
    '欠席': Colors.red,
  };
  
  // カスタマイズ可能なコース色
  Map<String, Color> _courseColors = {};
  
  final List<String> _courseList = ['通常', 'モンテッソーリ', '感覚統合', '言語', '就学支援', '契約', '体験', '欠席'];
  
  // カラーパレット（選択可能な色）
  static const List<Color> _colorPalette = [
    Colors.blue, Colors.lightBlue, Colors.cyan, Colors.teal,
    Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow,
    Colors.amber, Colors.orange, Colors.deepOrange, Colors.red,
    Colors.pink, Colors.purple, Colors.deepPurple, Colors.indigo,
    Colors.brown, Colors.grey, Colors.blueGrey,
  ];

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
  Map<String, Map<String, dynamic>> _cellMemos = {};
  
  // ホバーポップアップ用のオーバーレイエントリ（グローバル管理）
  OverlayEntry? _currentOverlay;
  
  // サイドメニュー関連
  bool _isSideMenuOpen = false;
  DateTime _sideMenuMonth = DateTime.now();
  Set<String> _selectedFilters = {'all'}; // 'all', 'mySchedule', 'event', または講師名

  // ページコントローラー（週スクロール用）
  int _currentWeekPage = 1000; // 中央値から開始（前後にスクロール可能にするため）
  DateTime _baseWeekStart = DateTime.now(); // 基準週

  int _lastScrollTime = 0;
  bool _slideFromRight = true;

@override
void initState() {
  super.initState();
  _weekStart = _getMonday(DateTime.now());
  _baseWeekStart = _weekStart; // 基準週を保存
  _monthViewDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  _courseColors = Map.from(_defaultCourseColors);
  _initializeData();
}

// コース色をFirestoreから読み込む
Future<void> _loadCourseColors() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('plus_settings')
        .doc('course_colors')
        .get();
    
    if (doc.exists) {
      final data = doc.data()!;
      final colors = data['colors'] as Map<String, dynamic>?;
      if (colors != null) {
        setState(() {
          for (var entry in colors.entries) {
            final colorValue = entry.value as int?;
            if (colorValue != null) {
              _courseColors[entry.key] = Color(colorValue);
            }
          }
        });
      }
    }
  } catch (e) {
    debugPrint('Error loading course colors: $e');
  }
}

// コース色をFirestoreに保存
Future<void> _saveCourseColor(String course, Color color) async {
  try {
    setState(() {
      _courseColors[course] = color;
    });
    
    final colorsMap = <String, int>{};
    for (var entry in _courseColors.entries) {
      colorsMap[entry.key] = entry.value.value;
    }
    
    await FirebaseFirestore.instance
        .collection('plus_settings')
        .doc('course_colors')
        .set({
      'colors': colorsMap,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
    debugPrint('Error saving course color: $e');
  }
}

// 新しいメソッド（initStateの直後に追加）
Future<void> _initializeData() async {
  await _loadSavedState();  // まず保存された状態を読み込む
  await _loadCourseColors();
  await _loadInitialData(); // その後でデータを読み込む
}
  
Future<void> _loadSavedState() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedViewMode = prefs.getInt('plusScheduleViewMode');
    final savedWeekStart = prefs.getString('plusScheduleWeekStart');
    final savedMonthViewDate = prefs.getString('plusScheduleMonthViewDate');
    
    if (mounted) {
      setState(() {
        if (savedViewMode != null) _viewMode = savedViewMode;
        if (savedWeekStart != null) {
          final date = DateTime.tryParse(savedWeekStart);
          if (date != null) {
            _weekStart = _getMonday(date);
          }
        }
        if (savedMonthViewDate != null) {
          final date = DateTime.tryParse(savedMonthViewDate);
          if (date != null) _monthViewDate = DateTime(date.year, date.month, 1);
        }
      });
    }
  } catch (e) {
    debugPrint('Error loading saved state: $e');
  }
}
Future<void> _saveViewMode(int mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('plusScheduleViewMode', mode);
  } catch (e) {
    debugPrint('Error saving view mode: $e');
  }
}

Future<void> _saveWeekStart(DateTime date) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plusScheduleWeekStart', date.toIso8601String());
  } catch (e) {
    debugPrint('Error saving week start: $e');
  }
}

Future<void> _saveMonthViewDate(DateTime date) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plusScheduleMonthViewDate', date.toIso8601String());
  } catch (e) {
    debugPrint('Error saving month view date: $e');
  }
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
    _loadStudentsFromFirestore(),
    _loadAllTasks(),
  ]);
  
  // viewModeに応じてレッスンを読み込む
  if (_viewMode == 2) {
    await _loadLessonsForMonth();
  } else {
    await _loadLessonsForWeek();
  }
}

// ★追加★ コマメモを週単位で読み込み
Future<void> _loadCellMemosForWeek() async {
  try {
    final memos = <String, Map<String, dynamic>>{};
    
    for (int dayIndex = 0; dayIndex < 6; dayIndex++) {
      final date = _weekStart.add(Duration(days: dayIndex));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      for (int slotIndex = 0; slotIndex < 4; slotIndex++) {
        final docId = '${dateStr}_$slotIndex';
        final doc = await FirebaseFirestore.instance
            .collection('plus_cell_memos')
            .doc(docId)
            .get();
        
        if (doc.exists) {
          memos[docId] = {
            'id': doc.id,
            ...doc.data()!,
          };
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _cellMemos = memos;
      });
    }
  } catch (e) {
    debugPrint('Error loading cell memos: $e');
  }
}

// ★追加★ コマメモを保存
Future<void> _saveCellMemo(DateTime date, int slotIndex, String title, String comment) async {
  final dateStr = DateFormat('yyyy-MM-dd').format(date);
  final docId = '${dateStr}_$slotIndex';
  
  try {
    await FirebaseFirestore.instance
        .collection('plus_cell_memos')
        .doc(docId)
        .set({
      'title': title,
      'comment': comment,
      'date': Timestamp.fromDate(date),
      'slotIndex': slotIndex,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    setState(() {
      _cellMemos[docId] = {
        'id': docId,
        'title': title,
        'comment': comment,
        'date': Timestamp.fromDate(date),
        'slotIndex': slotIndex,
      };
    });
  } catch (e) {
    debugPrint('Error saving cell memo: $e');
  }
}

// ★追加★ コマメモを削除
Future<void> _deleteCellMemo(DateTime date, int slotIndex) async {
  final dateStr = DateFormat('yyyy-MM-dd').format(date);
  final docId = '${dateStr}_$slotIndex';
  
  try {
    await FirebaseFirestore.instance
        .collection('plus_cell_memos')
        .doc(docId)
        .delete();
    
    setState(() {
      _cellMemos.remove(docId);
    });
  } catch (e) {
    debugPrint('Error deleting cell memo: $e');
  }
}

// ★追加★ コマメモを取得
Map<String, dynamic>? _getCellMemo(DateTime date, int slotIndex) {
  final dateStr = DateFormat('yyyy-MM-dd').format(date);
  final docId = '${dateStr}_$slotIndex';
  return _cellMemos[docId];
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
            'profileUrl': child['profileUrl'] ?? '',
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
  Future<void> _loadLessonsForWeek({bool showLoading = true}) async {
  if (!mounted) return;
  
  if (showLoading) {
    setState(() {
      _isLoadingLessons = true;
    });
  }
    
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
        _loadCellMemosForWeek();
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

  // 月カレンダー用のレッスンを読み込み
  Future<void> _loadLessonsForMonth() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingMonthLessons = true;
    });
    
    try {
      final monthStart = DateTime(_monthViewDate.year, _monthViewDate.month, 1);
      final monthEnd = DateTime(_monthViewDate.year, _monthViewDate.month + 1, 0, 23, 59, 59);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .orderBy('date')
          .get();
      
      if (!mounted) return;
      
      final lessons = <Map<String, dynamic>>[];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final dateField = data['date'];
        if (dateField == null || dateField is! Timestamp) continue;
        
        final date = dateField.toDate();
        
        lessons.add({
          'id': doc.id,
          'date': date,
          'slotIndex': data['slotIndex'] ?? 0,
          'studentName': data['studentName'] ?? '',
          'teachers': List<String>.from(data['teachers'] ?? []),
          'room': data['room'] ?? '',
          'course': data['course'] ?? '通常',
          'note': data['note'] ?? '',
          'order': data['order'] ?? 0,
        });
      }
      
      lessons.sort((a, b) {
        final dateCompare = (a['date'] as DateTime).compareTo(b['date'] as DateTime);
        if (dateCompare != 0) return dateCompare;
        final slotCompare = (a['slotIndex'] as int).compareTo(b['slotIndex'] as int);
        if (slotCompare != 0) return slotCompare;
        return (a['order'] as int).compareTo(b['order'] as int);
      });
      
      if (mounted) {
        setState(() {
          _monthLessons = lessons;
          _isLoadingMonthLessons = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading month lessons: $e');
      if (mounted) {
        setState(() {
          _isLoadingMonthLessons = false;
        });
      }
    }
  }
  
  // 特定の日付のレッスンを取得
  List<Map<String, dynamic>> _getLessonsForDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return _monthLessons.where((lesson) {
      final lessonDate = lesson['date'] as DateTime;
      return lessonDate.year == dateOnly.year &&
             lessonDate.month == dateOnly.month &&
             lessonDate.day == dateOnly.day;
    }).toList();
  }
  
  // 月移動
  void _previousMonth() {
    _hideCurrentOverlay();
    setState(() {
      _monthViewDate = DateTime(_monthViewDate.year, _monthViewDate.month - 1, 1);
    });
    _saveMonthViewDate(_monthViewDate);
    _loadLessonsForMonth();
  }
  
  void _nextMonth() {
    _hideCurrentOverlay();
    setState(() {
      _monthViewDate = DateTime(_monthViewDate.year, _monthViewDate.month + 1, 1);
    });
    _saveMonthViewDate(_monthViewDate);
    _loadLessonsForMonth();
  }
  
  void _goToThisMonth() {
    _hideCurrentOverlay();
    setState(() {
      _monthViewDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    });
    _loadLessonsForMonth();
  }

  DateTime _getMonday(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    // 時刻を00:00:00にリセット（日付計算の精度を確保）
    return DateTime(monday.year, monday.month, monday.day);
  }

 void _previousWeek() {
  setState(() => _slideFromRight = false);
  _goToPage(_currentWeekPage - 1);
}

void _nextWeek() {
  setState(() => _slideFromRight = true);
  _goToPage(_currentWeekPage + 1);
}

void _goToThisWeek() {
  _hideCurrentOverlay();
  final thisWeekStart = _getMonday(DateTime.now());
  final weeksDiff = thisWeekStart.difference(_baseWeekStart).inDays ~/ 7;
  _goToPage(1000 + weeksDiff);
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
            final defaultShift = data['defaultShift'] as Map<String, dynamic>?;
            return {
  'id': doc.id,
  'name': data['name'] ?? '',
  'furigana': data['furigana'] ?? '',
  'uid': data['uid'] ?? '',
  'isPlus': true,
  'staffType': data['staffType'] ?? 'fulltime',
  'defaultShiftStart': defaultShift?['start'] ?? '9:00',
  'defaultShiftEnd': defaultShift?['end'] ?? '18:00',
  'showInSchedule': data['showInSchedule'] ?? true,  // ← 追加
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
  super.build(context); // ← この行を追加（AutomaticKeepAliveClientMixin必須）
  
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
            if (_viewMode == 0 || _viewMode == 2)
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
              // メインコンテンツ
              Expanded(
  child: _viewMode == 0
      ? _buildWeekPageView()  // ← ここを変更
      : _viewMode == 2
          ? (_isLoadingMonthLessons
              ? const Center(child: CircularProgressIndicator())
              : _buildMonthCalendar())
          : const PlusDashboardContent(),
),
            ],
          ),
        ),
      ],
    );
  }


Widget _buildWeekPageView() {
  const double kScrollDxTrigger = 14.0;
  const int kLockMs = 1000;

  bool isLocked() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - _lastScrollTime) < kLockMs;
  }

  void lockAndMove({required bool next}) {
    if (isLocked()) return;
    _lastScrollTime = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _slideFromRight = next;  // 方向を記録
    });
    if (next) {
      _nextWeek();
    } else {
      _previousWeek();
    }
  }

  return Listener(
    behavior: HitTestBehavior.translucent,
    onPointerSignal: (signal) {
      if (signal is PointerScrollEvent) {
        if (isLocked()) return;

        final dx = signal.scrollDelta.dx;
        final dy = signal.scrollDelta.dy;

        if (dx.abs() >= kScrollDxTrigger) {
          lockAndMove(next: dx > 0);
          return;
        }

        if (dy.abs() >= kScrollDxTrigger) {
          lockAndMove(next: dy > 0);
        }
      }
    },
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (isLocked()) return;
        final v = details.primaryVelocity ?? 0;
        if (v < -100) {
          lockAndMove(next: true);
        } else if (v > 100) {
          lockAndMove(next: false);
        }
      },
      child: _isLoadingLessons
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                // スライド方向に応じたオフセット
                final offsetAnimation = Tween<Offset>(
                  begin: Offset(_slideFromRight ? 1.0 : -1.0, 0.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ));
                
                return SlideTransition(
                  position: offsetAnimation,
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_weekStart),  // 週が変わるとアニメーション発動
                child: _buildScheduleTable(),
              ),
            ),
    ),
  );
}
  

void _goToPage(int page) {
  _hideCurrentOverlay();
  final weeksDiff = page - 1000;
  final newWeekStart = _baseWeekStart.add(Duration(days: weeksDiff * 7));
  
  setState(() {
    _currentWeekPage = page;
    _weekStart = newWeekStart;
  });
  
  _saveWeekStart(_weekStart);
  _loadShiftData();
  _loadLessonsForWeek(showLoading: false);  // ← ここを変更
  _loadAllTasks();
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
    final plusStaff = _staffList.where((s) => 
  s['isPlus'] == true && s['showInSchedule'] != false
).toList();
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
                      _saveWeekStart(_weekStart);
                      _loadShiftData();
                      _loadLessonsForWeek();
                    },
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
                      ),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isToday ? AppColors.primary : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 13,
                                color: isToday ? Colors.white : (isSunday ? Colors.red : (isSaturday ? Colors.blue : Colors.black87)),
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
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
   // プラス担当のスタッフを取得（showInSchedule=trueのみ）
final plusStaff = _staffList.where((s) => 
  s['isPlus'] == true && s['showInSchedule'] != false
).toList();
    
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
          ] else if (_viewMode == 2) ...[   // ← ] を追加
            // 月カレンダーモードの時
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.textMain),
              tooltip: 'メニュー',
              onPressed: () => setState(() => _isSideMenuOpen = !_isSideMenuOpen),
            ),
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
                onPressed: _goToThisMonth,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  foregroundColor: AppColors.textMain,
                ),
                child: const Text('今月'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppColors.textSub),
              onPressed: _previousMonth,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppColors.textSub),
              onPressed: _nextMonth,
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('yyyy年 M月', 'ja').format(_monthViewDate),
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
                _buildViewModeTab(0, Icons.calendar_today, '週'),
                _buildViewModeTab(2, Icons.calendar_month, '月'),
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
           _saveViewMode(mode);
            if (mode == 0) {
  _loadAllTasks();
  _loadLessonsForWeek(showLoading: false); 
}
            // 月カレンダーモードに切り替えた時は月データを読み込み
            if (mode == 2) {
              _loadLessonsForMonth();
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
      // タスク件数表示（タスクがない場合も追加ボタンを表示）
                  SizedBox(
                    height: 22,
                    child: GestureDetector(
                      onTap: () {
                        if (taskCount > 0) {
                          _showTasksForDateDialog(date, tasksForDay);
                        } else {
                          _showAddTaskDialogForDate(date);
                        }
                      },
                      child: taskCount > 0
                          ? Container(
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
                            )
                          : MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.add_circle_outline,
                                  size: 16,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                    ),
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
          // 最新のタスクリストを取得
          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          final currentTasks = _tasksByDueDate[dateKey] ?? [];
          
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentTasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('タスクはありません', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ...currentTasks.map((task) {
                      final studentName = task['studentName'] as String?;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _showEditTaskDialog(context, task, () {
                            _showTasksForDateDialog(date, _tasksByDueDate[dateKey] ?? []);
                          });
                        },
                        child: Container(
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
                              IconButton(
                                onPressed: () async {
                                  await _completeTask(task['id']);
                                  setDialogState(() {});
                                  setState(() {});
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(content: Text('タスクを完了しました')),
                                  );
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                color: Colors.green,
                                tooltip: '完了',
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  // タスク追加ボタン
                  InkWell(
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showAddTaskDialogForDate(date);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.primary.withValues(alpha: 0.05),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 18, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'タスクを追加',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
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

  // 日付指定でタスク追加ダイアログ（ダッシュボードと同等のUI）
  void _showAddTaskDialogForDate(DateTime date) {
    String inputMode = 'student'; // 'student' or 'custom'
    Map<String, dynamic>? selectedStudent;
    final titleController = TextEditingController();
    final commentController = TextEditingController();
    DateTime selectedDueDate = date;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSave = inputMode == 'student'
              ? (selectedStudent != null && titleController.text.isNotEmpty)
              : titleController.text.isNotEmpty;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.task_alt, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('タスクを追加', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 入力モード切り替え
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => inputMode = 'student'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'student'
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '生徒',
                              style: TextStyle(
                                color: inputMode == 'student'
                                    ? Colors.white
                                    : AppColors.textMain,
                                fontWeight: FontWeight.w500,
                              ),
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
                              color: inputMode == 'custom'
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '自由記述',
                              style: TextStyle(
                                color: inputMode == 'custom'
                                    ? Colors.white
                                    : AppColors.textMain,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 生徒選択（生徒モードのみ）
                  if (inputMode == 'student') ...[
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
                                  color: selectedStudent == null
                                      ? AppColors.textSub
                                      : AppColors.textMain,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: AppColors.textSub),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 内容入力（生徒モード）
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: '内容を入力',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ] else
                    // 内容入力（自由記述モード）
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: '内容を入力',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  const SizedBox(height: 16),
                  // 期限選択
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDueDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDueDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 20, color: Colors.orange.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              DateFormat('M月d日 (E)', 'ja').format(selectedDueDate),
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textMain,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // コメント（生徒モードのみ）
                  if (inputMode == 'student') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        hintText: 'コメント（任意）',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: canSave
                    ? () async {
                        final studentNameValue = inputMode == 'student' 
                            ? (selectedStudent?['name'] as String?) 
                            : null;
                        await _addTaskForStudent(
                          studentNameValue,
                          titleController.text,
                          selectedDueDate,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('タスクを追加しました')),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('追加'),
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
  final cellMemo = _getCellMemo(date, slotIndex); // ★追加★
    
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
        return Builder(
          builder: (cellContext) {
            return GestureDetector(
              onTap: () {
                // セル全体（空白部分）をタップしたらレッスン追加
                if (!isHoliday) {
                  final renderBox = cellContext.findRenderObject() as RenderBox?;
                  final cellOffset = renderBox?.localToGlobal(Offset.zero);
                  final cellW = renderBox?.size.width ?? 0;
                  _showAddLessonDialog(
                    dayIndex: dayIndex, 
                    slotIndex: slotIndex,
                    cellOffset: cellOffset,
                    cellWidth: cellW,
                  );
                }
              },
              child: Container(
  width: cellWidth,
  height: cellHeight,
  clipBehavior: Clip.hardEdge,
  decoration: BoxDecoration(
    color: isHoliday ? Colors.grey.shade200 : Colors.white,
    border: Border(
      top: slotIndex == 0 ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
      bottom: BorderSide(color: Colors.grey.shade300),
      left: BorderSide(color: Colors.grey.shade300),
    ),
  ),
  child: Stack(
    children: [
      // レッスンリスト
      Padding(
        padding: const EdgeInsets.all(6),
        child: isHoliday && lessons.isEmpty
            ? null
            : Builder(
                builder: (cellContext) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildLessonListWithDropIndicators(lessons, dayIndex, slotIndex, cellContext),
                  );
                },
              ),
      ),
      // ★追加★ コマメモアイコン（右下）
      if (cellMemo != null)
        Positioned(
          right: 4,
          bottom: 4,
          child: _buildCellMemoIcon(date, slotIndex, cellMemo),
        ),
    ],
  ),
),
            );  // Builder
          },
        );  // GestureDetector
      },
    );  // DragTarget
  }

  // ★追加★ コマメモアイコン
Widget _buildCellMemoIcon(DateTime date, int slotIndex, Map<String, dynamic> memo) {
  final key = GlobalKey();
  
  void showMemoOverlay() {
    _hideCurrentOverlay();
    
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final overlay = Overlay.of(context);
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;
    
    const popupWidth = 200.0;
    final showOnLeft = offset.dx + popupWidth > screenWidth - 20;
    
    _currentOverlay = OverlayEntry(
      builder: (ctx) {
        double left = showOnLeft ? offset.dx - popupWidth - 8 : offset.dx + 24;
        
        return Positioned(
          top: offset.dy - 8,
          left: left,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: Container(
              width: popupWidth,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memo['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if ((memo['comment'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      memo['comment'] ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
    
    overlay.insert(_currentOverlay!);
  }
  
  return MouseRegion(
    key: key,
    cursor: SystemMouseCursors.click,
    onEnter: (_) => showMemoOverlay(),
    onExit: (_) => _hideCurrentOverlay(),
    child: GestureDetector(
      onTap: () {
        _hideCurrentOverlay();
        _showEditCellMemoDialog(date, slotIndex, memo);
      },
      child: Icon(
  Icons.info_outline,
  size: 16,
  color: Colors.grey.shade500,
),
    ),
  );
}

// ★追加★ コマメモ編集ダイアログ
void _showEditCellMemoDialog(DateTime date, int slotIndex, Map<String, dynamic> memo) {
  final titleController = TextEditingController(text: memo['title'] ?? '');
  final commentController = TextEditingController(text: memo['comment'] ?? '');
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey.shade600, size: 22),
          const SizedBox(width: 8),
          const Text('コマメモを編集', style: TextStyle(fontSize: 18)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            tooltip: '削除',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text('メモを削除'),
                  content: const Text('このメモを削除しますか？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await _deleteCellMemo(date, slotIndex);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                scaffoldMessenger.showSnackBar(const SnackBar(content: Text('メモを削除しました')));
              }
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('M月d日 (E)', 'ja').format(date)} ${_timeSlots[slotIndex]}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              decoration: InputDecoration(
                labelText: 'コメント（任意）',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル')),
        ElevatedButton(
          onPressed: () async {
            final title = titleController.text.trim();
            if (title.isEmpty) return;
            await _saveCellMemo(date, slotIndex, title, commentController.text.trim());
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            scaffoldMessenger.showSnackBar(const SnackBar(content: Text('メモを保存しました')));
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

  // レッスンリストを行間ドロップインジケーター付きで構築
  List<Widget> _buildLessonListWithDropIndicators(List<Map<String, dynamic>> lessons, int dayIndex, int slotIndex, [BuildContext? cellContext]) {
    // ドラッグ中でない場合は通常のリストを返す
    final isDraggingInSameCell = _draggingLesson != null &&
        _draggingLesson!['dayIndex'] == dayIndex &&
        _draggingLesson!['slotIndex'] == slotIndex;
    
    if (!isDraggingInSameCell) {
      return lessons.map((lesson) => _buildLessonItem(lesson, cellContext: cellContext)).toList();
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
        widgets.add(_buildLessonItem(lessons[i], cellContext: cellContext));
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

  Widget _buildLessonItem(Map<String, dynamic> lesson, {BuildContext? cellContext}) {
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
              // 生徒名部分（クリックで詳細ダイアログ）
              Flexible(
                flex: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
              const SizedBox(width: 4),
              // 講師名部分（クリックで講師選択）
              Flexible(
                flex: 3,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (cellContext != null) {
                        final renderBox = cellContext.findRenderObject() as RenderBox?;
                        final cellOffset = renderBox?.localToGlobal(Offset.zero);
                        final cellW = renderBox?.size.width ?? 0;
                        _showQuickTeacherEdit(lesson, cellOffset: cellOffset, cellWidth: cellW);
                      } else {
                        _showQuickTeacherEdit(lesson);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        teacherLastNames.join('・'),
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 部屋名部分（クリックで部屋選択）
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    if (cellContext != null) {
                      final renderBox = cellContext.findRenderObject() as RenderBox?;
                      final cellOffset = renderBox?.localToGlobal(Offset.zero);
                      final cellW = renderBox?.size.width ?? 0;
                      _showQuickRoomEdit(lesson, cellOffset: cellOffset, cellWidth: cellW);
                    } else {
                      _showQuickRoomEdit(lesson);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      lesson['room'],
                      style: const TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                      ),
                    ),
                  ),
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
          child: _buildLessonWithHover(lesson, lessonContent, note, cellContext: cellContext),
        ),
      ),
    );
  }
  
 // ホバー時のリッチなポップアップを表示
  Widget _buildLessonWithHover(Map<String, dynamic> lesson, Widget lessonContent, String note, {BuildContext? cellContext}) {
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
      final noInfoKey = GlobalKey();
      return InkWell(
        key: noInfoKey,
        onTap: () {
          final renderBox = noInfoKey.currentContext?.findRenderObject() as RenderBox?;
          final cellOffset = renderBox?.localToGlobal(Offset.zero);
          final cellWidth = renderBox?.size.width ?? 0;
          _showEditLessonDialog(lesson, cellOffset: cellOffset, cellWidth: cellWidth);
        },
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
  onEnter: (_) => showOverlay(),
  onExit: (_) => _hideCurrentOverlay(),
  child: InkWell(
    onTap: () {
      _hideCurrentOverlay();
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      final cellOffset = renderBox?.localToGlobal(Offset.zero);
      final cellWidth = renderBox?.size.width ?? 0;
      _showEditLessonDialog(lesson, cellOffset: cellOffset, cellWidth: cellWidth);
    },
    hoverColor: Colors.grey.shade100,
    borderRadius: BorderRadius.circular(4),
    child: _buildClickableLessonContent(lesson, key, cellContext: cellContext),
  ),
);
  }
  
// クリック可能なレッスン内容を構築（生徒名のみ詳細ダイアログ）
  Widget _buildClickableLessonContent(Map<String, dynamic> lesson, GlobalKey key, {BuildContext? cellContext}) {
    final course = lesson['course'] as String? ?? '通常';
    final color = _courseColors[course] ?? Colors.blue;
    final teachers = lesson['teachers'] as List<dynamic>? ?? [];
    final note = lesson['note'] as String? ?? '';
    final hasNote = note.isNotEmpty;
    
    final textColor = course == '通常' ? Colors.black87 : color;
    final courseInitial = course != '通常' && course.isNotEmpty 
        ? '(${course.substring(0, 1)})' 
        : '';
    
    final teacherLastNames = teachers
        .where((name) => name != null && name.toString().isNotEmpty)
        .map((name) => name.toString().split(' ').first)
        .where((name) => name.isNotEmpty)
        .toList();
    
    return Stack(
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
              // 生徒名部分（親のInkWellでクリック処理するので、ここではGestureDetectorを削除）
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
              // 講師名部分（クリックで講師選択）
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _hideCurrentOverlay();
                    if (cellContext != null) {
                      final renderBox = cellContext.findRenderObject() as RenderBox?;
                      final cellOffset = renderBox?.localToGlobal(Offset.zero);
                      final cellW = renderBox?.size.width ?? 0;
                      _showQuickTeacherEdit(lesson, cellOffset: cellOffset, cellWidth: cellW);
                    } else {
                      _showQuickTeacherEdit(lesson);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      teacherLastNames.join('・'),
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            // 部屋名部分（クリックで部屋選択）
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _hideCurrentOverlay();
                    if (cellContext != null) {
                      final renderBox = cellContext.findRenderObject() as RenderBox?;
                      final cellOffset = renderBox?.localToGlobal(Offset.zero);
                      final cellW = renderBox?.size.width ?? 0;
                      _showQuickRoomEdit(lesson, cellOffset: cellOffset, cellWidth: cellW);
                    } else {
                      _showQuickRoomEdit(lesson);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      lesson['room'],
                      style: const TextStyle(
                        color: AppColors.textSub,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 右上の三角マーク
        if (hasNote || _hasStudentInfo(lesson['studentName'] ?? ''))
          Positioned(
            top: 0,
            right: -6,
            child: CustomPaint(
              size: const Size(8, 8),
              painter: _NoteTrianglePainter(color: Colors.black87),
            ),
          ),
      ],
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

  
  

// _showShiftDialogメソッドを以下に完全に置き換えてください

void _showShiftDialog(DateTime date) {
    final dayKey = date.day.toString();
    final monthKey = DateFormat('yyyy-MM').format(date);
    final isMonday = date.weekday == DateTime.monday;
    final isHolidayDate = _holidays.contains(dayKey);
    
    // 全スタッフのシフト状態を管理
    Map<String, Map<String, dynamic>> staffShifts = {};
    
    // 既存のシフトデータを読み込み
    final existingShifts = _shiftData[dayKey] ?? [];
    
    // 全スタッフを初期化（showInSchedule=trueのみ）
for (var staff in _staffList.where((s) => s['showInSchedule'] != false)) {
      final staffId = staff['id'] as String;
      final staffType = staff['staffType'] as String? ?? 'fulltime';
      
      final existingShift = existingShifts.firstWhere(
        (s) => s['staffId'] == staffId,
        orElse: () => <String, dynamic>{},
      );
      
      if (existingShift.isNotEmpty) {
  staffShifts[staffId] = {
    'name': staff['name'],
    'staffType': staffType,
    'start': existingShift['start'] ?? '',
    'end': existingShift['end'] ?? '',
    'note': existingShift['note'] ?? '',
    'isWorking': existingShift['isWorking'] ?? true,  // ← 保存されたisWorkingを読み込む
  };
} else {
        if (staffType == 'fulltime') {
          staffShifts[staffId] = {
            'name': staff['name'],
            'staffType': staffType,
            'start': staff['defaultShiftStart'] ?? '9:00',
            'end': staff['defaultShiftEnd'] ?? '18:00',
            'note': '',
            'isWorking': !isMonday && !isHolidayDate,
          };
        } else {
          staffShifts[staffId] = {
            'name': staff['name'],
            'staffType': staffType,
            'start': '9:30',
            'end': '14:00',
            'note': '',
            'isWorking': false,
          };
        }
      }
    }
    
    bool isHolidayLocal = isHolidayDate;

    // ★★★ ここが重要: TextEditingControllerをshowDialogの外で作成 ★★★
    final Map<String, TextEditingController> startControllers = {};
    final Map<String, TextEditingController> endControllers = {};
    final Map<String, TextEditingController> noteControllers = {};
    
    for (var staffId in staffShifts.keys) {
      final data = staffShifts[staffId]!;
      startControllers[staffId] = TextEditingController(text: data['start'] as String? ?? '');
      endControllers[staffId] = TextEditingController(text: data['end'] as String? ?? '');
      noteControllers[staffId] = TextEditingController(text: data['note'] as String? ?? '');
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final sortedStaffIds = staffShifts.keys.toList();
          sortedStaffIds.sort((a, b) {
            // 1. 社員/パートで分ける（社員が上）
            final typeA = staffShifts[a]!['staffType'] == 'fulltime' ? 0 : 1;
            final typeB = staffShifts[b]!['staffType'] == 'fulltime' ? 0 : 1;
            if (typeA != typeB) return typeA.compareTo(typeB);
            
            // 2. 同じタイプ内ではふりがな順
            final staffA = _staffList.firstWhere((s) => s['id'] == a, orElse: () => <String, dynamic>{});
            final staffB = _staffList.firstWhere((s) => s['id'] == b, orElse: () => <String, dynamic>{});
            final kanaA = (staffA['furigana'] as String?) ?? (staffShifts[a]!['name'] as String);
            final kanaB = (staffB['furigana'] as String?) ?? (staffShifts[b]!['name'] as String);
            return kanaA.compareTo(kanaB);
          });
          
          return AlertDialog(
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
                if (isMonday || isHolidayLocal) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '休み',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            content: SizedBox(
              width: 520,
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 80, child: Text('スタッフ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700))),
                        SizedBox(width: 70, child: Text('開始', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700), textAlign: TextAlign.center)),
                        const SizedBox(width: 8),
                        SizedBox(width: 70, child: Text('終了', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700), textAlign: TextAlign.center)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700))),
                        const SizedBox(width: 8),
                        SizedBox(width: 70, child: Text('出勤', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700), textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  // スタッフリスト
                  Expanded(
                    child: ListView.builder(
                      itemCount: sortedStaffIds.length,
                      itemBuilder: (context, index) {
                        final staffId = sortedStaffIds[index];
                        final data = staffShifts[staffId]!;
                        final isWorking = data['isWorking'] as bool;
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                          ),
                          child: Row(
                            children: [
                              // スタッフ名
                              SizedBox(
                                width: 80,
                                child: Text(
                                  (data['name'] as String).split(' ').first,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isWorking ? AppColors.textMain : Colors.grey.shade500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 開始時間 or 「休み」表示
                              SizedBox(
                                width: 70,
                                child: isWorking
                                    ? TextField(
                                        controller: startControllers[staffId],
                                        enabled: !isHolidayLocal,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style: const TextStyle(fontSize: 14),
                                        textAlign: TextAlign.center,
                                      )
                                    : Center(
                                        child: Text(
                                          '休み',
                                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              // 終了時間
                              SizedBox(
                                width: 70,
                                child: isWorking
                                    ? TextField(
                                        controller: endControllers[staffId],
                                        enabled: !isHolidayLocal,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style: const TextStyle(fontSize: 14),
                                        textAlign: TextAlign.center,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(width: 8),
                              // 備考
                              Expanded(
                                child: isWorking
                                    ? TextField(
                                        controller: noteControllers[staffId],
                                        enabled: !isHolidayLocal,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                                          filled: true,
                                          fillColor: Colors.white,
                                        ),
                                        style: const TextStyle(fontSize: 14),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(width: 8),
                              // 出勤トグル
                              SizedBox(
                                width: 70,
                                child: Transform.scale(
                                  scale: 0.8,
                                  child: Switch(
                                    value: isWorking,
                                    onChanged: isHolidayLocal ? null : (value) {
                                      setDialogState(() {
                                        data['isWorking'] = value;
                                      });
                                    },
                                    activeColor: AppColors.primary,
                                    activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                                    inactiveThumbColor: Colors.grey.shade400,
                                    inactiveTrackColor: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // 「この日を休みにする」を下部に配置（月曜以外）
                  if (!isMonday) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_busy, size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text('この日を休みにする', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          const Spacer(),
                          Transform.scale(
                            scale: 0.8,
                            child: Switch(
                              value: isHolidayLocal,
                              onChanged: (value) {
                                setDialogState(() {
                                  isHolidayLocal = value;
                                  if (value) {
                                    for (var id in staffShifts.keys) {
                                      staffShifts[id]!['isWorking'] = false;
                                    }
                                  }
                                });
                              },
                              activeColor: Colors.red.shade400,
                              activeTrackColor: Colors.red.shade200,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
  // ★★★ controllerから値を取得して保存 ★★★
  // 休みのスタッフも含めて全員分保存する（isWorkingフラグ付き）
  final shiftsToSave = <Map<String, dynamic>>[];
  for (var entry in staffShifts.entries) {
    final staffId = entry.key;
    final data = entry.value;
    final isWorking = data['isWorking'] == true;
    shiftsToSave.add({
      'staffId': staffId,
      'name': data['name'],
      'staffType': data['staffType'],
      'start': isWorking ? (startControllers[staffId]?.text ?? '') : '',
      'end': isWorking ? (endControllers[staffId]?.text ?? '') : '',
      'note': isWorking ? (noteControllers[staffId]?.text ?? '') : '',
      'isWorking': isWorking,  // ← 追加：休みかどうかを保存
    });
  }
  await _saveShiftsAndHoliday(monthKey, dayKey, shiftsToSave, isHolidayLocal);
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

  void _showAddLessonDialog({int? dayIndex, int? slotIndex, Offset? cellOffset, double cellWidth = 0}) {
    if (dayIndex == null || slotIndex == null) return;
    
    // 入力モード: 'student'=生徒選択, 'custom'=イベント
    String inputMode = 'student';
    final memoTitleController = TextEditingController();
final memoCommentController = TextEditingController();
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
    
    // ダイアログの表示位置を計算
    final screenWidth = MediaQuery.of(context).size.width;
    const dialogWidth = 500.0;
    final bool showOnRight;
    double? dialogLeft;
    double? dialogRight;
    
    if (cellOffset != null) {
      final rightEdge = cellOffset.dx + cellWidth + dialogWidth + 20;
      if (rightEdge < screenWidth) {
        showOnRight = true;
        dialogLeft = cellOffset.dx + cellWidth + 8;
      } else {
        showOnRight = false;
        dialogRight = screenWidth - cellOffset.dx + 8;
      }
    } else {
      showOnRight = dayIndex <= 2;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black26,
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
          
          final bool canSave = inputMode == 'memo' 
    ? memoTitleController.text.trim().isNotEmpty
    : title.isNotEmpty;
          
          Widget dialogContent = Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 24,
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
    // 生徒選択タブ
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
              const SizedBox(width: 4),
              Text('生徒', style: TextStyle(
                fontSize: 12,
                fontWeight: inputMode == 'student' ? FontWeight.bold : FontWeight.normal,
                color: inputMode == 'student' ? AppColors.primary : AppColors.textSub,
              )),
            ],
          ),
        ),
      ),
    ),
    // イベントタブ
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
              const SizedBox(width: 4),
              Text('イベント', style: TextStyle(
                fontSize: 12,
                fontWeight: inputMode == 'custom' ? FontWeight.bold : FontWeight.normal,
                color: inputMode == 'custom' ? AppColors.primary : AppColors.textSub,
              )),
            ],
          ),
        ),
      ),
    ),
    // ★追加★ メモタブ
    Expanded(
      child: GestureDetector(
        onTap: () => setDialogState(() => inputMode = 'memo'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: inputMode == 'memo' ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: inputMode == 'memo' ? [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2),
            ] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
  Icons.info_outline,
  size: 16,
  color: inputMode == 'memo' ? AppColors.primary : AppColors.textSub,
),
              const SizedBox(width: 4),
              Text('メモ', style: TextStyle(
                fontSize: 12,
                fontWeight: inputMode == 'memo' ? FontWeight.bold : FontWeight.normal,
                color: inputMode == 'memo' ? AppColors.primary : AppColors.textSub,
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

                          if (inputMode == 'memo') ...[
  TextField(
    controller: memoTitleController,
    decoration: InputDecoration(
      hintText: 'タイトルを入力',
      prefixIcon: const Icon(Icons.info_outline, size: 20, color: Colors.grey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    onChanged: (_) => setDialogState(() {}),
  ),
  const SizedBox(height: 12),
  TextField(
    controller: memoCommentController,
    decoration: InputDecoration(
      hintText: 'コメント（任意）',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: const EdgeInsets.all(12),
    ),
    maxLines: 3,
  ),
],
                          
                         // 共通入力フォーム（メモモード以外）
if (inputMode != 'memo') ...[
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
                           ],
                          
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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setDialogState(() => newTaskDueDate = null),
            child: const Icon(Icons.close, size: 14, color: AppColors.textSub),
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
                              if (inputMode == 'memo') {
          final memoTitle = memoTitleController.text.trim();
          if (memoTitle.isEmpty) return;
          
          await _saveCellMemo(date, slotIndex, memoTitle, memoCommentController.text.trim());
          if (!dialogContext.mounted) return;
          Navigator.pop(dialogContext);
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('メモを保存しました')),
          );
          return;
        }
                                final saveDate = DateTime(date.year, date.month, date.day, 12, 0, 0);
final lessonData = {
                                  'date': Timestamp.fromDate(saveDate),
                                  'slotIndex': slotIndex,
                                  'studentName': title,
                                  'teachers': selectedTeachers,
                                  'room': selectedRoom,
                                  'course': selectedCourse,
                                  'note': '',
                                  'link': selectedStudent?['profileUrl'] ?? '',
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
await _loadLessonsForWeek(showLoading: false);
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
  inputMode == 'memo'
      ? (memoTitleController.text.trim().isEmpty ? 'タイトルを入力してください' : 'メモを追加')
      : title.isEmpty
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
          
          // セル位置が指定されている場合はPositionedで配置
          if (cellOffset != null) {
            return Stack(
              children: [
                Positioned(
                  top: 50,
                  left: dialogLeft,
                  right: dialogRight,
                  child: dialogContent,
                ),
              ],
            );
          } else {
            return Center(child: dialogContent);
          }
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
                    // 個別スタッフ（showInSchedule=trueのみ表示）
..._staffList.where((s) => s['showInSchedule'] != false).map((staff) {
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


  void _showEditLessonDialog(Map<String, dynamic> lesson, {Offset? cellOffset, double cellWidth = 0}) {
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
    
    // ダイアログの表示位置を計算
    final screenWidth = MediaQuery.of(context).size.width;
    const dialogWidth = 500.0;
    final bool showOnRight;
    double? dialogLeft;
    double? dialogRight;
    
    if (cellOffset != null) {
      // セルの右端にダイアログを表示できるかチェック
      final rightEdge = cellOffset.dx + cellWidth + dialogWidth + 20;
      if (rightEdge < screenWidth) {
        // セルのすぐ右に表示
        showOnRight = true;
        dialogLeft = cellOffset.dx + cellWidth + 8;
      } else {
        // セルのすぐ左に表示
        showOnRight = false;
        dialogRight = screenWidth - cellOffset.dx + 8;
      }
    } else {
      // フォールバック: dayIndexで判定
      showOnRight = dayIndex <= 2;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black26,
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
          
          // セル位置が指定されている場合はPositionedで配置
          Widget dialogContent = Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 24,
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
                  // 生徒名（クリックでプロフィールURLを開く）
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
                          child: MouseRegion(
  cursor: SystemMouseCursors.click,
  child: GestureDetector(
    onTap: () async {
      // _allStudentsから最新のprofileUrlを取得
      final student = _allStudents.firstWhere(
        (s) => s['name'] == studentName,
        orElse: () => <String, dynamic>{},
      );
      final link = student['profileUrl'] as String? ?? lesson['link'] as String? ?? '';
      if (link.isNotEmpty) {
        final uri = Uri.tryParse(link);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    },
                              child: Text(
                                studentName,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.blue,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // AIに相談ボタン
                        if (!isCustomEvent && studentName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                final nameParts = studentName.split(' ');
                                final lastName = nameParts.isNotEmpty ? nameParts[0] : '';
                                final firstName = nameParts.length > 1 ? nameParts[1] : '';
                                final student = _allStudents.firstWhere(
                                  (s) => s['name'] == studentName,
                                  orElse: () => <String, dynamic>{},
                                );
                                final studentInfo = {
                                  'firstName': firstName,
                                  'lastName': lastName,
                                  'age': '',
                                  'gender': '',
                                  'classroom': student['classroom'] ?? 'プラス',
                                  'diagnosis': '',
                                };
                                final studentId = student['studentId'] ?? '${student['familyUid'] ?? ''}_$firstName';
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AiChatScreen(
                                      studentId: studentId,
                                      studentName: studentName,
                                      studentInfo: studentInfo,
                                      supportPlan: null,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.smart_toy, size: 16),
                              label: const Text('AIに相談'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setDialogState(() => newTaskDueDate = null),
            child: const Icon(Icons.close, size: 14, color: AppColors.textSub),
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
await _loadLessonsForWeek(showLoading: false);
                              
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
          
          // セル位置が指定されている場合はPositionedで配置、そうでなければAlignで配置
          if (cellOffset != null) {
            return Stack(
              children: [
                Positioned(
                  top: 50,
                  left: dialogLeft,
                  right: dialogRight,
                  child: dialogContent,
                ),
              ],
            );
          } else {
            return Align(
              alignment: showOnRight ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left: showOnRight ? 0 : 40,
                  right: showOnRight ? 40 : 0,
                ),
                child: dialogContent,
              ),
            );
          }
        },
      ),
    );
  }

  void _showCourseSelectionDialog(String currentCourse, Function(String) onSelect) {
  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('内容を選択', style: TextStyle(fontSize: 18)),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _courseList.map((course) {
                final color = _courseColors[course] ?? Colors.blue;
                return ListTile(
                  leading: GestureDetector(
                    onTap: () {
                      _showColorPickerDialog(course, color, (newColor) {
                        _saveCourseColor(course, newColor);
                        setDialogState(() {});
                      });
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
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
        );
      },
    ),
  );
}

// カラーピッカーダイアログ（新規追加）
void _showColorPickerDialog(String course, Color currentColor, Function(Color) onColorSelected) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('$courseの色を選択', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 300,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colorPalette.map((color) {
            final isSelected = color.value == currentColor.value;
            return GestureDetector(
              onTap: () {
                Navigator.pop(dialogContext);
                onColorSelected(color);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.black, width: 3)
                      : Border.all(color: Colors.grey.shade300),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('キャンセル'),
        ),
      ],
    ),
  );
}

 // 講師クイック編集
  void _showQuickTeacherEdit(Map<String, dynamic> lesson, {Offset? cellOffset, double cellWidth = 0}) {
    final lessonId = lesson['id'] as String?;
    if (lessonId == null) return;
    
    List<String> selectedTeachers = List<String>.from(lesson['teachers'] ?? []);
    
    // ダイアログの表示位置を計算
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const dialogWidth = 300.0;
    const dialogHeight = 400.0; // 推定高さ
    double? dialogLeft;
    double? dialogRight;
    double dialogTop = 100;
    
    if (cellOffset != null) {
      // 横位置：セルの右端か左端にピッタリ表示
      final rightEdge = cellOffset.dx + cellWidth + dialogWidth + 8;
      if (rightEdge < screenWidth) {
        // セルの右側に表示
        dialogLeft = cellOffset.dx + cellWidth + 4;
      } else {
        // セルの左側に表示
        dialogRight = screenWidth - cellOffset.dx + 4;
      }
      
      // 縦位置：セルの上端を基準に、画面内に収まるように調整
      dialogTop = cellOffset.dy;
      if (dialogTop + dialogHeight > screenHeight - 20) {
        dialogTop = screenHeight - dialogHeight - 20;
      }
      if (dialogTop < 60) dialogTop = 60;
    }
    
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool isAllSelected = selectedTeachers.contains('全員');
          
          Widget dialogContent = Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 24,
            child: Container(
              width: dialogWidth,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      const Text('講師を変更', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(dialogContext),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 個別スタッフ（showInSchedule=trueのみ表示）
..._staffList.where((s) => s['showInSchedule'] != false).map((staff) {
                    final name = staff['name'] as String;
                    final isSelected = selectedTeachers.contains(name);
                    return CheckboxListTile(
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      value: isSelected,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      onChanged: isAllSelected ? null : (value) {
                        setDialogState(() {
                          if (value == true) {
                            selectedTeachers.add(name);
                          } else {
                            selectedTeachers.remove(name);
                          }
                        });
                      },
                      activeColor: AppColors.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  const Divider(height: 16),
                  // 「全員」オプション
                  CheckboxListTile(
                    title: const Text('全員', style: TextStyle(fontSize: 14)),
                    value: isAllSelected,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          selectedTeachers = ['全員'];
                        } else {
                          selectedTeachers.remove('全員');
                        }
                      });
                    },
                    activeColor: AppColors.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('キャンセル'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          
                          // ローカル状態を先に更新（画面が白くならないように）
                          setState(() {
                            final index = _lessons.indexWhere((l) => l['id'] == lessonId);
                            if (index != -1) {
                              _lessons[index]['teachers'] = selectedTeachers;
                            }
                          });
                          
                          // Firestoreを非同期で更新
                          try {
                            await FirebaseFirestore.instance
                                .collection('plus_lessons')
                                .doc(lessonId)
                                .update({
                              'teachers': selectedTeachers,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          } catch (e) {
                            debugPrint('Error updating teachers: $e');
                            // エラー時はリロード
                            await _loadLessonsForWeek();
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
                ],
              ),
            ),
          );
          
         // セル位置が指定されている場合はPositionedで配置
          if (cellOffset != null) {
            return Stack(
              children: [
                Positioned(
                  top: dialogTop,
                  left: dialogLeft,
                  right: dialogRight,
                  child: dialogContent,
                ),
              ],
            );
          } else {
            return Center(child: dialogContent);
          }
        },
      ),
    );
  }

 // 部屋クイック編集
  void _showQuickRoomEdit(Map<String, dynamic> lesson, {Offset? cellOffset, double cellWidth = 0}) {
    final lessonId = lesson['id'] as String?;
    if (lessonId == null) return;
    
    final currentRoom = lesson['room'] as String? ?? '';
    
    // ダイアログの表示位置を計算
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const dialogWidth = 200.0;
    const dialogHeight = 280.0; // 推定高さ
    double? dialogLeft;
    double? dialogRight;
    double dialogTop = 100;
    
    if (cellOffset != null) {
      // 横位置：セルの右端か左端にピッタリ表示
      final rightEdge = cellOffset.dx + cellWidth + dialogWidth + 8;
      if (rightEdge < screenWidth) {
        // セルの右側に表示
        dialogLeft = cellOffset.dx + cellWidth + 4;
      } else {
        // セルの左側に表示
        dialogRight = screenWidth - cellOffset.dx + 4;
      }
      
      // 縦位置：セルの上端を基準に、画面内に収まるように調整
      dialogTop = cellOffset.dy;
      if (dialogTop + dialogHeight > screenHeight - 20) {
        dialogTop = screenHeight - dialogHeight - 20;
      }
      if (dialogTop < 60) dialogTop = 60;
    }
    
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) {
        Widget dialogContent = Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 24,
          child: Container(
            width: dialogWidth,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.meeting_room, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('部屋を変更', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(dialogContext),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._roomList.map((room) {
                  final isSelected = currentRoom == room;
                  return ListTile(
                    title: Text(room, style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.primary : null,
                      fontSize: 14,
                    )),
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? AppColors.primary : Colors.grey,
                      size: 20,
                    ),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      Navigator.pop(dialogContext);
                      
                      // ローカル状態を先に更新（画面が白くならないように）
                      setState(() {
                        final index = _lessons.indexWhere((l) => l['id'] == lessonId);
                        if (index != -1) {
                          _lessons[index]['room'] = room;
                        }
                      });
                      
                      // Firestoreを非同期で更新
                      try {
                        await FirebaseFirestore.instance
                            .collection('plus_lessons')
                            .doc(lessonId)
                            .update({
                          'room': room,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      } catch (e) {
                        debugPrint('Error updating room: $e');
                        // エラー時はリロード
                        await _loadLessonsForWeek();
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        );
        
        // セル位置が指定されている場合はPositionedで配置
        if (cellOffset != null) {
          return Stack(
            children: [
              Positioned(
                top: dialogTop,
                left: dialogLeft,
                right: dialogRight,
                child: dialogContent,
              ),
            ],
          );
        } else {
          return Center(child: dialogContent);
        }
      },
    );
  }

  void _showDeleteConfirmDialog(Map<String, dynamic> lesson) {
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
              
              Navigator.pop(dialogContext);
              
              try {
                await FirebaseFirestore.instance
    .collection('plus_lessons')
    .doc(lessonId)
    .delete();

if (!mounted) return;
await _loadLessonsForWeek(showLoading: false);
                
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

  // ========================================
  // 月カレンダービュー
  // ========================================
  
  // ========================================
  // 月カレンダービュー
  // ========================================
  
  Widget _buildMonthCalendar() {
    final year = _monthViewDate.year;
    final month = _monthViewDate.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final lastDayOfMonth = DateTime(year, month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    
    // 月曜始まりで計算（日曜は除外）
    final firstWeekday = firstDayOfMonth.weekday; // 1=月曜, 7=日曜
    final startOffset = firstWeekday - 1;
    
    final today = DateTime.now();
    final days = ['月', '火', '水', '木', '金', '土']; // 日曜を除外
    
    // 日付リストを作成（日曜を除く）
    List<DateTime?> calendarDays = [];
    
    // 月初の空白
    for (int i = 0; i < startOffset; i++) {
      calendarDays.add(null);
    }
    
    // 各日付を追加（日曜日以外）
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday != DateTime.sunday) {
        calendarDays.add(date);
      }
      // 土曜日の後は次の行へ（日曜をスキップ）
      if (date.weekday == DateTime.saturday && day < daysInMonth) {
        // 次の日が日曜の場合、その次の月曜から
      }
    }
    
    // 週ごとに分割（6列）
    List<List<DateTime?>> weeks = [];
    List<DateTime?> currentWeek = [];
    
    int dayIndex = 0;
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      
      // 日曜日はスキップ
      if (date.weekday == DateTime.sunday) continue;
      
      // 週の開始位置を調整
      if (currentWeek.isEmpty && weeks.isEmpty) {
        // 最初の週の空白を追加
        for (int i = 0; i < date.weekday - 1; i++) {
          currentWeek.add(null);
        }
      }
      
      currentWeek.add(date);
      
      // 土曜日で週を終了
      if (date.weekday == DateTime.saturday) {
        weeks.add(currentWeek);
        currentWeek = [];
      }
    }
    
    // 最後の週を追加
    if (currentWeek.isNotEmpty) {
      // 残りを空白で埋める
      while (currentWeek.length < 6) {
        currentWeek.add(null);
      }
      weeks.add(currentWeek);
    }
    
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 曜日ヘッダー（日曜除く）
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: List.generate(6, (index) {
                final isSaturday = index == 5;
                return Expanded(
                  child: Center(
                    child: Text(
                      days[index],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isSaturday ? Colors.blue : AppColors.textMain,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // カレンダーグリッド
          Expanded(
            child: Column(
              children: weeks.map((week) {
                return Expanded(
                  child: Row(
                    children: week.map((date) {
                      if (date == null) {
                        return Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border(
                                right: BorderSide(color: Colors.grey.shade300),
                                bottom: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                        );
                      }
                      
                      final isToday = date.year == today.year && 
                                     date.month == today.month && 
                                     date.day == today.day;
                      final isSaturday = date.weekday == DateTime.saturday;
                      final isHoliday = _isHoliday(date);
                      
                      return Expanded(
                        child: _buildMonthCalendarCell(
                          date, date.day, isToday, isSaturday, isHoliday,
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
// _buildMonthCalendarCell メソッドを以下に置き換えてください

  // 月カレンダーのセル
  Widget _buildMonthCalendarCell(
    DateTime date, int dayNumber, bool isToday, bool isSaturday, bool isHoliday,
  ) {
    final lessons = _getLessonsForDate(date);
    
    // フィルタリング適用
    var filteredLessons = lessons;
    if (!_selectedFilters.contains('all')) {
      if (_selectedFilters.isEmpty) {
        filteredLessons = [];
      } else {
        filteredLessons = lessons.where((lesson) {
          final teachers = lesson['teachers'] as List<dynamic>? ?? [];
          if (teachers.contains('全員')) return true;
          for (final teacher in teachers) {
            if (_selectedFilters.contains(teacher)) return true;
          }
          return false;
        }).toList();
      }
    }
    
    // ホバー用のキー
    final cellKey = GlobalKey();
    
    // ホバーポップアップを表示
    void showCellOverlay() {
      if (filteredLessons.isEmpty) return;
      
      _hideCurrentOverlay();
      
      final renderBox = cellKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final overlay = Overlay.of(context);
      final offset = renderBox.localToGlobal(Offset.zero);
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      
      const popupWidth = 220.0;
      final bool showOnLeft = offset.dx + renderBox.size.width + popupWidth > screenWidth;
      final bool showAbove = offset.dy > screenHeight * 0.5;
      
      _currentOverlay = OverlayEntry(
        builder: (ctx) {
          double left;
          if (showOnLeft) {
            left = offset.dx - popupWidth - 4;
          } else {
            left = offset.dx + renderBox.size.width + 4;
          }
          if (left < 4) left = 4;
          
          final popupContent = Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: Container(
              width: popupWidth,
              constraints: BoxConstraints(maxHeight: screenHeight * 0.6),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('M月d日 (E)', 'ja').format(date),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 時間帯ごとのレッスン（タスクなし）
                      ..._timeSlots.asMap().entries.map((entry) {
                        final slotIndex = entry.key;
                        final slotLabel = entry.value;
                        final slotLessons = filteredLessons.where((l) => l['slotIndex'] == slotIndex).toList();
                        
                        if (slotLessons.isEmpty) return const SizedBox.shrink();
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slotLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...slotLessons.map((lesson) {
                              final course = lesson['course'] as String? ?? '通常';
                              final color = _courseColors[course] ?? Colors.blue;
                              final teachers = lesson['teachers'] as List<dynamic>? ?? [];
                              final room = lesson['room'] as String? ?? '';
                              final teacherNames = teachers.isNotEmpty 
                                  ? teachers.map((t) => t.toString().split(' ').first).join('・')
                                  : '';
                              
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        lesson['studentName'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (teacherNames.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        teacherNames,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                    if (room.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        room,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          );
          
          if (showAbove) {
            return Positioned(
              bottom: screenHeight - offset.dy + 4,
              left: left,
              child: popupContent,
            );
          } else {
            return Positioned(
              top: offset.dy,
              left: left,
              child: popupContent,
            );
          }
        },
      );
      
      overlay.insert(_currentOverlay!);
    }
    
    // セル全体をクリック可能に
    return GestureDetector(
      onTap: () {
        _hideCurrentOverlay();
        setState(() {
          _weekStart = _getMonday(date);
          _viewMode = 0;
        });
        _loadShiftData();
        _loadLessonsForWeek();
        _loadAllTasks();
      },
      child: MouseRegion(
        key: cellKey,
        cursor: SystemMouseCursors.click,
        onEnter: (_) => showCellOverlay(),
        onExit: (_) => _hideCurrentOverlay(),
        child: Container(
          decoration: BoxDecoration(
            color: isHoliday ? Colors.grey.shade100 : Colors.white,
            border: Border(
              right: BorderSide(color: Colors.grey.shade300),
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 日付ヘッダー（中央寄せ、タスク件数なし）
              Container(
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isToday ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday 
                            ? Colors.white 
                            : (isSaturday ? Colors.blue : AppColors.textMain),
                      ),
                    ),
                  ),
                ),
              ),
              // 4コマ（時間帯）ごとのレッスン表示 - 縦に4列
              if (!isHoliday)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4), // 左側にパディング追加
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(4, (slotIndex) {
                        final slotLessons = filteredLessons.where((l) => l['slotIndex'] == slotIndex).toList();
                        final timeLabels = ['9:30', '11:00', '14:00', '15:30'];
                        return Expanded(
                          child: Container(
                            padding: const EdgeInsets.only(right: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 時間ラベル（フォントサイズ12に）
                                Padding(
                                  padding: const EdgeInsets.only(top: 1, bottom: 1),
                                  child: Text(
                                    timeLabels[slotIndex],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                                // レッスン一覧
Expanded(
  child: slotLessons.isEmpty
      ? const SizedBox.shrink()
      : SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: slotLessons.map((lesson) {
              final course = lesson['course'] as String? ?? '通常';
              final color = _courseColors[course] ?? Colors.blue;
              final studentName = lesson['studentName'] as String? ?? '';
              final nameParts = studentName.split(' ');
              final firstName = nameParts.length > 1 ? nameParts[1] : studentName;
              
              // 講師名を取得（苗字1文字目のみ）
              final teachers = lesson['teachers'] as List<dynamic>? ?? [];
              final teacherInitials = teachers.isNotEmpty
                  ? teachers.map((t) {
                      final name = t.toString().split(' ').first;
                      return name.isNotEmpty ? name[0] : '';
                    }).join('')
                  : '';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 2,
                      height: 13,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: firstName,
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (teacherInitials.isNotEmpty)
                              TextSpan(
                                text: ' $teacherInitials',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
            ],
          ),
        ),
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

