import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// 旧データの英語キーを日本語に変換
String _normalizeCategoryLabel(String raw) {
  const legacy = {
    'care_record': 'ケア記録',
    'support_plan': '支援計画',
    'meeting_note': '会議メモ',
    'other': 'その他',
  };
  return legacy[raw] ?? raw;
}

/// 保存コンテンツ一覧ダイアログを表示
Future<void> showSavedContentsDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => const _SavedContentsDialog(),
  );
}

class _SavedContentsDialog extends StatefulWidget {
  const _SavedContentsDialog();

  @override
  State<_SavedContentsDialog> createState() => _SavedContentsDialogState();
}

class _SavedContentsDialogState extends State<_SavedContentsDialog> {
  String _categoryFilter = 'all';
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final snap = await FirebaseFirestore.instance
        .collection('ai_chat_commands')
        .orderBy('order')
        .get();
    if (mounted) {
      setState(() {
        _categories = snap.docs
            .map((d) => d.data()['label'] as String? ?? '')
            .where((l) => l.isNotEmpty)
            .toList();
        if (!_categories.contains('その他')) {
          _categories.add('その他');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            // ヘッダー
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Text('保存済みコンテンツ',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  // カテゴリフィルター
                  DropdownButton<String>(
                    value: _categoryFilter,
                    underline: const SizedBox(),
                    borderRadius: BorderRadius.circular(8),
                    isDense: true,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('全カテゴリ')),
                      ..._categories.map((label) =>
                          DropdownMenuItem(value: label, child: Text(label))),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _categoryFilter = v);
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // コンテンツ一覧
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    Query query = FirebaseFirestore.instance
        .collection('saved_ai_contents')
        .orderBy('date', descending: true);

    if (_categoryFilter != 'all') {
      query = query.where('category', isEqualTo: _categoryFilter);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('エラー: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined,
                    size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text('保存されたコンテンツがありません',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildCard(String docId, Map<String, dynamic> data) {
    final studentName = data['studentName'] ?? '';
    final recorderName = data['recorderName'] ?? '';
    final date = (data['date'] as Timestamp?)?.toDate();
    final content = data['content'] ?? '';
    final category = _normalizeCategoryLabel(data['category'] ?? '');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showEditDialog(docId, data),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(studentName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(category,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700)),
                  ),
                  const Spacer(),
                  if (date != null)
                    Text(DateFormat('yyyy/MM/dd').format(date),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 4),
              Text(content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text('記録者: $recorderName',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(
      String docId, Map<String, dynamic> data) async {
    final textController =
        TextEditingController(text: data['content'] ?? '');
    final date =
        (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime selectedDate = date;
    final studentName = data['studentName'] ?? '';
    final recorderName = data['recorderName'] ?? '';
    final category = _normalizeCategoryLabel(data['category'] ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ヘッダー
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('$studentName',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(category,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx, null),
                          ),
                        ],
                      ),
                    ),
                    // 情報
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('記録者: $recorderName',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600)),
                              const Spacer(),
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDate,
                                    firstDate: DateTime.now()
                                        .subtract(const Duration(days: 30)),
                                    lastDate: DateTime.now(),
                                    locale: const Locale('ja'),
                                  );
                                  if (picked != null) {
                                    setDialogState(
                                        () => selectedDate = picked);
                                  }
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 14,
                                        color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('yyyy/MM/dd')
                                          .format(selectedDate),
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // テキスト編集
                          SizedBox(
                            height: 300,
                            child: TextField(
                              controller: textController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                              style: const TextStyle(
                                  fontSize: 13, height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // フッターボタン
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red, size: 18),
                            label: const Text('削除',
                                style: TextStyle(color: Colors.red)),
                            onPressed: () => Navigator.pop(ctx, 'delete'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            child: const Text('キャンセル'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, 'save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      textController.dispose();
      return;
    }

    try {
      if (result == 'delete') {
        final confirmDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('削除確認'),
            content: const Text('このコンテンツを削除しますか？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('キャンセル')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white),
                child: const Text('削除'),
              ),
            ],
          ),
        );
        if (confirmDelete == true) {
          await FirebaseFirestore.instance
              .collection('saved_ai_contents')
              .doc(docId)
              .delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('削除しました'),
                  backgroundColor: Colors.orange),
            );
          }
        }
      } else {
        await FirebaseFirestore.instance
            .collection('saved_ai_contents')
            .doc(docId)
            .update({
          'content': textController.text,
          'date': Timestamp.fromDate(DateTime(
              selectedDate.year, selectedDate.month, selectedDate.day)),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('保存しました'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
    textController.dispose();
  }
}
