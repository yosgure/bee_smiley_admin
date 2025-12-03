import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final CollectionReference _notificationsRef =
      FirebaseFirestore.instance.collection('notifications');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('お知らせ'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('エラーが発生しました'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('お知らせはありません'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              DateTime date = DateTime.now();
              if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
                date = (data['createdAt'] as Timestamp).toDate();
              }
              final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(date);

              String targetStr = '全体';
              if (data['target'] == 'specific') {
                final list = List<String>.from(data['targetClassrooms'] ?? []);
                if (list.isNotEmpty) {
                  targetStr = list.join(', ');
                } else {
                  targetStr = '指定なし';
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                child: InkWell(
                  onTap: () => _openEditScreen(doc),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                data['title'] ?? '(タイトルなし)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '対象: $targetStr',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data['body'] ?? data['detail'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('編集'),
                              onPressed: () => _openEditScreen(doc),
                              style: TextButton.styleFrom(foregroundColor: Colors.blue),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('削除'),
                              onPressed: () => _deleteNotification(doc.id),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      // ★修正: イベント画面と同じFABデザイン
      floatingActionButton: FloatingActionButton(
        heroTag: null, 
        onPressed: () => _openEditScreen(null),
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

  Future<void> _deleteNotification(String docId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: const Text('このお知らせを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _notificationsRef.doc(docId).delete();
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openEditScreen(DocumentSnapshot? doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationEditScreen(doc: doc),
        fullscreenDialog: true,
      ),
    );
  }
}

class NotificationEditScreen extends StatefulWidget {
  final DocumentSnapshot? doc;

  const NotificationEditScreen({super.key, required this.doc});

  @override
  State<NotificationEditScreen> createState() => _NotificationEditScreenState();
}

class _NotificationEditScreenState extends State<NotificationEditScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _targetType = 'all';
  final Set<String> _selectedClassrooms = {};

  List<String> _classroomOptions = [];
  bool _isLoadingClassrooms = true;
  bool _isLoadingSave = false;

  @override
  void initState() {
    super.initState();
    _fetchClassrooms();

    if (widget.doc != null) {
      final data = widget.doc!.data() as Map<String, dynamic>;
      _titleController.text = data['title'] ?? '';
      _bodyController.text = data['body'] ?? data['detail'] ?? '';
      _targetType = data['target'] ?? 'all';

      if (_targetType == 'specific') {
        final list = List<String>.from(data['targetClassrooms'] ?? []);
        _selectedClassrooms.addAll(list);
      }
    }
  }

  Future<void> _fetchClassrooms() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('classrooms').get();
      final List<String> list = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('name') && data['name'] != null) {
          list.add(data['name'].toString());
        }
      }

      if (list.isEmpty) {
        list.addAll([
          'ビースマイリー湘南藤沢教室',
          'ビースマイリー湘南台教室',
          'ビースマイリープラス湘南藤沢教室',
        ]);
      }

      if (mounted) {
        setState(() {
          _classroomOptions = list.toSet().toList();
          _isLoadingClassrooms = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching classrooms: $e');
      if (mounted) {
        setState(() {
          _classroomOptions = [
            'ビースマイリー湘南藤沢教室',
            'ビースマイリー湘南台教室',
            'ビースマイリープラス湘南藤沢教室',
          ];
          _isLoadingClassrooms = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('タイトルを入力してください')));
      return;
    }
    if (_targetType == 'specific' && _selectedClassrooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('教室を選択してください')));
      return;
    }

    setState(() => _isLoadingSave = true);

    try {
      final data = {
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'target': _targetType,
        'targetClassrooms': _targetType == 'specific' ? _selectedClassrooms.toList() : [],
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.doc == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('notifications').add(data);
      } else {
        await widget.doc!.reference.update(data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('お知らせを保存しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingSave = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.doc != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'お知らせ編集' : 'お知らせ作成'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: _isLoadingSave ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isLoadingSave
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isEditing ? '更新' : '配信'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('タイトル', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: '例：9月のイベントについて',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),

              const Text('本文', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyController,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'お知らせの内容を入力してください',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 24),

              const Text('配信対象', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Radio<String>(
                    value: 'all',
                    groupValue: _targetType,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _targetType = val!),
                  ),
                  const Text('全体へ配信'),
                  const SizedBox(width: 24),
                  Radio<String>(
                    value: 'specific',
                    groupValue: _targetType,
                    activeColor: Colors.orange,
                    onChanged: (val) => setState(() => _targetType = val!),
                  ),
                  const Text('教室を指定して配信'),
                ],
              ),

              if (_targetType == 'specific') ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isLoadingClassrooms
                      ? const Center(child: CircularProgressIndicator())
                      : _classroomOptions.isEmpty
                          ? const Text('教室データがありません', style: TextStyle(color: Colors.grey))
                          : Column(
                              children: _classroomOptions.map((roomName) {
                                return CheckboxListTile(
                                  value: _selectedClassrooms.contains(roomName),
                                  title: Text(roomName),
                                  activeColor: Colors.orange,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedClassrooms.add(roomName);
                                      } else {
                                        _selectedClassrooms.remove(roomName);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                ),
              ],
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}