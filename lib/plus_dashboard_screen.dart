import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'classroom_utils.dart';
import 'student_profile_dialog.dart';

/// プラスダッシュボードのコンテンツウィジェット
class PlusDashboardContent extends StatefulWidget {
  const PlusDashboardContent({super.key});

  @override
  State<PlusDashboardContent> createState() => _PlusDashboardContentState();
}

class _PlusDashboardContentState extends State<PlusDashboardContent> {
  // 曜日リスト
  final List<String> _weekDays = ['月', '火', '水', '木', '金', '土'];
  
  // 時間帯リスト
  final List<String> _timeSlots = ['9:30〜', '11:00〜', '14:00〜', '15:30〜'];

  // コース色定義
  static const Map<String, Color> _courseColors = {
    '通常': AppColors.info,
    'モンテッソーリ': AppColors.info,
    '感覚統合': AppColors.secondary,
    '言語': AppColors.aiAccent,
    '就学支援': AppColors.secondary,
    '放デイ': AppColors.primary,
    '契約': AppColors.accent,
    '体験': AppColors.success,
    '欠席': AppColors.error, // 旧データ互換用
    '欠席（加算あり）': AppColors.error,
    '策定会議': AppColors.aiAccent,
  };

  final List<String> _courseList = ['通常', 'モンテッソーリ', '感覚統合', '言語', '就学支援', '放デイ', '契約', '体験', '欠席（加算あり）', '策定会議'];

  // レギュラースケジュールデータ
  Map<String, Map<String, List<Map<String, dynamic>>>> _regularSchedule = {};
  
  // タスクデータ
  List<Map<String, dynamic>> _tasks = [];
  
  // 生徒リスト（familiesから取得）
  List<Map<String, dynamic>> _allStudents = [];
  
  // 生徒メモデータ（園訪問・就学相談・移動希望）
  List<Map<String, dynamic>> _studentNotes = [];
  
  // タブ選択状態
  String _selectedTab = 'tasks';

  // モバイル: スケジュール/タスク切り替え（0=スケジュール, 1=タスク）
  int _mobileViewIndex = 0;
  
  // ローディング状態
  bool _isLoading = true;
  
  // ホバーオーバーレイ
  OverlayEntry? _currentOverlay;
  
  void _hideCurrentOverlay() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  @override
  void dispose() {
    _hideCurrentOverlay();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadScheduleFromFirestore(),
      _loadStudentsFromFirestore(),
      _loadTasksFromFirestore(),
      _loadStudentNotesFromFirestore(),
    ]);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
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
        final familyUid = data['uid'] as String? ?? doc.id;
        final lastName = data['lastName'] as String? ?? '';
        final lastNameKana = data['lastNameKana'] as String? ?? '';
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);

        for (var child in children) {
          final firstName = child['firstName'] as String? ?? '';
          final classrooms = getChildClassrooms(child);
          final classroom = classrooms.join(', ');

          // プラスの教室のみ
          if (firstName.isNotEmpty && classrooms.any((c) => c.contains('プラス'))) {
            final studentId = child['studentId'] ?? '${familyUid}_$firstName';
            students.add({
              'studentId': studentId,
              'name': '$lastName $firstName'.trim(),
              'firstName': firstName,
              'lastName': lastName,
              'lastNameKana': lastNameKana,
              'classroom': classroom,
              'course': child['course'] ?? '',
              'meetingUrls': child['meetingUrls'] ?? [],
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
      
      _allStudents = students;
    } catch (e) {
      debugPrint('Error loading students: $e');
    }
  }

  // Firestoreからレギュラースケジュールを読み込み
  Future<void> _loadScheduleFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('plus_regular_schedule')
          .doc('data')
          .get();

      if (doc.exists) {
        final data = doc.data();
        final scheduleData = data?['schedule'] as Map<String, dynamic>? ?? {};
        
        _regularSchedule = {};
        for (var day in _weekDays) {
          _regularSchedule[day] = {};
          final dayData = scheduleData[day] as Map<String, dynamic>? ?? {};
          for (var slot in _timeSlots) {
            final slotData = dayData[slot] as List<dynamic>? ?? [];
            _regularSchedule[day]![slot] = slotData.map((item) {
              if (item is Map<String, dynamic>) {
                return item;
              }
              return <String, dynamic>{};
            }).toList();
          }
        }
      } else {
        _initializeEmptySchedule();
      }
    } catch (e) {
      debugPrint('Error loading schedule: $e');
      _initializeEmptySchedule();
    }
  }

  // タスクを読み込み
  Future<void> _loadTasksFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_tasks')
          .where('completed', isEqualTo: false)
          .get();
      
      _tasks = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? '',
          'comment': data['comment'] ?? '',
          'studentName': data['studentName'],
          'dueDate': data['dueDate'],
          'isCustom': data['isCustom'] ?? (data['studentName'] == null),
          'completed': data['completed'] ?? false,
          'createdAt': data['createdAt'],
        };
      }).toList();
      
      // 期限日順にソート（期限なしは最後）
      _tasks.sort((a, b) {
        final dateA = a['dueDate'] as Timestamp?;
        final dateB = b['dueDate'] as Timestamp?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.toDate().compareTo(dateB.toDate());
      });
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      _tasks = [];
    }
  }

  // 生徒メモを読み込み（療育プラン・園訪問・就学相談・移動希望）
  Future<void> _loadStudentNotesFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('plus_student_notes')
          .get();
      
      _studentNotes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'studentName': doc.id,
          'therapyPlan': data['therapyPlan'] ?? '',
          'schoolVisit': data['schoolVisit'] ?? '',
          'schoolConsultation': data['schoolConsultation'] ?? '',
          'moveRequest': data['moveRequest'] ?? '',
        };
      }).where((note) {
        // 何か入力があるものだけ
        return (note['therapyPlan'] as String).isNotEmpty ||
               (note['schoolVisit'] as String).isNotEmpty ||
               (note['schoolConsultation'] as String).isNotEmpty ||
               (note['moveRequest'] as String).isNotEmpty;
      }).toList();
      
      // 生徒名でソート
      _studentNotes.sort((a, b) => 
        (a['studentName'] as String).compareTo(b['studentName'] as String));
    } catch (e) {
      debugPrint('Error loading student notes: $e');
      _studentNotes = [];
    }
  }

  // 空のスケジュールを初期化
  void _initializeEmptySchedule() {
    _regularSchedule = {};
    for (var day in _weekDays) {
      _regularSchedule[day] = {};
      for (var slot in _timeSlots) {
        _regularSchedule[day]![slot] = [];
      }
    }
  }

  // Firestoreにスケジュールを保存
  Future<void> _saveScheduleToFirestore() async {
    try {
      await FirebaseFirestore.instance
          .collection('plus_regular_schedule')
          .doc('data')
          .set({
        'schedule': _regularSchedule,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving schedule: $e');
      if (mounted) {
        AppFeedback.info(context, '保存に失敗しました');
      }
    }
  }

  // タスクを追加
  Future<Map<String, dynamic>?> _addTask(String title, String comment, bool isCustom, {String? studentName, DateTime? dueDate}) async {
  try {
    final docRef = await FirebaseFirestore.instance.collection('plus_tasks').add({
      'title': title,
      'comment': comment,
      'studentName': isCustom ? null : studentName,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'isCustom': isCustom,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    // 新しいタスクオブジェクトを作成
    final newTask = {
      'id': docRef.id,
      'title': title,
      'comment': comment,
      'studentName': isCustom ? null : studentName,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'isCustom': isCustom,
      'completed': false,
    };
    
    // ローカルリストに追加
    _tasks.add(newTask);
    _tasks.sort((a, b) {
      final dateA = a['dueDate'] as Timestamp?;
      final dateB = b['dueDate'] as Timestamp?;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateA.toDate().compareTo(dateB.toDate());
    });
    
    if (mounted) {
      setState(() {});
    }
    
    return newTask;
  } catch (e) {
    debugPrint('Error adding task: $e');
    return null;
  }
}
    

  // タスクを更新（完了時は削除）
  Future<void> _updateTask(String id, {String? title, String? comment, bool? completed, DateTime? dueDate}) async {
    try {
      // 完了の場合は削除
      if (completed == true) {
        await _deleteTask(id);
        return;
      }
      
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (comment != null) updates['comment'] = comment;
      updates['dueDate'] = dueDate != null ? Timestamp.fromDate(dueDate) : null;
      
      await FirebaseFirestore.instance.collection('plus_tasks').doc(id).update(updates);
      
      setState(() {
        final index = _tasks.indexWhere((t) => t['id'] == id);
        if (index != -1) {
          if (title != null) _tasks[index]['title'] = title;
          if (comment != null) _tasks[index]['comment'] = comment;
          _tasks[index]['dueDate'] = dueDate != null ? Timestamp.fromDate(dueDate) : null;
        }
      });
    } catch (e) {
      debugPrint('Error updating task: $e');
    }
  }

  // タスクを削除
  Future<void> _deleteTask(String id) async {
    try {
      await FirebaseFirestore.instance.collection('plus_tasks').doc(id).delete();
      
      setState(() {
        _tasks.removeWhere((t) => t['id'] == id);
      });
    } catch (e) {
      debugPrint('Error deleting task: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      return _buildMobileLayout();
    }

    return Container(
      color: context.colors.cardBg,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // レギュラースケジュール（左側）- レスポンシブ
          Expanded(
            flex: 3,
            child: _buildScheduleTable(),
          ),
          const SizedBox(width: 32),
          // タブ切り替え（右側）- 固定幅
          SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タブボタン
                _buildTabButtons(),
                const SizedBox(height: 12),
                // タブコンテンツ
                Expanded(
                  child: _buildTabContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // モバイルレイアウト
  Widget _buildMobileLayout() {
    return Container(
      color: context.colors.cardBg,
      child: Column(
        children: [
          // スケジュール/タスク切り替えタブ
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.chipBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _buildMobileDashboardTab(0, Icons.grid_view, 'スケジュール'),
                  _buildMobileDashboardTab(1, Icons.task_alt, 'タスク'),
                ],
              ),
            ),
          ),
          // コンテンツ
          Expanded(
            child: _mobileViewIndex == 0
                ? _buildMobileScheduleView()
                : _buildMobileTaskView(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDashboardTab(int index, IconData icon, String label) {
    final isSelected = _mobileViewIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mobileViewIndex = index),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? AppColors.primary : context.colors.textSecondary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppColors.primary : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // モバイル: スケジュール表（フル画面、横スクロール）
  Widget _buildMobileScheduleView() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        width: 700,
        child: _buildScheduleTable(),
      ),
    );
  }

  // モバイル: タスクビュー
  Widget _buildMobileTaskView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: _buildTabButtons(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildTabContent(),
        ),
      ],
    );
  }

  // タブボタン
  Widget _buildTabButtons() {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.borderLight,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabButton('tasks', 'タスク', Icons.task_alt),
          const SizedBox(width: 3),
          _buildTabButton('therapyPlan', '療育', Icons.psychology),
          const SizedBox(width: 3),
          _buildTabButton('schoolVisit', '園訪問', Icons.school),
          const SizedBox(width: 3),
          _buildTabButton('schoolConsultation', '就学', Icons.celebration),
          const SizedBox(width: 3),
          _buildTabButton('moveRequest', '移動', Icons.swap_horiz),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tabId, String label, IconData icon) {
    final isSelected = _selectedTab == tabId;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? context.colors.cardBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: context.colors.shadow,
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? AppColors.primary : context.colors.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTextSize.caption,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // タブコンテンツ
  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 'tasks':
        return _buildTaskSection();
      case 'therapyPlan':
        return _buildTherapyPlanSection();
      case 'schoolVisit':
        return _buildSchoolVisitSection();
      case 'schoolConsultation':
        return _buildSchoolConsultationSection();
      case 'moveRequest':
        return _buildMoveRequestSection();
      default:
        return _buildTaskSection();
    }
  }

  // 療育プランセクション
  Widget _buildTherapyPlanSection() {
    final notes = _studentNotes
        .where((n) => (n['therapyPlan'] as String).isNotEmpty)
        .toList();
    
    return _buildNoteListSection(
      title: '療育プラン',
      icon: Icons.psychology,
      iconColor: AppColors.primary,
      notes: notes,
      noteKey: 'therapyPlan',
      emptyMessage: '療育プランの記録はありません',
    );
  }

  // 園訪問セクション
  Widget _buildSchoolVisitSection() {
    final notes = _studentNotes
        .where((n) => (n['schoolVisit'] as String).isNotEmpty)
        .toList();
    
    return _buildNoteListSection(
      title: '園訪問',
      icon: Icons.school,
      iconColor: AppColors.secondary,
      notes: notes,
      noteKey: 'schoolVisit',
      emptyMessage: '園訪問の記録はありません',
    );
  }

  // 就学相談セクション
  Widget _buildSchoolConsultationSection() {
    final notes = _studentNotes
        .where((n) => (n['schoolConsultation'] as String).isNotEmpty)
        .toList();
    
    return _buildNoteListSection(
      title: '就学相談',
      icon: Icons.celebration,
      iconColor: AppColors.secondary,
      notes: notes,
      noteKey: 'schoolConsultation',
      emptyMessage: '就学相談の記録はありません',
    );
  }

  // 移動希望セクション
  Widget _buildMoveRequestSection() {
    final notes = _studentNotes
        .where((n) => (n['moveRequest'] as String).isNotEmpty)
        .toList();
    
    return _buildNoteListSection(
      title: '移動希望',
      icon: Icons.swap_horiz,
      iconColor: AppColors.aiAccent,
      notes: notes,
      noteKey: 'moveRequest',
      emptyMessage: '移動希望の記録はありません',
    );
  }

  // メモリストセクション（共通）
  Widget _buildNoteListSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Map<String, dynamic>> notes,
    required String noteKey,
    required String emptyMessage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyMd,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${notes.length}件',
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // リスト（スクロール可能）
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      emptyMessage,
                      style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.body),
                    ),
                  )
                : ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (context, index) => _buildNoteItem(notes[index], noteKey, iconColor),
                  ),
          ),
          // 追加ボタン
          InkWell(
            onTap: () => _showAddNoteDialog(noteKey, iconColor),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.borderLight)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    '$titleを追加',
                    style: TextStyle(
                      fontSize: AppTextSize.body,
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
    );
  }

  // メモアイテム
  Widget _buildNoteItem(Map<String, dynamic> note, String noteKey, Color accentColor) {
    final studentName = note['studentName'] as String;
    final content = note[noteKey] as String;
    
    return InkWell(
      onTap: () => _showEditNoteDialog(studentName, noteKey, content),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.borderLight)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 生徒名
            SizedBox(
              width: 80,
              child: Text(
                studentName,
                style: const TextStyle(
                  fontSize: AppTextSize.body,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Text(
                content,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: context.colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 削除ボタン
            IconButton(
              icon: Icon(Icons.close, size: 18, color: context.colors.iconMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _showDeleteNoteConfirmDialog(studentName, noteKey),
            ),
          ],
        ),
      ),
    );
  }

  // メモ削除確認ダイアログ
  void _showDeleteNoteConfirmDialog(String studentName, String noteKey) {
    final String title;
    switch (noteKey) {
      case 'therapyPlan':
        title = '療育プラン';
        break;
      case 'schoolVisit':
        title = '園訪問';
        break;
      case 'schoolConsultation':
        title = '就学相談';
        break;
      case 'moveRequest':
        title = '移動希望';
        break;
      default:
        title = 'メモ';
    }
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('$titleを削除', style: TextStyle(fontSize: AppTextSize.titleSm)),
        content: Text('$studentNameの$titleを削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final doc = await FirebaseFirestore.instance
                    .collection('plus_student_notes')
                    .doc(studentName)
                    .get();
                
                if (doc.exists) {
                  final currentData = Map<String, dynamic>.from(doc.data() ?? {});
                  currentData[noteKey] = '';
                  
                  await FirebaseFirestore.instance
                      .collection('plus_student_notes')
                      .doc(studentName)
                      .set(currentData);
                }
                
                await _loadStudentNotesFromFirestore();
                
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) setState(() {});
              } catch (e) {
                debugPrint('Error deleting note: $e');
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // メモ追加ダイアログ
  void _showAddNoteDialog(String noteKey, Color iconColor) {
    String? selectedStudent;
    final contentController = TextEditingController();
    
    final String title;
    final String hintText;
    final IconData icon;
    
    switch (noteKey) {
      case 'therapyPlan':
        title = '療育プラン';
        hintText = '療育プランの内容を記入';
        icon = Icons.medical_services;
        break;
      case 'schoolVisit':
        title = '園訪問';
        hintText = '園訪問の記録や予定を記入';
        icon = Icons.school;
        break;
      case 'schoolConsultation':
        title = '就学相談';
        hintText = '就学相談の記録や予定を記入';
        icon = Icons.celebration;
        break;
      case 'moveRequest':
        title = '移動希望';
        hintText = '曜日や時間の変更希望を記入';
        icon = Icons.swap_horiz;
        break;
      default:
        title = 'メモ';
        hintText = 'メモを記入';
        icon = Icons.note;
    }
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text('$titleを追加', style: TextStyle(fontSize: AppTextSize.titleSm)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 生徒選択
                InkWell(
                  onTap: () {
  _showStudentSelectionDialog((student) {
    setDialogState(() => selectedStudent = student['name']);
  });
},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.borderMedium),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedStudent ?? '生徒を選択',
                            style: TextStyle(
                              fontSize: AppTextSize.bodyMd,
                              color: selectedStudent != null ? context.colors.textPrimary : context.colors.textSecondary,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 内容入力
                TextField(
                  controller: contentController,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  maxLines: 5,
                  minLines: 3,
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
                if (selectedStudent == null || contentController.text.isEmpty) {
                  return;
                }
                
                try {
                  final doc = await FirebaseFirestore.instance
                      .collection('plus_student_notes')
                      .doc(selectedStudent)
                      .get();
                  
                  final currentData = doc.exists 
                      ? Map<String, dynamic>.from(doc.data() ?? {}) 
                      : <String, dynamic>{};
                  currentData[noteKey] = contentController.text;
                  
                  await FirebaseFirestore.instance
                      .collection('plus_student_notes')
                      .doc(selectedStudent)
                      .set(currentData);
                  
                  await _loadStudentNotesFromFirestore();
                  
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) setState(() {});
                } catch (e) {
                  debugPrint('Error adding note: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }



  // メモ編集ダイアログ
  void _showEditNoteDialog(String studentName, String noteKey, String currentContent) {
    final controller = TextEditingController(text: currentContent);
    final String title;
    final String hintText;
    final IconData icon;
    final Color iconColor;
    
    switch (noteKey) {
      case 'therapyPlan':
        title = '療育プラン';
        hintText = '療育プランの内容を記入';
        icon = Icons.medical_services;
        iconColor = AppColors.primary;
        break;
      case 'schoolVisit':
        title = '園訪問';
        hintText = '園訪問の記録や予定を記入';
        icon = Icons.school;
        iconColor = AppColors.secondary;
        break;
      case 'schoolConsultation':
        title = '就学相談';
        hintText = '就学相談の記録や予定を記入';
        icon = Icons.celebration;
        iconColor = AppColors.secondary;
        break;
      case 'moveRequest':
        title = '移動希望';
        hintText = '曜日や時間の変更希望を記入';
        icon = Icons.swap_horiz;
        iconColor = AppColors.aiAccent;
        break;
      default:
        title = 'メモ';
        hintText = 'メモを記入';
        icon = Icons.note;
        iconColor = context.colors.textSecondary;
    }
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Text('$studentName - $title', style: TextStyle(fontSize: AppTextSize.titleSm)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
            ),
            maxLines: 5,
            minLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // 現在のデータを取得
                final doc = await FirebaseFirestore.instance
                    .collection('plus_student_notes')
                    .doc(studentName)
                    .get();
                
                final currentData = doc.exists 
                    ? Map<String, dynamic>.from(doc.data() ?? {}) 
                    : <String, dynamic>{};
                currentData[noteKey] = controller.text;
                
                // 保存
                await FirebaseFirestore.instance
                    .collection('plus_student_notes')
                    .doc(studentName)
                    .set(currentData);
                
                // 再読み込み
                await _loadStudentNotesFromFirestore();
                
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) setState(() {});
              } catch (e) {
                debugPrint('Error saving note: $e');
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
      ),
    );
  }

  Widget _buildScheduleTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const timeColumnWidth = 60.0;
        const headerHeight = 40.0;
        const footerHeight = 40.0;
        const borderWidth = 1.0; // 外枠の太さ
        
        // 外枠のborderの分を引いて計算
        final cellWidth = (constraints.maxWidth - timeColumnWidth - borderWidth * 2) / 6;
        final cellHeight = (constraints.maxHeight - headerHeight - footerHeight - borderWidth * 2) / 4;

        return Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.borderMedium, width: borderWidth),
            boxShadow: [
              BoxShadow(
                color: context.colors.shadow,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7), // border分小さく
            child: Column(
              children: [
                // ヘッダー行（曜日）
                _buildHeaderRow(cellWidth, timeColumnWidth, headerHeight),
                // 時間帯ごとの行
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTimeColumn(timeColumnWidth, cellHeight),
                      ...List.generate(6, (dayIndex) => _buildDayColumn(dayIndex, cellWidth, cellHeight)),
                    ],
                  ),
                ),
                // フッター行（合計人数）
                _buildFooterRow(cellWidth, timeColumnWidth, footerHeight),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeColumn(double width, double cellHeight) {
    return SizedBox(
      width: width,
      child: Column(
        children: List.generate(_timeSlots.length, (index) {
          return Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  top: index == 0 ? BorderSide(color: context.colors.borderMedium) : BorderSide.none,
                  bottom: BorderSide(color: context.colors.borderMedium),
                ),
              ),
              child: Text(
                _timeSlots[index],
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: AppTextSize.small,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayColumn(int dayIndex, double cellWidth, double cellHeight) {
    final day = _weekDays[dayIndex];
    return Expanded(
      child: Column(
        children: List.generate(_timeSlots.length, (slotIndex) {
          final timeSlot = _timeSlots[slotIndex];
          final students = _regularSchedule[day]?[timeSlot] ?? [];
          return Expanded(
            child: _buildCell(day, timeSlot, students, cellHeight, cellWidth, slotIndex),
          );
        }),
      ),
    );
  }

  Widget _buildHeaderRow(double cellWidth, double timeColumnWidth, double headerHeight) {
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
      ),
      child: Row(
        children: [
          // 時間列のヘッダー（空）
          SizedBox(
            width: timeColumnWidth,
            child: const Text(''),
          ),
          // 曜日ヘッダー
          ...List.generate(_weekDays.length, (index) {
            final day = _weekDays[index];
            final isSaturday = day == '土';
            return Expanded(
              child: Center(
                child: Text(
                  day,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyMd,
                    color: isSaturday ? AppColors.info : context.colors.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCell(String day, String timeSlot, List<Map<String, dynamic>> students, double cellHeight, double cellWidth, int slotIndex) {
    return GestureDetector(
      onTap: () {
        _showAddStudentDialog(day, timeSlot);
      },
      child: SizedBox.expand(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            border: Border(
              top: slotIndex == 0 ? BorderSide(color: context.colors.borderMedium) : BorderSide.none,
              bottom: BorderSide(color: context.colors.borderMedium),
              left: BorderSide(color: context.colors.borderMedium),
            ),
          ),
          child: students.isEmpty
              ? null
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: students.asMap().entries.map((entry) {
                      final index = entry.key;
                      final student = entry.value;
                      return _buildStudentItem(day, timeSlot, index, student);
                    }).toList(),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStudentItem(String day, String timeSlot, int index, Map<String, dynamic> student) {
    final name = student['name'] as String;
    final course = student['course'] as String? ?? '通常';
    final scheduleNote = student['note'] as String? ?? '';
    final color = _courseColors[course] ?? AppColors.info;
    
    // Firebaseからの生徒メモを取得
    final studentNote = _studentNotes.firstWhere(
      (n) => n['studentName'] == name,
      orElse: () => <String, dynamic>{},
    );
    final therapyPlan = studentNote['therapyPlan'] as String? ?? '';
    final schoolVisit = studentNote['schoolVisit'] as String? ?? '';
    final schoolConsultation = studentNote['schoolConsultation'] as String? ?? '';
    final moveRequest = studentNote['moveRequest'] as String? ?? '';
    
    // タスクがあるかどうか
final hasTask = _tasks.any((t) => t['studentName'] == name && t['completed'] != true);

// メモまたはタスクがあるかどうか
final hasAnyNote = scheduleNote.isNotEmpty || 
    therapyPlan.isNotEmpty || 
    schoolVisit.isNotEmpty || 
    schoolConsultation.isNotEmpty ||
    moveRequest.isNotEmpty ||
    hasTask;
    
    // 文字色（通常の場合は黒）
    final textColor = course == '通常' ? context.colors.textPrimary : color;
    
    // 頭文字を取得（通常の場合は空文字）
    final courseInitial = course != '通常' && course.isNotEmpty 
        ? '(${course.substring(0, 1)})' 
        : '';

    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: AppTextSize.bodyMd,
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
                    fontSize: AppTextSize.small,
                  ),
                ),
            ],
          ),
        ),
        // 右上の三角マーク（メモあり）
        if (hasAnyNote)
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(6, 6),
              painter: _NoteTrianglePainter(color: context.colors.textPrimary),
            ),
          ),
      ],
    );

    // メモがない場合はシンプルに
    if (!hasAnyNote) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showEditStudentDialog(day, timeSlot, index, student),
            onLongPress: () => _showDeleteConfirmDialog(day, timeSlot, index, student),
            child: content,
          ),
        ),
      );
    }
    
    // メモがある場合はオーバーレイで表示
    final key = GlobalKey();
    const popupWidth = 180.0;
    
    void showOverlay() {
      _hideCurrentOverlay();
      
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final overlay = Overlay.of(context);
      final offset = renderBox.localToGlobal(Offset.zero);
      
      // ポップアップ内容を構築
      final widgets = <Widget>[];
      if (therapyPlan.isNotEmpty) {
        widgets.add(const Text('【療育プラン】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(therapyPlan, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      if (schoolVisit.isNotEmpty) {
        widgets.add(const Text('【園訪問】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(schoolVisit, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      if (schoolConsultation.isNotEmpty) {
        widgets.add(const Text('【就学相談】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(schoolConsultation, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      if (moveRequest.isNotEmpty) {
        widgets.add(const Text('【移動希望】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(moveRequest, style: TextStyle(fontSize: AppTextSize.small)));
        widgets.add(const SizedBox(height: 8));
      }
      // タスク情報
final studentTasks = _tasks.where((t) => t['studentName'] == name && t['completed'] != true).toList();
if (studentTasks.isNotEmpty) {
  widgets.add(const Text('【タスク】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
  for (var task in studentTasks) {
    final title = task['title'] as String? ?? '';
    final dueDate = task['dueDate'] as Timestamp?;
    final dueDateStr = dueDate != null ? ' (${DateFormat('M/d').format(dueDate.toDate())})' : '';
    widgets.add(Text('・$title$dueDateStr', style: TextStyle(fontSize: AppTextSize.small)));
  }
  widgets.add(const SizedBox(height: 8));
}
      if (scheduleNote.isNotEmpty) {
        widgets.add(const Text('【メモ】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.small)));
        widgets.add(Text(scheduleNote, style: TextStyle(fontSize: AppTextSize.small)));
      }
      // 最後のSizedBoxを削除
      if (widgets.isNotEmpty && widgets.last is SizedBox) {
        widgets.removeLast();
      }
      
      final popupContent = Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: context.colors.cardBg,
        child: Container(
          width: popupWidth,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widgets,
          ),
        ),
      );
      
      _currentOverlay = OverlayEntry(
        builder: (ctx) {
          // 右側に表示
          final left = offset.dx + renderBox.size.width + 4;
          
          return Positioned(
            top: offset.dy,
            left: left,
            child: popupContent,
          );
        },
      );
      
      overlay.insert(_currentOverlay!);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        key: key,
        cursor: SystemMouseCursors.click,
        onEnter: (_) => showOverlay(),
        onExit: (_) => _hideCurrentOverlay(),
        child: GestureDetector(
          onTap: () {
            _hideCurrentOverlay();
            _showEditStudentDialog(day, timeSlot, index, student);
          },
          onLongPress: () {
            _hideCurrentOverlay();
            _showDeleteConfirmDialog(day, timeSlot, index, student);
          },
          child: content,
        ),
      ),
    );
  }

  Widget _buildFooterRow(double cellWidth, double timeColumnWidth, double footerHeight) {
    return Container(
      height: footerHeight,
      decoration: BoxDecoration(
        color: context.colors.tagBg,
      ),
      child: Row(
        children: [
          // 合計ラベル
          SizedBox(
            width: timeColumnWidth,
            child: const Center(
              child: Text(
                '計',
                style: TextStyle(
                  fontSize: AppTextSize.small,
                ),
              ),
            ),
          ),
          // 各曜日の合計
          ...List.generate(_weekDays.length, (index) {
            final day = _weekDays[index];
            int count = 0;
            for (var slot in _timeSlots) {
              count += _regularSchedule[day]?[slot]?.length ?? 0;
            }
            return Expanded(
              child: Center(
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: AppTextSize.body,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===== タスクセクション =====

  Widget _buildTaskSection() {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.task_alt, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  'タスク',
                  style: TextStyle(
                    fontSize: AppTextSize.bodyMd,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_tasks.length}件',
                  style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // タスク一覧（スクロール可能）
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Text(
                      'タスクはありません',
                      style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.body),
                    ),
                  )
                : ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) => _buildTaskItem(_tasks[index]),
                  ),
          ),
          // 追加ボタン
          InkWell(
            onTap: _showAddTaskDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.borderLight)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'タスクを追加',
                    style: TextStyle(
                      fontSize: AppTextSize.body,
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
    );
  }

  Widget _buildTaskItem(Map<String, dynamic> task) {
    final id = task['id'] as String;
    final title = task['title'] as String;
    final studentName = task['studentName'] as String?;
    final dueDate = task['dueDate'] as Timestamp?;
    final isCustom = studentName == null || studentName.isEmpty;
    
    // 期限切れかどうか
    final isOverdue = dueDate != null && 
        dueDate.toDate().isBefore(DateTime.now().subtract(const Duration(days: 1)));

    return InkWell(
      onTap: () => _showEditTaskDialog(task),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.borderLight)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isCustom)
              // 自由記述の場合: 内容のみ
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else ...[
              // 生徒タスクの場合: 生徒名 | 内容
              SizedBox(
                width: 80,
                child: Text(
                  studentName,
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: context.colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            // 期限
            if (dueDate != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOverdue ? AppColors.errorBg : AppColors.accent.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDueDate(dueDate.toDate()),
                  style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: isOverdue ? AppColors.error : AppColors.accent.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            // 完了ボタン
            IconButton(
              onPressed: () => _updateTask(id, completed: true),
              icon: const Icon(Icons.check_circle_outline),
              color: AppColors.success,
              tooltip: '完了',
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    if (dateOnly == today) {
      return '今日';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      return '明日';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  // タスク追加ダイアログ
  void _showAddTaskDialog() {
    String inputMode = 'student'; // 'student' or 'custom'
    Map<String, dynamic>? selectedStudent;
    final titleController = TextEditingController();
    final commentController = TextEditingController();
    DateTime? selectedDueDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSave = inputMode == 'student'
              ? (selectedStudent != null && titleController.text.isNotEmpty)
              : titleController.text.isNotEmpty;

          return AlertDialog(
            backgroundColor: context.colors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('タスクを追加', style: TextStyle(fontSize: AppTextSize.titleLg)),
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
                                  : context.colors.borderLight,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '生徒',
                              style: TextStyle(
                                color: inputMode == 'student'
                                    ? context.colors.cardBg
                                    : context.colors.textPrimary,
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
                                  : context.colors.borderLight,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(8),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '自由記述',
                              style: TextStyle(
                                color: inputMode == 'custom'
                                    ? context.colors.cardBg
                                    : context.colors.textPrimary,
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
  (student) => setDialogState(() => selectedStudent = student),
),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: context.colors.borderMedium),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 20, color: context.colors.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedStudent == null
                                    ? '生徒を選択'
                                    : selectedStudent!['name'] as String,
                                style: TextStyle(
                                  fontSize: AppTextSize.bodyLarge,
                                  color: selectedStudent == null
                                      ? context.colors.textSecondary
                                      : context.colors.textPrimary,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
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
                        initialDate: selectedDueDate ?? DateTime.now(),
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
                        border: Border.all(color: context.colors.borderMedium),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 20, color: AppColors.accent.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedDueDate != null
                                  ? '${selectedDueDate!.month}/${selectedDueDate!.day}'
                                  : '期限を設定',
                              style: TextStyle(
                                fontSize: AppTextSize.bodyLarge,
                                color: selectedDueDate != null
                                    ? context.colors.textPrimary
                                    : context.colors.textSecondary,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            GestureDetector(
                              onTap: () => setDialogState(() => selectedDueDate = null),
                              child: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
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
                        hintText: 'コメント',
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
          await _addTask(
            titleController.text, 
            inputMode == 'student' ? commentController.text : '', 
            inputMode == 'custom',
            studentName: studentNameValue,
            dueDate: selectedDueDate,
          );
          Navigator.pop(dialogContext);
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

  // タスク編集ダイアログ
  void _showEditTaskDialog(Map<String, dynamic> task) {
    final id = task['id'] as String;
    final studentName = task['studentName'] as String?;
    final isCustom = studentName == null || studentName.isEmpty;
    final titleController = TextEditingController(text: task['title']);
    final commentController = TextEditingController(text: task['comment']);
    DateTime? selectedDueDate = (task['dueDate'] as Timestamp?)?.toDate();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Dialog(
            backgroundColor: context.colors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ヘッダー
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, color: AppColors.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isCustom ? 'タスクを編集' : '$studentName のタスク',
                            style: TextStyle(fontSize: AppTextSize.titleSm, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: Icon(Icons.close, color: context.colors.textTertiary, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                  // コンテンツ
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // タスク内容
                        Text('内容', style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: titleController,
                          maxLines: null,
                          minLines: 3,
                          decoration: InputDecoration(
                            hintText: 'タスクの内容を入力...',
                            hintStyle: TextStyle(color: context.colors.iconMuted),
                            filled: true,
                            fillColor: context.colors.tagBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: context.colors.borderLight),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: context.colors.borderLight),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                          style: TextStyle(fontSize: AppTextSize.bodyMd, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        // 期限日
                        Text('期限日', style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDueDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setDialogState(() => selectedDueDate = date);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.colors.tagBg,
                              border: Border.all(color: context.colors.borderLight),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 18, color: selectedDueDate != null ? AppColors.primary : context.colors.textSecondary),
                                const SizedBox(width: 10),
                                Text(
                                  selectedDueDate != null ? DateFormat('yyyy年M月d日').format(selectedDueDate!) : '期限を設定...',
                                  style: TextStyle(
                                    fontSize: AppTextSize.bodyMd,
                                    color: selectedDueDate != null ? context.colors.textPrimary : context.colors.iconMuted,
                                  ),
                                ),
                                const Spacer(),
                                if (selectedDueDate != null)
                                  GestureDetector(
                                    onTap: () => setDialogState(() => selectedDueDate = null),
                                    child: Icon(Icons.close, size: 18, color: context.colors.iconMuted),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // コメント欄（生徒タスクのみ）
                        if (!isCustom) ...[
                          const SizedBox(height: 20),
                          Text('コメント', style: TextStyle(fontSize: AppTextSize.small, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: commentController,
                            maxLines: null,
                            minLines: 2,
                            decoration: InputDecoration(
                              hintText: 'コメントを入力...',
                              hintStyle: TextStyle(color: context.colors.iconMuted),
                              filled: true,
                              fillColor: context.colors.tagBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: context.colors.borderLight),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: context.colors.borderLight),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.all(14),
                            ),
                            style: TextStyle(fontSize: AppTextSize.bodyMd, height: 1.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // アクション
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(
                      children: [
                        // 削除ボタン
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _showDeleteTaskDialog(task);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('削除'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.errorBorder,
                          ),
                        ),
                        const Spacer(),
                        // 保存ボタン
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _updateTask(
                              id,
                              title: titleController.text,
                              comment: isCustom ? '' : commentController.text,
                              dueDate: selectedDueDate,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
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

  // タスク削除確認ダイアログ
  void _showDeleteTaskDialog(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('タスクを削除'),
        content: Text('「${task['title']}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteTask(task['id']);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

 

  String _getKanaGroup(String kana) {
    if (kana.isEmpty) return 'その他';
    final firstChar = kana.substring(0, 1);
    const kanaGroups = {
      'あ': 'あ行', 'い': 'あ行', 'う': 'あ行', 'え': 'あ行', 'お': 'あ行',
      'ア': 'あ行', 'イ': 'あ行', 'ウ': 'あ行', 'エ': 'あ行', 'オ': 'あ行',
      'か': 'か行', 'き': 'か行', 'く': 'か行', 'け': 'か行', 'こ': 'か行',
      'カ': 'か行', 'キ': 'か行', 'ク': 'か行', 'ケ': 'か行', 'コ': 'か行',
      'が': 'か行', 'ぎ': 'か行', 'ぐ': 'か行', 'げ': 'か行', 'ご': 'か行',
      'ガ': 'か行', 'ギ': 'か行', 'グ': 'か行', 'ゲ': 'か行', 'ゴ': 'か行',
      'さ': 'さ行', 'し': 'さ行', 'す': 'さ行', 'せ': 'さ行', 'そ': 'さ行',
      'サ': 'さ行', 'シ': 'さ行', 'ス': 'さ行', 'セ': 'さ行', 'ソ': 'さ行',
      'ざ': 'さ行', 'じ': 'さ行', 'ず': 'さ行', 'ぜ': 'さ行', 'ぞ': 'さ行',
      'ザ': 'さ行', 'ジ': 'さ行', 'ズ': 'さ行', 'ゼ': 'さ行', 'ゾ': 'さ行',
      'た': 'た行', 'ち': 'た行', 'つ': 'た行', 'て': 'た行', 'と': 'た行',
      'タ': 'た行', 'チ': 'た行', 'ツ': 'た行', 'テ': 'た行', 'ト': 'た行',
      'だ': 'た行', 'ぢ': 'た行', 'づ': 'た行', 'で': 'た行', 'ど': 'た行',
      'ダ': 'た行', 'ヂ': 'た行', 'ヅ': 'た行', 'デ': 'た行', 'ド': 'た行',
      'な': 'な行', 'に': 'な行', 'ぬ': 'な行', 'ね': 'な行', 'の': 'な行',
      'ナ': 'な行', 'ニ': 'な行', 'ヌ': 'な行', 'ネ': 'な行', 'ノ': 'な行',
      'は': 'は行', 'ひ': 'は行', 'ふ': 'は行', 'へ': 'は行', 'ほ': 'は行',
      'ハ': 'は行', 'ヒ': 'は行', 'フ': 'は行', 'ヘ': 'は行', 'ホ': 'は行',
      'ば': 'は行', 'び': 'は行', 'ぶ': 'は行', 'べ': 'は行', 'ぼ': 'は行',
      'バ': 'は行', 'ビ': 'は行', 'ブ': 'は行', 'ベ': 'は行', 'ボ': 'は行',
      'ぱ': 'は行', 'ぴ': 'は行', 'ぷ': 'は行', 'ぺ': 'は行', 'ぽ': 'は行',
      'パ': 'は行', 'ピ': 'は行', 'プ': 'は行', 'ペ': 'は行', 'ポ': 'は行',
      'ま': 'ま行', 'み': 'ま行', 'む': 'ま行', 'め': 'ま行', 'も': 'ま行',
      'マ': 'ま行', 'ミ': 'ま行', 'ム': 'ま行', 'メ': 'ま行', 'モ': 'ま行',
      'や': 'や行', 'ゆ': 'や行', 'よ': 'や行',
      'ヤ': 'や行', 'ユ': 'や行', 'ヨ': 'や行',
      'ら': 'ら行', 'り': 'ら行', 'る': 'ら行', 'れ': 'ら行', 'ろ': 'ら行',
      'ラ': 'ら行', 'リ': 'ら行', 'ル': 'ら行', 'レ': 'ら行', 'ロ': 'ら行',
      'わ': 'わ行', 'を': 'わ行', 'ん': 'わ行',
      'ワ': 'わ行', 'ヲ': 'わ行', 'ン': 'わ行',
    };
    return kanaGroups[firstChar] ?? 'その他';
  }

  // ===== レギュラースケジュール関連ダイアログ =====

  // 生徒追加ダイアログ
  void _showAddStudentDialog(String day, String timeSlot) {
    Map<String, dynamic>? selectedStudent;
    String selectedCourse = '通常';
    String inputMode = 'student'; // 'student' or 'custom'
    final customTitleController = TextEditingController();
    
    // 生徒メモ用コントローラー
    final therapyController = TextEditingController();
    final schoolVisitController = TextEditingController();
    final consultationController = TextEditingController();
    final moveRequestController = TextEditingController();
    
    // タスク用
    final newTaskController = TextEditingController();
    DateTime? newTaskDueDate;
    List<Map<String, dynamic>> studentTasks = [];
    
    // 最後に読み込んだ生徒名（重複読み込み防止）
    String lastLoadedStudent = '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final currentColor = _courseColors[selectedCourse] ?? AppColors.info;
          
          // タイトル（生徒名またはイベント）
          final String title;
          if (inputMode == 'student') {
            title = selectedStudent?['name'] as String? ?? '';
          } else {
            title = customTitleController.text;
          }
          
          // 生徒が選択されたらデータを読み込み
          if (inputMode == 'student' && title.isNotEmpty && title != lastLoadedStudent) {
            lastLoadedStudent = title;
            _loadStudentNotesForEdit(title).then((notes) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  therapyController.text = notes['therapyPlan'] ?? '';
                  schoolVisitController.text = notes['schoolVisit'] ?? '';
                  consultationController.text = notes['schoolConsultation'] ?? '';
                  moveRequestController.text = notes['moveRequest'] ?? '';
                });
              }
            });
            // 既存タスク読み込み
            studentTasks = _tasks.where((t) => t['studentName'] == title && t['completed'] != true).toList();
          }
          
          // 保存可能かチェック
          final bool canSave = title.isNotEmpty;
          
          return Dialog(
            backgroundColor: context.colors.cardBg,
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
                          '$day曜日 $timeSlot に追加',
                          style: const TextStyle(
                            fontSize: AppTextSize.titleLg,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                          color: context.colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'レギュラースケジュール',
                      style: TextStyle(fontSize: AppTextSize.bodyMd, color: context.colors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 入力モード切り替えタブ
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.chipBg,
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
                                  color: inputMode == 'student' ? context.colors.cardBg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: inputMode == 'student' ? [
                                    BoxShadow(color: context.colors.shadow, blurRadius: 2),
                                  ] : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person, size: 16, 
                                      color: inputMode == 'student' ? AppColors.primary : context.colors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text('生徒選択', style: TextStyle(
                                      fontSize: AppTextSize.body,
                                      fontWeight: inputMode == 'student' ? FontWeight.bold : FontWeight.normal,
                                      color: inputMode == 'student' ? AppColors.primary : context.colors.textSecondary,
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
                                  color: inputMode == 'custom' ? context.colors.cardBg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: inputMode == 'custom' ? [
                                    BoxShadow(color: context.colors.shadow, blurRadius: 2),
                                  ] : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_note, size: 16,
                                      color: inputMode == 'custom' ? AppColors.primary : context.colors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text('イベント', style: TextStyle(
                                      fontSize: AppTextSize.body,
                                      fontWeight: inputMode == 'custom' ? FontWeight.bold : FontWeight.normal,
                                      color: inputMode == 'custom' ? AppColors.primary : context.colors.textSecondary,
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
                  
                  // メインコンテンツ
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 生徒選択モード
                          if (inputMode == 'student') ...[
                            // 生徒選択
                            InkWell(
                              onTap: () => _showStudentSelectionDialog(
  (student) => setDialogState(() => selectedStudent = student),
),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: context.colors.borderMedium),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.person, size: 20, color: context.colors.textSecondary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        selectedStudent == null
                                            ? '生徒を選択'
                                            : selectedStudent!['name'] as String,
                                        style: TextStyle(
                                          fontSize: AppTextSize.bodyLarge,
                                          color: selectedStudent == null
                                              ? context.colors.textSecondary
                                              : context.colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
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
                                prefixIcon: Icon(Icons.title, size: 20, color: context.colors.textSecondary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: context.colors.borderMedium),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: context.colors.borderMedium),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                filled: true,
                                fillColor: context.colors.tagBg,
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 12),
                          ],
                          
                          // コース選択
                          InkWell(
                            onTap: () => _showCourseSelectionDialogForAdd(
                              selectedCourse,
                              (course) => setDialogState(() => selectedCourse = course),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.colors.borderMedium),
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
                                  Expanded(child: Text(selectedCourse, style: TextStyle(fontSize: AppTextSize.bodyLarge))),
                                  Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          
                          // === 生徒情報セクション（生徒モードで生徒選択済みの場合のみ） ===
                          if (inputMode == 'student' && title.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Divider(height: 1, color: context.colors.borderLight),
                            const SizedBox(height: 20),
                            
                            // タスクセクション
                            Row(
                              children: [
                                const Icon(Icons.task_alt, size: 18, color: AppColors.accent),
                                const SizedBox(width: 8),
                                const Text('タスク', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 既存タスク一覧
                            if (studentTasks.isNotEmpty) ...[
                              ...studentTasks.map((task) {
                                final isDark = Theme.of(context).brightness == Brightness.dark;
                                final taskBg = isDark
                                    ? AppColors.accent.shade900.withValues(alpha: 0.25)
                                    : AppColors.accent.shade50;
                                final taskBorder = isDark
                                    ? AppColors.accent.shade700.withValues(alpha: 0.4)
                                    : AppColors.accent.shade100;
                                return GestureDetector(
                                onTap: () => _showEditTaskDialog(task),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: taskBg,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: taskBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(task['title'] ?? '',
                                                style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textPrimary)),
                                            if (task['dueDate'] != null)
                                              Text(
                                                '期限: ${DateFormat('M/d').format((task['dueDate'] as Timestamp).toDate())}',
                                                style: TextStyle(fontSize: AppTextSize.caption, color: context.colors.textSecondary),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          await _updateTask(task['id'], completed: true);
                                          setDialogState(() {
                                            studentTasks = _tasks.where((t) => t['studentName'] == title && t['completed'] != true).toList();
                                          });
                                        },
                                        icon: const Icon(Icons.check_circle_outline, size: 20),
                                        color: AppColors.success,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: '完了',
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              }),
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
                                    style: TextStyle(fontSize: AppTextSize.body),
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
      border: Border.all(color: context.colors.borderMedium),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today, size: 16, color: newTaskDueDate != null ? AppColors.primary : context.colors.textSecondary),
        if (newTaskDueDate != null) ...[
          const SizedBox(width: 4),
          Text(
            DateFormat('M/d').format(newTaskDueDate!),
            style: TextStyle(fontSize: AppTextSize.small),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setDialogState(() => newTaskDueDate = null),
            child: Icon(Icons.close, size: 14, color: context.colors.textSecondary),
          ),
        ],
      ],
    ),
  ),
),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // タスク追加ボタン
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () async {
  final taskText = newTaskController.text.trim();
  if (taskText.isEmpty) return;
  final newTask = await _addTask(taskText, '', false, studentName: title, dueDate: newTaskDueDate);
  newTaskController.clear();
  setDialogState(() {
    newTaskDueDate = null;
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
                                        ? context.colors.borderMedium 
                                        : AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            Divider(height: 1, color: context.colors.borderLight),
                            const SizedBox(height: 20),
                            
                            // 療育プラン
                            Row(
                              children: [
                                const Icon(Icons.psychology, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                const Text('療育プラン', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: therapyController,
                              decoration: InputDecoration(
                                hintText: '療育プランを入力',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              style: TextStyle(fontSize: AppTextSize.body),
                              maxLines: 3,
                              minLines: 2,
                            ),
                            
                            const SizedBox(height: 16),
                            // 園訪問
                            Row(
                              children: [
                                const Icon(Icons.school, size: 18, color: AppColors.secondary),
                                const SizedBox(width: 8),
                                const Text('園訪問', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: schoolVisitController,
                              decoration: InputDecoration(
                                hintText: '園訪問について入力',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              style: TextStyle(fontSize: AppTextSize.body),
                              maxLines: 3,
                              minLines: 2,
                            ),
                            
                            const SizedBox(height: 16),
                            // 就学相談
                            Row(
                              children: [
                                const Icon(Icons.psychology_alt, size: 18, color: AppColors.secondary),
                                const SizedBox(width: 8),
                                const Text('就学相談', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: consultationController,
                              decoration: InputDecoration(
                                hintText: '就学相談について入力',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              style: TextStyle(fontSize: AppTextSize.body),
                              maxLines: 3,
                              minLines: 2,
                            ),
                            
                            const SizedBox(height: 16),
                            // 移動希望
                            Row(
                              children: [
                                const Icon(Icons.swap_horiz, size: 18, color: AppColors.aiAccent),
                                const SizedBox(width: 8),
                                const Text('移動希望', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: moveRequestController,
                              decoration: InputDecoration(
                                hintText: '曜日や時間の変更希望を記入',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                              style: TextStyle(fontSize: AppTextSize.body),
                              maxLines: 3,
                              minLines: 2,
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  // フッター
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: context.colors.borderLight)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
  onPressed: canSave
      ? () async {
          if (inputMode == 'student') {
            // 入力中のタスクがあれば保存
            final taskText = newTaskController.text.trim();
            if (taskText.isNotEmpty) {
              await _addTask(taskText, '', false, studentName: selectedStudent!['name'], dueDate: newTaskDueDate);
            }
            
            setState(() {
              _regularSchedule[day]?[timeSlot]?.add({
                'name': selectedStudent!['name'],
                'course': selectedCourse,
                'note': '',
              });
            });
            
            // 生徒メモも保存
            await _saveStudentNotesFromEdit(
                                    selectedStudent!['name'],
                                    therapyController.text,
                                    schoolVisitController.text,
                                    consultationController.text,
                                    moveRequestController.text,
                                  );
                                } else {
                                  // イベントモード
                                  setState(() {
                                    _regularSchedule[day]?[timeSlot]?.add({
                                      'name': customTitleController.text,
                                      'course': selectedCourse,
                                      'note': '',
                                      'isCustomEvent': true,
                                    });
                                  });
                                }
                                Navigator.pop(dialogContext);
                                await _saveScheduleToFirestore();
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: context.colors.borderLight,
                          disabledForegroundColor: context.colors.textTertiary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          canSave ? '追加' : (inputMode == 'student' ? '生徒を選択してください' : 'タイトルを入力してください'),
                          style: TextStyle(fontSize: AppTextSize.bodyLarge),
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

// ===== 共通の生徒選択ダイアログ =====
void _showStudentSelectionDialog(Function(Map<String, dynamic>) onSelect) {
  String searchText = '';

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final filteredStudents = searchText.isEmpty
            ? _allStudents
            : _allStudents.where((s) {
                final name = (s['name'] as String).toLowerCase();
                return name.contains(searchText.toLowerCase());
              }).toList();

        final groupedStudents = <String, List<Map<String, dynamic>>>{};
        for (var student in filteredStudents) {
          final kana = student['lastNameKana'] as String? ?? '';
          final group = _getKanaGroup(kana);
          groupedStudents.putIfAbsent(group, () => []);
          groupedStudents[group]!.add(student);
        }
        final sortedGroups = groupedStudents.keys.toList()..sort();

        return AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('生徒を選択', style: TextStyle(fontSize: AppTextSize.titleLg)),
          content: SizedBox(
            width: 350,
            height: 400,
            child: Column(
              children: [
                // 検索バー
                TextField(
                  decoration: InputDecoration(
                    hintText: '名前で検索...',
                    prefixIcon: Icon(Icons.search, size: 20, color: context.colors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.colors.borderMedium),
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
                      ? Center(child: Text('生徒が見つかりません', style: TextStyle(color: context.colors.textSecondary)))
                      : ListView.builder(
                          itemCount: sortedGroups.length,
                          itemBuilder: (listContext, groupIndex) {
                            final group = sortedGroups[groupIndex];
                            final studentsInGroup = groupedStudents[group]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // あ行、か行などの見出し
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  color: context.colors.chipBg,
                                  child: Text(
                                    group,
                                    style: TextStyle(
                                      fontSize: AppTextSize.body,
                                      fontWeight: FontWeight.bold,
                                      color: context.colors.textSecondary,
                                    ),
                                  ),
                                ),
                                // 生徒リスト（タップで即選択）
                                ...studentsInGroup.map((student) {
                                  return ListTile(
                                    dense: true,
                                    title: Text(student['name']),
                                    onTap: () {
                                      Navigator.pop(dialogContext);
                                      onSelect(student);
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

  // コース選択ダイアログ（追加用）
  void _showCourseSelectionDialogForAdd(String currentCourse, Function(String) onSelect) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('内容を選択', style: TextStyle(fontSize: AppTextSize.titleLg)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _courseList.map((course) {
              final color = _courseColors[course] ?? AppColors.info;
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

  // 生徒編集ダイアログ
  void _showEditStudentDialog(String day, String timeSlot, int index, Map<String, dynamic> student) {
    String selectedCourse = student['course'] as String? ?? '通常';
    final studentName = student['name'] as String;
    
    // 生徒メモ用コントローラー
    final therapyController = TextEditingController();
    final schoolVisitController = TextEditingController();
    final consultationController = TextEditingController();
    final moveRequestController = TextEditingController();
    
    // タスク用
    final newTaskController = TextEditingController();
    DateTime? newTaskDueDate;
    List<Map<String, dynamic>> studentTasks = [];
    
    // 初期データ読み込み
    bool isLoading = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // 初回のみデータ読み込み
          if (isLoading && studentName.isNotEmpty) {
            isLoading = false;
            // 生徒メモ読み込み
            _loadStudentNotesForEdit(studentName).then((notes) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  therapyController.text = notes['therapyPlan'] ?? '';
                  schoolVisitController.text = notes['schoolVisit'] ?? '';
                  consultationController.text = notes['schoolConsultation'] ?? '';
                  moveRequestController.text = notes['moveRequest'] ?? '';
                });
              }
            });
            // タスク読み込み
            studentTasks = _tasks.where((t) => t['studentName'] == studentName && t['completed'] != true).toList();
          }
          
          final currentColor = _courseColors[selectedCourse] ?? AppColors.info;
          
          return Dialog(
            backgroundColor: context.colors.cardBg,
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
                            _showDeleteConfirmDialog(day, timeSlot, index, student);
                          },
                          tooltip: '削除',
                          color: context.colors.textSecondary,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                          color: context.colors.textSecondary,
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
                              fontSize: AppTextSize.display,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        // プロファイルボタン（児童プロファイルダイアログを開く）
                        Builder(builder: (_) {
                          final matchedStudent = _allStudents.firstWhere(
                            (s) => s['name'] == studentName,
                            orElse: () => <String, dynamic>{},
                          );
                          final sid = matchedStudent['studentId'] as String?;
                          if (sid == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ElevatedButton(
                              onPressed: () => showStudentProfileDialog(
                                context,
                                studentId: sid,
                                studentName: studentName,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.secondary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('プロファイル'),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 日時
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '$day曜日　$timeSlot',
                      style: TextStyle(fontSize: AppTextSize.bodyMd, color: context.colors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: context.colors.borderLight),
                  // メインコンテンツ
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // コース選択
                          InkWell(
                            onTap: () => _showCourseSelectionDialogForEdit(
                              selectedCourse,
                              (course) => setDialogState(() => selectedCourse = course),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: context.colors.borderMedium),
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
                                  Expanded(child: Text(selectedCourse, style: TextStyle(fontSize: AppTextSize.bodyLarge))),
                                  Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          
                          // === タスクセクション ===
                          const SizedBox(height: 24),
                          Divider(height: 1, color: context.colors.borderLight),
                          const SizedBox(height: 20),
                          
                          Row(
                            children: [
                              const Icon(Icons.task_alt, size: 18, color: AppColors.accent),
                              const SizedBox(width: 8),
                              const Text('タスク', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 既存タスク一覧
                          if (studentTasks.isNotEmpty) ...[
                            ...studentTasks.map((task) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              final taskBg = isDark
                                  ? AppColors.accent.shade900.withValues(alpha: 0.25)
                                  : AppColors.accent.shade50;
                              final taskBorder = isDark
                                  ? AppColors.accent.shade700.withValues(alpha: 0.4)
                                  : AppColors.accent.shade100;
                              return GestureDetector(
                              onTap: () => _showEditTaskDialog(task),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: taskBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: taskBorder),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(task['title'] ?? '',
                                              style: TextStyle(fontSize: AppTextSize.body, color: context.colors.textPrimary)),
                                          if (task['dueDate'] != null)
                                            Text(
                                              '期限: ${DateFormat('M/d').format((task['dueDate'] as Timestamp).toDate())}',
                                              style: TextStyle(fontSize: AppTextSize.caption, color: context.colors.textSecondary),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        await _updateTask(task['id'], completed: true);
                                        setDialogState(() {
                                          studentTasks = _tasks.where((t) => t['studentName'] == studentName && t['completed'] != true).toList();
                                        });
                                      },
                                      icon: const Icon(Icons.check_circle_outline, size: 20),
                                      color: AppColors.success,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: '完了',
                                    ),
                                  ],
                                ),
                              ),
                            );
                            }),
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
                                  style: TextStyle(fontSize: AppTextSize.body),
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
      border: Border.all(color: context.colors.borderMedium),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today, size: 16, color: newTaskDueDate != null ? AppColors.primary : context.colors.textSecondary),
        if (newTaskDueDate != null) ...[
          const SizedBox(width: 4),
          Text(
            DateFormat('M/d').format(newTaskDueDate!),
            style: TextStyle(fontSize: AppTextSize.small),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setDialogState(() => newTaskDueDate = null),
            child: Icon(Icons.close, size: 14, color: context.colors.textSecondary),
          ),
        ],
      ],
    ),
  ),
),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // タスク追加ボタン
                          Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () async {
  final taskText = newTaskController.text.trim();
  if (taskText.isEmpty) return;
  final newTask = await _addTask(taskText, '', false, studentName: studentName, dueDate: newTaskDueDate);
  newTaskController.clear();
  setDialogState(() {
    newTaskDueDate = null;
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
                                      ? context.colors.borderMedium 
                                      : AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                          
                          // === 生徒情報セクション ===
                          const SizedBox(height: 24),
                          Divider(height: 1, color: context.colors.borderLight),
                          const SizedBox(height: 20),
                          
                          // 療育プラン
                          Row(
                            children: [
                              const Icon(Icons.psychology, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              const Text('療育プラン', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: therapyController,
                            decoration: InputDecoration(
                              hintText: '療育プランを入力',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: AppTextSize.body),
                            maxLines: 3,
                            minLines: 2,
                          ),
                          
                          const SizedBox(height: 16),
                          // 園訪問
                          Row(
                            children: [
                              const Icon(Icons.school, size: 18, color: AppColors.secondary),
                              const SizedBox(width: 8),
                              const Text('園訪問', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: schoolVisitController,
                            decoration: InputDecoration(
                              hintText: '園訪問について入力',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: AppTextSize.body),
                            maxLines: 3,
                            minLines: 2,
                          ),
                          
                          const SizedBox(height: 16),
                          // 就学相談
                          Row(
                            children: [
                              const Icon(Icons.psychology_alt, size: 18, color: AppColors.secondary),
                              const SizedBox(width: 8),
                              const Text('就学相談', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: consultationController,
                            decoration: InputDecoration(
                              hintText: '就学相談について入力',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: AppTextSize.body),
                            maxLines: 3,
                            minLines: 2,
                          ),
                          
                          const SizedBox(height: 16),
                          // 移動希望
                          Row(
                            children: [
                              const Icon(Icons.swap_horiz, size: 18, color: AppColors.aiAccent),
                              const SizedBox(width: 8),
                              const Text('移動希望', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyMd)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: moveRequestController,
                            decoration: InputDecoration(
                              hintText: '曜日や時間の変更希望を記入',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: AppTextSize.body),
                            maxLines: 3,
                            minLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // フッター
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: context.colors.borderLight)),
                    ),
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
    // 入力中のタスクがあれば保存
    final taskText = newTaskController.text.trim();
    if (taskText.isNotEmpty) {
      await _addTask(taskText, '', false, studentName: studentName, dueDate: newTaskDueDate);
    }
    
    // レギュラースケジュール保存
    setState(() {
      _regularSchedule[day]?[timeSlot]?[index] = {
        'name': studentName,
        'course': selectedCourse,
        'note': '',
      };
    });
    await _saveScheduleToFirestore();
    
    // 生徒メモ保存
    await _saveStudentNotesFromEdit(
      studentName,
      therapyController.text,
      schoolVisitController.text,
      consultationController.text,
      moveRequestController.text,
    );
    
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext);
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
  
  // 編集用の生徒メモ読み込み
  Future<Map<String, String>> _loadStudentNotesForEdit(String studentName) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('plus_student_notes')
          .doc(studentName)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        return {
          'therapyPlan': data['therapyPlan'] as String? ?? '',
          'schoolVisit': data['schoolVisit'] as String? ?? '',
          'schoolConsultation': data['schoolConsultation'] as String? ?? '',
          'moveRequest': data['moveRequest'] as String? ?? '',
        };
      }
    } catch (e) {
      debugPrint('Error loading student notes: $e');
    }
    return {};
  }
  
  // 編集用の生徒メモ保存
  Future<void> _saveStudentNotesFromEdit(
    String studentName,
    String therapyPlan,
    String schoolVisit,
    String schoolConsultation,
    String moveRequest,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('plus_student_notes')
          .doc(studentName)
          .set({
        'therapyPlan': therapyPlan,
        'schoolVisit': schoolVisit,
        'schoolConsultation': schoolConsultation,
        'moveRequest': moveRequest,
      }, SetOptions(merge: true));
      
      // ローカルデータも更新
      await _loadStudentNotesFromFirestore();
    } catch (e) {
      debugPrint('Error saving student notes: $e');
    }
  }

  // コース選択ダイアログ（編集用）
  void _showCourseSelectionDialogForEdit(String currentCourse, Function(String) onSelect) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('内容を選択', style: TextStyle(fontSize: AppTextSize.titleLg)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _courseList.map((course) {
              final color = _courseColors[course] ?? AppColors.info;
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
                  Navigator.pop(context);
                  onSelect(course);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // 削除確認ダイアログ
  void _showDeleteConfirmDialog(String day, String timeSlot, int index, Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('生徒を削除'),
        content: Text('${student['name']} を$day曜日 $timeSlotから削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _regularSchedule[day]?[timeSlot]?.removeAt(index);
              });
              Navigator.pop(context);
              await _saveScheduleToFirestore();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
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