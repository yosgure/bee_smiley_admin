import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_event_screen.dart';
import 'student_detail_screen.dart';
import 'app_theme.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // ★追加: ScaffoldKey
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

  // フィルタ
  bool _showMySchedule = true;
  bool _showMyTasks = true;
  final Map<String, bool> _classroomFilters = {};

  final CollectionReference _eventsRef =
      FirebaseFirestore.instance.collection('calendar_events');
  final CollectionReference _tasksRef =
      FirebaseFirestore.instance.collection('tasks');

  static const String _pendingTasksId = 'PENDING_TASKS_SUMMARY';
  static const String _taskNoteMarker = 'TASK';

  @override
  void initState() {
    super.initState();
    // 初期表示を8:00に設定
    final now = DateTime.now();
    _controller.displayDate = DateTime(now.year, now.month, now.day, 8, 0);
    _initData();

    // 安全装置
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
    ]);
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
              _myClassrooms = List<String>.from(data['classrooms'] ?? []);
              for (var room in _myClassrooms) {
                _classroomFilters[room] = true;
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
        }
      });
    }
  }

  void _goToToday() {
    final now = DateTime.now();
    _controller.displayDate = now;
    _miniCalendarController.displayDate = now;
    _updateHeaderText(now);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocaleInitialized || _isLoadingStaffInfo) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('データを読み込んでいます...', style: TextStyle(color: AppColors.textSub)),
            ],
          ),
        ),
      );
    }

    final bool showSidebar = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      // ★追加: keyを設定
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: showSidebar
          ? null
          : Drawer(
              backgroundColor: AppColors.surface,
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
        // PC版AppBar
        ? AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            toolbarHeight: 64,
            titleSpacing: 24, 
            title: Row(
              children: [
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: _goToToday,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: AppStyles.radiusSmall),
                      foregroundColor: AppColors.textMain,
                    ),
                    child: const Text('今日'),
                  ),
                ),
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppColors.textSub),
                  onPressed: () => _controller.backward!(),
                  splashRadius: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppColors.textSub),
                  onPressed: () => _controller.forward!(),
                  splashRadius: 20,
                ),
                const SizedBox(width: 16),
                Text(
                  _headerTextWithYear,
                  style: const TextStyle(
                    color: AppColors.textMain, fontSize: 22, fontWeight: FontWeight.w400,
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
        // スマホ版AppBar - Stackで日週月を絶対中央に
        : AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            toolbarHeight: kToolbarHeight,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: Stack(
              alignment: Alignment.center,
              children: [
                // 中央: 日週月（絶対中央）
                Center(
                  child: _buildSegmentedControl(),
                ),
                // 左右の要素
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左: ハンバーガー + 12月
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.menu, color: AppColors.textMain),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        ),
                        Text(
                          _headerText,
                          style: const TextStyle(
                            color: AppColors.textMain, fontSize: 20, fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    // 右: 今日ボタン
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        onTap: _goToToday,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400, width: 1.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${DateTime.now().day}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textMain,
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
      body: StreamBuilder<QuerySnapshot>(
        stream: _eventsRef.snapshots(),
        builder: (context, eventSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: _tasksRef.where('userId', isEqualTo: _myUid).snapshots(),
            builder: (context, taskSnapshot) {
              
              List<Appointment> appointments = [];
              
              // 1. 予定の処理
              if (eventSnapshot.hasData) {
                for (var doc in eventSnapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String? eventClassroom = data['classroom']; 
                  final List<dynamic> staffIds = data['staffIds'] ?? []; 

                  bool isVisible = false;
                  if (_showMySchedule && staffIds.contains(_myUid)) isVisible = true;
                  if (!isVisible && eventClassroom != null) {
                    if (_classroomFilters.containsKey(eventClassroom) && _classroomFilters[eventClassroom] == true) {
                      isVisible = true;
                    }
                  }
                  if (data['classroom'] == null && data['staffIds'] == null) isVisible = true;

                  if (isVisible) {
                    Color eventColor = Color(data['color'] ?? AppColors.primary.value);
                    if (eventClassroom != null && _classroomColors.containsKey(eventClassroom)) {
                      eventColor = _classroomColors[eventClassroom]!;
                    }

                    appointments.add(Appointment(
                      id: doc, 
                      startTime: (data['startTime'] as Timestamp).toDate(),
                      endTime: (data['endTime'] as Timestamp).toDate(),
                      subject: data['subject'] ?? '(件名なし)',
                      notes: 'EVENT',
                      color: eventColor,
                      recurrenceRule: data['recurrenceRule'],
                    ));
                  }
                }
              }

              // 2. タスクの処理
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

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSidebar)
                    Container(
                      width: 280,
                      padding: const EdgeInsets.only(top: 16, left: 12, right: 12),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                      ),
                      child: _buildSidebarContent(),
                    ),
                  
                  Expanded(
                    child: Stack(
                      children: [
                        SfCalendarTheme(
                          data: SfCalendarThemeData(
                            selectionBorderColor: Colors.transparent,
                            todayHighlightColor: AppColors.primary,
                            cellBorderColor: Colors.grey.shade400,
                          ),
                          child: SfCalendar(
                            view: _calendarView,
                            controller: _controller,
                            firstDayOfWeek: 1,
                            dataSource: _DataSource(appointments),
                            onTap: calendarTapped, 
                            onViewChanged: _onViewChanged,
                            backgroundColor: AppColors.surface,
                            cellBorderColor: Colors.grey.shade400,
                            headerHeight: 0,
                            viewHeaderHeight: 70,
                            allowViewNavigation: false,
                            selectionDecoration: BoxDecoration(
                              color: Colors.transparent,
                              border: Border.all(color: Colors.transparent, width: 0),
                            ),
                            viewHeaderStyle: const ViewHeaderStyle(
                              dayTextStyle: TextStyle(fontSize: 11, color: AppColors.textSub, fontWeight: FontWeight.bold),
                              dateTextStyle: TextStyle(fontSize: 20, color: AppColors.textMain, fontWeight: FontWeight.w400),
                            ),
                            monthViewSettings: const MonthViewSettings(
                              appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                              appointmentDisplayCount: 4,
                              showAgenda: false,
                              monthCellStyle: MonthCellStyle(
                                textStyle: TextStyle(fontSize: 12, color: AppColors.textMain),
                                trailingDatesTextStyle: TextStyle(fontSize: 12, color: AppColors.textSub),
                                leadingDatesTextStyle: TextStyle(fontSize: 12, color: AppColors.textSub),
                                todayBackgroundColor: Colors.transparent, 
                                todayTextStyle: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                            appointmentBuilder: (context, calendarAppointmentDetails) {
                              final Appointment appointment = calendarAppointmentDetails.appointments.first;
                              
                              final bool isPending = appointment.id == _pendingTasksId;
                              final bool isTask = appointment.notes == _taskNoteMarker;
                              
                              final isSmallScreen = MediaQuery.of(context).size.width < 800;

                              if (isPending) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(4),
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
                                          style: const TextStyle(
                                            color: AppColors.error, 
                                            fontSize: 10,
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

                              if (isTask) {
                                final isMonthView = _calendarView == CalendarView.month;
                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary, 
                                    borderRadius: BorderRadius.circular(4),
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
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10, 
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
                              
                              // 通常の予定
                              final isMonthView = _calendarView == CalendarView.month;
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 1),
                                decoration: BoxDecoration(
                                  color: appointment.color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: isMonthView ? Alignment.centerLeft : Alignment.topLeft,
                                padding: isMonthView 
                                  ? const EdgeInsets.symmetric(horizontal: 2)
                                  : const EdgeInsets.only(left: 4, top: 2, right: 2),
                                child: Text(
                                  appointment.subject,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    height: 1.0,
                                  ),
                                  maxLines: isMonthView ? 1 : 3,
                                  overflow: TextOverflow.clip,
                                ),
                              );
                            },
                            timeSlotViewSettings: const TimeSlotViewSettings(
                              timeIntervalHeight: 60,
                              timeFormat: 'H:mm',
                              timeTextStyle: TextStyle(color: AppColors.textSub, fontSize: 11),
                              dateFormat: 'd',
                              dayFormat: 'EEE',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
          );
        },
      ),
      
      floatingActionButton: FloatingActionButton(heroTag: null, 
        onPressed: () => _showAddEventDialog(),
        backgroundColor: AppColors.surface,
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
              viewHeaderStyle: const ViewHeaderStyle(
                dayTextStyle: TextStyle(fontSize: 11, color: AppColors.textSub, fontWeight: FontWeight.w500),
              ),
              headerStyle: const CalendarHeaderStyle(
                textStyle: TextStyle(fontSize: 13, color: AppColors.textMain, fontWeight: FontWeight.bold),
                backgroundColor: Colors.transparent,
              ),
              todayHighlightColor: AppColors.primary,
              selectionDecoration: BoxDecoration(
                color: Colors.transparent, 
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              monthViewSettings: const MonthViewSettings(
                numberOfWeeksInView: 6,
                appointmentDisplayMode: MonthAppointmentDisplayMode.none,
                monthCellStyle: MonthCellStyle(
                  textStyle: TextStyle(fontSize: 12, color: AppColors.textMain),
                  trailingDatesTextStyle: TextStyle(fontSize: 12, color: AppColors.textSub),
                  leadingDatesTextStyle: TextStyle(fontSize: 12, color: AppColors.textSub),
                  todayBackgroundColor: Colors.transparent,
                  todayTextStyle: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
              onTap: (details) {
                if (details.date != null) {
                  _controller.displayDate = details.date!;
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
              _buildFilterCheckbox('マイカレンダー', _showMySchedule, (val) => setState(() => _showMySchedule = val), AppColors.primary),
              _buildFilterCheckbox('マイタスク', _showMyTasks, (val) => setState(() => _showMyTasks = val), AppColors.secondary),
              
              const SizedBox(height: 8),
              if (_myClassrooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 32, top: 4),
                  child: Text('担当教室なし', style: TextStyle(color: AppColors.textSub, fontSize: 12)),
                )
              else
                ..._myClassrooms.map((roomName) {
                  final color = _classroomColors[roomName] ?? AppColors.primary;
                  return _buildFilterCheckbox(
                    roomName,
                    _classroomFilters[roomName] ?? true,
                    (val) => setState(() => _classroomFilters[roomName] = val),
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
              _buildFilterCheckbox('マイカレンダー', _showMySchedule, (val) => setState(() => _showMySchedule = val), AppColors.primary),
              _buildFilterCheckbox('マイタスク', _showMyTasks, (val) => setState(() => _showMyTasks = val), AppColors.secondary),
              
              const SizedBox(height: 8),
              if (_myClassrooms.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 32, top: 4),
                  child: Text('担当教室なし', style: TextStyle(color: AppColors.textSub, fontSize: 12)),
                )
              else
                ..._myClassrooms.map((roomName) {
                  final color = _classroomColors[roomName] ?? AppColors.primary;
                  return _buildFilterCheckbox(
                    roomName,
                    _classroomFilters[roomName] ?? true,
                    (val) => setState(() => _classroomFilters[roomName] = val),
                    color, 
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedControl() {
    final views = [CalendarView.day, CalendarView.week, CalendarView.month];
    final labels = ['日', '週', '月'];
    final selectedIndex = views.indexOf(_calendarView);
    const double buttonWidth = 48.0;
    const double buttonHeight = 32.0;
    const double containerPadding = 3.0;
    
    return Container(
      width: buttonWidth * 3 + containerPadding * 2,
      height: buttonHeight + containerPadding * 2,
      padding: EdgeInsets.all(containerPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: selectedIndex * buttonWidth,
            top: 0,
            child: Container(
              width: buttonWidth,
              height: buttonHeight,
              decoration: BoxDecoration(
                color: Colors.white,
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
            children: List.generate(3, (index) {
              final isSelected = selectedIndex == index;
              return GestureDetector(
                onTap: () => setState(() {
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
                      color: isSelected ? AppColors.textMain : AppColors.textSub,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    String label = '';
    switch (_calendarView) {
      case CalendarView.month: label = '月'; break;
      case CalendarView.week: label = '週'; break;
      case CalendarView.day: label = '日'; break;
      default: label = '週';
    }
    return PopupMenuButton<CalendarView>(
      onSelected: (CalendarView value) => setState(() { _calendarView = value; _controller.view = value; }),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: AppStyles.radiusSmall),
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem(value: CalendarView.day, child: Text('日')),
        const PopupMenuItem(value: CalendarView.week, child: Text('週')),
        const PopupMenuItem(value: CalendarView.month, child: Text('月')),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: AppStyles.radiusSmall,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down, color: AppColors.textSub, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCheckbox(String title, bool value, Function(bool) onChanged, Color color) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: Checkbox(value: value, activeColor: color, onChanged: (val) => onChanged(val!))),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textMain))),
          ],
        ),
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
          _controller.displayDate = details.date!;
        });
      } else {
        _showAddEventDialog(initialDate: details.date);
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
        } else {
          if (target.id is DocumentSnapshot) {
            _showRichAppointmentDetail(target.id as DocumentSnapshot);
          }
        }
      }
    }
  }

  Future<void> _showAddEventDialog({DateTime? initialDate}) async {
    final bool showSidebar = MediaQuery.of(context).size.width >= 800;
    
    if (showSidebar) {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
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
          decoration: const BoxDecoration(
            color: Colors.white,
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
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
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

              final contentHeight = pendingDocs.isEmpty 
                ? 100.0 
                : (pendingDocs.length * 72.0).clamp(100.0, 400.0);

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
                        ? const Center(
                            child: Text(
                              '保留中のタスクはありません',
                              style: TextStyle(color: AppColors.textSub),
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
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat('yyyy/MM/dd').format(date),
                                            style: const TextStyle(fontSize: 13, color: AppColors.error),
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
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: Icon(Icons.edit_outlined, size: 24, color: Colors.grey.shade600),
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
    final bool showSidebar = MediaQuery.of(context).size.width >= 800;
    
    if (showSidebar) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
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
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                    tooltip: '編集',
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDialog(context: context, builder: (_) => AddEventDialog(taskDoc: doc));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                    tooltip: '削除',
                    onPressed: () async { Navigator.pop(ctx); await doc.reference.delete(); },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
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
                      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: AppColors.textSub),
                          const SizedBox(width: 8),
                          Text(DateFormat('yyyy年MM月dd日 (E)', 'ja').format(date), style: const TextStyle(fontSize: 14, color: AppColors.textSub)),
                        ],
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.inputFill, 
                            borderRadius: AppStyles.radiusSmall,
                          ),
                          child: Text(notes, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMain)),
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
    showDialog(
      context: context,
      builder: (context) {
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

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: AppStyles.radius),
              contentPadding: EdgeInsets.zero,
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(subject, 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMain),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                    onPressed: () async {
                      Navigator.pop(context);
                      await showDialog(
                        context: context,
                        builder: (context) => AddEventDialog(appointment: doc),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                    onPressed: () => _confirmDelete(doc.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
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
                      
                      if (studentNames.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.face, size: 20, color: AppColors.textSub),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List.generate(studentIds.length, (index) {
                                  if (index >= studentNames.length) return const SizedBox();
                                  final id = studentIds[index];
                                  final name = studentNames[index];
                                  final displayName = name;
                                  
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
                                            Navigator.push(context, MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: id, studentName: name)));
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
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
  
  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('予定を削除'),
        content: const Text('本当にこの予定を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async { Navigator.pop(ctx); Navigator.pop(context); await _eventsRef.doc(docId).delete(); },
            child: const Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSub),
        const SizedBox(width: 20),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textMain))),
      ],
    );
  }

  Widget _buildDetailList(IconData icon, List<String> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSub),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(item, style: const TextStyle(fontSize: 14, color: AppColors.textMain)),
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