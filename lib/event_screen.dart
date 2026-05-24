import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'app_theme.dart';
import 'widgets/app_feedback.dart';
import 'time_list_picker.dart';

// イベントの時間帯（同日複数部対応）
class _Session {
  TimeOfDay? start;
  TimeOfDay? end;
  _Session({this.start, this.end});
}

// sessions[] を "10:00〜11:00 / 12:00〜13:00" 形式に整形
// 旧 startTime/endTime フィールドのフォールバック対応
String _formatSessions(Map<String, dynamic> event) {
  final dynamic raw = event['sessions'];
  if (raw is List && raw.isNotEmpty) {
    final parts = <String>[];
    for (final s in raw) {
      if (s is Map) {
        final st = (s['start'] ?? '').toString();
        final en = (s['end'] ?? '').toString();
        if (st.isEmpty && en.isEmpty) continue;
        parts.add('${st.isNotEmpty ? '$st〜' : ''}${en.isNotEmpty ? en : ''}');
      }
    }
    if (parts.isNotEmpty) return parts.join(' / ');
  }
  // 旧スキーマ
  final String startTime = (event['startTime'] ?? '').toString();
  final String endTime = (event['endTime'] ?? '').toString();
  if (startTime.isEmpty && endTime.isEmpty) return '';
  return '${startTime.isNotEmpty ? '$startTime〜' : ''}${endTime.isNotEmpty ? endTime : ''}';
}

// 日付範囲を "yyyy年MM月dd日" or "yyyy年MM月dd日 〜 MM月dd日" 形式に
String _formatDateRange(Timestamp? startTs, Timestamp? endTs) {
  if (startTs == null) return '日程未定';
  final start = startTs.toDate();
  if (endTs == null) {
    return DateFormat('yyyy年MM月dd日').format(start);
  }
  final end = endTs.toDate();
  final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
  if (sameDay) return DateFormat('yyyy年MM月dd日').format(start);
  return '${DateFormat('yyyy年MM月dd日').format(start)} 〜 ${DateFormat('MM月dd日').format(end)}';
}

class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CollectionReference _eventsRef =
      FirebaseFirestore.instance.collection('events');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _launchURL(BuildContext context, String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (context.mounted) {
        AppFeedback.info(context, 'リンクを開けませんでした');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('イベント'),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.colors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '公開中'),
            Tab(text: '終了分 (アーカイブ)'),
          ],
        ),
      ),
      backgroundColor: context.colors.scaffoldBg,

      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: StreamBuilder<QuerySnapshot>(
            stream: _eventsRef.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('エラーが発生しました'));
              }

              final allDocs = snapshot.data!.docs;
              final now = DateTime.now();

              final activeEvents = <DocumentSnapshot>[];
              final pastEvents = <DocumentSnapshot>[];

              for (var doc in allDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final Timestamp? deadlineTs = data['deadline'];
                final DateTime deadline = (deadlineTs?.toDate() ?? DateTime(2100)).add(const Duration(days: 1)).subtract(const Duration(seconds: 1));

                if (deadline.isAfter(now)) {
                  activeEvents.add(doc);
                } else {
                  pastEvents.add(doc);
                }
              }

              return TabBarView(
                controller: _tabController,
                children: [
                  _buildEventList(activeEvents, true),
                  _buildEventList(pastEvents, false),
                ],
              );
            },
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EventCreateScreen()),
          );
        },
        backgroundColor: context.colors.cardBg,
        elevation: 4,
        shape: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/logo_beesmileymark.png'),
        ),
      ),
    );
  }

  Widget _buildEventList(List<DocumentSnapshot> docs, bool isActive) {
    if (docs.isEmpty) {
      return Center(
        child: Text(
          isActive ? '現在公開中のイベントはありません' : '過去のイベントはありません',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        return _buildEventCard(doc.id, data, isActive);
      },
    );
  }

  Widget _buildEventCard(String docId, Map<String, dynamic> event, bool isActive) {
    final Timestamp? eventDateTs = event['eventDate'];
    final Timestamp? endDateTs = event['endDate'];
    final Timestamp? deadlineTs = event['deadline'];
    final Timestamp? publishAtTs = event['publishAt'];

    final dateStr = _formatDateRange(eventDateTs, endDateTs);
    final sessionsStr = _formatSessions(event);
    final eventDateTimeStr = sessionsStr.isEmpty ? dateStr : '$dateStr $sessionsStr';

    final String deadlineStr = deadlineTs != null
        ? DateFormat('MM/dd').format(deadlineTs.toDate())
        : '-';

    final bool isScheduled = publishAtTs != null && publishAtTs.toDate().isAfter(DateTime.now());
    final String publishStr = publishAtTs != null
        ? DateFormat('MM/dd HH:mm').format(publishAtTs.toDate())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isActive ? context.colors.cardBg : context.colors.chipBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
        boxShadow: isActive ? [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 画像部分
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              width: double.infinity,
              color: context.colors.inputFill,
              child: event['imageUrl'] != null && (event['imageUrl'] as String).isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: event['imageUrl'],
                      fit: BoxFit.cover,
                      color: isActive ? null : Colors.grey.withOpacity(0.5),
                      colorBlendMode: isActive ? null : BlendMode.saturation,
                      placeholder: (context, url) => Container(color: context.colors.borderLight),
                      errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                    )
                  : Container(
                      color: context.colors.borderLight,
                      child: Center(
                        child: Icon(Icons.event, size: 50, color: context.colors.iconMuted),
                      ),
                    ),
            ),
          ),

          // コンテンツ部分
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タイトル行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        event['title'] ?? '名称未設定',
                        style: TextStyle(
                          fontSize: AppTextSize.titleLg,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: context.colors.iconMuted, size: 20),
                      tooltip: '編集',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventCreateScreen(docId: docId, initialData: event),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(Icons.copy_outlined, color: context.colors.iconMuted, size: 20),
                      tooltip: '複製して新規作成',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventCreateScreen(initialData: event),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: context.colors.iconMuted, size: 20),
                      tooltip: '削除',
                      onPressed: () => _deleteEvent(docId, event['title']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 公開予約バッジ
                if (isScheduled) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, size: 14, color: AppColors.accent.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '公開予約: $publishStr',
                          style: TextStyle(
                            fontSize: AppTextSize.small,
                            color: AppColors.accent.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // 日程
                _buildInfoRow(Icons.calendar_today, eventDateTimeStr),

                // 締め切り
                if (deadlineTs != null && isActive) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: context.colors.textTertiary),
                        const SizedBox(width: 6),
                        Text(
                          '申込締切: $deadlineStr まで',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: AppTextSize.small,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 場所
                const SizedBox(height: 8),
                _buildInfoRow(Icons.place, event['location'] ?? ''),
                if ((event['address'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 26, top: 2),
                    child: Text(
                      event['address'],
                      style: TextStyle(color: context.colors.textTertiary, fontSize: AppTextSize.small),
                    ),
                  ),

                const SizedBox(height: 16),
                Divider(color: context.colors.borderLight),
                const SizedBox(height: 12),

                // 詳細
                Text(
                  event['detail'] ?? '',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    height: 1.6,
                    fontSize: AppTextSize.bodyMd,
                  ),
                ),

                const SizedBox(height: 20),

                // 申し込みボタン
                if ((event['link'] ?? '').isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isActive ? () => _launchURL(context, event['link']) : null,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('申し込みページへ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        disabledBackgroundColor: context.colors.borderLight,
                        disabledForegroundColor: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppTextSize.bodyMd,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  void _deleteEvent(String docId, String? title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('$title を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              await _eventsRef.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ============================================
// イベント作成/編集/複製画面
// docId が指定されていれば編集モード
// initialData のみ指定されていれば複製モード（新規作成として保存）
// どちらも指定なしなら新規作成
// ============================================
class EventCreateScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? initialData;

  const EventCreateScreen({super.key, this.docId, this.initialData});

  @override
  State<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends State<EventCreateScreen> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _detailController = TextEditingController();
  final _linkController = TextEditingController();

  late DateTime _eventDate;
  DateTime? _endDate; // null = 単日
  late DateTime _deadlineDate;
  DateTime? _publishAt; // null = 即公開

  // 時間帯リスト（同日複数部対応）
  final List<_Session> _sessions = [];

  Uint8List? _imageBytes;
  String? _existingImageUrl;
  bool _isUploading = false;

  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    if (init != null) {
      _titleController.text = (init['title'] ?? '').toString();
      _locationController.text = (init['location'] ?? '').toString();
      _addressController.text = (init['address'] ?? '').toString();
      _detailController.text = (init['detail'] ?? '').toString();
      _linkController.text = (init['link'] ?? '').toString();

      _eventDate = (init['eventDate'] is Timestamp)
          ? (init['eventDate'] as Timestamp).toDate()
          : DateTime.now().add(const Duration(days: 7));
      _endDate = (init['endDate'] is Timestamp) ? (init['endDate'] as Timestamp).toDate() : null;
      _deadlineDate = (init['deadline'] is Timestamp)
          ? (init['deadline'] as Timestamp).toDate()
          : _eventDate.subtract(const Duration(days: 1));
      _publishAt = (init['publishAt'] is Timestamp) ? (init['publishAt'] as Timestamp).toDate() : null;

      // sessions[] 読み込み（旧 startTime/endTime からのフォールバック付き）
      final dynamic rawSessions = init['sessions'];
      if (rawSessions is List && rawSessions.isNotEmpty) {
        for (final s in rawSessions) {
          if (s is Map) {
            _sessions.add(_Session(
              start: _parseTimeOfDay(s['start']?.toString()),
              end: _parseTimeOfDay(s['end']?.toString()),
            ));
          }
        }
      } else {
        final st = _parseTimeOfDay(init['startTime']?.toString());
        final en = _parseTimeOfDay(init['endTime']?.toString());
        if (st != null || en != null) {
          _sessions.add(_Session(start: st, end: en));
        }
      }

      // 編集モードでのみ既存画像URLを引き継ぐ（複製ではコピーしない）
      if (_isEdit) {
        _existingImageUrl = (init['imageUrl'] as String?)?.isNotEmpty == true
            ? init['imageUrl'] as String
            : null;
      }
    } else {
      _eventDate = DateTime.now().add(const Duration(days: 7));
      _deadlineDate = DateTime.now().add(const Duration(days: 6));
    }

    if (_sessions.isEmpty) {
      _sessions.add(_Session(
        start: const TimeOfDay(hour: 10, minute: 0),
        end: const TimeOfDay(hour: 11, minute: 0),
      ));
    }
  }

  // "10:00" "10:00 AM" "午前10時" 等を寛容にパース
  TimeOfDay? _parseTimeOfDay(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'(\d{1,2})[:時](\d{2})').firstMatch(raw);
    if (m == null) return null;
    int h = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    if (raw.contains('PM') && h < 12) h += 12;
    if (raw.contains('AM') && h == 12) h = 0;
    if (raw.contains('午後') && h < 12) h += 12;
    if (raw.contains('午前') && h == 12) h = 0;
    if (h < 0 || h > 23 || mm < 0 || mm > 59) return null;
    return TimeOfDay(hour: h, minute: mm);
  }

  String _fmtTime(TimeOfDay? t) {
    if (t == null) return '';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<Uint8List> _compressImage(Uint8List bytes) async {
    final original = img.decodeImage(bytes);
    if (original == null) return bytes;
    const int targetSize = 500 * 1024;
    if (bytes.length <= targetSize) return bytes;
    img.Image resized;
    if (original.width > original.height) {
      resized = original.width > 1200 ? img.copyResize(original, width: 1200) : original;
    } else {
      resized = original.height > 1200 ? img.copyResize(original, height: 1200) : original;
    }
    for (int quality = 85; quality >= 30; quality -= 10) {
      final compressed = img.encodeJpg(resized, quality: quality);
      if (compressed.length <= targetSize) {
        return Uint8List.fromList(compressed);
      }
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 30));
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final compressed = await _compressImage(bytes);
      setState(() {
        _imageBytes = compressed;
      });
    }
  }

  Future<void> _pickDate({required DateTime initial, required ValueChanged<DateTime> onPicked, DateTime? firstDate}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ja', 'JP'),
    );
    if (picked != null) onPicked(picked);
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) async {
    return await showTimeListPicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
  }

  Future<void> _pickPublishAt() async {
    final initial = _publishAt ?? DateTime.now().add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ja', 'JP'),
    );
    if (pickedDate == null) return;
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return;
    setState(() {
      _publishAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_titleController.text.isEmpty) {
      AppFeedback.info(context, 'イベント名を入力してください');
      return;
    }
    final effectiveEnd = _endDate ?? _eventDate;
    if (effectiveEnd.isBefore(DateTime(_eventDate.year, _eventDate.month, _eventDate.day))) {
      AppFeedback.info(context, '終了日は開始日以降に設定してください');
      return;
    }
    if (_deadlineDate.isAfter(_eventDate)) {
      AppFeedback.info(context, '締め切り日はイベント開始日より前に設定してください');
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? imageUrl = _existingImageUrl;

      if (_imageBytes != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('event_photos')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

        await storageRef.putData(
          _imageBytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        imageUrl = await storageRef.getDownloadURL();
      }

      final sessionsData = _sessions
          .where((s) => s.start != null || s.end != null)
          .map((s) => {
                'start': _fmtTime(s.start),
                'end': _fmtTime(s.end),
              })
          .toList();

      final data = <String, dynamic>{
        'title': _titleController.text,
        'eventDate': Timestamp.fromDate(_eventDate),
        'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
        'sessions': sessionsData,
        // 後方互換: 1件目を旧フィールドにも書き込む（古い表示コードのため）
        'startTime': sessionsData.isNotEmpty ? sessionsData.first['start'] : '',
        'endTime': sessionsData.isNotEmpty ? sessionsData.first['end'] : '',
        'deadline': Timestamp.fromDate(_deadlineDate),
        'publishAt': _publishAt != null ? Timestamp.fromDate(_publishAt!) : null,
        'location': _locationController.text,
        'address': _addressController.text,
        'detail': _detailController.text,
        'link': _linkController.text,
        'imageUrl': imageUrl,
      };

      final col = FirebaseFirestore.instance.collection('events');
      if (_isEdit) {
        data['updatedAt'] = FieldValue.serverTimestamp();
        await col.doc(widget.docId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await col.add(data);
      }

      if (mounted) {
        Navigator.pop(context);
        AppFeedback.info(context, _isEdit ? 'イベントを更新しました' : 'イベントを公開しました');
      }
    } catch (e) {
      AppFeedback.info(context, 'エラー: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'イベント編集' : '新規イベント'),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
            child: ElevatedButton(
              onPressed: _isUploading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_isEdit ? '保存' : '公開', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // カバー写真
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: context.colors.inputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.borderMedium),
                      image: _imageBytes != null
                          ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover)
                          : (_existingImageUrl != null
                              ? DecorationImage(image: NetworkImage(_existingImageUrl!), fit: BoxFit.cover)
                              : null),
                    ),
                    child: (_imageBytes == null && _existingImageUrl == null)
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, size: 36, color: context.colors.iconMuted),
                              const SizedBox(height: 8),
                              Text(
                                'カバー写真を追加',
                                style: TextStyle(color: context.colors.textTertiary, fontSize: AppTextSize.bodyMd),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 24),

                _buildLabel('イベント名'),
                _buildTextField(_titleController, '例：秋の収穫体験'),

                _buildLabel('開始日'),
                _buildDatePicker(
                  date: _eventDate,
                  onTap: () => _pickDate(
                    initial: _eventDate,
                    onPicked: (d) => setState(() => _eventDate = d),
                  ),
                ),

                _buildLabel('終了日（複数日にまたがる場合のみ）'),
                _endDate == null
                    ? OutlinedButton.icon(
                        onPressed: () => setState(() => _endDate = _eventDate.add(const Duration(days: 1))),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('終了日を追加'),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _buildDatePicker(
                              date: _endDate!,
                              onTap: () => _pickDate(
                                initial: _endDate!,
                                firstDate: _eventDate,
                                onPicked: (d) => setState(() => _endDate = d),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: context.colors.iconMuted),
                            tooltip: '終了日を削除',
                            onPressed: () => setState(() => _endDate = null),
                          ),
                        ],
                      ),

                _buildLabel('時間帯'),
                ..._sessions.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTimePicker(
                            time: s.start,
                            label: '開始',
                            onTap: () async {
                              final t = await _pickTime(s.start);
                              if (t != null) setState(() => s.start = t);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('〜'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildTimePicker(
                            time: s.end,
                            label: '終了',
                            onTap: () async {
                              final t = await _pickTime(s.end);
                              if (t != null) setState(() => s.end = t);
                            },
                          ),
                        ),
                        if (_sessions.length > 1)
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline, color: context.colors.iconMuted),
                            tooltip: 'この時間帯を削除',
                            onPressed: () => setState(() => _sessions.removeAt(i)),
                          ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _sessions.add(_Session(
                          start: const TimeOfDay(hour: 12, minute: 0),
                          end: const TimeOfDay(hour: 13, minute: 0),
                        ))),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('時間帯を追加'),
                  ),
                ),

                _buildLabel('申し込み締め切り'),
                _buildDatePicker(
                  date: _deadlineDate,
                  onTap: () => _pickDate(
                    initial: _deadlineDate,
                    onPicked: (d) => setState(() => _deadlineDate = d),
                  ),
                  isDeadline: true,
                ),

                _buildLabel('公開時間（任意）'),
                _publishAt == null
                    ? OutlinedButton.icon(
                        onPressed: _pickPublishAt,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('公開予約を設定'),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _pickPublishAt,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: context.colors.inputFill,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.schedule, size: 18, color: AppColors.accent.shade700),
                                    const SizedBox(width: 10),
                                    Text(
                                      DateFormat('yyyy年 MM月 dd日 (E) HH:mm', 'ja').format(_publishAt!),
                                      style: const TextStyle(
                                        fontSize: AppTextSize.bodyMd,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: context.colors.iconMuted),
                            tooltip: '公開予約を解除（即公開）',
                            onPressed: () => setState(() => _publishAt = null),
                          ),
                        ],
                      ),

                _buildLabel('場所名'),
                _buildTextField(_locationController, '例：近所の農園'),

                _buildLabel('住所'),
                _buildTextField(_addressController, '例：藤沢市...'),

                _buildLabel('詳細'),
                _buildTextField(_detailController, 'イベントの内容や持ち物などを入力...', maxLines: 5),

                _buildLabel('申し込みリンク'),
                _buildTextField(_linkController, 'https://...'),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
          fontSize: AppTextSize.body,
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: context.colors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          hintStyle: TextStyle(color: context.colors.textHint, fontSize: AppTextSize.bodyMd),
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required DateTime date,
    required VoidCallback onTap,
    bool isDeadline = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: context.colors.inputFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month,
              size: 18,
              color: isDeadline ? AppColors.error : AppColors.primary,
            ),
            const SizedBox(width: 10),
            Text(
              DateFormat('yyyy年 MM月 dd日 (E)', 'ja').format(date),
              style: TextStyle(
                fontSize: AppTextSize.bodyMd,
                fontWeight: FontWeight.w500,
                color: isDeadline ? AppColors.error : context.colors.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_drop_down, color: context.colors.iconMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker({
    TimeOfDay? time,
    required VoidCallback onTap,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.inputFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              time != null ? _fmtTime(time) : label,
              style: TextStyle(
                fontSize: AppTextSize.bodyMd,
                fontWeight: FontWeight.w500,
                color: time != null ? context.colors.textPrimary : context.colors.textHint,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_drop_down, color: context.colors.iconMuted),
          ],
        ),
      ),
    );
  }
}
