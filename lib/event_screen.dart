import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('リンクを開けませんでした')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('イベント'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: '公開中'),
            Tab(text: '終了分 (アーカイブ)'),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF2F2F7),
      
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
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EventCreateScreen()),
          );
        },
        backgroundColor: Colors.white,
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
          style: const TextStyle(color: Colors.grey),
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
    final Timestamp? deadlineTs = event['deadline'];
    final String startTime = event['startTime'] ?? '';
    final String endTime = event['endTime'] ?? '';
    
    String eventDateTimeStr = '';
    if (eventDateTs != null) {
      eventDateTimeStr = DateFormat('yyyy年MM月dd日').format(eventDateTs.toDate());
      if (startTime.isNotEmpty || endTime.isNotEmpty) {
        eventDateTimeStr += ' ${startTime.isNotEmpty ? '$startTime〜' : ''}${endTime.isNotEmpty ? endTime : ''}';
      }
    } else {
      eventDateTimeStr = '日程未定';
    }
        
    final String deadlineStr = deadlineTs != null
        ? DateFormat('MM/dd').format(deadlineTs.toDate())
        : '-';

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isActive ? 3 : 1,
      color: isActive ? Colors.white : Colors.grey.shade200,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              child: event['imageUrl'] != null && (event['imageUrl'] as String).isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: event['imageUrl'],
                      fit: BoxFit.cover,
                      color: isActive ? null : Colors.grey.withOpacity(0.5),
                      colorBlendMode: isActive ? null : BlendMode.saturation,
                      placeholder: (context, url) => Container(color: Colors.grey.shade200),
                      errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                    )
                  : Container(
                      color: Colors.grey.shade300,
                      child: const Center(child: Icon(Icons.event, size: 50, color: Colors.grey)),
                    ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        event['title'] ?? '名称未設定',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      onPressed: () => _deleteEvent(docId, event['title']),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),

                _buildIconText(Icons.calendar_today, eventDateTimeStr),
                
                if (deadlineTs != null && isActive) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const SizedBox(width: 28),
                      Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        '申込締切: $deadlineStr まで',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 6),
                _buildIconText(Icons.place, event['location'] ?? ''),
                if ((event['address'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Text(
                      event['address'],
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                Text(
                  event['detail'] ?? '',
                  style: const TextStyle(color: Colors.black87, height: 1.5),
                ),
                
                const SizedBox(height: 24),

                if ((event['link'] ?? '').isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isActive ? () => _launchURL(context, event['link']) : null,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('申し込みページへ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade50,
                        foregroundColor: Colors.deepOrange,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        disabledBackgroundColor: Colors.grey.shade300,
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

  Widget _buildIconText(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _eventsRef.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class EventCreateScreen extends StatefulWidget {
  const EventCreateScreen({super.key});

  @override
  State<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends State<EventCreateScreen> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _detailController = TextEditingController();
  final _linkController = TextEditingController();
  
  DateTime _eventDate = DateTime.now().add(const Duration(days: 7));
  DateTime _deadlineDate = DateTime.now().add(const Duration(days: 6));
  
  TimeOfDay? _startTime = TimeOfDay.now();
  TimeOfDay? _endTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));

  Uint8List? _imageBytes;
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _pickDate(bool isEventDate) async {
    final initialDate = isEventDate ? _eventDate : _deadlineDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      locale: const Locale('ja', 'JP'),
    );
    if (picked != null) {
      setState(() {
        if (isEventDate) {
          _eventDate = picked;
        } else {
          _deadlineDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStartTime) async {
    final initialTime = isStartTime ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('イベント名を入力してください')));
      return;
    }
    if (_deadlineDate.isAfter(_eventDate)) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('締め切り日はイベント日程より前に設定してください')));
       return;
    }

    setState(() => _isUploading = true);

    try {
      String? imageUrl;
      
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

      await FirebaseFirestore.instance.collection('events').add({
        'title': _titleController.text,
        'eventDate': Timestamp.fromDate(_eventDate),
        'startTime': _startTime?.format(context),
        'endTime': _endTime?.format(context),
        'deadline': Timestamp.fromDate(_deadlineDate),
        'location': _locationController.text,
        'address': _addressController.text,
        'detail': _detailController.text,
        'link': _linkController.text,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('イベントを公開しました')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('新規イベント'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _submit,
            child: _isUploading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('公開', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                  image: _imageBytes != null
                      ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover)
                      : null,
                ),
                child: _imageBytes == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('カバー写真を追加', style: TextStyle(color: Colors.grey)),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            _buildLabel('イベント名'),
            _buildTextField(_titleController, '例：秋の収穫体験'),

            _buildLabel('日程'),
            _buildDatePicker(
              date: _eventDate, 
              onTap: () => _pickDate(true),
            ),
            Row(
              children: [
                Expanded(child: _buildTimePicker(
                  time: _startTime,
                  onTap: () => _pickTime(true),
                  label: '開始時間',
                )),
                const SizedBox(width: 16),
                Expanded(child: _buildTimePicker(
                  time: _endTime,
                  onTap: () => _pickTime(false),
                  label: '終了時間',
                )),
              ],
            ),

            _buildLabel('申し込み締め切り'),
            _buildDatePicker(
              date: _deadlineDate, 
              onTap: () => _pickDate(false),
              isAlert: true,
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
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildDatePicker({required DateTime date, required VoidCallback onTap, bool isAlert = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isAlert ? Border.all(color: Colors.red.shade100) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month, color: isAlert ? Colors.red : Colors.orange),
            const SizedBox(width: 12),
            Text(
              DateFormat('yyyy年 MM月 dd日 (E)', 'ja').format(date),
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: isAlert ? Colors.red : Colors.black87,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker({TimeOfDay? time, required VoidCallback onTap, required String label}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.blueGrey),
            const SizedBox(width: 12),
            Text(
              time != null ? time.format(context) : label,
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: time != null ? Colors.black87 : Colors.grey,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}