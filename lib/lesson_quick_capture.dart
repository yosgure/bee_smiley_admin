import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

// レッスン枠の開始時刻（plus_schedule_screen の _timeSlots と一致させる）
// slot 0: 9:30〜11:00, 1: 11:00〜12:30, 2: 14:00〜15:30, 3: 15:30〜17:00
const List<Duration> _slotStarts = [
  Duration(hours: 9, minutes: 30),
  Duration(hours: 11, minutes: 0),
  Duration(hours: 14, minutes: 0),
  Duration(hours: 15, minutes: 30),
];
const Duration _slotDuration = Duration(minutes: 90);

const List<String> _slotLabels = ['9:30〜', '11:00〜', '14:00〜', '15:30〜'];

/// 現在時刻が属するレッスンスロット index を返す（時間外なら null）。
/// plus_lessons 用のスロット判定。calendar_events は startTime/endTime で個別判定するため使わない。
int? currentSlotIndex([DateTime? now]) {
  final n = now ?? DateTime.now();
  final t = Duration(hours: n.hour, minutes: n.minute);
  for (int i = 0; i < _slotStarts.length; i++) {
    final start = _slotStarts[i];
    final end = start + _slotDuration;
    if (t >= start && t < end) return i;
  }
  return null;
}

String slotLabel(int slotIndex) =>
    (slotIndex >= 0 && slotIndex < _slotLabels.length) ? _slotLabels[slotIndex] : '';

/// 現在時刻ラベル（セクション見出し用）
String currentLessonLabel(DateTime now) {
  final slot = currentSlotIndex(now);
  if (slot != null) return slotLabel(slot);
  return DateFormat('HH:mm').format(now);
}

/// 現在進行中のレッスンで、自分が担当する生徒一覧を返す。
/// 通常レッスン（calendar_events: startTime/endTime/staffNames/studentIds 等）と
/// プラスレッスン（plus_lessons: slotIndex/teachers/studentName）の両方を照合する。
/// allStudents は assessment_screen の _allStudents と同形式
/// ({id, name, kana, classroom, classrooms}) を想定。
Future<List<Map<String, dynamic>>> fetchCurrentLessonStudents({
  required List<Map<String, dynamic>> allStudents,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return [];

  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final myNames = await _resolveMyStaffNames(user.uid);
  String norm(String s) => s.replaceAll(RegExp(r'[\s　]'), '');
  final myNamesNorm = myNames.map(norm).toSet();
  if (myNamesNorm.isEmpty) {
    debugPrint('[QuickCapture] 自分のスタッフ名が解決できませんでした (uid=${user.uid})');
  }

  final byName = <String, Map<String, dynamic>>{};
  final byId = <String, Map<String, dynamic>>{};
  for (final s in allStudents) {
    byName[norm(s['name'] as String? ?? '')] = s;
    final id = s['id'] as String?;
    if (id != null) byId[id] = s;
  }

  final result = <Map<String, dynamic>>[];
  final seen = <String>{};
  void addStudent(Map<String, dynamic>? s) {
    if (s == null) return;
    final id = s['id'] as String?;
    if (id == null) return;
    if (seen.add(id)) result.add(s);
  }

  // ---- 1) 通常レッスン (calendar_events) ----
  try {
    final evSnap = await FirebaseFirestore.instance
        .collection('calendar_events')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('startTime', isLessThan: Timestamp.fromDate(dayEnd))
        .get();
    int evMatched = 0;
    for (final doc in evSnap.docs) {
      final data = doc.data();
      final startTs = data['startTime'] as Timestamp?;
      final endTs = data['endTime'] as Timestamp?;
      if (startTs == null || endTs == null) continue;
      final start = startTs.toDate();
      final end = endTs.toDate();
      if (now.isBefore(start) || !now.isBefore(end)) continue; // 進行中のみ
      final staffNames = (data['staffNames'] as List?)?.cast<dynamic>() ?? [];
      final mine = staffNames.any((s) => myNamesNorm.contains(norm(s.toString())));
      if (!mine) continue;
      evMatched++;
      // studentIds 優先 → なければ studentNames で名前一致
      final studentIds =
          (data['studentIds'] as List?)?.cast<dynamic>() ?? [];
      final studentNames =
          (data['studentNames'] as List?)?.cast<dynamic>() ?? [];
      // 欠席除外
      final absentIds =
          (data['absentStudentIds'] as List?)?.cast<dynamic>().map((e) => e.toString()).toSet() ?? <String>{};
      if (studentIds.isNotEmpty) {
        for (final raw in studentIds) {
          final sid = raw.toString();
          if (absentIds.contains(sid)) continue;
          addStudent(byId[sid]);
        }
      } else {
        for (final raw in studentNames) {
          addStudent(byName[norm(raw.toString())]);
        }
      }
    }
    debugPrint(
        '[QuickCapture] calendar_events 進行中=$evMatched / 取得=${evSnap.docs.length}');
  } catch (e) {
    debugPrint('[QuickCapture] calendar_events 取得エラー: $e');
  }

  // ---- 2) プラスレッスン (plus_lessons) ----
  final slot = currentSlotIndex(now);
  if (slot != null) {
    try {
      final pSnap = await FirebaseFirestore.instance
          .collection('plus_lessons')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('date', isLessThan: Timestamp.fromDate(dayEnd))
          .where('slotIndex', isEqualTo: slot)
          .get();
      int pMatched = 0;
      for (final doc in pSnap.docs) {
        final data = doc.data();
        final teachers = (data['teachers'] as List?)?.cast<dynamic>() ?? [];
        final mine =
            teachers.any((t) => myNamesNorm.contains(norm(t.toString())));
        if (!mine) continue;
        pMatched++;
        final sn = data['studentName'] as String? ?? '';
        if (sn.isEmpty) continue;
        addStudent(byName[norm(sn)]);
      }
      debugPrint('[QuickCapture] plus_lessons slot=$slot 担当=$pMatched / 取得=${pSnap.docs.length}');
    } catch (e) {
      debugPrint('[QuickCapture] plus_lessons 取得エラー: $e');
    }
  }

  result.sort((a, b) =>
      (a['kana'] as String? ?? '').compareTo(b['kana'] as String? ?? ''));
  debugPrint(
      '[QuickCapture] 該当生徒=${result.length} 件 (myNames=${myNamesNorm.toList()})');
  return result;
}

Future<Set<String>> _resolveMyStaffNames(String uid) async {
  final names = <String>{};
  try {
    final snap = await FirebaseFirestore.instance
        .collection('staffs')
        .where('uid', isEqualTo: uid)
        .get();
    for (final d in snap.docs) {
      final data = d.data();
      final n = data['name'] as String?;
      if (n != null && n.isNotEmpty) names.add(n);
      // 旧データ互換: 苗字/名前が分かれている場合
      final last = data['lastName'] as String?;
      final first = data['firstName'] as String?;
      if (last != null && first != null) {
        names.add('$last $first');
        names.add('$last$first');
      }
    }
  } catch (_) {}
  return names;
}

/// 撮影 → 圧縮アップロード → 該当生徒の今週分の下書きアセスメントに追記。
/// 戻り値: 成功した枚数（キャンセル/失敗は 0）
Future<int> quickCapturePhoto({
  required BuildContext context,
  required String studentId,
  required String studentName,
}) async {
  // context を async gap 越しに使わないよう、先に messenger を取得
  // ignore: use_build_context_synchronously
  final messenger = ScaffoldMessenger.of(context);
  final picker = ImagePicker();
  final XFile? file = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 90,
  );
  if (file == null) return 0;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('$studentName の写真を保存中…')),
        ],
      ),
      duration: const Duration(seconds: 20),
    ),
  );

  try {
    final bytes = await file.readAsBytes();
    final compressed = await _compressImage(bytes);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    final ref =
        FirebaseStorage.instance.ref().child('assessment_photos/$fileName');
    await ref.putData(
        compressed, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await _appendPhotoToWeeklyDraft(
      studentId: studentId,
      studentName: studentName,
      photoUrl: url,
    );

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$studentName の下書きに写真を追加しました'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return 1;
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('保存エラー: $e')),
    );
    return 0;
  }
}

Future<Uint8List> _compressImage(Uint8List bytes) async {
  try {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;
    const int maxDimension = 1200;
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        image = img.copyResize(image, width: maxDimension);
      } else {
        image = img.copyResize(image, height: maxDimension);
      }
    }
    final compressed = img.encodeJpg(image, quality: 80);
    return Uint8List.fromList(compressed);
  } catch (_) {
    return bytes;
  }
}

/// 今週分の下書き週次アセスメントに mediaItems を追記。
/// なければ新規作成。クイック撮影専用エントリ（isQuickDraft: true）に集約。
Future<void> _appendPhotoToWeeklyDraft({
  required String studentId,
  required String studentName,
  required String photoUrl,
}) async {
  final now = DateTime.now();
  // 週の月曜 0:00 〜 翌週月曜 0:00
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final nextMonday = monday.add(const Duration(days: 7));

  final user = FirebaseAuth.instance.currentUser;
  String staffName = '担当スタッフ';
  if (user != null) {
    try {
      final s = await FirebaseFirestore.instance
          .collection('staffs')
          .where('uid', isEqualTo: user.uid)
          .get();
      if (s.docs.isNotEmpty) {
        staffName = s.docs.first.data()['name'] ?? staffName;
      }
    } catch (_) {}
  }

  // 既存の今週分・下書きを検索
  final col = FirebaseFirestore.instance.collection('assessments');
  final snap = await col
      .where('studentId', isEqualTo: studentId)
      .where('type', isEqualTo: 'weekly')
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monday))
      .where('date', isLessThan: Timestamp.fromDate(nextMonday))
      .get();

  // 下書き優先（公開済みは触らない）
  DocumentSnapshot? targetDoc;
  for (final d in snap.docs) {
    final data = d.data();
    if (data['isPublished'] != true) {
      targetDoc = d;
      break;
    }
  }

  final mediaItem = {'type': 'image', 'url': photoUrl};

  if (targetDoc == null) {
    // 新規作成: クイック撮影エントリ1件のみ
    await col.add({
      'studentId': studentId,
      'studentName': studentName,
      'type': 'weekly',
      'date': Timestamp.fromDate(now),
      'staffId': user?.uid,
      'staffName': staffName,
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dateRange': DateFormat('yyyy/MM/dd (E)', 'ja').format(now),
      'entries': [
        {
          'tool': null,
          'rating': null,
          'duration': null,
          'comment': null,
          'photoUrl': photoUrl,
          'mediaItems': [mediaItem],
          'task': '',
          'isQuickDraft': true,
        }
      ],
      'content': '(写真のみ・記録未入力)',
    });
    return;
  }

  // 既存ドキュメントに追記（トランザクションで安全に）
  final ref = targetDoc.reference;
  await FirebaseFirestore.instance.runTransaction((tx) async {
    final fresh = await tx.get(ref);
    final data = fresh.data() as Map<String, dynamic>;
    final entries =
        List<Map<String, dynamic>>.from(data['entries'] as List? ?? []);

    // 既存の isQuickDraft エントリを探す
    int qIdx =
        entries.indexWhere((e) => e['isQuickDraft'] == true);
    if (qIdx >= 0) {
      final media = List<Map<String, dynamic>>.from(
          entries[qIdx]['mediaItems'] as List? ?? []);
      media.add(mediaItem);
      entries[qIdx] = {
        ...entries[qIdx],
        'mediaItems': media,
        'photoUrl': entries[qIdx]['photoUrl'] ?? photoUrl,
      };
    } else {
      entries.add({
        'tool': null,
        'rating': null,
        'duration': null,
        'comment': null,
        'photoUrl': photoUrl,
        'mediaItems': [mediaItem],
        'task': '',
        'isQuickDraft': true,
      });
    }

    tx.update(ref, {
      'entries': entries,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
}
