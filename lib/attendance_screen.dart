import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'app_theme.dart';
import 'widgets/app_feedback.dart';

class AttendanceScreen extends StatefulWidget {
  final String classroom;
  
  const AttendanceScreen({
    super.key,
    required this.classroom,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    // 1分ごとに時刻を更新
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.chipBg,
      appBar: AppBar(
        backgroundColor: context.colors.cardBg,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset(
          'assets/logo_beesmiley.png',
          height: 36,
          errorBuilder: (_, __, ___) => const Text(
            'Bee Smiley',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: AppTextSize.xl,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                DateFormat('HH:mm').format(_currentTime),
                style: TextStyle(
                  fontSize: AppTextSize.headline,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final now = _currentTime;
    final today = DateTime(now.year, now.month, now.day);
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('calendar_events')
          .where('classroom', isEqualTo: widget.classroom)
          .snapshots(),
      builder: (context, eventSnapshot) {
        if (!eventSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // 今日の未退室の入室記録を取得
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('attendance')
              .where('classroom', isEqualTo: widget.classroom)
              .where('date', isEqualTo: Timestamp.fromDate(today))
              .where('exitedAt', isNull: true)
              .snapshots(),
          builder: (context, attendanceSnapshot) {
            // 未退室の生徒がいるレッスンIDを取得
            final Set<String> lessonsWithActiveStudents = {};
            if (attendanceSnapshot.hasData) {
              for (var doc in attendanceSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final lessonId = data['lessonId'] as String?;
                if (lessonId != null) {
                  lessonsWithActiveStudents.add(lessonId);
                }
              }
            }

            // 表示するレッスンを抽出
            final events = eventSnapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final startTime = (data['startTime'] as Timestamp).toDate();
              final endTime = (data['endTime'] as Timestamp).toDate();
              
              // レッスン開始10分前〜終了10分後
              final displayStart = startTime.subtract(const Duration(minutes: 10));
              final displayEnd = endTime.add(const Duration(minutes: 10));
              
              final isInTimeRange = now.isAfter(displayStart) && now.isBefore(displayEnd);
              
              // 時間内、または未退室の生徒がいる場合は表示
              final hasActiveStudents = lessonsWithActiveStudents.contains(doc.id);
              
              return isInTimeRange || hasActiveStudents;
            }).toList();

            // 開始時刻でソート（早い順）
            events.sort((a, b) {
              final aStart = ((a.data() as Map<String, dynamic>)['startTime'] as Timestamp).toDate();
              final bStart = ((b.data() as Map<String, dynamic>)['startTime'] as Timestamp).toDate();
              return aStart.compareTo(bStart);
            });

            if (events.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_busy, size: 80, color: context.colors.iconMuted),
                    const SizedBox(height: 24),
                    Text(
                      '現在レッスンはありません',
                      style: TextStyle(
                        fontSize: AppTextSize.headline,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('yyyy年M月d日 (E)', 'ja').format(now),
                      style: TextStyle(
                        fontSize: AppTextSize.titleLg,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              );
            }

            // 複数レッスンがある場合は全て表示
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                final data = event.data() as Map<String, dynamic>;
                final endTime = (data['endTime'] as Timestamp).toDate();
                final isExpired = now.isAfter(endTime.add(const Duration(minutes: 10)));
                
                return _buildLessonCard(event, isExpired: isExpired);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLessonCard(DocumentSnapshot event, {bool isExpired = false}) {
    final data = event.data() as Map<String, dynamic>;
    final lessonName = data['subject'] ?? '(レッスン名なし)';
    final startTime = (data['startTime'] as Timestamp).toDate();
    final endTime = (data['endTime'] as Timestamp).toDate();
    final studentIds = List<String>.from(data['studentIds'] ?? []);
    final studentNames = List<String>.from(data['studentNames'] ?? []);

    if (studentIds.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                lessonName,
                style: const TextStyle(fontSize: AppTextSize.xl, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}',
                style: TextStyle(fontSize: AppTextSize.titleSm, color: context.colors.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                '生徒が登録されていません',
                style: TextStyle(color: context.colors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isExpired ? context.colors.chipBg : context.colors.cardBg,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // レッスン情報ヘッダー
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isExpired ? Colors.grey : AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lessonName,
                    style: const TextStyle(
                      fontSize: AppTextSize.titleLg,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}',
                  style: TextStyle(
                    fontSize: AppTextSize.titleSm,
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isExpired) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.accent.shade300),
                    ),
                    child: Text(
                      '未退室あり',
                      style: TextStyle(
                        fontSize: AppTextSize.small,
                        color: AppColors.accent.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            
            // 生徒グリッド
            _buildStudentGrid(event.id, lessonName, studentIds, studentNames),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentGrid(
    String lessonId,
    String lessonName,
    List<String> studentIds,
    List<String> studentNames,
  ) {
    final today = DateTime(_currentTime.year, _currentTime.month, _currentTime.day);
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .where('lessonId', isEqualTo: lessonId)
          .where('date', isEqualTo: Timestamp.fromDate(today))
          .snapshots(),
      builder: (context, attendanceSnapshot) {
        // 入室済みの生徒IDを取得
        final Map<String, DocumentSnapshot> attendanceMap = {};
        if (attendanceSnapshot.hasData) {
          for (var doc in attendanceSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final studentId = data['studentId'] as String;
            attendanceMap[studentId] = doc;
          }
        }

        return FutureBuilder<Map<String, String>>(
          future: _getStudentKanaNames(studentIds),
          builder: (context, kanaSnapshot) {
            final kanaMap = kanaSnapshot.data ?? {};
            
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                childAspectRatio: 1.4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: studentIds.length,
              itemBuilder: (context, index) {
                final studentId = studentIds[index];
                final studentName = index < studentNames.length ? studentNames[index] : '不明';
                final studentKana = kanaMap[studentId] ?? '';
                final attendanceDoc = attendanceMap[studentId];
                
                return _buildStudentTile(
                  lessonId: lessonId,
                  lessonName: lessonName,
                  studentId: studentId,
                  studentName: studentName,
                  studentKana: studentKana,
                  attendanceDoc: attendanceDoc,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>> _getStudentKanaNames(List<String> studentIds) async {
    final Map<String, String> kanaMap = {};
    
    debugPrint('=== Getting kana names ===');
    debugPrint('studentIds: $studentIds');
    
    try {
      // families（通常）と plus_families（プラス）両方からふりがなマップを構築
      final allFamilies = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final coll in const ['families', 'plus_families']) {
        final s = await FirebaseFirestore.instance.collection(coll).get();
        allFamilies.addAll(s.docs);
      }

      for (var familyDoc in allFamilies) {
        final familyData = familyDoc.data();
        if (familyData['_compat'] == true) continue;
        final children = List<Map<String, dynamic>>.from(familyData['children'] ?? []);
        final lastNameKana = familyData['lastNameKana'] ?? '';
        final familyUid = familyData['uid'] ?? familyDoc.id;
        
        debugPrint('Family: uid=$familyUid, lastNameKana=$lastNameKana');
        
        for (var child in children) {
          // studentIdは "familyUid_firstName" 形式
          final childId = '${familyUid}_${child['firstName']}';
          final firstNameKana = child['firstNameKana'] ?? '';
          
          debugPrint('  Child: id=$childId, firstNameKana=$firstNameKana');
          
          if (studentIds.contains(childId)) {
            kanaMap[childId] = '$lastNameKana $firstNameKana'.trim();
            debugPrint('  -> MATCHED! kana=${kanaMap[childId]}');
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting kana names: $e');
    }
    
    debugPrint('Final kanaMap: $kanaMap');
    return kanaMap;
  }

  Widget _buildStudentTile({
    required String lessonId,
    required String lessonName,
    required String studentId,
    required String studentName,
    required String studentKana,
    DocumentSnapshot? attendanceDoc,
  }) {
    final bool isEntered = attendanceDoc != null;
    final bool isExited = isEntered && 
        (attendanceDoc!.data() as Map<String, dynamic>)['exitedAt'] != null;
    
    String? enteredTime;
    String? exitedTime;
    
    if (isEntered) {
      final data = attendanceDoc!.data() as Map<String, dynamic>;
      final enteredAt = (data['enteredAt'] as Timestamp).toDate();
      enteredTime = DateFormat('HH:mm').format(enteredAt);
      
      if (isExited) {
        final exitedAt = (data['exitedAt'] as Timestamp).toDate();
        exitedTime = DateFormat('HH:mm').format(exitedAt);
      }
    }

    Color backgroundColor;
    Color textColor;
    IconData? statusIcon;
    String statusText;
    
    if (isExited) {
      backgroundColor = context.colors.borderMedium;
      textColor = context.colors.textSecondary;
      statusIcon = Icons.logout;
      statusText = '退室 $exitedTime';
    } else if (isEntered) {
      backgroundColor = AppColors.successBg;
      textColor = AppColors.successDark;
      statusIcon = Icons.check_circle;
      statusText = '入室 $enteredTime';
    } else {
      backgroundColor = context.colors.cardBg;
      textColor = AppColors.textMain;
      statusIcon = null;
      statusText = '';
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      elevation: isEntered && !isExited ? 3 : 1,
      child: InkWell(
        onTap: () => _handleTap(
          lessonId: lessonId,
          lessonName: lessonName,
          studentId: studentId,
          studentName: studentName,
          attendanceDoc: attendanceDoc,
        ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEntered && !isExited 
                  ? AppColors.successBorder 
                  : context.colors.borderMedium,
              width: isEntered && !isExited ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (studentKana.isNotEmpty)
                Text(
                  studentKana,
                  style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: textColor.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                studentName,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (statusIcon != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(statusIcon, size: 12, color: textColor),
                    const SizedBox(width: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap({
    required String lessonId,
    required String lessonName,
    required String studentId,
    required String studentName,
    DocumentSnapshot? attendanceDoc,
  }) async {
    final today = DateTime(_currentTime.year, _currentTime.month, _currentTime.day);
    
    // familyUidを取得（studentIdは "familyUid_firstName" 形式）
    final parts = studentId.split('_');
    final familyUid = parts.isNotEmpty ? parts[0] : '';
    
    if (attendanceDoc == null) {
      // 入室処理
      await _confirmAndExecute(
        title: '入室確認',
        message: '$studentName さんの入室を記録しますか？',
        onConfirm: () async {
          await FirebaseFirestore.instance.collection('attendance').add({
            'studentId': studentId,
            'studentName': studentName,
            'classroom': widget.classroom,
            'lessonId': lessonId,
            'lessonName': lessonName,
            'enteredAt': Timestamp.now(),
            'exitedAt': null,
            'date': Timestamp.fromDate(today),
            'familyUid': familyUid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          
          // 親への通知送信
          await _sendNotificationToParent(
            familyUid: familyUid,
            studentName: studentName,
            type: 'enter',
            lessonName: lessonName,
          );
          
          if (mounted) {
            _showSuccessSnackBar('$studentName さんが入室しました');
          }
        },
      );
    } else {
      final data = attendanceDoc.data() as Map<String, dynamic>;
      final isExited = data['exitedAt'] != null;
      
      if (isExited) {
        // すでに退室済み - 再入室確認
        await _confirmAndExecute(
          title: '再入室確認',
          message: '$studentName さんは既に退室済みです。\n再入室を記録しますか？',
          onConfirm: () async {
            // 新しい入室レコードを作成
            await FirebaseFirestore.instance.collection('attendance').add({
              'studentId': studentId,
              'studentName': studentName,
              'classroom': widget.classroom,
              'lessonId': lessonId,
              'lessonName': lessonName,
              'enteredAt': Timestamp.now(),
              'exitedAt': null,
              'date': Timestamp.fromDate(today),
              'familyUid': familyUid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            
            await _sendNotificationToParent(
              familyUid: familyUid,
              studentName: studentName,
              type: 'enter',
              lessonName: lessonName,
            );
            
            if (mounted) {
              _showSuccessSnackBar('$studentName さんが再入室しました');
            }
          },
        );
      } else {
        // 退室処理
        await _confirmAndExecute(
          title: '退室確認',
          message: '$studentName さんの退室を記録しますか？',
          onConfirm: () async {
            await attendanceDoc.reference.update({
              'exitedAt': Timestamp.now(),
            });
            
            await _sendNotificationToParent(
              familyUid: familyUid,
              studentName: studentName,
              type: 'exit',
              lessonName: lessonName,
            );
            
            if (mounted) {
              _showSuccessSnackBar('$studentName さんが退室しました');
            }
          },
        );
      }
    }
  }

  Future<void> _confirmAndExecute({
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final result = await AppFeedback.confirm(
      context,
      title: title,
      message: message,
      confirmLabel: 'OK',
    );

    if (result) {
      await onConfirm();
    }
  }

  Future<void> _sendNotificationToParent({
    required String familyUid,
    required String studentName,
    required String type,
    required String lessonName,
  }) async {
    try {
      // 親のFCMトークンを families / plus_families 両方から検索
      QuerySnapshot<Map<String, dynamic>>? familyDoc;
      for (final coll in const ['families', 'plus_families']) {
        final q = await FirebaseFirestore.instance
            .collection(coll)
            .where('uid', isEqualTo: familyUid)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          familyDoc = q;
          break;
        }
      }

      if (familyDoc == null || familyDoc.docs.isEmpty) return;
      
      final familyData = familyDoc.docs.first.data();
      final fcmTokens = List<String>.from(familyData['fcmTokens'] ?? []);
      
      if (fcmTokens.isEmpty) return;
      
      final now = DateTime.now();
      final timeStr = DateFormat('HH:mm').format(now);
      
      String title;
      String body;
      
      if (type == 'enter') {
        title = '入室のお知らせ';
        body = '$studentName さんが $timeStr に入室しました（$lessonName）';
      } else {
        title = '退室のお知らせ';
        body = '$studentName さんが $timeStr に退室しました（$lessonName）';
      }
      
      // 通知をnotificationsコレクションに保存（Cloud Functionsで処理）
      await FirebaseFirestore.instance.collection('attendance_notifications').add({
        'familyUid': familyUid,
        'fcmTokens': fcmTokens,
        'title': title,
        'body': body,
        'type': type,
        'studentName': studentName,
        'lessonName': lessonName,
        'classroom': widget.classroom,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontSize: AppTextSize.titleSm)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// 教室選択画面（タブレット起動時に最初に表示）
class AttendanceClassroomSelectScreen extends StatelessWidget {
  const AttendanceClassroomSelectScreen({super.key});

  static const List<String> _classrooms = [
    'ビースマイリー湘南藤沢',
    'ビースマイリー湘南台',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.chipBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo_beesmiley.png',
              height: 80,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school,
                size: 80,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '入退室管理',
              style: TextStyle(
                fontSize: AppTextSize.hero,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '教室を選択してください',
              style: TextStyle(
                fontSize: AppTextSize.titleSm,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 48),
            ..._classrooms.map((classroom) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: 300,
                height: 60,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceScreen(classroom: classroom),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    classroom,
                    style: const TextStyle(
                      fontSize: AppTextSize.titleLg,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}