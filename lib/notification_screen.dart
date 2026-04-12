import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

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
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: const Text('お知らせ'),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        foregroundColor: context.colors.textPrimary,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: StreamBuilder<QuerySnapshot>(
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
            return Center(
              child: Text(
                'お知らせはありません',
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

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openEditScreen(doc),
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
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: context.colors.iconMuted, size: 20),
                              onPressed: () => _deleteNotification(doc.id),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 16, color: context.colors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              dateStr,
                              style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.groups_outlined, size: 16, color: context.colors.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '対象: $targetStr',
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data['body'] ?? data['detail'] ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.colors.textPrimary, fontSize: 14, height: 1.5),
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
        ),
      ),
      // ★修正: イベント画面と同じFABデザイン
      floatingActionButton: FloatingActionButton(
        heroTag: null, 
        onPressed: () => _openEditScreen(null),
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
                backgroundColor: AppColors.accent,
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
                    activeColor: AppColors.accent,
                    onChanged: (val) => setState(() => _targetType = val!),
                  ),
                  const Text('全体へ配信'),
                  const SizedBox(width: 24),
                  Radio<String>(
                    value: 'specific',
                    groupValue: _targetType,
                    activeColor: AppColors.accent,
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
                    color: context.colors.cardBg,
                    border: Border.all(color: context.colors.borderMedium),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isLoadingClassrooms
                      ? const Center(child: CircularProgressIndicator())
                      : _classroomOptions.isEmpty
                          ? Text('教室データがありません', style: TextStyle(color: context.colors.textSecondary))
                          : Column(
                              children: _classroomOptions.map((roomName) {
                                return CheckboxListTile(
                                  value: _selectedClassrooms.contains(roomName),
                                  title: Text(roomName),
                                  activeColor: AppColors.accent,
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