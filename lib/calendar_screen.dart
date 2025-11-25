import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_event_screen.dart';
import 'student_detail_screen.dart'; // ★追加: 生徒詳細画面をインポート

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarView _calendarView = CalendarView.month;
  final CalendarController _controller = CalendarController();
  final CalendarController _miniCalendarController = CalendarController();
  
  String _headerText = '';
  
  String _myUid = '';
  List<String> _myClassrooms = [];
  
  bool _isLocaleInitialized = false;
  bool _isLoadingStaffInfo = true;

  bool _showMySchedule = true;
  final Map<String, bool> _classroomFilters = {};

  final CollectionReference _eventsRef =
      FirebaseFirestore.instance.collection('calendar_events');
  final CollectionReference _transfersRef =
      FirebaseFirestore.instance.collection('transfers');

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await initializeDateFormatting('ja');
    
    if (mounted) {
      setState(() {
        _isLocaleInitialized = true;
        _headerText = DateFormat('yyyy年 M月', 'ja').format(DateTime.now());
      });
    }

    await _fetchStaffInfo();
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
      _headerText = DateFormat('yyyy年 M月', 'ja').format(date);
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
        titleSpacing: 24,
        title: Row(
          children: [
            OutlinedButton(
              onPressed: _goToToday,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                foregroundColor: Colors.black87,
              ),
              child: const Text('今日'),
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.black54),
              onPressed: () => _controller.backward!(),
              splashRadius: 20,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.black54),
              onPressed: () => _controller.forward!(),
              splashRadius: 20,
            ),
            const SizedBox(width: 16),
            Text(
              _headerText,
              style: const TextStyle(
                color: Colors.black87, fontSize: 22, fontWeight: FontWeight.w400,
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
      ),
      body: StreamBuilder<QuerySnapshot>(
              stream: _eventsRef.snapshots(),
              builder: (context, snapshot) {
                List<Appointment> appointments = [];
                
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final String? eventClassroom = data['classroom']; 
                    final List<dynamic> staffIds = data['staffIds'] ?? []; 

                    bool isVisible = false;

                    if (_showMySchedule) {
                      if (staffIds.contains(_myUid)) {
                        isVisible = true;
                      }
                    }

                    if (!isVisible && eventClassroom != null) {
                      if (_classroomFilters.containsKey(eventClassroom) && _classroomFilters[eventClassroom] == true) {
                        isVisible = true;
                      }
                    }
                    
                    if (data['classroom'] == null && data['staffIds'] == null) {
                       isVisible = true; 
                    }

                    if (isVisible) {
                      appointments.add(Appointment(
                        id: doc,
                        startTime: (data['startTime'] as Timestamp).toDate(),
                        endTime: (data['endTime'] as Timestamp).toDate(),
                        subject: data['subject'] ?? '(件名なし)',
                        notes: data['notes'],
                        color: Color(data['color'] ?? Colors.blue.value),
                        recurrenceRule: data['recurrenceRule'], 
                      ));
                    }
                  }
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 256,
                      padding: const EdgeInsets.only(top: 16, left: 12, right: 12),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 270,
                            child: SfCalendarTheme(
                              data: SfCalendarThemeData(
                                backgroundColor: Colors.transparent,
                                headerTextStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              child: SfCalendar(
                                controller: _miniCalendarController,
                                view: CalendarView.month,
                                headerDateFormat: 'yyyy年 MM月', 
                                backgroundColor: Colors.transparent,
                                cellBorderColor: Colors.transparent,
                                headerHeight: 40,
                                viewHeaderHeight: 30,
                                headerStyle: const CalendarHeaderStyle(
                                  textStyle: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold),
                                  backgroundColor: Colors.transparent,
                                ),
                                todayHighlightColor: const Color(0xFF1976D2),
                                selectionDecoration: BoxDecoration(
                                  color: Colors.transparent, 
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF1976D2), width: 2),
                                ),
                                monthViewSettings: const MonthViewSettings(
                                  numberOfWeeksInView: 6,
                                  appointmentDisplayMode: MonthAppointmentDisplayMode.none,
                                  monthCellStyle: MonthCellStyle(
                                    textStyle: TextStyle(fontSize: 12, color: Colors.black87),
                                    todayBackgroundColor: Colors.transparent,
                                    todayTextStyle: TextStyle(
                                      fontSize: 12, 
                                      color: Color(0xFF1976D2), 
                                      fontWeight: FontWeight.bold
                                    ),
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
                                _buildFilterCheckbox(
                                  '自分',
                                  _showMySchedule,
                                  (val) => setState(() => _showMySchedule = val),
                                  Colors.orange,
                                ),
                                if (_myClassrooms.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 32, top: 4),
                                    child: Text('担当教室なし', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  )
                                else
                                  ..._myClassrooms.map((roomName) {
                                    return _buildFilterCheckbox(
                                      roomName,
                                      _classroomFilters[roomName] ?? true,
                                      (val) => setState(() => _classroomFilters[roomName] = val),
                                      Colors.blue, 
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      child: SfCalendarTheme(
                        data: SfCalendarThemeData(
                          selectionBorderColor: Colors.transparent,
                          todayHighlightColor: const Color(0xFF1976D2),
                        ),
                        child: SfCalendar(
                          view: _calendarView,
                          controller: _controller,
                          firstDayOfWeek: 1,
                          dataSource: _DataSource(appointments),
                          onTap: calendarTapped,
                          onViewChanged: _onViewChanged,
                          backgroundColor: Colors.white,
                          cellBorderColor: Colors.grey.shade200,
                          headerHeight: 0,
                          selectionDecoration: const BoxDecoration(color: Colors.transparent),
                          viewHeaderStyle: const ViewHeaderStyle(
                            dayTextStyle: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold),
                            dateTextStyle: TextStyle(fontSize: 20, color: Colors.black87, fontWeight: FontWeight.w400),
                          ),
                          monthViewSettings: const MonthViewSettings(
                            appointmentDisplayMode: MonthAppointmentDisplayMode.appointment,
                            appointmentDisplayCount: 4,
                            showAgenda: false,
                            monthCellStyle: MonthCellStyle(
                              textStyle: TextStyle(fontSize: 12, color: Colors.black87),
                              todayBackgroundColor: Colors.transparent, 
                              todayTextStyle: TextStyle(fontSize: 12, color: Color(0xFF1976D2), fontWeight: FontWeight.bold),
                            ),
                          ),
                          timeSlotViewSettings: const TimeSlotViewSettings(
                            timeIntervalHeight: 60,
                            timeFormat: 'H:mm',
                            timeTextStyle: TextStyle(color: Colors.black54, fontSize: 11),
                            dateFormat: 'd',
                            dayFormat: 'EEE',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
            ),
      
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventDialog(),
        backgroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/logo_beesmileymark.png',
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.add, color: Colors.blue),
          ),
        ),
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
      onSelected: (CalendarView value) {
        setState(() {
          _calendarView = value;
          _controller.view = value;
        });
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem(value: CalendarView.day, child: Text('日')),
        const PopupMenuItem(value: CalendarView.week, child: Text('週')),
        const PopupMenuItem(value: CalendarView.month, child: Text('月')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down, color: Colors.black54, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCheckbox(String title, bool value, Function(bool) onChanged, Color color) {
    return InkWell(
      onTap: () => onChanged(!value),
      splashColor: color.withOpacity(0.1),
      hoverColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                activeColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                side: BorderSide(color: color, width: 2),
                onChanged: (val) => onChanged(val!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
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
      final Appointment meeting = details.appointments![0];
      _showRichAppointmentDetail(meeting.id as DocumentSnapshot);
    }
  }

  Future<void> _showAddEventDialog({DateTime? initialDate}) async {
    await showDialog(
      context: context,
      builder: (context) => AddEventDialog(initialStartDate: initialDate),
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
            
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final subject = data['subject'] ?? '(件名なし)';
            final start = (data['startTime'] as Timestamp).toDate();
            final end = (data['endTime'] as Timestamp).toDate();
            final notes = data['notes'] ?? '';
            final classroom = data['classroom'] ?? '指定なし';
            final color = Color(data['color'] ?? Colors.blue.value);
            
            final studentIds = List<String>.from(data['studentIds'] ?? []);
            final studentNames = List<String>.from(data['studentNames'] ?? []);
            final staffNames = List<String>.from(data['staffNames'] ?? []);
            
            final absentIds = List<String>.from(data['absentStudentIds'] ?? []);
            final transferMap = data['studentTransferDates'] as Map<String, dynamic>? ?? {};

            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              content: Container(
                width: 450,
                constraints: const BoxConstraints(maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ヘッダー
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              Navigator.pop(context);
                              await showDialog(
                                context: context,
                                builder: (context) => AddEventDialog(appointment: doc),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(doc.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  width: 16, height: 16,
                                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(subject, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

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
                              // ★修正: 生徒名をクリック可能に
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.face, size: 20, color: Colors.black54),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: List.generate(studentIds.length, (index) {
                                        if (index >= studentNames.length) return const SizedBox();
                                        final id = studentIds[index];
                                        final name = studentNames[index];
                                        final isAbsent = absentIds.contains(id);
                                        final transferDate = transferMap[id] != null 
                                            ? (transferMap[id] as Timestamp).toDate() 
                                            : null;

                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 6.0),
                                          child: Row(
                                            children: [
                                              // ★InkWellでラップしてクリック可能に
                                              InkWell(
                                                onTap: () {
                                                  // 生徒詳細画面へ遷移
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => StudentDetailScreen(
                                                        studentId: id,
                                                        studentName: name,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: isAbsent ? Colors.grey : Colors.blue, // リンクっぽく青色に
                                                    decoration: isAbsent 
                                                        ? TextDecoration.lineThrough 
                                                        : TextDecoration.underline, // 下線を追加
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              
                                              if (isAbsent)
                                                _buildStatusBadge('欠席', Colors.red),
                                              if (transferDate != null)
                                                _buildStatusBadge('${DateFormat('M/d').format(transferDate)}振替分', Colors.blue),
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
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
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
            onPressed: () async {
              Navigator.pop(ctx); 
              Navigator.pop(context); 
              await _eventsRef.doc(docId).delete();
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.black54),
        const SizedBox(width: 20),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87))),
      ],
    );
  }

  Widget _buildDetailList(IconData icon, List<String> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.black54),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(item, style: const TextStyle(fontSize: 14, color: Colors.black87)),
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