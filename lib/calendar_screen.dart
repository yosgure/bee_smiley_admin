import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_event_screen.dart';

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

  final CollectionReference _eventsRef =
      FirebaseFirestore.instance.collection('calendar_events');

  final Map<String, bool> _calendarFilters = {
    '幼児クラス': true,
    '児童発達支援': true,
    'スタッフ': true,
    '行事': true,
  };

  final Map<String, Color> _calendarColors = {
    '幼児クラス': const Color(0xFF039BE5),
    '児童発達支援': const Color(0xFFF4511E),
    'スタッフ': const Color(0xFF8E24AA),
    '行事': const Color(0xFF33B679),
  };

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ja');
    _updateHeaderText(DateTime.now());
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
            appointments = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Appointment(
                id: doc.id,
                startTime: (data['startTime'] as Timestamp).toDate(),
                endTime: (data['endTime'] as Timestamp).toDate(),
                subject: data['subject'] ?? '',
                notes: data['notes'],
                color: Color(data['color'] ?? Colors.blue.value),
              );
            }).toList();
          }

          final filteredAppointments = appointments.where((app) {
            if (app.color.value == _calendarColors['幼児クラス']!.value) return _calendarFilters['幼児クラス']!;
            if (app.color.value == _calendarColors['児童発達支援']!.value) return _calendarFilters['児童発達支援']!;
            if (app.color.value == _calendarColors['スタッフ']!.value) return _calendarFilters['スタッフ']!;
            if (app.color.value == _calendarColors['行事']!.value) return _calendarFilters['行事']!;
            return true;
          }).toList();

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 256,
                padding: const EdgeInsets.only(top: 16, left: 12, right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 240,
                      child: SfCalendarTheme(
                        data: SfCalendarThemeData(
                          backgroundColor: Colors.transparent,
                          headerTextStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        child: SfCalendar(
                          controller: _miniCalendarController,
                          view: CalendarView.month,
                          backgroundColor: Colors.transparent,
                          cellBorderColor: Colors.transparent,
                          headerHeight: 30,
                          viewHeaderHeight: 30,
                          headerStyle: const CalendarHeaderStyle(
                            textStyle: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.bold),
                            backgroundColor: Colors.transparent,
                          ),
                          todayHighlightColor: const Color(0xFF1976D2),
                          selectionDecoration: BoxDecoration(
                            color: const Color(0xFFE8F0FE),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF1976D2), width: 1),
                          ),
                          monthViewSettings: const MonthViewSettings(
                            numberOfWeeksInView: 6,
                            appointmentDisplayMode: MonthAppointmentDisplayMode.none,
                            monthCellStyle: MonthCellStyle(
                              textStyle: TextStyle(fontSize: 12, color: Colors.black87),
                              todayTextStyle: TextStyle(fontSize: 12, color: Colors.white),
                              todayBackgroundColor: Color(0xFF1976D2),
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
                          _buildSidebarHeader('マイカレンダー'),
                          ..._calendarFilters.keys.map((key) {
                            return _buildCalendarFilterCheckbox(key);
                          }),
                          const SizedBox(height: 24),
                          _buildSidebarHeader('その他のカレンダー'),
                          _buildCalendarFilterCheckbox('日本の祝日', color: const Color(0xFF0B8043)),
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
                    dataSource: _DataSource(filteredAppointments),
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
                      startHour: 7,
                      endHour: 20,
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
      
      // ★ここが修正点：ロゴ画像を表示するボタン
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddEventScreen(),
        backgroundColor: Colors.white, // 背景を白に
        elevation: 4,
        shape: const CircleBorder(), // まん丸に
        child: Padding(
          padding: const EdgeInsets.all(8.0), // 余白調整
          child: Image.asset('assets/logo_beesmileymark.png'), // 画像を表示
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

  Widget _buildSidebarHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
          const Spacer(),
          const Icon(Icons.keyboard_arrow_up, size: 20, color: Colors.black54),
        ],
      ),
    );
  }

  Widget _buildCalendarFilterCheckbox(String key, {Color? color}) {
    final isChecked = _calendarFilters[key] ?? true;
    final displayColor = color ?? _calendarColors[key] ?? Colors.grey;

    return InkWell(
      onTap: () {
        setState(() {
          if (_calendarFilters.containsKey(key)) {
            _calendarFilters[key] = !isChecked;
            // StreamBuilderが再ビルドされるのでsetStateだけでOK
          }
        });
      },
      splashColor: displayColor.withOpacity(0.1),
      hoverColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Transform.scale(
              scale: 0.9,
              child: Checkbox(
                value: isChecked,
                activeColor: displayColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                side: BorderSide(color: displayColor, width: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (bool? value) {
                  setState(() {
                    if (_calendarFilters.containsKey(key)) {
                      _calendarFilters[key] = value!;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                key,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                overflow: TextOverflow.ellipsis,
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
        _openAddEventScreen(initialDate: details.date);
      }
    } else if (details.appointments != null && details.appointments!.isNotEmpty) {
      _controller.selectedDate = null;
      final Appointment meeting = details.appointments![0];
      _showAppointmentDetail(meeting);
    }
  }

  Future<void> _openAddEventScreen({DateTime? initialDate}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEventScreen(initialStartDate: initialDate),
      ),
    );

    if (result != null && result is Appointment) {
      await _eventsRef.add({
        'startTime': result.startTime,
        'endTime': result.endTime,
        'subject': result.subject,
        'notes': result.notes,
        'color': result.color.value,
      });
    }
  }

  void _showAppointmentDetail(Appointment meeting) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(color: meeting.color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(meeting.subject)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('日時:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${DateFormat('M/d HH:mm').format(meeting.startTime)} - ${DateFormat('HH:mm').format(meeting.endTime)}'),
              const SizedBox(height: 16),
              if (meeting.notes != null && meeting.notes!.isNotEmpty) ...[
                const Text('詳細:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(meeting.notes!),
              ],
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.edit, color: Colors.blue),
              label: const Text('編集', style: TextStyle(color: Colors.blue)),
              onPressed: () async {
                Navigator.of(context).pop(); 
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AddEventScreen(appointment: meeting),
                  ),
                );
                if (result != null && result is Appointment) {
                  await _eventsRef.doc(meeting.id as String).update({
                    'startTime': result.startTime,
                    'endTime': result.endTime,
                    'subject': result.subject,
                    'notes': result.notes,
                    'color': result.color.value,
                  });
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text('削除', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _eventsRef.doc(meeting.id as String).delete();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('予定を削除しました')),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }
}

class _DataSource extends CalendarDataSource {
  _DataSource(List<Appointment> source) {
    appointments = source;
  }
}