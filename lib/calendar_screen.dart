import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_event_screen.dart';
import 'student_detail_screen.dart';
import 'plus_schedule_screen.dart';
import 'bee_dashboard_screen.dart';
import 'app_theme.dart';
import 'main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'classroom_utils.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  CalendarView _calendarView = CalendarView.month;
  final CalendarController _controller = CalendarController();
  final CalendarController _miniCalendarController = CalendarController();
  
  String _headerText = '';
  String _headerTextWithYear = '';
  String _myUid = '';
  
  List<String> _myClassrooms = [];
  Map<String, Color> _classroomColors = {};
  
  bool _isLocaleInitialized = false;
  bool _isLoadingStaffInfo = true;

  bool _showPlusSchedule = false;
  bool _showDashboard = false;

  // フィルタ
  bool _showMySchedule = true;
  bool _showMyTasks = true;

  // Syncfusionの月表示でappointmentBuilderが同じイベントを2回呼ぶバグ対策
  final Set<String> _birthdayRenderedThisFrame = {};
  bool _birthdayFrameResetScheduled = false;
  bool _showBirthdays = true;
  final Map<String, bool> _classroomFilters = {};

  final CollectionReference _eventsRef =
      FirebaseFirestore.instance.collection('calendar_events');
  final CollectionReference _tasksRef =
      FirebaseFirestore.instance.collection('tasks');
  final CollectionReference _familiesRef =
      FirebaseFirestore.instance.collection('families');

  static const String _pendingTasksId = 'PENDING_TASKS_SUMMARY';
  static const String _taskNoteMarker = 'TASK';

  @override
void initState() {
  super.initState();
  _loadSavedDisplayDate();
  _loadFilterPrefs();
  _initData();

  // クリック後に残るセル選択枠を常時クリア
  _controller.addPropertyChangedListener((property) {
    if (property == 'selectedDate' && _controller.selectedDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.selectedDate = null;
      });
    }
  });

  Future.delayed(const Duration(seconds: 5), () {
    if (mounted && (_isLoadingStaffInfo || !_isLocaleInitialized)) {
      setState(() {
        _isLocaleInitialized = true;
        _isLoadingStaffInfo = false;
        if (_headerText.isEmpty) {
           _headerText = DateFormat('M月', 'ja').format(DateTime.now());
        }
      });
    }
  });
}

// 保存された表示月を読み込む
Future<void> _loadSavedDisplayDate() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('calendarDisplayDate');
    if (savedDate != null && mounted) {
      final date = DateTime.tryParse(savedDate);
      if (date != null) {
        setState(() {
          _controller.displayDate = DateTime(date.year, date.month, date.day, 8, 0);
          _miniCalendarController.displayDate = date;
          _updateHeaderText(date);
        });
        return;
      }
    }
  } catch (e) {
    debugPrint('Error loading saved display date: $e');
  }
  final now = DateTime.now();
  _controller.displayDate = DateTime(now.year, now.month, now.day, 8, 0);
}

// フィルタチェックの読込
Future<void> _loadFilterPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mySchedule = prefs.getBool('calFilter_mySchedule');
    final myTasks = prefs.getBool('calFilter_myTasks');
    final birthdays = prefs.getBool('calFilter_birthdays');
    final classroomKeys = prefs.getStringList('calFilter_classroomKeys') ?? [];
    if (!mounted) return;
    setState(() {
      if (mySchedule != null) _showMySchedule = mySchedule;
      if (myTasks != null) _showMyTasks = myTasks;
      if (birthdays != null) _showBirthdays = birthdays;
      for (final k in classroomKeys) {
        final v = prefs.getBool('calFilter_classroom_$k');
        if (v != null) _classroomFilters[k] = v;
      }
    });
  } catch (e) {
    debugPrint('Error loading filter prefs: $e');
  }
}

Future<void> _saveFilterPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calFilter_mySchedule', _showMySchedule);
    await prefs.setBool('calFilter_myTasks', _showMyTasks);
    await prefs.setBool('calFilter_birthdays', _showBirthdays);
    await prefs.setStringList('calFilter_classroomKeys', _classroomFilters.keys.toList());
    for (final entry in _classroomFilters.entries) {
      await prefs.setBool('calFilter_classroom_${entry.key}', entry.value);
    }
  } catch (e) {
    debugPrint('Error saving filter prefs: $e');
  }
}

// 表示月を保存
Future<void> _saveDisplayDate(DateTime date) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calendarDisplayDate', date.toIso8601String());
  } catch (e) {
    debugPrint('Error saving display date: $e');
  }
}


  Future<void> _initData() async {
    try {
      await initializeDateFormatting('ja', null);
    } catch (e) {
      debugPrint('DateFormat init error: $e');
    }
    
    if (mounted) {
      setState(() {
        _isLocaleInitialized = true;
        _headerText = DateFormat('M月', 'ja').format(DateTime.now());
        _headerTextWithYear = DateFormat('yyyy年M月', 'ja').format(DateTime.now());
      });
    }

    await Future.wait([
      _fetchStaffInfo(),
      _fetchClassroomColors(),
      _fetchStudentCourses(),
    ]);
  }

  // studentId (uid_firstName) → コース名 のマップ
  Map<String, String> _studentCourseMap = {};

  Future<void> _fetchStudentCourses() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('families').get();
      final Map<String, String> courseMap = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? '';
        final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
        for (var child in children) {
          final firstName = child['firstName'] as String? ?? '';
          final course = child['course'] as String? ?? '';
          if (uid.isNotEmpty && firstName.isNotEmpty) {
            courseMap['${uid}_$firstName'] = course;
          }
        }
      }
      if (mounted) {
        setState(() => _studentCourseMap = courseMap);
      }
    } catch (e) {
      debugPrint('Error fetching student courses: $e');
    }
  }

  String _courseSuffix(String studentId) {
    final course = _studentCourseMap[studentId];
    if (course == 'キッズコース（1h）') return '(1h)';
    if (course == 'キッズコース（2h）') return '(2h)';
    return '';
  }

  Future<void> _fetchClassroomColors() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('classrooms').get();
      final Map<String, Color> colors = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String?;
        final colorVal = data['color'] as int?;
        if (name != null && name.isNotEmpty && colorVal != null) {
          colors[name] = Color(colorVal);
        }
      }
      if (mounted) {
        setState(() {
          _classroomColors = colors;
        });
      }
    } catch (e) {
      debugPrint('Error fetching classroom colors: $e');
    }
  }

  Future<void> _fetchStaffInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _myUid = user.uid;
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('staffs')
            .where('uid', isEqualTo: _myUid)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final data = snapshot.docs.first.data();
          if (mounted) {
            setState(() {
              _myClassrooms = List<String>.from(data['classrooms'] ?? [])
                  .where((room) => !room.contains('プラス'))
                  .toList();
              for (var room in _myClassrooms) {
                // 既存の値（SharedPreferences から読み込み済み）があれば尊重する
                _classroomFilters.putIfAbsent(room, () => true);
              }
              _isLoadingStaffInfo = false;
            });
          }
        } else {
          if (mounted) setState(() => _isLoadingStaffInfo = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingStaffInfo = false);
      }
    } else {
      if (mounted) setState(() => _isLoadingStaffInfo = false);
    }
  }

  void _updateHeaderText(DateTime date) {
    if (!mounted) return;
    setState(() {
      _headerText = DateFormat('M月', 'ja').format(date);
      _headerTextWithYear = DateFormat('yyyy年M月', 'ja').format(date);
    });
  }

  void _onViewChanged(ViewChangedDetails details) {
  final visibleDates = details.visibleDates;
  if (visibleDates.isNotEmpty) {
    final centerDate = visibleDates[visibleDates.length ~/ 2];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateHeaderText(centerDate);
        if (_miniCalendarController.displayDate?.month != centerDate.month) {
          _miniCalendarController.displayDate = centerDate;
        }
        _saveDisplayDate(centerDate);
      }
    });
  }
}

  void _goToToday() {
  final now = DateTime.now();
  _controller.displayDate = now;
  _miniCalendarController.displayDate = now;
  _updateHeaderText(now);
  _saveDisplayDate(now);
}

  // ドラッグでイベント移動時の処理（15分単位、週ビューは日単位の横移動）
  void _onDragEnd(AppointmentDragEndDetails details) async {
    if (details.appointment == null || details.droppingTime == null) return;
    
    final appointment = details.appointment as Appointment;
    
    // タスクや誕生日は移動不可
    if (appointment.notes == _taskNoteMarker || 
        appointment.notes == 'BIRTHDAY' ||
        appointment.notes == 'PENDING_TASKS' ||
        appointment.id == _pendingTasksId) {
      return;
    }
    
    if (appointment.id is! DocumentSnapshot) return;
    
    final doc = appointment.id as DocumentSnapshot;
    final docData = doc.data() as Map<String, dynamic>;
    final originalStart = (docData['startTime'] as Timestamp).toDate();
    final originalEnd = (docData['endTime'] as Timestamp).toDate();
    final duration = originalEnd.difference(originalStart);
    final droppedTime = details.droppingTime!;
    
    // 15分単位に丸める
    final roundedMinute = (droppedTime.minute / 15).round() * 15;
    final adjustedMinute = roundedMinute == 60 ? 0 : roundedMinute;
    final adjustedHour = roundedMinute == 60 ? droppedTime.hour + 1 : droppedTime.hour;
    
    DateTime newStart;
    
    if (_calendarView == CalendarView.week) {
      // 週ビュー：日付はドロップ先の日付を使用（横方向は日単位で移動）
      newStart = DateTime(
        droppedTime.year, 
        droppedTime.month, 
        droppedTime.day, 
        adjustedHour, 
        adjustedMinute
      );
    } else if (_calendarView == CalendarView.day) {
      // 日ビュー：横方向移動なし（元の日付を維持）
      newStart = DateTime(
        appointment.startTime.year, 
        appointment.startTime.month, 
        appointment.startTime.day, 
        adjustedHour, 
        adjustedMinute
      );
    } else {
      // 月ビュー：日付はドロップ先、時刻はFirestoreの元データから取得
      // （Syncfusionがドラッグ中にappointment.startTimeを0:00に書き換えるため）
      newStart = DateTime(
        droppedTime.year,
        droppedTime.month,
        droppedTime.day,
        originalStart.hour,
        originalStart.minute
      );
    }
    
    final newEnd = newStart.add(duration);
    
    try {
      await doc.reference.update({
        'startTime': Timestamp.fromDate(newStart),
        'endTime': Timestamp.fromDate(newEnd),
      });
    } catch (e) {
      debugPrint('Error updating event time: $e');
    }
  }

  // リサイズでイベントの時間変更時の処理（15分単位）
  void _onAppointmentResizeEnd(AppointmentResizeEndDetails details) async {
    if (details.appointment == null) return;
    
    final appointment = details.appointment as Appointment;
    
    // タスクや誕生日はリサイズ不可
    if (appointment.notes == _taskNoteMarker || 
        appointment.notes == 'BIRTHDAY' ||
        appointment.notes == 'PENDING_TASKS' ||
        appointment.id == _pendingTasksId) {
      return;
    }
    
    if (appointment.id is! DocumentSnapshot) return;
    
    final doc = appointment.id as DocumentSnapshot;
    
    // 開始時間を15分単位に丸める
    final startMinute = (appointment.startTime.minute / 15).round() * 15;
    final adjustedStartMinute = startMinute == 60 ? 0 : startMinute;
    final adjustedStartHour = startMinute == 60 ? appointment.startTime.hour + 1 : appointment.startTime.hour;
    final newStart = DateTime(
      appointment.startTime.year,
      appointment.startTime.month,
      appointment.startTime.day,
      adjustedStartHour,
      adjustedStartMinute,
    );
    
    // 終了時間を15分単位に丸める
    final endMinute = (appointment.endTime.minute / 15).round() * 15;
    final adjustedEndMinute = endMinute == 60 ? 0 : endMinute;
    final adjustedEndHour = endMinute == 60 ? appointment.endTime.hour + 1 : appointment.endTime.hour;
    final newEnd = DateTime(
      appointment.endTime.year,
      appointment.endTime.month,
      appointment.endTime.day,
      adjustedEndHour,
      adjustedEndMinute,
    );
    
    try {
      await doc.reference.update({
        'startTime': Timestamp.fromDate(newStart),
        'endTime': Timestamp.fromDate(newEnd),
      });
    } catch (e) {
      debugPrint('Error updating event time: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocaleInitialized || _isLoadingStaffInfo) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('データを読み込んでいます...', style: TextStyle(color: context.colors.textSecondary)),
            ],
          ),
        ),
      );
    }

    final bool showSidebar = MediaQuery.of(context).size.width >= AppBreakpoints.desktop;

    if (_showPlusSchedule) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: context.colors.scaffoldBg,
        body: PlusScheduleContent(
          onBack: () => setState(() => _showPlusSchedule = false),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.colors.scaffoldBg,
      drawer: showSidebar
          ? null
          : Drawer(
              backgroundColor: context.colors.cardBg,
              width: 300,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, left: 12, right: 12),
                  child: _buildDrawerContent(),
                ),
              ),
            ),
      appBar: showSidebar 
        ? AppBar(
            backgroundColor: context.colors.cardBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 64,
            titleSpacing: 24, 
            title: _showDashboard
                ? const SizedBox.shrink()
                : Row(
              children: [
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: _goToToday,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      side: BorderSide(color: context.colors.borderMedium),
                      shape: RoundedRectangleBorder(borderRadius: AppStyles.radiusSmall),
                      foregroundColor: context.colors.textPrimary,
                    ),
                    child: const Text('今日'),
                  ),
                ),
                SizedBox(width: 20),
                IconButton(
                  icon: Icon(Icons.chevron_left, color: context.colors.textSecondary),
                  onPressed: () => _controller.backward!(),
                  splashRadius: 20,
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: context.colors.textSecondary),
                  onPressed: () => _controller.forward!(),
                  splashRadius: 20,
                ),
                SizedBox(width: 16),
                Text(
                  _headerTextWithYear,
                  style: TextStyle(
                    color: context.colors.textPrimary, fontSize: 22, fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: _buildViewSwitcher(),
              ),
            ],
          )
        : AppBar(
            backgroundColor: context.colors.cardBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: kToolbarHeight,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: _buildSegmentedControl(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.menu, color: context.colors.textPrimary),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),
                        Text(
                          _headerText,
                          style: TextStyle(
                            color: context.colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        onTap: _goToToday,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            border: Border.all(color: context.colors.iconMuted, width: 1.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${DateTime.now().day}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      body: _showDashboard
        ? const BeeDashboardContent()
        : StreamBuilder<QuerySnapshot>(
        stream: _eventsRef.snapshots(),
        builder: (context, eventSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: _tasksRef.where('userId', isEqualTo: _myUid).snapshots(),
            builder: (context, taskSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: _familiesRef.snapshots(),
                builder: (context, familySnapshot) {
                  List<Appointment> appointments = [];
                  _birthdayRenderedThisFrame.clear();

                  // イベント処理
                  if (eventSnapshot.hasData) {
                    for (var doc in eventSnapshot.data!.docs) {
                      try {
                        final data = doc.data() as Map<String, dynamic>;
                        final String? eventClassroom = data['classroom'];
                        // プラス教室のイベントは表示しない
                        if (eventClassroom != null && eventClassroom.contains('プラス')) continue;
                        final List<dynamic> staffIds = data['staffIds'] ?? [];

                        bool isVisible = false;
                        if (_showMySchedule && staffIds.contains(_myUid)) isVisible = true;
                        if (!isVisible && eventClassroom != null) {
                          if (_classroomFilters.containsKey(eventClassroom) && _classroomFilters[eventClassroom] == true) {
                            isVisible = true;
                          }
                        }
                        // クラスルームもスタッフも未指定なら汎用イベントとして常時表示
                        final bool noClassroom = eventClassroom == null;
                        final bool noStaff = data['staffIds'] == null || staffIds.isEmpty;
                        if (noClassroom && noStaff) isVisible = true;

                        if (!isVisible) continue;

                        // startTime/endTime の安全な変換
                        final startTs = data['startTime'];
                        final endTs = data['endTime'];
                        if (startTs is! Timestamp || endTs is! Timestamp) {
                          debugPrint(
                              '⚠️ event skipped (bad timestamps): id=${doc.id} classroom=$eventClassroom');
                          continue;
                        }
                        final startDt = startTs.toDate();
                        final endDt = endTs.toDate();

                        Color eventColor = Color(data['color'] ?? AppColors.primary.value);
                        if (eventClassroom != null && _classroomColors.containsKey(eventClassroom)) {
                          eventColor = _classroomColors[eventClassroom]!;
                        }

                        // RRULE の事前バリデーション
                        // Syncfusion は不正な RRULE を描画時に遅延展開して throw する場合があり、
                        // その1件がカレンダー全体のレンダリングを潰すことがある。
                        // ここで parseRRule + getRecurrenceDateTimeCollection で検証する。
                        String? rrule;
                        final rawRule = data['recurrenceRule'];
                        if (rawRule != null && rawRule.toString().isNotEmpty) {
                          var ruleStr = rawRule.toString();

                          // FREQ=WEEKLY で BYDAY がない場合、開始日の曜日から自動補完
                          if (ruleStr.contains('FREQ=WEEKLY') &&
                              !ruleStr.contains('BYDAY=')) {
                            const dayNames = [
                              'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'
                            ];
                            final dayOfWeek =
                                dayNames[startDt.weekday - 1]; // DateTime.monday == 1
                            ruleStr = '$ruleStr;BYDAY=$dayOfWeek';
                            debugPrint(
                                '🔧 auto-fix RRULE: id=${doc.id} added BYDAY=$dayOfWeek → $ruleStr');
                          }

                          try {
                            SfCalendar.parseRRule(ruleStr, startDt);
                            SfCalendar.getRecurrenceDateTimeCollection(
                              ruleStr,
                              startDt,
                              specificStartDate: startDt,
                              specificEndDate: startDt.add(const Duration(days: 730)),
                            );
                            rrule = ruleStr;
                          } catch (e) {
                            debugPrint(
                                '⚠️ invalid recurrenceRule: id=${doc.id} classroom=$eventClassroom subject=${data['subject']} rule=$ruleStr error=$e');
                            rrule = null;
                          }
                        }

                        // 例外日（削除された回）のサポート
                        List<DateTime>? exceptionDates;
                        final rawExceptions = data['exceptionDates'];
                        if (rawExceptions is List && rawExceptions.isNotEmpty) {
                          exceptionDates = rawExceptions
                              .whereType<Timestamp>()
                              .map((t) => t.toDate())
                              .toList();
                          if (exceptionDates.isEmpty) exceptionDates = null;
                        }

                        appointments.add(Appointment(
                          id: doc,
                          startTime: startDt,
                          endTime: endDt,
                          subject: data['subject'] ?? '(件名なし)',
                          notes: 'EVENT',
                          color: eventColor,
                          recurrenceRule: rrule,
                          recurrenceExceptionDates: exceptionDates,
                        ));
                      } catch (e) {
                        debugPrint('⚠️ event processing failed: id=${doc.id} error=$e');
                      }
                    }
                  }

                  // タスク処理
                  if (taskSnapshot.hasData) {
                    int pendingCount = 0;
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);

                    for (var doc in taskSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final dateTs = data['date'] as Timestamp;
                      final date = dateTs.toDate();
                      final taskDate = DateTime(date.year, date.month, date.day); 
                      
                      final isCompleted = data['isCompleted'] ?? false;
                      final title = data['title'] ?? '(無題のタスク)';

                      if (!isCompleted && taskDate.isBefore(today)) {
                        pendingCount++;
                      } else {
                        if (!isCompleted && _showMyTasks) {
                          appointments.add(Appointment(
                            id: doc,
                            startTime: date,
                            endTime: date,
                            isAllDay: true, 
                            subject: '◯ $title',
                            notes: _taskNoteMarker, 
                            color: AppColors.secondary,
                            recurrenceRule: null,
                          ));
                        }
                      }
                    }

                    if (pendingCount > 0 && _showMyTasks) {
                      appointments.add(Appointment(
                        id: _pendingTasksId, 
                        startTime: today,
                        endTime: today,
                        isAllDay: true,
                        subject: '⚠️ ${pendingCount}件の保留中のタスク',
                        notes: 'PENDING_TASKS',
                        color: Colors.transparent, 
                      ));
                    }
                  }

                  // 誕生日処理（修正版：複数年対応＋教室フィルタ連動＋重複排除）
                  if (familySnapshot.hasData && _showBirthdays) {
                    final displayDate = _controller.displayDate ?? DateTime.now();
                    final baseYear = displayDate.year;
                    // 同じ名前＋同じ誕生日の重複を排除するためのSet
                    final addedBirthdays = <String>{};

                    for (var doc in familySnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
                      final parentLastName = data['lastName'] ?? '';

                      for (var child in children) {
                        final childClassrooms = getChildClassrooms(child);
                        if (childClassrooms.isEmpty || !childClassrooms.any((c) => _myClassrooms.contains(c))) continue;

                        // 教室フィルタとの連動チェック
                        final matchedClassroom = childClassrooms.firstWhere((c) => _myClassrooms.contains(c), orElse: () => '');
                        if (matchedClassroom.isNotEmpty && _classroomFilters.containsKey(matchedClassroom) && _classroomFilters[matchedClassroom] != true) {
                          continue;
                        }

                        final birthDateStr = child['birthDate'] as String?;
                        if (birthDateStr == null || birthDateStr.isEmpty) continue;

                        final parts = birthDateStr.split('/');
                        if (parts.length != 3) continue;

                        final birthMonth = int.tryParse(parts[1]) ?? 0;
                        final birthDay = int.tryParse(parts[2]) ?? 0;
                        if (birthMonth == 0 || birthDay == 0) continue;

                        final childName = (child['firstName'] ?? '').toString().trim();
                        final displayName = '${parentLastName.trim()} $childName';

                        // 同名＋同誕生日の重複チェック
                        final dedupeKey = '${displayName}_${birthMonth}_$birthDay';
                        if (addedBirthdays.contains(dedupeKey)) continue;
                        addedBirthdays.add(dedupeKey);

                        // 表示中の年を中心に前後1年（計3年分）の誕生日を生成
                        for (int year = baseYear - 1; year <= baseYear + 1; year++) {
                          final birthdayDate = DateTime(year, birthMonth, birthDay);

                          final bdStart = DateTime(year, birthMonth, birthDay, 0, 0);
                          final bdEnd = DateTime(year, birthMonth, birthDay, 0, 1);
                          appointments.add(Appointment(
                            id: 'birthday_${doc.id}_${childName}_$year',
                            startTime: bdStart,
                            endTime: bdEnd,
                            isAllDay: false,
                            subject: '🎂 $displayName',
                            notes: 'BIRTHDAY',
                            color: Colors.pink.shade300,
                          ));
                        }
                      }
                    }
                  }

                  // 誕生日を最上段に表示するためソート
                  appointments.sort((a, b) {
                    final aIsBirthday = a.notes == 'BIRTHDAY' ? 0 : 1;
                    final bIsBirthday = b.notes == 'BIRTHDAY' ? 0 : 1;
                    if (aIsBirthday != bIsBirthday) return aIsBirthday.compareTo(bIsBirthday);
                    return a.startTime.compareTo(b.startTime);
                  });

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSidebar)
                        Container(
                          width: 280,
                          padding: const EdgeInsets.only(top: 16, left: 12, right: 12),
                          decoration: BoxDecoration(
                            color: context.colors.cardBg,
                          ),
                          child: _buildSidebarContent(),
                        ),
                      
                      Expanded(
                        child: Stack(
                          children: [
                            Theme(
                              data: Theme.of(context).copyWith(
                                hoverColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                splashColor: Colors.transparent,
                              ),
                              child: Builder(
                              builder: (context) {
                              final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.tablet;
                              return SfCalendarTheme(
                              data: SfCalendarThemeData(
                                selectionBorderColor: Colors.transparent,
                                // 現在時刻ライン色（Google風の赤）。今日の日付ハイライトもこの色になる
                                todayHighlightColor: AppColors.primary,
                                cellBorderColor: context.colors.borderMedium,
                              ),
                              child: MouseRegion(
                                onEnter: (_) {},
                                onExit: (_) {},
                                onHover: (_) {},
                                child: SfCalendar(
                                view: _calendarView,
                                controller: _controller,
                                firstDayOfWeek: 1,
                                dataSource: _DataSource(appointments),
                                onTap: calendarTapped, 
                                onViewChanged: _onViewChanged,
                                // ドラッグでイベント移動を有効化
                                allowDragAndDrop: true,
                                onDragEnd: _onDragEnd,
                                // リサイズでイベントの時間変更を有効化
                                allowAppointmentResize: true,
                                onAppointmentResizeEnd: _onAppointmentResizeEnd,
                                backgroundColor: context.colors.cardBg,
                                cellBorderColor: context.colors.borderMedium,
                                headerHeight: 0,
                                viewHeaderHeight: isMobile ? 56 : 60,
                                allowViewNavigation: false,
                                selectionDecoration: const BoxDecoration(),
                                viewHeaderStyle: ViewHeaderStyle(
                                  dayTextStyle: TextStyle(fontSize: isMobile ? 10 : 11, color: context.colors.textSecondary, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                                  dateTextStyle: TextStyle(fontSize: isMobile ? 14 : 18, color: context.colors.textPrimary, fontWeight: FontWeight.w400),
                                ),
                                monthViewSettings: MonthViewSettings(
                                  appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                                  appointmentDisplayCount: isMobile ? 5 : 5,
                                  showAgenda: false,
                                  monthCellStyle: MonthCellStyle(
                                    textStyle: TextStyle(fontSize: isMobile ? 11 : 12, color: context.colors.textPrimary, height: 1.0),
                                    trailingDatesTextStyle: TextStyle(fontSize: isMobile ? 11 : 12, color: context.colors.textSecondary, height: 1.0),
                                    leadingDatesTextStyle: TextStyle(fontSize: isMobile ? 11 : 12, color: context.colors.textSecondary, height: 1.0),
                                    todayBackgroundColor: Colors.transparent,
                                    todayTextStyle: TextStyle(fontSize: isMobile ? 9 : 11, color: Colors.white, fontWeight: FontWeight.w600, height: 1.0),
                                  ),
                                ),
                                appointmentBuilder: (context, calendarAppointmentDetails) {
                                  final Appointment appointment = calendarAppointmentDetails.appointments.first;
                                  
                                  final bool isPending = appointment.id == _pendingTasksId;
                                  final bool isTask = appointment.notes == _taskNoteMarker;
                                  final bool isBirthday = appointment.notes == 'BIRTHDAY';

                                  // 保留中タスク
                                  if (isPending) {
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 1),
                                      decoration: BoxDecoration(
                                        color: context.colors.cardBg,
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(color: AppColors.error.withOpacity(0.5)),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.check_circle_outline, size: 10, color: AppColors.error),
                                          const SizedBox(width: 2),
                                          Expanded(
                                            child: Text(
                                              appointment.subject.replaceAll('⚠️ ', ''), 
                                              style: TextStyle(
                                                color: AppColors.error, 
                                                fontSize: 12,
                                                height: 1.0, 
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  // タスク
                                  if (isTask) {
                                    return Container(
                                      margin: const EdgeInsets.symmetric(vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondary, 
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      alignment: Alignment.centerLeft,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.check_circle_outline, size: 10, color: Colors.white), 
                                          const SizedBox(width: 2),
                                          Expanded(
                                            child: Text(
                                              appointment.subject.replaceAll('◯ ', ''),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12, 
                                                decoration: TextDecoration.none,
                                                height: 1.0,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  
                                  // 誕生日
                                  if (isBirthday) {
                                    return _buildBirthdayAppointment(context, appointment);
                                  }
                                  
                                  // 通常イベント
                                  final isMonthView = _calendarView == CalendarView.month;
                                  // 時間テキスト（Google風: 午前9時, 午後12時30分）
                                  String fmtJpHour(DateTime t) {
                                    final h = t.hour;
                                    final m = t.minute;
                                    final isAm = h < 12;
                                    final h12 = h == 0 ? 12 : (h <= 12 ? h : h - 12);
                                    final base = '${isAm ? '午前' : '午後'}$h12時';
                                    return m == 0 ? base : '$base$m分';
                                  }
                                  final timeText =
                                      '${fmtJpHour(appointment.startTime)}〜${fmtJpHour(appointment.endTime)}';
                                  final tileHeight = calendarAppointmentDetails.bounds.height;
                                  // 高さが小さい時は1行でまとめる（Googleカレンダー風: 「タイトル、時間」）
                                  final isCompact = tileHeight < 36;

                                  return Container(
                                    margin: isMonthView
                                        ? (isMobile ? const EdgeInsets.symmetric(vertical: 0.5) : const EdgeInsets.symmetric(vertical: 1))
                                        : EdgeInsets.only(top: 1, bottom: 1, right: isMobile ? 1 : 6),
                                    decoration: BoxDecoration(
                                      color: appointment.color,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    alignment: isMonthView ? Alignment.centerLeft : Alignment.topLeft,
                                    padding: isMonthView
                                        ? EdgeInsets.symmetric(horizontal: isMobile ? 1 : 4)
                                        : (isCompact
                                            ? EdgeInsets.fromLTRB(isMobile ? 3 : 8, 2, isMobile ? 2 : 8, 2)
                                            : EdgeInsets.fromLTRB(isMobile ? 3 : 8, 4, isMobile ? 2 : 8, 4)),
                                    child: isMonthView
                                        ? Text(
                                            appointment.subject,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: isMobile ? 9.5 : 12,
                                              height: 1.0,
                                              letterSpacing: -0.3,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.clip,
                                          )
                                        : isMobile
                                            // 週/日ビュー（モバイル）: Googleカレンダー風に折り返し全表示
                                            ? Text(
                                                appointment.subject,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w400,
                                                  height: 1.15,
                                                  letterSpacing: -0.3,
                                                ),
                                                softWrap: true,
                                                maxLines: 100,
                                                overflow: TextOverflow.clip,
                                              )
                                            : isCompact
                                                ? Text(
                                                    '${appointment.subject}、$timeText',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w400,
                                                      height: 1.2,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.clip,
                                                  )
                                                : Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        appointment.subject,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w400,
                                                          height: 1.2,
                                                        ),
                                                        softWrap: true,
                                                        maxLines: 100,
                                                        overflow: TextOverflow.clip,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        timeText,
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.9),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w400,
                                                          height: 1.2,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.clip,
                                                      ),
                                                    ],
                                                  ),
                                  );
                                },
                                timeSlotViewSettings: TimeSlotViewSettings(
                                  timeIntervalHeight: isMobile ? 50 : 60,
                                  timeRulerSize: isMobile ? 44 : 64,
                                  // Google風の時間表記（例: 9:00 / 13:00）
                                  timeFormat: 'H:mm',
                                  // 時間グリッドは1時間単位
                                  timeInterval: Duration(minutes: 60),
                                  timeTextStyle: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                                  dateFormat: 'd',
                                  dayFormat: 'EEE',
                                  allDayPanelColor: context.colors.cardBg,
                                  // 15分単位で操作可能に
                                  minimumAppointmentDuration: Duration(minutes: 15),
                                ),
                                // 【修正2】dragAndDropSettingsでドラッグ時の動作を設定
                                dragAndDropSettings: DragAndDropSettings(
                                  allowNavigation: true,
                                  allowScroll: true,
                                  showTimeIndicator: true,
                                  indicatorTimeFormat: 'HH:mm',
                                  timeIndicatorStyle: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ),
                              );
                              },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: _showDashboard ? null : FloatingActionButton(
        heroTag: null, 
        onPressed: () => _showAddEventDialog(),
        backgroundColor: context.colors.cardBg,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo_beesmileymark.png',
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.add, color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  // 新規タスク追加ダイアログ
  Future<void> _showAddTaskDialog({DateTime? initialDate}) async {
    final bool showSidebar = MediaQuery.of(context).size.width >= AppBreakpoints.desktop;
    
    if (showSidebar) {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: context.colors.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 500,
            height: MediaQuery.of(context).size.height * 0.85,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AddEventDialog(
                initialStartDate: initialDate,
                initialIsTask: true, // タスクモードで開く
              ),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: AddEventDialog(
              initialStartDate: initialDate,
              initialIsTask: true, // タスクモードで開く
            ),
          ),
        ),
      );
    }
  }

  Widget _buildSidebarContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 280,
          child: SfCalendarTheme(
            data: SfCalendarThemeData(
              backgroundColor: Colors.transparent,
              headerTextStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            child: SfCalendar(
              controller: _miniCalendarController,
              view: CalendarView.month,
              headerDateFormat: 'yyyy年 M月',
              backgroundColor: Colors.transparent,
              cellBorderColor: Colors.transparent,
              headerHeight: 40,
              viewHeaderHeight: 30,
              viewHeaderStyle: ViewHeaderStyle(
                dayTextStyle: TextStyle(fontSize: 11, color: context.colors.textSecondary, fontWeight: FontWeight.w500),
              ),
              headerStyle: CalendarHeaderStyle(
                textStyle: TextStyle(fontSize: 13, color: context.colors.textPrimary, fontWeight: FontWeight.bold),
                backgroundColor: Colors.transparent,
              ),
              todayHighlightColor: AppColors.primary,
              selectionDecoration: BoxDecoration(
                color: Colors.transparent, 
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              monthViewSettings: MonthViewSettings(
                numberOfWeeksInView: 6,
                appointmentDisplayMode: MonthAppointmentDisplayMode.none,
                monthCellStyle: MonthCellStyle(
                  textStyle: TextStyle(fontSize: 12, color: context.colors.textPrimary),
                  trailingDatesTextStyle: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                  leadingDatesTextStyle: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                  todayBackgroundColor: Colors.transparent,
                  todayTextStyle: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
              onTap: (details) {
                if (details.date != null) {
                  _controller.displayDate = DateTime(details.date!.year, details.date!.month, details.date!.day, 8, 0);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              _buildFilterCheckbox('マイカレンダー', _showMySchedule, (val) { setState(() => _showMySchedule = val); _saveFilterPrefs(); }, AppColors.primary),
              _buildFilterCheckbox('マイタスク', _showMyTasks, (val) { setState(() => _showMyTasks = val); _saveFilterPrefs(); }, AppColors.secondary),
              _buildFilterCheckbox('誕生日', _showBirthdays, (val) { setState(() => _showBirthdays = val); _saveFilterPrefs(); }, Colors.pink.shade300),
              const SizedBox(height: 8),
              if (_myClassrooms.isEmpty)
                Padding(
                  padding: EdgeInsets.only(left: 32, top: 4),
                  child: Text('担当教室なし', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                )
              else
                ..._myClassrooms.map((roomName) {
                  final color = _classroomColors[roomName] ?? AppColors.primary;
                  return _buildFilterCheckbox(
                    roomName,
                    _classroomFilters[roomName] ?? true,
                    (val) { setState(() => _classroomFilters[roomName] = val); _saveFilterPrefs(); },
                    color, 
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              _buildFilterCheckbox('マイカレンダー', _showMySchedule, (val) { setState(() => _showMySchedule = val); _saveFilterPrefs(); }, AppColors.primary),
              _buildFilterCheckbox('マイタスク', _showMyTasks, (val) { setState(() => _showMyTasks = val); _saveFilterPrefs(); }, AppColors.secondary),
              _buildFilterCheckbox('誕生日', _showBirthdays, (val) { setState(() => _showBirthdays = val); _saveFilterPrefs(); }, Colors.pink.shade300),
              const SizedBox(height: 8),
              if (_myClassrooms.isEmpty)
                Padding(
                  padding: EdgeInsets.only(left: 32, top: 4),
                  child: Text('担当教室なし', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                )
              else
                ..._myClassrooms.map((roomName) {
                  final color = _classroomColors[roomName] ?? AppColors.primary;
                  return _buildFilterCheckbox(
                    roomName,
                    _classroomFilters[roomName] ?? true,
                    (val) { setState(() => _classroomFilters[roomName] = val); _saveFilterPrefs(); },
                    color, 
                  );
                }),
              
              const SizedBox(height: 16),
              const Divider(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedControl() {
    // 4つのセグメント: 日, 週, 月, ダッシュボード(アイコン)
    final labels = ['日', '週', '月'];
    int selectedIndex;
    if (_showDashboard) {
      selectedIndex = 3;
    } else {
      final views = [CalendarView.day, CalendarView.week, CalendarView.month];
      selectedIndex = views.indexOf(_calendarView);
    }
    const double buttonWidth = 42.0;
    const double dashboardButtonWidth = 42.0;
    const double buttonHeight = 32.0;
    const double containerPadding = 3.0;
    const totalWidth = buttonWidth * 3 + dashboardButtonWidth + containerPadding * 2;

    double selectedLeft;
    double selectedWidth;
    if (selectedIndex < 3) {
      selectedLeft = selectedIndex * buttonWidth;
      selectedWidth = buttonWidth;
    } else {
      selectedLeft = buttonWidth * 3;
      selectedWidth = dashboardButtonWidth;
    }

    return Container(
      width: totalWidth,
      height: buttonHeight + containerPadding * 2,
      padding: EdgeInsets.all(containerPadding),
      decoration: BoxDecoration(
        color: context.colors.borderLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: selectedLeft,
            top: 0,
            child: Container(
              width: selectedWidth,
              height: buttonHeight,
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              // 日・週・月ボタン
              ...List.generate(3, (index) {
                final isSelected = selectedIndex == index;
                final views = [CalendarView.day, CalendarView.week, CalendarView.month];
                return GestureDetector(
                  onTap: () => setState(() {
                    _showDashboard = false;
                    _calendarView = views[index];
                    _controller.view = views[index];
                  }),
                  child: Container(
                    width: buttonWidth,
                    height: buttonHeight,
                    color: Colors.transparent,
                    alignment: Alignment.center,
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? context.colors.textPrimary : context.colors.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
              // ダッシュボードボタン
              GestureDetector(
                onTap: () => setState(() {
                  _showDashboard = true;
                }),
                child: Container(
                  width: dashboardButtonWidth,
                  height: buttonHeight,
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.dashboard_outlined,
                    size: 18,
                    color: selectedIndex == 3 ? context.colors.textPrimary : context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    // モバイル版と同じセグメントコントロール（日・週・月 + ダッシュボードアイコン）
    return _buildSegmentedControl();
  }

  Widget _buildFilterCheckbox(String title, bool value, Function(bool) onChanged, Color color) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: Checkbox(value: value, activeColor: color, onChanged: (val) => onChanged(val!))),
            SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: context.colors.textPrimary))),
          ],
        ),
      ),
    );
  }

  Widget _buildBirthdayAppointment(BuildContext context, Appointment appointment) {
    if (!_birthdayFrameResetScheduled) {
      _birthdayFrameResetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _birthdayRenderedThisFrame.clear();
        _birthdayFrameResetScheduled = false;
      });
    }
    final birthdayKey = '${appointment.id}_${appointment.startTime.day}';
    if (_birthdayRenderedThisFrame.contains(birthdayKey)) {
      return const SizedBox.shrink();
    }
    _birthdayRenderedThisFrame.add(birthdayKey);
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      margin: isMobile ? const EdgeInsets.symmetric(vertical: 0.5) : const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: Colors.pink.shade300,
        borderRadius: BorderRadius.circular(2),
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 1 : 2),
      alignment: Alignment.centerLeft,
      child: Text(
        appointment.subject,
        style: TextStyle(
          color: Colors.white,
          fontSize: isMobile ? 9.5 : 12,
          height: 1.0,
          letterSpacing: isMobile ? -0.3 : 0,
        ),
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );
  }

  void calendarTapped(CalendarTapDetails details) {
    if (details.targetElement == CalendarElement.calendarCell) {
      _controller.selectedDate = null;
      if (_calendarView == CalendarView.month) {
        setState(() {
          _calendarView = CalendarView.day;
          _controller.view = CalendarView.day;
          _controller.displayDate = DateTime(details.date!.year, details.date!.month, details.date!.day, 8, 0);
        });
      } else {
        // クリック位置で00か30を判定（minuteが0-29なら:00、30-59なら:30）
        final date = details.date!;
        final roundedMinute = date.minute < 30 ? 0 : 30;
        final roundedDate = DateTime(date.year, date.month, date.day, date.hour, roundedMinute);
        _showAddEventDialog(initialDate: roundedDate);
      }
    } else if (details.targetElement == CalendarElement.allDayPanel) {
      // 週・日ビューの終日パネルクリックで新規タスク追加
      _controller.selectedDate = null;
      if (_calendarView == CalendarView.day || _calendarView == CalendarView.week) {
        // 既存のタスクをタップした場合はその詳細を表示、空白なら新規タスク
        if (details.appointments != null && details.appointments!.isNotEmpty) {
          final first = details.appointments![0];
          if (first is Appointment) {
            if (first.id == _pendingTasksId) {
              _showPendingTasksListDialog();
            } else if (first.notes == _taskNoteMarker) {
              if (first.id is DocumentSnapshot) {
                _showTaskDetail(first.id as DocumentSnapshot);
              }
            } else if (first.notes == 'BIRTHDAY') {
              // 誕生日は何もしない
            } else {
              if (first.id is DocumentSnapshot) {
                _showRichAppointmentDetail(first.id as DocumentSnapshot);
              }
            }
          }
        } else {
          // 空白部分クリックで新規タスク追加
          _showAddTaskDialog(initialDate: details.date);
        }
      }
    } else if (details.targetElement == CalendarElement.viewHeader) {
      // 日付ヘッダー（日付の左右含む）クリックで新規タスク追加
      _controller.selectedDate = null;
      if (_calendarView == CalendarView.day || _calendarView == CalendarView.week) {
        _showAddTaskDialog(initialDate: details.date);
      }
    } else if (details.appointments != null && details.appointments!.isNotEmpty) {
      _controller.selectedDate = null;
      
      Appointment? target;
      
      try {
        final found = details.appointments!.firstWhere(
          (app) => app is Appointment && app.id == _pendingTasksId, 
          orElse: () => null
        );
        if (found != null) target = found as Appointment;
      } catch (_) {}

      if (target == null) {
        try {
          final found = details.appointments!.firstWhere(
            (app) => app is Appointment && app.notes == _taskNoteMarker, 
            orElse: () => null
          );
          if (found != null) target = found as Appointment;
        } catch (_) {}
      }

      if (target == null) {
         final first = details.appointments![0];
         if (first is Appointment) {
            target = first;
         }
      }

      if (target != null) {
        if (target.id == _pendingTasksId) {
          _showPendingTasksListDialog();
        } else if (target.notes == _taskNoteMarker) {
          if (target.id is DocumentSnapshot) {
            _showTaskDetail(target.id as DocumentSnapshot);
          }
        } else if (target.notes == 'BIRTHDAY') {
          // 誕生日クリック時は何もしない（または詳細表示を追加可能）
        } else {
          if (target.id is DocumentSnapshot) {
            _showRichAppointmentDetail(target.id as DocumentSnapshot);
          }
        }
      }
    }
  }

  Future<void> _showAddEventDialog({DateTime? initialDate}) async {
    final bool showSidebar = MediaQuery.of(context).size.width >= AppBreakpoints.desktop;
    
    if (showSidebar) {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: context.colors.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 500,
            height: MediaQuery.of(context).size.height * 0.85,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AddEventDialog(initialStartDate: initialDate),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: AddEventDialog(initialStartDate: initialDate),
          ),
        ),
      );
    }
  }

  void _showPendingTasksListDialog() {
    double? initialContentHeight;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: context.colors.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: StreamBuilder<QuerySnapshot>(
            stream: _tasksRef
                .where('userId', isEqualTo: _myUid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  width: 400,
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              
              final allDocs = snapshot.data!.docs;
              final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
              final pendingDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final isCompleted = data['isCompleted'] ?? false;
                final date = (data['date'] as Timestamp).toDate();
                final taskDate = DateTime(date.year, date.month, date.day);
                return !isCompleted && taskDate.isBefore(today);
              }).toList();

              pendingDocs.sort((a, b) {
                final d1 = (a['date'] as Timestamp).toDate();
                final d2 = (b['date'] as Timestamp).toDate();
                return d1.compareTo(d2);
              });

              final computedHeight = pendingDocs.isEmpty
                ? 100.0
                : (pendingDocs.length * 72.0).clamp(100.0, 400.0);
              // 初回表示時の高さを保持し、チェックで削除してもDialogが縮まない（位置ずれ防止）
              initialContentHeight ??= computedHeight;
              final contentHeight = initialContentHeight!;

              return SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '保留中のタスク',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 24),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: contentHeight,
                      child: pendingDocs.isEmpty
                        ? Center(
                            child: Text(
                              '保留中のタスクはありません',
                              style: TextStyle(color: context.colors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: pendingDocs.length,
                            itemBuilder: (context, index) {
                              final doc = pendingDocs[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final date = (data['date'] as Timestamp).toDate();
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['title'] ?? '無題',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('yyyy/MM/dd').format(date),
                                            style: TextStyle(fontSize: 13, color: AppColors.error),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline, size: 26, color: AppColors.primary),
                                      tooltip: '完了にする',
                                      onPressed: () async {
                                        await doc.reference.delete();
                                      },
                                    ),
                                    SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(Icons.edit_outlined, size: 24, color: context.colors.textSecondary),
                                      tooltip: '編集',
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _showEditTaskDialog(doc);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showEditTaskDialog(DocumentSnapshot doc) {
    final bool showSidebar = MediaQuery.of(context).size.width >= AppBreakpoints.desktop;
    
    if (showSidebar) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: context.colors.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 500,
            height: MediaQuery.of(context).size.height * 0.85,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AddEventDialog(taskDoc: doc),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: AddEventDialog(taskDoc: doc),
          ),
        ),
      );
    }
  }

  void _showTaskDetail(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: doc.reference.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final title = data['title'] ?? '(無題)';
            final date = (data['date'] as Timestamp).toDate();
            final notes = data['notes'] ?? '';

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: AppStyles.radius),
              contentPadding: EdgeInsets.zero,
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              
              title: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('タスク詳細', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: Icon(Icons.edit, size: 20, color: context.colors.iconMuted),
                    tooltip: '編集',
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDialog(context: context, builder: (_) => AddEventDialog(taskDoc: doc));
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: context.colors.iconMuted),
                    tooltip: '削除',
                    onPressed: () async { Navigator.pop(ctx); await doc.reference.delete(); },
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: context.colors.iconMuted),
                    tooltip: '閉じる',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: context.colors.textSecondary),
                          SizedBox(width: 8),
                          Text(DateFormat('yyyy年MM月dd日 (E)', 'ja').format(date), style: TextStyle(fontSize: 14, color: context.colors.textSecondary)),
                        ],
                      ),
                      if (notes.isNotEmpty) ...[
                        SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.inputFill, 
                            borderRadius: AppStyles.radiusSmall,
                          ),
                          child: Text(notes, style: TextStyle(fontSize: 14, height: 1.5, color: context.colors.textPrimary)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 24, 24),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await doc.reference.delete();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('タスクを完了しました')));
                  },
                  child: const Text('完了とする', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showRichAppointmentDetail(DocumentSnapshot doc) {
    final outerContext = context; // AdminShellが見えるcontext
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StreamBuilder<DocumentSnapshot>(
          stream: doc.reference.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            if (!snapshot.data!.exists) return const SizedBox.shrink();
            
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final subject = data['subject'] ?? '(件名なし)';
            final start = (data['startTime'] as Timestamp).toDate();
            final end = (data['endTime'] as Timestamp).toDate();
            final notes = data['notes'] ?? '';
            final classroom = data['classroom'] ?? '指定なし';
            
            Color color = Color(data['color'] ?? AppColors.primary.value);
            if (classroom != '指定なし' && _classroomColors.containsKey(classroom)) {
              color = _classroomColors[classroom]!;
            }
            
            final studentIds = List<String>.from(data['studentIds'] ?? []);
            final studentNames = List<String>.from(data['studentNames'] ?? []);
            final staffNames = List<String>.from(data['staffNames'] ?? []);
            final absentIds = List<String>.from(data['absentStudentIds'] ?? []);
            final transferMap = data['studentTransferDates'] as Map<String, dynamic>? ?? {};
            final trialStudentNames = List<String>.from(data['trialStudentNames'] ?? []);

            return Dialog(
              backgroundColor: context.colors.dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              elevation: 6,
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 上部ツールバー（Googleカレンダー風）
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.close, size: 22, color: context.colors.textSecondary),
                            tooltip: '閉じる',
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.edit_outlined, size: 22, color: context.colors.textSecondary),
                            tooltip: '編集',
                            onPressed: () => _confirmEdit(doc),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 22, color: context.colors.textSecondary),
                            tooltip: '削除',
                            onPressed: () => _confirmDelete(doc),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    // タイトル部分
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              subject,
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: context.colors.textPrimary, height: 1.2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      _buildDetailRow(Icons.access_time,
                        '${DateFormat('M月d日 (E)', 'ja').format(start)}\n'
                        '${DateFormat('H:mm').format(start)} – ${DateFormat('H:mm').format(end)}'
                      ),
                      const SizedBox(height: 16),

                      if (classroom != '指定なし')
                        _buildDetailRow(Icons.location_on_outlined, classroom),
                      const SizedBox(height: 16),

                      if (staffNames.isNotEmpty)
                        _buildDetailList(Icons.badge_outlined, staffNames),
                      
                      if (studentNames.isNotEmpty || trialStudentNames.isNotEmpty) ...[
                        SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.face, size: 20, color: context.colors.textSecondary),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...List.generate(studentIds.length, (index) {
                                  if (index >= studentNames.length) return const SizedBox();
                                  final id = studentIds[index];
                                  final name = studentNames[index];
                                  final displayName = '$name${_courseSuffix(id)}';
                                  
                                  final isAbsent = absentIds.contains(id);
                                  final transferDate = transferMap[id] != null 
                                      ? (transferMap[id] as Timestamp).toDate() 
                                      : null;

                                  final lineColor = isAbsent ? Colors.grey : AppColors.primary;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6.0),
                                    child: Row(
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            Navigator.pop(context); // ポップアップを閉じる
                                            final isWide = MediaQuery.of(outerContext).size.width >= 600;
                                            if (isWide) {
                                              AdminShell.showOverlay(
                                                outerContext,
                                                StudentDetailScreen(
                                                  studentId: id,
                                                  studentName: name,
                                                  onClose: () => AdminShell.hideOverlay(outerContext),
                                                ),
                                              );
                                            } else {
                                              Navigator.push(outerContext, MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: id, studentName: name)));
                                            }
                                          },
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border(bottom: BorderSide(color: lineColor, width: 1.0)),
                                            ),
                                            child: Text(
                                              displayName, 
                                              style: TextStyle(fontSize: 14, height: 1.1, color: isAbsent ? Colors.grey : AppColors.primary, decoration: isAbsent ? TextDecoration.lineThrough : TextDecoration.none),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isAbsent) _buildStatusBadge('欠席', AppColors.error),
                                        if (transferDate != null) _buildStatusBadge('${DateFormat('M/d').format(transferDate)}振替分', AppColors.primary),
                                      ],
                                    ),
                                  );
                                }),
                                  ...trialStudentNames.map((trialName) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: Text(
                                          '$trialName（体）',
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.1,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildDetailRow(Icons.notes, notes),
                      ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(2), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
  

  void _confirmDelete(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final recurrenceRule = data['recurrenceRule'];
    final recurrenceGroupId = data['recurrenceGroupId'];
    final startTime = (data['startTime'] as Timestamp).toDate();
    
    final isRecurring = (recurrenceRule != null && recurrenceRule.toString().isNotEmpty) || 
                        (recurrenceGroupId != null && recurrenceGroupId.toString().isNotEmpty);
    
    if (isRecurring) {
      _showRecurringDeleteDialog(doc, data, startTime);
    } else {
      _showSimpleDeleteDialog(doc.id);
    }
  }

  void _showSimpleDeleteDialog(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('予定を削除'),
        content: const Text('本当にこの予定を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);
              await _eventsRef.doc(docId).delete();
            },
            child: const Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showRecurringDeleteDialog(DocumentSnapshot doc, Map<String, dynamic> data, DateTime startTime) {
    final recurrenceGroupId = data['recurrenceGroupId'];
    String selectedOption = 'this';
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('定期的な予定の削除'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('この予定'),
                value: 'this',
                groupValue: selectedOption,
                onChanged: (v) => setDialogState(() => selectedOption = v!),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                title: const Text('これ以降のすべての予定'),
                value: 'future',
                groupValue: selectedOption,
                onChanged: (v) => setDialogState(() => selectedOption = v!),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                title: const Text('すべての予定'),
                value: 'all',
                groupValue: selectedOption,
                onChanged: (v) => setDialogState(() => selectedOption = v!),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                await _executeRecurringDelete(doc, data, startTime, selectedOption, recurrenceGroupId);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeRecurringDelete(DocumentSnapshot doc, Map<String, dynamic> data, DateTime startTime, String option, String? recurrenceGroupId) async {
    switch (option) {
      case 'this':
        await doc.reference.delete();
        break;
      case 'future':
        if (recurrenceGroupId != null) {
          final query = await _eventsRef.where('recurrenceGroupId', isEqualTo: recurrenceGroupId).get();
          final batch = FirebaseFirestore.instance.batch();
          for (var eventDoc in query.docs) {
            final eventData = eventDoc.data() as Map<String, dynamic>;
            final eventStart = (eventData['startTime'] as Timestamp).toDate();
            if (!eventStart.isBefore(startTime)) batch.delete(eventDoc.reference);
          }
          await batch.commit();
        } else {
          final recurrenceRule = data['recurrenceRule'] as String?;
          if (recurrenceRule != null) {
            final untilDate = startTime.subtract(const Duration(days: 1));
            final untilStr = '${untilDate.year}${untilDate.month.toString().padLeft(2, '0')}${untilDate.day.toString().padLeft(2, '0')}T235959Z';
            String newRule = recurrenceRule.contains('UNTIL=') ? recurrenceRule.replaceAll(RegExp(r'UNTIL=[^;]+'), 'UNTIL=$untilStr') : '$recurrenceRule;UNTIL=$untilStr';
            await doc.reference.update({'recurrenceRule': newRule});
          }
        }
        break;
      case 'all':
        if (recurrenceGroupId != null) {
          final query = await _eventsRef.where('recurrenceGroupId', isEqualTo: recurrenceGroupId).get();
          final batch = FirebaseFirestore.instance.batch();
          for (var eventDoc in query.docs) batch.delete(eventDoc.reference);
          await batch.commit();
        } else {
          await doc.reference.delete();
        }
        break;
    }
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.colors.textSecondary),
        SizedBox(width: 20),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: context.colors.textPrimary))),
      ],
    );
  }

  void _confirmEdit(DocumentSnapshot doc) {
    // 編集ボタン押下時は確認ダイアログを出さず、直接編集画面を開く。
    // 繰り返し予定の場合、保存時に変更内容に応じてスコープを確認する。
    Navigator.pop(context);
    final bool showSidebar = MediaQuery.of(context).size.width >= AppBreakpoints.desktop;
    if (showSidebar) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: context.colors.dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: SizedBox(
            width: 500,
            height: MediaQuery.of(context).size.height * 0.85,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AddEventDialog(appointment: doc),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: AddEventDialog(appointment: doc),
          ),
        ),
      );
    }
  }

  Widget _buildDetailList(IconData icon, List<String> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.colors.textSecondary),
        SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(item, style: TextStyle(fontSize: 14, color: context.colors.textPrimary)),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _DataSource extends CalendarDataSource {
  _DataSource(List<Appointment> source) {
    appointments = source;
  }
}