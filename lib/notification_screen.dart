import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'app_theme.dart';
import 'main.dart';
import 'widgets/app_feedback.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with SingleTickerProviderStateMixin {
  final CollectionReference _notificationsRef =
      FirebaseFirestore.instance.collection('notifications');
  late TabController _tabController;

  static const int _archiveDays = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

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
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.colors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '公開中'),
            Tab(text: 'アーカイブ'),
          ],
        ),
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

              final allDocs = snapshot.data!.docs;
              final now = DateTime.now();
              final archiveCutoff = now.subtract(const Duration(days: _archiveDays));
              final activeDocs = <DocumentSnapshot>[];
              final archiveDocs = <DocumentSnapshot>[];
              for (final doc in allDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = (data['publishAt'] is Timestamp)
                    ? data['publishAt'] as Timestamp
                    : (data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null);
                final dt = ts?.toDate() ?? now;
                if (dt.isBefore(archiveCutoff)) {
                  archiveDocs.add(doc);
                } else {
                  activeDocs.add(doc);
                }
              }

              return TabBarView(
                controller: _tabController,
                children: [
                  _buildList(activeDocs, true),
                  _buildList(archiveDocs, false),
                ],
              );
            },
          ),
        ),
      ),
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

  Widget _buildList(List<DocumentSnapshot> docs, bool isActive) {
    if (docs.isEmpty) {
      return Center(
        child: Text(
          isActive ? 'お知らせはありません' : 'アーカイブはありません',
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
        return _buildCard(doc, data, isActive);
      },
    );
  }

  Widget _buildCard(DocumentSnapshot doc, Map<String, dynamic> data, bool isActive) {
    final Timestamp? createdAtTs = data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
    final Timestamp? publishAtTs = data['publishAt'] is Timestamp ? data['publishAt'] as Timestamp : null;
    final DateTime displayDate = (publishAtTs ?? createdAtTs)?.toDate() ?? DateTime.now();
    final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(displayDate);
    final bool isScheduled = publishAtTs != null && publishAtTs.toDate().isAfter(DateTime.now());

    String targetStr = '全体';
    if (data['target'] == 'specific') {
      final list = List<String>.from(data['targetClassrooms'] ?? []);
      targetStr = list.isNotEmpty ? list.join(', ') : '指定なし';
    }

    final bool hasAttachment = (data['attachmentUrl'] as String?)?.isNotEmpty == true;

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
                        fontSize: AppTextSize.titleLg,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: context.colors.iconMuted, size: 20),
                    tooltip: '操作',
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openEditScreen(doc);
                      } else if (value == 'duplicate') {
                        _openEditScreen(doc, duplicate: true);
                      } else if (value == 'delete') {
                        _deleteNotification(doc.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('編集'), dense: true)),
                      PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('複製して新規作成'), dense: true)),
                      PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.error), title: Text('削除', style: TextStyle(color: AppColors.error)), dense: true)),
                    ],
                  ),
                ],
              ),
              if (isScheduled) ...[
                const SizedBox(height: 8),
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
                        '公開予約: ${DateFormat('MM/dd HH:mm').format(publishAtTs.toDate())}',
                        style: TextStyle(
                          fontSize: AppTextSize.small,
                          color: AppColors.accent.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: context.colors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    dateStr,
                    style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.body),
                  ),
                  if (hasAttachment) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.attach_file, size: 16, color: context.colors.textSecondary),
                  ],
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
                      style: TextStyle(color: context.colors.textSecondary, fontSize: AppTextSize.body),
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
                style: TextStyle(color: context.colors.textPrimary, fontSize: AppTextSize.bodyMd, height: 1.5),
              ),
            ],
          ),
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
            child: const Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _openEditScreen(DocumentSnapshot? doc, {bool duplicate = false}) {
    AdminShell.showOverlay(
      context,
      NotificationEditScreen(doc: doc, duplicate: duplicate),
    );
  }
}

class NotificationEditScreen extends StatefulWidget {
  final DocumentSnapshot? doc;
  final bool duplicate;

  const NotificationEditScreen({super.key, required this.doc, this.duplicate = false});

  @override
  State<NotificationEditScreen> createState() => _NotificationEditScreenState();
}

class _NotificationEditScreenState extends State<NotificationEditScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _targetType = 'all';
  final Set<String> _selectedClassrooms = {};
  DateTime? _publishAt;

  // 添付ファイル
  String? _attachmentUrl;
  String? _attachmentName;
  // 新規アップロード待ち
  Uint8List? _pendingAttachmentBytes;
  String? _pendingAttachmentName;

  List<String> _classroomOptions = [];
  bool _isLoadingClassrooms = true;
  bool _isLoadingSave = false;

  bool get _isEditing => widget.doc != null && !widget.duplicate;

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

      // 編集モードのみ既存添付・公開予約を引き継ぐ
      if (!widget.duplicate) {
        final pub = data['publishAt'];
        if (pub is Timestamp) _publishAt = pub.toDate();
        _attachmentUrl = data['attachmentUrl'] as String?;
        _attachmentName = data['attachmentName'] as String?;
      }
    }
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
        pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute,
      );
    });
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    setState(() {
      _pendingAttachmentBytes = f.bytes!;
      _pendingAttachmentName = f.name;
    });
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
        list.addAll(['ビースマイリー湘南藤沢教室', 'ビースマイリー湘南台教室']);
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
          _classroomOptions = ['ビースマイリー湘南藤沢教室', 'ビースマイリー湘南台教室'];
          _isLoadingClassrooms = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      AppFeedback.info(context, 'タイトルを入力してください');
      return;
    }
    if (_targetType == 'specific' && _selectedClassrooms.isEmpty) {
      AppFeedback.info(context, '教室を選択してください');
      return;
    }

    setState(() => _isLoadingSave = true);

    try {
      String? attachmentUrl = _attachmentUrl;
      String? attachmentName = _attachmentName;

      // 新規ファイルアップロード
      if (_pendingAttachmentBytes != null && _pendingAttachmentName != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('notification_attachments')
            .child('${DateTime.now().millisecondsSinceEpoch}_$_pendingAttachmentName');
        await storageRef.putData(_pendingAttachmentBytes!);
        attachmentUrl = await storageRef.getDownloadURL();
        attachmentName = _pendingAttachmentName;
      }

      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'target': _targetType,
        'targetClassrooms': _targetType == 'specific' ? _selectedClassrooms.toList() : [],
        'publishAt': _publishAt != null ? Timestamp.fromDate(_publishAt!) : null,
        'attachmentUrl': attachmentUrl,
        'attachmentName': attachmentName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEditing) {
        await widget.doc!.reference.update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('notifications').add(data);
      }

      if (mounted) {
        AdminShell.hideOverlay(context);
        AppFeedback.info(context, 'お知らせを保存しました');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.info(context, 'エラーが発生しました: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoadingSave = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      appBar: AppBar(
        title: Text(_isEditing ? 'お知らせ編集' : 'お知らせ作成'),
        centerTitle: true,
        backgroundColor: context.colors.cardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => AdminShell.hideOverlay(context),
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
                  : Text(_isEditing ? '更新' : '配信'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('タイトル', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm)),
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

                  const Text('本文', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm)),
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
                  const Text('添付ファイル（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm)),
                  const SizedBox(height: 8),
                  _buildAttachmentSection(),

                  const SizedBox(height: 24),
                  const Text('配信対象', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm)),
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

                  const SizedBox(height: 24),
                  const Text('公開時間（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextSize.titleSm)),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentSection() {
    final hasNewFile = _pendingAttachmentName != null;
    final hasExisting = _attachmentUrl != null && _attachmentUrl!.isNotEmpty;

    if (hasNewFile) {
      return Row(
        children: [
          Icon(Icons.insert_drive_file, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(_pendingAttachmentName!, overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: Icon(Icons.close, color: context.colors.iconMuted),
            tooltip: 'キャンセル',
            onPressed: () => setState(() {
              _pendingAttachmentBytes = null;
              _pendingAttachmentName = null;
            }),
          ),
        ],
      );
    }
    if (hasExisting) {
      return Row(
        children: [
          Icon(Icons.insert_drive_file, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(_attachmentName ?? 'ファイル', overflow: TextOverflow.ellipsis)),
          TextButton.icon(
            onPressed: _pickAttachment,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('差し替え'),
          ),
          IconButton(
            icon: Icon(Icons.close, color: context.colors.iconMuted),
            tooltip: '添付を削除',
            onPressed: () => setState(() {
              _attachmentUrl = null;
              _attachmentName = null;
            }),
          ),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: _pickAttachment,
      icon: const Icon(Icons.attach_file, size: 18),
      label: const Text('ファイルを添付'),
    );
  }
}
