import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

/// ビースマイリーダッシュボードのコンテンツウィジェット
class BeeDashboardContent extends StatefulWidget {
  const BeeDashboardContent({super.key});

  @override
  State<BeeDashboardContent> createState() => _BeeDashboardContentState();
}

class _BeeDashboardContentState extends State<BeeDashboardContent> {
  final List<String> _weekDays = ['月', '火', '水', '木', '金', '土'];

  // 教室リスト
  List<Map<String, dynamic>> _classrooms = [];
  String _selectedClassroom = '';

  // コース設定（bee_dashboard_courses）
  List<Map<String, dynamic>> _courses = [];

  // スケジュールデータ（bee_dashboard_schedule）
  // structure: { courseName: { day: [ {name, type} ] } }
  Map<String, Map<String, List<Map<String, dynamic>>>> _schedule = {};

  // タスクデータ（bee_dashboard_tasks）
  List<Map<String, dynamic>> _tasks = [];

  // 生徒リスト（familiesから取得、教室でフィルタ）
  List<Map<String, dynamic>> _allStudents = [];

  // 講師リスト（staffsから取得、教室でフィルタ）
  List<Map<String, dynamic>> _staffList = [];

  // モバイル切り替え（0=スケジュール, 1=タスク）
  int _mobileViewIndex = 0;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      debugPrint('[BeeDashboard] _loadInitialData start');
      await _loadClassrooms().timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('[BeeDashboard] _loadClassrooms timeout');
      });
      debugPrint('[BeeDashboard] classrooms loaded: ${_classrooms.length}, selected: $_selectedClassroom');
      if (_selectedClassroom.isNotEmpty) {
        await _loadDataForClassroom().timeout(const Duration(seconds: 15), onTimeout: () {
          debugPrint('[BeeDashboard] _loadDataForClassroom timeout');
        });
      }
      debugPrint('[BeeDashboard] all data loaded');
    } catch (e) {
      debugPrint('[BeeDashboard] ERROR in _loadInitialData: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClassrooms() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .get();
      _classrooms = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'color': data['color'] ?? Colors.blue.value,
        };
      }).where((c) => (c['name'] as String).isNotEmpty).toList();

      // カテゴリが「幼児教室」のもののみ表示（ビースマイリー教室）
      // プラスは別画面なのでここでは除外
      _classrooms = _classrooms.where((c) {
        final name = c['name'] as String;
        return !name.contains('プラス');
      }).toList();

      // 湘南藤沢を先、湘南台を後に
      _classrooms.sort((a, b) =>
          (b['name'] as String).compareTo(a['name'] as String));

      if (_classrooms.isNotEmpty) {
        _selectedClassroom = _classrooms.first['name'] as String;
      }
    } catch (e) {
      debugPrint('Error loading classrooms: $e');
    }
  }

  Future<void> _loadDataForClassroom() async {
    debugPrint('[BeeDashboard] _loadDataForClassroom start');
    await Future.wait([
      _loadCourses().then((_) => debugPrint('[BeeDashboard] courses loaded: ${_courses.length}')),
      _loadSchedule().then((_) => debugPrint('[BeeDashboard] schedule loaded')),
      _loadStudents().then((_) => debugPrint('[BeeDashboard] students loaded: ${_allStudents.length}')),
      _loadStaff().then((_) => debugPrint('[BeeDashboard] staff loaded: ${_staffList.length}')),
      _loadTasks().then((_) => debugPrint('[BeeDashboard] tasks loaded: ${_tasks.length}')),
    ]);
    debugPrint('[BeeDashboard] all parallel loads done');
  }


  Future<void> _loadCourses() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bee_dashboard_courses')
          .where('classroom', isEqualTo: _selectedClassroom)
          .get();

      _courses = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'classroom': data['classroom'] ?? '',
          'courseName': data['courseName'] ?? '',
          'startTime': data['startTime'] ?? '',
          'endTime': data['endTime'] ?? '',
          'capacity': data['capacity'] ?? 0,
          'order': data['order'] ?? 0,
        };
      }).toList();
      // orderでローカルソート
      _courses.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    } catch (e) {
      debugPrint('Error loading courses: $e');
      _courses = [];
    }
  }

  Future<void> _loadSchedule() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bee_dashboard_schedule')
          .doc(_selectedClassroom)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final scheduleData = data?['schedule'] as Map<String, dynamic>? ?? {};

        _schedule = {};
        for (var entry in scheduleData.entries) {
          final courseName = entry.key;
          final dayMap = entry.value as Map<String, dynamic>? ?? {};
          _schedule[courseName] = {};
          for (var day in _weekDays) {
            final dayList = dayMap[day] as List<dynamic>? ?? [];
            _schedule[courseName]![day] = dayList.map((item) {
              if (item is Map<String, dynamic>) {
                // 生徒名のスペースを統一
                if (item['type'] == 'student' && item['name'] != null) {
                  item['name'] = (item['name'] as String).replaceAll('　', ' ');
                }
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

  void _initializeEmptySchedule() {
    _schedule = {};
    for (var course in _courses) {
      final courseName = course['courseName'] as String;
      _schedule[courseName] = {};
      for (var day in _weekDays) {
        _schedule[courseName]![day] = [];
      }
    }
  }

  Future<void> _loadStudents() async {
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

          if (firstName.isNotEmpty && classroom.contains(_selectedClassroom)) {
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

  Future<void> _loadStaff() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staffs')
          .get();

      _staffList = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final classrooms = List<String>.from(data['classrooms'] ?? []);
            return {
              'id': doc.id,
              'name': data['name'] ?? '',
              'furigana': data['furigana'] ?? '',
              'classrooms': classrooms,
            };
          })
          .where((s) {
            final classrooms = s['classrooms'] as List<String>;
            final name = s['name'] as String;
            return name.isNotEmpty &&
                classrooms.any((c) => c.contains(_selectedClassroom));
          })
          .toList();

      _staffList.sort((a, b) =>
          (a['furigana'] as String).compareTo(b['furigana'] as String));
    } catch (e) {
      debugPrint('Error loading staff: $e');
    }
  }

  Future<void> _loadTasks() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bee_dashboard_tasks')
          .where('classroom', isEqualTo: _selectedClassroom)
          .get();

      _tasks = snapshot.docs
          .where((doc) => doc.data()['completed'] != true)
          .map((doc) {
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

  // Firestoreにスケジュールを保存
  Future<void> _saveScheduleToFirestore() async {
    try {
      await FirebaseFirestore.instance
          .collection('bee_dashboard_schedule')
          .doc(_selectedClassroom)
          .set({
        'schedule': _schedule,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存に失敗しました')),
        );
      }
    }
  }

  // タスク追加
  Future<Map<String, dynamic>?> _addTask(String title, String comment,
      bool isCustom,
      {String? studentName, DateTime? dueDate}) async {
    try {
      final docRef =
          await FirebaseFirestore.instance.collection('bee_dashboard_tasks').add({
        'title': title,
        'comment': comment,
        'studentName': isCustom ? null : studentName,
        'classroom': _selectedClassroom,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
        'isCustom': isCustom,
        'completed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final newTask = {
        'id': docRef.id,
        'title': title,
        'comment': comment,
        'studentName': isCustom ? null : studentName,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
        'isCustom': isCustom,
        'completed': false,
      };

      _tasks.add(newTask);
      _tasks.sort((a, b) {
        final dateA = a['dueDate'] as Timestamp?;
        final dateB = b['dueDate'] as Timestamp?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.toDate().compareTo(dateB.toDate());
      });

      if (mounted) setState(() {});
      return newTask;
    } catch (e) {
      debugPrint('Error adding task: $e');
      return null;
    }
  }

  // タスク更新
  Future<void> _updateTask(String id,
      {String? title,
      String? comment,
      bool? completed,
      DateTime? dueDate}) async {
    try {
      if (completed == true) {
        await _deleteTask(id);
        return;
      }

      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (comment != null) updates['comment'] = comment;
      updates['dueDate'] =
          dueDate != null ? Timestamp.fromDate(dueDate) : null;

      await FirebaseFirestore.instance
          .collection('bee_dashboard_tasks')
          .doc(id)
          .update(updates);

      setState(() {
        final index = _tasks.indexWhere((t) => t['id'] == id);
        if (index != -1) {
          if (title != null) _tasks[index]['title'] = title;
          if (comment != null) _tasks[index]['comment'] = comment;
          _tasks[index]['dueDate'] =
              dueDate != null ? Timestamp.fromDate(dueDate) : null;
        }
      });
    } catch (e) {
      debugPrint('Error updating task: $e');
    }
  }

  // タスク削除
  Future<void> _deleteTask(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('bee_dashboard_tasks')
          .doc(id)
          .delete();

      setState(() {
        _tasks.removeWhere((t) => t['id'] == id);
      });
    } catch (e) {
      debugPrint('Error deleting task: $e');
    }
  }

  // 教室切り替え
  Future<void> _switchClassroom(String classroomName) async {
    if (_selectedClassroom == classroomName) return;
    setState(() {
      _selectedClassroom = classroomName;
      _isLoading = true;
    });
    await _loadDataForClassroom();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_classrooms.isEmpty) {
      return const Center(
        child: Text('教室が登録されていません', style: TextStyle(color: AppColors.textSub)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      return _buildMobileLayout();
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 教室セレクタ
          _buildClassroomSelector(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // スケジュールグリッド（左側）
                Expanded(
                  flex: 3,
                  child: _buildScheduleGrid(),
                ),
                const SizedBox(width: 32),
                // タスクパネル（右側）
                SizedBox(
                  width: 400,
                  child: _buildTaskSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== 教室セレクタ =====

  Widget _buildClassroomSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _classrooms.map((classroom) {
          final name = classroom['name'] as String;
          final isSelected = name == _selectedClassroom;
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: GestureDetector(
              onTap: () => _switchClassroom(name),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.primary : AppColors.textSub,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===== スケジュールグリッド =====

  Widget _buildScheduleGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const courseColumnWidth = 130.0;
        const headerHeight = 40.0;
        const footerHeight = 40.0;
        const borderWidth = 1.0;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: borderWidth),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              children: [
                // ヘッダー行（曜日）
                _buildHeaderRow(courseColumnWidth, headerHeight),
                // コースごとの行
                Expanded(
                  child: _courses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline,
                                  size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('コースを追加してください',
                                  style: TextStyle(
                                      color: AppColors.textSub,
                                      fontSize: 14)),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _showCourseConfigDialog,
                                icon: const Icon(Icons.settings, size: 16),
                                label: const Text('コース設定'),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: _buildCourseTable(courseColumnWidth),
                        ),
                ),
                // フッター行（合計人数）
                _buildFooterRow(courseColumnWidth, footerHeight),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(double courseColumnWidth, double headerHeight) {
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: AppColors.primary,
      ),
      child: Row(
        children: [
          // コース列ヘッダー（設定ボタン）
          SizedBox(
            width: courseColumnWidth,
            child: IconButton(
              onPressed: _showCourseConfigDialog,
              icon: const Icon(Icons.settings, size: 16),
              color: Colors.white70,
              tooltip: 'コース設定',
            ),
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
                    fontSize: 15,
                    color: isSaturday ? Colors.lightBlue.shade100 : Colors.white,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCourseTable(double courseColumnWidth) {
    return Table(
      columnWidths: {
        0: FixedColumnWidth(courseColumnWidth),
        for (var i = 1; i <= 6; i++) i: const FlexColumnWidth(1),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade300),
        verticalInside: BorderSide(color: Colors.grey.shade300),
        top: BorderSide(color: Colors.grey.shade300),
        bottom: BorderSide(color: Colors.grey.shade300),
      ),
      children: _courses.map((course) {
        final courseName = course['courseName'] as String;
        final startTime = course['startTime'] as String;
        final endTime = course['endTime'] as String;
        final defaultCapacity = course['capacity'] as int;

        return TableRow(
          children: [
            // コース名セル（中央寄せ、背景色fill）
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                constraints: const BoxConstraints(minHeight: 80),
                color: Colors.grey.shade50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      courseName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMain,
                      ),
                      textAlign: TextAlign.center,
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$startTime〜$endTime',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            // 各曜日セル（講師縦書き左 | 生徒右）
            ...List.generate(6, (dayIndex) {
              final day = _weekDays[dayIndex];
              final cellEntries = _schedule[courseName]?[day] ?? [];
              final students = cellEntries.where((e) => e['type'] == 'student').toList();
              final teachers = cellEntries.where((e) => e['type'] == 'teacher').toList();
              // コマごとの定員（未設定ならコースのデフォルト）
              final cellCapacityEntry = cellEntries.firstWhere(
                (e) => e['type'] == 'capacity',
                orElse: () => <String, dynamic>{},
              );
              final cellCapacity = cellCapacityEntry.isNotEmpty
                  ? (cellCapacityEntry['value'] as int? ?? defaultCapacity)
                  : defaultCapacity;
              final remainingSeats = cellCapacity - students.length;
              final hasContent = students.isNotEmpty || teachers.isNotEmpty;
              final isDisabled = cellEntries.any((e) => e['type'] == 'disabled');

              if (isDisabled) {
                return TableCell(
                  verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _showCellEditDialog(courseName, day, cellCapacity),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 80),
                      color: Colors.grey.shade200,
                    ),
                  ),
                );
              }

              return TableCell(
                verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _showCellEditDialog(courseName, day, cellCapacity),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 講師エリア（常に罫線で区切り、セル全高）
                        Container(
                          width: 26,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: teachers.isNotEmpty
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: teachers.map((t) {
                                    final name = t['name'] as String;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Column(
                                        children: name.split('').map((char) => Text(
                                          char,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                            height: 1.15,
                                          ),
                                        )).toList(),
                                      ),
                                    );
                                  }).toList(),
                                )
                              : const SizedBox.shrink(),
                        ),
                        // 生徒名 + 残席（右側）
                        Expanded(
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(5, 6, 4, 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: students.map((s) {
                                    final name = s['name'] as String;
                                    final note = s['note'] as String? ?? '';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textMain,
                                                height: 1.4,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (note.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 1),
                                              child: Text(
                                                '($note)',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.orange.shade600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              // 残席数（右下固定）
                              if (hasContent && cellCapacity > 0)
                                Positioned(
                                  right: 4,
                                  bottom: 2,
                                  child: Text(
                                    '残席$remainingSeats',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: remainingSeats <= 0
                                          ? Colors.red.shade600
                                          : Colors.grey.shade500,
                                      fontWeight: remainingSeats <= 0
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildPersonItem(String courseName, String day,
      Map<String, dynamic> person,
      {bool isTeacher = false}) {
    final name = person['name'] as String;
    final note = person['note'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () =>
              _showEditPersonDialog(courseName, day, person),
          onLongPress: () =>
              _showDeletePersonDialog(courseName, day, person),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMain,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Text(
                    '($note)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterRow(double courseColumnWidth, double footerHeight) {
    return Container(
      height: footerHeight,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
      ),
      child: Row(
        children: [
          SizedBox(
            width: courseColumnWidth,
            child: const Center(
              child: Text('計', style: TextStyle(fontSize: 12)),
            ),
          ),
          ...List.generate(_weekDays.length, (index) {
            final day = _weekDays[index];
            int count = 0;
            for (var course in _courses) {
              final courseName = course['courseName'] as String;
              final entries = _schedule[courseName]?[day] ?? [];
              count +=
                  entries.where((e) => e['type'] == 'student').length;
            }
            return Expanded(
              child: Center(
                child: Text('$count', style: const TextStyle(fontSize: 13)),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===== セル編集ダイアログ（統合版：生徒追加・講師追加・メモ・定員） =====

  void _showCellEditDialog(String courseName, String day, int currentCapacity) {
    final cellEntries = _schedule[courseName]?[day] ?? [];
    final students = cellEntries.where((e) => e['type'] == 'student').toList();
    final teachers = cellEntries.where((e) => e['type'] == 'teacher').toList();
    final capacityController = TextEditingController(text: '$currentCapacity');

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // 最新のデータを再取得
          final latestEntries = _schedule[courseName]?[day] ?? [];
          final latestStudents = latestEntries.where((e) => e['type'] == 'student').toList();
          final latestTeachers = latestEntries.where((e) => e['type'] == 'teacher').toList();
          final isDisabled = latestEntries.any((e) => e['type'] == 'disabled');
          final remainingSeats = currentCapacity - latestStudents.length;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: EdgeInsets.zero,
            contentPadding: EdgeInsets.zero,
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                color: isDisabled ? Colors.grey.shade300 : Colors.blue.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$day曜日 $courseName',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      // レッスンなしトグル
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('レッスンなし', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: isDisabled,
                              onChanged: (val) {
                                _schedule.putIfAbsent(courseName, () => {});
                                _schedule[courseName]!.putIfAbsent(day, () => []);
                                if (val) {
                                  _schedule[courseName]![day]!.add({'type': 'disabled'});
                                } else {
                                  _schedule[courseName]![day]!.removeWhere((e) => e['type'] == 'disabled');
                                }
                                _saveScheduleToFirestore();
                                setState(() {});
                                setDialogState(() {});
                              },
                              activeColor: Colors.grey,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (!isDisabled) ...[
                    const SizedBox(height: 4),
                    Text(
                      '残席 $remainingSeats / 定員 $currentCapacity',
                      style: TextStyle(fontSize: 12, color: remainingSeats <= 0 ? Colors.red : Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
            content: isDisabled
                ? const SizedBox(
                    width: 420,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('このコマはレッスンなしに設定されています', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : SizedBox(
              width: 420,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── 講師セクション ──
                    Row(
                      children: [
                        Icon(Icons.school, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Text('講師', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            _showStaffSelectionDialog((staff) {
                              final name = staff['name'] as String;
                              _schedule.putIfAbsent(courseName, () => {});
                              _schedule[courseName]!.putIfAbsent(day, () => []);
                              _schedule[courseName]![day]!.add({
                                'name': name,
                                'type': 'teacher',
                                'note': '',
                              });
                              _saveScheduleToFirestore();
                              setState(() {});
                              setDialogState(() {});
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('追加', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    if (latestTeachers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 22, bottom: 8),
                        child: Text('未設定', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      )
                    else
                      ...latestTeachers.map((t) => _buildCellEditPersonTile(
                        t, courseName, day, isTeacher: true,
                        onChanged: () { setState(() {}); setDialogState(() {}); },
                      )),
                    const Divider(height: 20),

                    // ── 生徒セクション ──
                    Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text('生徒', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            _showStudentSelectionDialog((student) {
                              final name = _normalizeStudentName(student['name'] as String);
                              _schedule.putIfAbsent(courseName, () => {});
                              _schedule[courseName]!.putIfAbsent(day, () => []);
                              _schedule[courseName]![day]!.add({
                                'name': name,
                                'type': 'student',
                                'note': '',
                              });
                              _saveScheduleToFirestore();
                              setState(() {});
                              setDialogState(() {});
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('追加', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orange.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    if (latestStudents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 22, bottom: 8),
                        child: Text('未登録', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      )
                    else
                      ...latestStudents.map((s) => _buildCellEditPersonTile(
                        s, courseName, day, isTeacher: false,
                        onChanged: () { setState(() {}); setDialogState(() {}); },
                      )),
                    const Divider(height: 20),

                    // ── 定員設定 ──
                    Row(
                      children: [
                        Icon(Icons.event_seat, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text('定員数', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                        const Spacer(),
                        SizedBox(
                          width: 80,
                          height: 36,
                          child: TextField(
                            controller: capacityController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixText: '人',
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('閉じる'),
              ),
              ElevatedButton(
                onPressed: () {
                  // 定員保存
                  final value = int.tryParse(capacityController.text) ?? currentCapacity;
                  if (value != currentCapacity) {
                    _schedule.putIfAbsent(courseName, () => {});
                    _schedule[courseName]!.putIfAbsent(day, () => []);
                    _schedule[courseName]![day]!.removeWhere((e) => e['type'] == 'capacity');
                    _schedule[courseName]![day]!.add({
                      'type': 'capacity',
                      'value': value,
                    });
                    _saveScheduleToFirestore();
                    setState(() {});
                  }
                  Navigator.pop(dialogContext);
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

  // セル編集ダイアログ内の人物タイル
  Widget _buildCellEditPersonTile(
    Map<String, dynamic> person,
    String courseName,
    String day, {
    required bool isTeacher,
    required VoidCallback onChanged,
  }) {
    final name = person['name'] as String;
    final note = person['note'] as String? ?? '';
    final type = person['type'] as String;

    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                if (note.isNotEmpty)
                  Text(note, style: TextStyle(fontSize: 11, color: Colors.orange.shade600)),
              ],
            ),
          ),
          // メモ編集
          IconButton(
            icon: Icon(Icons.edit_note, size: 18, color: Colors.grey.shade500),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'メモ編集',
            onPressed: () {
              final noteCtrl = TextEditingController(text: note);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('$name のメモ', style: const TextStyle(fontSize: 14)),
                  content: TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      hintText: 'メモを入力',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                    ElevatedButton(
                      onPressed: () {
                        final entries = _schedule[courseName]?[day] ?? [];
                        final idx = entries.indexWhere((e) => e['name'] == name && e['type'] == type);
                        if (idx != -1) {
                          entries[idx]['note'] = noteCtrl.text;
                          _saveScheduleToFirestore();
                        }
                        Navigator.pop(ctx);
                        onChanged();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
            },
          ),
          // 削除
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.red.shade300),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '削除',
            onPressed: () {
              _schedule[courseName]?[day]?.removeWhere(
                (e) => e['name'] == name && e['type'] == type,
              );
              _saveScheduleToFirestore();
              onChanged();
            },
          ),
        ],
      ),
    );
  }

  // 生徒名のスペースを統一（苗字と名前の間に半角スペース）
  String _normalizeStudentName(String name) {
    // すでにスペースありならそのまま
    if (name.contains(' ') || name.contains('　')) {
      return name.replaceAll('　', ' '); // 全角→半角
    }
    return name;
  }

  // ===== 人物追加ダイアログ（講師/生徒切替あり） =====

  void _showAddPersonDialog(String courseName, String day) {
    String inputMode = 'student'; // 'student' or 'teacher'
    Map<String, dynamic>? selectedPerson;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSave = selectedPerson != null;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Text('$day曜日 $courseName に追加',
                style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 生徒/講師切り替え
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              inputMode = 'student';
                              selectedPerson = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'student'
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(8)),
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
                          onTap: () {
                            setDialogState(() {
                              inputMode = 'teacher';
                              selectedPerson = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'teacher'
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(8)),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '講師',
                              style: TextStyle(
                                color: inputMode == 'teacher'
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
                  // 選択ボタン
                  InkWell(
                    onTap: () {
                      if (inputMode == 'student') {
                        _showStudentSelectionDialog((student) {
                          setDialogState(
                              () => selectedPerson = student);
                        });
                      } else {
                        _showStaffSelectionDialog((staff) {
                          setDialogState(
                              () => selectedPerson = staff);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            inputMode == 'student'
                                ? Icons.person
                                : Icons.school,
                            size: 20,
                            color: AppColors.textSub,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedPerson == null
                                  ? (inputMode == 'student'
                                      ? '生徒を選択'
                                      : '講師を選択')
                                  : selectedPerson!['name'] as String,
                              style: TextStyle(
                                fontSize: 14,
                                color: selectedPerson != null
                                    ? AppColors.textMain
                                    : AppColors.textSub,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down,
                              color: AppColors.textSub),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // メモ
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      hintText: 'メモ（任意）',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
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
              ElevatedButton(
                onPressed: canSave
                    ? () {
                        final newEntry = {
                          'name': selectedPerson!['name'] as String,
                          'type': inputMode,
                          'note': noteController.text,
                        };
                        _schedule.putIfAbsent(courseName, () => {});
                        _schedule[courseName]!
                            .putIfAbsent(day, () => []);
                        _schedule[courseName]![day]!.add(newEntry);

                        _saveScheduleToFirestore();
                        Navigator.pop(dialogContext);
                        setState(() {});
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

  // 人物編集ダイアログ
  void _showEditPersonDialog(
      String courseName, String day, Map<String, dynamic> person) {
    final noteController =
        TextEditingController(text: person['note'] as String? ?? '');
    final name = person['name'] as String;
    final type = person['type'] as String? ?? 'student';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(name, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: noteController,
            decoration: InputDecoration(
              hintText: 'メモ',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showDeletePersonDialog(courseName, day, person);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              final entries = _schedule[courseName]?[day] ?? [];
              final index = entries.indexWhere(
                  (e) => e['name'] == name && e['type'] == type);
              if (index != -1) {
                entries[index]['note'] = noteController.text;
                _saveScheduleToFirestore();
              }
              Navigator.pop(dialogContext);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 人物削除確認
  void _showDeletePersonDialog(
      String courseName, String day, Map<String, dynamic> person) {
    final name = person['name'] as String;
    final type = person['type'] as String? ?? 'student';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('削除確認', style: TextStyle(fontSize: 16)),
        content: Text('$nameを$day曜日の$courseNameから削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              final entries = _schedule[courseName]?[day] ?? [];
              entries.removeWhere(
                  (e) => e['name'] == name && e['type'] == type);
              _saveScheduleToFirestore();
              Navigator.pop(dialogContext);
              setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // ===== 生徒選択ダイアログ =====

  void _showStudentSelectionDialog(
      Function(Map<String, dynamic>) onSelect) {
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
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: const Text('生徒を選択', style: TextStyle(fontSize: 18)),
            content: SizedBox(
              width: 350,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: '名前で検索...',
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setDialogState(() => searchText = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredStudents.isEmpty
                        ? const Center(
                            child: Text('生徒が見つかりません',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: sortedGroups.length,
                            itemBuilder: (listContext, groupIndex) {
                              final group = sortedGroups[groupIndex];
                              final studentsInGroup =
                                  groupedStudents[group]!;
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    color: Colors.grey.shade100,
                                    child: Text(
                                      group,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  ...studentsInGroup.map((student) {
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                          student['name'] as String),
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

  // ===== 講師選択ダイアログ =====

  void _showStaffSelectionDialog(
      Function(Map<String, dynamic>) onSelect) {
    String searchText = '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final filteredStaff = searchText.isEmpty
              ? _staffList
              : _staffList.where((s) {
                  final name = (s['name'] as String).toLowerCase();
                  return name.contains(searchText.toLowerCase());
                }).toList();

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: const Text('講師を選択', style: TextStyle(fontSize: 18)),
            content: SizedBox(
              width: 350,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: '名前で検索...',
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setDialogState(() => searchText = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredStaff.isEmpty
                        ? const Center(
                            child: Text('講師が見つかりません',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: filteredStaff.length,
                            itemBuilder: (context, index) {
                              final staff = filteredStaff[index];
                              return ListTile(
                                dense: true,
                                title:
                                    Text(staff['name'] as String),
                                onTap: () {
                                  Navigator.pop(dialogContext);
                                  onSelect(staff);
                                },
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

  // ===== コース設定ダイアログ =====

  void _showCourseConfigDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                const Icon(Icons.settings, size: 20),
                const SizedBox(width: 8),
                Text('$_selectedClassroom コース設定',
                    style: const TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  Expanded(
                    child: _courses.isEmpty
                        ? const Center(
                            child: Text('コースがありません',
                                style: TextStyle(color: Colors.grey)))
                        : ReorderableListView.builder(
                            itemCount: _courses.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (newIndex > oldIndex) newIndex--;
                              final item =
                                  _courses.removeAt(oldIndex);
                              _courses.insert(newIndex, item);
                              // order更新
                              for (var i = 0;
                                  i < _courses.length;
                                  i++) {
                                _courses[i]['order'] = i;
                                await FirebaseFirestore.instance
                                    .collection(
                                        'bee_dashboard_courses')
                                    .doc(_courses[i]['id'] as String)
                                    .update({'order': i});
                              }
                              setDialogState(() {});
                              setState(() {});
                            },
                            itemBuilder: (context, index) {
                              final course = _courses[index];
                              return ListTile(
                                key: ValueKey(course['id']),
                                title: Text(
                                    course['courseName'] as String,
                                    style: const TextStyle(
                                        fontSize: 14)),
                                subtitle: Text(
                                    '${course['startTime']}〜${course['endTime']}',
                                    style: const TextStyle(
                                        fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 18),
                                      onPressed: () =>
                                          _showEditCourseDialog(
                                              course, () {
                                        setDialogState(() {});
                                      }),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete,
                                          size: 18,
                                          color: AppColors.error),
                                      onPressed: () =>
                                          _showDeleteCourseDialog(
                                              course, () {
                                        setDialogState(() {});
                                      }),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddCourseDialog(() {
                        setDialogState(() {});
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('コースを追加'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
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

  void _showAddCourseDialog(VoidCallback onComplete) {
    final nameController = TextEditingController();
    final startTimeController = TextEditingController();
    final endTimeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title:
            const Text('コースを追加', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'コース名',
                  hintText: '例: プリスクール',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startTimeController,
                      decoration: InputDecoration(
                        labelText: '開始時間',
                        hintText: '10:00',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('〜'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: endTimeController,
                      decoration: InputDecoration(
                        labelText: '終了時間',
                        hintText: '13:00',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
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
              if (nameController.text.isEmpty) return;

              final newOrder = _courses.isEmpty
                  ? 0
                  : (_courses.last['order'] as int) + 1;

              final docRef = await FirebaseFirestore.instance
                  .collection('bee_dashboard_courses')
                  .add({
                'classroom': _selectedClassroom,
                'courseName': nameController.text,
                'startTime': startTimeController.text,
                'endTime': endTimeController.text,
                'capacity': 0,
                'order': newOrder,
              });

              _courses.add({
                'id': docRef.id,
                'classroom': _selectedClassroom,
                'courseName': nameController.text,
                'startTime': startTimeController.text,
                'endTime': endTimeController.text,
                'capacity': 0,
                'order': newOrder,
              });

              // スケジュールに空の枠を追加
              _schedule[nameController.text] = {};
              for (var day in _weekDays) {
                _schedule[nameController.text]![day] = [];
              }

              Navigator.pop(dialogContext);
              onComplete();
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  void _showEditCourseDialog(
      Map<String, dynamic> course, VoidCallback onComplete) {
    final nameController =
        TextEditingController(text: course['courseName'] as String);
    final startTimeController =
        TextEditingController(text: course['startTime'] as String);
    final endTimeController =
        TextEditingController(text: course['endTime'] as String);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title:
            const Text('コースを編集', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'コース名',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startTimeController,
                      decoration: InputDecoration(
                        labelText: '開始時間',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('〜'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: endTimeController,
                      decoration: InputDecoration(
                        labelText: '終了時間',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
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
              if (nameController.text.isEmpty) return;

              final id = course['id'] as String;
              final oldName = course['courseName'] as String;
              final newName = nameController.text;

              await FirebaseFirestore.instance
                  .collection('bee_dashboard_courses')
                  .doc(id)
                  .update({
                'courseName': newName,
                'startTime': startTimeController.text,
                'endTime': endTimeController.text,
              });

              // ローカル更新
              final index =
                  _courses.indexWhere((c) => c['id'] == id);
              if (index != -1) {
                _courses[index]['courseName'] = newName;
                _courses[index]['startTime'] =
                    startTimeController.text;
                _courses[index]['endTime'] =
                    endTimeController.text;
              }

              // コース名変更時はスケジュールのキーも更新
              if (oldName != newName &&
                  _schedule.containsKey(oldName)) {
                _schedule[newName] = _schedule.remove(oldName)!;
                await _saveScheduleToFirestore();
              }

              Navigator.pop(dialogContext);
              onComplete();
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCourseDialog(
      Map<String, dynamic> course, VoidCallback onComplete) {
    final courseName = course['courseName'] as String;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('コースを削除', style: TextStyle(fontSize: 16)),
        content: Text('$courseNameを削除しますか？\n配置データも削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              final id = course['id'] as String;
              await FirebaseFirestore.instance
                  .collection('bee_dashboard_courses')
                  .doc(id)
                  .delete();

              _courses.removeWhere((c) => c['id'] == id);
              _schedule.remove(courseName);
              await _saveScheduleToFirestore();

              Navigator.pop(dialogContext);
              onComplete();
              setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // ===== タスクセクション =====

  Widget _buildTaskSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ヘッダー
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.task_alt,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text(
                  'タスク',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_tasks.length}件',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          // タスク一覧
          Expanded(
            child: _tasks.isEmpty
                ? const Center(
                    child: Text('タスクはありません',
                        style: TextStyle(
                            color: AppColors.textSub, fontSize: 13)),
                  )
                : ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) =>
                        _buildTaskItem(_tasks[index]),
                  ),
          ),
          // 追加ボタン
          InkWell(
            onTap: _showAddTaskDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'タスクを追加',
                    style: TextStyle(
                      fontSize: 13,
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

    final isOverdue = dueDate != null &&
        dueDate
            .toDate()
            .isBefore(DateTime.now().subtract(const Duration(days: 1)));

    return InkWell(
      onTap: () => _showEditTaskDialog(task),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isCustom)
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else ...[
              SizedBox(
                width: 80,
                child: Text(
                  studentName,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMain),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (dueDate != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? Colors.red.shade50
                      : AppColors.accent.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDueDate(dueDate.toDate()),
                  style: TextStyle(
                    fontSize: 11,
                    color: isOverdue
                        ? Colors.red.shade700
                        : AppColors.accent.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            IconButton(
              onPressed: () => _updateTask(id, completed: true),
              icon: const Icon(Icons.check_circle_outline),
              color: Colors.green,
              tooltip: '完了',
              iconSize: 24,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
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
    String inputMode = 'student';
    Map<String, dynamic>? selectedStudent;
    final titleController = TextEditingController();
    final commentController = TextEditingController();
    DateTime? selectedDueDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final canSave = inputMode == 'student'
              ? (selectedStudent != null &&
                  titleController.text.isNotEmpty)
              : titleController.text.isNotEmpty;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: const Text('タスクを追加',
                style: TextStyle(fontSize: 18)),
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
                          onTap: () => setDialogState(
                              () => inputMode = 'student'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'student'
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius:
                                  const BorderRadius.horizontal(
                                      left: Radius.circular(8)),
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
                          onTap: () => setDialogState(
                              () => inputMode = 'custom'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10),
                            decoration: BoxDecoration(
                              color: inputMode == 'custom'
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              borderRadius:
                                  const BorderRadius.horizontal(
                                      right: Radius.circular(8)),
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
                  if (inputMode == 'student') ...[
                    InkWell(
                      onTap: () => _showStudentSelectionDialog(
                        (student) => setDialogState(
                            () => selectedStudent = student),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                size: 20,
                                color: AppColors.textSub),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedStudent == null
                                    ? '生徒を選択'
                                    : selectedStudent!['name']
                                        as String,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: selectedStudent == null
                                      ? AppColors.textSub
                                      : AppColors.textMain,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down,
                                color: AppColors.textSub),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      hintText: '内容を入力',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  // 期限選択
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate:
                            selectedDueDate ?? DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 30)),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(
                            () => selectedDueDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 20,
                              color: AppColors.accent.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedDueDate != null
                                  ? '${selectedDueDate!.month}/${selectedDueDate!.day}'
                                  : '期限を設定',
                              style: TextStyle(
                                fontSize: 15,
                                color: selectedDueDate != null
                                    ? AppColors.textMain
                                    : AppColors.textSub,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            GestureDetector(
                              onTap: () => setDialogState(
                                  () => selectedDueDate = null),
                              child: const Icon(Icons.close,
                                  size: 18,
                                  color: AppColors.textSub),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (inputMode == 'student') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        hintText: 'コメント',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
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
                        final studentNameValue =
                            inputMode == 'student'
                                ? (selectedStudent?['name']
                                    as String?)
                                : null;
                        await _addTask(
                          titleController.text,
                          inputMode == 'student'
                              ? commentController.text
                              : '',
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
    final commentController =
        TextEditingController(text: task['comment']);
    DateTime? selectedDueDate =
        (task['dueDate'] as Timestamp?)?.toDate();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            title: Text(
              isCustom ? 'タスクを編集' : '$studentName のタスクを編集',
              style: const TextStyle(fontSize: 18),
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: '内容',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate:
                            selectedDueDate ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(
                            const Duration(days: 365)),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setDialogState(
                            () => selectedDueDate = date);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 20, color: AppColors.textSub),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedDueDate != null
                                  ? '${selectedDueDate!.month}/${selectedDueDate!.day}'
                                  : '期限を設定',
                              style: TextStyle(
                                fontSize: 15,
                                color: selectedDueDate != null
                                    ? AppColors.textMain
                                    : AppColors.textSub,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            GestureDetector(
                              onTap: () => setDialogState(
                                  () => selectedDueDate = null),
                              child: const Icon(Icons.close,
                                  size: 18,
                                  color: AppColors.textSub),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!isCustom) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        labelText: 'コメント',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
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
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _updateTask(
                    id,
                    title: titleController.text,
                    comment:
                        isCustom ? '' : commentController.text,
                    dueDate: selectedDueDate,
                  );
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

  // ===== モバイルレイアウト =====

  Widget _buildMobileLayout() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 教室セレクタ（横スクロール）
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildClassroomSelector(),
            ),
          ),
          // スケジュール/タスク切り替えタブ
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildMobileDashboardTab(
                      0, Icons.grid_view, 'スケジュール'),
                  _buildMobileDashboardTab(
                      1, Icons.task_alt, 'タスク'),
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

  Widget _buildMobileDashboardTab(
      int index, IconData icon, String label) {
    final isSelected = _mobileViewIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mobileViewIndex = index),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 2)
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSub),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScheduleView() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SizedBox(
        width: 800,
        child: _buildScheduleGrid(),
      ),
    );
  }

  Widget _buildMobileTaskView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: _buildTaskSection(),
    );
  }

  // ===== ユーティリティ =====

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
}
